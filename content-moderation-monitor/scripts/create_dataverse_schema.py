#!/usr/bin/env python3
"""Create Dataverse schema for Content Moderation Monitor.

Deploys three tables (ModerationBaseline, ModerationValidationHistory,
ModerationViolation) with shared option sets for zone classification
and severity levels. All operations are idempotent.

Tables:
  - fsi_ModerationBaseline (UserOwned): Captured moderation level snapshots
  - fsi_ModerationValidationHistory (OrganizationOwned): Immutable scan results
  - fsi_ModerationViolation (UserOwned): Individual agent-level violations
"""

import argparse
import os
import sys
from typing import Optional

from cmm_client import CMMClient

# Publisher prefix for custom entities
PUBLISHER_PREFIX = "fsi"

# =============================================================================
# Shared Option Sets (reuse existing ACV option sets — existence check first)
# =============================================================================

SHARED_OPTIONSETS = {
    "fsi_acv_zone": {
        "name": "fsi_acv_zone",
        "options": [
            ("Unclassified", 100000000),
            ("Zone 1", 100000001),
            ("Zone 2", 100000002),
            ("Zone 3", 100000003),
        ],
    },
    "fsi_acv_severity": {
        "name": "fsi_acv_severity",
        "options": [
            ("Passed", 100000000),
            ("Warning", 100000001),
            ("GracePeriod", 100000002),
            ("Failed", 100000003),
            ("Error", 100000004),
        ],
    },
}


# =============================================================================
# Column Definition Helpers
# =============================================================================


