#!/usr/bin/env python3
"""Create Dataverse schema for Agent Communication Restriction Detector.

Deploys five tables with shared and solution-specific option sets for
zone classification, severity levels, violation types, violation status,
direction types, and exception status. All operations are idempotent.

Tables:
  - fsi_AgentCommViolation (UserOwned): Communication violations
  - fsi_ApprovedCommRoute (OrganizationOwned): Approved communication matrix
  - fsi_AgentSkillRegistration (OrganizationOwned): Point-in-time skill config snapshots
  - fsi_CommException (UserOwned): Approved exceptions
  - fsi_CommScanRun (OrganizationOwned): Scan execution audit trail

Version: 1.2.1

Migrated in v1.2.1 from the solution-local `acrd_client.py` to the shared
`scripts/shared/dataverse_client.py`. The shared client supports the full
managed-identity-first authentication ladder (system-assigned MI, user-assigned
MI, workload identity federation, certificate, interactive, client-secret),
whereas the legacy ACRD client only supported interactive and client-secret.
(council review M-1)
"""

import argparse
import os
import sys
from pathlib import Path
from typing import Optional

# Import shared DataverseClient (the local acrd_client.py was retired in v1.2.1;
# see acrd_client.py for the deprecation stub).
sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared")
)
from dataverse_client import DataverseClient

# Publisher prefix for custom entities
PUBLISHER_PREFIX = "fsi"

# =============================================================================
# Shared Option Sets (reuse existing ACV option sets — existence check first)
# =============================================================================
#
# Style-decisions §9 specifies that new Dataverse global option sets start at
# value 100000000. `fsi_acv_zone` (0–3) and `fsi_acv_severity` (1–5) are
# allowlisted exceptions — they predate the convention and are shared across
# ACV, ACRD, CTSG, and other solutions. Re-keying them now would be a breaking
# cross-solution change that requires a coordinated migration. ACRD's
# solution-specific option sets (`fsi_ACRD_*`) below correctly use 100000000+.
# (council review M-6)

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
# ACRD-Specific Option Sets
# =============================================================================

