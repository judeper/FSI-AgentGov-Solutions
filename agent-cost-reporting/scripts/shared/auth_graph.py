#!/usr/bin/env python3
"""
Microsoft Graph token helper for Agent Cost Reporting.

Used by the Copilot usage-report, license-inventory, and (beta) Purview audit-log
collectors. Graph supports app-only auth and managed identity, so this helper is
managed-identity-first, with a client-secret fallback for dev-only use.

Required permissions (application): Reports.Read.All and Organization.Read.All for usage
and licenses; AuditLogsQuery.Read.All for the optional beta Purview audit collector.
"""

from __future__ import annotations

import argparse
import logging
from typing import Optional

logger = logging.getLogger(__name__)

GRAPH_SCOPE = "https://graph.microsoft.com/.default"


def get_graph_token(
    client_id: Optional[str] = None,
    tenant_id: Optional[str] = None,
    client_secret: Optional[str] = None,
) -> str:
    """Acquire a Microsoft Graph bearer token (app-only / managed identity).

    Priority:
      1. Managed identity / DefaultAzureCredential chain.
      2. Client secret (``# legacy: dev-only -- replace with managed identity in production``).
    """
    if client_secret and client_id and tenant_id:
        # legacy: dev-only -- replace with managed identity in production
        from azure.identity import ClientSecretCredential

        cred = ClientSecretCredential(tenant_id, client_id, client_secret)
        return cred.get_token(GRAPH_SCOPE).token

    from azure.identity import DefaultAzureCredential, ManagedIdentityCredential

    if client_id:
        cred = ManagedIdentityCredential(client_id=client_id)
    else:
        cred = DefaultAzureCredential()
    return cred.get_token(GRAPH_SCOPE).token


def _main() -> int:
    parser = argparse.ArgumentParser(description="Smoke-test Microsoft Graph token acquisition.")
    parser.add_argument("--client-id")
    parser.add_argument("--tenant-id")
    parser.add_argument("--client-secret")
    args = parser.parse_args()
    logging.basicConfig(level=logging.INFO)
    token = get_graph_token(args.client_id, args.tenant_id, args.client_secret)
    logger.info("Acquired Graph token (%d chars).", len(token))
    return 0


if __name__ == "__main__":
    raise SystemExit(_main())
