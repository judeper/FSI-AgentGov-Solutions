#!/usr/bin/env python3
"""Create Dataverse environment variables for Agent Registry Automation.

Deploys ten environment variables with fsi_ARA_* prefix that control
sync behavior, SLA escalation, and alerting configuration. All operations
are idempotent — safe to re-run.

Variables consumed by Power Automate flows:
  - fsi_ARA_IsEntraRegistrySyncEnabled: Feature flag for Microsoft Entra Agent ID sync
  - fsi_ARA_FrameworkVersion: FSI-AgentGov version tag for registry entries
  - fsi_ARA_EscalationApproverUPN: Skip-level approver for SLA escalation
  - fsi_ARA_GovernanceTeamEmail: Distribution list for unregistered agent alerts
  - fsi_ARA_FlowAdministrators: Email for flow error notifications
  - fsi_ARA_TenantId: Entra ID tenant ID for service principal auth
  - fsi_ARA_DataverseEnvironmentUrl: Target Dataverse environment URL
  - fsi_ARA_TeamsChannelId: Teams channel ID for governance notifications
  - fsi_ARA_ApprovalDeadlineDays: Business days for approval SLA deadline
  - fsi_ARA_DefaultTimeZone: Fallback time zone for SLA calculations
"""

import argparse
import os
import sys

from ara_client import ARAClient


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
    {
        "schema_name": "fsi_ARA_IsEntraRegistrySyncEnabled",
        "display_name": "ARA - Agent ID Sync Enabled",
        "type": 100000000,  # String
        "default_value": "false",
        "description": (
            "Feature flag for Microsoft Entra Agent ID sync (Flow 3). "
            "Set to 'true' only after Microsoft Agent 365 or Microsoft 365 E5 "
            "licensing and Microsoft Graph beta endpoint availability are confirmed in tenant."
        ),
    },
    {
        "schema_name": "fsi_ARA_FrameworkVersion",
        "display_name": "ARA - Framework Version",
        "type": 100000000,  # String
        "default_value": "FSI-AgentGov-v1.1",
        "description": (
            "FSI-AgentGov framework version tag applied to "
            "Microsoft Entra Agent ID entries."
        ),
    },
    {
        "schema_name": "fsi_ARA_EscalationApproverUPN",
        "display_name": "ARA - Escalation Approver UPN",
        "type": 100000000,  # String
        "default_value": "",
        "description": (
            "UPN of skip-level governance approver for SLA escalation "
            "in registration workflow."
        ),
    },
    {
        "schema_name": "fsi_ARA_GovernanceTeamEmail",
        "display_name": "ARA - Governance Team Email",
        "type": 100000000,  # String
        "default_value": "",
        "description": (
            "Governance distribution list email for unregistered agent "
            "alerts and escalation notifications."
        ),
    },
    {
        "schema_name": "fsi_ARA_FlowAdministrators",
        "display_name": "ARA - Flow Administrators",
        "type": 100000000,  # String
        "default_value": "",
        "description": (
            "Email address for flow error notifications and "
            "administrative alerts."
        ),
    },
    {
        "schema_name": "fsi_ARA_TenantId",
        "display_name": "ARA - Tenant ID",
        "type": 100000000,  # String
        "default_value": "",
        "description": (
            "Microsoft Entra ID tenant ID for service principal "
            "authentication in flows."
        ),
    },
    {
        "schema_name": "fsi_ARA_DataverseEnvironmentUrl",
        "display_name": "ARA - Dataverse Environment URL",
        "type": 100000000,  # String
        "default_value": "",
        "description": (
            "Target Dataverse environment URL "
            "(e.g., https://example.crm.dynamics.com) for API operations."
        ),
    },
    {
        "schema_name": "fsi_ARA_TeamsChannelId",
        "display_name": "ARA - Teams Channel ID",
        "type": 100000000,  # String
        "default_value": "",
        "description": (
            "Microsoft Teams channel ID for governance notifications "
            "and approval adaptive cards."
        ),
    },
    {
        "schema_name": "fsi_ARA_ApprovalDeadlineDays",
        "display_name": "ARA - Approval Deadline Days",
        "type": 100000000,  # String
        "default_value": "5",
        "description": (
            "Number of business days allowed for registration approval "
            "before SLA escalation is triggered."
        ),
    },
    {
        "schema_name": "fsi_ARA_DefaultTimeZone",
        "display_name": "ARA - Default Time Zone",
        "type": 100000000,  # String
        "default_value": "Eastern Standard Time",
        "description": (
            "Fallback time zone for SLA deadline calculations when "
            "the Office 365 Users connector is unavailable."
        ),
    },
]