ACRD_OPTIONSETS = {
    "fsi_ACRD_violationtype": {
        "name": "fsi_ACRD_violationtype",
        "options": [
            ("ZONE_BOUNDARY_VIOLATION", 100000000),
            ("CROSS_TENANT_VIOLATION", 100000001),
            ("CROSS_ENVIRONMENT_UNAPPROVED", 100000002),
            ("MAKER_CHECKER_VIOLATION", 100000003),
        ],
    },
    "fsi_ACRD_violationstatus": {
        "name": "fsi_ACRD_violationstatus",
        "options": [
            ("Open", 100000000),
            ("Acknowledged", 100000001),
            ("Remediated", 100000002),
            ("Excepted", 100000003),
        ],
    },
    "fsi_ACRD_directiontype": {
        "name": "fsi_ACRD_directiontype",
        "options": [
            ("OneWay", 100000000),
            ("Bidirectional", 100000001),
        ],
    },
    "fsi_ACRD_exceptionstatus": {
        "name": "fsi_ACRD_exceptionstatus",
        "options": [
            ("Pending", 100000000),
            ("Approved", 100000001),
            ("Denied", 100000002),
            ("Expired", 100000003),
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

VIOLATION_COLUMNS = [
    _string_col("fsi_CallingAgentId", "Calling Agent ID", 100,
                description="GUID of the agent initiating the communication"),
    _string_col("fsi_CallingAgentName", "Calling Agent Name", 500,
                description="Display name of the calling agent"),
    _string_col("fsi_CalledAgentId", "Called Agent ID", 100,
                description="GUID of the agent being called"),
    _string_col("fsi_CalledAgentName", "Called Agent Name", 500,
                description="Display name of the called agent"),
    _picklist_col("fsi_CallingAgentZone", "Calling Agent Zone", "fsi_acv_zone",
                  description="Zone classification of the calling agent"),
    _picklist_col("fsi_CalledAgentZone", "Called Agent Zone", "fsi_acv_zone",
                  description="Zone classification of the called agent"),
    _string_col("fsi_CallingEnvironmentId", "Calling Environment ID", 100,
                description="Environment GUID of the calling agent"),
    _string_col("fsi_CalledEnvironmentId", "Called Environment ID", 100,
                description="Environment GUID of the called agent"),
    _picklist_col("fsi_ViolationType", "Violation Type", "fsi_ACRD_violationtype",
                  description="Type of communication restriction violation"),
    _picklist_col("fsi_ViolationStatus", "Violation Status", "fsi_ACRD_violationstatus",
                  description="Current status of the violation"),
    _string_col("fsi_Severity", "Severity", 50,
                description="Violation severity (Critical/High/Medium/Warning)"),
    _string_col("fsi_SkillManifestUrl", "Skill Manifest URL", 2000,
                required=False,
                description="URL to the skill manifest triggering the violation"),
    _boolean_col("fsi_MakerCheckViolation", "Maker-Check Violation", default=False,
                 description="Whether this violation involves a maker-checker policy breach"),
    _string_col("fsi_RegulatoryContext", "Regulatory Context", 2000,
                required=False,
                description="FINRA/SOX/GLBA regulatory impact context"),
    _datetime_col("fsi_DetectedAt", "Detected At",
                  description="When the violation was detected"),
    _string_col("fsi_RunId", "Run ID", 36, required=False,
                description="Correlating scan GUID"),
    _string_col("fsi_SkillName", "Skill Name", 500,
                required=False,
                description="Name of the skill triggering the violation"),
    _string_col("fsi_EnvironmentName", "Environment Name", 500,
                required=False,
                description="Display name of the calling agent environment"),
    _memo_col("fsi_Notes", "Notes", 5000,
              description="Additional notes or remediation context"),
]

APPROVED_ROUTE_COLUMNS = [
    _picklist_col("fsi_SourceZone", "Source Zone", "fsi_acv_zone",
                  description="Zone classification of the source agent"),
    _picklist_col("fsi_TargetZone", "Target Zone", "fsi_acv_zone",
                  description="Zone classification of the target agent"),
    _picklist_col("fsi_DirectionType", "Direction Type", "fsi_ACRD_directiontype",
                  description="Whether the route is one-way or bidirectional"),
    _boolean_col("fsi_AllowCrossEnvironment", "Allow Cross-Environment", default=False,
                 description="Whether cross-environment communication is permitted on this route"),
    _boolean_col("fsi_IsActive", "Is Active", default=True,
                 description="Whether this approved route is currently active"),
    _string_col("fsi_ApprovedBy", "Approved By", 200,
                description="UPN of the administrator who approved this route"),
    _datetime_col("fsi_ApprovedAt", "Approved At",
                  description="When the route was approved"),
    _datetime_col("fsi_ExpiresAt", "Expires At", required=False,
                  description="Route approval expiration date (optional)"),
    _memo_col("fsi_Notes", "Notes", 5000,
              description="Additional notes or justification for approval"),
]

SKILL_REGISTRATION_COLUMNS = [
    _string_col("fsi_AgentId", "Agent ID", 100,
                description="Copilot Studio bot GUID"),
    _string_col("fsi_AgentName", "Agent Name", 500,
                description="Agent display name"),
    _string_col("fsi_EnvironmentId", "Environment ID", 100,
                description="Power Platform environment GUID"),
    _string_col("fsi_EnvironmentName", "Environment Name", 500,
                description="Environment display name"),
    _picklist_col("fsi_Zone", "Zone", "fsi_acv_zone",
                  description="Zone classification of the agent"),
    _string_col("fsi_SkillName", "Skill Name", 500,
                description="Name of the registered skill"),
    _string_col("fsi_TargetAgentId", "Target Agent ID", 100,
                required=False,
                description="GUID of the target agent for this skill"),
    _string_col("fsi_TargetAgentName", "Target Agent Name", 500,
                required=False,
                description="Display name of the target agent"),
    _string_col("fsi_TargetEnvironmentId", "Target Environment ID", 100,
                required=False,
                description="Environment GUID of the target agent"),
    _string_col("fsi_ManifestUrl", "Manifest URL", 2000,
                required=False,
                description="URL to the skill manifest definition"),
    _datetime_col("fsi_CapturedAt", "Captured At",
                  description="When the skill registration snapshot was captured"),
    _string_col("fsi_RunId", "Run ID", 36, required=False,
                description="Correlating scan GUID"),
    _memo_col("fsi_RawJson", "Raw JSON", 100000,
              description="Full JSON snapshot of the skill configuration"),
]

EXCEPTION_COLUMNS = [
    _string_col("fsi_CallingAgentId", "Calling Agent ID", 100,
                required=False,
                description="GUID of the calling agent (optional for zone-level exceptions)"),
    _string_col("fsi_CalledAgentId", "Called Agent ID", 100,
                required=False,
                description="GUID of the called agent (optional for zone-level exceptions)"),
    _picklist_col("fsi_SourceZone", "Source Zone", "fsi_acv_zone",
                  description="Zone classification of the source"),
    _picklist_col("fsi_TargetZone", "Target Zone", "fsi_acv_zone",
                  description="Zone classification of the target"),
    _picklist_col("fsi_ExceptionStatus", "Exception Status", "fsi_ACRD_exceptionstatus",
                  description="Current status of the exception request"),
    _memo_col("fsi_Justification", "Justification", 5000,
              description="Business justification for the exception"),
    _string_col("fsi_ApprovedBy", "Approved By", 200,
                required=False,
                description="UPN of the administrator who approved the exception"),
    _datetime_col("fsi_ApprovedAt", "Approved At", required=False,
                  description="When the exception was approved"),
    _datetime_col("fsi_ExpiresAt", "Expires At", required=False,
                  description="Exception expiration date (optional)"),
    _boolean_col("fsi_IsActive", "Is Active", default=True,
                 description="Whether this exception is currently active"),
]

SCAN_RUN_COLUMNS = [
    _string_col("fsi_RunId", "Run ID", 36,
                description="GUID correlating all records in one scan run"),
    _datetime_col("fsi_ValidationTime", "Validation Time",
                  description="When scan executed"),
    _integer_col("fsi_TotalAgents", "Total Agents",
                 description="Total agents scanned"),
    _integer_col("fsi_TotalSkills", "Total Skills",
                 description="Total skills discovered across all agents"),
    _integer_col("fsi_ViolationCount", "Violation Count",
                 description="Communication restriction violations detected"),
    _integer_col("fsi_CompliantCount", "Compliant Count", required=False,
                 description="Number of compliant skill registrations in this scan"),
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
    "fsi_agentcommviolation": {
        "schema_name": "fsi_AgentCommViolation",
        "display": "Agent Comm Violation",
        "plural": "Agent Comm Violations",
        "description": (
            "Communication restriction violations detected between agents "
            "across zones, environments, or tenants"
        ),
        "ownership": "UserOwned",
        "columns": VIOLATION_COLUMNS,
        "entity_set_name": None,  # Use default auto-generated name
    },
    "fsi_approvedcommroute": {
        "schema_name": "fsi_ApprovedCommRoute",
        "display": "Approved Comm Route",
        "plural": "Approved Comm Routes",
        "description": (
            "Approved zone-to-zone communication routing matrix "
            "defining permitted agent interaction paths"
        ),
        "ownership": "OrganizationOwned",
        "columns": APPROVED_ROUTE_COLUMNS,
        "entity_set_name": None,
    },
    "fsi_agentskillregistration": {
        "schema_name": "fsi_AgentSkillRegistration",
        "display": "Agent Skill Registration",
        "plural": "Agent Skill Registrations",
        "description": (
            "Point-in-time skill configuration snapshots for agents, "
            "capturing inter-agent communication capabilities"
        ),
        "ownership": "OrganizationOwned",
        "columns": SKILL_REGISTRATION_COLUMNS,
        "entity_set_name": None,
    },
    "fsi_commexception": {
        "schema_name": "fsi_CommException",
        "display": "Comm Exception",
        "plural": "Comm Exceptions",
        "description": (
            "Approved exceptions to communication restriction policies "
            "with justification and expiration tracking"
        ),
        "ownership": "UserOwned",
        "columns": EXCEPTION_COLUMNS,
        "entity_set_name": None,
    },
    "fsi_commscanrun": {
        "schema_name": "fsi_CommScanRun",
        "display": "Comm Scan Run",
        "plural": "Comm Scan Runs",
        "description": (
            "Immutable scan summary records for regulatory evidence "
            "(supports compliance with FINRA 4511, SEC 17a-3)"
        ),
        "ownership": "OrganizationOwned",
        "columns": SCAN_RUN_COLUMNS,
        # Explicit EntitySetName avoids auto-plural 'fsi_commscanruns'
        "entity_set_name": "fsi_commscanrun",
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
        "# Agent Communication Restriction Detector - Dataverse Schema",
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
        "### ACRD-Specific Option Sets",
        "",
        "| Option Set | Values |",
        "|-----------|--------|",
    ])

    for os_name, os_def in ACRD_OPTIONSETS.items():
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
    """Construct a Dataverse global OptionSetMetadata payload from an ACRD def.

    Mirrors the helper pattern in
    `cross-tenant-external-sharing-governance/scripts/create_ctsg_dataverse_schema.py`
    so that the schema script keeps a high-level option-set definition shape
    while still feeding the raw metadata dicts that the shared
    `DataverseClient.create_option_set()` expects. (council review M-1)
    """
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


def _build_table_metadata(table_def: dict) -> dict:
    """Construct a Dataverse EntityMetadata payload for a table.

    Builds the raw dict that the shared `DataverseClient.create_entity()`
    expects, including the required primary-name attribute. (council review M-1)
    """
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
                "@odata.type": "#Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": "fsi_Name",
                "DisplayName": _label(f"{table_def['display']} ID"),
                "Description": _label("Primary name attribute"),
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "MaxLength": 200,
                "FormatName": {"Value": "Text"},
            },
        ],
    }
    if table_def.get("entity_set_name"):
        definition["EntitySetName"] = table_def["entity_set_name"]
    return definition


