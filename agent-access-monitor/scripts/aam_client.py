#!/usr/bin/env python3
"""
Dataverse Web API client for Agent Access Governance Monitor.

Uses Azure Identity for managed identity/workload identity and MSAL for interactive
or legacy dev-only client secret authentication. Includes retry logic and dry-run mode
for safe deployments.
"""

import argparse
import os
import sys
from typing import Optional
from urllib.parse import urljoin

import msal
import requests
from requests.adapters import HTTPAdapter, Retry


def _azure_identity_class(class_name: str):
    """Lazy import an azure.identity credential class.

    Mirrors the shared scripts/shared/dataverse_client.py pattern so the
    module can be imported even when azure-identity is not installed
    (e.g., when only --access-token or legacy client-secret auth is used).
    """
    try:
        import azure.identity as azure_identity  # type: ignore
    except ImportError as exc:  # pragma: no cover - depends on optional runtime package
        raise RuntimeError(
            "azure-identity is required for managed identity or workload identity auth. "
            "Install the solution requirements first (pip install -r requirements.txt)."
        ) from exc
    return getattr(azure_identity, class_name)


def _client_authentication_error_cls():
    """Lazy import ClientAuthenticationError from azure.core.exceptions."""
    try:
        from azure.core.exceptions import ClientAuthenticationError  # type: ignore
    except ImportError as exc:  # pragma: no cover - depends on optional runtime package
        raise RuntimeError(
            "azure-core is required for managed identity or workload identity auth. "
            "Install the solution requirements first (pip install -r requirements.txt)."
        ) from exc
    return ClientAuthenticationError


