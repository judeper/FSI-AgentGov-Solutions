#!/usr/bin/env python3
"""Generate Dataverse schema documentation for Segregation of Duties Detector.

This module is the source of truth for solution table names, logical column
names, and choice values used by the PowerShell scripts. It intentionally does
not ship exported Power Platform solution artifacts.
"""

from __future__ import annotations

import argparse
from pathlib import Path
from typing import Any

PUBLISHER_PREFIX = "fsi"


def _label(text: str) -> dict[str, Any]:
    """Return a Dataverse label object for an English display label."""
    return {"LocalizedLabels": [{"Label": text, "LanguageCode": 1033}]}


def _string_col(schema_name: str, display: str, max_length: int, required: bool, description: str) -> dict[str, Any]:
    """Build a string column definition."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "Description": _label(description),
        "RequiredLevel": {"Value": "ApplicationRequired" if required else "None"},
        "MaxLength": max_length,
        "FormatName": {"Value": "Text"},
    }


def _memo_col(schema_name: str, display: str, required: bool, description: str) -> dict[str, Any]:
    """Build a memo column definition."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "Description": _label(description),
        "RequiredLevel": {"Value": "ApplicationRequired" if required else "None"},
        "MaxLength": 100000,
        "Format": "Text",
    }


def _picklist_col(schema_name: str, display: str, optionset_name: str, required: bool, description: str) -> dict[str, Any]:
    """Build a picklist column definition bound to a global option set."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "Description": _label(description),
        "RequiredLevel": {"Value": "ApplicationRequired" if required else "None"},
        "GlobalOptionSet@odata.bind": f"/GlobalOptionSetDefinitions(Name='{optionset_name}')",
    }


def _bool_col(schema_name: str, display: str, default: bool, required: bool, description: str) -> dict[str, Any]:
    """Build a boolean column definition."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "Description": _label(description),
        "RequiredLevel": {"Value": "ApplicationRequired" if required else "None"},
        "DefaultValue": default,
        "OptionSet": {
            "TrueOption": {"Value": 1, "Label": _label("Yes")},
            "FalseOption": {"Value": 0, "Label": _label("No")},
        },
    }


def _datetime_col(schema_name: str, display: str, required: bool, description: str, date_only: bool = False) -> dict[str, Any]:
    """Build a date or date/time column definition."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "Description": _label(description),
        "RequiredLevel": {"Value": "ApplicationRequired" if required else "None"},
        "Format": "DateOnly" if date_only else "DateAndTime",
        "DateTimeBehavior": {"Value": "DateOnly" if date_only else "UserLocal"},
    }


def _lookup_col(schema_name: str, display: str, target: str, required: bool, description: str) -> dict[str, Any]:
    """Build a lookup column definition for documentation."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.LookupAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "Description": _label(description),
        "RequiredLevel": {"Value": "ApplicationRequired" if required else "None"},
        "Targets": [target],
    }


