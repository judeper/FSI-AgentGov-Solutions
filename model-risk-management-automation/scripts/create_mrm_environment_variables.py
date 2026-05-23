#!/usr/bin/env python3
"""Create Dataverse environment variables for Model Risk Management Automation.

Deploys 30 environment variables with fsi_MRM_* prefix that control
feature flags, notification targets, infrastructure, monitoring thresholds,
validation SLAs, tenant configuration, material change detection, and
validation cadence. All operations are idempotent — safe to re-run.

Variables consumed by Power Automate flows:
  - fsi_MRM_IsMRMAutomationEnabled: Master feature flag for MRM automation
  - fsi_MRM_IsAgent365LifecycleEnabled: Cross-solution flag from agent-365-lifecycle-governance
  - fsi_MRM_GovernanceTeamEmail: Distribution list for MRM notifications
  - fsi_MRM_EscalationApproverUPN: Skip-level approver for SLA breaches
  - fsi_MRM_FlowAdministrators: Email for flow error and API failure alerts
  - fsi_MRM_DataverseEnvironmentUrl: Target Dataverse environment URL
  - fsi_MRM_MRMSiteUrl: SharePoint site URL for Agent Card Library
  - fsi_MRM_MRMAgentCardLibrary: SharePoint document library name for Agent Cards
  - fsi_MRM_FSI_FRAMEWORK_VERSION: FSI-AgentGov framework version tag
  - fsi_MRM_MonitoringThreshold_ErrorRate_Warning: Error rate warning threshold
  - fsi_MRM_MonitoringThreshold_ErrorRate_Revalidation: Error rate revalidation threshold
  - fsi_MRM_MonitoringThreshold_EscalationRate_Warning: Escalation rate warning threshold
  - fsi_MRM_MonitoringThreshold_EscalationRate_Revalidation: Escalation rate revalidation threshold
  - fsi_MRM_MonitoringThreshold_OutOfScope_Warning: Out-of-scope warning threshold
  - fsi_MRM_MonitoringThreshold_OutOfScope_Revalidation: Out-of-scope revalidation threshold
  - fsi_MRM_ValidationSLA_Tier1_Assignment: Tier 1 validator assignment SLA
  - fsi_MRM_ValidationSLA_Tier1_Findings: Tier 1 findings delivery SLA
  - fsi_MRM_ValidationSLA_Tier1_Remediation: Tier 1 remediation SLA
  - fsi_MRM_ValidationSLA_Tier2_Assignment: Tier 2 validator assignment SLA
  - fsi_MRM_ValidationSLA_Tier2_Findings: Tier 2 findings delivery SLA
  - fsi_MRM_ValidationSLA_Tier2_Remediation: Tier 2 remediation SLA
  - fsi_MRM_ValidationSLA_Tier3_Assignment: Tier 3 validator assignment SLA
  - fsi_MRM_ValidationSLA_Tier3_Findings: Tier 3 findings delivery SLA
  - fsi_MRM_ValidationSLA_Tier3_Remediation: Tier 3 remediation SLA
  - fsi_MRM_TenantId: Microsoft Entra tenant ID for interactive or legacy auth
  - fsi_MRM_RiskScoreCriticalThreshold: Critical composite score threshold
  - fsi_MRM_RiskScoreHighThreshold: High composite score threshold
  - fsi_MRM_RiskScoreMediumThreshold: Medium composite score threshold
  - fsi_MRM_MaterialChangeTextDiffThreshold: Material change text diff threshold
  - fsi_MRM_ValidationApproachingDaysLookahead: Validation due lookahead days
"""

import argparse
import os
import sys

sys.path.insert(
    0,
    os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"),
)
from dataverse_client import DataverseClient  # noqa: E402


# =============================================================================
# Environment Variable Definitions
# =============================================================================

# Dataverse environment variable types:
#   100000000 = String
#   100000001 = Decimal Number
#   100000002 = Boolean (not used — booleans stored as String "true"/"false")
#   100000003 = JSON
#   100000004 = Data Source

