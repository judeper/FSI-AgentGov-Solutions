#!/usr/bin/env python3
"""
Create Dataverse environment variables for Conditional Access Automation.

Deploys 16 environment variables with fsi_CAA_* prefix that control
scan configuration, notification targets, Azure infrastructure references,
and sovereign cloud portal URLs. All operations are idempotent — safe to
re-run.

Variables consumed by Power Automate flows and PowerShell scripts:
  - fsi_CAA_GracePeriodHours: Hours before newly deployed policies are validated
  - fsi_CAA_ScanFrequencyHours: Automated compliance scan interval
  - fsi_CAA_BaselineMaxAgeDays: Alert threshold for stale baselines
  - fsi_CAA_DriftSeverityEscalation: Zone 3 drift severity escalation flag
  - fsi_CAA_IncludeReportOnlyPolicies: Include report-only CA policies
  - fsi_CAA_TeamsGroupId: Teams group GUID for violation alerts
  - fsi_CAA_TeamsChannelId: Teams channel GUID for violation alerts
  - fsi_CAA_ComplianceDistributionList: Email distribution list for alerts
  - fsi_CAA_DocsBaseUrl: Documentation site root URL
  - fsi_CAA_SubscriptionId: Azure subscription for Automation Account
  - fsi_CAA_ResourceGroup: Azure resource group for Automation Account
  - fsi_CAA_AutomationAccount: Azure Automation account name
  - fsi_CAA_EntraPortalUrl: Entra admin center URL (sovereign cloud override)
  - fsi_CAA_AzurePortalUrl: Azure portal URL (sovereign cloud override)
  - fsi_CAA_PowerPlatformAdminUrl: Power Platform admin URL (sovereign cloud)
  - fsi_CAA_DataverseUrl: Dataverse environment URL
"""

import argparse
import os
import sys

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared")
)
from dataverse_client import DataverseClient

# =============================================================================
# Environment Variable Definitions
# =============================================================================

# Dataverse environment variable types:
#   100000000 = String
#   100000001 = Decimal Number

ENV_VARIABLES = [
    # -------------------------------------------------------------------------
    # Scan Configuration
    # -------------------------------------------------------------------------
    {
        "schemaname": "fsi_CAA_GracePeriodHours",
        "displayname": "CAA - Grace Period (Hours)",
        "description": (
            "Hours before newly deployed policies are included "
            "in validation (default: 48)"
        ),
        "type": "Decimal",
        "defaultvalue": "48",
    },
    {
        "schemaname": "fsi_CAA_ScanFrequencyHours",
        "displayname": "CAA - Scan Frequency (Hours)",
        "description": (
            "Automated compliance scan interval for the daily flow "
            "(default: 24)"
        ),
        "type": "Decimal",
        "defaultvalue": "24",
    },
    {
        "schemaname": "fsi_CAA_BaselineMaxAgeDays",
        "displayname": "CAA - Maximum Baseline Age (Days)",
        "description": (
            "Alert threshold for stale baselines requiring refresh "
            "(default: 30)"
        ),
        "type": "Decimal",
        "defaultvalue": "30",
    },
    {
        "schemaname": "fsi_CAA_DriftSeverityEscalation",
        "displayname": "CAA - Drift Severity Escalation",
        "description": (
            "Whether Zone 3 drift violations receive severity +1 "
            "(default: true)"
        ),
        "type": "String",
        "defaultvalue": "true",
    },
    {
        "schemaname": "fsi_CAA_IncludeReportOnlyPolicies",
        "displayname": "CAA - Include Report-Only Policies",
        "description": (
            "Whether report-only CA policies are included in "
            "validation scans (default: true)"
        ),
        "type": "String",
        "defaultvalue": "true",
    },
    # -------------------------------------------------------------------------
    # Notification Targets
    # -------------------------------------------------------------------------
    {
        "schemaname": "fsi_CAA_TeamsGroupId",
        "displayname": "CAA - Teams Alert Group ID",
        "description": (
            "Microsoft Teams group GUID for violation alert delivery"
        ),
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_CAA_TeamsChannelId",
        "displayname": "CAA - Teams Alert Channel ID",
        "description": (
            "Microsoft Teams channel GUID for violation alert delivery"
        ),
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_CAA_ComplianceDistributionList",
        "displayname": "CAA - Compliance Distribution List",
        "description": (
            "Email distribution list for compliance alert routing"
        ),
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_CAA_DocsBaseUrl",
        "displayname": "CAA - Documentation Base URL",
        "description": (
            "Documentation site root URL for adaptive card links"
        ),
        "type": "String",
        "defaultvalue": "",
    },
    # -------------------------------------------------------------------------
    # Azure Infrastructure
    # -------------------------------------------------------------------------
    {
        "schemaname": "fsi_CAA_SubscriptionId",
        "displayname": "CAA - Azure Subscription ID",
        "description": (
            "Azure subscription GUID containing the Automation Account"
        ),
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_CAA_ResourceGroup",
        "displayname": "CAA - Resource Group",
        "description": (
            "Azure resource group containing the Automation Account"
        ),
        "type": "String",
        "defaultvalue": "",
    },
    {
        "schemaname": "fsi_CAA_AutomationAccount",
        "displayname": "CAA - Automation Account",
        "description": (
            "Azure Automation account name for validation "
            "runbook execution"
        ),
        "type": "String",
        "defaultvalue": "",
    },
    # -------------------------------------------------------------------------
    # Portal URLs (sovereign cloud overrides)
    # -------------------------------------------------------------------------
    {
        "schemaname": "fsi_CAA_EntraPortalUrl",
        "displayname": "CAA - Entra Portal URL",
        "description": (
            "Entra admin center base URL (override for sovereign clouds, "
            "e.g., https://entra.microsoft.us for GCC High)"
        ),
        "type": "String",
        "defaultvalue": "https://entra.microsoft.com",
    },
    {
        "schemaname": "fsi_CAA_AzurePortalUrl",
        "displayname": "CAA - Azure Portal URL",
        "description": (
            "Azure portal base URL (override for sovereign clouds, "
            "e.g., https://portal.azure.us for GCC High)"
        ),
        "type": "String",
        "defaultvalue": "https://portal.azure.com",
    },
    {
        "schemaname": "fsi_CAA_PowerPlatformAdminUrl",
        "displayname": "CAA - Power Platform Admin URL",
        "description": (
            "Power Platform admin center base URL "
            "(override for sovereign clouds)"
        ),
        "type": "String",
        "defaultvalue": "https://admin.powerplatform.microsoft.com",
    },
    # -------------------------------------------------------------------------
    # Dataverse
    # -------------------------------------------------------------------------
    {
        "schemaname": "fsi_CAA_DataverseUrl",
        "displayname": "CAA - Dataverse URL",
        "description": (
            "Dataverse environment URL "
            "(e.g., https://org.crm.dynamics.com)"
        ),
        "type": "String",
        "defaultvalue": "",
    },
]


