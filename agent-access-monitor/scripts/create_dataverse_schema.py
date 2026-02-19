#!/usr/bin/env python3
"""
Create Dataverse schema for Agent Access Governance Monitor.

Creates AccessBaseline, AccessValidationHistory, and AccessViolation tables
with all columns and supporting option sets. Reuses shared option sets
(fsi_acv_zone, fsi_acv_severity) from ACV where they already exist.
"""

import argparse
import os
import sys
from typing import Optional

from aam_client import AAMClient

# Publisher prefix for custom entities
PUBLISHER_PREFIX = "fsi"

# ============================================================================
# Shared Option Set Definitions (existence check — create only if missing)
# These are shared with ACV and may already exist in the environment.
# ============================================================================

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
    "fsi_acv_severity": {
        "Name": "fsi_acv_severity",
        "DisplayName": {"LocalizedLabels": [{"Label": "Validation Severity", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Validation result severity", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Critical", "LanguageCode": 1033}]}},
            {"Value": 2, "Label": {"LocalizedLabels": [{"Label": "High", "LanguageCode": 1033}]}},
            {"Value": 3, "Label": {"LocalizedLabels": [{"Label": "Warning", "LanguageCode": 1033}]}},
            {"Value": 4, "Label": {"LocalizedLabels": [{"Label": "Info", "LanguageCode": 1033}]}},
        ],
    },
}


def create_shared_optionsets(client: AAMClient, dry_run: bool = False) -> tuple:
    """
    Check for shared option sets and create only if missing.

    These option sets are shared with ACV and may already exist in the
    Dataverse environment. This function is idempotent.

    Returns:
        Tuple of (created_count, skipped_count)
    """
    print("\n[Checking Shared Option Sets]")
    created = 0
    skipped = 0

    for name, definition in SHARED_OPTIONSETS.items():
        existing = client.get_global_optionset(name)
        if existing:
            print(f"  {name}: already exists (shared with ACV), skipping")
            skipped += 1
            continue

        if dry_run:
            print(f"  {name}: would create (not found in environment)")
        else:
            client.create_global_optionset(definition)
            print(f"  {name}: created (not found in environment)")
        created += 1

    return created, skipped


# ============================================================================
# Table Definitions
# ============================================================================

def get_access_baseline_entity() -> dict:
    """
    Get AccessBaseline entity definition.

    UserOwned table storing per-environment access setting snapshots.
    """
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.EntityMetadata",
        "SchemaName": "fsi_AccessBaseline",
        "DisplayName": {"LocalizedLabels": [{"Label": "Access Baseline", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Access Baselines", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Per-environment access setting snapshots for governance monitoring", "LanguageCode": 1033}]},
        "OwnershipType": "UserOwned",
        "IsActivity": False,
        "HasActivities": False,
        "HasNotes": False,
        "IsAuditEnabled": {"Value": True},
        "PrimaryNameAttribute": "fsi_name",
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": "fsi_Name",
                "DisplayName": {"LocalizedLabels": [{"Label": "Baseline Name", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Baseline identifier (environment name + timestamp)", "LanguageCode": 1033}]},
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "MaxLength": 200,
                "FormatName": {"Value": "Text"},
            },
        ],
    }


def get_validation_history_entity() -> dict:
    """
    Get AccessValidationHistory entity definition.

    CRITICAL: OwnershipType is OrganizationOwned for immutability.
    Immutable audit log for FINRA 4511/SEC 17a-3 compliance evidence.
    Security roles must remove Write/Delete privileges post-deployment.
    """
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.EntityMetadata",
        "SchemaName": "fsi_AccessValidationHistory",
        "EntitySetName": "fsi_accessvalidationhistory",
        "DisplayName": {"LocalizedLabels": [{"Label": "Access Validation History", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Access Validation History", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Immutable access validation audit log for FINRA 4511/SEC 17a-3 regulatory evidence", "LanguageCode": 1033}]},
        "OwnershipType": "OrganizationOwned",  # CRITICAL: immutability requires org-owned
        "IsActivity": False,
        "HasActivities": False,
        "HasNotes": False,
        "IsAuditEnabled": {"Value": True},
        "PrimaryNameAttribute": "fsi_name",
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": "fsi_Name",
                "DisplayName": {"LocalizedLabels": [{"Label": "Validation ID", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Validation run identifier", "LanguageCode": 1033}]},
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "MaxLength": 200,
                "FormatName": {"Value": "Text"},
            },
        ],
    }