OPTIONSETS: dict[str, dict[str, Any]] = {
    "fsi_SD_category": {
        "Name": "fsi_SD_category",
        "DisplayName": _label("SoD Conflict Category"),
        "Description": _label("Segregation of Duties conflict category"),
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": _label("Maker/Checker")},
            {"Value": 100000001, "Label": _label("Segregation")},
            {"Value": 100000002, "Label": _label("Privileged Access")},
        ],
    },
    "fsi_SD_rolecontext": {
        "Name": "fsi_SD_rolecontext",
        "DisplayName": _label("SoD Role Context"),
        "Description": _label("Source system where a role assignment is evaluated"),
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": _label("Entra ID Directory Role")},
            {"Value": 100000001, "Label": _label("Entra ID App Role")},
            {"Value": 100000002, "Label": _label("Power Platform Environment Role")},
            {"Value": 100000003, "Label": _label("Dataverse Security Role")},
            {"Value": 100000004, "Label": _label("Custom Application Role")},
        ],
    },
    "fsi_SD_severity": {
        "Name": "fsi_SD_severity",
        "DisplayName": _label("SoD Severity"),
        "Description": _label("Severity assigned to a detected SoD violation"),
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": _label("Critical")},
            {"Value": 100000001, "Label": _label("High")},
            {"Value": 100000002, "Label": _label("Medium")},
            {"Value": 100000003, "Label": _label("Low")},
        ],
    },
    "fsi_SD_violationstatus": {
        "Name": "fsi_SD_violationstatus",
        "DisplayName": _label("SoD Violation Status"),
        "Description": _label("Lifecycle status for a SoD violation"),
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": _label("Open")},
            {"Value": 100000001, "Label": _label("Under Review")},
            {"Value": 100000002, "Label": _label("Exception Requested")},
            {"Value": 100000003, "Label": _label("Exception Approved")},
            {"Value": 100000004, "Label": _label("Resolved - Role Removed")},
            {"Value": 100000005, "Label": _label("Resolved - User Removed")},
            {"Value": 100000006, "Label": _label("Closed - False Positive")},
        ],
    },
    "fsi_SD_resolutiontype": {
        "Name": "fsi_SD_resolutiontype",
        "DisplayName": _label("SoD Resolution Type"),
        "Description": _label("How a SoD violation was remediated or closed"),
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": _label("Role A Removed")},
            {"Value": 100000001, "Label": _label("Role B Removed")},
            {"Value": 100000002, "Label": _label("Both Roles Removed")},
            {"Value": 100000003, "Label": _label("User Deactivated")},
            {"Value": 100000004, "Label": _label("Exception Granted")},
            {"Value": 100000005, "Label": _label("False Positive")},
            {"Value": 100000006, "Label": _label("Rule Disabled")},
        ],
    },
    "fsi_SD_exceptiontype": {
        "Name": "fsi_SD_exceptiontype",
        "DisplayName": _label("SoD Exception Type"),
        "Description": _label("Approved exception duration category"),
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": _label("Emergency")},
            {"Value": 100000001, "Label": _label("Temporary")},
            {"Value": 100000002, "Label": _label("Permanent")},
        ],
    },
    "fsi_SD_exceptionstatus": {
        "Name": "fsi_SD_exceptionstatus",
        "DisplayName": _label("SoD Exception Status"),
        "Description": _label("Approval status for a SoD exception"),
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": _label("Requested")},
            {"Value": 100000001, "Label": _label("Manager Approved")},
            {"Value": 100000002, "Label": _label("Compliance Review")},
            {"Value": 100000003, "Label": _label("Approved")},
            {"Value": 100000004, "Label": _label("Denied")},
            {"Value": 100000005, "Label": _label("Expired")},
            {"Value": 100000006, "Label": _label("Revoked")},
        ],
    },
    "fsi_SD_auditeventtype": {
        "Name": "fsi_SD_auditeventtype",
        "DisplayName": _label("SoD Audit Event Type"),
        "Description": _label("Type of SoD audit event"),
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": _label("Violation Detected")},
            {"Value": 100000001, "Label": _label("Violation Resolved")},
            {"Value": 100000002, "Label": _label("Exception Requested")},
            {"Value": 100000003, "Label": _label("Exception Approved")},
            {"Value": 100000004, "Label": _label("Exception Denied")},
            {"Value": 100000005, "Label": _label("Exception Expired")},
            {"Value": 100000006, "Label": _label("Rule Created")},
            {"Value": 100000007, "Label": _label("Rule Modified")},
            {"Value": 100000008, "Label": _label("Rule Disabled")},
            {"Value": 100000009, "Label": _label("Scan Completed")},
            {"Value": 100000010, "Label": _label("Alert Sent")},
        ],
    },
}

