#!/usr/bin/env python3
"""Create Dataverse schema for HITL Workflow Governance.

Deploys three tables with shared and solution-specific option sets for
zone classification, severity levels, checkpoint types, checkpoint status,
and violation status. All operations are idempotent.

Tables:
  - fsi_HitlCheckpointResult (UserOwned): Per-agent HITL checkpoint scan results
  - fsi_HitlCheckpointException (UserOwned): Approved exceptions
  - fsi_HitlScanRun (OrganizationOwned): Scan execution audit trail
"""

import argparse
import os
import sys
from pathlib import Path
from typing import Optional

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared")
)
from dataverse_client import DataverseClient  # noqa: E402

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
# HWG-Specific Option Sets
# =============================================================================

HWG_OPTIONSETS = {
    "fsi_HWG_checkpointtype": {
        "name": "fsi_HWG_checkpointtype",
        "options": [
            ("RequestForInformation", 100000000),
            ("MultistageApproval", 100000001),
            ("CustomHitl", 100000002),
            ("AdvancedApprovalsGeneric", 100000003),
            ("NotApplicable", 100000004),
        ],
    },
    "fsi_HWG_checkpointstatus": {
        "name": "fsi_HWG_checkpointstatus",
        "options": [
            ("Present", 100000000),
            ("Missing", 100000001),
            ("Partial", 100000002),
            ("UnableToDetermine", 100000003),
        ],
    },
    "fsi_HWG_violationstatus": {
        "name": "fsi_HWG_violationstatus",
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

HITL_CHECKPOINT_RESULT_COLUMNS = [
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
    _string_col("fsi_FlowName", "Flow Name", 500,
                required=False,
                description="Agent flow name"),
    _string_col("fsi_FlowId", "Flow ID", 100,
                required=False,
                description="Agent flow GUID"),
    _picklist_col("fsi_CheckpointType", "Checkpoint Type",
                  "fsi_HWG_checkpointtype",
                  description="Type of HITL checkpoint"),
    _string_col("fsi_CheckpointName", "Checkpoint Name", 500,
                required=False,
                description="Name of the HITL action/step"),
    _picklist_col("fsi_CheckpointStatus", "Checkpoint Status",
                  "fsi_HWG_checkpointstatus",
                  description="Whether checkpoint is present/missing"),
    _string_col("fsi_AssignedReviewers", "Assigned Reviewers", 2000,
                required=False,
                description="Configured reviewer email addresses"),
    _integer_col("fsi_InputCount", "Input Count",
                 required=False,
                 description="Number of RFI inputs configured"),
    _boolean_col("fsi_HasHitlCheckpoint", "Has HITL Checkpoint", default=False,
                 description="Whether agent flow has at least one HITL checkpoint"),
    _picklist_col("fsi_ViolationStatus", "Violation Status",
                  "fsi_HWG_violationstatus",
                  description="Current violation lifecycle status"),
    _string_col("fsi_ViolationType", "Violation Type", 200,
                required=False,
                description="e.g., MissingHitlCheckpoint, MissingReviewer, InsufficientInputs"),
    _string_col("fsi_Severity", "Severity", 50,
                description="Critical/High/Medium/Warning"),
    _string_col("fsi_RegulatoryContext", "Regulatory Context", 2000,
                required=False,
                description="FINRA/SOX regulatory impact context"),
    _datetime_col("fsi_DetectedAt", "Detected At",
                  description="When detected"),
    _string_col("fsi_RunId", "Run ID", 36,
                required=False,
                description="Correlating scan GUID"),
]

HITL_CHECKPOINT_EXCEPTION_COLUMNS = [
    _string_col("fsi_EnvironmentGuid", "Environment GUID", 100,
                required=False,
                description="Power Platform environment GUID (optional for global exceptions)"),
    _string_col("fsi_AgentId", "Agent ID", 100,
                required=False,
                description="Copilot Studio bot GUID (optional for broad exceptions)"),
    _string_col("fsi_FlowName", "Flow Name", 500,
                required=False,
                description="Agent flow name (optional filter)"),
    _picklist_col("fsi_Zone", "Zone", "fsi_acv_zone",
                  description="Zone this exception applies to"),
    _string_col("fsi_ExceptionScope", "Exception Scope", 200,
                description="Scope (AllFlows, SpecificFlow, ReadOnlyActions)"),
    _string_col("fsi_RequestedBy", "Requested By", 200,
                required=False,
                description="UPN of the exception requester"),
    _datetime_col("fsi_RequestedAt", "Requested At",
                  required=False,
                  description="When the exception was requested"),
    _string_col("fsi_ApprovalStatus", "Approval Status", 50,
                required=False,
                description="Pending/Approved/Rejected/TimedOut"),
    _memo_col("fsi_ApprovalNotes", "Approval Notes", 5000,
              description="Approver comments or timeout/rejection reason"),
    _string_col("fsi_ApprovedBy", "Approved By", 200,
                required=False,
                description="UPN of approving or responding administrator"),
    _datetime_col("fsi_ApprovedAt", "Approved At",
                  required=False,
                  description="When the approval response was recorded"),
    _datetime_col("fsi_ExpiresAt", "Expires At",
                  required=False,
                  description="Exception expiration date (optional)"),
    _memo_col("fsi_Justification", "Justification", 5000,
              description="Business justification for the exception"),
    _boolean_col("fsi_IsActive", "Is Active", default=True,
                 description="Whether this exception is currently active"),
]

HITL_SCAN_RUN_COLUMNS = [
    _string_col("fsi_RunId", "Run ID", 36,
                description="GUID correlating all records in one scan run"),
    _datetime_col("fsi_ScanTime", "Scan Time",
                  description="When scan executed"),
    _integer_col("fsi_TotalAgents", "Total Agents",
                 description="Total agents scanned"),
    _integer_col("fsi_TotalFlows", "Total Flows",
                 description="Total agent flows evaluated"),
    _integer_col("fsi_AgentsWithHitl", "Agents With HITL",
                 required=False,
                 description="Agents with at least one HITL checkpoint"),
    _integer_col("fsi_AgentsMissingHitl", "Agents Missing HITL",
                 required=False,
                 description="Agents missing required HITL checkpoints"),
    _integer_col("fsi_TotalCheckpoints", "Total Checkpoints",
                 required=False,
                 description="Total HITL checkpoints found across all agents"),
    _integer_col("fsi_CompliantCount", "Compliant Count",
                 required=False,
                 description="Number of compliant agents in this scan run"),
    _integer_col("fsi_CheckpointsFound", "Checkpoints Found",
                 description="HITL checkpoints detected"),
    _integer_col("fsi_CheckpointsMissing", "Checkpoints Missing",
                 description="Required HITL checkpoints not found"),
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
    "fsi_hitlcheckpointresult": {
        "schema_name": "fsi_HitlCheckpointResult",
        "display": "HITL Checkpoint Result",
        "plural": "HITL Checkpoint Results",
        "description": (
            "Per-agent HITL checkpoint scan results tracking Human in the Loop "
            "checkpoint presence for agent flows across Power Platform environments"
        ),
        "ownership": "UserOwned",
        "columns": HITL_CHECKPOINT_RESULT_COLUMNS,
        "entity_set_name": None,  # Use default auto-generated name
    },
    "fsi_hitlcheckpointexception": {
        "schema_name": "fsi_HitlCheckpointException",
        "display": "HITL Checkpoint Exception",
        "plural": "HITL Checkpoint Exceptions",
        "description": (
            "Approved exceptions for agents not requiring HITL checkpoints, "
            "with expiration and audit trail"
        ),
        "ownership": "UserOwned",
        "columns": HITL_CHECKPOINT_EXCEPTION_COLUMNS,
        "entity_set_name": None,
    },
    "fsi_hitlscanrun": {
        "schema_name": "fsi_HitlScanRun",
        "display": "HITL Scan Run",
        "plural": "HITL Scan Runs",
        "description": (
            "Immutable scan execution audit trail for regulatory evidence "
            "(supports compliance with FINRA Rule 4511(a) and SEC Rule 17a-3)"
        ),
        "ownership": "OrganizationOwned",
        "columns": HITL_SCAN_RUN_COLUMNS,
        "entity_set_name": None,
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
        "# HITL Workflow Governance - Dataverse Schema",
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
        "### HWG-Specific Option Sets",
        "",
        "| Option Set | Values |",
        "|-----------|--------|",
    ])

    for os_name, os_def in HWG_OPTIONSETS.items():
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


def _build_optionset_metadata(os_def: dict) -> dict:
    """Construct a Dataverse global OptionSetMetadata payload from an HWG def."""
    name = os_def["name"]
    options = os_def["options"]
    display_label = os_def.get("display") or " ".join(
        word.capitalize() for word in name.split("_")[1:]
    ) or name
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.OptionSetMetadata",
        "Name": name,
        "DisplayName": _label(display_label),
        "Description": _label(os_def.get("description", display_label)),
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "IsCustomOptionSet": True,
        "Options": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.OptionMetadata",
                "Value": value,
                "Label": _label(label),
            }
            for (label, value) in options
        ],
    }


