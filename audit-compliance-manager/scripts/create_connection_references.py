#!/usr/bin/env python3
"""
Create connection references for Audit Configuration Validator.

Connection references define connectors needed for the solution.
Actual connections are bound during solution import or runtime.
"""

import argparse
import os
import sys

from acv_client import ACVClient

# ============================================================================
# Connection Reference Definitions
# ============================================================================

CONNECTION_REFS = [
    {
        "logical_name": "fsi_cr_dataverse_auditvalidation",
        "display_name": "Dataverse - Audit Configuration Validator",
        "connector": "shared_commondataserviceforapps",
        "description": "Dataverse connector for reading/writing validation history",
    },
    {
        "logical_name": "fsi_cr_office365_auditvalidation",
        "display_name": "Office 365 - Audit Configuration Validator",
        "connector": "shared_office365",
        "description": "Office 365 connector for tenant-level audit validation",
    },
]


def create_connection_references(client: ACVClient, dry_run: bool = False) -> dict:
    """
    Create connection references for ACV solution.

    Args:
        client: Authenticated ACVClient
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
            existing = client.query(
                "connectionreferences",
                filter_expr=f"connectionreferencelogicalname eq '{logical_name}'",
            )
            if existing:
                print(f"  {logical_name}: already exists, skipping")
                results["skipped"] += 1
                continue

            if dry_run or client.dry_run:
                print(f"  [DRY RUN] {logical_name}: would create")
                print(f"    Display name: {conn_ref['display_name']}")
                print(f"    Connector: {conn_ref['connector']}")
                results["created"] += 1
            else:
                # Create connection reference
                # Connection references are definition-only at creation time
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

    return results


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Create connection references for ACV",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ACV_TENANT_ID"),
        help="Microsoft Entra ID tenant ID",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ACV_CLIENT_ID"),
        help="Application (client) ID",
    )
    # Client secret read from ACV_CLIENT_SECRET env var (not CLI arg to avoid shell history exposure)
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ACV_ENVIRONMENT_URL"),
        help="Dataverse environment URL",
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
    parser.add_argument(
        "--solution-name",
        default="AuditComplianceManager",
        help="Solution unique name for component registration (default: AuditComplianceManager)",
    )

    args = parser.parse_args()

    # Validate required arguments
    if not args.tenant_id or not args.environment_url:
        parser.error("--tenant-id and --environment-url are required")

    # Validate auth mode
    if not args.interactive and not args.client_id:
        parser.error(
            "Either --interactive or --client-id is required.\n"
            "Use --interactive for manual runs or provide legacy dev-only service principal credentials."
        )
    if args.interactive and not args.client_id:
        parser.error(
            "--client-id is required for interactive authentication.\n"
            "Register an app in Microsoft Entra ID and provide --client-id."
        )

    # legacy: dev-only — replace with managed identity in production
    # Get client secret from env var or prompt (never via CLI arg to avoid shell history exposure)
    client_secret = os.environ.get("ACV_CLIENT_SECRET")
    if not args.interactive and args.client_id and not client_secret:
        import getpass
        client_secret = getpass.getpass("Client secret: ")

    try:
        client = ACVClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            interactive=args.interactive,
            dry_run=args.dry_run,
            solution_name=args.solution_name,
        )

        results = create_connection_references(client, dry_run=args.dry_run)

        if results["errors"] > 0:
            sys.exit(1)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