class AAMClient:
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
        managed_identity: bool = False,
        managed_identity_client_id: Optional[str] = None,
        workload_identity: bool = False,
    ):
        """
        Initialize AAM client.

        Args:
            tenant_id: Entra ID tenant ID
            environment_url: Dataverse environment URL (e.g., https://org.crm.dynamics.com)
            client_id: Application (client) ID for interactive, workload identity, or legacy fallback
            client_secret: Client secret value (legacy dev-only fallback)
            interactive: Use interactive browser auth instead of unattended auth
            dry_run: If True, log API calls without executing them
            managed_identity: Use system-assigned managed identity
            managed_identity_client_id: User-assigned managed identity client ID
            workload_identity: Use workload identity federation
        """
        self.tenant_id = tenant_id
        self.client_id = client_id
        self.client_secret = client_secret
        self.environment_url = environment_url.rstrip("/")
        self.api_url = f"{self.environment_url}/api/data/{self.API_VERSION}/"
        self.interactive = interactive
        self.dry_run = dry_run
        self._azure_credential = None

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

        if interactive:
            # Public client for interactive auth
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
            if managed_identity or managed_identity_client_id:
                # Managed identity is preferred for Azure-hosted automation.
                credential_kwargs = {}
                if managed_identity_client_id:
                    credential_kwargs["client_id"] = managed_identity_client_id
                ManagedIdentityCredential = _azure_identity_class("ManagedIdentityCredential")
                self._azure_credential = ManagedIdentityCredential(**credential_kwargs)
                self._app = None
            elif workload_identity:
                if not client_id:
                    raise ValueError("client_id is required for workload identity authentication")
                WorkloadIdentityCredential = _azure_identity_class("WorkloadIdentityCredential")
                self._azure_credential = WorkloadIdentityCredential(
                    tenant_id=tenant_id,
                    client_id=client_id,
                )
                self._app = None
            else:
                # legacy: dev-only — replace with managed identity in production
                if not client_id or not client_secret:
                    raise ValueError(
                        "non-interactive auth requires --managed-identity, "
                        "--managed-identity-client-id, --workload-identity, or legacy "
                        "client_id/client_secret credentials"
                    )
                self._app = msal.ConfidentialClientApplication(
                    client_id=client_id,
                    client_credential=client_secret,
                    authority=f"https://login.microsoftonline.com/{tenant_id}",
                )

    def _get_token(self) -> str:
        """Acquire access token with caching."""
        if self._azure_credential is not None:
            ClientAuthenticationError = _client_authentication_error_cls()
            try:
                access_token = self._azure_credential.get_token(self._scope[0])
            except ClientAuthenticationError as exc:
                raise RuntimeError(f"Failed to acquire token: {exc.message}") from exc
            return access_token.token

        # Try to get cached token first
        accounts = self._app.get_accounts() if self.interactive else None
        result = self._app.acquire_token_silent(
            scopes=self._scope,
            account=accounts[0] if accounts else None,
        )

        if not result:
            if self.interactive:
                # Interactive browser flow
                result = self._app.acquire_token_interactive(scopes=self._scope)
            else:
                # legacy: dev-only — replace with managed identity in production
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
        """
        Test connection to Dataverse.

        Returns:
            Organization information if successful
        """
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

    def query(
        self,
        entity_set: str,
        select: Optional[list[str]] = None,
        filter_expr: Optional[str] = None,
        orderby: Optional[str] = None,
        top: Optional[int] = None,
    ) -> list[dict]:
        """
        Query Dataverse table using OData.

        Args:
            entity_set: Entity set name (e.g., "fsi_accessbaselines")
            select: Columns to select
            filter_expr: OData filter expression
            orderby: Order by expression
            top: Maximum records to return

        Returns:
            List of records
        """
        if self.dry_run:
            print(f"  [DRY RUN] Would query: {entity_set}")
            return []

        params = {}
        if select:
            params["$select"] = ",".join(select)
        if filter_expr:
            params["$filter"] = filter_expr
        if orderby:
            params["$orderby"] = orderby
        if top:
            params["$top"] = str(top)

        all_records: list[dict] = []
        url = urljoin(self.api_url, entity_set)
        while url:
            response = self._session.get(
                url,
                headers=self._get_headers(),
                params=params,
            )
            response.raise_for_status()
            data = response.json()
            all_records.extend(data.get("value", []))
            url = data.get("@odata.nextLink")
            params = {}  # nextLink includes query params
        return all_records

    def create_record(self, entity_set: str, data: dict) -> str:
        """
        Create a record in Dataverse.

        Args:
            entity_set: Entity set name
            data: Record data

        Returns:
            Created record ID
        """
        if self.dry_run:
            print(f"  [DRY RUN] Would create record in: {entity_set}")
            return "00000000-0000-0000-0000-000000000000"

        response = self._session.post(
            urljoin(self.api_url, entity_set),
            headers=self._get_headers(),
            json=data,
        )
        response.raise_for_status()

        # Extract ID from OData-EntityId header
        entity_id = response.headers.get("OData-EntityId", "")
        if "(" in entity_id and ")" in entity_id:
            return entity_id.split("(")[1].split(")")[0]
        return ""

    # =========================================================================
    # Metadata Operations (for schema deployment)
    # =========================================================================

    def get_entity_metadata(self, logical_name: str) -> Optional[dict]:
        """
        Get entity metadata by logical name.

        Args:
            logical_name: Entity logical name (e.g., fsi_accessbaseline)

        Returns:
            Entity metadata dict or None if not found
        """
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
        """
        Create a new entity (table).

        Args:
            entity_metadata: Entity definition per Dataverse Web API spec

        Returns:
            Created entity metadata
        """
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

        # Get the created entity
        entity_id = response.headers.get("OData-EntityId", "")
        if entity_id:
            get_response = self._session.get(entity_id, headers=self._get_headers())
            if get_response.ok:
                return get_response.json()
        return {"LogicalName": entity_metadata.get("SchemaName", "").lower()}

    def create_attribute(self, entity_logical_name: str, attribute_metadata: dict) -> dict:
        """
        Create a new attribute (column) on an entity.

        Args:
            entity_logical_name: Entity logical name
            attribute_metadata: Attribute definition per Dataverse Web API spec

        Returns:
            Created attribute metadata
        """
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
        """
        Get attribute metadata.

        Args:
            entity_logical_name: Entity logical name
            attribute_logical_name: Attribute logical name

        Returns:
            Attribute metadata or None if not found
        """
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
        """
        Create a global option set (choice).

        Args:
            optionset_metadata: OptionSet definition

        Returns:
            Created optionset metadata
        """
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
        """
        Get global option set by name.

        Args:
            name: OptionSet name

        Returns:
            OptionSet metadata or None if not found
        """
        if self.dry_run:
            print(f"  [DRY RUN] Would check option set: {name}")
            return None

        # Dataverse normalises the OptionSet Name to lowercase (matching the
        # logical-name convention). The lookup-by-Name is case-sensitive, so
        # querying with the SchemaName casing (e.g. "fsi_ACV_Zone") 404s even
        # when the option set exists, then the subsequent create POST returns
        # 400 SchemaNameisNotUnique. Always lowercase the name for the
        # existence probe. Mirrors scripts/shared/dataverse_client.py.
        lookup_name = name.lower()

        try:
            response = self._session.get(
                urljoin(self.api_url, f"GlobalOptionSetDefinitions(Name='{lookup_name}')"),
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
    # Helper Methods for Idempotent Deployment
    # =========================================================================

    def check_table_exists(self, logical_name: str) -> bool:
        """
        Check if a table exists.

        Args:
            logical_name: Table logical name

        Returns:
            True if table exists, False otherwise
        """
        metadata = self.get_entity_metadata(logical_name)
        return metadata is not None

    def create_table(self, table_metadata: dict) -> Optional[dict]:
        """
        Create a table if it doesn't already exist (idempotent).

        Args:
            table_metadata: Table definition

        Returns:
            Created table metadata or None if already exists
        """
        schema_name = table_metadata.get("SchemaName", "")
        logical_name = schema_name.lower()

        if self.check_table_exists(logical_name):
            return None

        return self.create_entity(table_metadata)

    def create_option_set(self, optionset_metadata: dict) -> Optional[dict]:
        """
        Create an option set if it doesn't already exist (idempotent).

        Args:
            optionset_metadata: Option set definition

        Returns:
            Created option set metadata or None if already exists
        """
        name = optionset_metadata.get("Name", "")

        if self.get_global_optionset(name):
            return None

        return self.create_global_optionset(optionset_metadata)

    def create_column(
        self, entity_logical_name: str, column_metadata: dict
    ) -> Optional[dict]:
        """
        Create a column if it doesn't already exist (idempotent).

        Args:
            entity_logical_name: Entity logical name
            column_metadata: Column definition

        Returns:
            Created column metadata or None if already exists
        """
        schema_name = column_metadata.get("SchemaName", "")
        col_logical_name = schema_name.lower()

        if self.get_attribute_metadata(entity_logical_name, col_logical_name):
            return None

        return self.create_attribute(entity_logical_name, column_metadata)


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Dataverse Web API client for Agent Access Governance Monitor",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("AAM_TENANT_ID"),
        help="Entra ID tenant ID (or set AAM_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("AAM_CLIENT_ID"),
        help="Application (client) ID for interactive, workload identity, or legacy fallback (or set AAM_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("AAM_CLIENT_SECRET"),
        help="Client secret (legacy dev-only fallback; prefer managed identity, workload identity, or AAM_CLIENT_SECRET env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("AAM_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set AAM_ENVIRONMENT_URL env var)",
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser authentication",
    )
    parser.add_argument(
        "--managed-identity",
        action="store_true",
        help="Use system-assigned managed identity for unattended authentication",
    )
    parser.add_argument(
        "--managed-identity-client-id",
        default=os.environ.get("AAM_MANAGED_IDENTITY_CLIENT_ID"),
        help="User-assigned managed identity client ID (or set AAM_MANAGED_IDENTITY_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--workload-identity",
        action="store_true",
        help="Use workload identity federation for unattended authentication",
    )
    parser.add_argument(
        "--test-connection",
        action="store_true",
        help="Test connection to Dataverse",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Log API calls without executing them",
    )

    args = parser.parse_args()

    # Validate required arguments
    if not args.tenant_id or not args.environment_url:
        parser.error(
            "Missing required arguments. Provide --tenant-id and --environment-url "
            "(or set AAM_TENANT_ID and AAM_ENVIRONMENT_URL env vars)"
        )

    # For unattended auth, prefer managed identity or workload identity.
    client_secret = args.client_secret
    if args.interactive and not args.client_id:
        parser.error("--client-id is required with --interactive (or set AAM_CLIENT_ID env var)")
    if args.workload_identity and not args.client_id:
        parser.error("--client-id is required with --workload-identity")
    if not args.interactive and not (
        args.managed_identity
        or args.managed_identity_client_id
        or args.workload_identity
        or client_secret
    ):
        if args.client_id:
            import getpass

            # legacy: dev-only — replace with managed identity in production
            client_secret = getpass.getpass("Client secret (legacy dev-only): ")
        else:
            parser.error(
                "For unattended auth, use --managed-identity, --managed-identity-client-id, "
                "or --workload-identity. Client secrets are a legacy dev-only fallback."
            )
    if not args.interactive and client_secret and not args.client_id and not (
        args.managed_identity or args.managed_identity_client_id
    ):
        parser.error("--client-id is required with legacy client secret fallback")

    try:
        client = AAMClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            interactive=args.interactive,
            dry_run=args.dry_run,
            managed_identity=args.managed_identity,
            managed_identity_client_id=args.managed_identity_client_id,
            workload_identity=args.workload_identity,
        )

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