def create_shared_optionsets(client: DataverseClient, dry_run: bool = False) -> None:
    """Create or verify shared global option sets.

    These option sets are shared with ACV and other solutions.
    Existence is checked before creation to support idempotent runs.

    NOTE: ``dry_run`` is **not** passed to the shared DataverseClient
    constructor (per the migrate_ctsg_optionsets_v1_1_0.py pattern), because
    that would short-circuit reads. Writes are gated locally via the
    ``if not dry_run`` branch below.
    """
    print("\n[Creating/Verifying Shared Option Sets]")

    for os_name, os_def in SHARED_OPTIONSETS.items():
        existing = client.get_global_optionset(os_def["name"])
        if existing:
            print(f"  {os_def['name']}: already exists, skipping")
            continue
        if dry_run:
            print(f"  [DRY RUN] Would create option set: {os_def['name']}")
        else:
            client.create_global_optionset(_build_optionset_metadata(os_def))
            print(f"  {os_def['name']}: created")


def create_hwg_optionsets(client: DataverseClient, dry_run: bool = False) -> None:
    """Create HWG-specific global option sets.

    These option sets are unique to HITL Workflow Governance.
    Existence is checked before creation to support idempotent runs.

    Local write gating mirrors create_shared_optionsets — see that docstring
    for the rationale on not passing ``dry_run`` to the shared client.
    """
    print("\n[Creating HWG-Specific Option Sets]")

    for os_name, os_def in HWG_OPTIONSETS.items():
        existing = client.get_global_optionset(os_def["name"])
        if existing:
            print(f"  {os_def['name']}: already exists, skipping")
            continue
        if dry_run:
            print(f"  [DRY RUN] Would create option set: {os_def['name']}")
        else:
            client.create_global_optionset(_build_optionset_metadata(os_def))
            print(f"  {os_def['name']}: created")