def get_access_violation_entity() -> dict:
    """
    Get AccessViolation entity definition.

    UserOwned table storing individual access policy violations.
    """
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.EntityMetadata",
        "SchemaName": "fsi_AccessViolation",
        "DisplayName": {"LocalizedLabels": [{"Label": "Access Violation", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Access Violations", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Individual access policy violations detected during governance monitoring", "LanguageCode": 1033}]},
        "OwnershipType": "UserOwned",
        "IsActivity": False,
        "HasActivities": False,
        "HasNotes": False,
        "IsAuditEnabled": {"Value": True},
        "PrimaryNameAttribute": "fsi_name",
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": "fsi_Name",
                "DisplayName": {"LocalizedLabels": [{"Label": "Violation ID", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Violation identifier", "LanguageCode": 1033}]},
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "MaxLength": 200,
                "FormatName": {"Value": "Text"},
            },
        ],
    }


# ============================================================================
# Column Definitions
# ============================================================================

# --- AccessBaseline columns ---
BASELINE_TABLE_COLUMNS = [
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_environment_guid",
        "DisplayName": {"LocalizedLabels": [{"Label": "Environment GUID", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Power Platform environment GUID", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "MaxLength": 100,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_environment_name",
        "DisplayName": {"LocalizedLabels": [{"Label": "Environment Name", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Environment display name", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "MaxLength": 500,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_zone",
        "DisplayName": {"LocalizedLabels": [{"Label": "Zone", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Governance zone classification", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_zone')",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_bot_limit_sharing_mode",
        "DisplayName": {"LocalizedLabels": [{"Label": "Bot Limit Sharing Mode", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Bot sharing limitation mode setting", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "MaxLength": 200,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
        "SchemaName": "fsi_bot_authoring_sharing_disabled",
        "DisplayName": {"LocalizedLabels": [{"Label": "Bot Authoring Sharing Disabled", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Whether bot authoring sharing is disabled", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "DefaultValue": False,
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_bot_published_limit_sharing_mode",
        "DisplayName": {"LocalizedLabels": [{"Label": "Published Bot Limit Sharing Mode", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Published bot sharing limitation mode setting", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "MaxLength": 200,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
        "SchemaName": "fsi_is_active",
        "DisplayName": {"LocalizedLabels": [{"Label": "Is Active", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Whether this baseline is the current active baseline", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "DefaultValue": True,
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": "fsi_captured_at",
        "DisplayName": {"LocalizedLabels": [{"Label": "Captured At", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "When the baseline snapshot was captured", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "Format": "DateAndTime",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_captured_by",
        "DisplayName": {"LocalizedLabels": [{"Label": "Captured By", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Identity that captured the baseline", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 200,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
        "SchemaName": "fsi_raw_json",
        "DisplayName": {"LocalizedLabels": [{"Label": "Raw JSON", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Full JSON payload of access settings at capture time", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 100000,
    },
]

# --- AccessValidationHistory columns ---
HISTORY_TABLE_COLUMNS = [
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_run_id",
        "DisplayName": {"LocalizedLabels": [{"Label": "Run ID", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "GUID correlating all records in one execution run", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "MaxLength": 36,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_zone",
        "DisplayName": {"LocalizedLabels": [{"Label": "Zone", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Governance zone at time of validation", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_zone')",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_severity",
        "DisplayName": {"LocalizedLabels": [{"Label": "Severity", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Overall validation result severity", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_severity')",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
        "SchemaName": "fsi_total_environments",
        "DisplayName": {"LocalizedLabels": [{"Label": "Total Environments", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Number of environments evaluated in this run", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MinValue": 0,
        "MaxValue": 999999,
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
        "SchemaName": "fsi_compliant_count",
        "DisplayName": {"LocalizedLabels": [{"Label": "Compliant Count", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Number of environments that passed validation", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MinValue": 0,
        "MaxValue": 999999,
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
        "SchemaName": "fsi_violation_count",
        "DisplayName": {"LocalizedLabels": [{"Label": "Violation Count", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Number of environments with violations", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MinValue": 0,
        "MaxValue": 999999,
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_overall_status",
        "DisplayName": {"LocalizedLabels": [{"Label": "Overall Status", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Aggregate validation status (e.g., Passed, Failed, Warning)", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "MaxLength": 50,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
        "SchemaName": "fsi_summary_json",
        "DisplayName": {"LocalizedLabels": [{"Label": "Summary JSON", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Full JSON summary of validation results", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 100000,
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": "fsi_validation_time",
        "DisplayName": {"LocalizedLabels": [{"Label": "Validation Time", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "When validation was executed", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "Format": "DateAndTime",
    },
]

# --- AccessViolation columns ---
VIOLATION_TABLE_COLUMNS = [
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_run_id",
        "DisplayName": {"LocalizedLabels": [{"Label": "Run ID", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "GUID correlating this violation to a validation run", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 36,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_environment_guid",
        "DisplayName": {"LocalizedLabels": [{"Label": "Environment GUID", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Power Platform environment GUID", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "MaxLength": 100,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_environment_name",
        "DisplayName": {"LocalizedLabels": [{"Label": "Environment Name", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Environment display name", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "MaxLength": 500,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_zone",
        "DisplayName": {"LocalizedLabels": [{"Label": "Zone", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Governance zone classification", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_zone')",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_severity",
        "DisplayName": {"LocalizedLabels": [{"Label": "Severity", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Violation severity level", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_severity')",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_violation_type",
        "DisplayName": {"LocalizedLabels": [{"Label": "Violation Type", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Type of access policy violation detected", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "MaxLength": 200,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_expected_value",
        "DisplayName": {"LocalizedLabels": [{"Label": "Expected Value", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Expected configuration value per governance policy", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "MaxLength": 2000,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_actual_value",
        "DisplayName": {"LocalizedLabels": [{"Label": "Actual Value", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Actual configuration value found in environment", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "MaxLength": 2000,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_regulatory_context",
        "DisplayName": {"LocalizedLabels": [{"Label": "Regulatory Context", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Regulatory requirement context (e.g., FINRA 4511, SEC 17a-3)", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 2000,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": "fsi_detected_at",
        "DisplayName": {"LocalizedLabels": [{"Label": "Detected At", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "When the violation was detected", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "Format": "DateAndTime",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
        "SchemaName": "fsi_acknowledged",
        "DisplayName": {"LocalizedLabels": [{"Label": "Acknowledged", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Whether the violation has been acknowledged by an administrator", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "DefaultValue": False,
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_acknowledged_by",
        "DisplayName": {"LocalizedLabels": [{"Label": "Acknowledged By", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Identity that acknowledged the violation", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 200,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": "fsi_acknowledged_on",
        "DisplayName": {"LocalizedLabels": [{"Label": "Acknowledged On", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "When the violation was acknowledged", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "Format": "DateAndTime",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": "fsi_resolved_at",
        "DisplayName": {"LocalizedLabels": [{"Label": "Resolved At", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "When the violation was resolved", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "Format": "DateAndTime",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
        "SchemaName": "fsi_notes",
        "DisplayName": {"LocalizedLabels": [{"Label": "Notes", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Administrator notes on this violation", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 2000,
    },
]


# ============================================================================
# Schema Deployment Functions
# ============================================================================

def create_tables(client: AAMClient, dry_run: bool = False) -> tuple:
    """Create AAM tables with primary name attributes.

    Returns:
        Tuple of (created_count, skipped_count)
    """
    print("\n[Creating Tables]")
    created = 0
    skipped = 0

    # Create AccessBaseline table
    baseline_logical_name = "fsi_accessbaseline"
    existing = client.get_entity_metadata(baseline_logical_name)
    if existing:
        print(f"  {baseline_logical_name}: already exists")
        skipped += 1
    elif dry_run:
        print(f"  {baseline_logical_name}: would create (User-owned, auditing enabled)")
        created += 1
    else:
        client.create_entity(get_access_baseline_entity())
        print(f"  {baseline_logical_name}: created")
        created += 1

    # Create AccessValidationHistory table
    history_logical_name = "fsi_accessvalidationhistory"
    existing = client.get_entity_metadata(history_logical_name)
    if existing:
        print(f"  {history_logical_name}: already exists")
        skipped += 1
    elif dry_run:
        print(f"  {history_logical_name}: would create (Org-owned, auditing enabled, immutable)")
        created += 1
    else:
        client.create_entity(get_validation_history_entity())
        print(f"  {history_logical_name}: created")
        created += 1

    # Create AccessViolation table
    violation_logical_name = "fsi_accessviolation"
    existing = client.get_entity_metadata(violation_logical_name)
    if existing:
        print(f"  {violation_logical_name}: already exists")
        skipped += 1
    elif dry_run:
        print(f"  {violation_logical_name}: would create (User-owned, auditing enabled)")
        created += 1
    else:
        client.create_entity(get_access_violation_entity())
        print(f"  {violation_logical_name}: created")
        created += 1

    return created, skipped


def create_columns(client: AAMClient, dry_run: bool = False) -> tuple:
    """Create columns on AAM tables.

    Returns:
        Tuple of (created_count, skipped_count)
    """
    print("\n[Creating Columns]")
    created = 0
    skipped = 0

    # AccessBaseline columns
    print("  AccessBaseline columns:")
    for col in BASELINE_TABLE_COLUMNS:
        col_name = col["SchemaName"].lower()
        existing = client.get_attribute_metadata("fsi_accessbaseline", col_name)
        if existing:
            print(f"    {col_name}: already exists")
            skipped += 1
        elif dry_run:
            print(f"    {col_name}: would create")
            created += 1
        else:
            client.create_attribute("fsi_accessbaseline", col)
            print(f"    {col_name}: created")
            created += 1

    # AccessValidationHistory columns
    print("  AccessValidationHistory columns:")
    for col in HISTORY_TABLE_COLUMNS:
        col_name = col["SchemaName"].lower()
        existing = client.get_attribute_metadata("fsi_accessvalidationhistory", col_name)
        if existing:
            print(f"    {col_name}: already exists")
            skipped += 1
        elif dry_run:
            print(f"    {col_name}: would create")
            created += 1
        else:
            client.create_attribute("fsi_accessvalidationhistory", col)
            print(f"    {col_name}: created")
            created += 1

    # AccessViolation columns
    print("  AccessViolation columns:")
    for col in VIOLATION_TABLE_COLUMNS:
        col_name = col["SchemaName"].lower()
        existing = client.get_attribute_metadata("fsi_accessviolation", col_name)
        if existing:
            print(f"    {col_name}: already exists")
            skipped += 1
        elif dry_run:
            print(f"    {col_name}: would create")
            created += 1
        else:
            client.create_attribute("fsi_accessviolation", col)
            print(f"    {col_name}: created")
            created += 1

    return created, skipped


def create_schema(client: AAMClient, dry_run: bool = False) -> dict:
    """
    Create complete Dataverse schema for AAM.

    Returns:
        Results dict with success/failure counts
    """
    print("=" * 60)
    print("AAM Dataverse Schema Deployment")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN - No changes will be made ***\n")

    results = {
        "optionsets_created": 0,
        "optionsets_skipped": 0,
        "tables_created": 0,
        "tables_skipped": 0,
        "columns_created": 0,
        "columns_skipped": 0,
    }

    # Step 1: Check/create shared option sets (must exist before tables reference them)
    os_created, os_skipped = create_shared_optionsets(client, dry_run)
    results["optionsets_created"] = os_created
    results["optionsets_skipped"] = os_skipped

    # Step 2: Create tables
    tbl_created, tbl_skipped = create_tables(client, dry_run)
    results["tables_created"] = tbl_created
    results["tables_skipped"] = tbl_skipped

    # Step 3: Create columns
    col_created, col_skipped = create_columns(client, dry_run)
    results["columns_created"] = col_created
    results["columns_skipped"] = col_skipped

    print("\n" + "=" * 60)
    if dry_run:
        print("DRY RUN COMPLETE - Review output above")
    else:
        print("SCHEMA DEPLOYMENT COMPLETE")
    print("=" * 60)

    return results


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Create Dataverse schema for Agent Access Governance Monitor",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("AAM_TENANT_ID"),
        help="Entra ID tenant ID",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("AAM_CLIENT_ID"),
        help="Application (client) ID",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("AAM_CLIENT_SECRET"),
        help="Client secret",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("AAM_ENVIRONMENT_URL"),
        help="Dataverse environment URL",
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
    if not args.tenant_id or not args.environment_url:
        parser.error("--tenant-id and --environment-url are required")

    # Get client secret if needed
    client_secret = args.client_secret
    if not args.interactive and not client_secret:
        if args.client_id:
            import getpass
            client_secret = getpass.getpass("Client secret: ")

    try:
        client = AAMClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            interactive=args.interactive,
            dry_run=args.dry_run,
        )

        create_schema(client, dry_run=args.dry_run)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
