#!/usr/bin/env python3
"""
Create connection references for Message Center Monitor.

Connection references enable Power Automate flows to access Dataverse, Teams,
Key Vault, and the Graph API for Message Center post monitoring and notifications.
"""

import argparse
import os
import sys
from typing import Optional

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"))
from dataverse_client import DataverseClient

CONNECTION_REFS = [
    {
        "logical_name": "fsi_cr_dataverse_messagecenter",
        "display_name": "Dataverse - MCM",
        "connector": "shared_commondataserviceforapps",
        "description": "Dataverse connector for message persistence and assessment tracking",
    },
    {
        "logical_name": "fsi_cr_teams_messagecenter",
        "display_name": "Teams - MCM",
        "connector": "shared_teams",
        "description": "Teams connector for Message Center alert notifications",
    },
    {
        "logical_name": "fsi_cr_keyvault_messagecenter",
        "display_name": "Key Vault - MCM",
        "connector": "shared_keyvault",
        "description": "Key Vault connector for Graph API secret retrieval",
    },
    {
        "logical_name": "fsi_cr_http_messagecenter",
        "display_name": "HTTP - MCM",
        "connector": "shared_httppremium",
        "description": "HTTP connector for Microsoft Graph API calls to Message Center",
    },
]


def create_connection_references(client: DataverseClient, dry_run: bool = False) -> dict:
    """
    Create connection references for MCM Power Automate flows.

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
                    filter_expr=f"connectionreferencelogicalname eq '{logical_name}'"
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
                    "connectionreferencedisplayname": conn_ref["display_name"],
                    "connectorid": f"/providers/Microsoft.PowerApps/apis/{conn_ref['connector']}",
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
    print(f"  Summary: {results['created']} created, {results['skipped']} skipped")
    if results["errors"] > 0:
        print(f"  Errors: {results['errors']}")

    return results


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create connection references for Message Center Monitor",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Connection references created:
  - fsi_cr_dataverse_messagecenter (Dataverse connector)
  - fsi_cr_teams_messagecenter (Teams connector)
  - fsi_cr_keyvault_messagecenter (Key Vault connector)
  - fsi_cr_http_messagecenter (HTTP Premium connector)

These connection references must be bound to actual connections in Power Automate
before flows can use them.

Examples:
  # Interactive authentication
  python create_mcm_connection_references.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive

  # Service Principal authentication
  python create_mcm_connection_references.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --client-id <app-id>

  # Dry run to preview changes
  python create_mcm_connection_references.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive --dry-run
        """
    )

    # Connection arguments
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("MCM_TENANT_ID"),
        help="Microsoft Entra tenant ID (or MCM_TENANT_ID env var)"
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("MCM_CLIENT_ID"),
        help="Service Principal application ID (or MCM_CLIENT_ID env var)"
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("MCM_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or MCM_ENVIRONMENT_URL env var)"
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser authentication"
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview changes without creating resources"
    )

    args = parser.parse_args()

    # Validate required arguments
    if not args.tenant_id or not args.environment_url:
        parser.error("--tenant-id and --environment-url are required")

    # Handle client secret for Service Principal auth
    client_secret = os.environ.get("MCM_CLIENT_SECRET")
    if not args.interactive and not client_secret:
        if args.client_id:
            import getpass
            client_secret = getpass.getpass("Client secret: ")

    try:
        # Initialize client
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            interactive=args.interactive,
            dry_run=args.dry_run
        )

        # Create connection references
        results = create_connection_references(client, dry_run=args.dry_run)

        # Exit with error if any failures
        if results["errors"] > 0:
            sys.exit(1)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
