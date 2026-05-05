"""Shared authentication module for Dataverse API access."""

import sys
from typing import Optional

try:
    from azure.identity import DefaultAzureCredential, ManagedIdentityCredential
    from msal import ConfidentialClientApplication, PublicClientApplication
except ImportError as exc:
    print("Error: Required packages not installed.")
    print("Run: pip install -r requirements.txt")
    print(f"Missing package detail: {exc}")
    sys.exit(1)


def _acquire_managed_identity_token(scope: str, managed_identity_client_id: Optional[str] = None) -> str:
    """Acquire a token using managed identity or workload identity credentials."""
    attempts = []

    if managed_identity_client_id:
        attempts.append((
            "user-assigned managed identity",
            ManagedIdentityCredential(client_id=managed_identity_client_id),
        ))
    else:
        attempts.append(("system-assigned managed identity", ManagedIdentityCredential()))

    attempts.append((
        "workload identity/default credential chain",
        DefaultAzureCredential(exclude_managed_identity_credential=True),
    ))

    errors = []
    for label, credential in attempts:
        try:
            return credential.get_token(scope).token
        except Exception as exc:  # pragma: no cover - depends on host identity configuration
            errors.append(f"{label}: {exc}")

    print("Error: managed identity/workload identity authentication failed.")
    for error in errors:
        print(f"  {error}")
    print("For local admin runs, use --interactive. Client-secret auth is a legacy dev-only fallback.")
    sys.exit(1)


def get_access_token(
    tenant_id: str,
    client_id: Optional[str] = None,
    client_secret: Optional[str] = None,
    interactive: bool = False,
    environment_url: str = "",
    managed_identity_client_id: Optional[str] = None,
) -> str:
    """Acquire an access token for Dataverse."""
    scope = f"{environment_url.rstrip('/')}/.default"

    if interactive:
        app = PublicClientApplication(
            client_id="51f81489-12ee-4a9e-aaae-a2591f45987d",  # Power Apps CLI client ID
            authority=f"https://login.microsoftonline.com/{tenant_id}",
        )
        result = app.acquire_token_interactive(scopes=[scope])
        if "access_token" in result:
            return result["access_token"]
        print(f"Authentication failed: {result.get('error_description', 'Unknown error')}")
        sys.exit(1)

    if client_id or client_secret:
        if not client_id or not client_secret:
            print("Error: both client_id and client_secret are required for legacy client-secret authentication")
            print("Use --managed-identity-client-id for user-assigned managed identity.")
            sys.exit(1)
        # legacy: dev-only — replace with managed identity in production
        print("WARNING: client-secret authentication is a legacy dev-only fallback. Use managed identity in production.")
        app = ConfidentialClientApplication(
            client_id=client_id,
            client_credential=client_secret,
            authority=f"https://login.microsoftonline.com/{tenant_id}",
        )
        result = app.acquire_token_for_client(scopes=[scope])
        if "access_token" in result:
            return result["access_token"]
        print(f"Authentication failed: {result.get('error_description', 'Unknown error')}")
        sys.exit(1)

    return _acquire_managed_identity_token(scope, managed_identity_client_id)
