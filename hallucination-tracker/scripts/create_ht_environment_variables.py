#!/usr/bin/env python3
"""
Create Dataverse environment variables for Hallucination Tracker.

Environment variables store configurable settings for pattern analysis
windows, clustering thresholds, and notification targets used by the
hallucination tracking and alerting workflows.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"))
from dataverse_client import DataverseClient

ENV_VARIABLES = [
    {
        "schemaname": "fsi_HT_DataverseUrl",
        "displayname": "HT - Dataverse URL",
        "description": "Dataverse environment URL for Hallucination Tracker API calls",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_HT_AnalysisWindowDays",
        "displayname": "HT - Analysis Window (Days)",
        "description": "Number of days of data to include in pattern analysis (default: 30)",
        "type": "Decimal",
        "defaultvalue": "30",
    },
    {
        "schemaname": "fsi_HT_ClusterThreshold",
        "displayname": "HT - Cluster Threshold",
        "description": "Minimum number of reports required to form a category cluster (default: 3)",
        "type": "Decimal",
        "defaultvalue": "3",
    },
    {
        "schemaname": "fsi_HT_AgentClusterThreshold",
        "displayname": "HT - Agent Cluster Threshold",
        "description": "Minimum number of reports per agent to flag for review (default: 5)",
        "type": "Decimal",
        "defaultvalue": "5",
    },
    {
        "schemaname": "fsi_HT_NotificationEmail",
        "displayname": "HT - Notification Email",
        "description": "Email address for critical hallucination pattern alerts",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_HT_TeamsGroupId",
        "displayname": "HT - Teams Group ID",
        "description": "Microsoft Teams group ID for hallucination pattern alerts",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_HT_TeamsChannelId",
        "displayname": "HT - Teams Channel ID",
        "description": "Microsoft Teams channel ID for hallucination pattern alerts",
        "type": "String",
        "defaultvalue": "",
    },
]


def create_environment_variables(client: DataverseClient, dry_run: bool = False) -> dict:
    """
    Create environment variables for Hallucination Tracker configuration.

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
                        "environmentvariabledefinitionid@odata.bind": f"/environmentvariabledefinitions({definition_id})",
                    }
                    client.create_record("environmentvariablevalues", value_data)
                except Exception as val_err:
                    print(f"  {schemaname}: value creation failed, rolling back definition - {val_err}")
                    try:
                        client.delete_record("environmentvariabledefinitions", definition_id)
                    except Exception as cleanup_err:
                        print(f"  {schemaname}: WARNING - rollback failed, orphaned definition {definition_id} - {cleanup_err}")
                    raise

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
        description="Create environment variables for Hallucination Tracker",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Environment variables created:
  - fsi_HT_DataverseUrl (Dataverse environment URL)
  - fsi_HT_AnalysisWindowDays (30 days)
  - fsi_HT_ClusterThreshold (3 reports)
  - fsi_HT_AgentClusterThreshold (5 reports per agent)
  - fsi_HT_NotificationEmail (alert email)
  - fsi_HT_TeamsGroupId (Teams group)
  - fsi_HT_TeamsChannelId (Teams channel)

Examples:
  # Interactive authentication
  python create_ht_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive

  # Service Principal authentication
  python create_ht_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --client-id <app-id>

  # Dry run to preview changes
  python create_ht_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive --dry-run
        """
    )

    # Connection arguments
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("HT_TENANT_ID"),
        help="Microsoft Entra tenant ID (or HT_TENANT_ID env var)"
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("HT_CLIENT_ID"),
        help="Service Principal application ID (or HT_CLIENT_ID env var)"
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("HT_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or HT_ENVIRONMENT_URL env var)"
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
    # legacy: dev-only - replace with managed identity in production
    client_secret = os.environ.get("HT_CLIENT_SECRET")
    if not args.interactive and not client_secret:
        if args.client_id:
            import getpass
            client_secret = getpass.getpass("Client secret (legacy dev-only): ")

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

        # Create environment variables
        results = create_environment_variables(client, dry_run=args.dry_run)

        # Exit with error if any failures
        if results["errors"] > 0:
            sys.exit(1)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
