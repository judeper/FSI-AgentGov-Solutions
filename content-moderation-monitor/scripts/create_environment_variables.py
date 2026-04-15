#!/usr/bin/env python3
"""Create Dataverse environment variables for Content Moderation Monitor.

Deploys seven environment variables with fsi_CMM_* prefix that control
scan behavior, grace periods, and alerting configuration. All operations
are idempotent — safe to re-run.

Variables consumed by Start-ModerationValidationRunbook.ps1 (via CMMClient):
  - fsi_CMM_GracePeriodHours: Hours to exclude newly provisioned environments
  - fsi_CMM_IncludeSandbox: Whether to include sandbox environments
  - fsi_CMM_IncludeDrafts: Whether to include draft/unpublished agents

Variables consumed by Test-ContentModerationCompliance.ps1 (via CMMClient):
  - fsi_CMM_GracePeriodHours: Grace period override
  - fsi_CMM_IncludeSandbox: Include sandbox override
  - fsi_CMM_IncludeDrafts: Include drafts override

Variables for future use (not yet consumed by flow or scripts):
  - fsi_CMM_ScanFrequencyHours: Automated scan interval (flow uses Recurrence trigger)
  - fsi_CMM_BaselineMaxAgeDays: Alert threshold for stale baselines
  - fsi_CMM_TeamsGroupId: Teams group GUID (flow uses InitializeVariable)
  - fsi_CMM_TeamsChannelId: Teams channel GUID (flow uses InitializeVariable)
"""

import argparse
import os
import sys

from cmm_client import CMMClient


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
        "schema_name": "fsi_CMM_GracePeriodHours",
        "display_name": "CMM - Grace Period (Hours)",
        "type": 100000001,  # Decimal
        "default_value": "48",
        "description": (
            "Hours to exclude newly provisioned environments from "
            "moderation scans. Supports orderly agent onboarding."
        ),
    },
    {
        "schema_name": "fsi_CMM_ScanFrequencyHours",
        "display_name": "CMM - Scan Frequency (Hours)",
        "type": 100000001,  # Decimal
        "default_value": "24",
        "description": (
            "Interval in hours between automated moderation scans. "
            "Shorter intervals increase detection responsiveness."
        ),
    },
    {
        "schema_name": "fsi_CMM_IncludeSandbox",
        "display_name": "CMM - Include Sandbox Environments",
        "type": 100000000,  # String
        "default_value": "false",
        "description": (
            "Whether to include sandbox environments in moderation scans. "
            "Set to 'true' to scan sandbox environments."
        ),
    },
    {
        "schema_name": "fsi_CMM_IncludeDrafts",
        "display_name": "CMM - Include Draft Agents",
        "type": 100000000,  # String
        "default_value": "false",
        "description": (
            "Whether to include draft/unpublished agents in moderation scans. "
            "Set to 'true' to scan agents that are not yet published."
        ),
    },
    {
        "schema_name": "fsi_CMM_BaselineMaxAgeDays",
        "display_name": "CMM - Maximum Baseline Age (Days)",
        "type": 100000001,  # Decimal
        "default_value": "30",
        "description": (
            "Number of days before a baseline is considered stale. "
            "Reserved for future use by stale-baseline alerting (not yet implemented)."
        ),
    },
    {
        "schema_name": "fsi_CMM_TeamsGroupId",
        "display_name": "CMM - Teams Alert Group ID",
        "type": 100000000,  # String
        "default_value": "",
        "description": (
            "Microsoft Teams group (team) GUID for posting moderation "
            "violation alerts via adaptive cards."
        ),
    },
    {
        "schema_name": "fsi_CMM_TeamsChannelId",
        "display_name": "CMM - Teams Alert Channel ID",
        "type": 100000000,  # String
        "default_value": "",
        "description": (
            "Microsoft Teams channel GUID within the alert group for "
            "posting moderation violation adaptive cards."
        ),
    },
]


# =============================================================================
# Deployment Functions
# =============================================================================


def create_environment_variable(
    client: CMMClient, definition: dict, dry_run: bool = False,
) -> None:
    """Create a single environment variable definition and default value.

    Checks for existence first — skips if already present. Creates the
    definition record, then a default value record if a non-empty default
    is specified.

    Args:
        client: CMMClient instance
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
    client: CMMClient, dry_run: bool = False,
) -> None:
    """Deploy all CMM environment variables to Dataverse.

    Creates seven fsi_CMM_* environment variables with their default
    values. All operations are idempotent — safe to re-run.

    Args:
        client: CMMClient instance
        dry_run: Preview mode flag
    """
    print("=" * 60)
    print("CMM Environment Variables Deployment")
    print("  Content Moderation Governance Monitor")
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
            "Content Moderation Monitor"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Dry run with interactive auth\n"
            "  python create_environment_variables.py "
            "--dry-run --interactive\n\n"
            "  # Deploy with service principal\n"
            "  python create_environment_variables.py \\\n"
            "    --tenant-id $CMM_TENANT_ID \\\n"
            "    --client-id $CMM_CLIENT_ID \\\n"
            "    --client-secret $CMM_CLIENT_SECRET \\\n"
            "    --environment-url $CMM_ENVIRONMENT_URL\n"
        ),
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("CMM_TENANT_ID"),
        help="Microsoft Entra ID tenant ID (or set CMM_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("CMM_CLIENT_ID"),
        help="Service principal app ID (or set CMM_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("CMM_CLIENT_SECRET"),
        help="Service principal secret (or set CMM_CLIENT_SECRET env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("CMM_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set CMM_ENVIRONMENT_URL env var)",
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
        print("ERROR: --tenant-id or CMM_TENANT_ID required")
        sys.exit(1)
    if not args.environment_url:
        print("ERROR: --environment-url or CMM_ENVIRONMENT_URL required")
        sys.exit(1)

    try:
        client = CMMClient(
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
