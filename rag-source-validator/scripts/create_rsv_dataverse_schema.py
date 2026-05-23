#!/usr/bin/env python3
"""Create Dataverse schema for RAG Source Validator.

Deploys three tables with solution-specific option sets for knowledge source
integrity validation, change detection, and validation history.

Tables:
  - fsi_KnowledgeSource (UserOwned): Source registry with hash baselines
  - fsi_ValidationResult (OrganizationOwned): Immutable validation history
  - fsi_SourceChange (UserOwned): Change tracking with review workflow
"""

import argparse
import os
import sys
from typing import Optional

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared")
)
from dataverse_client import DataverseClient

PUBLISHER_PREFIX = "fsi"

# ---------------------------------------------------------------------------
# RSV option sets
# ---------------------------------------------------------------------------
OPTIONSETS = {
    "fsi_RSV_sourcetype": {
        "Name": "fsi_RSV_sourcetype",
        "DisplayName": {"LocalizedLabels": [{"Label": "Source Type", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Type of RAG knowledge source", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "SharePoint Document Library", "LanguageCode": 1033}]}},
            {"Value": 2, "Label": {"LocalizedLabels": [{"Label": "SharePoint List", "LanguageCode": 1033}]}},
            {"Value": 3, "Label": {"LocalizedLabels": [{"Label": "SharePoint Page", "LanguageCode": 1033}]}},
            {"Value": 4, "Label": {"LocalizedLabels": [{"Label": "Dataverse Table", "LanguageCode": 1033}]}},
            {"Value": 5, "Label": {"LocalizedLabels": [{"Label": "Azure Blob Container", "LanguageCode": 1033}]}},
            {"Value": 6, "Label": {"LocalizedLabels": [{"Label": "Azure Blob File", "LanguageCode": 1033}]}},
            {"Value": 7, "Label": {"LocalizedLabels": [{"Label": "External API", "LanguageCode": 1033}]}},
            {"Value": 8, "Label": {"LocalizedLabels": [{"Label": "Database Query", "LanguageCode": 1033}]}},
            {"Value": 9, "Label": {"LocalizedLabels": [{"Label": "Public Website", "LanguageCode": 1033}]}},
            {"Value": 10, "Label": {"LocalizedLabels": [{"Label": "OneDrive File or Folder", "LanguageCode": 1033}]}},
            {"Value": 11, "Label": {"LocalizedLabels": [{"Label": "Microsoft 365 Copilot Connector External Item", "LanguageCode": 1033}]}},
            {"Value": 12, "Label": {"LocalizedLabels": [{"Label": "Azure AI Search Index", "LanguageCode": 1033}]}},
            {"Value": 13, "Label": {"LocalizedLabels": [{"Label": "Copilot Studio Uploaded Document", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_RSV_sourcestatus": {
        "Name": "fsi_RSV_sourcestatus",
        "DisplayName": {"LocalizedLabels": [{"Label": "Source Status", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Current status of the knowledge source", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Active", "LanguageCode": 1033}]}},
            {"Value": 2, "Label": {"LocalizedLabels": [{"Label": "Pending Validation", "LanguageCode": 1033}]}},
            {"Value": 3, "Label": {"LocalizedLabels": [{"Label": "Validation Failed", "LanguageCode": 1033}]}},
            {"Value": 4, "Label": {"LocalizedLabels": [{"Label": "Stale", "LanguageCode": 1033}]}},
            {"Value": 5, "Label": {"LocalizedLabels": [{"Label": "Archived", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_RSV_validationfrequency": {
        "Name": "fsi_RSV_validationfrequency",
        "DisplayName": {"LocalizedLabels": [{"Label": "Validation Frequency", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "How often the source is validated", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Realtime", "LanguageCode": 1033}]}},
            {"Value": 2, "Label": {"LocalizedLabels": [{"Label": "Hourly", "LanguageCode": 1033}]}},
            {"Value": 3, "Label": {"LocalizedLabels": [{"Label": "Daily", "LanguageCode": 1033}]}},
            {"Value": 4, "Label": {"LocalizedLabels": [{"Label": "Weekly", "LanguageCode": 1033}]}},
            {"Value": 5, "Label": {"LocalizedLabels": [{"Label": "Monthly", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_RSV_validationresult": {
        "Name": "fsi_RSV_validationresult",
        "DisplayName": {"LocalizedLabels": [{"Label": "Validation Result", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Outcome of a source validation run", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Passed", "LanguageCode": 1033}]}},
            {"Value": 2, "Label": {"LocalizedLabels": [{"Label": "Hash Mismatch", "LanguageCode": 1033}]}},
            {"Value": 3, "Label": {"LocalizedLabels": [{"Label": "Schema Drift", "LanguageCode": 1033}]}},
            {"Value": 4, "Label": {"LocalizedLabels": [{"Label": "Stale Content", "LanguageCode": 1033}]}},
            {"Value": 5, "Label": {"LocalizedLabels": [{"Label": "Source Unavailable", "LanguageCode": 1033}]}},
            {"Value": 6, "Label": {"LocalizedLabels": [{"Label": "Unexpected Error", "LanguageCode": 1033}]}},
            {"Value": 7, "Label": {"LocalizedLabels": [{"Label": "Skipped - Not Implemented", "LanguageCode": 1033}]}},
            {"Value": 8, "Label": {"LocalizedLabels": [{"Label": "Skipped - Unsupported Type", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_RSV_validationtype": {
        "Name": "fsi_RSV_validationtype",
        "DisplayName": {"LocalizedLabels": [{"Label": "Validation Type", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "How the validation was triggered", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Scheduled", "LanguageCode": 1033}]}},
            {"Value": 2, "Label": {"LocalizedLabels": [{"Label": "On-Demand", "LanguageCode": 1033}]}},
            {"Value": 3, "Label": {"LocalizedLabels": [{"Label": "Webhook Triggered", "LanguageCode": 1033}]}},
            {"Value": 4, "Label": {"LocalizedLabels": [{"Label": "Baseline Capture", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_RSV_changetype": {
        "Name": "fsi_RSV_changetype",
        "DisplayName": {"LocalizedLabels": [{"Label": "Change Type", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Type of change detected on a knowledge source", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Content Modified", "LanguageCode": 1033}]}},
            {"Value": 2, "Label": {"LocalizedLabels": [{"Label": "Schema Changed", "LanguageCode": 1033}]}},
            {"Value": 3, "Label": {"LocalizedLabels": [{"Label": "Source Moved", "LanguageCode": 1033}]}},
            {"Value": 4, "Label": {"LocalizedLabels": [{"Label": "Source Deleted", "LanguageCode": 1033}]}},
            {"Value": 5, "Label": {"LocalizedLabels": [{"Label": "Permissions Changed", "LanguageCode": 1033}]}},
            {"Value": 6, "Label": {"LocalizedLabels": [{"Label": "New Content Added", "LanguageCode": 1033}]}},
        ],
    },
}

# ---------------------------------------------------------------------------
# Helper functions for column definitions
# ---------------------------------------------------------------------------


def _label(text: str) -> dict:
    """Create a Dataverse label structure from a plain string."""
    return {"LocalizedLabels": [{"Label": text, "LanguageCode": 1033}]}


def _string_col(schema_name: str, display: str, max_length: int = 200,
                required: bool = False, description: str = "",
                format_name: str = "Text") -> dict:
    """Build a StringAttributeMetadata definition."""
    defn = {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "ApplicationRequired" if required else "None"},
        "MaxLength": max_length,
        "FormatName": {"Value": format_name},
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _memo_col(schema_name: str, display: str, max_length: int = 100000,
              required: bool = False, description: str = "") -> dict:
    """Build a MemoAttributeMetadata definition."""
    defn = {
        "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "ApplicationRequired" if required else "None"},
        "MaxLength": max_length,
        "Format": "Text",
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _picklist_col(schema_name: str, display: str, optionset_name: str,
                  required: bool = False, description: str = "") -> dict:
    """Build a PicklistAttributeMetadata definition bound to a global option set."""
    defn = {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "ApplicationRequired" if required else "None"},
        "GlobalOptionSet@odata.bind": f"/GlobalOptionSetDefinitions(Name='{optionset_name}')",
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _bool_col(schema_name: str, display: str, default: bool = False,
              required: bool = False, description: str = "") -> dict:
    """Build a BooleanAttributeMetadata definition."""
    defn = {
        "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "ApplicationRequired" if required else "None"},
        "DefaultValue": default,
        "OptionSet": {
            "TrueOption": {"Value": 1, "Label": _label("Yes")},
            "FalseOption": {"Value": 0, "Label": _label("No")},
        },
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _datetime_col(schema_name: str, display: str, required: bool = False,
                  description: str = "") -> dict:
    """Build a DateTimeAttributeMetadata definition."""
    defn = {
        "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "ApplicationRequired" if required else "None"},
        "Format": "DateAndTime",
        "DateTimeBehavior": {"Value": "UserLocal"},
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _int_col(schema_name: str, display: str, required: bool = False,
             description: str = "", min_val: int = 0,
             max_val: int = 2147483647) -> dict:
    """Build an IntegerAttributeMetadata definition."""
    defn = {
        "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "ApplicationRequired" if required else "None"},
        "MinValue": min_val,
        "MaxValue": max_val,
        "Format": "None",
    }
    if description:
        defn["Description"] = _label(description)
    return defn


# ---------------------------------------------------------------------------
# Table definitions
# ---------------------------------------------------------------------------
TABLES = {
    # ── Table 1: fsi_KnowledgeSource — Source registry ──────────────────
    "fsi_KnowledgeSource": {
        "SchemaName": "fsi_KnowledgeSource",
        "DisplayName": _label("Knowledge Source"),
        "DisplayCollectionName": _label("Knowledge Sources"),
        "Description": _label("RAG knowledge source registry with hash baselines and validation settings"),
        "OwnershipType": "UserOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            _string_col(f"{PUBLISHER_PREFIX}_SourceName", "Source Name",
                        max_length=200, required=True,
                        description="Display name of the knowledge source"),
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_sourcename",
    },
    # ── Table 2: fsi_ValidationResult — Immutable validation history ────
    "fsi_ValidationResult": {
        "SchemaName": "fsi_ValidationResult",
        "DisplayName": _label("Validation Result"),
        "DisplayCollectionName": _label("Validation Results"),
        "Description": _label("Immutable validation history for RAG knowledge sources"),
        "OwnershipType": "OrganizationOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            _string_col(f"{PUBLISHER_PREFIX}_ResultName", "Result Name",
                        max_length=200, required=True,
                        description="Auto-generated validation result identifier"),
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_resultname",
    },
    # ── Table 3: fsi_SourceChange — Change tracking ─────────────────────
    "fsi_SourceChange": {
        "SchemaName": "fsi_SourceChange",
        "DisplayName": _label("Source Change"),
        "DisplayCollectionName": _label("Source Changes"),
        "Description": _label("Change tracking for RAG knowledge sources with review workflow"),
        "OwnershipType": "UserOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            _string_col(f"{PUBLISHER_PREFIX}_ChangeName", "Change Name",
                        max_length=200, required=True,
                        description="Auto-generated change record identifier"),
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_changename",
    },
}

# ---------------------------------------------------------------------------
# Column definitions (added after table creation)
# ---------------------------------------------------------------------------
COLUMNS = {
    # ── fsi_knowledgesource ─────────────────────────────────────────────
    "fsi_knowledgesource": [
        _picklist_col(f"{PUBLISHER_PREFIX}_SourceType", "Source Type",
                      "fsi_RSV_sourcetype", required=True),
        _string_col(f"{PUBLISHER_PREFIX}_SourceUri", "Source URI",
                    max_length=500, required=True,
                    description="Full URI of the knowledge source"),
        _string_col(f"{PUBLISHER_PREFIX}_AgentId", "Agent ID",
                    max_length=36, required=True,
                    description="Power Platform Bot ID referencing this source"),
        _memo_col(f"{PUBLISHER_PREFIX}_Description", "Description",
                  description="Detailed description of the knowledge source"),
        _string_col(f"{PUBLISHER_PREFIX}_CurrentHash", "Current Hash",
                    max_length=64,
                    description="SHA-256 hash of current source content"),
        _string_col(f"{PUBLISHER_PREFIX}_BaselineHash", "Baseline Hash",
                    max_length=64,
                    description="SHA-256 hash captured at baseline"),
        _picklist_col(f"{PUBLISHER_PREFIX}_Status", "Status",
                      "fsi_RSV_sourcestatus"),
        _datetime_col(f"{PUBLISHER_PREFIX}_LastValidated", "Last Validated",
                      description="Timestamp of last successful validation"),
        _picklist_col(f"{PUBLISHER_PREFIX}_ValidationFrequency", "Validation Frequency",
                      "fsi_RSV_validationfrequency"),
        _bool_col(f"{PUBLISHER_PREFIX}_AlertOnChange", "Alert on Change",
                  default=True,
                  description="Send notification when source content changes"),
        _int_col(f"{PUBLISHER_PREFIX}_FreshnessThreshold", "Freshness Threshold",
                 description="Maximum acceptable age in days before source is considered stale",
                 min_val=0, max_val=365),
        _datetime_col(f"{PUBLISHER_PREFIX}_LastModified", "Last Modified",
                      description="Timestamp of last detected source modification"),
        # ── Change detection and provenance columns (H5) ───────────────
        _string_col(f"{PUBLISHER_PREFIX}_eTag", "eTag",
                    max_length=255,
                    description="Document eTag from SharePoint/OneDrive for change detection"),
        _string_col(f"{PUBLISHER_PREFIX}_cTag", "cTag",
                    max_length=255,
                    description="Document cTag from SharePoint/OneDrive (catalog tag)"),
        _string_col(f"{PUBLISHER_PREFIX}_DeltaLink", "Delta Link",
                    max_length=2048, format_name="Url",
                    description="Microsoft Graph delta query link for incremental change tracking"),
        _string_col(f"{PUBLISHER_PREFIX}_SearchConnectorId", "Search Connector ID",
                    max_length=100,
                    description="Microsoft Search connector identifier"),
        _string_col(f"{PUBLISHER_PREFIX}_LineageUri", "Lineage URI",
                    max_length=2048, format_name="Url",
                    description="Source lineage URI for RAG provenance tracking"),
    ],

    # ── fsi_validationresult ────────────────────────────────────────────
    "fsi_validationresult": [
        _datetime_col(f"{PUBLISHER_PREFIX}_ValidationTime", "Validation Time",
                      required=True,
                      description="Timestamp when validation was performed"),
        _picklist_col(f"{PUBLISHER_PREFIX}_Result", "Result",
                      "fsi_RSV_validationresult", required=True),
        _string_col(f"{PUBLISHER_PREFIX}_PreviousHash", "Previous Hash",
                    max_length=64,
                    description="SHA-256 hash before this validation"),
        _string_col(f"{PUBLISHER_PREFIX}_CurrentHash", "Current Hash",
                    max_length=64,
                    description="SHA-256 hash at validation time"),
        _bool_col(f"{PUBLISHER_PREFIX}_HashChanged", "Hash Changed",
                  default=False,
                  description="Whether source hash changed since last validation"),
        _memo_col(f"{PUBLISHER_PREFIX}_ChangeDetails", "Change Details",
                  description="Human-readable description of detected changes"),
        _picklist_col(f"{PUBLISHER_PREFIX}_ValidationType", "Validation Type",
                      "fsi_RSV_validationtype"),
        _int_col(f"{PUBLISHER_PREFIX}_Duration", "Duration",
                 description="Validation duration in milliseconds",
                 min_val=0, max_val=2147483647),
        _memo_col(f"{PUBLISHER_PREFIX}_ErrorDetails", "Error Details",
                  description="Error stack trace or message when validation fails"),
    ],

    # ── fsi_sourcechange ────────────────────────────────────────────────
    "fsi_sourcechange": [
        _picklist_col(f"{PUBLISHER_PREFIX}_ChangeType", "Change Type",
                      "fsi_RSV_changetype", required=True),
        _datetime_col(f"{PUBLISHER_PREFIX}_DetectedOn", "Detected On",
                      required=True,
                      description="Timestamp when the change was detected"),
        _memo_col(f"{PUBLISHER_PREFIX}_PreviousValue", "Previous Value",
                  description="Content or metadata value before the change"),
        _memo_col(f"{PUBLISHER_PREFIX}_NewValue", "New Value",
                  description="Content or metadata value after the change"),
        _string_col(f"{PUBLISHER_PREFIX}_ChangedBy", "Changed By",
                    max_length=200,
                    description="UPN or identity that made the change"),
        _bool_col(f"{PUBLISHER_PREFIX}_Reviewed", "Reviewed",
                  default=False,
                  description="Whether the change has been reviewed"),
        _string_col(f"{PUBLISHER_PREFIX}_ReviewedBy", "Reviewed By",
                    max_length=200,
                    description="UPN of the reviewer"),
        _datetime_col(f"{PUBLISHER_PREFIX}_ReviewedOn", "Reviewed On",
                      description="Timestamp when the change was reviewed"),
        _bool_col(f"{PUBLISHER_PREFIX}_Approved", "Approved",
                  description="Whether the reviewed change was approved"),
    ],
}

# ---------------------------------------------------------------------------
# Relationships
# ---------------------------------------------------------------------------
RELATIONSHIPS = [
    {
        "@odata.type": "#Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata",
        "SchemaName": f"{PUBLISHER_PREFIX}_ValidationResult_KnowledgeSource",
        "ReferencedEntity": "fsi_knowledgesource",
        "ReferencingEntity": "fsi_validationresult",
        "CascadeConfiguration": {
            "Assign": "NoCascade",
            "Delete": "RemoveLink",
            "Merge": "NoCascade",
            "Reparent": "NoCascade",
            "Share": "NoCascade",
            "Unshare": "NoCascade",
        },
        "Lookup": {
            "SchemaName": f"{PUBLISHER_PREFIX}_KnowledgeSourceId",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": _label("Knowledge Source"),
            "Description": _label("Parent knowledge source for this validation result"),
        },
    },
    {
        "@odata.type": "#Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata",
        "SchemaName": f"{PUBLISHER_PREFIX}_SourceChange_KnowledgeSource",
        "ReferencedEntity": "fsi_knowledgesource",
        "ReferencingEntity": "fsi_sourcechange",
        "CascadeConfiguration": {
            "Assign": "NoCascade",
            "Delete": "RemoveLink",
            "Merge": "NoCascade",
            "Reparent": "NoCascade",
            "Share": "NoCascade",
            "Unshare": "NoCascade",
        },
        "Lookup": {
            "SchemaName": f"{PUBLISHER_PREFIX}_KnowledgeSourceId",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": _label("Knowledge Source"),
            "Description": _label("Parent knowledge source for this change record"),
        },
    },
]


# ---------------------------------------------------------------------------
# Documentation helpers
# ---------------------------------------------------------------------------


def _label_text(obj: dict) -> str:
    """Extract the English label string from a Dataverse LocalizedLabels structure."""
    labels = obj.get("LocalizedLabels", [])
    for lbl in labels:
        if lbl.get("LanguageCode") == 1033:
            return lbl.get("Label", "")
    return labels[0].get("Label", "") if labels else ""


def _col_type(col: dict) -> str:
    """Return a human-friendly column type from the @odata.type."""
    odata = col.get("@odata.type", "")
    mapping = {
        "Microsoft.Dynamics.CRM.StringAttributeMetadata": "String",
        "Microsoft.Dynamics.CRM.MemoAttributeMetadata": "Memo",
        "Microsoft.Dynamics.CRM.PicklistAttributeMetadata": "Picklist",
        "Microsoft.Dynamics.CRM.BooleanAttributeMetadata": "Boolean",
        "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata": "DateTime",
        "Microsoft.Dynamics.CRM.IntegerAttributeMetadata": "Integer",
        "Microsoft.Dynamics.CRM.DecimalAttributeMetadata": "Decimal",
        "Microsoft.Dynamics.CRM.LookupAttributeMetadata": "Lookup",
    }
    return mapping.get(odata, odata.split(".")[-1] if odata else "Unknown")


def _optionset_name_from_bind(col: dict) -> Optional[str]:
    """Extract the global option-set name from a GlobalOptionSet@odata.bind value."""
    bind = col.get("GlobalOptionSet@odata.bind", "")
    if "Name='" in bind:
        return bind.split("Name='")[1].rstrip("')")
    return None


def _resolve_optionset(name: str) -> Optional[dict]:
    """Look up an option set by name in OPTIONSETS."""
    return OPTIONSETS.get(name)


def _format_option_values(options: list) -> str:
    """Return a compact string of value/label pairs for an option set."""
    parts = []
    for opt in options:
        val = opt.get("Value", "")
        lbl = _label_text(opt.get("Label", {}))
        parts.append(f"`{val}` = {lbl}")
    return ", ".join(parts)


def generate_schema_docs() -> str:
    """Generate a Markdown reference document from the in-memory schema definitions."""
    lines: list[str] = []

    # ── Header ──────────────────────────────────────────────────────────
    lines.append("# Dataverse Schema Reference")
    lines.append("")
    lines.append("> Auto-generated from `create_rsv_dataverse_schema.py`. Do not edit manually.")
    lines.append("")

    # ── Tables ──────────────────────────────────────────────────────────
    lines.append("## Tables")
    lines.append("")
    lines.append("| SchemaName | Logical Name | Description | Ownership | Primary Name Attribute |")
    lines.append("|---|---|---|---|---|")
    for schema_name, tbl in TABLES.items():
        logical = schema_name.lower()
        desc = _label_text(tbl.get("Description", {}))
        ownership = tbl.get("OwnershipType", "")
        pna = tbl.get("PrimaryNameAttribute", "")
        lines.append(f"| {schema_name} | {logical} | {desc} | {ownership} | {pna} |")
    lines.append("")

    # ── Columns (per table) ─────────────────────────────────────────────
    lines.append("## Columns")
    lines.append("")

    for table_schema_name, tbl in TABLES.items():
        table_logical = table_schema_name.lower()
        primary_attrs = tbl.get("Attributes", [])
        extra_cols = COLUMNS.get(table_logical, [])
        all_cols = primary_attrs + extra_cols

        lines.append(f"### {table_schema_name} (`{table_logical}`)")
        lines.append("")
        lines.append("| SchemaName | Logical Name | Type | Required | Description | Option Set |")
        lines.append("|---|---|---|---|---|---|")

        for col in all_cols:
            sn = col.get("SchemaName", "")
            ln = sn.lower()
            ctype = _col_type(col)
            req_val = col.get("RequiredLevel", {}).get("Value", "None")
            required = "Yes" if req_val == "ApplicationRequired" else "No"
            desc = _label_text(col.get("Description", {}))

            os_cell = ""
            os_name = _optionset_name_from_bind(col)
            if os_name:
                os_def = _resolve_optionset(os_name)
                if os_def:
                    os_cell = f"**{os_name}**: {_format_option_values(os_def.get('Options', []))}"
                else:
                    os_cell = os_name
            elif ctype == "Boolean":
                opt = col.get("OptionSet", {})
                true_lbl = _label_text(opt.get("TrueOption", {}).get("Label", {})) if opt.get("TrueOption") else "Yes"
                false_lbl = _label_text(opt.get("FalseOption", {}).get("Label", {})) if opt.get("FalseOption") else "No"
                os_cell = f"`1` = {true_lbl}, `0` = {false_lbl}"

            lines.append(f"| {sn} | {ln} | {ctype} | {required} | {desc} | {os_cell} |")

        lines.append("")

    # ── Option Sets ─────────────────────────────────────────────────────
    lines.append("## Option Sets")
    lines.append("")

    lines.append("### RSV Option Sets")
    lines.append("")
    for name, osdef in OPTIONSETS.items():
        desc = _label_text(osdef.get("Description", {}))
        lines.append(f"#### {name}")
        lines.append("")
        lines.append(f"{desc}")
        lines.append("")
        lines.append("| Value | Label |")
        lines.append("|---|---|")
        for opt in osdef.get("Options", []):
            lines.append(f"| {opt['Value']} | {_label_text(opt['Label'])} |")
        lines.append("")

    # ── Relationships ───────────────────────────────────────────────────
    lines.append("## Relationships")
    lines.append("")
    lines.append("| SchemaName | Parent (Referenced) | Child (Referencing) | Lookup Column |")
    lines.append("|---|---|---|---|")
    for rel in RELATIONSHIPS:
        sn = rel.get("SchemaName", "")
        parent = rel.get("ReferencedEntity", "")
        child = rel.get("ReferencingEntity", "")
        lookup_sn = rel.get("Lookup", {}).get("SchemaName", "")
        lines.append(f"| {sn} | {parent} | {child} | {lookup_sn} |")
    lines.append("")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Deployment functions
# ---------------------------------------------------------------------------


def create_optionsets(client: DataverseClient, dry_run: bool) -> dict:
    """Create global option sets."""
    print("\n=== Creating Option Sets ===")
    created = 0
    skipped = 0

    for name, metadata in OPTIONSETS.items():
        if client.get_global_optionset(name):
            print(f"  {name}: Already exists")
            skipped += 1
        else:
            print(f"  {name}: Creating")
            client.create_global_optionset(metadata)
            created += 1

    return {"created": created, "skipped": skipped}


def create_tables(client: DataverseClient, dry_run: bool) -> dict:
    """Create tables."""
    print("\n=== Creating Tables ===")
    created = 0
    skipped = 0
    for table_name, metadata in TABLES.items():
        logical_name = table_name.lower()
        if client.check_table_exists(logical_name):
            print(f"  {table_name}: Already exists")
            skipped += 1
        else:
            print(f"  {table_name}: Creating")
            client.create_entity(metadata)
            created += 1
    return {"created": created, "skipped": skipped}


def create_columns(client: DataverseClient, dry_run: bool) -> None:
    """Create columns on tables."""
    print("\n=== Creating Columns ===")
    for table_logical_name, columns in COLUMNS.items():
        print(f"\n{table_logical_name}:")
        for column_metadata in columns:
            schema_name = column_metadata.get("SchemaName", "")
            col_logical_name = schema_name.lower()
            if client.get_attribute_metadata(table_logical_name, col_logical_name):
                print(f"  {schema_name}: Already exists")
            else:
                print(f"  {schema_name}: Creating")
                client.create_attribute(table_logical_name, column_metadata)


def create_relationships(client: DataverseClient, dry_run: bool) -> dict:
    """Create one-to-many relationships (lookup columns)."""
    print("\n=== Creating Relationships ===")
    created = 0
    skipped = 0
    for rel_metadata in RELATIONSHIPS:
        schema_name = rel_metadata.get("SchemaName", "")
        if client.get_relationship(schema_name):
            print(f"  {schema_name}: Already exists")
            skipped += 1
        else:
            print(f"  {schema_name}: Creating")
            if not dry_run:
                client.create_relationship(rel_metadata)
            created += 1
    return {"created": created, "skipped": skipped}


def create_schema(client: DataverseClient, dry_run: bool) -> dict:
    """Create complete schema (orchestrator)."""
    option_set_results = create_optionsets(client, dry_run)
    table_results = create_tables(client, dry_run)
    create_columns(client, dry_run)
    relationship_results = create_relationships(client, dry_run)
    print("\n=== Schema Creation Complete ===")
    return {
        "errors": 0,
        "option_sets": option_set_results,
        "tables": table_results,
        "relationships": relationship_results,
    }


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create Dataverse schema for RAG Source Validator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--tenant-id", default=os.environ.get("RSV_TENANT_ID"),
                        help="Entra ID tenant ID (or set RSV_TENANT_ID env var)")
    parser.add_argument("--client-id", default=os.environ.get("RSV_CLIENT_ID"),
                        help="Application/client ID for user-assigned managed identity, workload identity, certificate, or legacy client-secret auth (or set RSV_CLIENT_ID env var)")
    parser.add_argument("--client-secret", default=os.environ.get("RSV_CLIENT_SECRET"),
                        help="Client secret (legacy dev-only; prefer managed identity, workload identity, or certificate)")
    parser.add_argument("--environment-url", default=os.environ.get("RSV_ENVIRONMENT_URL"),
                        help="Dataverse environment URL (or set RSV_ENVIRONMENT_URL env var)")
    parser.add_argument("--interactive", action="store_true",
                        help="Use interactive browser authentication")
    parser.add_argument("--auth-mode",
                        choices=["interactive", "managed-identity", "workload-identity", "certificate", "client-secret"],
                        default=os.environ.get("RSV_AUTH_MODE"),
                        help="Authentication mode; prefer managed-identity, workload-identity, or certificate for automation")
    parser.add_argument("--access-token", default=os.environ.get("RSV_ACCESS_TOKEN"),
                        help="Externally acquired Dataverse bearer token; takes precedence over other auth modes")
    parser.add_argument("--certificate-path", default=os.environ.get("RSV_CERTIFICATE_PATH"),
                        help="PEM/PFX certificate path for certificate authentication")
    parser.add_argument("--certificate-password-env", default="RSV_CERTIFICATE_PASSWORD",
                        help="Environment variable name containing the certificate password")
    parser.add_argument("--dry-run", action="store_true",
                        help="Preview schema operations without API calls")
    parser.add_argument("--output-docs", action="store_true",
                        help="Generate docs/dataverse-schema.md and exit (no credentials required)")
    args = parser.parse_args()

    # --output-docs: generate schema reference docs and exit immediately
    if args.output_docs:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        solution_root = os.path.dirname(script_dir)
        docs_dir = os.path.join(solution_root, "docs")
        os.makedirs(docs_dir, exist_ok=True)
        out_path = os.path.join(docs_dir, "dataverse-schema.md")
        md = generate_schema_docs()
        with open(out_path, "w", encoding="utf-8") as fh:
            fh.write(md)
        print(f"Schema docs written to {out_path}")
        sys.exit(0)

    if not args.environment_url:
        parser.error(
            "Missing required argument. Provide --environment-url "
            "(or set RSV_ENVIRONMENT_URL env var)"
        )
    if not args.access_token and not args.tenant_id:
        parser.error("--tenant-id is required unless --access-token is provided (or set RSV_TENANT_ID)")

    client_secret = args.client_secret
    auth_mode = "interactive" if args.interactive else (
        args.auth_mode or ("client-secret" if client_secret else "managed-identity")
    )
    if not args.access_token and auth_mode in {"interactive", "workload-identity", "certificate", "client-secret"} and not args.client_id:
        parser.error("--client-id is required for the selected auth mode (or set RSV_CLIENT_ID env var)")

    # legacy: dev-only -- replace with managed identity, workload identity federation, or certificate auth in production
    if not args.access_token and auth_mode == "client-secret" and not client_secret:
        import getpass
        client_secret = getpass.getpass("Client secret: ")

    certificate_password = os.environ.get(args.certificate_password_env) if args.certificate_password_env else None

    try:
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            access_token=args.access_token,
            interactive=args.interactive,
            auth_mode=auth_mode,
            certificate_path=args.certificate_path,
            certificate_password=certificate_password,
        )
        client.dry_run = args.dry_run

        if args.dry_run:
            print("=== DRY RUN MODE - No changes will be made ===")

        create_schema(client, args.dry_run)

        if not args.dry_run:
            print("\nSchema deployment: SUCCESS")

        sys.exit(0)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(1)


if __name__ == "__main__":
    main()
