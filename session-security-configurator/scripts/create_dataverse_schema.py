#!/usr/bin/env python3
"""
Create Dataverse schema for Session Security Configurator.

Creates SessionBaseline, ValidationHistory, and DriftViolation tables with all columns,
choice fields, and supporting option sets. Reuses shared ACV option sets (fsi_acv_zone,
fsi_acv_severity) when present.
"""

import argparse
import os
import sys
from typing import Optional

from ssc_client import SSCClient

PUBLISHER_PREFIX = "fsi"

# Shared option sets (reused from ACV) - only create if missing
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
    "fsi_acv_severity": {
        "Name": "fsi_acv_severity",
        "DisplayName": {"LocalizedLabels": [{"Label": "Validation Severity", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Validation result severity", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Passed", "LanguageCode": 1033}]}},
            {"Value": 2, "Label": {"LocalizedLabels": [{"Label": "Warning", "LanguageCode": 1033}]}},
            {"Value": 3, "Label": {"LocalizedLabels": [{"Label": "GracePeriod", "LanguageCode": 1033}]}},
            {"Value": 4, "Label": {"LocalizedLabels": [{"Label": "Failed", "LanguageCode": 1033}]}},
            {"Value": 5, "Label": {"LocalizedLabels": [{"Label": "Error", "LanguageCode": 1033}]}},
        ],
    },
}

# SSC-specific option sets
OPTIONSETS = {
    "fsi_ssc_validationtype": {
        "Name": "fsi_ssc_validationtype",
        "DisplayName": {"LocalizedLabels": [{"Label": "Session Validation Type", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Type of session security validation", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "SessionControls", "LanguageCode": 1033}]}},
            {"Value": 2, "Label": {"LocalizedLabels": [{"Label": "AuthStrength", "LanguageCode": 1033}]}},
            {"Value": 3, "Label": {"LocalizedLabels": [{"Label": "PIMSettings", "LanguageCode": 1033}]}},
            {"Value": 4, "Label": {"LocalizedLabels": [{"Label": "BreakGlass", "LanguageCode": 1033}]}},
            {"Value": 5, "Label": {"LocalizedLabels": [{"Label": "ConflictAudit", "LanguageCode": 1033}]}},
            {"Value": 6, "Label": {"LocalizedLabels": [{"Label": "Orchestrator", "LanguageCode": 1033}]}},
        ],
    },
}

# Table definitions
TABLES = {
    "fsi_SessionBaseline": {
        "SchemaName": "fsi_SessionBaseline",
        "DisplayName": {"LocalizedLabels": [{"Label": "Session Baseline", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Session Baselines", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Zone-specific session security baseline configurations", "LanguageCode": 1033}]},
        "OwnershipType": "UserOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": f"{PUBLISHER_PREFIX}_Name",
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "DisplayName": {"LocalizedLabels": [{"Label": "Baseline ID", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Baseline identifier like Zone1-2026-02-07", "LanguageCode": 1033}]},
                "MaxLength": 200,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_name",
    },
    "fsi_ValidationHistory": {
        "SchemaName": "fsi_ValidationHistory",
        "DisplayName": {"LocalizedLabels": [{"Label": "Validation History", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Validation History", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Immutable audit log of session security validations", "LanguageCode": 1033}]},
        "OwnershipType": "OrganizationOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": f"{PUBLISHER_PREFIX}_Name",
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "DisplayName": {"LocalizedLabels": [{"Label": "Validation ID", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Validation identifier like Zone3-2026-02-07T14:30:00Z", "LanguageCode": 1033}]},
                "MaxLength": 200,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_name",
    },
    "fsi_DriftViolation": {
        "SchemaName": "fsi_DriftViolation",
        "DisplayName": {"LocalizedLabels": [{"Label": "Drift Violation", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Drift Violations", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Session security drift violations requiring operator attention", "LanguageCode": 1033}]},
        "OwnershipType": "UserOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": f"{PUBLISHER_PREFIX}_Name",
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "DisplayName": {"LocalizedLabels": [{"Label": "Violation ID", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Violation identifier like Zone2-DRIFT-2026-02-07T14:30:00Z", "LanguageCode": 1033}]},
                "MaxLength": 200,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_name",
    },
}

# Column definitions for each table
COLUMNS = {
    "fsi_sessionbaseline": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Zone",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Zone", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Governance zone classification", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_zone')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_SignInFrequencyMinutes",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Sign-In Frequency (Minutes)", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Expected sign-in frequency in minutes", "LanguageCode": 1033}]},
            "MinValue": 0,
            "MaxValue": 999999,
            "Format": "None",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AuthStrength",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Auth Strength", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Expected auth strength: standard, passwordless, phishing-resistant", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_RequireCompliantDevice",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Require Compliant Device", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether compliant device is required", "LanguageCode": 1033}]},
            "DefaultValue": False,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_PIMMaxActivationHours",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "PIM Max Activation Hours", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Max PIM activation duration in hours", "LanguageCode": 1033}]},
            "MinValue": 0,
            "MaxValue": 999999,
            "Format": "None",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_PIMRequireApproval",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "PIM Require Approval", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether PIM activation requires approval", "LanguageCode": 1033}]},
            "DefaultValue": False,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_PIMRequireAuthContext",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "PIM Require Auth Context", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether PIM activation requires auth context", "LanguageCode": 1033}]},
            "DefaultValue": False,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_IsActive",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Is Active", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether this baseline is the current active baseline for the zone", "LanguageCode": 1033}]},
            "DefaultValue": True,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_CapturedOn",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Captured On", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When baseline was captured", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_RawJson",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Raw JSON", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Full JSON snapshot of CA session settings at capture time", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
    ],
    "fsi_validationhistory": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_RunId",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Run ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "GUID correlating all records in one execution run", "LanguageCode": 1033}]},
            "MaxLength": 36,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Zone",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Zone", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Governance zone classification", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_zone')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Severity",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Severity", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Validation result severity", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_severity')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ValidationType",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Validation Type", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Type of session security validation", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_ssc_validationtype')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_RawValue",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Raw Value", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Actual config values checked", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Reason",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Reason", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Human-readable explanation", "LanguageCode": 1033}]},
            "MaxLength": 4000,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_RemediationHint",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Remediation Hint", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Suggested fix for alerting", "LanguageCode": 1033}]},
            "MaxLength": 2000,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Timestamp",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Timestamp", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When validation ran", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_CheckCount",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Check Count", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Number of individual checks", "LanguageCode": 1033}]},
            "MinValue": 0,
            "MaxValue": 999999,
            "Format": "None",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_BaselineId",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Baseline ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Reference to baseline used for comparison", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
    ],
    "fsi_driftviolation": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Zone",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Zone", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Governance zone classification", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_zone')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Severity",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Severity", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Violation severity", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_severity')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_DriftType",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Drift Type", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Type of drift: SignInFrequencyWeakened, AuthStrengthDowngraded, PolicyDisabled, ExclusionAdded", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ExpectedValue",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Expected Value", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Expected configuration per baseline", "LanguageCode": 1033}]},
            "MaxLength": 2000,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ActualValue",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Actual Value", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Actual configuration found", "LanguageCode": 1033}]},
            "MaxLength": 2000,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_PolicyId",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Policy ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "CA policy ID that drifted", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_PolicyName",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Policy Name", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "CA policy display name", "LanguageCode": 1033}]},
            "MaxLength": 500,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_DetectedOn",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Detected On", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When drift was detected", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Acknowledged",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Acknowledged", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether operator has reviewed", "LanguageCode": 1033}]},
            "DefaultValue": False,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AcknowledgedBy",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Acknowledged By", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "UPN of acknowledging operator", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AcknowledgedOn",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Acknowledged On", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When acknowledged", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Notes",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Notes", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Operator notes on violation", "LanguageCode": 1033}]},
            "MaxLength": 2000,
            "Format": "Text",
        },
    ],
}


