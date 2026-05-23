#!/usr/bin/env python3
"""ACAClient - Dataverse Web API client for Action Confirmation Auditor.

Provides authenticated access to Microsoft Dataverse (Power Platform)
for schema deployment and data operations. Supports both interactive
browser and service principal authentication via MSAL.
"""

import argparse
import os
import re
import sys
from typing import Optional

import msal
import requests
from requests.adapters import HTTPAdapter
from urllib3.util.retry import Retry


class ACAClient:
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
        """Initialize ACA client.

        Args:
            tenant_id: Entra ID tenant ID
            environment_url: Dataverse environment URL (e.g., https://org.crm.dynamics.com)
            client_id: Application (client) ID
            client_secret: Legacy dev-only client secret value (required for SP auth)
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

        # Dataverse requires the environment URL as the scope
        authority = f"https://login.microsoftonline.com/{tenant_id}"
        self.scopes = [f"{self.environment_url}/.default"]

        if interactive:
            # Public client for interactive auth — use provided ID or Microsoft
            # well-known public client ID as fallback
            app_id = client_id or "51f81489-12ee-4a9e-aaae-a2591f45987d"
            self.app = msal.PublicClientApplication(
                app_id,
                authority=authority,
                token_cache=self._token_cache,
            )
        else:
            # legacy: dev-only — replace with managed identity in production
            # Confidential client for service-to-service auth
            if not client_id or not client_secret:
                raise ValueError(
                    "client_id and legacy dev-only client_secret required for non-interactive auth"
                )
            self.app = msal.ConfidentialClientApplication(
                client_id,
                client_credential=client_secret,
                authority=authority,
                token_cache=self._token_cache,
            )

        # Setup retry strategy for transient failures
        self.session = requests.Session()
        retry = Retry(
            total=3,
            backoff_factor=1,
            status_forcelist=[429, 500, 502, 503, 504],
            allowed_methods=["GET", "POST", "PATCH", "DELETE"],
        )
        adapter = HTTPAdapter(max_retries=retry)
        self.session.mount("https://", adapter)
        self.session.mount("http://", adapter)

    # =========================================================================
    # Authentication
    # =========================================================================

    def _get_token(self) -> str:
        """Acquire access token with silent cache fallback.

        Returns:
            Access token string

        Raises:
            RuntimeError: If token acquisition fails
        """
        accounts = self.app.get_accounts() if self.interactive else None
        result = self.app.acquire_token_silent(
            scopes=self.scopes,
            account=accounts[0] if accounts else None,
        )

        if not result:
            if self.interactive:
                result = self.app.acquire_token_interactive(scopes=self.scopes)
            else:
                result = self.app.acquire_token_for_client(scopes=self.scopes)

        if "access_token" not in result:
            error = result.get(
                "error_description", result.get("error", "Unknown error")
            )
            raise RuntimeError(f"Token acquisition failed: {error}")

        return result["access_token"]

    def _get_headers(self) -> dict:
        """Get HTTP headers with authorization and OData settings."""
        return {
            "Authorization": f"Bearer {self._get_token()}",
            "Accept": "application/json",
            "Content-Type": "application/json",
            "OData-MaxVersion": "4.0",
            "OData-Version": "4.0",
            "Prefer": "odata.include-annotations=*",
        }

    # =========================================================================
    # Connection Test
    # =========================================================================

    def test_connection(self) -> dict:
        """Test connection to Dataverse by querying organizations endpoint.

        Returns:
            Organization information dict
        """
        if self.dry_run:
            print("  [DRY-RUN] Would test connection to Dataverse")
            return {"name": "DRY-RUN-ORG"}

        resp = self.session.get(
            f"{self.base_url}/organizations",
            headers=self._get_headers(),
            params={"$select": "organizationid,name"},
        )
        resp.raise_for_status()
        orgs = resp.json().get("value", [])
        if orgs:
            print(f"  Connected: {orgs[0].get('name', 'unknown')}")
        return orgs[0] if orgs else {}

    # =========================================================================
    # Data Operations
    # =========================================================================

    def query(
        self,
        entity_set: str,
        select: Optional[str] = None,
        filter: Optional[str] = None,
        orderby: Optional[str] = None,
        top: Optional[int] = None,
    ) -> dict:
        """Query Dataverse table using OData.

        Args:
            entity_set: Entity set name (e.g., 'fsi_actionauditresults')
            select: OData $select expression
            filter: OData $filter expression
            orderby: OData $orderby expression
            top: Maximum records to return

        Returns:
            OData response dict with 'value' list
        """
        if self.dry_run:
            print(f"  [DRY-RUN] Would query: {entity_set}")
            return {"value": []}

        params = {}
        if select:
            params["$select"] = select
        if filter:
            params["$filter"] = filter
        if orderby:
            params["$orderby"] = orderby
        if top:
            params["$top"] = str(top)

        resp = self.session.get(
            f"{self.base_url}/{entity_set}",
            headers=self._get_headers(),
            params=params,
        )
        resp.raise_for_status()
        return resp.json()

    def create_record(self, entity_set: str, data: dict) -> Optional[str]:
        """Create a record in Dataverse.

        Args:
            entity_set: Entity set name
            data: Record data dict

        Returns:
            Created record ID or None
        """
        if self.dry_run:
            print(f"  [DRY-RUN] Would create record in {entity_set}")
            return "00000000-0000-0000-0000-000000000000"

        resp = self.session.post(
            f"{self.base_url}/{entity_set}",
            headers=self._get_headers(),
            json=data,
        )
        resp.raise_for_status()

        # Extract ID from OData-EntityId header
        entity_id = resp.headers.get("OData-EntityId", "")
        match = re.search(r"\(([^)]+)\)", entity_id)
        return match.group(1) if match else None

    # =========================================================================
    # Metadata Operations (for schema deployment)
    # =========================================================================

    def get_entity_metadata(self, logical_name: str) -> Optional[dict]:
        """Get entity metadata by logical name.

        Args:
            logical_name: Entity logical name (e.g., 'fsi_actionauditresult')

        Returns:
            Entity metadata dict or None if not found
        """
        if self.dry_run:
            print(f"  [DRY-RUN] Would check entity: {logical_name}")
            return None

        try:
            resp = self.session.get(
                f"{self.base_url}/EntityDefinitions(LogicalName='{logical_name}')",
                headers=self._get_headers(),
            )
            if resp.status_code == 404:
                return None
            resp.raise_for_status()
            return resp.json()
        except requests.exceptions.HTTPError as e:
            if e.response is not None and e.response.status_code == 404:
                return None
            raise

    def create_entity(self, definition: dict) -> Optional[dict]:
        """Create a new entity (table) in Dataverse.

        Args:
            definition: Entity definition per Dataverse Web API spec

        Returns:
            Created entity metadata or None in dry-run mode
        """
        if self.dry_run:
            name = definition.get("SchemaName", "unknown")
            print(f"  [DRY-RUN] Would create entity: {name}")
            return {"LogicalName": name.lower()}

        resp = self.session.post(
            f"{self.base_url}/EntityDefinitions",
            headers=self._get_headers(),
            json=definition,
        )
        resp.raise_for_status()

        # Retrieve the created entity metadata
        entity_id = resp.headers.get("OData-EntityId", "")
        if entity_id:
            get_resp = self.session.get(entity_id, headers=self._get_headers())
            if get_resp.ok:
                return get_resp.json()
        return {"LogicalName": definition.get("SchemaName", "").lower()}

    def create_attribute(self, entity_name: str, definition: dict) -> Optional[dict]:
        """Create a new attribute (column) on an entity.

        Args:
            entity_name: Entity logical name
            definition: Attribute definition per Dataverse Web API spec

        Returns:
            Created attribute metadata
        """
        if self.dry_run:
            name = definition.get("SchemaName", "unknown")
            print(f"  [DRY-RUN] Would create attribute {name} on {entity_name}")
            return definition

        url = (
            f"{self.base_url}/EntityDefinitions"
            f"(LogicalName='{entity_name}')/Attributes"
        )
        resp = self.session.post(url, headers=self._get_headers(), json=definition)
        resp.raise_for_status()
        return definition

    def get_attribute_metadata(
        self, entity_name: str, attribute: str
    ) -> Optional[dict]:
        """Get attribute metadata by logical name.

        Args:
            entity_name: Entity logical name
            attribute: Attribute logical name

        Returns:
            Attribute metadata dict or None if not found
        """
        if self.dry_run:
            print(f"  [DRY-RUN] Would check column: {entity_name}.{attribute}")
            return None

        try:
            url = (
                f"{self.base_url}/EntityDefinitions"
                f"(LogicalName='{entity_name}')"
                f"/Attributes(LogicalName='{attribute}')"
            )
            resp = self.session.get(url, headers=self._get_headers())
            if resp.status_code == 404:
                return None
            resp.raise_for_status()
            return resp.json()
        except requests.exceptions.HTTPError as e:
            if e.response is not None and e.response.status_code == 404:
                return None
            raise

    def create_global_optionset(self, definition: dict) -> Optional[dict]:
        """Create a global option set (choice).

        Args:
            definition: OptionSet definition

        Returns:
            Created option set metadata
        """
        if self.dry_run:
            name = definition.get("Name", "unknown")
            print(f"  [DRY-RUN] Would create global option set: {name}")
            return definition

        resp = self.session.post(
            f"{self.base_url}/GlobalOptionSetDefinitions",
            headers=self._get_headers(),
            json=definition,
        )
        resp.raise_for_status()
        return definition

    def get_global_optionset(self, name: str) -> Optional[dict]:
        """Get global option set by name.

        Args:
            name: OptionSet name (e.g., 'fsi_acv_zone')

        Returns:
            OptionSet metadata dict or None if not found
        """
        if self.dry_run:
            print(f"  [DRY-RUN] Would check option set: {name}")
            return None

        try:
            resp = self.session.get(
                f"{self.base_url}/GlobalOptionSetDefinitions(Name='{name}')",
                headers=self._get_headers(),
            )
            if resp.status_code == 404:
                return None
            resp.raise_for_status()
            return resp.json()
        except requests.exceptions.HTTPError as e:
            if e.response is not None and e.response.status_code == 404:
                return None
            raise

    # =========================================================================
    # Idempotent Deployment Helpers
    # =========================================================================

    def check_table_exists(self, logical_name: str) -> bool:
        """Check if a table exists in Dataverse.

        Args:
            logical_name: Table logical name

        Returns:
            True if table exists, False otherwise
        """
        return self.get_entity_metadata(logical_name) is not None

    def create_table(
        self,
        name: str,
        display: str,
        plural: str,
        description: str,
        ownership: str,
        columns: Optional[list] = None,
    ) -> None:
        """Create a table if it doesn't already exist (idempotent).

        Args:
            name: Table schema name (e.g., 'fsi_ActionAuditResult')
            display: Display name
            plural: Plural display name
            description: Table description
            ownership: 'UserOwned' or 'OrganizationOwned'
            columns: Optional list of inline column definitions
        """
        logical = name.lower()
        if self.check_table_exists(logical):
            print(f"  {logical}: already exists, skipping table creation")
            return

        definition = {
            "@odata.type": "#Microsoft.Dynamics.CRM.EntityMetadata",
            "SchemaName": name,
            "DisplayName": {
                "@odata.type": "Microsoft.Dynamics.CRM.Label",
                "LocalizedLabels": [
                    {
                        "@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel",
                        "Label": display,
                        "LanguageCode": 1033,
                    }
                ],
            },
            "DisplayCollectionName": {
                "@odata.type": "Microsoft.Dynamics.CRM.Label",
                "LocalizedLabels": [
                    {
                        "@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel",
                        "Label": plural,
                        "LanguageCode": 1033,
                    }
                ],
            },
            "Description": {
                "@odata.type": "Microsoft.Dynamics.CRM.Label",
                "LocalizedLabels": [
                    {
                        "@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel",
                        "Label": description,
                        "LanguageCode": 1033,
                    }
                ],
            },
            "OwnershipType": ownership,
            "IsActivity": False,
            "HasActivities": False,
            "HasNotes": False,
            "IsAuditEnabled": {"Value": True, "CanBeChanged": True},
            "PrimaryNameAttribute": "fsi_name",
        }

        self.create_entity(definition)
        print(f"  {logical}: created")

    def create_option_set(
        self, name: str, options: list[tuple[str, int]]
    ) -> None:
        """Create a global option set if it doesn't already exist (idempotent).

        Args:
            name: Option set name (e.g., 'fsi_acv_zone')
            options: List of (label, value) tuples
        """
        existing = self.get_global_optionset(name)
        if existing:
            print(f"  {name}: already exists, reusing")
            return

        option_items = [
            {
                "Value": v,
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
            for label, v in options
        ]

        definition = {
            "@odata.type": "#Microsoft.Dynamics.CRM.OptionSetMetadata",
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
            "Options": option_items,
        }

        self.create_global_optionset(definition)
        print(f"  {name}: created")

    def create_column(
        self,
        entity: str,
        name: str,
        col_type: str,
        definition: dict,
    ) -> None:
        """Create a column if it doesn't already exist (idempotent).

        Args:
            entity: Entity logical name
            name: Column schema name
            col_type: Column type descriptor (for logging)
            definition: Column metadata definition
        """
        existing = self.get_attribute_metadata(entity, name.lower())
        if existing:
            print(f"    {entity}.{name}: already exists, skipping")
            return

        self.create_attribute(entity, definition)
        print(f"    {entity}.{name}: created ({col_type})")


# =============================================================================
# CLI Entry Point
# =============================================================================


def main() -> None:
    """CLI entry point for ACAClient standalone testing."""
    parser = argparse.ArgumentParser(
        description="ACAClient - Dataverse Web API client for Action Confirmation Auditor",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ACA_TENANT_ID"),
        help="Microsoft Entra ID tenant ID (or set ACA_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ACA_CLIENT_ID"),
        help="Service principal app ID (or set ACA_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("ACA_CLIENT_SECRET"),
        help="Legacy dev-only service principal secret (or set ACA_CLIENT_SECRET env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ACA_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set ACA_ENVIRONMENT_URL env var)",
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser auth",
    )
    parser.add_argument(
        "--test-connection",
        action="store_true",
        help="Test connection and exit",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview operations without executing",
    )

    args = parser.parse_args()

    if not args.tenant_id:
        print("ERROR: --tenant-id or ACA_TENANT_ID required")
        sys.exit(1)
    if not args.environment_url:
        print("ERROR: --environment-url or ACA_ENVIRONMENT_URL required")
        sys.exit(1)

    try:
        client = ACAClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=args.client_secret,
            interactive=args.interactive,
            dry_run=args.dry_run,
        )

        if args.test_connection:
            print("Testing connection...")
            org = client.test_connection()
            if not args.dry_run:
                print("  Token acquired: OK")
                print("  API accessible: OK")
                print(f"  Organization: {org.get('name', 'Unknown')}")
            print("Connection successful!")
            sys.exit(0)

    except requests.exceptions.HTTPError as e:
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
