#!/usr/bin/env python3
"""
Dataverse Web API client for Session Security Configurator.

Uses MSAL for authentication (interactive browser or service principal).
Includes retry logic and dry-run mode for safe deployments.
"""

import argparse
import json
import os
import sys
from typing import Any, Optional
from urllib.parse import urljoin

import msal
import requests
from requests.adapters import HTTPAdapter, Retry


class SSCClient:
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
        Initialize SSC client.

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

        # Dataverse requires the environment URL as the scope
        self._scope = [f"{self.environment_url}/.default"]
        self._token: Optional[dict] = None

        # Setup retry strategy
        self._session = requests.Session()
        retry_strategy = Retry(
            total=3,
            backoff_factor=1,
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["GET", "POST", "PATCH", "DELETE"],
        )
        adapter = HTTPAdapter(max_retries=retry_strategy)
        self._session.mount("https://", adapter)
        self._session.mount("http://", adapter)

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
        return data.get("value", [{}])[0]

    def query(self, entity_set, select=None, filter_expr=None, orderby=None, top=None):
        if self.dry_run:
            print(f"  [DRY RUN] Would query: {entity_set}")
            return []
        params = {}
        if select: params["$select"] = ",".join(select)
        if filter_expr: params["$filter"] = filter_expr
        if orderby: params["$orderby"] = orderby
        if top: params["$top"] = str(top)
        results = []
        url = urljoin(self.api_url, entity_set)
        headers = self._get_headers()
        while url:
            response = self._session.get(url, headers=headers, params=params)
            response.raise_for_status()
            data = response.json()
            results.extend(data.get("value", []))
            url = data.get("@odata.nextLink")
            params = {}  # nextLink URL includes query params
        return results

    def create_record(self, entity_set, data):
        if self.dry_run:
            print(f"  [DRY RUN] Would create record in: {entity_set}")
            return "00000000-0000-0000-0000-000000000000"
        response = self._session.post(urljoin(self.api_url, entity_set), headers=self._get_headers(), json=data)
        response.raise_for_status()
        entity_id = response.headers.get("OData-EntityId", "")
        if "(" in entity_id and ")" in entity_id:
            return entity_id.split("(")[1].split(")")[0]
        return ""

    def get_entity_metadata(self, logical_name):
        if self.dry_run:
            print(f"  [DRY RUN] Would check entity: {logical_name}")
            return None
        try:
            response = self._session.get(urljoin(self.api_url, f"EntityDefinitions(LogicalName='{logical_name}')"), headers=self._get_headers())
            if response.status_code == 404: return None
            response.raise_for_status()
            return response.json()
        except requests.HTTPError as e:
            if e.response.status_code == 404: return None
            raise

    def create_entity(self, entity_metadata):
        if self.dry_run:
            schema_name = entity_metadata.get("SchemaName", "Unknown")
            print(f"  [DRY RUN] Would create entity: {schema_name}")
            return {"LogicalName": schema_name.lower()}
        response = self._session.post(urljoin(self.api_url, "EntityDefinitions"), headers=self._get_headers(), json=entity_metadata)
        response.raise_for_status()
        entity_id = response.headers.get("OData-EntityId", "")
        if entity_id:
            get_response = self._session.get(entity_id, headers=self._get_headers())
            if get_response.ok: return get_response.json()
        return {"LogicalName": entity_metadata.get("SchemaName", "").lower()}

    def create_attribute(self, entity_logical_name, attribute_metadata):
        if self.dry_run:
            col_name = attribute_metadata.get("SchemaName", "Unknown")
            print(f"  [DRY RUN] Would create column: {entity_logical_name}.{col_name}")
            return attribute_metadata
        response = self._session.post(urljoin(self.api_url, f"EntityDefinitions(LogicalName='{entity_logical_name}')/Attributes"), headers=self._get_headers(), json=attribute_metadata)
        response.raise_for_status()
        return attribute_metadata

    def get_attribute_metadata(self, entity_logical_name, attribute_logical_name):
        if self.dry_run:
            print(f"  [DRY RUN] Would check column: {entity_logical_name}.{attribute_logical_name}")
            return None
        try:
            response = self._session.get(urljoin(self.api_url, f"EntityDefinitions(LogicalName='{entity_logical_name}')/Attributes(LogicalName='{attribute_logical_name}')"), headers=self._get_headers())
            if response.status_code == 404: return None
            response.raise_for_status()
            return response.json()
        except requests.HTTPError as e:
            if e.response.status_code == 404: return None
            raise

    def create_global_optionset(self, optionset_metadata):
        if self.dry_run:
            name = optionset_metadata.get("Name", "Unknown")
            print(f"  [DRY RUN] Would create option set: {name}")
            return optionset_metadata
        response = self._session.post(urljoin(self.api_url, "GlobalOptionSetDefinitions"), headers=self._get_headers(), json=optionset_metadata)
        response.raise_for_status()
        return optionset_metadata

    def get_global_optionset(self, name):
        if self.dry_run:
            print(f"  [DRY RUN] Would check option set: {name}")
            return None
        try:
            response = self._session.get(urljoin(self.api_url, f"GlobalOptionSetDefinitions(Name='{name}')"), headers=self._get_headers())
            if response.status_code == 404: return None
            response.raise_for_status()
            return response.json()
        except requests.HTTPError as e:
            if e.response.status_code == 404: return None
            raise

    def check_table_exists(self, logical_name):
        return self.get_entity_metadata(logical_name) is not None

    def create_table(self, table_metadata):
        schema_name = table_metadata.get("SchemaName", "")
        logical_name = schema_name.lower()
        if self.check_table_exists(logical_name): return None
        return self.create_entity(table_metadata)

    def create_option_set(self, optionset_metadata):
        name = optionset_metadata.get("Name", "")
        if self.get_global_optionset(name): return None
        return self.create_global_optionset(optionset_metadata)

    def create_column(self, entity_logical_name, column_metadata):
        schema_name = column_metadata.get("SchemaName", "")
        col_logical_name = schema_name.lower()
        if self.get_attribute_metadata(entity_logical_name, col_logical_name): return None
        return self.create_attribute(entity_logical_name, column_metadata)


