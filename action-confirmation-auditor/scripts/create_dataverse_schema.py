#!/usr/bin/env python3
"""Create Dataverse schema for Action Confirmation Auditor.

Deploys three tables with shared and solution-specific option sets for
zone classification, severity levels, action types, confirmation status,
and violation status. All operations are idempotent.

Tables:
  - fsi_ActionAuditResult (UserOwned): Per-action violation records
  - fsi_ActionConfirmationException (UserOwned): Approved exceptions
  - fsi_ActionScanRun (OrganizationOwned): Scan execution audit trail
"""

import argparse
import os
import sys
from pathlib import Path
from typing import Optional

from aca_client import ACAClient

# Publisher prefix for custom entities
PUBLISHER_PREFIX = "fsi"

# =============================================================================
# Shared Option Sets (reuse existing ACV option sets — existence check first)
# =============================================================================

SHARED_OPTIONSETS = {
    "fsi_acv_zone": {
        "name": "fsi_acv_zone",
        "options": [
            ("Unclassified", 0),
            ("Zone 1", 1),
            ("Zone 2", 2),
            ("Zone 3", 3),
        ],
    },
    "fsi_acv_severity": {
        "name": "fsi_acv_severity",
        "options": [
            ("Passed", 1),
            ("Warning", 2),
            ("GracePeriod", 3),
            ("Failed", 4),
            ("Error", 5),
        ],
    },
}

# =============================================================================
# ACA-Specific Option Sets
# =============================================================================

