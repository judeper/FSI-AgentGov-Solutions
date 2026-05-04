#!/usr/bin/env python3
"""
Create Dataverse environment variables for Unrestricted Agent Sharing Detector.

Environment variables store configurable detection thresholds, remediation settings,
and notification targets for sharing violation scanning.
"""

import argparse
import os
import sys
from typing import Optional

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"))
from dataverse_client import DataverseClient

ENV_VARIABLES = [
    {
        "schemaname": "fsi_UASD_ScanFrequencyHours",
        "displayname": "UASD - Scan Frequency (Hours)",
        "description": "Detection scan interval in hours (default: 24)",
        "type": "Decimal",
        "defaultvalue": "24",
    },
    {
        "schemaname": "fsi_UASD_AutoRemediatePublicLink",
        "displayname": "UASD - Auto-Remediate Public Links",
        "description": "Automatically remediate public internet link violations (default: false)",
        "type": "String",
        "defaultvalue": "false",
    },
    {
        "schemaname": "fsi_UASD_MaxIndividualShares",
        "displayname": "UASD - Max Individual Shares",
        "description": "Threshold for excessive individual sharing violations (default: 5)",
        "type": "Decimal",
        "defaultvalue": "5",
    },
    {
        "schemaname": "fsi_UASD_HomeTenantId",
        "displayname": "UASD - Home Tenant ID",
        "description": "Entra ID home tenant GUID for cross-tenant detection",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_UASD_DefaultExceptionDays",
        "displayname": "UASD - Default Exception Duration (Days)",
        "description": "Default exception duration in days (default: 90)",
        "type": "Decimal",
        "defaultvalue": "90",
    },
    {
        "schemaname": "fsi_UASD_SecurityApproverEmail",
        "displayname": "UASD - Security Approver Email",
        "description": "Security team approver email for dual-approval workflow",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_UASD_DataOwnerApproverEmail",
        "displayname": "UASD - Data Owner Approver Email",
        "description": "Data owner approver email for dual-approval workflow",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_UASD_ComplianceApproverEmail",
        "displayname": "UASD - Compliance Approver Email",
        "description": "Compliance/regulatory approver email for Restricted data classification approval",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_UASD_RemediationDryRun",
        "displayname": "UASD - Remediation Dry Run",
        "description": "Dry-run mode prevents remediation changes (default: true)",
        "type": "String",
        "defaultvalue": "true",
    },
    {
        "schemaname": "fsi_UASD_TeamsGroupId",
        "displayname": "UASD - Teams Group ID",
        "description": "Teams group/team ID for violation alert notifications",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_UASD_TeamsChannelId",
        "displayname": "UASD - Teams Channel ID",
        "description": "Teams channel ID for posting violation alert notifications",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_UASD_DataverseUrl",
        "displayname": "UASD - Dataverse URL",
        "description": "Dataverse environment URL for API calls",
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_UASD_ExpirationWarningDays",
        "displayname": "UASD - Expiration Warning Days",
        "description": "Number of days before exception expiration to send warning alerts (default: 7)",
        "type": "Decimal",
        "defaultvalue": "7",
    },
]


def create_environment_variables(client: DataverseClient, dry_run: bool = False) -> dict:
    """
    Create environment variables for sharing detection and remediation thresholds.

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
        description="Create environment variables for Unrestricted Agent Sharing Detector",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Environment variables created:
  - fsi_UASD_ScanFrequencyHours (24 hours)
  - fsi_UASD_AutoRemediatePublicLink (false)
  - fsi_UASD_MaxIndividualShares (5)
  - fsi_UASD_HomeTenantId
  - fsi_UASD_DefaultExceptionDays (90 days)
  - fsi_UASD_SecurityApproverEmail
  - fsi_UASD_DataOwnerApproverEmail
  - fsi_UASD_ComplianceApproverEmail
  - fsi_UASD_RemediationDryRun (true)
  - fsi_UASD_TeamsGroupId
  - fsi_UASD_TeamsChannelId
  - fsi_UASD_DataverseUrl
  - fsi_UASD_ExpirationWarningDays (7 days)

Examples:
  # Interactive authentication
  python create_uasd_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive

  # Legacy dev-only service principal secret authentication
  python create_uasd_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --client-id <app-id>

  # Dry run to preview changes
  python create_uasd_environment_variables.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive --dry-run
        """
    )

    # Connection arguments
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("UASD_TENANT_ID"),
        help="Microsoft Entra tenant ID (or UASD_TENANT_ID env var)"
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("UASD_CLIENT_ID"),
        help="Service Principal application ID (or UASD_CLIENT_ID env var)"
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("UASD_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or UASD_ENVIRONMENT_URL env var)"
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

    # legacy: dev-only — replace with managed identity in production
    # Handle client secret for service principal fallback auth
    client_secret = os.environ.get("UASD_CLIENT_SECRET")
    if not args.interactive and not client_secret:
        if args.client_id:
            import getpass
            client_secret = getpass.getpass("Client secret (legacy dev-only fallback): ")

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
