#!/usr/bin/env python3
"""
Create connection references for Conditional Access Automation.

Deploys three connection references that Power Automate flows use to
interact with Dataverse, Office 365 Outlook, and Microsoft Teams.
All operations are idempotent — safe to re-run.

Connection References:
  - fsi_cr_dataverse_conditionalaccessautomation: Table CRUD for
    baselines, validation history, and violations
  - fsi_cr_office365_conditionalaccessautomation: Email notification
    delivery for compliance alerts
  - fsi_cr_teams_conditionalaccessautomation: Adaptive card alert
    delivery to Teams channels
"""

import argparse
import os
import sys

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared")
)
from dataverse_client import DataverseClient

# =============================================================================
# Connection Reference Definitions
# =============================================================================

CONNECTION_REFS = [
    {
        "logical_name": "fsi_cr_dataverse_conditionalaccessautomation",
        "display_name": "Dataverse - Conditional Access Automation",
        "connector": "shared_commondataserviceforapps",
        "description": (
            "Dataverse connection for CAA. Used for baseline CRUD, "
            "validation history persistence, and violation record management."
        ),
    },
    {
        "logical_name": "fsi_cr_office365_conditionalaccessautomation",
        "display_name": "Office 365 - Conditional Access Automation",
        "connector": "shared_office365",
        "description": (
            "Office 365 Outlook connection for CAA. Used for email "
            "notification delivery to the compliance distribution list."
        ),
    },
    {
        "logical_name": "fsi_cr_teams_conditionalaccessautomation",
        "display_name": "Teams - Conditional Access Automation",
        "connector": "shared_teams",
        "description": (
            "Microsoft Teams connection for CAA. Used for adaptive card "
            "alert delivery to violation notification channels."
        ),
    },
]


# =============================================================================
# Deployment Functions
# =============================================================================


def create_connection_references(
    client: DataverseClient, dry_run: bool = False
) -> dict:
    """
    Create connection references for CAA Power Automate flows.

    Args:
        client: DataverseClient instance
        dry_run: If True, preview changes without creating

    Returns:
        dict: Results summary with created/skipped/errors counts
    """
    print("\n[Creating Connection References]")
    results = {"created": 0, "skipped": 0, "errors": 0}

    for conn_ref in CONNECTION_REFS:
        logical_name = conn_ref["logical_name"]
        try:
            # Check if connection reference already exists
            if not dry_run and not client.dry_run:
                existing = client.query(
                    "connectionreferences",
                    filter_expr=(
                        f"connectionreferencelogicalname eq "
                        f"'{logical_name}'"
                    ),
                )
                if existing:
                    print(f"  {logical_name}: already exists, skipping")
                    results["skipped"] += 1
                    continue
            elif dry_run or client.dry_run:
                print(f"  [DRY RUN] {logical_name}: would check if exists")

            # Create connection reference
            if dry_run or client.dry_run:
                print(f"  [DRY RUN] {logical_name}: would create")
                print(f"    Display name: {conn_ref['display_name']}")
                print(f"    Connector: {conn_ref['connector']}")
                results["created"] += 1
            else:
                data = {
                    "connectionreferencelogicalname": logical_name,
                    "connectionreferencedisplayname": (
                        conn_ref["display_name"]
                    ),
                    "connectorid": (
                        f"/providers/Microsoft.PowerApps/apis/"
                        f"{conn_ref['connector']}"
                    ),
                    "description": conn_ref.get("description", ""),
                }
                client.create_record("connectionreferences", data)

                print(f"  {logical_name}: created")
                print(f"    Display name: {conn_ref['display_name']}")
                print(f"    Connector: {conn_ref['connector']}")
                results["created"] += 1

        except Exception as e:
            print(f"  {logical_name}: ERROR - {e}")
            results["errors"] += 1

    print()
    print(
        f"  Summary: {results['created']} created, "
        f"{results['skipped']} skipped"
    )
    if results["errors"] > 0:
        print(f"  Errors: {results['errors']}")

    return results


# =============================================================================
# CLI Entry Point
# =============================================================================


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Create connection references for "
            "Conditional Access Automation"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Connection references created:\n"
            "  - fsi_cr_dataverse_conditionalaccessautomation "
            "(Dataverse connector)\n"
            "  - fsi_cr_office365_conditionalaccessautomation "
            "(Office 365 Outlook connector)\n"
            "  - fsi_cr_teams_conditionalaccessautomation "
            "(Teams connector)\n\n"
            "These connection references must be bound to actual "
            "connections in Power Automate before flows can use them.\n\n"
            "Examples:\n"
            "  # Interactive authentication\n"
            "  python create_caa_connection_references.py \\\n"
            "      --tenant-id <tenant-id> \\\n"
            "      --environment-url https://org.crm.dynamics.com \\\n"
            "      --interactive\n\n"
            "  # Service Principal authentication\n"
            "  python create_caa_connection_references.py \\\n"
            "      --tenant-id <tenant-id> \\\n"
            "      --environment-url https://org.crm.dynamics.com \\\n"
            "      --client-id <app-id>\n\n"
            "  # Dry run to preview changes\n"
            "  python create_caa_connection_references.py \\\n"
            "      --tenant-id <tenant-id> \\\n"
            "      --environment-url https://org.crm.dynamics.com \\\n"
            "      --interactive --dry-run\n"
        ),
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("CAA_TENANT_ID"),
        help="Microsoft Entra tenant ID (or CAA_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("CAA_CLIENT_ID"),
        help="Service Principal application ID (or CAA_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("CAA_CLIENT_SECRET"),
        help="Client secret (or CAA_CLIENT_SECRET env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("CAA_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or CAA_ENVIRONMENT_URL env var)",
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser authentication",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without creating resources",
    )

    args = parser.parse_args()

    if not args.tenant_id or not args.environment_url:
        parser.error("--tenant-id and --environment-url are required")

    client_secret = args.client_secret or os.environ.get("CAA_CLIENT_SECRET")
    if not args.interactive and not client_secret:
        if args.client_id:
            import getpass

            client_secret = getpass.getpass("Client secret: ")

    try:
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            interactive=args.interactive,
            dry_run=args.dry_run,
        )

        results = create_connection_references(client, dry_run=args.dry_run)

        if results["errors"] > 0:
            sys.exit(1)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
