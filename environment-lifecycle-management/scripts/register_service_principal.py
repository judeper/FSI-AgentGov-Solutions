#!/usr/bin/env python3
"""
Register Service Principal for Environment Lifecycle Management.

Creates a Microsoft Entra app registration and stores credentials in Azure Key Vault.
Prefer managed identity, workload identity federation, or certificate-backed
authentication for production; client secrets are retained as a legacy
development fallback.
"""

import argparse
import os
import sys
from datetime import datetime, timedelta, timezone
from typing import Optional

try:
    from azure.identity import DefaultAzureCredential, InteractiveBrowserCredential
    from azure.keyvault.secrets import SecretClient
    import requests
    from requests.adapters import HTTPAdapter
    from urllib3.util.retry import Retry
except ImportError:
    print("Missing dependencies. Run: pip install -r requirements.txt", file=sys.stderr)
    sys.exit(4)


_GRAPH_SESSION: Optional[requests.Session] = None
GRAPH_RESOURCE_APP_ID = "00000003-0000-0000-c000-000000000000"
GRAPH_GROUP_READ_ALL_APP_ROLE_ID = "5b567255-7703-4780-807c-7be8301ae99b"


def _get_graph_session() -> requests.Session:
    """Return a process-wide HTTP session with retry logic for Graph API calls.

    POST is intentionally NOT in ``allowed_methods`` because Graph POST
    operations (create application, create service principal, add password)
    are non-idempotent — a retried POST after a transient 503 can produce
    duplicate apps/secrets.
    """
    global _GRAPH_SESSION
    if _GRAPH_SESSION is not None:
        return _GRAPH_SESSION
    session = requests.Session()
    retry_strategy = Retry(
        total=3,
        backoff_factor=1,
        status_forcelist=[429, 500, 502, 503, 504],
        allowed_methods=["GET"],
    )
    adapter = HTTPAdapter(max_retries=retry_strategy)
    session.mount("https://", adapter)
    _GRAPH_SESSION = session
    return session


def get_graph_token(credential) -> str:
    """Get access token for Microsoft Graph."""
    token = credential.get_token("https://graph.microsoft.com/.default")
    return token.token


def create_app_registration(
    token: str,
    app_name: str,
    tenant_id: str,
    dry_run: bool = False,
) -> dict:
    """
    Create Entra ID app registration.

    Args:
        token: Graph API access token
        app_name: Display name for the application
        tenant_id: Tenant ID
        dry_run: If True, don't create, just validate

    Returns:
        Application details including appId and id
    """
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }

    # Check if app already exists
    search_response = _get_graph_session().get(
        "https://graph.microsoft.com/v1.0/applications",
        headers=headers,
        params={"$filter": f"displayName eq '{app_name.replace(chr(39), chr(39)*2)}'"},
    )
    search_response.raise_for_status()
    existing = search_response.json().get("value", [])

    if existing:
        app = existing[0]
        print(f"  Application already exists: {app['appId']}")
        return app

    if dry_run:
        print(f"  [DRY RUN] Would create application: {app_name}")
        return {"appId": "dry-run-app-id", "id": "dry-run-object-id"}

    # Create new application with Graph app permission required by group validation.
    app_data = {
        "displayName": app_name,
        "signInAudience": "AzureADMyOrg",
        "requiredResourceAccess": [
            {
                "resourceAppId": GRAPH_RESOURCE_APP_ID,
                "resourceAccess": [
                    {
                        "id": GRAPH_GROUP_READ_ALL_APP_ROLE_ID,
                        "type": "Role",
                    }
                ],
            }
        ],
    }

    response = _get_graph_session().post(
        "https://graph.microsoft.com/v1.0/applications",
        headers=headers,
        json=app_data,
    )
    response.raise_for_status()
    app = response.json()

    print(f"  Application ID: {app['appId']}")
    print(f"  Object ID: {app['id']}")

    return app


