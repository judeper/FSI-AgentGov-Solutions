#!/usr/bin/env python3
"""Create Dataverse schema for Generative AI Config Auditor.

Deploys five tables with shared and solution-specific option sets for
zone classification, severity levels, orchestration modes, generative AI
feature types, and connection approval status. All operations are idempotent.

Tables:
  - fsi_GACBaseline (UserOwned): Per-agent generative AI config snapshots
  - fsi_GACValidationHistory (OrganizationOwned): Scan summary records
  - fsi_GACViolation (UserOwned): Per-agent violations with severity
  - fsi_GACApprovedConnection (UserOwned): Approved Azure OpenAI connections
  - fsi_GACFeatureInventory (UserOwned): Per-agent feature tracking inventory
"""

import argparse
import os
import sys
from pathlib import Path
from typing import Optional

# Import the shared Dataverse client from scripts/shared.
_SHARED_DIR = Path(__file__).resolve().parent.parent.parent / "scripts" / "shared"
if str(_SHARED_DIR) not in sys.path:
    sys.path.insert(0, str(_SHARED_DIR))
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
# GAC-Specific Option Sets
# =============================================================================

GAC_OPTIONSETS = {
    "fsi_GAC_orchestrationmode": {
        "name": "fsi_GAC_orchestrationmode",
        "options": [
            ("Classic", 100000000),
            ("Generative", 100000001),
            ("Custom", 100000002),
        ],
    },
    "fsi_GAC_genaifeaturetype": {
        "name": "fsi_GAC_genaifeaturetype",
        "options": [
            ("AzureOpenAIIntegration", 100000000),
            ("GenerativeOrchestration", 100000001),
            ("GenerativeAnswersNode", 100000002),
            ("SearchAndSummarize", 100000003),
            ("GenerativeActions", 100000004),
            ("KnowledgeSource", 100000005),
            ("ModelKnowledge", 100000006),
            ("SemanticSearch", 100000007),
        ],
    },
    "fsi_GAC_connectionstatus": {
        "name": "fsi_GAC_connectionstatus",
        "options": [
            ("Approved", 100000000),
            ("Unapproved", 100000001),
            ("Unknown", 100000002),
            ("NotApplicable", 100000003),
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
    _picklist_col("fsi_Zone", "Zone", "fsi_acv_zone",
                  description="Zone classification"),
    _string_col("fsi_AgentId", "Agent ID", 100,
                description="Copilot Studio bot GUID"),
    _string_col("fsi_AgentName", "Agent Name", 500,
                description="Agent display name"),
    _boolean_col("fsi_AoaiEnabled", "Azure OpenAI Enabled", default=False,
                 description="Whether Azure OpenAI integration is enabled"),
    _picklist_col("fsi_OrchestrationMode", "Orchestration Mode",
                  "fsi_GAC_orchestrationmode",
                  description="Agent orchestration mode (Classic/Generative/Custom)"),
    _integer_col("fsi_KnowledgeSourceCount", "Knowledge Source Count",
                 required=False,
                 description="Number of knowledge sources configured"),
    _integer_col("fsi_GenerativeAnswersNodeCount", "Generative Answers Node Count",
                 required=False,
                 description="Number of generative answers nodes in topic tree"),
    _string_col("fsi_AoaiConnectionId", "AOAI Connection ID", 200,
                required=False,
                description="Azure OpenAI connection reference identifier"),
    _boolean_col("fsi_ModelKnowledgeEnabled", "Allow Ungrounded Responses Enabled",
                 default=False,
                 description="Whether Allow ungrounded responses (AI general knowledge) is enabled"),
    _boolean_col("fsi_SemanticSearchEnabled", "Work IQ Enabled",
                 default=False,
                 description="Whether Work IQ (semantic search) is enabled"),
    _boolean_col("fsi_IsActive", "Is Active", default=True,
                 description="Current active baseline flag"),
    _datetime_col("fsi_CapturedAt", "Captured At",
                  description="When baseline was captured"),
    _string_col("fsi_CapturedBy", "Captured By", 200, required=False,
                description="UPN of capturing operator"),
    _memo_col("fsi_RawJson", "Raw JSON", 100000,
              description="Full JSON snapshot of generative AI configuration"),
]

HISTORY_COLUMNS = [
    _string_col("fsi_RunId", "Run ID", 36,
                description="GUID correlating all records in one scan run"),
    _datetime_col("fsi_ValidationTime", "Validation Time",
                  description="When scan executed"),
    _integer_col("fsi_TotalAgents", "Total Agents",
                 description="Total agents scanned"),
    _integer_col("fsi_CompliantCount", "Compliant Count",
                 description="Agents passing generative AI config checks"),
    _integer_col("fsi_ViolationCount", "Violation Count",
                 description="Agents with generative AI config violations"),
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
    _picklist_col("fsi_Zone", "Zone", "fsi_acv_zone",
                  description="Zone classification"),
    _picklist_col("fsi_FeatureType", "Feature Type", "fsi_GAC_genaifeaturetype",
                  description="Type of generative AI feature in violation"),
    _string_col("fsi_ExpectedState", "Expected State", 500,
                description="Zone-required configuration state"),
    _string_col("fsi_ActualState", "Actual State", 500,
                description="Agent's current configuration state"),
    _picklist_col("fsi_ConnectionStatus", "Connection Status",
                  "fsi_GAC_connectionstatus", required=False,
                  description="Azure OpenAI connection approval status"),
    _string_col("fsi_Severity", "Severity", 50,
                description="Violation severity (Critical/High/Medium/Warning)"),
    _string_col("fsi_RegulatoryContext", "Regulatory Context", 2000,
                required=False,
                description="FINRA/SOX/GLBA regulatory impact context"),
    _string_col("fsi_TopicName", "Topic Name", 500,
                required=False,
                description="Name of the topic containing the violation"),
    _string_col("fsi_TopicId", "Topic ID", 100,
                required=False,
                description="GUID of the topic containing the violation"),
    _datetime_col("fsi_DetectedAt", "Detected At",
                  description="When violation was detected"),
    _string_col("fsi_RunId", "Run ID", 36, required=False,
                description="Correlating scan GUID"),
]

APPROVED_CONNECTION_COLUMNS = [
    _string_col("fsi_ConnectionId", "Connection ID", 200,
                description="Power Platform connection reference identifier"),
    _string_col("fsi_ConnectionName", "Connection Name", 500,
                description="Display name of the approved connection"),
    _picklist_col("fsi_Zone", "Zone", "fsi_acv_zone",
                  description="Zone this connection is approved for"),
    _string_col("fsi_ResourceGroup", "Resource Group", 500,
                required=False,
                description="Azure resource group containing the AOAI resource"),
    _string_col("fsi_AoaiEndpoint", "AOAI Endpoint", 1000,
                required=False,
                description="Azure OpenAI endpoint URL"),
    _string_col("fsi_ApprovedBy", "Approved By", 200,
                description="UPN of approving administrator"),
    _datetime_col("fsi_ApprovedAt", "Approved At",
                  description="When connection was approved"),
    _datetime_col("fsi_ExpiresAt", "Expires At", required=False,
                  description="Approval expiration date (optional)"),
    _boolean_col("fsi_IsActive", "Is Active", default=True,
                 description="Whether this approval is currently active"),
    _memo_col("fsi_Notes", "Notes", 5000,
              description="Additional notes or justification for approval"),
]

FEATURE_INVENTORY_COLUMNS = [
    _string_col("fsi_EnvironmentGuid", "Environment GUID", 100,
                description="Power Platform environment GUID"),
    _string_col("fsi_AgentId", "Agent ID", 100,
                description="Copilot Studio bot GUID"),
    _string_col("fsi_AgentName", "Agent Name", 500,
                description="Agent display name"),
    _picklist_col("fsi_Zone", "Zone", "fsi_acv_zone",
                  description="Zone classification"),
    _picklist_col("fsi_FeatureType", "Feature Type", "fsi_GAC_genaifeaturetype",
                  description="Type of generative AI feature"),
    _boolean_col("fsi_FeatureEnabled", "Feature Enabled", default=False,
                 description="Whether this feature is enabled on the agent"),
    _string_col("fsi_FeatureDetail", "Feature Detail", 2000,
                required=False,
                description="Additional detail about feature configuration"),
    _datetime_col("fsi_LastScannedAt", "Last Scanned At",
                  description="When this feature was last scanned"),
    _string_col("fsi_RunId", "Run ID", 36, required=False,
                description="Correlating scan GUID"),
]


# =============================================================================
# Table Definitions
# =============================================================================

TABLES = {
    "fsi_gacbaseline": {
        "schema_name": "fsi_GACBaseline",
        "display": "GAC Baseline",
        "plural": "GAC Baselines",
        "description": (
            "Per-agent generative AI configuration snapshots for "
            "governance comparison and drift detection"
        ),
        "ownership": "UserOwned",
        "columns": BASELINE_COLUMNS,
        "entity_set_name": None,  # Use default auto-generated name
    },
    "fsi_gacvalidationhistory": {
        "schema_name": "fsi_GACValidationHistory",
        "display": "GAC Validation History",
        "plural": "GAC Validation History",
        "description": (
            "Immutable scan summary records for regulatory evidence "
            "(supports compliance with FINRA Rule 4511, SEC Rule 17a-3)"
        ),
        "ownership": "OrganizationOwned",
        "columns": HISTORY_COLUMNS,
        # Explicit EntitySetName avoids auto-plural
        # 'fsi_gacvalidationhistorys'
        "entity_set_name": "fsi_gacvalidationhistory",
    },
    "fsi_gacviolation": {
        "schema_name": "fsi_GACViolation",
        "display": "GAC Violation",
        "plural": "GAC Violations",
        "description": (
            "Per-agent generative AI configuration violations "
            "detected during governance scans"
        ),
        "ownership": "UserOwned",
        "columns": VIOLATION_COLUMNS,
        "entity_set_name": None,
    },
    "fsi_gacapprovedconnection": {
        "schema_name": "fsi_GACApprovedConnection",
        "display": "GAC Approved Connection",
        "plural": "GAC Approved Connections",
        "description": (
            "Approved Azure OpenAI connection whitelist for "
            "zone-based connection governance"
        ),
        "ownership": "UserOwned",
        "columns": APPROVED_CONNECTION_COLUMNS,
        "entity_set_name": None,
    },
    "fsi_gacfeatureinventory": {
        "schema_name": "fsi_GACFeatureInventory",
        "display": "GAC Feature Inventory",
        "plural": "GAC Feature Inventory",
        "description": (
            "Per-agent generative AI feature tracking inventory "
            "for comprehensive capability visibility"
        ),
        "ownership": "UserOwned",
        "columns": FEATURE_INVENTORY_COLUMNS,
        "entity_set_name": None,
    },
}


# =============================================================================
# Metadata Builders for Shared DataverseClient
# =============================================================================
#
# The shared DataverseClient takes raw Dataverse metadata dicts (matching the
# Web API EntityMetadata / OptionSetMetadata payloads). These helpers translate
# the higher-level GAC schema definitions above into the dicts the API expects.

def _build_optionset_metadata(os_def: dict) -> dict:
    """Build OptionSetMetadata dict for a global option set."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.OptionSetMetadata",
        "Name": os_def["name"],
        "DisplayName": _label(os_def["name"]),
        "IsGlobal": True,
        "OptionSetType": "Picklist",
        "Options": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.OptionMetadata",
                "Value": value,
                "Label": _label(label),
            }
            for label, value in os_def["options"]
        ],
    }


def _build_table_metadata(table_def: dict) -> dict:
    """Build EntityMetadata dict (table + primary name attribute) for create_table."""
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
        "# Generative AI Config Auditor - Dataverse Schema",
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
        "### GAC-Specific Option Sets",
        "",
        "| Option Set | Values |",
        "|-----------|--------|",
    ])

    for os_name, os_def in GAC_OPTIONSETS.items():
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


def create_shared_optionsets(client: DataverseClient, dry_run: bool = False) -> None:
    """Create or verify shared global option sets.

    These option sets are shared with ACV and other solutions.
    Existence is checked before creation to support idempotent runs.
    """
    print("\n[Creating/Verifying Shared Option Sets]")

    for os_name, os_def in SHARED_OPTIONSETS.items():
        if dry_run:
            existing = client.get_global_optionset(os_name)
            if existing:
                print(f"  {os_name}: exists, would skip")
            else:
                print(f"  [DRY RUN] {os_name}: would create")
            continue
        result = client.create_option_set(_build_optionset_metadata(os_def))
        if result is None:
            print(f"  {os_name}: already exists, skipping")
        else:
            print(f"  {os_name}: created")


def create_gac_optionsets(client: DataverseClient, dry_run: bool = False) -> None:
    """Create GAC-specific global option sets.

    These option sets are unique to the Generative AI Config Auditor.
    Existence is checked before creation to support idempotent runs.
    """
    print("\n[Creating GAC-Specific Option Sets]")

    for os_name, os_def in GAC_OPTIONSETS.items():
        if dry_run:
            existing = client.get_global_optionset(os_name)
            if existing:
                print(f"  {os_name}: exists, would skip")
            else:
                print(f"  [DRY RUN] {os_name}: would create")
            continue
        result = client.create_option_set(_build_optionset_metadata(os_def))
        if result is None:
            print(f"  {os_name}: already exists, skipping")
        else:
            print(f"  {os_name}: created")


def create_table_with_columns(
    client: DataverseClient,
    table_name: str,
    table_def: dict,
    columns: list[dict],
    dry_run: bool = False,
) -> None:
    """Create a table and its columns (idempotent).

    Args:
        client: DataverseClient instance
        table_name: Logical table name
        table_def: Table definition dict
        columns: List of column definitions
        dry_run: Preview mode flag
    """
    logical_name = table_name.lower()

    # Check if table already exists (read goes against live tenant even in
    # dry-run for accurate preview)
    table_exists = client.check_table_exists(logical_name)
    if table_exists:
        print(f"  {logical_name}: already exists, skipping table creation")
    else:
        if dry_run:
            print(f"  [DRY RUN] {logical_name}: would create table")
        else:
            client.create_table(_build_table_metadata(table_def))
            print(f"  {logical_name}: created")

    # Create columns
    print(f"  {logical_name} columns:")
    for col in columns:
        col_schema = col["SchemaName"]
        col_logical = col_schema.lower()

        if not table_exists and dry_run:
            # Table doesn't exist yet and we're previewing — all columns are new
            print(f"    [DRY RUN] {col_logical}: would create (new table)")
            continue

        existing_col = client.get_attribute_metadata(logical_name, col_logical)
        if existing_col:
            print(f"    {col_logical}: already exists, skipping")
        elif dry_run:
            print(f"    [DRY RUN] {col_logical}: would create")
        else:
            client.create_column(logical_name, col)
            print(f"    {col_logical}: created")


def create_schema(client: DataverseClient, dry_run: bool = False) -> None:
    """Orchestrate full schema deployment.

    Order: shared option sets → GAC option sets → tables → columns.
    All operations are idempotent — safe to re-run.
    """
    print("=" * 60)
    print("GAC Dataverse Schema Deployment")
    print("  Generative AI Config Auditor")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN - No changes will be made ***\n")

    # Step 1: Shared option sets (must exist before tables reference them)
    create_shared_optionsets(client, dry_run)

    # Step 2: GAC-specific option sets
    create_gac_optionsets(client, dry_run)

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
    print(f"  GAC option sets: {len(GAC_OPTIONSETS)}")
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
        description="Create Dataverse schema for Generative AI Config Auditor",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Dry run with interactive auth\n"
            "  python create_dataverse_schema.py --dry-run --interactive\n\n"
            "  # Deploy with service principal\n"
            "  python create_dataverse_schema.py \\\n"
            "    --tenant-id $GAC_TENANT_ID \\\n"
            "    --client-id $GAC_CLIENT_ID \\\n"
            "    --client-secret $GAC_CLIENT_SECRET \\\n"
            "    --environment-url $GAC_ENVIRONMENT_URL\n\n"
            "  # Generate schema documentation only\n"
            "  python create_dataverse_schema.py --output-docs\n"
        ),
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("GAC_TENANT_ID"),
        help="Microsoft Entra ID tenant ID (or set GAC_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("GAC_CLIENT_ID"),
        help="Service principal app ID (or set GAC_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("GAC_CLIENT_SECRET"),
        help="Service principal secret (or set GAC_CLIENT_SECRET env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("GAC_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set GAC_ENVIRONMENT_URL env var)",
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
        print("ERROR: --tenant-id or GAC_TENANT_ID required")
        sys.exit(1)
    if not args.environment_url:
        print("ERROR: --environment-url or GAC_ENVIRONMENT_URL required")
        sys.exit(1)

    try:
        # NOTE: We deliberately do NOT pass dry_run to DataverseClient: the
        # shared client short-circuits reads in dry-run mode, which would
        # defeat a meaningful preview. Instead, we gate all writes locally
        # in create_schema(). The client itself is constructed live for both
        # --dry-run and live executions.
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
