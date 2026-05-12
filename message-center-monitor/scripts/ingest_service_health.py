#!/usr/bin/env python3
"""
Ingest Microsoft 365 Service Health events via Microsoft Graph.

Retrieves service health overviews and active issues from the Graph
serviceAnnouncement API endpoints and writes structured JSON output
for downstream consumption by the Message Center Monitor solution.

Endpoints used:
  GET /admin/serviceAnnouncement/healthOverviews
  GET /admin/serviceAnnouncement/issues

Required Graph permissions:
  ServiceHealth.Read.All (application)

Authentication priority (managed-identity-first):
  1. System-assigned managed identity (default)
  2. User-assigned managed identity (--client-id)
  3. Workload identity federation (AZURE_FEDERATED_TOKEN_FILE)
  4. Interactive / device-code (--interactive)
  5. Client secret (legacy, --auth-mode client-secret)

Usage:
    python ingest_service_health.py --tenant-id <id>
    python ingest_service_health.py --tenant-id <id> --output-dir ./output
    python ingest_service_health.py --tenant-id <id> --interactive
"""

from __future__ import annotations

import argparse
import json
import logging
import os
import sys
from datetime import datetime, timezone
from typing import Any

logger = logging.getLogger(__name__)

GRAPH_BASE = "https://graph.microsoft.com/v1.0"
HEALTH_OVERVIEWS_URL = f"{GRAPH_BASE}/admin/serviceAnnouncement/healthOverviews"
HEALTH_ISSUES_URL = f"{GRAPH_BASE}/admin/serviceAnnouncement/issues"
GRAPH_SCOPE = "https://graph.microsoft.com/.default"


def _get_credential(
    tenant_id: str,
    client_id: str | None = None,
    client_secret: str | None = None,
    interactive: bool = False,
    auth_mode: str | None = None,
) -> Any:
    """
    Build an Azure Identity credential following managed-identity-first priority.

    Returns:
        A TokenCredential instance.

    Raises:
        RuntimeError: If no suitable credential can be constructed.
    """
    try:
        from azure.identity import (
            ChainedTokenCredential,
            ClientSecretCredential,
            DeviceCodeCredential,
            InteractiveBrowserCredential,
            ManagedIdentityCredential,
            WorkloadIdentityCredential,
        )
    except ImportError:
        raise RuntimeError(
            "azure-identity package is required. Install with: pip install azure-identity"
        )

    if auth_mode == "client-secret" and client_id and client_secret:
        logger.info("Using client-secret credential (legacy fallback)")
        return ClientSecretCredential(
            tenant_id=tenant_id,
            client_id=client_id,
            client_secret=client_secret,
        )

    if interactive:
        logger.info("Using interactive browser credential")
        return InteractiveBrowserCredential(tenant_id=tenant_id)

    # Build chained credential: MI → workload identity → device code
    candidates = []

    if client_id:
        candidates.append(ManagedIdentityCredential(client_id=client_id))
    else:
        candidates.append(ManagedIdentityCredential())

    if os.environ.get("AZURE_FEDERATED_TOKEN_FILE"):
        candidates.append(
            WorkloadIdentityCredential(
                tenant_id=tenant_id,
                client_id=client_id or os.environ.get("AZURE_CLIENT_ID", ""),
            )
        )

    candidates.append(DeviceCodeCredential(tenant_id=tenant_id))

    return ChainedTokenCredential(*candidates)


def _graph_get(
    url: str,
    token: str,
    params: dict[str, str] | None = None,
) -> list[dict[str, Any]]:
    """
    Execute a paged GET against Microsoft Graph and return all results.

    Handles @odata.nextLink pagination automatically.
    """
    try:
        import requests
    except ImportError:
        raise RuntimeError(
            "requests package is required. Install with: pip install requests"
        )

    headers = {
        "Authorization": f"Bearer {token}",
        "Accept": "application/json",
    }

    all_results: list[dict[str, Any]] = []
    next_url: str | None = url

    while next_url:
        logger.debug("GET %s", next_url)
        resp = requests.get(next_url, headers=headers, params=params, timeout=30)
        resp.raise_for_status()
        data = resp.json()

        items = data.get("value", [])
        all_results.extend(items)
        logger.info("  Retrieved %d items (total so far: %d)", len(items), len(all_results))

        next_url = data.get("@odata.nextLink")
        params = None  # nextLink includes query params

    return all_results


