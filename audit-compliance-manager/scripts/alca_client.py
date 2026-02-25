#!/usr/bin/env python3
"""
Dataverse Web API client for Audit Logging Compliance Automation (ALCA).

Uses MSAL for authentication (interactive browser or service principal).
Includes retry logic, dry-run mode, and alternate key support for safe deployments.
"""

import json
import os
import sys
from typing import Any, Optional
from urllib.parse import urljoin

import msal
import requests
from requests.adapters import HTTPAdapter, Retry


class ALCAClient:
    """Dataverse Web API client with MSAL authentication and retry logic."""

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
        """
        Initialize ALCA client.

        Args:
            tenant_id: Entra ID tenant ID
            environment_url: Dataverse environment URL (e.g., https://org.crm.dynamics.com)
            client_id: Application (client) ID (required for all auth modes)
            client_secret: Client secret value (required for SP auth)
            interactive: Use interactive browser auth instead of SP
            dry_run: If True, log API calls without executing them
        """
        self.tenant_id = tenant_id
        self.client_id = client_id
        self.client_secret = client_secret
        self.environment_url = environment_url.rstrip("/")
        self.api_url = f"{self.environment_url}/api/data/{self.API_VERSION}/"
        self.interactive = interactive
        self.dry_run = dry_run

        self._scope = [f"{self.environment_url}/.default"]
        self._token: Optional[dict] = None

        # Setup retry strategy
        self._session = requests.Session()
        retry_strategy = Retry(
            total=3,
            backoff_factor=1,
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["GET", "POST", "PATCH", "DELETE", "PUT"],
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        self._session.mount("https://", adapter)

        if interactive:
            if not client_id:
                raise ValueError(
                    "client_id is required for interactive authentication. "
                    "Register an app in Entra ID and provide --client-id."
                )
            self._app = msal.PublicClientApplication(
                client_id=client_id,
                authority=f"https://login.microsoftonline.com/{tenant_id}",
            )
        else:
            if not client_id or not client_secret:
                raise ValueError("client_id and client_secret required for non-interactive auth")
            self._app = msal.ConfidentialClientApplication(
                client_id=client_id,
                client_credential=client_secret,
                authority=f"https://login.microsoftonline.com/{tenant_id}",
            )

    def _get_token(self) -> str:
        """Acquire access token with caching."""
        accounts = self._app.get_accounts() if self.interactive else None
        result = self._app.acquire_token_silent(
            scopes=self._scope,
            account=accounts[0] if accounts else None,
        )

        if not result:
            if self.interactive:
                result = self._app.acquire_token_interactive(scopes=self._scope)
            else:
                result = self._app.acquire_token_for_client(scopes=self._scope)

        if "access_token" not in result:
            error = result.get("error_description", result.get("error", "Unknown error"))
            raise RuntimeError(f"Failed to acquire token: {error}")

        self._token = result
        return result["access_token"]

    def _get_headers(self) -> dict:
        """Get HTTP headers with authorization."""
        token = self._get_token()
        return {
            "Authorization": f"Bearer {token}",
            "Content-Type": "application/json",
            "OData-MaxVersion": "4.0",
            "OData-Version": "4.0",
            "Accept": "application/json",
            "Prefer": "odata.include-annotations=*",
        }

    def test_connection(self) -> dict:
        """Test connection to Dataverse."""
        if self.dry_run:
            print("  [DRY RUN] Would test connection to Dataverse")
            return {"name": "DRY-RUN-ORG"}

        response = self._session.get(
            urljoin(self.api_url, "organizations"),
            headers=self._get_headers(),
            params={"$select": "organizationid,name"},
        )
        response.raise_for_status()
        data = response.json()
        values = data.get("value", [])
        return values[0] if values else {}

    # =========================================================================
    # Metadata Operations (schema deployment)
    # =========================================================================

    def get_entity_metadata(self, logical_name: str) -> Optional[dict]:
        """Get entity metadata by logical name. Returns None if not found."""
        if self.dry_run:
            print(f"  [DRY RUN] Would check entity: {logical_name}")
            return None

        try:
            response = self._session.get(
                urljoin(self.api_url, f"EntityDefinitions(LogicalName='{logical_name}')"),
                headers=self._get_headers(),
            )
            if response.status_code == 404:
                return None
            response.raise_for_status()
            return response.json()
        except requests.HTTPError as e:
            if e.response.status_code == 404:
                return None
            raise

    def create_entity(self, entity_metadata: dict) -> dict:
        """Create a new entity (table)."""
        if self.dry_run:
            schema_name = entity_metadata.get("SchemaName", "Unknown")
            print(f"  [DRY RUN] Would create entity: {schema_name}")
            return {"LogicalName": schema_name.lower()}

        response = self._session.post(
            urljoin(self.api_url, "EntityDefinitions"),
            headers=self._get_headers(),
            json=entity_metadata,
        )
        response.raise_for_status()

        entity_id = response.headers.get("OData-EntityId", "")
        if entity_id:
            get_response = self._session.get(entity_id, headers=self._get_headers())
            if get_response.ok:
                return get_response.json()
        return {"LogicalName": entity_metadata.get("SchemaName", "").lower()}

    def create_attribute(self, entity_logical_name: str, attribute_metadata: dict) -> dict:
        """Create a new attribute (column) on an entity."""
        if self.dry_run:
            col_name = attribute_metadata.get("SchemaName", "Unknown")
            print(f"  [DRY RUN] Would create column: {entity_logical_name}.{col_name}")
            return attribute_metadata

        response = self._session.post(
            urljoin(
                self.api_url,
                f"EntityDefinitions(LogicalName='{entity_logical_name}')/Attributes",
            ),
            headers=self._get_headers(),
            json=attribute_metadata,
        )
        response.raise_for_status()
        return attribute_metadata

    def get_attribute_metadata(
        self, entity_logical_name: str, attribute_logical_name: str
    ) -> Optional[dict]:
        """Get attribute metadata. Returns None if not found."""
        if self.dry_run:
            print(f"  [DRY RUN] Would check column: {entity_logical_name}.{attribute_logical_name}")
            return None

        try:
            response = self._session.get(
                urljoin(
                    self.api_url,
                    f"EntityDefinitions(LogicalName='{entity_logical_name}')"
                    f"/Attributes(LogicalName='{attribute_logical_name}')",
                ),
                headers=self._get_headers(),
            )
            if response.status_code == 404:
                return None
            response.raise_for_status()
            return response.json()
        except requests.HTTPError as e:
            if e.response.status_code == 404:
                return None
            raise

    def create_global_optionset(self, optionset_metadata: dict) -> dict:
        """Create a global option set (choice)."""
        if self.dry_run:
            name = optionset_metadata.get("Name", "Unknown")
            print(f"  [DRY RUN] Would create option set: {name}")
            return optionset_metadata

        response = self._session.post(
            urljoin(self.api_url, "GlobalOptionSetDefinitions"),
            headers=self._get_headers(),
            json=optionset_metadata,
        )
        response.raise_for_status()
        return optionset_metadata

    def get_global_optionset(self, name: str) -> Optional[dict]:
        """Get global option set by name. Returns None if not found."""
        if self.dry_run:
            print(f"  [DRY RUN] Would check option set: {name}")
            return None

        try:
            response = self._session.get(
                urljoin(self.api_url, f"GlobalOptionSetDefinitions(Name='{name}')"),
                headers=self._get_headers(),
            )
            if response.status_code == 404:
                return None
            response.raise_for_status()
            return response.json()
        except requests.HTTPError as e:
            if e.response.status_code == 404:
                return None
            raise

    # =========================================================================
    # Alternate Key Operations (for upsert support)
    # =========================================================================

    def create_alternate_key(
        self, entity_logical_name: str, key_metadata: dict
    ) -> dict:
        """
        Create an alternate key on an entity for upsert support.

        Args:
            entity_logical_name: Entity logical name
            key_metadata: Key definition with SchemaName, DisplayName, KeyAttributes
        """
        if self.dry_run:
            key_name = key_metadata.get("SchemaName", "Unknown")
            print(f"  [DRY RUN] Would create alternate key: {entity_logical_name}.{key_name}")
            return key_metadata

        response = self._session.post(
            urljoin(
                self.api_url,
                f"EntityDefinitions(LogicalName='{entity_logical_name}')/Keys",
            ),
            headers=self._get_headers(),
            json=key_metadata,
        )
        response.raise_for_status()
        return key_metadata

    def get_alternate_keys(self, entity_logical_name: str) -> list[dict]:
        """Get all alternate keys for an entity."""
        if self.dry_run:
            print(f"  [DRY RUN] Would check alternate keys: {entity_logical_name}")
            return []

        try:
            results = []
            url = urljoin(
                self.api_url,
                f"EntityDefinitions(LogicalName='{entity_logical_name}')/Keys",
            )
            headers = self._get_headers()
            while url:
                response = self._session.get(url, headers=headers)
                if response.status_code == 404:
                    return []
                response.raise_for_status()
                data = response.json()
                results.extend(data.get("value", []))
                url = data.get("@odata.nextLink")
            return results
        except requests.HTTPError as e:
            if e.response.status_code == 404:
                return []
            raise
