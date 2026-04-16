#!/usr/bin/env python3
"""
Create connection references for Agent Access Governance Monitor.

Connection references define connectors needed for Power Automate flows.
Actual connections are bound post-deployment during solution import or runtime.
"""

import argparse
import os
import sys

from aam_client import AAMClient

# ============================================================================
# Connection Reference Definitions
# ============================================================================

CONNECTION_REFS = [
    {
        "logical_name": "fsi_cr_dataverse_accessmonitor",
        "display_name": "Dataverse - Agent Access Monitor",
        "connector": "shared_commondataserviceforapps",
        "description": "Dataverse connector for reading/writing access baselines and validation history",
    },
    {
        "logical_name": "fsi_cr_office365_accessmonitor",
        "display_name": "Office 365 - Agent Access Monitor",
        "connector": "shared_office365",
        "description": "Office 365 connector for tenant-level access and permission queries",
    },
    {
        "logical_name": "fsi_cr_teams_accessmonitor",
        "display_name": "Teams - Agent Access Monitor",
        "connector": "shared_teams",
        "description": "Teams connector for sending compliance alert notifications",
    },
]


def create_connection_references(client: AAMClient, dry_run: bool = False) -> dict:
    """
    Create connection references for AAM solution.

    Args:
        client: Authenticated AAMClient
        dry_run: If True, preview without creating

    Returns:
        Results dict with created/skipped counts
    """
    print("\n[Creating Connection References]")

    results = {"created": 0, "skipped": 0, "errors": 0}

    for conn_ref in CONNECTION_REFS:
        logical_name = conn_ref["logical_name"]

        # Check if connection reference already exists
        try:
            if not dry_run and not client.dry_run:
                # Query existing connection references
                existing = client.query(
                    "connectionreferences",
                    filter_expr=f"connectionreferencelogicalname eq '{logical_name}'",
                )
                if existing:
                    print(f"  {logical_name}: already exists, skipping")
                    results["skipped"] += 1
                    continue
            elif dry_run or client.dry_run:
                print(f"  [DRY RUN] {logical_name}: would check if exists")

            if dry_run or client.dry_run:
                print(f"  [DRY RUN] {logical_name}: would create")
                print(f"    Display name: {conn_ref['display_name']}")
                print(f"    Connector: {conn_ref['connector']}")
                results["created"] += 1
            else:
                # Create connection reference (definition only)
                # Actual connections are bound during solution import or runtime
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

    # Summary
    print()
    print(f"  Summary: {results['created']} created, {results['skipped']} skipped")
    if results["errors"] > 0:
        print(f"  Errors: {results['errors']}")

    # Post-creation binding instructions
    print()
    print("  Connection references created (definitions only).")
    print("  After deployment, bind actual connections in Power Automate:")
    print("    1. Open make.powerapps.com → Solutions → Agent Access Monitor")
    print("    2. Select each connection reference")
    print("    3. Click \"Set connection\" and choose or create the connection")

    return results


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Create connection references for Agent Access Governance Monitor",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("AAM_TENANT_ID"),
        help="Entra ID tenant ID (or set AAM_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("AAM_CLIENT_ID"),
        help="Application (client) ID (or set AAM_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("AAM_CLIENT_SECRET"),
        help="Client secret (INSECURE: visible in process listings; prefer AAM_CLIENT_SECRET env var or interactive prompt)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("AAM_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set AAM_ENVIRONMENT_URL env var)",
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
    if not args.tenant_id or not args.environment_url:
        parser.error("--tenant-id and --environment-url are required")

    # Get client secret if needed
    client_secret = args.client_secret
    if not args.interactive and not client_secret:
        if args.client_id:
            import getpass

            client_secret = getpass.getpass("Client secret: ")

    try:
        client = AAMClient(
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
