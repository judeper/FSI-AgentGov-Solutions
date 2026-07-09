#!/usr/bin/env python3
"""
Create connection references for the Early-Release Validation solution.

These connection references let optional Power Automate orchestration write
validation evidence to Dataverse and post promotion-gate notifications to Teams.
The structural validation checks themselves run offline (PowerShell + PAC CLI)
and do not require a connector.
"""

import argparse
import os
import sys

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared")
)
from dataverse_client import DataverseClient

CONNECTION_REFS = [
    {
        "logical_name": "fsi_cr_dataverse_erv",
        "display_name": "Dataverse - Early-Release Validation",
        "connector": "shared_commondataserviceforapps",
        "description": (
            "Dataverse connector for early-release validation evidence storage "
            "and fsi_ervalidationresult queries"
        ),
    },
    {
        "logical_name": "fsi_cr_teams_erv",
        "display_name": "Teams - Early-Release Validation",
        "connector": "shared_teams",
        "description": (
            "Teams connector for early-release promotion-gate notifications "
            "and resilience-gap alert cards"
        ),
    },
]


def create_connection_references(
    client: DataverseClient, dry_run: bool = False
) -> dict:
    """
    Create connection references for Early-Release Validation orchestration.

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
            if not dry_run:
                existing = client.query(
                    "connectionreferences",
                    filter_expr=(
                        f"connectionreferencelogicalname eq '{logical_name}'"
                    ),
                )
                if existing:
                    print(f"  {logical_name}: already exists, skipping")
                    results["skipped"] += 1
                    continue
            else:
                print(f"  [DRY RUN] {logical_name}: would check if exists")

            if dry_run:
                print(f"  [DRY RUN] {logical_name}: would create")
                print(f"    Display name: {conn_ref['display_name']}")
                print(f"    Connector: {conn_ref['connector']}")
                results["created"] += 1
            else:
                data = {
                    "connectionreferencelogicalname": logical_name,
                    "connectionreferencedisplayname": conn_ref["display_name"],
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
    print(f"  Summary: {results['created']} created, {results['skipped']} skipped")
    if results["errors"] > 0:
        print(f"  Errors: {results['errors']}")

    return results


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create connection references for Early-Release Validation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Connection references created:
  - fsi_cr_dataverse_erv (Dataverse connector)
  - fsi_cr_teams_erv (Teams connector)

These connection references must be bound to actual connections in Power Automate
before any optional orchestration flow can use them.

Examples:
  # Interactive authentication
  python create_erv_connection_references.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive

  # Dry run to preview changes
  python create_erv_connection_references.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive --dry-run
        """,
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ERV_TENANT_ID"),
        help="Microsoft Entra tenant ID (or ERV_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ERV_CLIENT_ID"),
        help="Service Principal application ID (or ERV_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--access-token",
        default=os.environ.get("ERV_ACCESS_TOKEN"),
        help="Dataverse access token from managed identity or workload federation (or ERV_ACCESS_TOKEN env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ERV_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or ERV_ENVIRONMENT_URL env var)",
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

    if not args.environment_url:
        parser.error("--environment-url is required")
    if not args.access_token and not args.tenant_id:
        parser.error("--tenant-id is required unless --access-token/ERV_ACCESS_TOKEN is provided")
    if not args.access_token and not args.client_id and not args.interactive:
        parser.error("--client-id is required unless --interactive or --access-token is specified")

    client_secret = os.environ.get("ERV_CLIENT_SECRET")
    if not args.access_token and not args.interactive and not client_secret:
        if args.client_id:
            import getpass

            # legacy: dev-only — replace with managed identity in production
            client_secret = getpass.getpass("Client secret: ")

    try:
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            access_token=args.access_token,
            interactive=args.interactive,
        )

        results = create_connection_references(client, dry_run=args.dry_run)

        if results["errors"] > 0:
            sys.exit(1)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
