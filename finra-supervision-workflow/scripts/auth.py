"""Shared authentication module for Dataverse API access."""

import sys

try:
    from msal import PublicClientApplication, ConfidentialClientApplication
except ImportError:
    print("Error: Required packages not installed.")
    print("Run: pip install -r requirements.txt")
    sys.exit(1)


def get_access_token(tenant_id: str, client_id: str = None, client_secret: str = None,
                     interactive: bool = False, environment_url: str = None) -> str:
    """Acquire access token for Dataverse."""
    scope = [f"{environment_url}/.default"]

    if interactive:
        app = PublicClientApplication(
            client_id="51f81489-12ee-4a9e-aaae-a2591f45987d",  # Power Apps CLI client ID
            authority=f"https://login.microsoftonline.com/{tenant_id}"
        )
        result = app.acquire_token_interactive(scopes=scope)
    else:
        if not client_id or not client_secret:
            print("Error: client_id and client_secret are required for non-interactive authentication")
            sys.exit(1)
        app = ConfidentialClientApplication(
            client_id=client_id,
            client_credential=client_secret,
            authority=f"https://login.microsoftonline.com/{tenant_id}"
        )
        result = app.acquire_token_for_client(scopes=scope)

    if "access_token" in result:
        return result["access_token"]
    else:
        print(f"Authentication failed: {result.get('error_description', 'Unknown error')}")
        sys.exit(1)
