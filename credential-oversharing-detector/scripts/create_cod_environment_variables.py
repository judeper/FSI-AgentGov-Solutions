#!/usr/bin/env python3
"""
Create Dataverse environment variables for Credential Oversharing Detector.

Environment variables store configurable scan thresholds, credential age limits,
remediation settings, and notification targets for oversharing detection.
"""

import argparse
import os
import sys
from typing import Optional

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"))
from dataverse_client import DataverseClient

ENV_VARIABLES = [
    {
        "schemaname": "fsi_COD_ScanFrequencyHours",
        "displayname": "COD - Scan Frequency (Hours)",
        "description": "Hours between scheduled credential oversharing scans (default: 24)",
        "type": "Decimal",
        "defaultvalue": "24",
    },
    {
        "schemaname": "fsi_COD_DataverseUrl",
        "displayname": "COD - Dataverse URL",
        "description": "Dataverse environment URL for scan result persistence",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_COD_TeamsGroupId",
        "displayname": "COD - Teams Group ID",
        "description": "Teams group/team ID for credential alert routing",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_COD_TeamsChannelId",
        "displayname": "COD - Teams Channel ID",
        "description": "Teams channel ID for credential alert routing",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_COD_SecurityApproverEmail",
        "displayname": "COD - Security Approver Email",
        "description": "Security team email for exception approvals",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_COD_ComplianceApproverEmail",
        "displayname": "COD - Compliance Approver Email",
        "description": "Compliance team email for exception approvals",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_COD_DefaultExceptionDays",
        "displayname": "COD - Default Exception Duration (Days)",
        "description": "Default exception duration in days (default: 90)",
        "type": "Decimal",
        "defaultvalue": "90",
    },
    {
        "schemaname": "fsi_COD_MaxOAuthScopeThreshold",
        "displayname": "COD - Max OAuth Scope Threshold",
        "description": "Maximum OAuth scopes before flagging as overshared (default: 10)",
        "type": "Decimal",
        "defaultvalue": "10",
    },
    {
        "schemaname": "fsi_COD_MaxCredentialAgeDays",
        "displayname": "COD - Max Credential Age (Days)",
        "description": "Maximum credential age in days before rotation alert (default: 90)",
        "type": "Decimal",
        "defaultvalue": "90",
    },
    {
        "schemaname": "fsi_COD_AutoRemediateEnabled",
        "displayname": "COD - Auto-Remediate Enabled",
        "description": "Enable automatic remediation actions (default: false)",
        "type": "String",
        "defaultvalue": "false",
    },
    {
        "schemaname": "fsi_COD_ExpirationWarningDays",
        "displayname": "COD - Expiration Warning Days",
        "description": "Days before exception expiration to send warning alerts (default: 14)",
        "type": "Decimal",
        "defaultvalue": "14",
    },
]


def create_environment_variables(client: DataverseClient, dry_run: bool = False) -> dict:
    """
    Create environment variables for credential oversharing detection thresholds.

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
        description="Create environment variables for Credential Oversharing Detector",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Environment variables created:
  - fsi_COD_ScanFrequencyHours (24 hours)
  - fsi_COD_DataverseUrl
  - fsi_COD_TeamsGroupId
  - fsi_COD_TeamsChannelId
  - fsi_COD_SecurityApproverEmail
  - fsi_COD_ComplianceApproverEmail
  - fsi_COD_DefaultExceptionDays (90 days)
  - fsi_COD_MaxOAuthScopeThreshold (10 scopes)
  - fsi_COD_MaxCredentialAgeDays (90 days)
  - fsi_COD_AutoRemediateEnabled (false)
  - fsi_COD_ExpirationWarningDays (14 days)

Examples:
  # Interactive authentication
  python create_cod_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive

  # Service Principal authentication
  python create_cod_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --client-id <app-id>

  # Dry run to preview changes
  python create_cod_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive --dry-run
        """
    )

    # Connection arguments
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("COD_TENANT_ID"),
        help="Microsoft Entra tenant ID (or COD_TENANT_ID env var)"
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("COD_CLIENT_ID"),
        help="Service Principal application ID (or COD_CLIENT_ID env var)"
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("COD_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or COD_ENVIRONMENT_URL env var)"
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
    client_secret = os.environ.get("COD_CLIENT_SECRET")
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