TABLES: dict[str, dict[str, Any]] = {
    "fsi_ConflictRule": {
        "SchemaName": "fsi_ConflictRule",
        "DisplayName": _label("Conflict Rule"),
        "DisplayCollectionName": _label("Conflict Rules"),
        "Description": _label("Defines incompatible role combinations for SoD detection"),
        "OwnershipType": "OrganizationOwned",
        "PrimaryNameAttribute": "fsi_name",
        "Attributes": [_string_col("fsi_Name", "Name", 200, True, "Rule name")],
    },
    "fsi_SodViolation": {
        "SchemaName": "fsi_SodViolation",
        "DisplayName": _label("SoD Violation"),
        "DisplayCollectionName": _label("SoD Violations"),
        "Description": _label("Detected segregation of duties violation"),
        "OwnershipType": "OrganizationOwned",
        "PrimaryNameAttribute": "fsi_name",
        "Attributes": [_string_col("fsi_Name", "Name", 200, True, "Violation title")],
    },
    "fsi_SodException": {
        "SchemaName": "fsi_SodException",
        "DisplayName": _label("SoD Exception"),
        "DisplayCollectionName": _label("SoD Exceptions"),
        "Description": _label("Approved exception for a justified role conflict"),
        "OwnershipType": "OrganizationOwned",
        "PrimaryNameAttribute": "fsi_name",
        "Attributes": [_string_col("fsi_Name", "Name", 200, True, "Exception title")],
    },
    "fsi_SodAuditLog": {
        "SchemaName": "fsi_SodAuditLog",
        "DisplayName": _label("SoD Audit Log"),
        "DisplayCollectionName": _label("SoD Audit Logs"),
        "Description": _label("Audit trail for SoD-related activity"),
        "OwnershipType": "OrganizationOwned",
        "PrimaryNameAttribute": "fsi_name",
        "Attributes": [_string_col("fsi_Name", "Name", 200, True, "Log entry title")],
    },
}

COLUMNS: dict[str, list[dict[str, Any]]] = {
    "fsi_conflictrule": [
        _picklist_col("fsi_Category", "Category", "fsi_SD_category", True, "Conflict category"),
        _string_col("fsi_RoleA", "Role A", 100, True, "First role in conflict"),
        _picklist_col("fsi_RoleAContext", "Role A Context", "fsi_SD_rolecontext", True, "Context for Role A"),
        _string_col("fsi_RoleB", "Role B", 100, True, "Second role in conflict"),
        _picklist_col("fsi_RoleBContext", "Role B Context", "fsi_SD_rolecontext", True, "Context for Role B"),
        _picklist_col("fsi_Severity", "Severity", "fsi_SD_severity", True, "Violation severity"),
        _memo_col("fsi_Description", "Description", False, "Rule description"),
        _bool_col("fsi_Enabled", "Enabled", True, True, "Rule is active"),
        _bool_col("fsi_AllowException", "Allow Exception", True, True, "Exceptions are permitted"),
    ],
    "fsi_sodviolation": [
        _lookup_col("fsi_ConflictRuleId", "Conflict Rule", "fsi_conflictrule", True, "Violated rule"),
        _string_col("fsi_UserId", "User ID", 100, True, "User principal name"),
        _string_col("fsi_UserObjectId", "User Object ID", 36, True, "Microsoft Entra object ID"),
        _string_col("fsi_UserDisplayName", "User Display Name", 200, True, "User display name"),
        _string_col("fsi_RoleAAssignment", "Role A Assignment", 200, True, "Role A assignment details"),
        _string_col("fsi_RoleBAssignment", "Role B Assignment", 200, True, "Role B assignment details"),
        _string_col("fsi_Environment", "Environment", 100, False, "Power Platform environment ID when applicable"),
        _picklist_col("fsi_Status", "Status", "fsi_SD_violationstatus", True, "Violation status"),
        _datetime_col("fsi_DetectedOn", "Detected On", True, "Detection timestamp"),
        _datetime_col("fsi_ResolvedOn", "Resolved On", False, "Resolution timestamp"),
        _picklist_col("fsi_ResolutionType", "Resolution Type", "fsi_SD_resolutiontype", False, "How the violation was resolved"),
        _lookup_col("fsi_ExceptionId", "Exception", "fsi_sodexception", False, "Approved exception when applicable"),
    ],
    "fsi_sodexception": [
        _lookup_col("fsi_SodViolationId", "SoD Violation", "fsi_sodviolation", True, "Related violation"),
        _string_col("fsi_UserId", "User ID", 100, True, "User principal name"),
        _picklist_col("fsi_ExceptionType", "Exception Type", "fsi_SD_exceptiontype", True, "Exception type"),
        _memo_col("fsi_Justification", "Justification", True, "Business justification"),
        _memo_col("fsi_CompensatingControls", "Compensating Controls", True, "Mitigating controls"),
        _memo_col("fsi_MonitoringPlan", "Monitoring Plan", False, "Ongoing monitoring description"),
        _lookup_col("fsi_RequestedBy", "Requested By", "systemuser", True, "Exception requestor"),
        _datetime_col("fsi_RequestedOn", "Requested On", True, "Request timestamp"),
        _lookup_col("fsi_ApprovedBy", "Approved By", "systemuser", False, "Final approver"),
        _datetime_col("fsi_ApprovedOn", "Approved On", False, "Approval timestamp"),
        _picklist_col("fsi_Status", "Status", "fsi_SD_exceptionstatus", True, "Exception status"),
        _datetime_col("fsi_EffectiveDate", "Effective Date", False, "Exception start date", date_only=True),
        _datetime_col("fsi_ExpirationDate", "Expiration Date", False, "Exception end date", date_only=True),
        _datetime_col("fsi_NextReviewDate", "Next Review Date", False, "Next review due date", date_only=True),
        _bool_col("fsi_RiskAcceptance", "Risk Acceptance", False, False, "Risk formally accepted"),
    ],
    "fsi_sodauditlog": [
        _picklist_col("fsi_EventType", "Event Type", "fsi_SD_auditeventtype", True, "Type of event"),
        _string_col("fsi_EntityType", "Entity Type", 50, True, "Related entity type"),
        _string_col("fsi_EntityId", "Entity ID", 36, True, "Related entity ID"),
        _string_col("fsi_UserId", "User ID", 100, True, "User involved"),
        _string_col("fsi_PerformedBy", "Performed By", 100, True, "Action performer"),
        _memo_col("fsi_EventDetails", "Event Details", False, "Detailed event description"),
        _memo_col("fsi_PreviousValue", "Previous Value", False, "Value before change"),
        _memo_col("fsi_NewValue", "New Value", False, "Value after change"),
        _string_col("fsi_IpAddress", "IP Address", 50, False, "Source IP address"),
    ],
}