ENV_VAR_DEFINITIONS = [
    # -------------------------------------------------------------------------
    # Feature Flags
    # -------------------------------------------------------------------------
    {
        "schema_name": "fsi_MRM_IsMRMAutomationEnabled",
        "display_name": "MRM - Automation Enabled",
        "type": 100000000,  # String
        "default_value": "false",
        "description": (
            "Master feature flag. Set 'false' during deployment. "
            "All flows check at entry."
        ),
    },
    {
        "schema_name": "fsi_MRM_IsAgent365LifecycleEnabled",
        "display_name": "MRM - Agent 365 Lifecycle Enabled",
        "type": 100000000,  # String
        "default_value": "false",
        "description": (
            "Cross-solution flag from agent-365-lifecycle-governance. "
            "Gates Agent 365 / Microsoft Entra Agent ID registry calls."
        ),
    },
    # -------------------------------------------------------------------------
    # Notification Targets
    # -------------------------------------------------------------------------
    {
        "schema_name": "fsi_MRM_GovernanceTeamEmail",
        "display_name": "MRM - Governance Team Email",
        "type": 100000000,  # String
        "default_value": "",
        "description": (
            "Distribution list for MRM notifications and fallback "
            "when fsi_mrmofficerupn is not set."
        ),
    },
    {
        "schema_name": "fsi_MRM_EscalationApproverUPN",
        "display_name": "MRM - Escalation Approver UPN",
        "type": 100000000,  # String
        "default_value": "",
        "description": (
            "Skip-level approver for SLA breaches and "
            "revalidation confirmations."
        ),
    },
    {
        "schema_name": "fsi_MRM_FlowAdministrators",
        "display_name": "MRM - Flow Administrators",
        "type": 100000000,  # String
        "default_value": "",
        "description": (
            "Email for flow error, API failure, and "
            "Agent Card fallback alerts."
        ),
    },
    # -------------------------------------------------------------------------
    # Infrastructure
    # -------------------------------------------------------------------------
    {
        "schema_name": "fsi_MRM_DataverseEnvironmentUrl",
        "display_name": "MRM - Dataverse Environment URL",
        "type": 100000000,  # String
        "default_value": "",
        "description": (
            "Target Dataverse environment URL "
            "(e.g., https://contoso.crm.dynamics.com)."
        ),
    },
    {
        "schema_name": "fsi_MRM_MRMSiteUrl",
        "display_name": "MRM - SharePoint Site URL",
        "type": 100000000,  # String
        "default_value": "",
        "description": (
            "SharePoint site URL for Agent Card Library "
            "(e.g., https://contoso.sharepoint.com/sites/MRM)."
        ),
    },
    {
        "schema_name": "fsi_MRM_MRMAgentCardLibrary",
        "display_name": "MRM - Agent Card Library Name",
        "type": 100000000,  # String
        "default_value": "Agent Cards",
        "description": (
            "SharePoint document library name for "
            "Agent Card storage."
        ),
    },
    {
        "schema_name": "fsi_MRM_FSI_FRAMEWORK_VERSION",
        "display_name": "MRM - Framework Version",
        "type": 100000000,  # String
        "default_value": "FSI-AgentGov-v1.1",
        "description": "FSI-AgentGov framework version tag.",
    },
    # -------------------------------------------------------------------------
    # Monitoring Thresholds
    # -------------------------------------------------------------------------
    {
        "schema_name": "fsi_MRM_MonitoringThreshold_ErrorRate_Warning",
        "display_name": "MRM - Error Rate Warning Threshold",
        "type": 100000001,  # Decimal Number
        "default_value": "5",
        "description": (
            "Error rate percentage warning threshold (default: 5%)."
        ),
    },
    {
        "schema_name": "fsi_MRM_MonitoringThreshold_ErrorRate_Revalidation",
        "display_name": "MRM - Error Rate Revalidation Threshold",
        "type": 100000001,  # Decimal Number
        "default_value": "15",
        "description": (
            "Error rate percentage revalidation threshold (default: 15%)."
        ),
    },
    {
        "schema_name": "fsi_MRM_MonitoringThreshold_EscalationRate_Warning",
        "display_name": "MRM - Escalation Rate Warning Threshold",
        "type": 100000001,  # Decimal Number
        "default_value": "20",
        "description": (
            "Escalation rate percentage warning threshold (default: 20%)."
        ),
    },
    {
        "schema_name": "fsi_MRM_MonitoringThreshold_EscalationRate_Revalidation",
        "display_name": "MRM - Escalation Rate Revalidation Threshold",
        "type": 100000001,  # Decimal Number
        "default_value": "40",
        "description": (
            "Escalation rate percentage revalidation threshold "
            "(default: 40%)."
        ),
    },
    {
        "schema_name": "fsi_MRM_MonitoringThreshold_OutOfScope_Warning",
        "display_name": "MRM - Out-of-Scope Warning Threshold",
        "type": 100000001,  # Decimal Number
        "default_value": "10",
        "description": (
            "Out-of-scope triggers per week warning threshold "
            "(default: 10)."
        ),
    },
    {
        "schema_name": "fsi_MRM_MonitoringThreshold_OutOfScope_Revalidation",
        "display_name": "MRM - Out-of-Scope Revalidation Threshold",
        "type": 100000001,  # Decimal Number
        "default_value": "50",
        "description": (
            "Out-of-scope triggers per week revalidation threshold "
            "(default: 50)."
        ),
    },
    # -------------------------------------------------------------------------
    # Validation SLAs — Tier 1
    # -------------------------------------------------------------------------
    {
        "schema_name": "fsi_MRM_ValidationSLA_Tier1_Assignment",
        "display_name": "MRM - Tier 1 Assignment SLA",
        "type": 100000001,  # Decimal Number
        "default_value": "5",
        "description": (
            "Business days for Tier 1 validator assignment (default: 5)."
        ),
    },
    {
        "schema_name": "fsi_MRM_ValidationSLA_Tier1_Findings",
        "display_name": "MRM - Tier 1 Findings SLA",
        "type": 100000001,  # Decimal Number
        "default_value": "30",
        "description": (
            "Business days for Tier 1 findings delivery (default: 30)."
        ),
    },
    {
        "schema_name": "fsi_MRM_ValidationSLA_Tier1_Remediation",
        "display_name": "MRM - Tier 1 Remediation SLA",
        "type": 100000001,  # Decimal Number
        "default_value": "15",
        "description": (
            "Business days for Tier 1 remediation (default: 15)."
        ),
    },
    # -------------------------------------------------------------------------
    # Validation SLAs — Tier 2
    # -------------------------------------------------------------------------
    {
        "schema_name": "fsi_MRM_ValidationSLA_Tier2_Assignment",
        "display_name": "MRM - Tier 2 Assignment SLA",
        "type": 100000001,  # Decimal Number
        "default_value": "5",
        "description": (
            "Business days for Tier 2 validator assignment (default: 5)."
        ),
    },
    {
        "schema_name": "fsi_MRM_ValidationSLA_Tier2_Findings",
        "display_name": "MRM - Tier 2 Findings SLA",
        "type": 100000001,  # Decimal Number
        "default_value": "20",
        "description": (
            "Business days for Tier 2 findings delivery (default: 20)."
        ),
    },
    {
        "schema_name": "fsi_MRM_ValidationSLA_Tier2_Remediation",
        "display_name": "MRM - Tier 2 Remediation SLA",
        "type": 100000001,  # Decimal Number
        "default_value": "10",
        "description": (
            "Business days for Tier 2 remediation (default: 10)."
        ),
    },
    # -------------------------------------------------------------------------
    # Validation SLAs — Tier 3
    # -------------------------------------------------------------------------
    {
        "schema_name": "fsi_MRM_ValidationSLA_Tier3_Assignment",
        "display_name": "MRM - Tier 3 Assignment SLA",
        "type": 100000001,  # Decimal Number
        "default_value": "5",
        "description": (
            "Business days for Tier 3 validator assignment (default: 5)."
        ),
    },
    {
        "schema_name": "fsi_MRM_ValidationSLA_Tier3_Findings",
        "display_name": "MRM - Tier 3 Findings SLA",
        "type": 100000001,  # Decimal Number
        "default_value": "10",
        "description": (
            "Business days for Tier 3 findings delivery (default: 10)."
        ),
    },
    {
        "schema_name": "fsi_MRM_ValidationSLA_Tier3_Remediation",
        "display_name": "MRM - Tier 3 Remediation SLA",
        "type": 100000001,  # Decimal Number
        "default_value": "10",
        "description": (
            "Business days for Tier 3 remediation (default: 10)."
        ),
    },
    # -------------------------------------------------------------------------
    # Tenant Configuration
    # -------------------------------------------------------------------------
    {
        "schema_name": "fsi_MRM_TenantId",
        "display_name": "MRM - Tenant ID",
        "type": 100000000,  # String
        "default_value": "",
        "description": (
            "Microsoft Entra tenant ID for interactive auth and "
            "legacy dev-only client-secret auth."
        ),
    },
    # -------------------------------------------------------------------------
    # Risk Scoring Thresholds
    # -------------------------------------------------------------------------
    {
        "schema_name": "fsi_MRM_RiskScoreCriticalThreshold",
        "display_name": "MRM - Risk Score Critical Threshold",
        "type": 100000001,  # Decimal Number
        "default_value": "29",
        "description": (
            "Composite risk score threshold for Critical rating "
            "(default: 29). Calibrate to institutional MRM policy."
        ),
    },
    {
        "schema_name": "fsi_MRM_RiskScoreHighThreshold",
        "display_name": "MRM - Risk Score High Threshold",
        "type": 100000001,  # Decimal Number
        "default_value": "22",
        "description": (
            "Composite risk score threshold for High rating "
            "(default: 22). Calibrate to institutional MRM policy."
        ),
    },
    {
        "schema_name": "fsi_MRM_RiskScoreMediumThreshold",
        "display_name": "MRM - Risk Score Medium Threshold",
        "type": 100000001,  # Decimal Number
        "default_value": "15",
        "description": (
            "Composite risk score threshold for Medium rating "
            "(default: 15). Calibrate to institutional MRM policy."
        ),
    },
    # -------------------------------------------------------------------------
    # Material Change Thresholds
    # -------------------------------------------------------------------------
    {
        "schema_name": "fsi_MRM_MaterialChangeTextDiffThreshold",
        "display_name": "MRM - Material Change Text Diff Threshold",
        "type": 100000001,  # Decimal Number
        "default_value": "30",
        "description": (
            "Percentage character difference threshold for business function "
            "material change detection (default: 30%)."
        ),
    },
    # -------------------------------------------------------------------------
    # Validation Cadence Override
    # -------------------------------------------------------------------------
    {
        "schema_name": "fsi_MRM_ValidationApproachingDaysLookahead",
        "display_name": "MRM - Validation Due Lookahead Days",
        "type": 100000001,  # Decimal Number
        "default_value": "30",
        "description": (
            "Days before next validation due date to send "
            "approaching reminder (default: 30)."
        ),
    },
]


