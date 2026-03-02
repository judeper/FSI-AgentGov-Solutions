#!/usr/bin/env python3
"""Dataverse client for File Upload Security Configurator.

Provides authenticated Dataverse API access with idempotent helpers for
schema, environment variables, and connection reference operations.
Follows the proven CMMClient pattern with FUS_ environment variable prefix.
"""

import json
import os
import sys
import time
from typing import Any, Optional

try:
    import msal
    import requests
    from requests.adapters import HTTPAdapter
    from urllib3.util.retry import Retry
except ImportError:
    print(
        "ERROR: Required packages missing. Install with:\n"
        "  pip install msal requests\n"
        "  -- or --\n"
        "  pip install -r requirements.txt",
        file=sys.stderr,
    )
    sys.exit(1)


class FUSClient:
    """Dataverse REST API client for File Upload Security Configurator."""

    API_VERSION = "v9.2"

    def __init__(
        self,
        tenant_id: str,
        environment_url: str,
        client_id: Optional[str] = None,
        client_secret: Optional[str] = None,
        interactive: bool = False,
        dry_run: bool = False,
    ):
        self.tenant_id = tenant_id
        self.environment_url = environment_url.rstrip("/")
        self.api_url = f"{self.environment_url}/api/data/{self.API_VERSION}"
        self.client_id = client_id
        self.client_secret = client_secret
        self.interactive = interactive
        self.dry_run = dry_run
        self._token: Optional[str] = None
        self._token_expires: float = 0
        self._session = requests.Session()
        retry_strategy = Retry(total=3, backoff_factor=1, status_forcelist=[429, 500, 502, 503, 504])
        adapter = HTTPAdapter(max_retries=retry_strategy)
        self._session.mount("https://", adapter)

    def _get_token(self) -> str:
        """Acquire or refresh OAuth2 token."""
        now = time.time()
        if self._token and now < self._token_expires - 300:
            return self._token

        authority = f"https://login.microsoftonline.com/{self.tenant_id}"
        scope = [f"{self.environment_url}/.default"]

        if self.interactive:
            if not self.client_id:
                raise ValueError(
                    "client_id is required for interactive authentication"
                )
            app = msal.PublicClientApplication(
                self.client_id,
                authority=authority,
            )
            result = app.acquire_token_interactive(scopes=scope)
        else:
            if not self.client_id or not self.client_secret:
                raise ValueError(
                    "client_id and client_secret required for non-interactive auth"
                )
            app = msal.ConfidentialClientApplication(
                self.client_id,
                authority=authority,
                client_credential=self.client_secret,
            )
            result = app.acquire_token_for_client(scopes=scope)

        if "access_token" not in result:
            error = result.get("error_description", result.get("error", "Unknown"))
            raise RuntimeError(f"Token acquisition failed: {error}")

        self._token = result["access_token"]
        self._token_expires = now + result.get("expires_in", 3600)
        return self._token

    def _headers(self) -> dict:
        """Build standard request headers."""
        return {
            "Authorization": f"Bearer {self._get_token()}",
            "Content-Type": "application/json",
            "Accept": "application/json",
            "OData-MaxVersion": "4.0",
            "OData-Version": "4.0",
        }

    def _request(
        self, method: str, url: str, data: Optional[dict] = None, **kwargs
    ) -> requests.Response:
        """Make authenticated request with error handling."""
        headers = self._headers()
        response = self._session.request(
            method, url, headers=headers,
            json=data if data else None, **kwargs,
        )
        if response.status_code >= 400:
            msg = f"{method} {url} returned {response.status_code}"
            try:
                detail = response.json()
                if "error" in detail:
                    msg += f": {detail['error'].get('message', '')}"
            except Exception:
                msg += f": {response.text[:500]}"
            raise RuntimeError(msg)
        return response

    # ── High-Level Helpers ──────────────────────────────────────────

    def test_connection(self) -> dict:
        """Validate Dataverse connectivity."""
        r = self._request("GET", f"{self.api_url}/organizations?$top=1")
        orgs = r.json().get("value", [])
        return orgs[0] if orgs else {}

    def query(self, entity_set: str, filter: str = "", select: str = "") -> dict:
        """OData query with optional filter and select."""
        parts = []
        if filter:
            parts.append(f"$filter={filter}")
        if select:
            parts.append(f"$select={select}")
        qs = "&".join(parts)
        url = f"{self.api_url}/{entity_set}{'?' + qs if qs else ''}"
        return self._request("GET", url).json()

    def create_record(self, entity_set: str, data: dict) -> Optional[str]:
        """Create a Dataverse record. Returns record ID."""
        if self.dry_run:
            print(f"  [DRY RUN] Would create record in {entity_set}")
            return "00000000-0000-0000-0000-000000000000"
        url = f"{self.api_url}/{entity_set}"
        r = self._request("POST", url, data=data)
        entity_id = r.headers.get("OData-EntityId", "")
        if "(" in entity_id:
            return entity_id.split("(")[-1].rstrip(")")
        return None

    def check_table_exists(self, logical_name: str) -> bool:
        """Check if a Dataverse table exists."""
        try:
            url = (
                f"{self.api_url}/EntityDefinitions"
                f"(LogicalName='{logical_name}')?$select=LogicalName"
            )
            self._request("GET", url)
            return True
        except RuntimeError:
            return False

    def create_entity(self, definition: dict) -> None:
        """Create a Dataverse entity (table)."""
        if self.dry_run:
            schema = definition.get("SchemaName", "unknown")
            print(f"  [DRY RUN] Would create entity: {schema}")
            return
        url = f"{self.api_url}/EntityDefinitions"
        self._request("POST", url, data=definition)

    def create_column(
        self, table_name: str, schema_name: str, col_type: str, definition: dict
    ) -> None:
        """Create a column on an existing table (idempotent)."""
        try:
            check_url = (
                f"{self.api_url}/EntityDefinitions(LogicalName='{table_name}')"
                f"/Attributes(LogicalName='{schema_name.lower()}')"
                f"?$select=LogicalName"
            )
            self._request("GET", check_url)
            print(f"    {schema_name}: already exists")
            return
        except RuntimeError:
            pass

        if self.dry_run:
            print(f"    [DRY RUN] Would create {schema_name} ({col_type})")
            return

        url = (
            f"{self.api_url}/EntityDefinitions(LogicalName='{table_name}')"
            f"/Attributes"
        )
        self._request("POST", url, data=definition)
        print(f"    {schema_name}: created ({col_type})")

    def create_option_set(
        self, name: str, options: list[tuple[str, int]]
    ) -> None:
        """Create a global option set (idempotent)."""
        try:
            url = f"{self.api_url}/GlobalOptionSetDefinitions(Name='{name}')"
            self._request("GET", url)
            print(f"  {name}: already exists")
            return
        except RuntimeError:
            pass

        if self.dry_run:
            print(f"  [DRY RUN] Would create option set: {name}")
            return

        labels = []
        for label_text, value in options:
            labels.append(
                {
                    "Value": value,
                    "Label": {
                        "@odata.type": "Microsoft.Dynamics.CRM.Label",
                        "LocalizedLabels": [
                            {
                                "@odata.type": (
                                    "Microsoft.Dynamics.CRM.LocalizedLabel"
                                ),
                                "Label": label_text,
                                "LanguageCode": 1033,
                            }
                        ],
                    },
                }
            )

        definition = {
            "@odata.type": "#Microsoft.Dynamics.CRM.OptionSetMetadata",
            "Name": name,
            "OptionSetType": "Picklist",
            "Options": labels,
        }

        url = f"{self.api_url}/GlobalOptionSetDefinitions"
        self._request("POST", url, data=definition)
        print(f"  {name}: created")