def _label(text: str) -> dict:
    """Build a Dataverse Label structure."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.Label",
        "LocalizedLabels": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.LocalizedLabel",
                "Label": text,
                "LanguageCode": 1033,
            }
        ],
    }


def _string_col(
    schema_name: str, display: str, max_length: int, required: bool = True,
    description: str = "",
) -> dict:
    """Build a string column definition."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {
            "Value": "ApplicationRequired" if required else "None"
        },
        "MaxLength": max_length,
        "FormatName": {"Value": "Text"},
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _memo_col(
    schema_name: str, display: str, max_length: int,
    description: str = "",
) -> dict:
    """Build a memo (multiline text) column definition."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.MemoAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "None"},
        "MaxLength": max_length,
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _integer_col(
    schema_name: str, display: str, required: bool = True,
    description: str = "",
) -> dict:
    """Build an integer column definition."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {
            "Value": "ApplicationRequired" if required else "None"
        },
        "MinValue": 0,
        "MaxValue": 2147483647,
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _boolean_col(
    schema_name: str, display: str, default: bool = False,
    description: str = "",
) -> dict:
    """Build a boolean column definition."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "DefaultValue": default,
        "OptionSet": {
            "TrueOption": {
                "Value": 1,
                "Label": _label("Yes"),
            },
            "FalseOption": {
                "Value": 0,
                "Label": _label("No"),
            },
        },
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _datetime_col(
    schema_name: str, display: str, required: bool = True,
    description: str = "",
) -> dict:
    """Build a datetime column definition."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {
            "Value": "ApplicationRequired" if required else "None"
        },
        "Format": "DateAndTime",
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _picklist_col(
    schema_name: str, display: str, global_optionset_name: str,
    required: bool = True, description: str = "",
) -> dict:
    """Build a picklist column bound to a global option set."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {
            "Value": "ApplicationRequired" if required else "None"
        },
        "OptionSet": None,
        "GlobalOptionSet@odata.bind": (
            f"/GlobalOptionSetDefinitions(Name='{global_optionset_name}')"
        ),
    }
    if description:
        defn["Description"] = _label(description)
    return defn


# =============================================================================
# Table Column Definitions
# =============================================================================

BASELINE_COLUMNS = [
    _string_col("fsi_EnvironmentGuid", "Environment GUID", 100,
                description="Power Platform environment GUID"),
    _string_col("fsi_EnvironmentName", "Environment Name", 500,
                description="Environment display name"),
    _picklist_col("fsi_zone", "Zone", "fsi_acv_zone",
                  description="Zone classification"),
    _string_col("fsi_AgentId", "Agent ID", 100,
                description="Copilot Studio bot GUID"),
    _string_col("fsi_AgentName", "Agent Name", 500,
                description="Agent display name"),
    _string_col("fsi_ModerationLevel", "Moderation Level", 50,
                description="Captured moderation level (Low/Medium/High)"),
    _boolean_col("fsi_IsActive", "Is Active", default=True,
                 description="Current active baseline flag"),
    _datetime_col("fsi_CapturedAt", "Captured At",
                  description="When baseline was captured"),
    _string_col("fsi_CapturedBy", "Captured By", 200, required=False,
                description="UPN of capturing operator"),
    _memo_col("fsi_RawJson", "Raw JSON", 100000,
              description="Full JSON snapshot of moderation settings"),
]

HISTORY_COLUMNS = [
    _string_col("fsi_RunId", "Run ID", 36,
                description="GUID correlating all records in one scan run"),
    _datetime_col("fsi_ValidationTime", "Validation Time",
                  description="When scan executed"),
    _integer_col("fsi_TotalAgents", "Total Agents",
                 description="Total agents scanned"),
    _integer_col("fsi_CompliantCount", "Compliant Count",
                 description="Agents passing moderation checks"),
    _integer_col("fsi_ViolationCount", "Violation Count",
                 description="Agents with moderation violations"),
    _string_col("fsi_OverallStatus", "Overall Status", 50,
                description="Passed/Failed/Warning/Critical"),
    _string_col("fsi_EnvironmentsScanned", "Environments Scanned", 2000,
                required=False,
                description="Comma-separated environments covered"),
    _memo_col("fsi_SummaryJson", "Summary JSON", 100000,
              description="Full JSON summary blob"),
]

VIOLATION_COLUMNS = [
    _string_col("fsi_EnvironmentGuid", "Environment GUID", 100,
                description="Power Platform environment GUID"),
    _string_col("fsi_EnvironmentName", "Environment Name", 500,
                description="Environment display name"),
    _string_col("fsi_AgentId", "Agent ID", 100,
                description="Violating agent's bot GUID"),
    _string_col("fsi_AgentName", "Agent Name", 500,
                description="Agent display name"),
    _picklist_col("fsi_zone", "Zone", "fsi_acv_zone",
                  description="Zone classification"),
    _string_col("fsi_ExpectedLevel", "Expected Level", 50,
                description="Zone-required moderation level"),
    _string_col("fsi_ActualLevel", "Actual Level", 50,
                description="Agent's current moderation level"),
    _string_col("fsi_severity", "Severity", 50,
               description="Violation severity (Critical/High/Medium/Warning)"),
    _string_col("fsi_RegulatoryContext", "Regulatory Context", 2000,
                required=False,
                description="FINRA/SOX/GLBA regulatory impact context"),
    _datetime_col("fsi_DetectedAt", "Detected At",
                  description="When violation was detected"),
    _string_col("fsi_RunId", "Run ID", 36, required=False,
                description="Correlating scan GUID"),
]


# =============================================================================
# Table Definitions
# =============================================================================

TABLES = {
    "fsi_moderationbaseline": {
        "schema_name": "fsi_ModerationBaseline",
        "display": "Content Moderation Baseline",
        "plural": "Content Moderation Baselines",
        "description": (
            "Captured moderation level snapshots for governance comparison"
        ),
        "ownership": "UserOwned",
        "columns": BASELINE_COLUMNS,
        "entity_set_name": None,  # Use default auto-generated name
    },
    "fsi_moderationvalidationhistory": {
        "schema_name": "fsi_ModerationValidationHistory",
        "display": "Content Moderation Validation History",
        "plural": "Content Moderation Validation History",
        "description": (
            "Immutable scan results for regulatory evidence "
            "(supports compliance with FINRA 4511, SEC 17a-3)"
        ),
        "ownership": "OrganizationOwned",
        "columns": HISTORY_COLUMNS,
        # Explicit EntitySetName avoids auto-plural
        # 'fsi_moderationvalidationhistorys'
        "entity_set_name": "fsi_moderationvalidationhistory",
    },
    "fsi_moderationviolation": {
        "schema_name": "fsi_ModerationViolation",
        "display": "Content Moderation Violation",
        "plural": "Content Moderation Violations",
        "description": (
            "Individual agent-level moderation violations detected during scans"
        ),
        "ownership": "UserOwned",
        "columns": VIOLATION_COLUMNS,
        "entity_set_name": None,
    },
}


# =============================================================================
# Deployment Functions
# =============================================================================


def create_shared_optionsets(client: CMMClient, dry_run: bool = False) -> None:
    """Create or verify shared global option sets.

    These option sets are shared with ACV and other solutions.
    Existence is checked before creation to support idempotent runs.
    """
    print("\n[Creating/Verifying Shared Option Sets]")

    for os_name, os_def in SHARED_OPTIONSETS.items():
        client.create_option_set(os_def["name"], os_def["options"])


def create_table_with_columns(
    client: CMMClient,
    table_name: str,
    table_def: dict,
    columns: list[dict],
    dry_run: bool = False,
) -> None:
    """Create a table and its columns (idempotent).

    Args:
        client: CMMClient instance
        table_name: Logical table name
        table_def: Table definition dict
        columns: List of column definitions
        dry_run: Preview mode flag
    """
    logical_name = table_name.lower()

    # Check if table already exists
    if client.check_table_exists(logical_name):
        print(f"  {logical_name}: already exists, skipping table creation")
    else:
        # Build entity definition
        definition = {
            "@odata.type": "#Microsoft.Dynamics.CRM.EntityMetadata",
            "SchemaName": table_def["schema_name"],
            "DisplayName": _label(table_def["display"]),
            "DisplayCollectionName": _label(table_def["plural"]),
            "Description": _label(table_def["description"]),
            "OwnershipType": table_def["ownership"],
            "IsActivity": False,
            "HasActivities": False,
            "HasNotes": False,
            "IsAuditEnabled": {"Value": True, "CanBeChanged": True},
            "PrimaryNameAttribute": "fsi_name",
            "Attributes": [
                {
                    "@odata.type": (
                        "#Microsoft.Dynamics.CRM.StringAttributeMetadata"
                    ),
                    "SchemaName": "fsi_Name",
                    "DisplayName": _label(
                        f"{table_def['display']} ID"
                    ),
                    "Description": _label("Primary name attribute"),
                    "RequiredLevel": {"Value": "ApplicationRequired"},
                    "MaxLength": 500,
                    "FormatName": {"Value": "Text"},
                },
            ],
        }

        # Set explicit EntitySetName if specified
        if table_def.get("entity_set_name"):
            definition["EntitySetName"] = table_def["entity_set_name"]

        client.create_entity(definition)
        print(f"  {logical_name}: created")

    # Create columns
    print(f"  {logical_name} columns:")
    for col in columns:
        col_schema = col["SchemaName"]
        col_type = col.get("@odata.type", "Unknown").split(".")[-1]
        client.create_column(logical_name, col_schema, col_type, col)


def create_schema(client: CMMClient, dry_run: bool = False) -> None:
    """Orchestrate full schema deployment.

    Order: option sets → tables → columns (for each table).
    All operations are idempotent — safe to re-run.
    """
    print("=" * 60)
    print("CMM Dataverse Schema Deployment")
    print("  Content Moderation Governance Monitor")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN - No changes will be made ***\n")

    # Step 1: Shared option sets (must exist before tables reference them)
    create_shared_optionsets(client, dry_run)

    # Step 2: Tables and columns
    print("\n[Creating Tables and Columns]")
    for table_name, table_def in TABLES.items():
        print(f"\n  --- {table_def['display']} ({table_def['ownership']}) ---")
        create_table_with_columns(
            client, table_name, table_def, table_def["columns"], dry_run
        )

    # Summary
    print("\n" + "=" * 60)
    if dry_run:
        print("DRY RUN COMPLETE - Review output above")
    else:
        print("SCHEMA DEPLOYMENT COMPLETE")
    print(f"  Option sets: {len(SHARED_OPTIONSETS)}")
    print(f"  Tables: {len(TABLES)}")
    total_cols = sum(len(t["columns"]) for t in TABLES.values())
    print(f"  Columns: {total_cols}")
    print("=" * 60)


# =============================================================================
# CLI Entry Point
# =============================================================================


def main() -> None:
    """CLI entry point for schema deployment."""
    parser = argparse.ArgumentParser(
        description="Create Dataverse schema for Content Moderation Monitor",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Dry run with interactive auth\n"
            "  python create_dataverse_schema.py --dry-run --interactive\n\n"
            "  # Deploy with service principal\n"
            "  python create_dataverse_schema.py \\\n"
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

        create_schema(client, dry_run=args.dry_run)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
