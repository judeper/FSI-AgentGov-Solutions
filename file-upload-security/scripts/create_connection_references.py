#!/usr/bin/env python3
"""Create Dataverse connection references for File Upload Security Configurator.

Provisions four connection references for the FUS solution:
  - Dataverse (for baseline/violation storage)
  - Office 365 (for owner resolution and email notifications)
  - Teams (for adaptive card violation alerts)

All operations are idempotent — existing references are skipped.

Usage:
  python create_connection_references.py --tenant-id <tid> --url <url> [--dry-run]
"""

import argparse
import os

from fus_client import FUSClient


# ── Connection Reference Definitions ──────────────────────────────

CONNECTION_REFERENCES = [
    {
        "connectionreferencedisplayname": "FUS - Dataverse",
        "connectionreferencelogicalname": "fsi_cr_dataverse_fileuploadsecurity",
        "connectorid": "/providers/Microsoft.PowerApps/apis/shared_commondataserviceforapps",
        "description": (
            "Dataverse connection for File Upload Security Configurator. "
            "Used to read/write baseline, validation history, and violation records."
        ),
    },
    {
        "connectionreferencedisplayname": "FUS - Office 365",
        "connectionreferencelogicalname": "fsi_cr_office365_fileuploadsecurity",
        "connectorid": "/providers/Microsoft.PowerApps/apis/shared_office365",
        "description": (
            "Office 365 connection for File Upload Security Configurator. "
            "Used for agent owner resolution and email-based violation notifications."
        ),
    },
    {
        "connectionreferencedisplayname": "FUS - Teams",
        "connectionreferencelogicalname": "fsi_cr_teams_fileuploadsecurity",
        "connectorid": "/providers/Microsoft.PowerApps/apis/shared_teams",
        "description": (
            "Teams connection for File Upload Security Configurator. "
            "Used to post adaptive card violation alerts to governance channels."
        ),
    },
    {
        "connectionreferencedisplayname": "FUS - Azure Automation",
        "connectionreferencelogicalname": "fsi_cr_azureautomation_fileuploadsecurity",
        "connectorid": "/providers/Microsoft.PowerApps/apis/shared_azureautomation",
        "description": (
            "Azure Automation connection for File Upload Security Configurator. "
            "Used to trigger and monitor the validation runbook from Power Automate flows."
        ),
    },
]


def deploy_connection_references(client: FUSClient) -> None:
    """Create all FUS connection references (idempotent)."""
    print(f"\n{'='*60}")
    print("Connection References")
    print(f"{'='*60}")

    for ref_def in CONNECTION_REFERENCES:
        logical_name = ref_def["connectionreferencelogicalname"]

        # Check if already exists
        result = client.query(
            "connectionreferences",
            filter=(
                f"connectionreferencelogicalname eq '{logical_name}'"
            ),
            select="connectionreferencelogicalname",
        )
        if result.get("value"):
            print(f"  {logical_name}: already exists")
            continue

        if client.dry_run:
            print(f"  [DRY RUN] Would create: {logical_name}")
            continue

        client.create_record("connectionreferences", ref_def)
        print(f"  {logical_name}: created")

    print(f"\n  Total: {len(CONNECTION_REFERENCES)} connection references")
    print(f"{'='*60}")


# ── CLI Entry Point ──────────────────────────────────────────────

def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create connection references for File Upload Security Configurator"
    )
    parser.add_argument("--tenant-id", default=os.environ.get("FUS_TENANT_ID"))
    parser.add_argument("--client-id", default=os.environ.get("FUS_CLIENT_ID"))
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("FUS_CLIENT_SECRET"),
        help="Legacy dev-only fallback; use managed identity in production",
    )
    parser.add_argument(
        "--managed-identity-client-id",
        default=os.environ.get("FUS_MANAGED_IDENTITY_CLIENT_ID"),
        help="Optional user-assigned managed identity client ID",
    )
    parser.add_argument("--url", default=os.environ.get("FUS_DATAVERSE_URL"),
                        help="Dataverse environment URL")
    parser.add_argument("--interactive", action="store_true",
                        help="Use interactive browser auth")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be created without making changes")
    args = parser.parse_args()

    if not args.url:
        parser.error("url required (set FUS_DATAVERSE_URL env var or use --url)")
    if args.interactive and (not args.tenant_id or not args.client_id):
        parser.error("interactive auth requires tenant-id and client-id")
    if args.client_secret and (not args.tenant_id or not args.client_id):
        parser.error("legacy client secret auth requires tenant-id and client-id")

    client = FUSClient(
        tenant_id=args.tenant_id,
        environment_url=args.url,
        client_id=args.client_id,
        client_secret=args.client_secret,
        interactive=args.interactive,
        dry_run=args.dry_run,
        managed_identity_client_id=args.managed_identity_client_id,
    )

    deploy_connection_references(client)


if __name__ == "__main__":
    main()