def _build_column_metadata(col: dict) -> dict:
    """Pass-through helper for column metadata.

    ACRD's `_string_col`/`_memo_col`/`_integer_col`/`_boolean_col`/
    `_datetime_col`/`_picklist_col` builders already produce raw dicts that the
    shared `DataverseClient.create_column()` accepts unchanged. This helper
    exists for symmetry with `_build_table_metadata()` and
    `_build_optionset_metadata()` so future column-shape adjustments have a
    single place to land. (council review M-1)
    """
    return col


def create_shared_optionsets(client: DataverseClient, dry_run: bool = False) -> None:
    """Create or verify shared global option sets.

    These option sets are shared with ACV and other solutions.
    Existence is checked before creation to support idempotent runs.
    """
    print("\n[Creating/Verifying Shared Option Sets]")

    for os_name, os_def in SHARED_OPTIONSETS.items():
        client.create_option_set(_build_optionset_metadata(os_def))


def create_acrd_optionsets(client: DataverseClient, dry_run: bool = False) -> None:
    """Create ACRD-specific global option sets.

    These option sets are unique to the Agent Communication Restriction Detector.
    Existence is checked before creation to support idempotent runs.
    """
    print("\n[Creating ACRD-Specific Option Sets]")

    for os_name, os_def in ACRD_OPTIONSETS.items():
        client.create_option_set(_build_optionset_metadata(os_def))