# =============================================================================
# Deployment Functions
# =============================================================================


def create_environment_variables(
    client: DataverseClient, dry_run: bool = False
) -> dict:
    """
    Create environment variables for CAA configuration.

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
                print(
                    f"    Type: {var['type']}, "
                    f"Default: {var['defaultvalue']}"
                )
                results["created"] += 1
            else:
                type_code = (
                    100000001 if var["type"] == "Decimal" else 100000000
                )

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
                    client.create_record(
                        "environmentvariablevalues", value_data
                    )
                except Exception as val_err:
                    print(
                        f"  {schemaname}: value creation failed, "
                        f"rolling back definition - {val_err}"
                    )
                    try:
                        client.delete_record(
                            "environmentvariabledefinitions", definition_id
                        )
                    except Exception as cleanup_err:
                        print(
                            f"  {schemaname}: WARNING - rollback failed, "
                            f"orphaned definition {definition_id} - "
                            f"{cleanup_err}"
                        )
                    raise

                print(f"  {schemaname}: created")
                print(
                    f"    Type: {var['type']}, "
                    f"Default: {var['defaultvalue']}"
                )
                results["created"] += 1

        except Exception as e:
            print(f"  {schemaname}: ERROR - {e}")
            results["errors"] += 1

    print()
    print(
        f"  Summary: {results['created']} created, "
        f"{results['skipped']} skipped"
    )
    if results["errors"] > 0:
        print(f"  Errors: {results['errors']}")

    return results


# =============================================================================
# CLI Entry Point
# =============================================================================


def main():
    parser = argparse.ArgumentParser(
        description=(
            "Create Dataverse environment variables for "
            "Conditional Access Automation"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Environment variables created (16 total):\n"
            "  Scan config:     fsi_CAA_GracePeriodHours, "
            "fsi_CAA_ScanFrequencyHours,\n"
            "                   fsi_CAA_BaselineMaxAgeDays, "
            "fsi_CAA_DriftSeverityEscalation,\n"
            "                   fsi_CAA_IncludeReportOnlyPolicies\n"
            "  Notifications:   fsi_CAA_TeamsGroupId, "
            "fsi_CAA_TeamsChannelId,\n"
            "                   fsi_CAA_ComplianceDistributionList, "
            "fsi_CAA_DocsBaseUrl\n"
            "  Infrastructure:  fsi_CAA_SubscriptionId, "
            "fsi_CAA_ResourceGroup,\n"
            "                   fsi_CAA_AutomationAccount\n"
            "  Portal URLs:     fsi_CAA_EntraPortalUrl, "
            "fsi_CAA_AzurePortalUrl,\n"
            "                   fsi_CAA_PowerPlatformAdminUrl\n"
            "  Dataverse:       fsi_CAA_DataverseUrl\n\n"
            "Examples:\n"
            "  # Interactive authentication\n"
            "  python create_caa_environment_variables.py \\\n"
            "      --tenant-id <tenant-id> \\\n"
            "      --environment-url https://org.crm.dynamics.com \\\n"
            "      --interactive\n\n"
            "  # Service Principal authentication\n"
            "  python create_caa_environment_variables.py \\\n"
            "      --tenant-id <tenant-id> \\\n"
            "      --environment-url https://org.crm.dynamics.com \\\n"
            "      --client-id <app-id>\n\n"
            "  # Dry run to preview changes\n"
            "  python create_caa_environment_variables.py \\\n"
            "      --tenant-id <tenant-id> \\\n"
            "      --environment-url https://org.crm.dynamics.com \\\n"
            "      --interactive --dry-run\n"
        ),
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("CAA_TENANT_ID"),
        help="Microsoft Entra tenant ID (or CAA_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("CAA_CLIENT_ID"),
        help="Service Principal application ID (or CAA_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("CAA_CLIENT_SECRET"),
        help="Client secret (or CAA_CLIENT_SECRET env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("CAA_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or CAA_ENVIRONMENT_URL env var)",
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

    client_secret = args.client_secret or os.environ.get("CAA_CLIENT_SECRET")
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
