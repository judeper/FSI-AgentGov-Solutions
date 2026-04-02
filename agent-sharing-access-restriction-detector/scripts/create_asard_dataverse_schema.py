#!/usr/bin/env python3
"""
Create Dataverse schema for Agent Sharing Access Restriction Detector.

Creates AgentSharingCompliance and ApprovedSecurityGroupPolicy tables with all
columns, choice fields, and supporting option sets. Reuses shared ACV option set
(fsi_acv_zone) when present.

Deployment order: option sets → tables → columns.
"""

import argparse
import os
import sys
from typing import Optional

import requests

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"))
from dataverse_client import DataverseClient

PUBLISHER_PREFIX = "fsi"

# ---------------------------------------------------------------------------
# Shared option sets (reused from ACV) — only create if missing
# ---------------------------------------------------------------------------
SHARED_OPTIONSETS = {
    "fsi_acv_zone": {
        "Name": "fsi_acv_zone",
        "DisplayName": {"LocalizedLabels": [{"Label": "Governance Zone", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Governance zone classification", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "Unclassified", "LanguageCode": 1033}]}},
            {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Zone 1", "LanguageCode": 1033}]}},
            {"Value": 2, "Label": {"LocalizedLabels": [{"Label": "Zone 2", "LanguageCode": 1033}]}},
            {"Value": 3, "Label": {"LocalizedLabels": [{"Label": "Zone 3", "LanguageCode": 1033}]}},
        ],
    },
}

# ---------------------------------------------------------------------------
# ASARD-specific option sets
# ---------------------------------------------------------------------------
OPTIONSETS = {
    "fsi_ASARD_compliancestatus": {
        "Name": "fsi_ASARD_compliancestatus",
        "DisplayName": {"LocalizedLabels": [{"Label": "Compliance Status", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Compliance status of agent sharing configuration", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Compliant", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "NonCompliant", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Exception", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Error", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_ASARD_remediationstatus": {
        "Name": "fsi_ASARD_remediationstatus",
        "DisplayName": {"LocalizedLabels": [{"Label": "Remediation Status", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Status of sharing remediation action", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Pending", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Approved", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Rejected", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Completed", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "Failed", "LanguageCode": 1033}]}},
        ],
    },
}

# ---------------------------------------------------------------------------
# Table definitions
# ---------------------------------------------------------------------------
TABLES = {
    "fsi_AgentSharingCompliance": {
        "SchemaName": "fsi_AgentSharingCompliance",
        "DisplayName": {"LocalizedLabels": [{"Label": "Agent Sharing Compliance", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Agent Sharing Compliance Records", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Zone-based agent sharing compliance assessment records", "LanguageCode": 1033}]},
        "OwnershipType": "UserOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": f"{PUBLISHER_PREFIX}_ComplianceId",
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "DisplayName": {"LocalizedLabels": [{"Label": "Compliance ID", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Unique compliance assessment identifier", "LanguageCode": 1033}]},
                "MaxLength": 100,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_complianceid",
    },
    "fsi_ApprovedSecurityGroupPolicy": {
        "SchemaName": "fsi_ApprovedSecurityGroupPolicy",
        "DisplayName": {"LocalizedLabels": [{"Label": "Approved Security Group Policy", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Approved Security Group Policies", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Pre-approved security group policies for agent sharing by zone", "LanguageCode": 1033}]},
        "OwnershipType": "OrganizationOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": f"{PUBLISHER_PREFIX}_PolicyName",
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "DisplayName": {"LocalizedLabels": [{"Label": "Policy Name", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Approved security group policy name", "LanguageCode": 1033}]},
                "MaxLength": 200,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_policyname",
    },
}

# ---------------------------------------------------------------------------
# Column definitions for each table (keyed by logical table name)
# ---------------------------------------------------------------------------
COLUMNS = {
    "fsi_agentsharingcompliance": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AgentId",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Agent ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Unique identifier of the agent", "LanguageCode": 1033}]},
            "MaxLength": 100,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AgentName",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Agent Name", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Display name of the agent", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EnvironmentId",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Environment ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Power Platform environment identifier", "LanguageCode": 1033}]},
            "MaxLength": 100,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EnvironmentName",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Environment Name", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Display name of the environment", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Zone",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Zone", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Governance zone classification", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_zone')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ComplianceStatus",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Compliance Status", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Compliance status of agent sharing configuration", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_ASARD_compliancestatus')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_CurrentSharingPrincipals",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Current Sharing Principals", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "JSON array of current sharing principals", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ApprovedSharingPrincipals",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Approved Sharing Principals", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "JSON array of approved sharing principals", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ViolationDetails",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Violation Details", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "JSON with violation specifics", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_DetectedAt",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Detected At", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the compliance assessment was performed", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_RemediatedAt",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Remediated At", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the violation was remediated", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_RemediationStatus",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Remediation Status", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Status of sharing remediation action", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_ASARD_remediationstatus')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_RemediationApprovedBy",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Remediation Approved By", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "UPN of the person who approved remediation", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_RemediationNotes",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Remediation Notes", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Notes on remediation actions taken", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ExceptionExpiresAt",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Exception Expires At", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the compliance exception expires", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ExceptionJustification",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Exception Justification", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Business justification for compliance exception", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ExceptionApprovedBy",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Exception Approved By", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "UPN of the person who approved the exception", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EvidenceJson",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Evidence JSON", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "JSON evidence payload for audit trail", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
    ],
    "fsi_approvedsecuritygrouppolicy": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Zone",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Zone", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Governance zone this policy applies to", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_zone')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_SecurityGroupId",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Security Group ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Entra ID object ID of the approved security group", "LanguageCode": 1033}]},
            "MaxLength": 100,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_SecurityGroupName",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Security Group Name", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Display name of the approved security group", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ApprovedBy",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Approved By", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "UPN of the person who approved this policy", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ApprovedAt",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Approved At", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When this policy was approved", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_IsActive",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Is Active", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether this approved security group policy is currently active", "LanguageCode": 1033}]},
            "DefaultValue": True,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_PolicyNotes",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Policy Notes", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Additional notes or context for this policy", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
    ],
}


# ---------------------------------------------------------------------------
# Documentation helpers
# ---------------------------------------------------------------------------

def _label(obj: dict) -> str:
    """Extract the English label from a Dataverse LocalizedLabels structure."""
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
        "Microsoft.Dynamics.CRM.MoneyAttributeMetadata": "Money",
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
    """Look up an option set by name across OPTIONSETS and SHARED_OPTIONSETS."""
    if name in OPTIONSETS:
        return OPTIONSETS[name]
    if name in SHARED_OPTIONSETS:
        return SHARED_OPTIONSETS[name]
    return None


def _format_option_values(options: list) -> str:
    """Return a compact string of value/label pairs for an option set."""
    parts = []
    for opt in options:
        val = opt.get("Value", "")
        lbl = _label(opt.get("Label", {}))
        parts.append(f"`{val}` = {lbl}")
    return ", ".join(parts)


def generate_schema_docs() -> str:
    """Generate a Markdown reference document from the in-memory schema definitions."""
    lines: list[str] = []

    # Header
    lines.append("# Dataverse Schema Reference")
    lines.append("")
    lines.append("> Auto-generated from `create_asard_dataverse_schema.py`. Do not edit manually.")
    lines.append("")

    # Tables
    lines.append("## Tables")
    lines.append("")
    lines.append("| SchemaName | Logical Name | Description | Primary Name Attribute |")
    lines.append("|---|---|---|---|")
    for schema_name, tbl in TABLES.items():
        logical = schema_name.lower()
        desc = _label(tbl.get("Description", {}))
        pna = tbl.get("PrimaryNameAttribute", "")
        lines.append(f"| {schema_name} | {logical} | {desc} | {pna} |")
    lines.append("")

    # Columns (per table)
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
            desc = _label(col.get("Description", {}))

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
                true_lbl = _label(opt.get("TrueOption", {}).get("Label", {})) if opt.get("TrueOption") else "Yes"
                false_lbl = _label(opt.get("FalseOption", {}).get("Label", {})) if opt.get("FalseOption") else "No"
                os_cell = f"`1` = {true_lbl}, `0` = {false_lbl}"

            lines.append(f"| {sn} | {ln} | {ctype} | {required} | {desc} | {os_cell} |")

        lines.append("")

    # Option Sets
    lines.append("## Option Sets")
    lines.append("")

    lines.append("### Shared Option Sets")
    lines.append("")
    for name, osdef in SHARED_OPTIONSETS.items():
        desc = _label(osdef.get("Description", {}))
        lines.append(f"#### {name}")
        lines.append("")
        lines.append(f"{desc}")
        lines.append("")
        lines.append("| Value | Label |")
        lines.append("|---|---|")
        for opt in osdef.get("Options", []):
            lines.append(f"| {opt['Value']} | {_label(opt['Label'])} |")
        lines.append("")

    lines.append("### ASARD Option Sets")
    lines.append("")
    for name, osdef in OPTIONSETS.items():
        desc = _label(osdef.get("Description", {}))
        lines.append(f"#### {name}")
        lines.append("")
        lines.append(f"{desc}")
        lines.append("")
        lines.append("| Value | Label |")
        lines.append("|---|---|")
        for opt in osdef.get("Options", []):
            lines.append(f"| {opt['Value']} | {_label(opt['Label'])} |")
        lines.append("")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Deployment functions
# ---------------------------------------------------------------------------

def create_optionsets(client: DataverseClient, dry_run: bool) -> dict:
    """Create global option sets (shared and ASARD-specific).

    Args:
        client: DataverseClient instance.
        dry_run: If True, preview changes without creating.

    Returns:
        dict with created/skipped counts.
    """
    print("\n=== Creating Option Sets ===")
    created = 0
    skipped = 0

    print("\nShared option sets (reused from ACV):")
    for name, metadata in SHARED_OPTIONSETS.items():
        if client.get_global_optionset(name):
            print(f"  {name}: Already exists (reusing)")
            skipped += 1
        else:
            print(f"  {name}: Creating")
            client.create_option_set(metadata)
            created += 1

    print("\nASARD-specific option sets:")
    for name, metadata in OPTIONSETS.items():
        if client.get_global_optionset(name):
            print(f"  {name}: Already exists")
            skipped += 1
        else:
            print(f"  {name}: Creating")
            client.create_option_set(metadata)
            created += 1

    return {"created": created, "skipped": skipped}


def create_tables(client: DataverseClient, dry_run: bool) -> dict:
    """Create Dataverse tables.

    Args:
        client: DataverseClient instance.
        dry_run: If True, preview changes without creating.

    Returns:
        dict with created/skipped counts.
    """
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
            client.create_table(metadata)
            created += 1
    return {"created": created, "skipped": skipped}


def create_columns(client: DataverseClient, dry_run: bool) -> None:
    """Create columns on tables.

    Args:
        client: DataverseClient instance.
        dry_run: If True, preview changes without creating.
    """
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
                client.create_column(table_logical_name, column_metadata)


def create_schema(client: DataverseClient, dry_run: bool) -> dict:
    """Create complete schema (orchestrator).

    Args:
        client: DataverseClient instance.
        dry_run: If True, preview changes without creating.

    Returns:
        dict with deployment results summary.
    """
    option_set_results = create_optionsets(client, dry_run)
    table_results = create_tables(client, dry_run)
    create_columns(client, dry_run)
    print("\n=== Schema Creation Complete ===")
    return {
        "errors": 0,
        "option_sets": option_set_results,
        "tables": table_results,
    }


def main():
    """CLI entry point for ASARD Dataverse schema deployment."""
    parser = argparse.ArgumentParser(
        description="Create Dataverse schema for Agent Sharing Access Restriction Detector",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Tables created:
  - fsi_AgentSharingCompliance (UserOwned)
  - fsi_ApprovedSecurityGroupPolicy (OrganizationOwned)

Option sets:
  - fsi_acv_zone (shared, reused if present)
  - fsi_ASARD_compliancestatus
  - fsi_ASARD_remediationstatus

Examples:
  # Interactive authentication
  python create_asard_dataverse_schema.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive

  # Service Principal authentication
  python create_asard_dataverse_schema.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --client-id <app-id>

  # Dry run to preview changes
  python create_asard_dataverse_schema.py \\
      --tenant-id <tenant-id> \\
      --environment-url https://org.crm.dynamics.com \\
      --interactive --dry-run

  # Generate schema documentation only
  python create_asard_dataverse_schema.py --output-docs
        """,
    )
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ASARD_TENANT_ID"),
        help="Entra ID tenant ID (or set ASARD_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ASARD_CLIENT_ID"),
        help="Application (client) ID (or set ASARD_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ASARD_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set ASARD_ENVIRONMENT_URL env var)",
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser authentication",
    )
    parser.add_argument(
        "--dry-run",
        action="store_true",
        help="Preview schema operations without API calls",
    )
    parser.add_argument(
        "--output-docs",
        action="store_true",
        help="Generate docs/dataverse-schema.md and exit (no credentials required)",
    )

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

    if not args.tenant_id or not args.environment_url:
        parser.error(
            "Missing required arguments. Provide --tenant-id and --environment-url "
            "(or set ASARD_TENANT_ID and ASARD_ENVIRONMENT_URL env vars)"
        )
    if not args.client_id and not args.interactive:
        parser.error(
            "--client-id is required (or set ASARD_CLIENT_ID env var) unless --interactive is specified"
        )

    client_secret = os.environ.get("ASARD_CLIENT_SECRET")
    if not args.interactive:
        if not client_secret:
            import getpass
            client_secret = getpass.getpass("Client secret: ")

    try:
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            interactive=args.interactive,
            dry_run=args.dry_run,
        )

        if args.dry_run:
            print("=== DRY RUN MODE - No changes will be made ===")

        create_schema(client, args.dry_run)

        if not args.dry_run:
            print("\nSchema deployment: SUCCESS")

        sys.exit(0)
    except requests.HTTPError as e:
        print(f"HTTP Error: {e}", file=sys.stderr)
        sys.exit(2)
    except RuntimeError as e:
        print(f"Authentication Error: {e}", file=sys.stderr)
        sys.exit(1)
    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(4)


if __name__ == "__main__":
    main()