# =============================================================================
# Deployment Functions
# =============================================================================


def create_environment_variable(
    client: DataverseClient, definition: dict, dry_run: bool = False,
) -> None:
    """Create a single environment variable definition and default value.

    Checks for existence first — skips if already present. Creates the
    definition record, then a default value record if a non-empty default
    is specified.

    Args:
        client: DataverseClient instance
        definition: Dict with schema_name, display_name, type, default_value,
                     description
        dry_run: Preview mode flag
    """
    schema_name = definition["schema_name"]
    display_name = definition["display_name"]
    var_type = definition["type"]
    default_value = definition["default_value"]
    description = definition["description"]

    # Idempotent check — skip if already exists.
    # The shared DataverseClient.query() returns a list directly (no
    # {"value": [...]} wrapper) and uses filter_expr= as the kwarg name.
    existing = client.query(
        "environmentvariabledefinitions",
        filter_expr=f"schemaname eq '{schema_name}'",
    )
    if existing:
        print(f"  {schema_name}: already exists, skipping")
        return

    # Create definition record
    def_data = {
        "schemaname": schema_name,
        "displayname": display_name,
        "type": var_type,
        "defaultvalue": str(default_value),
        "description": description,
    }

    if dry_run:
        print(f"  {schema_name}: [DRY-RUN] Would create (type={var_type})")
        if default_value is not None and default_value != "":
            print(f"    [DRY-RUN] Would set default value: {default_value}")
        return

    def_id = client.create_record("environmentvariabledefinitions", def_data)
    print(f"  {schema_name}: created (type={var_type})")

    # Create default value record if a non-empty default is specified
    if default_value is not None and default_value != "":
        value_data = {
            "schemaname": f"{schema_name}_value",
            "value": str(default_value),
            "EnvironmentVariableDefinitionId@odata.bind": (
                f"/environmentvariabledefinitions({def_id})"
            ),
        }
        client.create_record("environmentvariablevalues", value_data)
        print(f"    Default value: {default_value}")