def ingest_service_health(
    tenant_id: str,
    client_id: str | None = None,
    client_secret: str | None = None,
    interactive: bool = False,
    auth_mode: str | None = None,
    output_dir: str | None = None,
) -> dict[str, Any]:
    """
    Ingest service health overviews and issues from Microsoft Graph.

    Args:
        tenant_id: Microsoft Entra tenant ID.
        client_id: Optional client ID for user-assigned MI or app registration.
        client_secret: Optional client secret (legacy fallback).
        interactive: Use interactive browser auth.
        auth_mode: Explicit auth mode override.
        output_dir: Directory for JSON output. If None, prints to stdout.

    Returns:
        dict with 'overviews' and 'issues' lists plus metadata.
    """
    credential = _get_credential(
        tenant_id=tenant_id,
        client_id=client_id,
        client_secret=client_secret,
        interactive=interactive,
        auth_mode=auth_mode,
    )

    logger.info("Acquiring Graph token...")
    token = credential.get_token(GRAPH_SCOPE).token

    logger.info("Fetching service health overviews...")
    overviews = _graph_get(HEALTH_OVERVIEWS_URL, token)

    logger.info("Fetching service health issues...")
    issues = _graph_get(HEALTH_ISSUES_URL, token)

    result = {
        "metadata": {
            "generatedAt": datetime.now(timezone.utc).isoformat(),
            "generatedBy": "ingest_service_health.py",
            "tenantId": tenant_id,
            "graphVersion": "v1.0",
            "permission": "ServiceHealth.Read.All",
        },
        "overviews": overviews,
        "issues": issues,
        "summary": {
            "totalServices": len(overviews),
            "totalIssues": len(issues),
            "activeIssues": len(
                [i for i in issues if i.get("status") not in ("resolved", "serviceRestored")]
            ),
        },
    }

    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
        timestamp = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H-%M-%S")
        out_path = os.path.join(output_dir, f"service-health-{timestamp}.json")
        with open(out_path, "w", encoding="utf-8") as f:
            json.dump(result, f, indent=2, default=str)
        logger.info("Output written to %s", out_path)
    else:
        print(json.dumps(result, indent=2, default=str))

    return result


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Ingest Microsoft 365 Service Health events via Graph API",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Required Graph permission: ServiceHealth.Read.All (application)

Examples:
  # Managed identity (default in Azure-hosted environments)
  python ingest_service_health.py --tenant-id <id>

  # User-assigned managed identity
  python ingest_service_health.py --tenant-id <id> --client-id <mi-client-id>

  # Interactive browser auth (admin workstation)
  python ingest_service_health.py --tenant-id <id> --interactive

  # Output to file
  python ingest_service_health.py --tenant-id <id> --output-dir ./output

  # Legacy client-secret (dev only)
  python ingest_service_health.py --tenant-id <id> --client-id <app-id> \\
      --auth-mode client-secret
        """,
    )

    parser.add_argument(
        "--tenant-id",
        required=True,
        help="Microsoft Entra tenant ID",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("MCM_CLIENT_ID"),
        help="Application / managed identity client ID (or MCM_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser authentication",
    )
    parser.add_argument(
        "--auth-mode",
        choices=["managed-identity", "workload-identity", "client-secret", "interactive"],
        default=None,
        help="Explicit authentication mode override",
    )
    parser.add_argument(
        "--output-dir",
        default=None,
        help="Directory for JSON output (default: stdout)",
    )
    parser.add_argument(
        "--log-level",
        default="INFO",
        choices=["DEBUG", "INFO", "WARNING", "ERROR"],
        help="Logging verbosity (default: INFO)",
    )

    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, args.log_level),
        format="%(asctime)s [%(levelname)s] %(message)s",
    )

    client_secret = os.environ.get("MCM_CLIENT_SECRET")
    if args.auth_mode == "client-secret" and not client_secret:
        import getpass
        client_secret = getpass.getpass("Client secret: ")

    try:
        result = ingest_service_health(
            tenant_id=args.tenant_id,
            client_id=args.client_id,
            client_secret=client_secret,
            interactive=args.interactive or args.auth_mode == "interactive",
            auth_mode=args.auth_mode,
            output_dir=args.output_dir,
        )

        logger.info(
            "Service health ingestion complete: %d services, %d issues (%d active)",
            result["summary"]["totalServices"],
            result["summary"]["totalIssues"],
            result["summary"]["activeIssues"],
        )

    except Exception as e:
        logger.error("Service health ingestion failed: %s", e)
        sys.exit(1)


if __name__ == "__main__":
    main()