def create_client_secret(
    token: str,
    app_object_id: str,
    expiry_days: int,
    dry_run: bool = False,
) -> dict:
    """
    Create client secret for application.

    Args:
        token: Graph API access token
        app_object_id: Application object ID (not appId)
        expiry_days: Days until secret expires
        dry_run: If True, don't create

    Returns:
        Secret details including secretText
    """
    # legacy: dev-only — replace with managed identity in production
    if dry_run:
        print(f"  [DRY RUN] Would create secret with {expiry_days}-day expiry")
        return {"secretText": "dry-run-secret", "keyId": "dry-run-key-id"}

    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }

    end_date = (datetime.now(timezone.utc) + timedelta(days=expiry_days)).isoformat().replace("+00:00", "Z")

    secret_data = {
        "passwordCredential": {
            "displayName": "ELM Provisioning Secret",
            "endDateTime": end_date,
        }
    }

    response = _get_graph_session().post(
        f"https://graph.microsoft.com/v1.0/applications/{app_object_id}/addPassword",
        headers=headers,
        json=secret_data,
    )
    response.raise_for_status()
    secret = response.json()

    expiry_date = datetime.fromisoformat(secret["endDateTime"].replace("Z", "+00:00"))
    print(f"  Secret ID: {secret['keyId']}")
    print(f"  Expiry: {expiry_date.strftime('%Y-%m-%d')} ({expiry_days} days)")

    return secret


def remove_existing_secrets(
    token: str,
    app_object_id: str,
    dry_run: bool = False,
) -> int:
    """
    Remove existing client secrets from application during rotation.

    Args:
        token: Graph API access token
        app_object_id: Application object ID (not appId)
        dry_run: If True, don't remove

    Returns:
        Number of secrets removed
    """
    headers = {
        "Authorization": f"Bearer {token}",
        "Content-Type": "application/json",
    }

    response = _get_graph_session().get(
        f"https://graph.microsoft.com/v1.0/applications/{app_object_id}",
        headers=headers,
        params={"$select": "passwordCredentials"},
    )
    response.raise_for_status()
    credentials = response.json().get("passwordCredentials", [])

    if not credentials:
        print("  No existing secrets to revoke")
        return 0

    # legacy: dev-only — replace with managed identity in production
    if dry_run:
        print(f"  [DRY RUN] Would revoke {len(credentials)} existing secret(s)")
        return len(credentials)

    for cred in credentials:
        _get_graph_session().post(
            f"https://graph.microsoft.com/v1.0/applications/{app_object_id}/removePassword",
            headers=headers,
            json={"keyId": cred["keyId"]},
        ).raise_for_status()
        print(f"  Revoked secret: {cred['keyId']}")

    return len(credentials)


