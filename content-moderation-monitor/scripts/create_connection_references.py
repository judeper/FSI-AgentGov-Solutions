#!/usr/bin/env python3
"""Create Dataverse connection references for Content Moderation Monitor.

Deploys three connection references that Power Automate flows use to
interact with Dataverse, Office 365 email, and Microsoft Teams. All
operations are idempotent — safe to re-run.

Connection References:
  - fsi_cr_dataverse_moderationmonitor: Core data operations
  - fsi_cr_office365_moderationmonitor: Email alerts
  - fsi_cr_teams_moderationmonitor: Teams adaptive card alerts
"""

import argparse
import os
import sys

from cmm_client import CMMClient


# =============================================================================
# Connection Reference Definitions
# =============================================================================

CONNECTION_REF_DEFINITIONS = [
    {
        "logical_name": "fsi_cr_dataverse_moderationmonitor",
        "display_name": "Dataverse - Content Moderation Monitor",
        "connector_id": "shared_commondataserviceforapps",
        "description": (
            "Dataverse connection for Content Moderation Monitor. "
            "Used for baseline storage, validation history, and "
            "violation tracking operations."
        ),
    },
    {
        "logical_name": "fsi_cr_office365_moderationmonitor",
        "display_name": "Office 365 - Content Moderation Monitor",
        "connector_id": "shared_office365",
        "description": (
            "Office 365 connection for Content Moderation Monitor. "
            "Used to send email alerts when moderation violations "
            "are detected."
        ),
    },
    {
        "logical_name": "fsi_cr_teams_moderationmonitor",
        "display_name": "Teams - Content Moderation Monitor",
        "connector_id": "shared_teams",
        "description": (
            "Microsoft Teams connection for Content Moderation Monitor. "
            "Used to post adaptive card alerts to the designated "
            "governance channel."
        ),
    },
]


# =============================================================================
# Deployment Functions
# =============================================================================


def create_connection_reference(
    client: CMMClient, definition: dict, dry_run: bool = False,
) -> None:
    """Create a single connection reference in Dataverse.

    Checks for existence first — skips if already present.

    Args:
        client: CMMClient instance
        definition: Dict with logical_name, display_name, connector_id,
                     description
        dry_run: Preview mode flag
    """
    logical_name = definition["logical_name"]
    display_name = definition["display_name"]
    connector_id = definition["connector_id"]
    description = definition["description"]

    # Idempotent check — skip if already exists
    existing = client.query(
        "connectionreferences",
        filter=f"connectionreferencelogicalname eq '{logical_name}'",
    )
    if existing["value"]:
        print(f"  {logical_name}: already exists, skipping")
        return

    # Create connection reference record
    ref_data = {
        "connectionreferencelogicalname": logical_name,
        "connectionreferencedisplayname": display_name,
        "connectorid": f"/providers/Microsoft.PowerApps/apis/{connector_id}",
        "description": description,
    }

    client.create_record("connectionreferences", ref_data)
    print(f"  {logical_name}: created ({connector_id})")


def create_connection_references(
    client: CMMClient, dry_run: bool = False,
) -> None:
    """Deploy all CMM connection references to Dataverse.

    Creates three connection references for Dataverse, Office 365, and
    Teams connectors. All operations are idempotent — safe to re-run.

    Args:
        client: CMMClient instance
        dry_run: Preview mode flag
    """
    print("=" * 60)
    print("CMM Connection References Deployment")
    print("  Content Moderation Governance Monitor")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN - No changes will be made ***\n")

    print("\n[Creating Connection References]")

    for defn in CONNECTION_REF_DEFINITIONS:
        create_connection_reference(client, defn, dry_run)

    # Summary
    print("\n" + "=" * 60)
    if dry_run:
        print("DRY RUN COMPLETE - Review output above")
    else:
        print("CONNECTION REFERENCES DEPLOYMENT COMPLETE")
    print(f"  Connection references: {len(CONNECTION_REF_DEFINITIONS)}")
    print("=" * 60)


# =============================================================================
# CLI Entry Point
# =============================================================================


def main():
    """CLI entry point for connection reference deployment."""
    parser = argparse.ArgumentParser(
        description=(
            "Create Dataverse connection references for "
            "Content Moderation Monitor"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Dry run with interactive auth\n"
            "  python create_connection_references.py "
            "--dry-run --interactive\n\n"
            "  # Deploy with service principal\n"
            "  python create_connection_references.py \\\n"
            "    --tenant-id $CMM_TENANT_ID \\\n"
            "    --client-id $CMM_CLIENT_ID \\\n"
            "    --client-secret $CMM_CLIENT_SECRET \\\n"
            "    --environment-url $CMM_ENVIRONMENT_URL\n"
        ),
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("CMM_TENANT_ID"),
        help="Azure AD tenant ID (or set CMM_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("CMM_CLIENT_ID"),
        help="Service principal app ID (or set CMM_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("CMM_CLIENT_SECRET"),
        help="Service principal secret (or set CMM_CLIENT_SECRET env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("CMM_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set CMM_ENVIRONMENT_URL env var)",
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser authentication",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Show what would be created without making changes",
    )

    args = parser.parse_args()

    # Validate required arguments
    if not args.tenant_id:
        print("ERROR: --tenant-id or CMM_TENANT_ID required")
        sys.exit(1)
    if not args.environment_url:
        print("ERROR: --environment-url or CMM_ENVIRONMENT_URL required")
        sys.exit(1)

    try:
        client = CMMClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=args.client_secret,
            interactive=args.interactive,
            dry_run=args.dry_run,
        )

        create_connection_references(client, dry_run=args.dry_run)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