def create_table_with_columns(
    client: DataverseClient,
    table_name: str,
    table_def: dict,
    columns: list[dict],
    dry_run: bool = False,
) -> None:
    """Create a table and its columns (idempotent).

    Args:
        client: Shared DataverseClient instance
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
        client.create_entity(_build_table_metadata(table_def))
        print(f"  {logical_name}: created")

    # Create columns
    print(f"  {logical_name} columns:")
    for col in columns:
        client.create_column(logical_name, _build_column_metadata(col))


def create_schema(client: DataverseClient, dry_run: bool = False) -> None:
    """Orchestrate full schema deployment.

    Order: shared option sets -> ACRD option sets -> tables -> columns.
    All operations are idempotent -- safe to re-run.
    """
    print("=" * 60)
    print("ACRD Dataverse Schema Deployment")
    print("  Agent Communication Restriction Detector")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN - No changes will be made ***\n")

    # Step 1: Shared option sets (must exist before tables reference them)
    create_shared_optionsets(client, dry_run)

    # Step 2: ACRD-specific option sets
    create_acrd_optionsets(client, dry_run)

    # Step 3: Tables and columns
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
    print(f"  Shared option sets: {len(SHARED_OPTIONSETS)}")
    print(f"  ACRD option sets: {len(ACRD_OPTIONSETS)}")
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
        description="Create Dataverse schema for Agent Communication Restriction Detector",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Dry run with interactive auth\n"
            "  python create_dataverse_schema.py --dry-run --interactive\n\n"
            "  # Deploy with service principal\n"
            "  python create_dataverse_schema.py \\\n"
            "    --tenant-id $ACRD_TENANT_ID \\\n"
            "    --client-id $ACRD_CLIENT_ID \\\n"
            "    --client-secret $ACRD_CLIENT_SECRET \\\n"
            "    --environment-url $ACRD_ENVIRONMENT_URL\n\n"
            "  # Generate schema documentation only\n"
            "  python create_dataverse_schema.py --output-docs\n"
        ),
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ACRD_TENANT_ID"),
        help="Microsoft Entra ID tenant ID (or set ACRD_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ACRD_CLIENT_ID"),
        help="Application (client) ID (or set ACRD_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("ACRD_CLIENT_SECRET"),
        # legacy: dev-only — replace with managed identity in production
        help=(
            "Service principal secret (or set ACRD_CLIENT_SECRET env var). "
            "Dev-only fallback; prefer managed identity or workload identity "
            "federation in production. See AGENTS.md authentication standard."
        ),
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ACRD_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set ACRD_ENVIRONMENT_URL env var)",
    )
    parser.add_argument(
        "--auth-mode",
        default=os.environ.get("ACRD_AUTH_MODE"),
        choices=[
            "interactive",
            "managed-identity",
            "workload-identity",
            "certificate",
            "client-secret",
        ],
        help=(
            "Authentication mode for the shared DataverseClient. Managed identity "
            "and workload identity require azure-identity (install via "
            "requirements.txt extras). Default: interactive when --interactive is "
            "set, otherwise client-secret."
        ),
    )
    parser.add_argument(
        "--certificate-path",
        default=os.environ.get("ACRD_CERTIFICATE_PATH"),
        help="Path to PEM/PFX certificate for --auth-mode certificate.",
    )
    parser.add_argument(
        "--certificate-password",
        default=os.environ.get("ACRD_CERTIFICATE_PASSWORD"),
        help="Optional certificate password for --auth-mode certificate.",
    )
    parser.add_argument(
        "--access-token",
        default=os.environ.get("ACRD_ACCESS_TOKEN"),
        help=(
            "Externally-acquired Dataverse bearer token (e.g. from a parent "
            "managed-identity or workload-identity process). Takes precedence "
            "over all other auth modes."
        ),
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
    if not args.environment_url:
        print("ERROR: --environment-url or ACRD_ENVIRONMENT_URL required")
        sys.exit(1)
    # tenant-id is optional for managed-identity and when an external access
    # token is supplied (the shared client tolerates both cases).
    if (
        not args.tenant_id
        and not args.access_token
        and args.auth_mode not in ("managed-identity", "workload-identity")
    ):
        print(
            "ERROR: --tenant-id or ACRD_TENANT_ID required "
            "(not needed for managed-identity / workload-identity / --access-token)"
        )
        sys.exit(1)

    try:
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=args.client_secret,
            access_token=args.access_token,
            interactive=args.interactive,
            dry_run=args.dry_run,
            auth_mode=args.auth_mode,
            certificate_path=args.certificate_path,
            certificate_password=args.certificate_password,
        )

        create_schema(client, dry_run=args.dry_run)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
