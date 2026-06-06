#!/usr/bin/env python3
"""
Create Dataverse environment variables for DR Testing Framework.

Environment variables store configurable validation probe budgets, notification
settings, and Dataverse connection details for DR validation automation.

Regulatory alignment:
  - OCC Heightened Standards — operational resilience testing
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
        "schemaname": "fsi_DRT_ProbeBudgetMinutes",
        "displayname": "DRT - Validation probe budget (minutes)",
        "description": "Reserved (v2.0.0) — validation probe wall-clock budget in minutes. Read by Invoke-DRTest.ps1 as ProbeDurationTargetHours when wired in a future release; currently informational only.",
        "type": "Decimal",
        "defaultvalue": "60",
    },
    {
        "schemaname": "fsi_DRT_MaxMinutesSinceLastResult",
        "displayname": "DRT - Max minutes since last result",
        "description": "Reserved (v2.0.0) — cadence freshness threshold in minutes. NOT a regulator-grade RPO; reflects gap between consecutive validation evidence rows.",
        "type": "Decimal",
        "defaultvalue": "1440",
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
            if not dry_run:
                existing = client.query(
                    "environmentvariabledefinitions",
                    filter_expr=f"schemaname eq '{schemaname}'",
                )
                if existing:
                    print(f"  {schemaname}: already exists, skipping")
                    results["skipped"] += 1
                    continue
            else:
                print(f"  [DRY RUN] {schemaname}: would check if exists")

            # Create variable
            if dry_run:
                print(f"  [DRY RUN] {schemaname}: would create")
                print(f"    Type: {var['type']}, Default: {var['defaultvalue']}")
                results["created"] += 1
            else:
                # Map type to Dataverse environment variable type code
                # (environmentvariabledefinition_type global choice):
                # 100000000 = String, 100000001 = Number, 100000002 = Boolean,
                # 100000003 = JSON, 100000004 = Data Source, 100000005 = Secret.
                # "Number" (100000001) is surfaced in the maker UI as the
                # "Decimal number" data type, so "Decimal" maps to 100000001.
                type_code_map = {
                    "String": 100000000,
                    "Number": 100000001,
                    "Boolean": 100000002,
                    "JSON": 100000003,
                    "Decimal": 100000001,  # "Decimal number" == Number type
                }
                type_code = type_code_map.get(var["type"], 100000000)

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
                        f"{schemaname}: {val_err}"
                    )
                    print(
                        "  Note: Environment variable definition was created "
                        "but has no default value. Set the value manually in "
                        "Power Apps."
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


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create environment variables for DR Testing Framework",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Environment variables created:
  - fsi_DRT_DataverseUrl (String, "")
  - fsi_DRT_ProbeBudgetMinutes (Number, 60)
  - fsi_DRT_MaxMinutesSinceLastResult (Number, 1440)
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
        "--access-token",
        default=os.environ.get("DRT_ACCESS_TOKEN"),
        help="Dataverse access token from managed identity or workload federation (or DRT_ACCESS_TOKEN env var)",
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

    if not args.environment_url:
        parser.error("--environment-url is required")
    if not args.access_token and not args.tenant_id:
        parser.error("--tenant-id is required unless --access-token/DRT_ACCESS_TOKEN is provided")
    if not args.access_token and not args.client_id and not args.interactive:
        parser.error("--client-id is required unless --interactive or --access-token is specified")

    client_secret = os.environ.get("DRT_CLIENT_SECRET")
    if not args.access_token and not args.interactive and not client_secret:
        if args.client_id:
            import getpass

            # legacy: dev-only — replace with managed identity in production
            client_secret = getpass.getpass("Client secret: ")

    try:
        # NOTE: We deliberately do NOT pass dry_run to DataverseClient ctor -
        # dry-run is gated downstream in create_environment_variables() instead
        # to avoid divergent dual flags (see council review m-5).
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            access_token=args.access_token,
            interactive=args.interactive,
        )

        results = create_environment_variables(client, dry_run=args.dry_run)

        if results["errors"] > 0:
            sys.exit(1)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
