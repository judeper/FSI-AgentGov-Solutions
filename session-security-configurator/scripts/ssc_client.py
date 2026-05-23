#!/usr/bin/env python3
"""
Dataverse Web API client for Session Security Configurator.

Uses MSAL for interactive / client-secret authentication and Azure Identity
for managed identity, workload identity federation, and certificate
authentication. Also supports passthrough of a pre-acquired access token
(e.g., from a parent Azure Automation runbook that already obtained one
via system-assigned managed identity). Includes retry logic and dry-run
mode for safe deployments.

Auth-mode priority (Council review M-02, v1.3.0):
    1. access_token (parent process already acquired a Dataverse token)
    2. managed-identity (Azure-hosted runners, runbooks)
    3. workload-identity (GitHub Actions OIDC -> Entra app)
    4. certificate (CI / unattended)
    5. interactive (admin workstation)
    6. client-secret (dev-only legacy; replace with managed identity in production)
"""

import argparse
import os
import sys
from typing import Optional
from urllib.parse import urljoin

import msal
import requests
from requests.adapters import HTTPAdapter, Retry


class SSCClient:
    """Dataverse Web API client with MSAL / Azure Identity authentication and retry logic."""

    API_VERSION = "v9.2"

    SUPPORTED_AUTH_MODES = (
        "interactive",
        "client-secret",
        "managed-identity",
        "workload-identity",
        "certificate",
    )

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
        Initialize SSC client.

        Args:
            tenant_id: Entra ID tenant ID (optional when access_token is supplied
                or when using system-assigned managed identity).
            environment_url: Dataverse environment URL (e.g., https://org.crm.dynamics.com).
            client_id: Application (client) ID. Required for interactive,
                client-secret, workload-identity, and certificate modes; optional
                for system-assigned managed identity (omit to use the runner's
                system-assigned identity).
            client_secret: Client secret (legacy dev-only fallback; required only
                for the client-secret auth mode).
            access_token: Externally-acquired Dataverse bearer token. Takes
                precedence over all other auth modes when provided.
            interactive: Convenience flag equivalent to auth_mode="interactive".
            dry_run: If True, log API calls without executing them.
            auth_mode: One of "interactive", "client-secret", "managed-identity",
                "workload-identity", "certificate". Ignored when access_token is
                supplied. Defaults to "interactive" if interactive=True, else
                "client-secret" (for backward compatibility with the v1.2.0 CLI).
            certificate_path: Path to PEM/PFX certificate for certificate auth.
            certificate_password: Optional certificate password.
        """
        self.tenant_id = tenant_id
        self.client_id = client_id
        self.client_secret = client_secret
        self.access_token = access_token
        self.certificate_path = certificate_path
        self.certificate_password = certificate_password
        self.environment_url = environment_url.rstrip("/")
        self.api_url = f"{self.environment_url}/api/data/{self.API_VERSION}/"
        self.interactive = interactive
        self.dry_run = dry_run

        # Resolve effective auth_mode. Explicit interactive=True wins for
        # backward compatibility with existing deploy.py callers that pass
        # interactive=True without setting auth_mode.
        if interactive:
            self.auth_mode = "interactive"
        else:
            self.auth_mode = auth_mode or "client-secret"

        if self.auth_mode not in self.SUPPORTED_AUTH_MODES:
            raise ValueError(
                f"Unsupported auth_mode: {self.auth_mode!r}. "
                f"Choose one of {', '.join(self.SUPPORTED_AUTH_MODES)}."
            )

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

        if not self.environment_url.startswith("https://"):
            raise ValueError(
                f"environment_url must use HTTPS scheme, got: {self.environment_url}"
            )

        self._credential = None
        self._app = None

        if self.access_token:
            # Externally acquired token; no MSAL or azure-identity client needed.
            return

        if self.auth_mode == "interactive":
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
            # legacy: dev-only — replace with managed identity in production
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
            self._credential = (
                ManagedIdentityCredential(client_id=client_id)
                if client_id
                else ManagedIdentityCredential()
            )
        elif self.auth_mode == "workload-identity":
            if not tenant_id or not client_id:
                raise ValueError(
                    "tenant_id and client_id are required for workload-identity auth."
                )
            WorkloadIdentityCredential = self._azure_identity_class("WorkloadIdentityCredential")
            self._credential = WorkloadIdentityCredential(
                tenant_id=tenant_id,
                client_id=client_id,
            )
        elif self.auth_mode == "certificate":
            if not tenant_id or not client_id or not certificate_path:
                raise ValueError(
                    "tenant_id, client_id, and certificate_path are required for certificate auth."
                )
            CertificateCredential = self._azure_identity_class("CertificateCredential")
            self._credential = CertificateCredential(
                tenant_id=tenant_id,
                client_id=client_id,
                certificate_path=certificate_path,
                password=certificate_password,
            )

    @staticmethod
    def _azure_identity_class(class_name: str):
        """Lazily import azure.identity so installs without it can still use MSAL modes."""
        try:
            import azure.identity as azure_identity  # type: ignore
        except ImportError as exc:  # pragma: no cover - depends on optional runtime package
            raise RuntimeError(
                "azure-identity is required for managed-identity, workload-identity, or "
                "certificate auth. Install it with: pip install azure-identity"
            ) from exc
        return getattr(azure_identity, class_name)

    def _get_token(self) -> str:
        if self.access_token:
            return self.access_token

        if self._credential is not None:
            # azure-identity returns AccessToken(token=..., expires_on=...)
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
        if select:
            params["$select"] = ",".join(select)
        if filter_expr:
            params["$filter"] = filter_expr
        if orderby:
            params["$orderby"] = orderby
        if top:
            params["$top"] = str(top)
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
            if response.status_code == 404:
                return None
            response.raise_for_status()
            return response.json()
        except requests.HTTPError as e:
            if e.response.status_code == 404:
                return None
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
            if get_response.ok:
                return get_response.json()
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
            if response.status_code == 404:
                return None
            response.raise_for_status()
            return response.json()
        except requests.HTTPError as e:
            if e.response.status_code == 404:
                return None
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
            if response.status_code == 404:
                return None
            response.raise_for_status()
            return response.json()
        except requests.HTTPError as e:
            if e.response.status_code == 404:
                return None
            raise

    def check_table_exists(self, logical_name):
        return self.get_entity_metadata(logical_name) is not None

    def create_table(self, table_metadata):
        schema_name = table_metadata.get("SchemaName", "")
        logical_name = schema_name.lower()
        if self.check_table_exists(logical_name):
            return None
        return self.create_entity(table_metadata)

    def create_option_set(self, optionset_metadata):
        name = optionset_metadata.get("Name", "")
        if self.get_global_optionset(name):
            return None
        return self.create_global_optionset(optionset_metadata)

    def create_column(self, entity_logical_name, column_metadata):
        schema_name = column_metadata.get("SchemaName", "")
        col_logical_name = schema_name.lower()
        if self.get_attribute_metadata(entity_logical_name, col_logical_name):
            return None
        return self.create_attribute(entity_logical_name, column_metadata)


def main() -> None:
    parser = argparse.ArgumentParser(description="Dataverse Web API client for Session Security Configurator", formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--tenant-id", default=os.environ.get("SSC_TENANT_ID"), help="Entra ID tenant ID (or set SSC_TENANT_ID env var); optional when --access-token or system-assigned managed identity is used")
    parser.add_argument("--client-id", default=os.environ.get("SSC_CLIENT_ID"), help="Application (client) ID (or set SSC_CLIENT_ID env var); optional for system-assigned managed identity")
    parser.add_argument("--client-secret", default=os.environ.get("SSC_CLIENT_SECRET"), help="Client secret (or set SSC_CLIENT_SECRET env var). WARNING: legacy dev-only path; prefer --auth-mode managed-identity or workload-identity in production")
    parser.add_argument("--environment-url", default=os.environ.get("SSC_ENVIRONMENT_URL"), help="Dataverse environment URL (or set SSC_ENVIRONMENT_URL env var)")
    parser.add_argument("--interactive", action="store_true", help="Use interactive browser authentication (equivalent to --auth-mode interactive)")
    parser.add_argument(
        "--auth-mode",
        choices=list(SSCClient.SUPPORTED_AUTH_MODES),
        default=os.environ.get("SSC_AUTH_MODE"),
        help="Authentication mode. Defaults to 'interactive' if --interactive is set, otherwise 'client-secret' for backward compatibility. Set SSC_AUTH_MODE env var to override.",
    )
    parser.add_argument("--access-token", default=os.environ.get("SSC_ACCESS_TOKEN"), help="Pre-acquired Dataverse bearer token (e.g. from a parent runbook). Takes precedence over all other auth modes.")
    parser.add_argument("--certificate-path", default=os.environ.get("SSC_CERTIFICATE_PATH"), help="Path to certificate (PEM/PFX) for --auth-mode certificate.")
    parser.add_argument("--certificate-password", default=os.environ.get("SSC_CERTIFICATE_PASSWORD"), help="Optional password for the certificate file.")
    parser.add_argument("--test-connection", action="store_true", help="Test connection to Dataverse")
    parser.add_argument("--dry-run", action="store_true", help="Log API calls without executing them")
    args = parser.parse_args()

    if not args.environment_url:
        parser.error("--environment-url (or SSC_ENVIRONMENT_URL) is required")

    # Resolve effective auth mode for validation
    if args.access_token:
        effective_mode = "access-token"
    elif args.interactive:
        effective_mode = "interactive"
    else:
        effective_mode = args.auth_mode or "client-secret"

    # Per-mode argument validation
    if effective_mode == "client-secret":
        if not args.tenant_id:
            parser.error("--tenant-id is required for client-secret auth (or set SSC_TENANT_ID)")
        if not args.client_id:
            parser.error("--client-id is required for client-secret auth (or set SSC_CLIENT_ID)")
    elif effective_mode == "interactive":
        if not args.tenant_id:
            parser.error("--tenant-id is required for interactive auth (or set SSC_TENANT_ID)")
        if not args.client_id:
            parser.error("--client-id is required for interactive auth (or set SSC_CLIENT_ID)")
    elif effective_mode == "workload-identity":
        if not args.tenant_id or not args.client_id:
            parser.error("--tenant-id and --client-id are required for workload-identity auth")
    elif effective_mode == "certificate":
        if not args.tenant_id or not args.client_id or not args.certificate_path:
            parser.error("--tenant-id, --client-id, and --certificate-path are required for certificate auth")
    elif effective_mode == "managed-identity":
        # client_id is optional (omit for system-assigned identity)
        pass
    # access-token requires no other args beyond environment-url

    client_secret = args.client_secret
    if effective_mode == "client-secret" and not client_secret:
        import getpass
        client_secret = getpass.getpass("Client secret: ")

    try:
        client = SSCClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            access_token=args.access_token,
            interactive=args.interactive,
            dry_run=args.dry_run,
            auth_mode=args.auth_mode,
            certificate_path=args.certificate_path,
            certificate_password=args.certificate_password,
        )
        if args.test_connection:
            print("Testing Dataverse connection...")
            org = client.test_connection()
            if not args.dry_run:
                print("  Token acquired: OK")
                print("  API accessible: OK")
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
