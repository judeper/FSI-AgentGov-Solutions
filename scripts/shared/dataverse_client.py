#!/usr/bin/env python3
"""
Shared Dataverse Web API client for FSI-AgentGov-Solutions.

Uses MSAL for interactive/client-secret authentication and Azure Identity for managed identity, workload identity federation, and certificate authentication. Includes retry logic and dry-run mode for safe deployments.
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


class DataverseClient:
    """Dataverse Web API client with MSAL authentication and retry logic."""

    API_VERSION = "v9.2"

    def __init__(
        self,
        tenant_id: Optional[str],
        environment_url: str,
        client_id: Optional[str] = None,
        client_secret: Optional[str] = None,
        access_token: Optional[str] = None,
        interactive: bool = False,
        dry_run: bool = False,
        auth_mode: Optional[str] = None,
        certificate_path: Optional[str] = None,
        certificate_password: Optional[str] = None,
    ):
        """
        Initialize Dataverse client.

        Args:
            tenant_id: Entra ID tenant ID (optional when access_token is supplied)
            environment_url: Dataverse environment URL (e.g., https://org.crm.dynamics.com)
            client_id: Application (client) ID; optional for system-assigned managed identity
            client_secret: Client secret value (legacy dev-only fallback)
            access_token: Externally-acquired Dataverse bearer token (e.g. from a parent
                process that already obtained one via managed identity or workload federation).
                Takes precedence over all other auth modes when provided.
            interactive: Use interactive browser auth instead of app-only auth
            dry_run: If True, log API calls without executing them
            auth_mode: interactive, managed-identity, workload-identity, certificate, or client-secret
                (ignored when access_token is supplied)
            certificate_path: Path to PEM/PFX certificate for certificate auth
            certificate_password: Optional certificate password
        """
        self.tenant_id = tenant_id
        self.client_id = client_id
        self.client_secret = client_secret
        self.access_token = access_token
        self.auth_mode = auth_mode or ("interactive" if interactive else "client-secret")
        if interactive:
            self.auth_mode = "interactive"
        self.certificate_path = certificate_path
        self.certificate_password = certificate_password
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

        self._credential = None
        self._app = None
        if self.access_token:
            # Externally acquired token; no MSAL or azure-identity client needed
            pass
        elif self.auth_mode == "interactive":
            if not client_id:
                raise ValueError(
                    "client_id is required for interactive authentication. "
                    "Register an app in Entra ID and provide --client-id."
                )
            self._app = msal.PublicClientApplication(
                client_id=client_id,
                authority=f"https://login.microsoftonline.com/{tenant_id}",
            )
        elif self.auth_mode == "client-secret":
            if not client_id or not client_secret:
                raise ValueError(
                    "client_id and client_secret are required for legacy client-secret auth. "
                    "Use --auth-mode managed-identity, workload-identity, or certificate in production."
                )
            self._app = msal.ConfidentialClientApplication(
                client_id=client_id,
                client_credential=client_secret,
                authority=f"https://login.microsoftonline.com/{tenant_id}",
            )
        elif self.auth_mode == "managed-identity":
            ManagedIdentityCredential = self._azure_identity_class("ManagedIdentityCredential")
            self._credential = ManagedIdentityCredential(client_id=client_id) if client_id else ManagedIdentityCredential()
            self._app = None
        elif self.auth_mode == "workload-identity":
            WorkloadIdentityCredential = self._azure_identity_class("WorkloadIdentityCredential")
            self._credential = WorkloadIdentityCredential(tenant_id=tenant_id, client_id=client_id)
            self._app = None
        elif self.auth_mode == "certificate":
            if not client_id or not certificate_path:
                raise ValueError("client_id and certificate_path are required for certificate auth")
            CertificateCredential = self._azure_identity_class("CertificateCredential")
            self._credential = CertificateCredential(
                tenant_id=tenant_id,
                client_id=client_id,
                certificate_path=certificate_path,
                password=certificate_password,
            )
            self._app = None
        else:
            raise ValueError(f"Unsupported auth_mode: {self.auth_mode}")

    @staticmethod
    def _azure_identity_class(class_name: str):
        try:
            import azure.identity as azure_identity  # type: ignore
        except ImportError as exc:  # pragma: no cover - depends on optional runtime package
            raise RuntimeError(
                "azure-identity is required for managed identity, workload identity, or certificate auth. "
                "Install the solution requirements first."
            ) from exc
        return getattr(azure_identity, class_name)

    def _get_token(self) -> str:
        if self.access_token:
            return self.access_token
        if self._credential is not None:
            return self._credential.get_token(self._scope[0]).token

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

    @staticmethod
    def _raise_for_status(response, context: str = "") -> None:
        """Raise an HTTPError that includes the Dataverse response body.

        requests.Response.raise_for_status only surfaces status + URL, which
        hides the actual Dataverse error code/message and makes 4xx failures
        opaque. This helper preserves the same exception type while including
        the server-side payload so callers see *why* a request was rejected.
        """
        if response.ok:
            return
        body = (response.text or "").strip()
        snippet = body[:2000] + ("... (truncated)" if len(body) > 2000 else "")
        msg = f"HTTP {response.status_code} {response.reason} for {response.request.method} {response.url}"
        if context:
            msg += f" [{context}]"
        if snippet:
            msg += f"\nResponse body: {snippet}"
        raise requests.HTTPError(msg, response=response)

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

    def update_record(self, entity_set: str, record_id: str, data: dict) -> None:
        """Update an existing record via PATCH. record_id is the row GUID."""
        if self.dry_run:
            print(f"  [DRY RUN] Would update record {entity_set}({record_id})")
            return
        url = urljoin(self.api_url, f"{entity_set}({record_id})")
        headers = self._get_headers()
        # If-Match: * required to prevent accidental upsert insertion when row missing
        headers["If-Match"] = "*"
        response = self._session.patch(url, headers=headers, json=data)
        response.raise_for_status()

    def delete_record(self, entity_set: str, record_id: str) -> None:
        """Delete a record from Dataverse.

        Args:
            entity_set: The entity set name (e.g., 'environmentvariabledefinitions')
            record_id: The GUID of the record to delete
        """
        if self.dry_run:
            print(f"  [DRY RUN] Would delete record from {entity_set}({record_id})")
            return
        url = urljoin(self.api_url, f"{entity_set}({record_id})")
        response = self._session.delete(url, headers=self._get_headers())
        response.raise_for_status()

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
        self._raise_for_status(response, context=f"create entity {entity_metadata.get('SchemaName', '?')}")
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
        self._raise_for_status(response, context=f"create attribute {entity_logical_name}.{attribute_metadata.get('SchemaName', '?')}")
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
        self._raise_for_status(response, context=f"create option set {optionset_metadata.get('Name', '?')}")
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

    def create_relationship(self, relationship_metadata):
        """Create a one-to-many relationship (and its lookup column)."""
        if self.dry_run:
            schema_name = relationship_metadata.get("SchemaName", "Unknown")
            print(f"  [DRY RUN] Would create relationship: {schema_name}")
            return None
        url = urljoin(self.api_url, "RelationshipDefinitions")
        response = self._session.post(url, headers=self._get_headers(), json=relationship_metadata)
        self._raise_for_status(response, context=f"create relationship {relationship_metadata.get('SchemaName', '?')}")
        return response.headers.get("OData-EntityId")

    def get_relationship(self, schema_name):
        """Check if a relationship exists by schema name."""
        if self.dry_run:
            print(f"  [DRY RUN] Would check relationship: {schema_name}")
            return None
        url = urljoin(self.api_url, f"RelationshipDefinitions?$filter=SchemaName eq '{schema_name}'")
        response = self._session.get(url, headers=self._get_headers())
        if response.status_code == 404:
            return None
        response.raise_for_status()
        data = response.json()
        return data.get("value", [None])[0] if data.get("value") else None


def main():
    parser = argparse.ArgumentParser(description="Shared Dataverse Web API client for FSI-AgentGov-Solutions", formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tenant-id", default=os.environ.get("DATAVERSE_TENANT_ID"), help="Entra ID tenant ID (or set DATAVERSE_TENANT_ID env var)")
    parser.add_argument("--client-id", default=os.environ.get("DATAVERSE_CLIENT_ID"), help="Application (client) ID (or set DATAVERSE_CLIENT_ID env var)")
    parser.add_argument("--client-secret", default=os.environ.get("DATAVERSE_CLIENT_SECRET"), help="Legacy dev-only client secret (or set DATAVERSE_CLIENT_SECRET env var)")
    parser.add_argument("--access-token", default=os.environ.get("DATAVERSE_ACCESS_TOKEN"), help="Externally-acquired Dataverse bearer token (managed identity / workload federation); takes precedence over other auth modes")
    parser.add_argument("--environment-url", default=os.environ.get("DATAVERSE_ENVIRONMENT_URL"), help="Dataverse environment URL (or set DATAVERSE_ENVIRONMENT_URL env var)")
    parser.add_argument("--interactive", action="store_true", help="Use interactive browser authentication")
    parser.add_argument("--auth-mode", choices=["interactive", "managed-identity", "workload-identity", "certificate", "client-secret"], default=os.environ.get("DATAVERSE_AUTH_MODE"), help="Authentication mode; prefer managed-identity, workload-identity, or certificate for automation")
    parser.add_argument("--certificate-path", default=os.environ.get("DATAVERSE_CERTIFICATE_PATH"), help="Certificate path for certificate auth")
    parser.add_argument("--certificate-password-env", default="DATAVERSE_CERTIFICATE_PASSWORD", help="Environment variable containing certificate password")
    parser.add_argument("--test-connection", action="store_true", help="Test connection to Dataverse")
    parser.add_argument("--dry-run", action="store_true", help="Log API calls without executing them")
    args = parser.parse_args()
    if not args.environment_url:
        parser.error("Missing required argument. Provide --environment-url (or set DATAVERSE_ENVIRONMENT_URL env var)")
    if not args.access_token and not args.tenant_id:
        parser.error("--tenant-id is required unless --access-token is provided (or set DATAVERSE_TENANT_ID)")
    auth_mode = "interactive" if args.interactive else (args.auth_mode or ("client-secret" if args.client_secret else "managed-identity"))
    if not args.access_token and auth_mode in {"interactive", "workload-identity", "certificate", "client-secret"} and not args.client_id:
        parser.error("--client-id is required for the selected auth mode (or set DATAVERSE_CLIENT_ID env var)")
    client_secret = args.client_secret
    # legacy: dev-only — replace with managed identity, workload identity federation, or certificate auth in production
    if not args.access_token and auth_mode == "client-secret" and not client_secret:
        import getpass
        client_secret = getpass.getpass("Client secret: ")
    certificate_password = os.environ.get(args.certificate_password_env) if args.certificate_password_env else None
    try:
        client = DataverseClient(tenant_id=args.tenant_id, environment_url=args.environment_url, client_id=args.client_id, client_secret=client_secret, access_token=args.access_token, interactive=args.interactive, dry_run=args.dry_run, auth_mode=auth_mode, certificate_path=args.certificate_path, certificate_password=certificate_password)
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
