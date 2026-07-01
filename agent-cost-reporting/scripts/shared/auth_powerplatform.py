#!/usr/bin/env python3
"""
Power Platform API token helper for Agent Cost Reporting.

IMPORTANT -- the Power Platform API (api.powerplatform.com) is an exception to this repo's
managed-identity-first convention. Per Microsoft Learn
(programmability-authentication-v2, updated 2026-03-11):

  * "Power Platform API uses delegated permissions only at this time."
  * "For service principal identities, don't use application permissions. Instead... assign
    it an RBAC role (such as Contributor or Reader)."

So service-principal access uses the OAuth2 client-credentials grant for a token in the
``https://api.powerplatform.com/.default`` audience, and the service principal must be
assigned a Power Platform RBAC role (Reader is sufficient for the billing-policy/environment
read used here). Managed identity is NOT supported for calling this API; do not build an
MI-only path against it.
"""

from __future__ import annotations

import argparse
import logging
from typing import Optional

logger = logging.getLogger(__name__)

POWERPLATFORM_SCOPE = "https://api.powerplatform.com/.default"
AUTHORITY_TEMPLATE = "https://login.microsoftonline.com/{tenant_id}"


def get_powerplatform_token(
    tenant_id: str,
    client_id: str,
    client_secret: Optional[str] = None,
    certificate_path: Optional[str] = None,
    certificate_password: Optional[str] = None,
) -> str:
    """Acquire a Power Platform API token via the service-principal client-credentials grant.

    The service principal must additionally be granted a Power Platform RBAC role; the token
    alone does not authorize calls. Application permissions are intentionally not used.

    Args:
        tenant_id: Microsoft Entra tenant id.
        client_id: App registration (client) id of the service principal.
        client_secret: Client secret (one of secret or certificate is required).
        certificate_path: Path to a PEM/PFX certificate (preferred over a secret).
        certificate_password: Optional certificate password.

    Returns:
        An access token string for the Power Platform API audience.
    """
    import msal

    authority = AUTHORITY_TEMPLATE.format(tenant_id=tenant_id)

    if certificate_path:
        with open(certificate_path, "rb") as handle:
            private_key = handle.read()
        client_credential = {"private_key": private_key, "password": certificate_password}
    elif client_secret:
        # legacy: dev-only -- prefer a certificate credential in production
        client_credential = client_secret
    else:
        raise ValueError("Provide either client_secret or certificate_path for the service principal.")

    app = msal.ConfidentialClientApplication(
        client_id=client_id, authority=authority, client_credential=client_credential
    )
    result = app.acquire_token_for_client(scopes=[POWERPLATFORM_SCOPE])
    if "access_token" not in result:
        raise RuntimeError(
            f"Power Platform token acquisition failed: {result.get('error')} - {result.get('error_description')}"
        )
    return result["access_token"]


def _main() -> int:
    parser = argparse.ArgumentParser(description="Smoke-test Power Platform API token acquisition.")
    parser.add_argument("--tenant-id", required=True)
    parser.add_argument("--client-id", required=True)
    parser.add_argument("--client-secret")
    parser.add_argument("--certificate-path")
    parser.add_argument("--certificate-password")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    token = get_powerplatform_token(
        args.tenant_id, args.client_id, args.client_secret, args.certificate_path, args.certificate_password
    )
    logger.info("Acquired Power Platform API token (%d chars). Ensure the SP has a Power Platform RBAC role.", len(token))
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