def main():
    parser = argparse.ArgumentParser(description="Dataverse Web API client for Session Security Configurator", formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tenant-id", default=os.environ.get("SSC_TENANT_ID"), help="Entra ID tenant ID (or set SSC_TENANT_ID env var)")
    parser.add_argument("--client-id", default=os.environ.get("SSC_CLIENT_ID"), help="Application (client) ID (or set SSC_CLIENT_ID env var)")
    parser.add_argument("--client-secret", default=os.environ.get("SSC_CLIENT_SECRET"), help="Client secret (or set SSC_CLIENT_SECRET env var)")
    parser.add_argument("--environment-url", default=os.environ.get("SSC_ENVIRONMENT_URL"), help="Dataverse environment URL (or set SSC_ENVIRONMENT_URL env var)")
    parser.add_argument("--interactive", action="store_true", help="Use interactive browser authentication")
    parser.add_argument("--test-connection", action="store_true", help="Test connection to Dataverse")
    parser.add_argument("--dry-run", action="store_true", help="Log API calls without executing them")
    args = parser.parse_args()
    if not args.tenant_id or not args.environment_url:
        parser.error("Missing required arguments. Provide --tenant-id and --environment-url (or set SSC_TENANT_ID and SSC_ENVIRONMENT_URL env vars)")
    if not args.client_id:
        parser.error("--client-id is required (or set SSC_CLIENT_ID env var)")
    client_secret = args.client_secret
    if not args.interactive:
        if not client_secret:
            import getpass
            client_secret = getpass.getpass("Client secret: ")
    try:
        client = SSCClient(tenant_id=args.tenant_id, environment_url=args.environment_url, client_id=args.client_id, client_secret=client_secret, interactive=args.interactive, dry_run=args.dry_run)
        if args.test_connection:
            print("Testing Dataverse connection...")
            org = client.test_connection()
            if not args.dry_run:
                print(f"  Token acquired: ✓")
                print(f"  API accessible: ✓")
                print(f"  Organization: {org.get('name', 'Unknown')}")
                print("\nConnection test: PASSED")
            sys.exit(0)
    except requests.HTTPError as e:
        print(f"HTTP Error: {e}", file=sys.stderr)
        sys.exit(2)
    except RuntimeError as e:
        print(f"Authentication Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(4)


if __name__ == "__main__":
    main()
