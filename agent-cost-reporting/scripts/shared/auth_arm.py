#!/usr/bin/env python3
"""
Azure Resource Manager (ARM) token helper for Agent Cost Reporting.

Used by the Azure Cost Management collectors. ARM supports managed identity, so this
helper is managed-identity-first per repo convention, falling back to other
DefaultAzureCredential sources (workload identity federation, Azure CLI, env vars).
A client-secret path is provided for dev-only use.

Required RBAC: Cost Management Reader (or Reader) on the cost query scope.
"""

from __future__ import annotations

import argparse
import logging
from typing import Optional

logger = logging.getLogger(__name__)

ARM_SCOPE = "https://management.azure.com/.default"


def get_arm_token(
    client_id: Optional[str] = None,
    tenant_id: Optional[str] = None,
    client_secret: Optional[str] = None,
) -> str:
    """Acquire an ARM bearer token.

    Priority:
      1. Managed identity / DefaultAzureCredential chain (preferred in Azure-hosted runners).
      2. Client secret (``# legacy: dev-only -- replace with managed identity in production``).

    Args:
        client_id: Optional client id for a user-assigned managed identity or app.
        tenant_id: Tenant id (required only for the client-secret path).
        client_secret: Client secret (dev-only fallback).

    Returns:
        An access token string for the ARM audience.
    """
    if client_secret and client_id and tenant_id:
        # legacy: dev-only -- replace with managed identity in production
        from azure.identity import ClientSecretCredential

        cred = ClientSecretCredential(tenant_id, client_id, client_secret)
        return cred.get_token(ARM_SCOPE).token

    from azure.identity import DefaultAzureCredential, ManagedIdentityCredential

    if client_id:
        cred = ManagedIdentityCredential(client_id=client_id)
    else:
        cred = DefaultAzureCredential()
    return cred.get_token(ARM_SCOPE).token


def _main() -> int:
    parser = argparse.ArgumentParser(description="Smoke-test ARM token acquisition.")
    parser.add_argument("--client-id")
    parser.add_argument("--tenant-id")
    parser.add_argument("--client-secret")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    token = get_arm_token(args.client_id, args.tenant_id, args.client_secret)
    logger.info("Acquired ARM token (%d chars).", len(token))
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