def store_in_keyvault(
    vault_name: str,
    secret_name: str,
    secret_value: str,
    credential,
    dry_run: bool = False,
) -> str:
    """
    Store secret in Azure Key Vault.

    Args:
        vault_name: Key Vault name
        secret_name: Secret name
        secret_value: Secret value
        credential: Azure credential
        dry_run: If True, don't store

    Returns:
        Secret version ID
    """
    vault_url = f"https://{vault_name}.vault.azure.net"

    # legacy: dev-only — replace with managed identity in production
    if dry_run:
        print(f"  [DRY RUN] Would store secret in {vault_url}")
        print(f"  [DRY RUN] Secret name: {secret_name}")
        return "dry-run-version"

    client = SecretClient(vault_url=vault_url, credential=credential)
    result = client.set_secret(secret_name, secret_value)

    print(f"  Vault: {vault_name}")
    print(f"  Secret: {secret_name}")
    print(f"  Version: {result.properties.version[:8]}...")

    return result.properties.version


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Register Service Principal for ELM",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Dry run
  python register_service_principal.py --tenant-id <id> --app-name ELM-SP --key-vault-name vault --expiry-days 90 --dry-run

  # Create new SP
  python register_service_principal.py --tenant-id <id> --app-name ELM-SP --key-vault-name vault --expiry-days 90

  # Rotate secret
  python register_service_principal.py --tenant-id <id> --app-name ELM-SP --key-vault-name vault --expiry-days 90 --rotate-secret
        """,
    )

    parser.add_argument(
        "--tenant-id",
        required=True,
        help="Entra ID tenant ID",
    )
    parser.add_argument(
        "--app-name",
        default="ELM-Provisioning-ServicePrincipal",
        help="Application display name (default: ELM-Provisioning-ServicePrincipal)",
    )
    parser.add_argument(
        "--key-vault-name",
        required=True,
        help="Azure Key Vault name",
    )
    parser.add_argument(
        "--secret-name",
        default="ELM-ServicePrincipal-Secret",
        help="Key Vault secret name (default: ELM-ServicePrincipal-Secret)",
    )
    parser.add_argument(
        "--expiry-days",
        type=int,
        default=90,
        help="Secret expiry in days (default: 90; valid range: 30-365)",
    )
    parser.add_argument(
        "--rotate-secret",
        action="store_true",
        help="Rotate existing secret (creates new, stores in Key Vault)",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Validate without creating resources",
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser authentication",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Show detailed output including stack traces on error",
    )

    args = parser.parse_args()

    # Validate expiry-days range
    if args.expiry_days < 30 or args.expiry_days > 365:
        parser.error(f"--expiry-days must be between 30 and 365 (got {args.expiry_days})")

    print("ELM Service Principal Registration")
    print("=" * 36)
    print()

    if args.dry_run:
        print("[DRY RUN MODE - No changes will be made]")
        print()

    try:
        # Get Azure credential
        if args.interactive:
            credential = InteractiveBrowserCredential(tenant_id=args.tenant_id)
        else:
            credential = DefaultAzureCredential()

        token = get_graph_token(credential)

        # Step 1: Create or find app registration
        print("[1/4] Creating Entra ID application...")
        app = create_app_registration(
            token=token,
            app_name=args.app_name,
            tenant_id=args.tenant_id,
            dry_run=args.dry_run,
        )
        print()

        # Step 1b: Revoke existing secrets if rotating
        if args.rotate_secret:
            print("  Rotating: revoking existing Entra ID secrets...")
            remove_existing_secrets(
                token=token,
                app_object_id=app["id"],
                dry_run=args.dry_run,
            )
            print()

        # Step 2: Create client secret
        print("[2/4] Creating client secret...")
        secret = create_client_secret(
            token=token,
            app_object_id=app["id"],
            expiry_days=args.expiry_days,
            dry_run=args.dry_run,
        )
        print()

        # Step 3: Store in Key Vault
        print("[3/4] Storing secret in Key Vault...")
        store_in_keyvault(
            vault_name=args.key_vault_name,
            secret_name=args.secret_name,
            secret_value=secret.get("secretText", ""),
            credential=credential,
            dry_run=args.dry_run,
        )
        print()

        # Step 4: Summary
        print("[4/4] Summary")
        print("      " + "=" * 8)
        print(f"      Application Name: {args.app_name}")
        print(f"      Application ID: {app['appId']}")
        print(f"      Tenant ID: {args.tenant_id}")
        print(f"      Key Vault: {args.key_vault_name}")
        print(f"      Secret Name: {args.secret_name}")
        print()
        print("      NEXT STEP (MANUAL):")
        print("      Register as Power Platform Management Application:")
        print("      1. Go to admin.powerplatform.microsoft.com")
        print("      2. Settings > Admin settings > Power Platform settings")
        print("      3. Service principal > New service principal")
        print(f"      4. Enter Application ID: {app['appId']}")
        print("      5. Click Create")
        print("      6. Grant admin consent for Microsoft Graph Group.Read.All")
        print()

        if args.dry_run:
            print("[DRY RUN] No resources were created")

        sys.exit(0)

    except Exception as e:
        print(f"\nError: {e}", file=sys.stderr)
        if args.verbose:
            import traceback
            traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