ACA_OPTIONSETS = {
    "fsi_ACA_actiontype": {
        "name": "fsi_ACA_actiontype",
        "options": [
            ("ConnectorAction", 100000000),
            ("CloudFlowAction", 100000001),
            ("PluginAction", 100000002),
            ("CustomAction", 100000003),
            ("HttpRequest", 100000004),
        ],
    },
    "fsi_ACA_confirmationstatus": {
        "name": "fsi_ACA_confirmationstatus",
        "options": [
            ("Present", 100000000),
            ("Missing", 100000001),
            ("Partial", 100000002),
            ("UnableToDetermine", 100000003),
        ],
    },
    "fsi_ACA_violationstatus": {
        "name": "fsi_ACA_violationstatus",
        "options": [
            ("Open", 100000000),
            ("Acknowledged", 100000001),
            ("Excepted", 100000002),
            ("Resolved", 100000003),
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

ACTION_AUDIT_RESULT_COLUMNS = [
    _string_col("fsi_EnvironmentGuid", "Environment GUID", 100,
                description="Power Platform environment GUID"),
    _string_col("fsi_EnvironmentName", "Environment Name", 500,
                description="Environment display name"),
    _picklist_col("fsi_Zone", "Zone", "fsi_acv_zone",
                  description="Zone classification"),
    _string_col("fsi_AgentId", "Agent ID", 100,
                description="Copilot Studio bot GUID"),
    _string_col("fsi_AgentName", "Agent Name", 500,
                description="Agent display name"),
    _string_col("fsi_TopicName", "Topic Name", 500,
                required=False,
                description="Name of the topic containing the action"),
    _string_col("fsi_TopicId", "Topic ID", 100,
                required=False,
                description="GUID of the topic containing the action"),
    _string_col("fsi_ActionName", "Action Name", 500,
                description="Name of the action being audited"),
    _picklist_col("fsi_ActionType", "Action Type", "fsi_ACA_actiontype",
                  description="Type of action (ConnectorAction/CloudFlowAction/etc.)"),
    _string_col("fsi_ConnectorName", "Connector Name", 500,
                required=False,
                description="Connector name if action is a connector action"),
    _string_col("fsi_HttpMethod", "HTTP Method", 20,
                required=False,
                description="HTTP method for HTTP request actions"),
    _string_col("fsi_RiskLevel", "Risk Level", 50,
                description="Zone-based risk level (hardcoded in v1.0)"),
    _picklist_col("fsi_ConfirmationStatus", "Confirmation Status",
                  "fsi_ACA_confirmationstatus",
                  description="Whether step-up confirmation is present/missing/partial"),
    _picklist_col("fsi_ViolationStatus", "Violation Status",
                  "fsi_ACA_violationstatus",
                  description="Current violation lifecycle status"),
    _string_col("fsi_Severity", "Severity", 50,
                description="Violation severity (Critical/High/Medium/Warning)"),
    _string_col("fsi_RegulatoryContext", "Regulatory Context", 2000,
                required=False,
                description="FINRA/SOX/GLBA regulatory impact context"),
    _datetime_col("fsi_DetectedAt", "Detected At",
                  description="When violation was detected"),
    _string_col("fsi_RunId", "Run ID", 36,
                required=False,
                description="Correlating scan GUID"),
]

ACTION_CONFIRMATION_EXCEPTION_COLUMNS = [
    _string_col("fsi_EnvironmentGuid", "Environment GUID", 100,
                required=False,
                description="Power Platform environment GUID (optional for global exceptions)"),
    _string_col("fsi_AgentId", "Agent ID", 100,
                required=False,
                description="Copilot Studio bot GUID (optional for broad exceptions)"),
    _string_col("fsi_ActionName", "Action Name", 500,
                description="Name of the excepted action"),
    _picklist_col("fsi_ActionType", "Action Type", "fsi_ACA_actiontype",
                  required=False,
                  description="Type of action (optional filter)"),
    _string_col("fsi_ConnectorName", "Connector Name", 500,
                required=False,
                description="Connector name (optional filter)"),
    _picklist_col("fsi_Zone", "Zone", "fsi_acv_zone",
                  description="Zone this exception applies to"),
    _string_col("fsi_ApprovedBy", "Approved By", 200,
                description="UPN of approving administrator"),
    _datetime_col("fsi_ApprovedAt", "Approved At",
                  description="When exception was approved"),
    _datetime_col("fsi_ExpiresAt", "Expires At",
                  required=False,
                  description="Exception expiration date (optional)"),
    _memo_col("fsi_Justification", "Justification", 5000,
              description="Business justification for the exception"),
    _boolean_col("fsi_IsActive", "Is Active", default=True,
                 description="Whether this exception is currently active"),
]

ACTION_SCAN_RUN_COLUMNS = [
    _string_col("fsi_RunId", "Run ID", 36,
                description="GUID correlating all records in one scan run"),
    _datetime_col("fsi_ValidationTime", "Validation Time",
                  description="When scan executed"),
    _integer_col("fsi_TotalAgents", "Total Agents",
                 description="Total agents scanned"),
    _integer_col("fsi_TotalActions", "Total Actions",
                 description="Total actions evaluated across all agents"),
    _integer_col("fsi_ActionsWithConfirmation", "Actions With Confirmation",
                 description="Actions that have step-up confirmation configured"),
    _integer_col("fsi_ActionsMissingConfirmation", "Actions Missing Confirmation",
                 description="Actions missing required step-up confirmation"),
    _integer_col("fsi_ViolationCount", "Violation Count",
                 description="Total violations detected in this scan run"),
    _string_col("fsi_OverallStatus", "Overall Status", 50,
                description="Passed/Failed/Warning/Critical"),
    _string_col("fsi_EnvironmentsScanned", "Environments Scanned", 2000,
                required=False,
                description="Comma-separated environments covered"),
    _memo_col("fsi_SummaryJson", "Summary JSON", 100000,
              description="Full JSON summary blob"),
]


# =============================================================================
# Table Definitions
# =============================================================================

TABLES = {
    "fsi_actionauditresult": {
        "schema_name": "fsi_ActionAuditResult",
        "display": "Action Audit Result",
        "plural": "Action Audit Results",
        "description": (
            "Per-action violation records tracking step-up confirmation "
            "presence for agent operations across Power Platform environments"
        ),
        "ownership": "UserOwned",
        "columns": ACTION_AUDIT_RESULT_COLUMNS,
        "entity_set_name": None,  # Use default auto-generated name
    },
    "fsi_actionconfirmationexception": {
        "schema_name": "fsi_ActionConfirmationException",
        "display": "Action Confirmation Exception",
        "plural": "Action Confirmation Exceptions",
        "description": (
            "Approved exceptions for actions that do not require "
            "step-up confirmation, with expiration and audit trail"
        ),
        "ownership": "UserOwned",
        "columns": ACTION_CONFIRMATION_EXCEPTION_COLUMNS,
        "entity_set_name": None,
    },
    "fsi_actionscanrun": {
        "schema_name": "fsi_ActionScanRun",
        "display": "Action Scan Run",
        "plural": "Action Scan Runs",
        "description": (
            "Immutable scan execution audit trail for regulatory evidence "
            "(supports compliance with FINRA 4511, SEC 17a-3)"
        ),
        "ownership": "OrganizationOwned",
        "columns": ACTION_SCAN_RUN_COLUMNS,
        # Explicit EntitySetName avoids auto-plural 'fsi_actionscanruns'
        "entity_set_name": "fsi_actionscanrun",
    },
}


# =============================================================================
# Documentation Generator
# =============================================================================


def generate_docs(output_path: str) -> None:
    """Generate Markdown documentation of the Dataverse schema.

    Writes a dataverse-schema.md file with tables and columns in
    Markdown table format.

    Args:
        output_path: Path to write the documentation file
    """
    lines = [
        "# Action Confirmation Auditor - Dataverse Schema",
        "",
        "Auto-generated schema documentation. Do not edit manually.",
        "",
        "## Option Sets",
        "",
        "### Shared Option Sets (reused from ACV)",
        "",
        "| Option Set | Values |",
        "|-----------|--------|",
    ]

    for os_name, os_def in SHARED_OPTIONSETS.items():
        values = ", ".join(
            f"{label} ({val})" for label, val in os_def["options"]
        )
        lines.append(f"| {os_name} | {values} |")

    lines.extend([
        "",
        "### ACA-Specific Option Sets",
        "",
        "| Option Set | Values |",
        "|-----------|--------|",
    ])

    for os_name, os_def in ACA_OPTIONSETS.items():
        values = ", ".join(
            f"{label} ({val})" for label, val in os_def["options"]
        )
        lines.append(f"| {os_name} | {values} |")

    lines.extend(["", "## Tables", ""])

    for table_name, table_def in TABLES.items():
        lines.extend([
            f"### {table_def['display']} (`{table_def['schema_name']}`)",
            "",
            f"**Ownership:** {table_def['ownership']}",
            f"**Description:** {table_def['description']}",
            "",
            "| Column (SchemaName) | Type | Required | Description |",
            "|-------------------|------|----------|-------------|",
            "| fsi_Name | String(200) | Yes | Primary name attribute |",
        ])

        for col in table_def["columns"]:
            schema = col["SchemaName"]
            odata_type = col.get("@odata.type", "")
            required_val = col.get("RequiredLevel", {}).get("Value", "None")
            is_required = "Yes" if required_val == "ApplicationRequired" else "No"
            desc_obj = col.get("Description", {})
            desc = ""
            if desc_obj:
                labels = desc_obj.get("LocalizedLabels", [])
                if labels:
                    desc = labels[0].get("Label", "")

            # Determine type string
            if "StringAttributeMetadata" in odata_type:
                max_len = col.get("MaxLength", "")
                type_str = f"String({max_len})"
            elif "MemoAttributeMetadata" in odata_type:
                max_len = col.get("MaxLength", "")
                type_str = f"Memo({max_len})"
            elif "IntegerAttributeMetadata" in odata_type:
                type_str = "Integer"
            elif "BooleanAttributeMetadata" in odata_type:
                default = col.get("DefaultValue", False)
                type_str = f"Boolean (default: {str(default).lower()})"
            elif "DateTimeAttributeMetadata" in odata_type:
                type_str = "DateTime"
            elif "PicklistAttributeMetadata" in odata_type:
                bind = col.get("GlobalOptionSet@odata.bind", "")
                os_name = bind.split("'")[1] if "'" in bind else "unknown"
                type_str = f"Picklist ({os_name})"
            else:
                type_str = "Unknown"

            lines.append(f"| {schema} | {type_str} | {is_required} | {desc} |")

        lines.append("")

    # Write the file
    output_dir = os.path.dirname(output_path)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
    with open(output_path, "w") as f:
        f.write("\n".join(lines))
    print(f"  Documentation written to: {output_path}")


# =============================================================================
# Deployment Functions
# =============================================================================


def create_shared_optionsets(client: ACAClient, dry_run: bool = False) -> None:
    """Create or verify shared global option sets.

    These option sets are shared with ACV and other solutions.
    Existence is checked before creation to support idempotent runs.
    """
    print("\n[Creating/Verifying Shared Option Sets]")

    for os_name, os_def in SHARED_OPTIONSETS.items():
        client.create_option_set(os_def["name"], os_def["options"])


def create_aca_optionsets(client: ACAClient, dry_run: bool = False) -> None:
    """Create ACA-specific global option sets.

    These option sets are unique to the Action Confirmation Auditor.
    Existence is checked before creation to support idempotent runs.
    """
    print("\n[Creating ACA-Specific Option Sets]")

    for os_name, os_def in ACA_OPTIONSETS.items():
        client.create_option_set(os_def["name"], os_def["options"])


def create_table_with_columns(
    client: ACAClient,
    table_name: str,
    table_def: dict,
    columns: list[dict],
    dry_run: bool = False,
) -> None:
    """Create a table and its columns (idempotent).

    Args:
        client: ACAClient instance
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
                    "MaxLength": 200,
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


def create_schema(client: ACAClient, dry_run: bool = False) -> None:
    """Orchestrate full schema deployment.

    Order: shared option sets -> ACA option sets -> tables -> columns.
    All operations are idempotent -- safe to re-run.
    """
    print("=" * 60)
    print("ACA Dataverse Schema Deployment")
    print("  Action Confirmation Auditor")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN - No changes will be made ***\n")

    # Step 1: Shared option sets (must exist before tables reference them)
    create_shared_optionsets(client, dry_run)

    # Step 2: ACA-specific option sets
    create_aca_optionsets(client, dry_run)

    # Step 3: Tables and columns
    print("\n[Creating Tables and Columns]")
    for table_name, table_def in TABLES.items():
        print(f"\n  --- {table_def['display']} ({table_def['ownership']}) ---")
        create_table_with_columns(
            client, table_name, table_def, table_def["columns"], dry_run
        )

    # Summary
    all_optionsets = {**SHARED_OPTIONSETS, **ACA_OPTIONSETS}
    print("\n" + "=" * 60)
    if dry_run:
        print("DRY RUN COMPLETE - Review output above")
    else:
        print("SCHEMA DEPLOYMENT COMPLETE")
    print(f"  Shared option sets: {len(SHARED_OPTIONSETS)}")
    print(f"  ACA option sets: {len(ACA_OPTIONSETS)}")
    print(f"  Tables: {len(TABLES)}")
    total_cols = sum(len(t["columns"]) for t in TABLES.values())
    print(f"  Columns: {total_cols}")
    print("=" * 60)


# =============================================================================
# CLI Entry Point
# =============================================================================


def main():
    """CLI entry point for schema deployment."""
    parser = argparse.ArgumentParser(
        description="Create Dataverse schema for Action Confirmation Auditor",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Dry run with interactive auth\n"
            "  python create_dataverse_schema.py --dry-run --interactive\n\n"
            "  # Deploy with service principal\n"
            "  python create_dataverse_schema.py \\\n"
            "    --tenant-id $ACA_TENANT_ID \\\n"
            "    --client-id $ACA_CLIENT_ID \\\n"
            "    --client-secret $ACA_CLIENT_SECRET \\\n"
            "    --environment-url $ACA_ENVIRONMENT_URL\n\n"
            "  # Generate schema documentation only\n"
            "  python create_dataverse_schema.py --output-docs\n"
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
    parser.add_argument(
        "--output-docs",
        action="store_true",
        help="Generate docs/dataverse-schema.md and exit (no Dataverse connection)",
    )

    args = parser.parse_args()

    # Handle --output-docs (no connection needed)
    if args.output_docs:
        script_dir = Path(__file__).resolve().parent
        docs_path = script_dir.parent / "docs" / "dataverse-schema.md"
        generate_docs(str(docs_path))
        print("Documentation generation complete.")
        sys.exit(0)

    # Validate required arguments for deployment
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

        create_schema(client, dry_run=args.dry_run)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
