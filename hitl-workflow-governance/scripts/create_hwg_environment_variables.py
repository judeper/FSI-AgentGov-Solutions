#!/usr/bin/env python3
"""Create Dataverse environment variables for HITL Workflow Governance.

Deploys six environment variables with fsi_HWG_* prefix that control
scan behavior, grace periods, review SLA, zone sample rates, and
alerting configuration. All operations are idempotent.

Variables consumed by HWG validation runbook (via HWGClient):
  - fsi_HWG_GracePeriodHours: Hours before new agents must have HITL configured
  - fsi_HWG_EnableDataversePersistence: Whether to persist results to Dataverse
  - fsi_HWG_DefaultReviewSlaHours: Default SLA for reviewer response

Variables for zone-based sampling and alerting:
  - fsi_HWG_Zone3SampleRate: Percentage of Zone 3 actions requiring pre-approval
  - fsi_HWG_Zone2SampleRate: Percentage for Zone 2 sampled review
  - fsi_HWG_NotificationWebhookUrl: Teams webhook URL for alerts
"""

import argparse
import os
import sys

from hwg_client import HWGClient


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
        "schema_name": "fsi_HWG_GracePeriodHours",
        "display_name": "HWG - Grace Period (Hours)",
        "type": 100000001,  # Decimal
        "default_value": "72",
        "description": (
            "Hours before new agents must have HITL checkpoints "
            "configured. Supports orderly agent onboarding."
        ),
    },
    {
        "schema_name": "fsi_HWG_EnableDataversePersistence",
        "display_name": "HWG - Enable Dataverse Persistence",
        "type": 100000000,  # String
        "default_value": "true",
        "description": (
            "Whether to persist HITL scan results to Dataverse tables. "
            "Set to 'false' to run in report-only mode."
        ),
    },
    {
        "schema_name": "fsi_HWG_DefaultReviewSlaHours",
        "display_name": "HWG - Default Review SLA (Hours)",
        "type": 100000001,  # Decimal
        "default_value": "24",
        "description": (
            "Default SLA in hours for reviewer response to HITL "
            "requests. Used when no agent-specific SLA is configured."
        ),
    },
    {
        "schema_name": "fsi_HWG_Zone3SampleRate",
        "display_name": "HWG - Zone 3 Sample Rate (%)",
        "type": 100000000,  # String
        "default_value": "100",
        "description": (
            "Percentage of Zone 3 agent actions requiring pre-approval "
            "via HITL checkpoint. 100 means all actions require review."
        ),
    },
    {
        "schema_name": "fsi_HWG_Zone2SampleRate",
        "display_name": "HWG - Zone 2 Sample Rate (%)",
        "type": 100000000,  # String
        "default_value": "10",
        "description": (
            "Percentage of Zone 2 agent actions selected for sampled "
            "review via HITL checkpoint."
        ),
    },
    {
        "schema_name": "fsi_HWG_NotificationWebhookUrl",
        "display_name": "HWG - Notification Webhook URL",
        "type": 100000000,  # String
        "default_value": "",
        "description": (
            "Microsoft Teams webhook URL for posting HITL violation "
            "alerts. Leave empty to disable webhook notifications."
        ),
    },
    {
        "schema_name": "fsi_HWG_IncludeSandbox",
        "display_name": "HWG - Include Sandbox Environments",
        "type": 100000000,  # String
        "default_value": "false",
        "description": (
            "Whether scans should include Sandbox environments. "
            "Set to 'true' to evaluate Sandbox alongside Production."
        ),
    },
    {
        "schema_name": "fsi_HWG_IncludeDrafts",
        "display_name": "HWG - Include Draft Flows",
        "type": 100000000,  # String
        "default_value": "false",
        "description": (
            "Whether scans should include draft (unpublished) flows. "
            "Set to 'true' to detect missing HITL checkpoints in drafts."
        ),
    },
]


# =============================================================================
# Deployment Functions
# =============================================================================


def create_environment_variable(
    client: HWGClient, definition: dict, dry_run: bool = False,
) -> None:
    """Create a single environment variable definition and default value.

    Checks for existence first -- skips if already present. Creates the
    definition record, then a default value record if a non-empty default
    is specified.

    Args:
        client: HWGClient instance
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
    client: HWGClient, dry_run: bool = False,
) -> None:
    """Deploy all HWG environment variables to Dataverse.

    Creates six fsi_HWG_* environment variables with their default
    values. All operations are idempotent -- safe to re-run.

    Args:
        client: HWGClient instance
        dry_run: Preview mode flag
    """
    print("=" * 60)
    print("HWG Environment Variables Deployment")
    print("  HITL Workflow Governance")
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
            "HITL Workflow Governance"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Dry run with interactive auth\n"
            "  python create_hwg_environment_variables.py "
            "--dry-run --interactive\n\n"
            "  # Deploy with service principal\n"
            "  python create_hwg_environment_variables.py \\\n"
            "    --tenant-id $HWG_TENANT_ID \\\n"
            "    --client-id $HWG_CLIENT_ID \\\n"
            "    --client-secret $HWG_CLIENT_SECRET \\\n"
            "    --environment-url $HWG_ENVIRONMENT_URL\n"
        ),
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("HWG_TENANT_ID"),
        help="Microsoft Entra ID tenant ID (or set HWG_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("HWG_CLIENT_ID"),
        help="Service principal app ID, or user-assigned managed identity client ID when no secret is provided (or set HWG_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("HWG_CLIENT_SECRET"),
        help="Client secret for legacy dev-only service principal auth; omit to use DefaultAzureCredential (or set HWG_CLIENT_SECRET env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("HWG_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set HWG_ENVIRONMENT_URL env var)",
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
        print("ERROR: --tenant-id or HWG_TENANT_ID required")
        sys.exit(1)
    if not args.environment_url:
        print("ERROR: --environment-url or HWG_ENVIRONMENT_URL required")
        sys.exit(1)

    try:
        client = HWGClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=args.client_secret,
            interactive=args.interactive,
            dry_run=args.dry_run,
        )

        create_environment_variables(client, dry_run=args.dry_run)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
