#!/usr/bin/env python3
"""
Create Dataverse environment variables for RAG Source Validator.

Environment variables store configurable validation thresholds, notification
targets, and API endpoints for knowledge source integrity validation.
"""

import argparse
import os
import sys
from typing import Optional

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"))
from dataverse_client import DataverseClient

ENV_VARIABLES = [
    {
        "schemaname": "fsi_RSV_DataverseUrl",
        "displayname": "RSV - Dataverse URL",
        "description": "Dataverse environment URL for all table operations",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_RSV_GraphBaseUrl",
        "displayname": "RSV - Graph Base URL",
        "description": "Microsoft Graph API base URL for SharePoint content access",
        "type": "String",
        "defaultvalue": "https://graph.microsoft.com",
    },
    {
        "schemaname": "fsi_RSV_AuthBaseUrl",
        "displayname": "RSV - Auth Base URL",
        "description": "Authentication endpoint base URL for token acquisition",
        "type": "String",
        "defaultvalue": "https://login.microsoftonline.com",
    },
    {
        "schemaname": "fsi_RSV_DefaultFreshnessThreshold",
        "displayname": "RSV - Default Freshness Threshold (Days)",
        "description": "Default freshness threshold in days — sources older than this are flagged as stale",
        "type": "Decimal",
        "defaultvalue": "7",
    },
    {
        "schemaname": "fsi_RSV_NotificationEmail",
        "displayname": "RSV - Notification Email",
        "description": "Email address for validation failure alerts",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_RSV_TeamsGroupId",
        "displayname": "RSV - Teams Group ID",
        "description": "Microsoft 365 group ID for Teams validation failure alerts",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_RSV_TeamsChannelId",
        "displayname": "RSV - Teams Channel ID",
        "description": "Teams channel ID for validation failure alerts",
        "type": "String",
        "defaultvalue": "",
    },
]


def create_environment_variables(client: DataverseClient, dry_run: bool = False) -> dict:
    """
    Create environment variables for RAG source validation settings.

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


def main():
    parser = argparse.ArgumentParser(
        description="Create environment variables for RAG Source Validator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Environment variables created:
  - fsi_RSV_DataverseUrl
  - fsi_RSV_GraphBaseUrl (https://graph.microsoft.com)
  - fsi_RSV_AuthBaseUrl (https://login.microsoftonline.com)
  - fsi_RSV_DefaultFreshnessThreshold (7 days)
  - fsi_RSV_NotificationEmail
  - fsi_RSV_TeamsGroupId
  - fsi_RSV_TeamsChannelId

Examples:
  # Interactive authentication
  python create_rsv_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive

  # Service Principal authentication
  python create_rsv_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --client-id <app-id>

  # Dry run to preview changes
  python create_rsv_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive --dry-run
        """
    )

    # Connection arguments
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("RSV_TENANT_ID"),
        help="Microsoft Entra tenant ID (or RSV_TENANT_ID env var)"
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("RSV_CLIENT_ID"),
        help="Service Principal application ID (or RSV_CLIENT_ID env var)"
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("RSV_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or RSV_ENVIRONMENT_URL env var)"
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
    client_secret = os.environ.get("RSV_CLIENT_SECRET")
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