def create_table_with_columns(
    client: DataverseClient,
    table_name: str,
    table_def: dict,
    columns: list[dict],
    dry_run: bool = False,
) -> None:
    """Create a table and its columns (idempotent).

    Args:
        client: shared DataverseClient instance (constructed in live mode)
        table_name: Logical table name
        table_def: Table definition dict
        columns: List of column definitions
        dry_run: Preview mode flag (gates writes locally)
    """
    logical_name = table_name.lower()

    # Check if table already exists (live read; ``dry_run`` is not passed to
    # the client, so this returns the real result in both modes).
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
                    "SchemaName": "fsi_name",
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

        if dry_run:
            print(f"  [DRY RUN] Would create entity: {table_def['schema_name']}")
        else:
            client.create_entity(definition)
            print(f"  {logical_name}: created")

    # Create columns
    print(f"  {logical_name} columns:")
    for col in columns:
        col_schema = col["SchemaName"]
        col_logical = col_schema.lower()
        existing_col = client.get_attribute_metadata(logical_name, col_logical)
        if existing_col:
            continue
        if dry_run:
            print(f"    [DRY RUN] Would create column: {logical_name}.{col_schema}")
        else:
            client.create_attribute(logical_name, col)
            print(f"    {logical_name}.{col_schema}: created")


def create_schema(client: DataverseClient, dry_run: bool = False) -> None:
    """Orchestrate full schema deployment.

    Order: shared option sets -> HWG option sets -> tables -> columns.
    All operations are idempotent -- safe to re-run.
    """
    print("=" * 60)
    print("HWG Dataverse Schema Deployment")
    print("  HITL Workflow Governance")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN - No changes will be made ***\n")

    # Step 1: Shared option sets (must exist before tables reference them)
    create_shared_optionsets(client, dry_run)

    # Step 2: HWG-specific option sets
    create_hwg_optionsets(client, dry_run)

    # Step 3: Tables and columns
    print("\n[Creating Tables and Columns]")
    for table_name, table_def in TABLES.items():
        print(f"\n  --- {table_def['display']} ({table_def['ownership']}) ---")
        create_table_with_columns(
            client, table_name, table_def, table_def["columns"], dry_run
        )

    # Summary
    all_optionsets = {**SHARED_OPTIONSETS, **HWG_OPTIONSETS}
    print("\n" + "=" * 60)
    if dry_run:
        print("DRY RUN COMPLETE - Review output above")
    else:
        print("SCHEMA DEPLOYMENT COMPLETE")
    print(f"  Shared option sets: {len(SHARED_OPTIONSETS)}")
    print(f"  HWG option sets: {len(HWG_OPTIONSETS)}")
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
        description="Create Dataverse schema for HITL Workflow Governance",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Dry run with interactive auth\n"
            "  python create_hwg_dataverse_schema.py --dry-run --interactive\n\n"
            "  # Deploy with service principal\n"
            "  python create_hwg_dataverse_schema.py \\\n"
            "    --tenant-id $HWG_TENANT_ID \\\n"
            "    --client-id $HWG_CLIENT_ID \\\n"
            "    --client-secret $HWG_CLIENT_SECRET \\\n"
            "    --environment-url $HWG_ENVIRONMENT_URL\n\n"
            "  # Generate schema documentation only\n"
            "  python create_hwg_dataverse_schema.py --output-docs\n"
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
        print("ERROR: --tenant-id or HWG_TENANT_ID required")
        sys.exit(1)
    if not args.environment_url:
        print("ERROR: --environment-url or HWG_ENVIRONMENT_URL required")
        sys.exit(1)

    try:
        # NOTE: dry_run is deliberately NOT passed to the shared
        # DataverseClient constructor (canonical reference:
        # cross-tenant-external-sharing-governance/scripts/
        #   migrate_ctsg_optionsets_v1_1_0.py lines 238-267). Doing so would
        # short-circuit READS (get_global_optionset, check_table_exists,
        # get_attribute_metadata), silently making every preview claim that
        # nothing exists and thereby reporting bogus "would create" output.
        # Writes are gated locally inside create_shared_optionsets,
        # create_hwg_optionsets, and create_table_with_columns instead.
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=args.client_secret,
            interactive=args.interactive,
        )

        create_schema(client, dry_run=args.dry_run)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
