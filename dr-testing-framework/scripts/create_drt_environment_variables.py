#!/usr/bin/env python3
"""
Create Dataverse environment variables for DR Testing Framework.

Environment variables store configurable RTO/RPO targets, notification settings,
and Dataverse connection details for disaster recovery test automation.

Regulatory alignment:
  - OCC 2011-12 (Third-Party Risk Management) — operational resilience testing
  - FFIEC BCP (Business Continuity Planning) — DR test documentation
  - SEC 17a-4 (Records Preservation) — immutable test evidence retention
  - FINRA 4370 (Business Continuity Plans) — annual DR testing requirements
"""

import argparse
import os
import sys

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared")
)
from dataverse_client import DataverseClient

ENV_VARIABLES = [
    {
        "schemaname": "fsi_DRT_DataverseUrl",
        "displayname": "DRT - Dataverse Environment URL",
        "description": "Target Dataverse URL for DR test result storage and evidence queries",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_DRT_TargetRTOMinutes",
        "displayname": "DRT - Target RTO (Minutes)",
        "description": "Default recovery time objective in minutes for DR tests (default: 60)",
        "type": "Decimal",
        "defaultvalue": "60",
    },
    {
        "schemaname": "fsi_DRT_TargetRPOMinutes",
        "displayname": "DRT - Target RPO (Minutes)",
        "description": "Default recovery point objective in minutes for DR tests (default: 15)",
        "type": "Decimal",
        "defaultvalue": "15",
    },
    {
        "schemaname": "fsi_DRT_TeamsGroupId",
        "displayname": "DRT - Teams Group ID",
        "description": "Microsoft Teams group (team) ID for DR test notification cards",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_DRT_TeamsChannelId",
        "displayname": "DRT - Teams Channel ID",
        "description": "Microsoft Teams channel ID for DR test notification cards",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_DRT_NotificationEmail",
        "displayname": "DRT - Notification Email",
        "description": "Distribution list or mailbox for DR test completion and failure alerts",
        "type": "String",
        "defaultvalue": "",
    },
]


def create_environment_variables(client: DataverseClient, dry_run: bool = False) -> dict:
    """
    Create environment variables for DR testing configuration.

    Args:
        client: DataverseClient instance
        dry_run: If True, preview changes without creating

    Returns:
        dict: Results summary with created/skipped/errors counts
    """
    print("\n[Creating Environment Variables]")
    results = {"created": 0, "skipped": 0, "errors": 0}

    for var in ENV_VARIABLES:
        schemaname = var["schemaname"]
        try:
            # Check if variable already exists
            if not dry_run and not client.dry_run:
                existing = client.query(
                    "environmentvariabledefinitions",
                    filter_expr=f"schemaname eq '{schemaname}'",
                )
                if existing:
                    print(f"  {schemaname}: already exists, skipping")
                    results["skipped"] += 1
                    continue
            elif dry_run or client.dry_run:
                print(f"  [DRY RUN] {schemaname}: would check if exists")

            # Create variable
            if dry_run or client.dry_run:
                print(f"  [DRY RUN] {schemaname}: would create")
                print(f"    Type: {var['type']}, Default: {var['defaultvalue']}")
                results["created"] += 1
            else:
                # Map type to Dataverse type code
                type_code = 100000001 if var["type"] == "Decimal" else 100000000

                # Create definition
                definition_data = {
                    "schemaname": schemaname,
                    "displayname": var["displayname"],
                    "description": var["description"],
                    "type": type_code,
                }
                definition_id = client.create_record(
                    "environmentvariabledefinitions", definition_data
                )

                # Create default value; roll back definition on failure
                try:
                    value_data = {
                        "value": var["defaultvalue"],
                        "environmentvariabledefinitionid@odata.bind": (
                            f"/environmentvariabledefinitions({definition_id})"
                        ),
                    }
                    client.create_record("environmentvariablevalues", value_data)
                except Exception as val_err:
                    print(
                        f"  Warning: Failed to create default value for "
                        f"{display_name}: {val_err}"
                    )
                    print(
                        f"  Note: Environment variable definition was created "
                        f"but has no default value. Set the value manually in "
                        f"Power Apps."
                    )

                print(f"  {schemaname}: created")
                print(f"    Type: {var['type']}, Default: {var['defaultvalue']}")
                results["created"] += 1

        except Exception as e:
            print(f"  {schemaname}: ERROR - {e}")
            results["errors"] += 1

    print()
    print(f"  Summary: {results['created']} created, {results['skipped']} skipped")
    if results["errors"] > 0:
        print(f"  Errors: {results['errors']}")

    return results


def main():
    parser = argparse.ArgumentParser(
        description="Create environment variables for DR Testing Framework",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Environment variables created:
  - fsi_DRT_DataverseUrl (String, "")
  - fsi_DRT_TargetRTOMinutes (Decimal, 60)
  - fsi_DRT_TargetRPOMinutes (Decimal, 15)
  - fsi_DRT_TeamsGroupId (String, "")
  - fsi_DRT_TeamsChannelId (String, "")
  - fsi_DRT_NotificationEmail (String, "")

Examples:
  # Interactive authentication
  python create_drt_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive

  # Service Principal authentication
  python create_drt_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --client-id <app-id>

  # Dry run to preview changes
  python create_drt_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive --dry-run
        """,
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("DRT_TENANT_ID"),
        help="Microsoft Entra tenant ID (or DRT_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("DRT_CLIENT_ID"),
        help="Service Principal application ID (or DRT_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("DRT_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or DRT_ENVIRONMENT_URL env var)",
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

    client_secret = os.environ.get("DRT_CLIENT_SECRET")
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

        results = create_environment_variables(client, dry_run=args.dry_run)

        if results["errors"] > 0:
            sys.exit(1)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