def _label_text(label_obj: dict[str, Any]) -> str:
    """Extract the English label from a Dataverse label object."""
    for item in label_obj.get("LocalizedLabels", []):
        if item.get("LanguageCode") == 1033:
            return item.get("Label", "")
    labels = label_obj.get("LocalizedLabels", [])
    return labels[0].get("Label", "") if labels else ""


def _col_type(column: dict[str, Any]) -> str:
    """Return a readable Dataverse column type."""
    mapping = {
        "Microsoft.Dynamics.CRM.StringAttributeMetadata": "String",
        "Microsoft.Dynamics.CRM.MemoAttributeMetadata": "Memo",
        "Microsoft.Dynamics.CRM.PicklistAttributeMetadata": "Choice",
        "Microsoft.Dynamics.CRM.BooleanAttributeMetadata": "Boolean",
        "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata": "DateTime",
        "Microsoft.Dynamics.CRM.LookupAttributeMetadata": "Lookup",
    }
    return mapping.get(column.get("@odata.type", ""), "Unknown")


def _option_set_name(column: dict[str, Any]) -> str | None:
    """Extract the option set name from a picklist bind path."""
    bind = column.get("GlobalOptionSet@odata.bind", "")
    if "Name='" in bind:
        return bind.split("Name='")[1].split("'")[0]
    return None


def _format_options(optionset_name: str | None, column: dict[str, Any]) -> str:
    """Format option values for the generated Markdown table."""
    if optionset_name:
        options = OPTIONSETS[optionset_name]["Options"]
        return ", ".join(f"`{opt['Value']}` = {_label_text(opt['Label'])}" for opt in options)
    if column.get("@odata.type") == "Microsoft.Dynamics.CRM.BooleanAttributeMetadata":
        return "`1` = Yes, `0` = No"
    targets = column.get("Targets")
    if targets:
        return f"Targets: `{', '.join(targets)}`"
    return ""