def create_environment_variables(
    client: DataverseClient, dry_run: bool = False,
) -> None:
    """Deploy all MRM environment variables to Dataverse.

    Creates 30 fsi_MRM_* environment variables with their default
    values. All operations are idempotent — safe to re-run.

    Args:
        client: DataverseClient instance
        dry_run: Preview mode flag
    """
    print("=" * 60)
    print("MRM Environment Variables Deployment")
    print("  Model Risk Management Automation")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN - No changes will be made ***\n")

    print("\n[Creating Environment Variables]")

    for defn in ENV_VAR_DEFINITIONS:
        create_environment_variable(client, defn, dry_run)

    # Summary
    print("\n" + "=" * 60)
    if dry_run:
        print("DRY RUN COMPLETE - Review output above")
    else:
        print("ENVIRONMENT VARIABLES DEPLOYMENT COMPLETE")
    print(f"  Variables: {len(ENV_VAR_DEFINITIONS)}")
    print("=" * 60)


# =============================================================================
# CLI Entry Point
# =============================================================================


def main() -> None:
    """CLI entry point for environment variable deployment."""
    parser = argparse.ArgumentParser(
        description=(
            "Create Dataverse environment variables for "
            "Model Risk Management Automation"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Deploy with managed identity/workload identity (preferred)\n"
            "  python create_mrm_environment_variables.py \\\n"
            "    --environment-url $MRM_ENVIRONMENT_URL\n\n"
            "  # Dry run with interactive admin auth\n"
            "  python create_mrm_environment_variables.py "
            "--dry-run --interactive --tenant-id $MRM_TENANT_ID \\\n"
            "    --environment-url $MRM_ENVIRONMENT_URL\n\n"
            "  # Legacy dev-only client-secret fallback\n"
            "  python create_mrm_environment_variables.py \\\n"
            "    --tenant-id $MRM_TENANT_ID \\\n"
            "    --client-id $MRM_CLIENT_ID \\\n"
            "    --client-secret $MRM_CLIENT_SECRET \\\n"
            "    --environment-url $MRM_ENVIRONMENT_URL\n"
        ),
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("MRM_TENANT_ID"),
        help="Microsoft Entra tenant ID for interactive or legacy auth (or MRM_TENANT_ID)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("MRM_CLIENT_ID"),
        help="Legacy dev-only application ID (or set MRM_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("MRM_CLIENT_SECRET"),
        help="Legacy dev-only client secret (or set MRM_CLIENT_SECRET env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("MRM_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set MRM_ENVIRONMENT_URL env var)",
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

    # Validate required arguments. Managed identity is preferred: when
    # neither --interactive nor --client-secret is supplied, the shared
    # DataverseClient defaults to managed-identity auth.
    if not args.environment_url:
        print("ERROR: --environment-url or MRM_ENVIRONMENT_URL required")
        sys.exit(1)
    if args.client_secret and (not args.tenant_id or not args.client_id):
        print(
            "ERROR: legacy client-secret auth requires --tenant-id, "
            "--client-id, and --client-secret"
        )
        sys.exit(1)

    if args.interactive:
        auth_mode = "interactive"
    elif args.client_secret:
        auth_mode = "client-secret"
    else:
        auth_mode = "managed-identity"

    try:
        # NOTE: We deliberately do NOT pass dry_run to DataverseClient: the
        # shared client short-circuits reads in dry-run mode, which would
        # defeat the idempotent "skip if exists" check. Writes are gated
        # locally inside create_environment_variable via the dry_run arg.
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=args.client_secret,
            interactive=args.interactive,
            auth_mode=auth_mode,
        )

        create_environment_variables(client, dry_run=args.dry_run)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