# =============================================================================
# Deployment Functions
# =============================================================================


def create_environment_variable(
    client: ARAClient, definition: dict, dry_run: bool = False,
) -> None:
    """Create a single environment variable definition and default value.

    Checks for existence first — skips if already present. Creates the
    definition record, then a default value record if a non-empty default
    is specified.

    Args:
        client: ARAClient instance
        definition: Dict with schema_name, display_name, type, default_value,
                     description
        dry_run: Preview mode flag
    """
    schema_name = definition["schema_name"]
    display_name = definition["display_name"]
    var_type = definition["type"]
    default_value = definition["default_value"]
    description = definition["description"]

    # Idempotent check — skip if already exists
    existing = client.query(
        "environmentvariabledefinitions",
        filter=f"schemaname eq '{schema_name}'",
    )
    if existing["value"]:
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
    client: ARAClient, dry_run: bool = False,
) -> None:
    """Deploy all ARA environment variables to Dataverse.

    Creates ten fsi_ARA_* environment variables with their default
    values. All operations are idempotent — safe to re-run.

    Args:
        client: ARAClient instance
        dry_run: Preview mode flag
    """
    print("=" * 60)
    print("ARA Environment Variables Deployment")
    print("  Agent Registry Automation")
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
            "Agent Registry Automation"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Dry run with interactive auth\n"
            "  python create_environment_variables.py "
            "--dry-run --interactive\n\n"
            "  # Deploy with certificate auth\n"
            "  python create_environment_variables.py \\\n"
            "    --tenant-id $ARA_TENANT_ID \\\n"
            "    --client-id $ARA_CLIENT_ID \\\n"
            "    --client-certificate-path $ARA_CLIENT_CERTIFICATE_PATH \\\n"
            "    --client-certificate-thumbprint $ARA_CLIENT_CERTIFICATE_THUMBPRINT \\\n"
            "    --environment-url $ARA_ENVIRONMENT_URL\n"
        ),
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ARA_TENANT_ID"),
        help="Microsoft Entra ID tenant ID (or set ARA_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ARA_CLIENT_ID"),
        help="App ID for certificate or legacy secret auth (or set ARA_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("ARA_CLIENT_SECRET"),
        help="Legacy dev-only service principal secret (or set ARA_CLIENT_SECRET env var)",
    )
    parser.add_argument(
        "--client-certificate-path",
        default=os.environ.get("ARA_CLIENT_CERTIFICATE_PATH"),
        help="PEM certificate/private key path for certificate authentication",
    )
    parser.add_argument(
        "--client-certificate-thumbprint",
        default=os.environ.get("ARA_CLIENT_CERTIFICATE_THUMBPRINT"),
        help="Certificate thumbprint for certificate authentication",
    )
    parser.add_argument(
        "--managed-identity-client-id",
        default=os.environ.get("ARA_MANAGED_IDENTITY_CLIENT_ID"),
        help="User-assigned managed identity client ID",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ARA_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set ARA_ENVIRONMENT_URL env var)",
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
    if not args.tenant_id:
        print("ERROR: --tenant-id or ARA_TENANT_ID required")
        sys.exit(1)
    if not args.environment_url:
        print("ERROR: --environment-url or ARA_ENVIRONMENT_URL required")
        sys.exit(1)

    try:
        client = ARAClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=args.client_secret,
            client_certificate_path=args.client_certificate_path,
            client_certificate_thumbprint=args.client_certificate_thumbprint,
            managed_identity_client_id=args.managed_identity_client_id,
            interactive=args.interactive,
            dry_run=args.dry_run,
        )

        create_environment_variables(client, dry_run=args.dry_run)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
