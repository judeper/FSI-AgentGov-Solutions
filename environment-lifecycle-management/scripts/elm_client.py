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
        client_id: str,
        client_secret: str,
        environment_url: str,
    ):
        """
        Initialize ELM client.

        Args:
            tenant_id: Entra ID tenant ID
            client_id: Application (client) ID
            client_secret: Client secret value
            environment_url: Dataverse environment URL (e.g., https://org.crm.dynamics.com)
        """
        self.tenant_id = tenant_id
        self.client_id = client_id
        self.client_secret = client_secret
        self.environment_url = environment_url.rstrip("/")
        self.api_url = f"{self.environment_url}/api/data/v9.2/"

        # MSAL Confidential Client for service-to-service auth
        self._app = msal.ConfidentialClientApplication(
            client_id=client_id,
            client_credential=client_secret,
            authority=f"https://login.microsoftonline.com/{tenant_id}",
        )

        # Dataverse requires the environment URL as the scope
        self._scope = [f"{self.environment_url}/.default"]
        self._token: Optional[dict] = None

    def _get_token(self) -> str:
        """Acquire access token using client credentials flow with caching."""
        # Try to get cached token first
        result = self._app.acquire_token_silent(scopes=self._scope, account=None)

        if not result:
            # No cached token, acquire new one
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
        "--test-connection",
        action="store_true",
        help="Test connection to Dataverse",
    )

    args = parser.parse_args()

    # Validate required arguments
    if not all([args.tenant_id, args.client_id, args.environment_url]):
        parser.error(
            "Missing required arguments. Provide --tenant-id, --client-id, "
            "--client-secret, and --environment-url (or set environment variables)"
        )

    # Prompt for secret if not provided
    client_secret = args.client_secret
    if not client_secret:
        import getpass
        client_secret = getpass.getpass("Client secret: ")

    try:
        client = ELMClient(
            tenant_id=args.tenant_id,
            client_id=args.client_id,
            client_secret=client_secret,
            environment_url=args.environment_url,
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