def generate_schema_docs() -> str:
    """Generate Markdown schema documentation from in-memory definitions."""
    lines: list[str] = [
        "# Dataverse Schema Reference",
        "",
        "> Auto-generated from `scripts/create_sd_dataverse_schema.py`. Do not edit manually.",
        "",
        "This reference lists the Dataverse SchemaName and logical name for each table and column. The PowerShell scripts use the logical names shown here in OData requests.",
        "",
        "## Tables",
        "",
        "| SchemaName | Logical Name | Description | Primary Name Attribute |",
        "|---|---|---|---|",
    ]

    for schema_name, table in TABLES.items():
        lines.append(
            f"| {schema_name} | {schema_name.lower()} | {_label_text(table['Description'])} | {table['PrimaryNameAttribute']} |"
        )

    lines.extend(["", "## Columns", ""])
    for schema_name, table in TABLES.items():
        logical_name = schema_name.lower()
        columns = table["Attributes"] + COLUMNS[logical_name]
        lines.extend([
            f"### {schema_name} (`{logical_name}`)",
            "",
            "| SchemaName | Logical Name | Type | Required | Description | Values / Target |",
            "|---|---|---|---|---|---|",
        ])
        for column in columns:
            column_schema = column["SchemaName"]
            required = "Yes" if column.get("RequiredLevel", {}).get("Value") == "ApplicationRequired" else "No"
            optionset_name = _option_set_name(column)
            lines.append(
                "| "
                f"{column_schema} | {column_schema.lower()} | {_col_type(column)} | {required} | "
                f"{_label_text(column['Description'])} | {_format_options(optionset_name, column)} |"
            )
        lines.append("")

    lines.extend(["## Option Sets", ""])
    for name, optionset in OPTIONSETS.items():
        lines.extend([f"### {name}", "", _label_text(optionset["Description"]), "", "| Value | Label |", "|---|---|"])
        for option in optionset["Options"]:
            lines.append(f"| {option['Value']} | {_label_text(option['Label'])} |")
        lines.append("")

    lines.extend([
        "## OData entity sets used by scripts",
        "",
        "| Table | Entity set | Used by |",
        "|---|---|---|",
        "| fsi_conflictrule | `fsi_conflictrules` | `Import-ConflictRules.ps1`, `Invoke-SoDScan.ps1` |",
        "| fsi_sodviolation | `fsi_sodviolations` | `Invoke-SoDScan.ps1` |",
        "| systemuser | `systemusers` | Dataverse security role collection expansion |",
        "| role | `roles` via `systemuserroles_association` | Dataverse security role collection expansion |",
        "",
        "## Deployment note",
        "",
        "Create these Dataverse tables and choices with the exact SchemaNames and numeric choice values above. If you create choice columns manually in Power Apps, verify the generated numeric values before running `Import-ConflictRules.ps1`; mismatched values can cause imports and OData filters to evaluate incorrectly.",
        "",
        "---",
        "",
        "*Segregation of Duties Detector v1.2.1*",
        "",
    ])
    return "\n".join(lines)


def main() -> None:
    """Command-line entry point."""
    parser = argparse.ArgumentParser(description="Generate Dataverse schema docs for Segregation of Duties Detector")
    parser.add_argument("--output-docs", action="store_true", help="Regenerate docs/dataverse-schema.md")
    args = parser.parse_args()

    if not args.output_docs:
        parser.error("Only --output-docs is supported; no Power Platform runtime artifacts are exported.")

    solution_root = Path(__file__).resolve().parents[1]
    out_path = solution_root / "docs" / "dataverse-schema.md"
    out_path.write_text(generate_schema_docs(), encoding="utf-8")
    print(f"Schema docs written to {out_path}")


if __name__ == "__main__":
    main()
