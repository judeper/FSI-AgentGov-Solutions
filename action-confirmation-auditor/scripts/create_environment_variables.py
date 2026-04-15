#!/usr/bin/env python3
"""Create Dataverse environment variables for Action Confirmation Auditor.

Deploys seven environment variables with fsi_ACA_* prefix that control
scan behavior, grace periods, confirmation pattern mode, and alerting
configuration. All operations are idempotent.

Variables consumed by ACA validation runbook (via ACAClient):
  - fsi_ACA_GracePeriodHours: Hours to exclude newly provisioned environments
  - fsi_ACA_ScanFrequencyHours: Automated scan interval
  - fsi_ACA_IncludeSandbox: Whether to include sandbox environments
  - fsi_ACA_IncludeDrafts: Whether to include draft/unpublished agents
  - fsi_ACA_ConfirmationPatternMode: Confirmation detection mode (standard/strict/permissive)

Variables for Teams alerting:
  - fsi_ACA_TeamsGroupId: Teams group GUID for posting alerts
  - fsi_ACA_TeamsChannelId: Teams channel GUID for posting alerts
"""

import argparse
import os
import sys

from aca_client import ACAClient


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
        "schema_name": "fsi_ACA_GracePeriodHours",
        "display_name": "ACA - Grace Period (Hours)",
        "type": 100000001,  # Decimal
        "default_value": "48",
        "description": (
            "Hours to exclude newly provisioned environments from "
            "action confirmation scans. Supports orderly agent onboarding."
        ),
    },
    {
        "schema_name": "fsi_ACA_ScanFrequencyHours",
        "display_name": "ACA - Scan Frequency (Hours)",
        "type": 100000001,  # Decimal
        "default_value": "24",
        "description": (
            "Interval in hours between automated action confirmation scans. "
            "Shorter intervals increase detection responsiveness."
        ),
    },
    {
        "schema_name": "fsi_ACA_IncludeSandbox",
        "display_name": "ACA - Include Sandbox Environments",
        "type": 100000000,  # String
        "default_value": "false",
        "description": (
            "Whether to include sandbox environments in action confirmation "
            "scans. Set to 'true' to scan sandbox environments."
        ),
    },
    {
        "schema_name": "fsi_ACA_IncludeDrafts",
        "display_name": "ACA - Include Draft Agents",
        "type": 100000000,  # String
        "default_value": "false",
        "description": (
            "Whether to include draft/unpublished agents in action confirmation "
            "scans. Set to 'true' to scan agents not yet published."
        ),
    },
    {
        "schema_name": "fsi_ACA_ConfirmationPatternMode",
        "display_name": "ACA - Confirmation Pattern Mode",
        "type": 100000000,  # String
        "default_value": "standard",
        "description": (
            "Step-up confirmation detection mode. "
            "'standard' uses default pattern matching; "
            "'strict' requires explicit confirmation nodes; "
            "'permissive' accepts implicit confirmation flows."
        ),
    },
    {
        "schema_name": "fsi_ACA_TeamsGroupId",
        "display_name": "ACA - Teams Alert Group ID",
        "type": 100000000,  # String
        "default_value": "",
        "description": (
            "Microsoft Teams group (team) GUID for posting action "
            "confirmation violation alerts via adaptive cards."
        ),
    },
    {
        "schema_name": "fsi_ACA_TeamsChannelId",
        "display_name": "ACA - Teams Alert Channel ID",
        "type": 100000000,  # String
        "default_value": "",
        "description": (
            "Microsoft Teams channel GUID within the alert group for "
            "posting action confirmation violation adaptive cards."
        ),
    },
]


# =============================================================================
# Deployment Functions
# =============================================================================


def create_environment_variable(
    client: ACAClient, definition: dict, dry_run: bool = False,
) -> None:
    """Create a single environment variable definition and default value.

    Checks for existence first -- skips if already present. Creates the
    definition record, then a default value record if a non-empty default
    is specified.

    Args:
        client: ACAClient instance
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
    client: ACAClient, dry_run: bool = False,
) -> None:
    """Deploy all ACA environment variables to Dataverse.

    Creates seven fsi_ACA_* environment variables with their default
    values. All operations are idempotent -- safe to re-run.

    Args:
        client: ACAClient instance
        dry_run: Preview mode flag
    """
    print("=" * 60)
    print("ACA Environment Variables Deployment")
    print("  Action Confirmation Auditor")
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
            "Action Confirmation Auditor"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Dry run with interactive auth\n"
            "  python create_environment_variables.py "
            "--dry-run --interactive\n\n"
            "  # Deploy with service principal\n"
            "  python create_environment_variables.py \\\n"
            "    --tenant-id $ACA_TENANT_ID \\\n"
            "    --client-id $ACA_CLIENT_ID \\\n"
            "    --client-secret $ACA_CLIENT_SECRET \\\n"
            "    --environment-url $ACA_ENVIRONMENT_URL\n"
        ),
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ACA_TENANT_ID"),
        help="Azure AD tenant ID (or set ACA_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ACA_CLIENT_ID"),
        help="Service principal app ID (or set ACA_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("ACA_CLIENT_SECRET"),
        help="Service principal secret (or set ACA_CLIENT_SECRET env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ACA_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set ACA_ENVIRONMENT_URL env var)",
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
        print("ERROR: --tenant-id or ACA_TENANT_ID required")
        sys.exit(1)
    if not args.environment_url:
        print("ERROR: --environment-url or ACA_ENVIRONMENT_URL required")
        sys.exit(1)

    try:
        client = ACAClient(
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