def create_optionsets(client: SSCClient, dry_run: bool) -> dict:
    """Create global option sets (shared and SSC-specific)."""
    print("\n=== Creating Option Sets ===")
    created = 0
    skipped = 0

    # Check and create shared option sets (fsi_acv_zone, fsi_acv_severity)
    print("\nShared option sets (reused from ACV):")
    for name, metadata in SHARED_OPTIONSETS.items():
        if client.get_global_optionset(name):
            print(f"  {name}: Already exists (reusing)")
            skipped += 1
        else:
            print(f"  {name}: Creating")
            client.create_option_set(metadata)
            created += 1

    # Create SSC-specific option sets
    print("\nSSC-specific option sets:")
    for name, metadata in OPTIONSETS.items():
        if client.get_global_optionset(name):
            print(f"  {name}: Already exists")
            skipped += 1
        else:
            print(f"  {name}: Creating")
            client.create_option_set(metadata)
            created += 1

    return {"created": created, "skipped": skipped}


def create_tables(client: SSCClient, dry_run: bool) -> dict:
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
            client.create_table(metadata)
            created += 1
    return {"created": created, "skipped": skipped}


def create_columns(client: SSCClient, dry_run: bool) -> None:
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
                client.create_column(table_logical_name, column_metadata)


def create_schema(client: SSCClient, dry_run: bool) -> dict:
    """Create complete schema (orchestrator)."""
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
    parser = argparse.ArgumentParser(
        description="Create Dataverse schema for Session Security Configurator",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--tenant-id", default=os.environ.get("SSC_TENANT_ID"), help="Entra ID tenant ID (or set SSC_TENANT_ID env var)")
    parser.add_argument("--client-id", default=os.environ.get("SSC_CLIENT_ID"), help="Application (client) ID (or set SSC_CLIENT_ID env var)")
    parser.add_argument("--client-secret", default=os.environ.get("SSC_CLIENT_SECRET"), help="Client secret (or set SSC_CLIENT_SECRET env var)")
    parser.add_argument("--environment-url", default=os.environ.get("SSC_ENVIRONMENT_URL"), help="Dataverse environment URL (or set SSC_ENVIRONMENT_URL env var)")
    parser.add_argument("--interactive", action="store_true", help="Use interactive browser authentication")
    parser.add_argument("--dry-run", action="store_true", help="Preview schema operations without API calls")
    args = parser.parse_args()

    if not args.tenant_id or not args.environment_url:
        parser.error("Missing required arguments. Provide --tenant-id and --environment-url (or set SSC_TENANT_ID and SSC_ENVIRONMENT_URL env vars)")
    if not args.client_id:
        parser.error("--client-id is required (or set SSC_CLIENT_ID env var)")

    client_secret = args.client_secret
    if not args.interactive:
        if not client_secret:
            import getpass
            client_secret = getpass.getpass("Client secret: ")

    try:
        client = SSCClient(
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
