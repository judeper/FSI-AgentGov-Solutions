#!/usr/bin/env python3
"""UASDClient - Dataverse Web API client for Unrestricted Agent Sharing Detector.

Provides authenticated access to Microsoft Dataverse (Power Platform)
for schema deployment and data operations. Supports both interactive
browser and service principal authentication via MSAL.
"""

import json
import os
import re
import sys
from typing import Any, Optional
from urllib.parse import urljoin

import msal
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


class UASDClient:
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
        """Initialize UASD client.

        Args:
            tenant_id: Entra ID tenant ID
            environment_url: Dataverse environment URL (e.g., https://org.crm.dynamics.com)
            client_id: Application (client) ID
            client_secret: Client secret value (required for SP auth)
            interactive: Use interactive browser auth instead of SP
            dry_run: If True, log API calls without executing them
        """
        self.tenant_id = tenant_id
        self.environment_url = environment_url.rstrip("/")
        self.client_id = client_id
        self.client_secret = client_secret
        self.interactive = interactive
        self.dry_run = dry_run
        self.base_url = f"{self.environment_url}/api/data/{self.API_VERSION}"
        self._token_cache = msal.SerializableTokenCache()

        authority = f"https://login.microsoftonline.com/{tenant_id}"
        self.scopes = [f"{self.environment_url}/.default"]

        if interactive:
            app_id = client_id or "51f81489-12ee-4a9e-aaae-a2591f45987d"
            self.app = msal.PublicClientApplication(
                app_id,
                authority=authority,
                token_cache=self._token_cache,
            )
        else:
            if not client_id or not client_secret:
                raise ValueError(
                    "client_id and client_secret required for non-interactive auth"
                )
            self.app = msal.ConfidentialClientApplication(
                client_id,
                client_credential=client_secret,
                authority=authority,
                token_cache=self._token_cache,
            )

        self._session = self._build_session()

    def _build_session(self) -> requests.Session:
        """Build requests session with retry logic."""
        session = requests.Session()
        retry = Retry(
            total=3,
            backoff_factor=1,
            status_forcelist=[429, 500, 502, 503, 504],
        )
        adapter = HTTPAdapter(max_retries=retry)
        session.mount("https://", adapter)
        return session

    def _get_token(self) -> str:
        """Acquire access token from MSAL cache or authority."""
        if self.interactive:
            accounts = self.app.get_accounts()
            if accounts:
                result = self.app.acquire_token_silent(self.scopes, account=accounts[0])
                if result is None:
                    result = self.app.acquire_token_interactive(self.scopes)
            else:
                result = self.app.acquire_token_interactive(self.scopes)
        else:
            result = self.app.acquire_token_for_client(self.scopes)

        if "access_token" not in result:
            raise RuntimeError(
                f"Failed to acquire token: {result.get('error_description', result)}"
            )
        return result["access_token"]

    def _headers(self) -> dict:
        """Build standard Dataverse API headers."""
        return {
            "Authorization": f"Bearer {self._get_token()}",
            "Accept": "application/json",
            "Content-Type": "application/json; charset=utf-8",
            "OData-MaxVersion": "4.0",
            "OData-Version": "4.0",
        }

    def query(self, entity: str, filter: str = "", select: str = "") -> dict:
        """Execute a GET query against a Dataverse entity collection.

        Args:
            entity: Dataverse entity set name (e.g., 'fsi_agentsharingaudits')
            filter: OData $filter expression (optional)
            select: Comma-separated $select column list (optional)

        Returns:
            Parsed JSON response with 'value' array.
        """
        params = {}
        if filter:
            params["$filter"] = filter
        if select:
            params["$select"] = select

        url = f"{self.base_url}/{entity}"
        response = self._session.get(url, headers=self._headers(), params=params)
        response.raise_for_status()
        return response.json()

    def create_record(self, entity: str, data: dict) -> str:
        """Create a Dataverse record and return its GUID.

        Args:
            entity: Dataverse entity set name
            data: Record field values

        Returns:
            GUID of created record.
        """
        if self.dry_run:
            print(f"  [DRY RUN] Would create record in {entity}: {list(data.keys())}")
            return "00000000-0000-0000-0000-000000000000"

        url = f"{self.base_url}/{entity}"
        response = self._session.post(url, headers=self._headers(), json=data)
        response.raise_for_status()
        location = response.headers.get("OData-EntityId", "")
        match = re.search(r"\(([^)]+)\)$", location)
        return match.group(1) if match else ""

    def check_table_exists(self, logical_name: str) -> bool:
        """Check whether a Dataverse table exists.

        Args:
            logical_name: Table logical name (lowercase)

        Returns:
            True if the table exists, False otherwise.
        """
        url = (
            f"{self.environment_url}/api/data/{self.API_VERSION}/"
            f"EntityDefinitions(LogicalName='{logical_name}')"
        )
        try:
            resp = self._session.get(
                url,
                headers=self._headers(),
                params={"$select": "LogicalName"},
            )
            return resp.status_code == 200
        except Exception:
            return False

    def create_entity(self, definition: dict) -> None:
        """Create a Dataverse custom table.

        Args:
            definition: EntityMetadata payload.
        """
        if self.dry_run:
            print(f"  [DRY RUN] Would create entity: {definition.get('SchemaName')}")
            return

        url = f"{self.environment_url}/api/data/{self.API_VERSION}/EntityDefinitions"
        response = self._session.post(url, headers=self._headers(), json=definition)
        response.raise_for_status()

    def create_option_set(self, name: str, options: list[tuple]) -> None:
        """Create or verify a global option set.

        Args:
            name: Option set schema name
            options: List of (label, value) tuples
        """
        # Check existence
        url = (
            f"{self.environment_url}/api/data/{self.API_VERSION}/"
            f"GlobalOptionSetDefinitions(Name='{name}')"
        )
        resp = self._session.get(
            url, headers=self._headers(), params={"$select": "Name"}
        )
        if resp.status_code == 200:
            print(f"  {name}: already exists, skipping")
            return

        if self.dry_run:
            print(f"  [DRY RUN] Would create option set: {name}")
            return

        payload = {
            "@odata.type": "Microsoft.Dynamics.CRM.OptionSetMetadata",
            "Name": name,
            "DisplayName": {
                "@odata.type": "Microsoft.Dynamics.CRM.Label",
                "LocalizedLabels": [
                    {
                        "@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel",
                        "Label": name,
                        "LanguageCode": 1033,
                    }
                ],
            },
            "IsGlobal": True,
            "OptionSetType": "Picklist",
            "Options": [
                {
                    "Value": val,
                    "Label": {
                        "@odata.type": "Microsoft.Dynamics.CRM.Label",
                        "LocalizedLabels": [
                            {
                                "@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel",
                                "Label": label,
                                "LanguageCode": 1033,
                            }
                        ],
                    },
                }
                for label, val in options
            ],
        }

        create_url = (
            f"{self.environment_url}/api/data/{self.API_VERSION}/"
            "GlobalOptionSetDefinitions"
        )
        response = self._session.post(create_url, headers=self._headers(), json=payload)
        response.raise_for_status()
        print(f"  {name}: created ({len(options)} options)")

    def create_column(
        self,
        entity_logical_name: str,
        schema_name: str,
        col_type: str,
        definition: dict,
    ) -> None:
        """Create a column on an existing Dataverse table.

        Args:
            entity_logical_name: Table logical name
            schema_name: Column schema name
            col_type: Metadata type string (for logging)
            definition: AttributeMetadata payload
        """
        # Check existence
        col_logical = schema_name.lower()
        url = (
            f"{self.environment_url}/api/data/{self.API_VERSION}/"
            f"EntityDefinitions(LogicalName='{entity_logical_name}')/"
            f"Attributes(LogicalName='{col_logical}')"
        )
        resp = self._session.get(
            url, headers=self._headers(), params={"$select": "LogicalName"}
        )
        if resp.status_code == 200:
            print(f"    {schema_name}: already exists, skipping")
            return

        if self.dry_run:
            print(f"    [DRY RUN] Would create column: {schema_name} ({col_type})")
            return

        create_url = (
            f"{self.environment_url}/api/data/{self.API_VERSION}/"
            f"EntityDefinitions(LogicalName='{entity_logical_name}')/Attributes"
        )
        response = self._session.post(
            create_url, headers=self._headers(), json=definition
        )
        response.raise_for_status()
        print(f"    {schema_name}: created ({col_type})")
