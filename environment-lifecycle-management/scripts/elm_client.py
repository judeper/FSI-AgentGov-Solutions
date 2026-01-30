#!/usr/bin/env python3
"""
Dataverse Web API client for Environment Lifecycle Management.

Uses MSAL Confidential Client for app-only authentication.
"""

import argparse
import json
import os
import sys
from typing import Any, Optional
from urllib.parse import urljoin

import msal
import requests


class ELMClient:
    """Dataverse Web API client with MSAL authentication."""

    def __init__(
        self,
        tenant_id: str,
        environment_url: str,
        client_id: Optional[str] = None,
        client_secret: Optional[str] = None,
        interactive: bool = False,
    ):
        """
        Initialize ELM client.

        Args:
            tenant_id: Entra ID tenant ID
            environment_url: Dataverse environment URL (e.g., https://org.crm.dynamics.com)
            client_id: Application (client) ID (required for SP auth)
            client_secret: Client secret value (required for SP auth)
            interactive: Use interactive browser auth instead of SP
        """
        self.tenant_id = tenant_id
        self.client_id = client_id
        self.client_secret = client_secret
        self.environment_url = environment_url.rstrip("/")
        self.api_url = f"{self.environment_url}/api/data/v9.2/"
        self.interactive = interactive

        # Dataverse requires the environment URL as the scope
        self._scope = [f"{self.environment_url}/.default"]
        self._token: Optional[dict] = None

        if interactive:
            # Public client for interactive auth
            self._app = msal.PublicClientApplication(
                client_id=client_id or "51f81489-12ee-4a9e-aaae-a2591f45987d",  # Well-known Power Platform CLI ID
                authority=f"https://login.microsoftonline.com/{tenant_id}",
            )
        else:
            # Confidential client for service-to-service auth
            if not client_id or not client_secret:
                raise ValueError("client_id and client_secret required for non-interactive auth")
            self._app = msal.ConfidentialClientApplication(
                client_id=client_id,
                client_credential=client_secret,
                authority=f"https://login.microsoftonline.com/{tenant_id}",
            )

    def _get_token(self) -> str:
        """Acquire access token with caching."""
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
                # Client credentials flow
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
        response = requests.get(
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
            entity_set: Entity set name (e.g., "fsi_environmentrequests")
            select: Columns to select
            filter_expr: OData filter expression
            orderby: Order by expression
            top: Maximum records to return

        Returns:
            List of records
        """
        params = {}
        if select:
            params["$select"] = ",".join(select)
        if filter_expr:
            params["$filter"] = filter_expr
        if orderby:
            params["$orderby"] = orderby
        if top:
            params["$top"] = str(top)

        response = requests.get(
            urljoin(self.api_url, entity_set),
            headers=self._get_headers(),
            params=params,
        )
        response.raise_for_status()
        return response.json().get("value", [])

    def query_fetchxml(self, entity_set: str, fetchxml: str) -> list[dict]:
        """
        Query Dataverse using FetchXML.

        Args:
            entity_set: Entity set name (e.g., "fsi_environmentrequests")
                        Note: Dataverse entity set names don't follow simple
                        pluralization rules. Always provide the exact entity
                        set name (typically logical name + 's' or 'es').
            fetchxml: FetchXML query string

        Returns:
            List of records
        """
        response = requests.get(
            urljoin(self.api_url, entity_set),
            headers=self._get_headers(),
            params={"fetchXml": fetchxml},
        )
        response.raise_for_status()
        return response.json().get("value", [])

    def create(self, entity_set: str, data: dict) -> str:
        """
        Create a record in Dataverse.

        Args:
            entity_set: Entity set name
            data: Record data

        Returns:
            Created record ID
        """
        response = requests.post(
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

    def update(self, entity_set: str, record_id: str, data: dict) -> None:
        """
        Update a record in Dataverse.

        Args:
            entity_set: Entity set name
            record_id: Record GUID
            data: Fields to update
        """
        response = requests.patch(
            urljoin(self.api_url, f"{entity_set}({record_id})"),
            headers=self._get_headers(),
            json=data,
        )
        response.raise_for_status()

    def get(self, entity_set: str, record_id: str, select: Optional[list[str]] = None) -> dict:
        """
        Get a single record by ID.

        Args:
            entity_set: Entity set name
            record_id: Record GUID
            select: Columns to select

        Returns:
            Record data
        """
        params = {}
        if select:
            params["$select"] = ",".join(select)

        response = requests.get(
            urljoin(self.api_url, f"{entity_set}({record_id})"),
            headers=self._get_headers(),
            params=params,
        )
        response.raise_for_status()
        return response.json()

    def query_audit(
        self,
        object_type_code: str,
        operations: Optional[list[int]] = None,
        start_date: Optional[str] = None,
        end_date: Optional[str] = None,
    ) -> list[dict]:
        """
        Query audit log for specific entity.

        Args:
            object_type_code: Entity type code or logical name
            operations: List of operation codes (1=Create, 2=Update, 3=Delete)
            start_date: ISO date string for start of range
            end_date: ISO date string for end of range

        Returns:
            List of audit records
        """
        filters = [f"objecttypecode eq '{object_type_code}'"]

        if operations:
            op_filter = " or ".join([f"operation eq {op}" for op in operations])
            filters.append(f"({op_filter})")

        if start_date:
            filters.append(f"createdon ge {start_date}")
        if end_date:
            filters.append(f"createdon le {end_date}")

        return self.query(
            "audits",
            select=["auditid", "createdon", "_userid_value", "operation", "_objectid_value"],
            filter_expr=" and ".join(filters),
            orderby="createdon desc",
        )

    # =========================================================================
    # Metadata Operations (for schema deployment)
    # =========================================================================

    def get_entity_metadata(self, logical_name: str) -> Optional[dict]:
        """
        Get entity metadata by logical name.

        Args:
            logical_name: Entity logical name (e.g., fsi_environmentrequest)

        Returns:
            Entity metadata dict or None if not found
        """
        try:
            response = requests.get(
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
        response = requests.post(
            urljoin(self.api_url, "EntityDefinitions"),
            headers=self._get_headers(),
            json=entity_metadata,
        )
        response.raise_for_status()

        # Get the created entity
        entity_id = response.headers.get("OData-EntityId", "")
        if entity_id:
            get_response = requests.get(entity_id, headers=self._get_headers())
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
        response = requests.post(
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
        try:
            response = requests.get(
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
        response = requests.post(
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
        try:
            response = requests.get(
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

    def get_roles(self, filter_expr: Optional[str] = None) -> list[dict]:
        """
        Get security roles.

        Args:
            filter_expr: OData filter expression

        Returns:
            List of security roles
        """
        return self.query("roles", filter_expr=filter_expr)

    def create_role(self, role_data: dict) -> str:
        """
        Create a security role.

        Args:
            role_data: Role definition

        Returns:
            Created role ID
        """
        return self.create("roles", role_data)

    def get_privileges(self, filter_expr: Optional[str] = None) -> list[dict]:
        """
        Get system privileges.

        Args:
            filter_expr: OData filter expression

        Returns:
            List of privileges
        """
        return self.query("privileges", filter_expr=filter_expr)

    def add_role_privilege(self, role_id: str, privilege_id: str, depth: int) -> None:
        """
        Add a privilege to a role.

        Args:
            role_id: Role GUID
            privilege_id: Privilege GUID
            depth: Privilege depth (1=User, 2=BU, 4=Parent:Child, 8=Org)
        """
        response = requests.post(
            urljoin(self.api_url, "AddPrivilegesRole"),
            headers=self._get_headers(),
            json={
                "RoleId": role_id,
                "Privileges": [{"PrivilegeId": privilege_id, "Depth": depth}],
            },
        )
        response.raise_for_status()

    def get_role_privileges(self, role_id: str) -> list[dict]:
        """
        Get privileges assigned to a role.

        Args:
            role_id: Role GUID

        Returns:
            List of role privileges
        """
        return self.query(
            f"roles({role_id})/roleprivileges_association",
            select=["privilegeid", "name"],
        )

    def create_saved_query(self, query_data: dict) -> str:
        """
        Create a saved query (view).

        Args:
            query_data: SavedQuery definition

        Returns:
            Created query ID
        """
        return self.create("savedqueries", query_data)

    def get_saved_queries(
        self, entity_logical_name: str, filter_expr: Optional[str] = None
    ) -> list[dict]:
        """
        Get saved queries for an entity.

        Args:
            entity_logical_name: Entity logical name
            filter_expr: Additional OData filter

        Returns:
            List of saved queries
        """
        base_filter = f"returnedtypecode eq '{entity_logical_name}'"
        if filter_expr:
            base_filter = f"{base_filter} and {filter_expr}"
        return self.query("savedqueries", filter_expr=base_filter)

    def create_workflow(self, workflow_data: dict) -> str:
        """
        Create a workflow (business rule).

        Args:
            workflow_data: Workflow definition

        Returns:
            Created workflow ID
        """
        return self.create("workflows", workflow_data)

    def get_workflows(
        self, entity_logical_name: str, category: int = 2
    ) -> list[dict]:
        """
        Get workflows for an entity.

        Args:
            entity_logical_name: Entity logical name
            category: Workflow category (2=Business Rule)

        Returns:
            List of workflows
        """
        return self.query(
            "workflows",
            filter_expr=f"primaryentity eq '{entity_logical_name}' and category eq {category}",
        )

    def create_field_security_profile(self, profile_data: dict) -> str:
        """
        Create a field security profile.

        Args:
            profile_data: FieldSecurityProfile definition

        Returns:
            Created profile ID
        """
        return self.create("fieldsecurityprofiles", profile_data)

    def get_field_security_profiles(self, filter_expr: Optional[str] = None) -> list[dict]:
        """
        Get field security profiles.

        Args:
            filter_expr: OData filter expression

        Returns:
            List of field security profiles
        """
        return self.query("fieldsecurityprofiles", filter_expr=filter_expr)

    def create_field_permission(self, permission_data: dict) -> str:
        """
        Create a field permission.

        Args:
            permission_data: FieldPermission definition

        Returns:
            Created permission ID
        """
        return self.create("fieldpermissions", permission_data)

    def get_solution_publisher(self, prefix: str) -> Optional[dict]:
        """
        Get solution publisher by prefix.

        Args:
            prefix: Publisher prefix (e.g., 'fsi')

        Returns:
            Publisher metadata or None if not found
        """
        publishers = self.query(
            "publishers",
            filter_expr=f"customizationprefix eq '{prefix}'",
            select=["publisherid", "uniquename", "customizationprefix"],
        )
        return publishers[0] if publishers else None

    def get_root_business_unit(self) -> dict:
        """
        Get the root business unit.

        Returns:
            Root business unit record
        """
        units = self.query(
            "businessunits",
            filter_expr="parentbusinessunitid eq null",
            select=["businessunitid", "name"],
        )
        if not units:
            raise RuntimeError("No root business unit found")
        return units[0]


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Dataverse Web API client for ELM",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ELM_TENANT_ID"),
        help="Entra ID tenant ID (or set ELM_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ELM_CLIENT_ID"),
        help="Application (client) ID (or set ELM_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("ELM_CLIENT_SECRET"),
        help="Client secret (or set ELM_CLIENT_SECRET env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ELM_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set ELM_ENVIRONMENT_URL env var)",
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser authentication",
    )
    parser.add_argument(
        "--test-connection",
        action="store_true",
        help="Test connection to Dataverse",
    )

    args = parser.parse_args()

    # Validate required arguments
    if not args.tenant_id or not args.environment_url:
        parser.error(
            "Missing required arguments. Provide --tenant-id and --environment-url "
            "(or set ELM_TENANT_ID and ELM_ENVIRONMENT_URL env vars)"
        )

    # For non-interactive mode, need client credentials
    client_secret = args.client_secret
    if not args.interactive:
        if not args.client_id:
            parser.error("--client-id required for non-interactive authentication")
        if not client_secret:
            import getpass
            client_secret = getpass.getpass("Client secret: ")

    try:
        client = ELMClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            interactive=args.interactive,
        )

        if args.test_connection:
            print("Testing Dataverse connection...")
            org = client.test_connection()
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
