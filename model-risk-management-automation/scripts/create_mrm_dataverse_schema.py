#!/usr/bin/env python3
"""
Create Dataverse schema for Model Risk Management Automation.

Creates ModelInventory, MrmRiskRating, ValidationCycle, ValidationFinding,
MonitoringRecord, and MrmComplianceEvent tables with all columns, choice
fields, and supporting option sets. Reuses shared ACV option set
(fsi_acv_zone) when present.
"""

import argparse
import os
import sys
from typing import Optional

import requests

sys.path.insert(
    0,
    os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"),
)
from dataverse_client import DataverseClient  # noqa: E402

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
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Unclassified", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Zone 1", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Zone 2", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Zone 3", "LanguageCode": 1033}]}},
        ],
    },
}

# ---------------------------------------------------------------------------
# MRM-specific option sets
# ---------------------------------------------------------------------------
OPTIONSETS = {
    "fsi_mrm_mrmtier": {
        "Name": "fsi_mrm_mrmtier",
        "DisplayName": {"LocalizedLabels": [{"Label": "MRM Tier", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Model Risk Management tier classification", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Tier 1 - Full MRM", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Tier 2 - Enhanced MRM", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Tier 3 - Standard MRM", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "Tier 4 - Minimal MRM", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_mrm_modelprovider": {
        "Name": "fsi_mrm_modelprovider",
        "DisplayName": {"LocalizedLabels": [{"Label": "Model Provider", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Underlying model provider", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Microsoft", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Anthropic", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "OpenAI", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Custom", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "Third-Party", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_mrm_decisionoutputtype": {
        "Name": "fsi_mrm_decisionoutputtype",
        "DisplayName": {"LocalizedLabels": [{"Label": "Decision Output Type", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Type of decision or output the model produces", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Quantitative Estimate", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Decision Support", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Information Retrieval", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Productivity", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_mrm_materiality": {
        "Name": "fsi_mrm_materiality",
        "DisplayName": {"LocalizedLabels": [{"Label": "Materiality", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Materiality level of the model output", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "High", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Medium", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Low", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_mrm_mrmstatus": {
        "Name": "fsi_mrm_mrmstatus",
        "DisplayName": {"LocalizedLabels": [{"Label": "MRM Status", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Lifecycle status of the model inventory record", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Pending Submission", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Submitted", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Risk Scored", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Validation Scheduled", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "In Validation", "LanguageCode": 1033}]}},
            {"Value": 100000005, "Label": {"LocalizedLabels": [{"Label": "Validated", "LanguageCode": 1033}]}},
            {"Value": 100000006, "Label": {"LocalizedLabels": [{"Label": "Conditionally Approved", "LanguageCode": 1033}]}},
            {"Value": 100000007, "Label": {"LocalizedLabels": [{"Label": "Rejected", "LanguageCode": 1033}]}},
            {"Value": 100000008, "Label": {"LocalizedLabels": [{"Label": "Retired", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_mrm_riskrating": {
        "Name": "fsi_mrm_riskrating",
        "DisplayName": {"LocalizedLabels": [{"Label": "Risk Rating", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Composite risk rating of the model", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Critical", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "High", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Medium", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Low", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_mrm_validationcadence": {
        "Name": "fsi_mrm_validationcadence",
        "DisplayName": {"LocalizedLabels": [{"Label": "Validation Cadence", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Scheduled validation frequency", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Annual", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Biennial", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Triennial", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_mrm_validationstatus": {
        "Name": "fsi_mrm_validationstatus",
        "DisplayName": {"LocalizedLabels": [{"Label": "Validation Status", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Current validation status of the model", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Not Started", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Submitted", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "In Progress", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "Findings Issued", "LanguageCode": 1033}]}},
            {"Value": 100000005, "Label": {"LocalizedLabels": [{"Label": "Remediated", "LanguageCode": 1033}]}},
            {"Value": 100000006, "Label": {"LocalizedLabels": [{"Label": "Validated", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_mrm_agentcardformat": {
        "Name": "fsi_mrm_agentcardformat",
        "DisplayName": {"LocalizedLabels": [{"Label": "Agent Card Format", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Format of the agent model card", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Word", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "JSON", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_mrm_compositerating": {
        "Name": "fsi_mrm_compositerating",
        "DisplayName": {"LocalizedLabels": [{"Label": "Composite Rating", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Composite risk rating derived from scoring dimensions", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Critical", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "High", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Medium", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Low", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_mrm_validationtype": {
        "Name": "fsi_mrm_validationtype",
        "DisplayName": {"LocalizedLabels": [{"Label": "Validation Type", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Type of validation cycle", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Initial", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Periodic", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Material Change", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Ad Hoc", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_mrm_cyclestatus": {
        "Name": "fsi_mrm_cyclestatus",
        "DisplayName": {"LocalizedLabels": [{"Label": "Cycle Status", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Current status of the validation cycle", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Not Started", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Submitted", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "In Progress", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "Findings Issued", "LanguageCode": 1033}]}},
            {"Value": 100000005, "Label": {"LocalizedLabels": [{"Label": "Remediated", "LanguageCode": 1033}]}},
            {"Value": 100000006, "Label": {"LocalizedLabels": [{"Label": "Validated", "LanguageCode": 1033}]}},
            {"Value": 100000007, "Label": {"LocalizedLabels": [{"Label": "Rejected", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_mrm_validationoutcome": {
        "Name": "fsi_mrm_validationoutcome",
        "DisplayName": {"LocalizedLabels": [{"Label": "Validation Outcome", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Final outcome of the validation cycle", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Validated - No Findings", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Validated - Findings Resolved", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Conditionally Approved", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Rejected", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_mrm_findingcategory": {
        "Name": "fsi_mrm_findingcategory",
        "DisplayName": {"LocalizedLabels": [{"Label": "Finding Category", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Category of the validation finding", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Conceptual Soundness", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Data Integrity", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Performance", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Bias/Fairness", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "Documentation", "LanguageCode": 1033}]}},
            {"Value": 100000005, "Label": {"LocalizedLabels": [{"Label": "Access Control", "LanguageCode": 1033}]}},
            {"Value": 100000006, "Label": {"LocalizedLabels": [{"Label": "Monitoring Gap", "LanguageCode": 1033}]}},
            {"Value": 100000007, "Label": {"LocalizedLabels": [{"Label": "Scope Limitation", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_mrm_severity": {
        "Name": "fsi_mrm_severity",
        "DisplayName": {"LocalizedLabels": [{"Label": "Severity", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Severity level of a validation finding", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Critical", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "High", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Medium", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "Low", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_mrm_remediationstatus": {
        "Name": "fsi_mrm_remediationstatus",
        "DisplayName": {"LocalizedLabels": [{"Label": "Remediation Status", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Status of finding remediation", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Open", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "In Progress", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Submitted for Review", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "Closed", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_mrm_sr117pillar": {
        "Name": "fsi_mrm_sr117pillar",
        "DisplayName": {"LocalizedLabels": [{"Label": "SR 11-7 Pillar", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Fed SR 11-7 model risk management pillar", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Pillar 1 (Development)", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Pillar 2 (Validation)", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Pillar 3 (Governance)", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_mrm_complianceimpact": {
        "Name": "fsi_mrm_complianceimpact",
        "DisplayName": {"LocalizedLabels": [{"Label": "Compliance Impact", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Compliance impact level of the event", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "None", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Low", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Medium", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "High", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "Critical", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_mrm_eventtype": {
        "Name": "fsi_mrm_eventtype",
        "DisplayName": {"LocalizedLabels": [{"Label": "Event Type", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Type of MRM compliance event", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Inventory Submitted", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Inventory Sync Failed", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Risk Scored", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Risk Rating Changed", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "Validation Cycle Opened", "LanguageCode": 1033}]}},
            {"Value": 100000005, "Label": {"LocalizedLabels": [{"Label": "Validation Assigned", "LanguageCode": 1033}]}},
            {"Value": 100000006, "Label": {"LocalizedLabels": [{"Label": "Findings Issued", "LanguageCode": 1033}]}},
            {"Value": 100000007, "Label": {"LocalizedLabels": [{"Label": "Remediation Submitted", "LanguageCode": 1033}]}},
            {"Value": 100000008, "Label": {"LocalizedLabels": [{"Label": "Validation Completed", "LanguageCode": 1033}]}},
            {"Value": 100000009, "Label": {"LocalizedLabels": [{"Label": "Validation Rejected", "LanguageCode": 1033}]}},
            {"Value": 100000010, "Label": {"LocalizedLabels": [{"Label": "Material Change Detected", "LanguageCode": 1033}]}},
            {"Value": 100000011, "Label": {"LocalizedLabels": [{"Label": "Agent Card Generated", "LanguageCode": 1033}]}},
            {"Value": 100000012, "Label": {"LocalizedLabels": [{"Label": "Agent Card Fallback Used", "LanguageCode": 1033}]}},
            {"Value": 100000013, "Label": {"LocalizedLabels": [{"Label": "Monitoring Alert", "LanguageCode": 1033}]}},
            {"Value": 100000014, "Label": {"LocalizedLabels": [{"Label": "Revalidation Triggered", "LanguageCode": 1033}]}},
            {"Value": 100000015, "Label": {"LocalizedLabels": [{"Label": "Model Retired", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_mrm_datasource": {
        "Name": "fsi_mrm_datasource",
        "DisplayName": {"LocalizedLabels": [{"Label": "Data Source", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Source of monitoring data", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Copilot Analytics", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "PPAC Telemetry", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Manual Entry", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Not Available", "LanguageCode": 1033}]}},
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
        "@odata.type": "#Microsoft.Dynamics.CRM.StringAttributeMetadata",
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
        "@odata.type": "#Microsoft.Dynamics.CRM.MemoAttributeMetadata",
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
        "@odata.type": "#Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
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
        "@odata.type": "#Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
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
        "@odata.type": "#Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
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
        "@odata.type": "#Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
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


def _decimal_col(schema_name: str, display: str, required: bool = False,
                 description: str = "", precision: int = 2,
                 min_val: int = 0, max_val: int = 100) -> dict:
    """Build a DecimalAttributeMetadata definition."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.DecimalAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "ApplicationRequired" if required else "None"},
        "Precision": precision,
        "MinValue": min_val,
        "MaxValue": max_val,
    }
    if description:
        defn["Description"] = _label(description)
    return defn


# ---------------------------------------------------------------------------
# Table definitions
# ---------------------------------------------------------------------------
TABLES = {
    # ── Table 1: fsi_ModelInventory — Master MRM Record ─────────────────
    "fsi_ModelInventory": {
        "SchemaName": "fsi_ModelInventory",
        "DisplayName": _label("Model Inventory"),
        "DisplayCollectionName": _label("Model Inventories"),
        "Description": _label("Master model risk management record for each AI agent"),
        "OwnershipType": "UserOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            _string_col(f"{PUBLISHER_PREFIX}_ModelName", "Model Name",
                        max_length=500, required=True,
                        description="Display name from agent registry"),
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_modelname",
    },
    # ── Table 2: fsi_MrmRiskRating — Risk Scoring Evidence ──────────────
    "fsi_MrmRiskRating": {
        "SchemaName": "fsi_MrmRiskRating",
        "DisplayName": _label("MRM Risk Rating"),
        "DisplayCollectionName": _label("MRM Risk Ratings"),
        "Description": _label("Risk scoring evidence and composite rating for model inventory records"),
        "OwnershipType": "OrganizationOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            _string_col(f"{PUBLISHER_PREFIX}_ScoredBy", "Scored By",
                        max_length=200, required=True,
                        description="UPN of the person who performed risk scoring"),
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_scoredby",
    },
    # ── Table 3: fsi_ValidationCycle — Validation Cycle Tracking ────────
    "fsi_ValidationCycle": {
        "SchemaName": "fsi_ValidationCycle",
        "DisplayName": _label("Validation Cycle"),
        "DisplayCollectionName": _label("Validation Cycles"),
        "Description": _label("Validation cycle tracking for model inventory records"),
        "OwnershipType": "UserOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            _string_col(f"{PUBLISHER_PREFIX}_CycleId", "Cycle ID",
                        max_length=50, required=False,
                        description="Auto Number"),
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_cycleid",
    },
    # ── Table 4: fsi_ValidationFinding — Individual Findings ────────────
    "fsi_ValidationFinding": {
        "SchemaName": "fsi_ValidationFinding",
        "DisplayName": _label("Validation Finding"),
        "DisplayCollectionName": _label("Validation Findings"),
        "Description": _label("Individual findings from validation cycles"),
        "OwnershipType": "UserOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            _string_col(f"{PUBLISHER_PREFIX}_FindingId", "Finding ID",
                        max_length=50, required=False,
                        description="Auto Number"),
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_findingid",
    },
    # ── Table 5: fsi_MonitoringRecord — Monitoring Results ──────────────
    "fsi_MonitoringRecord": {
        "SchemaName": "fsi_MonitoringRecord",
        "DisplayName": _label("Monitoring Record"),
        "DisplayCollectionName": _label("Monitoring Records"),
        "Description": _label("Periodic monitoring results for model inventory records"),
        "OwnershipType": "OrganizationOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            _string_col(f"{PUBLISHER_PREFIX}_MonitoringPeriod", "Monitoring Period",
                        max_length=20, required=True,
                        description="ISO week e.g. 2026-W12"),
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_monitoringperiod",
    },
    # ── Table 6: fsi_MrmComplianceEvent — Immutable Audit Log ───────────
    "fsi_MrmComplianceEvent": {
        "SchemaName": "fsi_MrmComplianceEvent",
        "DisplayName": _label("MRM Compliance Event"),
        "DisplayCollectionName": _label("MRM Compliance Events"),
        "Description": _label("Immutable audit log of MRM compliance events"),
        "OwnershipType": "OrganizationOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "EntitySetName": "fsi_mrmcomplianceevents",
        "Attributes": [
            _string_col(f"{PUBLISHER_PREFIX}_EventId", "Event ID",
                        max_length=50, required=False,
                        description="Auto Number"),
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_eventid",
    },
}

# ---------------------------------------------------------------------------
# Column definitions (added after table creation)
# ---------------------------------------------------------------------------
COLUMNS = {
    # ── fsi_modelinventory ──────────────────────────────────────────────
    "fsi_modelinventory": [
        _string_col(f"{PUBLISHER_PREFIX}_AgentId", "Agent ID",
                    max_length=100, required=True,
                    description="Power Platform Bot ID — Alternate Key part 1"),
        _string_col(f"{PUBLISHER_PREFIX}_EnvironmentId", "Environment ID",
                    max_length=100, required=True,
                    description="Power Platform environment GUID — Alternate Key part 2"),
        _string_col(f"{PUBLISHER_PREFIX}_EntraAgentId", "Entra Agent ID",
                    max_length=100, required=False,
                    description="From Microsoft Entra Agent ID / Agent 365 registry when available"),
        _string_col(f"{PUBLISHER_PREFIX}_ModelId", "Model ID",
                    max_length=50, required=False,
                    description="Auto Number format MRM-{YYYY}-{00000} — set by Dataverse"),
        _memo_col(f"{PUBLISHER_PREFIX}_BusinessFunction", "Business Function",
                  max_length=10000,
                  description="Declared use case — drives MRM tier assignment"),
        _picklist_col(f"{PUBLISHER_PREFIX}_MrmTier", "MRM Tier",
                      "fsi_mrm_mrmtier", required=True),
        _string_col(f"{PUBLISHER_PREFIX}_UnderlyingModel", "Underlying Model",
                    max_length=200, required=True,
                    description="e.g., GPT-5 Chat, Claude 3.7"),
        _picklist_col(f"{PUBLISHER_PREFIX}_ModelProvider", "Model Provider",
                      "fsi_mrm_modelprovider", required=True),
        _picklist_col(f"{PUBLISHER_PREFIX}_DecisionOutputType", "Decision Output Type",
                      "fsi_mrm_decisionoutputtype", required=True),
        _picklist_col(f"{PUBLISHER_PREFIX}_Materiality", "Materiality",
                      "fsi_mrm_materiality", required=True),
        _memo_col(f"{PUBLISHER_PREFIX}_DataInputs", "Data Inputs",
                  max_length=10000,
                  description="Input data sources description"),
        _memo_col(f"{PUBLISHER_PREFIX}_KnownLimitations", "Known Limitations",
                  max_length=10000,
                  description="Documented limitations per SR 11-7"),
        _string_col(f"{PUBLISHER_PREFIX}_IntendedUsers", "Intended Users",
                    max_length=500, required=True,
                    description="Target user population"),
        _picklist_col(f"{PUBLISHER_PREFIX}_GovernanceZone", "Governance Zone",
                      "fsi_acv_zone", required=True),
        _string_col(f"{PUBLISHER_PREFIX}_OwnerUpn", "Owner UPN",
                    max_length=200, required=True,
                    description="First Line of Defense"),
        _string_col(f"{PUBLISHER_PREFIX}_OwnerDepartment", "Owner Department",
                    max_length=200, required=False),
        _string_col(f"{PUBLISHER_PREFIX}_MrmOfficerUpn", "MRM Officer UPN",
                    max_length=200, required=False,
                    description="Second Line of Defense"),
        _string_col(f"{PUBLISHER_PREFIX}_AuditorUpn", "Auditor UPN",
                    max_length=200, required=False,
                    description="Third Line of Defense"),
        _picklist_col(f"{PUBLISHER_PREFIX}_MrmStatus", "MRM Status",
                      "fsi_mrm_mrmstatus", required=True),
        _picklist_col(f"{PUBLISHER_PREFIX}_CurrentRiskRating", "Current Risk Rating",
                      "fsi_mrm_riskrating", required=True),
        _picklist_col(f"{PUBLISHER_PREFIX}_ValidationCadence", "Validation Cadence",
                      "fsi_mrm_validationcadence", required=True),
        _datetime_col(f"{PUBLISHER_PREFIX}_LastValidatedDate", "Last Validated Date",
                      required=False),
        _datetime_col(f"{PUBLISHER_PREFIX}_NextValidationDue", "Next Validation Due",
                      required=True),
        _picklist_col(f"{PUBLISHER_PREFIX}_ValidationStatus", "Validation Status",
                      "fsi_mrm_validationstatus", required=True),
        _string_col(f"{PUBLISHER_PREFIX}_AgentCardVersion", "Agent Card Version",
                    max_length=20, required=False),
        _string_col(f"{PUBLISHER_PREFIX}_AgentCardUrl", "Agent Card URL",
                    max_length=2000, required=False, format_name="Url"),
        _picklist_col(f"{PUBLISHER_PREFIX}_AgentCardFormat", "Agent Card Format",
                      "fsi_mrm_agentcardformat", required=False),
        _bool_col(f"{PUBLISHER_PREFIX}_MaterialChangeFlag", "Material Change Flag",
                  default=False,
                  description="Triggers revalidation"),
        _memo_col(f"{PUBLISHER_PREFIX}_MaterialChangeDesc", "Material Change Description",
                  max_length=5000),
        _datetime_col(f"{PUBLISHER_PREFIX}_FirstSubmitted", "First Submitted",
                      required=True),
        _datetime_col(f"{PUBLISHER_PREFIX}_LastUpdated", "Last Updated",
                      required=True),
    ],

    # ── fsi_mrmriskrating ───────────────────────────────────────────────
    "fsi_mrmriskrating": [
        # NOTE: fsi_ModelInventory_Lookup — Lookup to fsi_modelinventory.
        # Lookup relationships require post-deployment setup in Power Platform
        # admin center or a separate OneToManyRelationshipMetadata API call.
        _datetime_col(f"{PUBLISHER_PREFIX}_ScoringDate", "Scoring Date",
                      required=True),
        _bool_col(f"{PUBLISHER_PREFIX}_IsCurrent", "Is Current",
                  default=False, required=True),
        _int_col(f"{PUBLISHER_PREFIX}_Score_DecisionImpact", "Score - Decision Impact",
                 required=True, description="1-5", min_val=1, max_val=5),
        _int_col(f"{PUBLISHER_PREFIX}_Score_DataSensitivity", "Score - Data Sensitivity",
                 required=True, description="1-5", min_val=1, max_val=5),
        _int_col(f"{PUBLISHER_PREFIX}_Score_UserPopulation", "Score - User Population",
                 required=True, description="1-5", min_val=1, max_val=5),
        _int_col(f"{PUBLISHER_PREFIX}_Score_Complexity", "Score - Complexity",
                 required=True, description="1-5", min_val=1, max_val=5),
        _int_col(f"{PUBLISHER_PREFIX}_Score_Explainability", "Score - Explainability",
                 required=True, description="1-5", min_val=1, max_val=5),
        _int_col(f"{PUBLISHER_PREFIX}_Score_RegulatoryExposure", "Score - Regulatory Exposure",
                 required=True, description="1-5", min_val=1, max_val=5),
        _int_col(f"{PUBLISHER_PREFIX}_Score_ChangeFrequency", "Score - Change Frequency",
                 required=True, description="1-5", min_val=1, max_val=5),
        _int_col(f"{PUBLISHER_PREFIX}_TotalScore", "Total Score",
                 required=True, description="Sum 7-35", min_val=7, max_val=35),
        _picklist_col(f"{PUBLISHER_PREFIX}_CompositeRating", "Composite Rating",
                      "fsi_mrm_compositerating", required=True),
        _memo_col(f"{PUBLISHER_PREFIX}_ScoringRationale", "Scoring Rationale",
                  max_length=10000,
                  description="Min 100 chars for examiner review"),
        _memo_col(f"{PUBLISHER_PREFIX}_ZoneWeightRationale", "Zone Weight Rationale",
                  max_length=5000,
                  description="Documents dual-zone scoring"),
        _bool_col(f"{PUBLISHER_PREFIX}_MrmOfficerOverride", "MRM Officer Override",
                  default=False, required=True),
        _memo_col(f"{PUBLISHER_PREFIX}_OverrideRationale", "Override Rationale",
                  max_length=10000),
        _string_col(f"{PUBLISHER_PREFIX}_OverrideApprovedBy", "Override Approved By",
                    max_length=200, required=False),
    ],

    # ── fsi_validationcycle ─────────────────────────────────────────────
    "fsi_validationcycle": [
        # NOTE: fsi_ModelInventory_Lookup — Lookup to fsi_modelinventory.
        # Requires post-deployment setup (see note above).
        _picklist_col(f"{PUBLISHER_PREFIX}_ValidationType", "Validation Type",
                      "fsi_mrm_validationtype", required=True),
        _picklist_col(f"{PUBLISHER_PREFIX}_MrmTierAtStart", "MRM Tier at Start",
                      "fsi_mrm_mrmtier", required=True),
        _picklist_col(f"{PUBLISHER_PREFIX}_RatingAtStart", "Rating at Start",
                      "fsi_mrm_riskrating", required=True),
        _picklist_col(f"{PUBLISHER_PREFIX}_CycleStatus", "Cycle Status",
                      "fsi_mrm_cyclestatus", required=True),
        _datetime_col(f"{PUBLISHER_PREFIX}_SubmittedDate", "Submitted Date"),
        _datetime_col(f"{PUBLISHER_PREFIX}_AssignedDate", "Assigned Date"),
        _string_col(f"{PUBLISHER_PREFIX}_ValidatorUpn", "Validator UPN",
                    max_length=200, required=False),
        _string_col(f"{PUBLISHER_PREFIX}_ValidatorDepartment", "Validator Department",
                    max_length=200, required=False),
        _datetime_col(f"{PUBLISHER_PREFIX}_ValidationStartDate", "Validation Start Date"),
        _datetime_col(f"{PUBLISHER_PREFIX}_FindingsIssuedDate", "Findings Issued Date"),
        _datetime_col(f"{PUBLISHER_PREFIX}_RemediationDueDate", "Remediation Due Date"),
        _datetime_col(f"{PUBLISHER_PREFIX}_RemediationSubmittedDate", "Remediation Submitted Date"),
        _datetime_col(f"{PUBLISHER_PREFIX}_ValidationCompletedDate", "Validation Completed Date"),
        _picklist_col(f"{PUBLISHER_PREFIX}_ValidationOutcome", "Validation Outcome",
                      "fsi_mrm_validationoutcome", required=False),
        _memo_col(f"{PUBLISHER_PREFIX}_OutcomeRationale", "Outcome Rationale",
                  max_length=10000),
        _bool_col(f"{PUBLISHER_PREFIX}_SlaBreachFlag", "SLA Breach Flag",
                  default=False, required=True),
        _memo_col(f"{PUBLISHER_PREFIX}_SlaBreachDetails", "SLA Breach Details",
                  max_length=5000),
        _string_col(f"{PUBLISHER_PREFIX}_EscalationTarget", "Escalation Target",
                    max_length=200, required=False),
    ],

    # ── fsi_validationfinding ───────────────────────────────────────────
    "fsi_validationfinding": [
        # NOTE: fsi_ValidationCycle_Lookup — Lookup to fsi_validationcycle.
        # NOTE: fsi_ModelInventory_Lookup — Lookup to fsi_modelinventory.
        # Lookup relationships require post-deployment manual setup in
        # Power Platform admin center or a separate API call.
        _picklist_col(f"{PUBLISHER_PREFIX}_Sr117Pillar", "SR 11-7 Pillar",
                      "fsi_mrm_sr117pillar", required=True),
        _picklist_col(f"{PUBLISHER_PREFIX}_FindingCategory", "Finding Category",
                      "fsi_mrm_findingcategory", required=True),
        _picklist_col(f"{PUBLISHER_PREFIX}_Severity", "Severity",
                      "fsi_mrm_severity", required=True),
        _memo_col(f"{PUBLISHER_PREFIX}_FindingDescription", "Finding Description",
                  max_length=10000,
                  description="Min 100 chars"),
        _memo_col(f"{PUBLISHER_PREFIX}_RequiredRemediation", "Required Remediation",
                  max_length=10000,
                  description="Min 50 chars"),
        _picklist_col(f"{PUBLISHER_PREFIX}_RemediationStatus", "Remediation Status",
                      "fsi_mrm_remediationstatus", required=True),
        _memo_col(f"{PUBLISHER_PREFIX}_OwnerResponse", "Owner Response",
                  max_length=10000),
        _memo_col(f"{PUBLISHER_PREFIX}_ValidatorClosureNotes", "Validator Closure Notes",
                  max_length=5000),
        _datetime_col(f"{PUBLISHER_PREFIX}_DueDate", "Due Date", required=True),
        _datetime_col(f"{PUBLISHER_PREFIX}_ClosedDate", "Closed Date"),
    ],

    # ── fsi_monitoringrecord ────────────────────────────────────────────
    "fsi_monitoringrecord": [
        # NOTE: fsi_ModelInventory_Lookup — Lookup to fsi_modelinventory.
        # Requires post-deployment setup (see note above).
        _datetime_col(f"{PUBLISHER_PREFIX}_MonitoringDate", "Monitoring Date",
                      required=True),
        _int_col(f"{PUBLISHER_PREFIX}_SessionCount", "Session Count",
                 description="Total sessions in monitoring period"),
        _decimal_col(f"{PUBLISHER_PREFIX}_ErrorRate", "Error Rate",
                     description="Error rate as percentage", precision=2,
                     min_val=0, max_val=100),
        _decimal_col(f"{PUBLISHER_PREFIX}_EscalationRate", "Escalation Rate",
                     description="Escalation rate as percentage", precision=2,
                     min_val=0, max_val=100),
        _decimal_col(f"{PUBLISHER_PREFIX}_AvgConfidence", "Avg Confidence",
                     description="Average confidence score", precision=2,
                     min_val=0, max_val=100),
        _int_col(f"{PUBLISHER_PREFIX}_OutOfScopeTriggers", "Out of Scope Triggers",
                 description="Count of out-of-scope trigger events"),
        _decimal_col(f"{PUBLISHER_PREFIX}_UserSatisfaction", "User Satisfaction",
                     description="User satisfaction score", precision=2,
                     min_val=0, max_val=100),
        _bool_col(f"{PUBLISHER_PREFIX}_DriftSignalDetected", "Drift Signal Detected",
                  default=False, required=True),
        _memo_col(f"{PUBLISHER_PREFIX}_DriftSignalDetails", "Drift Signal Details",
                  max_length=5000),
        _bool_col(f"{PUBLISHER_PREFIX}_ThresholdBreachFlag", "Threshold Breach Flag",
                  default=False, required=True),
        _bool_col(f"{PUBLISHER_PREFIX}_RevalidationTriggered", "Revalidation Triggered",
                  default=False, required=True),
        _picklist_col(f"{PUBLISHER_PREFIX}_DataSource", "Data Source",
                      "fsi_mrm_datasource", required=True),
        _memo_col(f"{PUBLISHER_PREFIX}_MonitoringNotes", "Monitoring Notes",
                  max_length=10000),
    ],

    # ── fsi_mrmcomplianceevent ──────────────────────────────────────────
    "fsi_mrmcomplianceevent": [
        # NOTE: fsi_ModelInventory_Lookup — Lookup to fsi_modelinventory.
        # Requires post-deployment setup (see note above).
        _picklist_col(f"{PUBLISHER_PREFIX}_EventType", "Event Type",
                      "fsi_mrm_eventtype", required=True),
        _datetime_col(f"{PUBLISHER_PREFIX}_EventTimestamp", "Event Timestamp",
                      required=True),
        _string_col(f"{PUBLISHER_PREFIX}_TriggeredBy", "Triggered By",
                    max_length=500, required=True),
        _memo_col(f"{PUBLISHER_PREFIX}_EventDetails", "Event Details",
                  max_length=50000,
                  description="JSON payload"),
        _string_col(f"{PUBLISHER_PREFIX}_PreviousValue", "Previous Value",
                    max_length=500, required=False),
        _string_col(f"{PUBLISHER_PREFIX}_NewValue", "New Value",
                    max_length=500, required=False),
        _picklist_col(f"{PUBLISHER_PREFIX}_Sr117Pillar", "SR 11-7 Pillar",
                      "fsi_mrm_sr117pillar", required=True),
        _picklist_col(f"{PUBLISHER_PREFIX}_ComplianceImpact", "Compliance Impact",
                      "fsi_mrm_complianceimpact", required=True),
    ],
}

# ---------------------------------------------------------------------------
# Alternate key definition
# ---------------------------------------------------------------------------
ALTERNATE_KEYS = [
    {
        "EntityLogicalName": "fsi_modelinventory",
        "SchemaName": "fsi_ModelInventoryUniqueKey",
        "DisplayName": _label("Model Inventory Unique Key"),
        "KeyAttributes": ["fsi_agentid", "fsi_environmentid"],
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
        "#Microsoft.Dynamics.CRM.StringAttributeMetadata": "String",
        "#Microsoft.Dynamics.CRM.MemoAttributeMetadata": "Memo",
        "#Microsoft.Dynamics.CRM.PicklistAttributeMetadata": "Picklist",
        "#Microsoft.Dynamics.CRM.BooleanAttributeMetadata": "Boolean",
        "#Microsoft.Dynamics.CRM.DateTimeAttributeMetadata": "DateTime",
        "#Microsoft.Dynamics.CRM.IntegerAttributeMetadata": "Integer",
        "#Microsoft.Dynamics.CRM.DecimalAttributeMetadata": "Decimal",
        "#Microsoft.Dynamics.CRM.MoneyAttributeMetadata": "Money",
        "#Microsoft.Dynamics.CRM.LookupAttributeMetadata": "Lookup",
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
        lbl = _label_text(opt.get("Label", {}))
        parts.append(f"`{val}` = {lbl}")
    return ", ".join(parts)


def generate_schema_docs() -> str:
    """Generate a Markdown reference document from the in-memory schema definitions."""
    lines: list[str] = []

    # ── Header ──────────────────────────────────────────────────────────
    lines.append("# Dataverse Schema Reference")
    lines.append("")
    lines.append("> Auto-generated from `create_mrm_dataverse_schema.py`. Do not edit manually.")
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

    lines.append("### Shared Option Sets")
    lines.append("")
    for name, osdef in SHARED_OPTIONSETS.items():
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

    lines.append("### MRM Option Sets")
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

    # ── Alternate Keys ──────────────────────────────────────────────────
    lines.append("## Alternate Keys")
    lines.append("")
    lines.append("| Entity | SchemaName | Key Columns |")
    lines.append("|---|---|---|")
    for key in ALTERNATE_KEYS:
        entity = key.get("EntityLogicalName", "")
        sn = key.get("SchemaName", "")
        cols = ", ".join(key.get("KeyAttributes", []))
        lines.append(f"| {entity} | {sn} | {cols} |")
    lines.append("")

    # ── Lookup Notes ────────────────────────────────────────────────────
    lines.append("## Lookup Relationships")
    lines.append("")
    lines.append("The following lookup columns require post-deployment setup in Power Platform")
    lines.append("admin center or via the Dataverse OneToManyRelationshipMetadata API:")
    lines.append("")
    lines.append("| Child Table | Lookup Column | Parent Table |")
    lines.append("|---|---|---|")
    lines.append("| fsi_mrmriskrating | fsi_ModelInventory_Lookup | fsi_modelinventory |")
    lines.append("| fsi_validationcycle | fsi_ModelInventory_Lookup | fsi_modelinventory |")
    lines.append("| fsi_validationfinding | fsi_ValidationCycle_Lookup | fsi_validationcycle |")
    lines.append("| fsi_validationfinding | fsi_ModelInventory_Lookup | fsi_modelinventory |")
    lines.append("| fsi_monitoringrecord | fsi_ModelInventory_Lookup | fsi_modelinventory |")
    lines.append("| fsi_mrmcomplianceevent | fsi_ModelInventory_Lookup | fsi_modelinventory |")
    lines.append("")

    return "\n".join(lines)


# ---------------------------------------------------------------------------
# Deployment functions
# ---------------------------------------------------------------------------


def _build_optionset_metadata(os_def: dict) -> dict:
    """Build a Dataverse global OptionSetMetadata payload from an MRM def.

    The MRM SHARED_OPTIONSETS and OPTIONSETS dicts already use the raw
    Dataverse Web API shape (Name, DisplayName, Options as LocalizedLabels).
    This helper ensures the @odata.type annotation is present so the shared
    DataverseClient.create_global_optionset POST has an unambiguous payload
    and returns the dict otherwise unchanged.
    """
    metadata = dict(os_def)
    metadata.setdefault(
        "@odata.type", "#Microsoft.Dynamics.CRM.OptionSetMetadata"
    )
    return metadata


def _build_table_metadata(table_def: dict) -> dict:
    """Pass-through helper for MRM TABLES entries.

    Mirrors the CTSG _build_table_metadata template so future shared-client
    refactors have a stable contract layer.
    """
    return dict(table_def)


def _build_column_metadata(col_def: dict) -> dict:
    """Pass-through helper for MRM column definitions.

    The _string_col / _picklist_col / _bool_col helpers above already emit
    Dataverse-shaped payloads; this thin wrapper exists so all metadata
    handed to the shared DataverseClient flows through a single seam.
    """
    return dict(col_def)


def create_optionsets(client: DataverseClient, dry_run: bool) -> dict:
    """Create global option sets (shared and MRM-specific)."""
    print("\n=== Creating Option Sets ===")
    created = 0
    skipped = 0

    print("\nShared option sets (reused from ACV):")
    for name, metadata in SHARED_OPTIONSETS.items():
        if client.get_global_optionset(name):
            print(f"  {name}: Already exists (reusing)")
            skipped += 1
        else:
            if dry_run:
                print(f"  {name}: [DRY-RUN] Would create")
            else:
                print(f"  {name}: Creating")
                client.create_global_optionset(_build_optionset_metadata(metadata))
            created += 1

    print("\nMRM-specific option sets:")
    for name, metadata in OPTIONSETS.items():
        if client.get_global_optionset(name):
            print(f"  {name}: Already exists")
            skipped += 1
        else:
            if dry_run:
                print(f"  {name}: [DRY-RUN] Would create")
            else:
                print(f"  {name}: Creating")
                client.create_global_optionset(_build_optionset_metadata(metadata))
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
            if dry_run:
                print(f"  {table_name}: [DRY-RUN] Would create")
            else:
                print(f"  {table_name}: Creating")
                client.create_entity(_build_table_metadata(metadata))
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
                if dry_run:
                    print(f"  {schema_name}: [DRY-RUN] Would create")
                else:
                    print(f"  {schema_name}: Creating")
                    client.create_attribute(
                        table_logical_name, _build_column_metadata(column_metadata)
                    )


def create_alternate_keys(client: DataverseClient, dry_run: bool) -> dict:
    """Create alternate keys on tables.

    Uses the shared DataverseClient.ensure_entity_key() helper (idempotent)
    instead of constructing raw EntityDefinitions(...)/Keys URLs against
    client._session — that direct API access pattern coupled MRM tightly
    to per-solution client internals (council review M-4).
    """
    print("\n=== Creating Alternate Keys ===")
    created = 0
    skipped = 0
    for key_def in ALTERNATE_KEYS:
        entity = key_def["EntityLogicalName"]
        schema_name = key_def["SchemaName"]
        print(f"  {schema_name} on {entity}:")
        if dry_run:
            print(f"    [DRY-RUN] Would create alternate key {schema_name}")
            created += 1
            continue

        key_metadata = {
            "SchemaName": schema_name,
            "DisplayName": key_def["DisplayName"],
            "KeyAttributes": key_def["KeyAttributes"],
        }
        try:
            result = client.ensure_entity_key(entity, key_metadata)
            if result is None:
                print(f"    Already exists")
                skipped += 1
            else:
                print(f"    Created")
                created += 1
        except requests.HTTPError as e:
            print(f"    Error: {e}")
            skipped += 1
    return {"created": created, "skipped": skipped}


def create_schema(client: DataverseClient, dry_run: bool) -> dict:
    """Create complete schema (orchestrator)."""
    option_set_results = create_optionsets(client, dry_run)
    table_results = create_tables(client, dry_run)
    create_columns(client, dry_run)
    key_results = create_alternate_keys(client, dry_run)
    print("\n=== Schema Creation Complete ===")
    return {
        "errors": 0,
        "option_sets": option_set_results,
        "tables": table_results,
        "alternate_keys": key_results,
    }


# ---------------------------------------------------------------------------
# CLI entry point
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create Dataverse schema for Model Risk Management Automation",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--tenant-id", default=os.environ.get("MRM_TENANT_ID"),
                        help="Microsoft Entra tenant ID for interactive or legacy auth (or MRM_TENANT_ID)")
    parser.add_argument("--client-id", default=os.environ.get("MRM_CLIENT_ID"),
                        help="Legacy dev-only application ID (or set MRM_CLIENT_ID env var)")
    parser.add_argument("--client-secret", default=os.environ.get("MRM_CLIENT_SECRET"),
                        help="Legacy dev-only client secret (or set MRM_CLIENT_SECRET env var)")
    parser.add_argument("--environment-url", default=os.environ.get("MRM_ENVIRONMENT_URL"),
                        help="Dataverse environment URL (or set MRM_ENVIRONMENT_URL env var)")
    parser.add_argument("--interactive", action="store_true",
                        help="Use interactive browser authentication")
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
            "(or set MRM_ENVIRONMENT_URL env var)"
        )
    if args.client_secret and (not args.tenant_id or not args.client_id):
        parser.error(
            "legacy client-secret auth requires --tenant-id, --client-id, "
            "and --client-secret"
        )

    client_secret = args.client_secret

    # Determine auth mode: interactive > client-secret > managed-identity.
    if args.interactive:
        auth_mode = "interactive"
    elif client_secret:
        auth_mode = "client-secret"
    else:
        auth_mode = "managed-identity"

    try:
        # NOTE: We deliberately do NOT pass dry_run to DataverseClient: the
        # shared client short-circuits *reads* in dry-run mode, which would
        # defeat a meaningful preview. Reads are executed live; writes are
        # gated locally inside create_optionsets/create_tables/create_columns/
        # create_alternate_keys via the dry_run argument. Pattern lesson from
        # Wave 1 CTSG; see migrate_ctsg_optionsets_v1_1_0.py:238-267.
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            interactive=args.interactive,
            auth_mode=auth_mode,
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
