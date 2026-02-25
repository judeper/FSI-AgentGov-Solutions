#!/usr/bin/env python3
"""
Create Dataverse schema for Audit Configuration Validator.

Creates AuditValidationHistory and EnvironmentRegistry tables with all columns,
choice fields, and supporting option sets.
"""

import argparse
import os
import sys
from typing import Optional

from acv_client import ACVClient

# Publisher prefix for custom entities
PUBLISHER_PREFIX = "fsi"

# ============================================================================
# Choice (OptionSet) Definitions
# ============================================================================

OPTIONSETS = {
    "fsi_acv_severity": {
        "Name": "fsi_acv_severity",
        "DisplayName": {"LocalizedLabels": [{"Label": "Validation Severity", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Validation result severity", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Passed", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Warning", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "GracePeriod", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Failed", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "Error", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_acv_scope": {
        "Name": "fsi_acv_scope",
        "DisplayName": {"LocalizedLabels": [{"Label": "Validation Scope", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Scope of validation (tenant or environment)", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Tenant", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Environment", "LanguageCode": 1033}]}},
        ],
    },
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
    "fsi_acv_envstatus": {
        "Name": "fsi_acv_envstatus",
        "DisplayName": {"LocalizedLabels": [{"Label": "Environment Status", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Environment registry status", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Active", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Inactive", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_acv_environmenttype": {
        "Name": "fsi_acv_environmenttype",
        "DisplayName": {"LocalizedLabels": [{"Label": "Environment Type", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Power Platform environment type", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Production", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Sandbox", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Developer", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Trial", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "Default", "LanguageCode": 1033}]}},
        ],
    },
}


def create_optionsets(client: ACVClient, dry_run: bool = False) -> None:
    """Create all global option sets."""
    print("\n[Creating Global Option Sets]")

    for name, definition in OPTIONSETS.items():
        existing = client.get_global_optionset(name)
        if existing:
            print(f"  {name}: already exists, skipping")
            continue

        if dry_run:
            print(f"  {name}: would create")
        else:
            client.create_global_optionset(definition)
            print(f"  {name}: created")


# ============================================================================
# Table Definitions
# ============================================================================

def get_audit_validation_history_entity() -> dict:
    """
    Get AuditValidationHistory entity definition.

    CRITICAL: OwnershipType is OrganizationOwned for immutability.
    Security roles must remove Write/Delete privileges post-deployment.
    """
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.EntityMetadata",
        "SchemaName": "fsi_AuditValidationHistory",
        "DisplayName": {"LocalizedLabels": [{"Label": "Audit Validation History", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Audit Validation History", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Immutable audit validation results for regulatory evidence", "LanguageCode": 1033}]},
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
                "Description": {"LocalizedLabels": [{"Label": "ENV-{name}-{timestamp} or TENANT-{timestamp}", "LanguageCode": 1033}]},
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "MaxLength": 200,
                "FormatName": {"Value": "Text"},
            },
        ],
    }


def get_environment_registry_entity() -> dict:
    """Get EnvironmentRegistry entity definition."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.EntityMetadata",
        "SchemaName": "fsi_EnvironmentRegistry",
        "DisplayName": {"LocalizedLabels": [{"Label": "Environment Registry", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Environment Registry", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Administrator-managed catalog of Power Platform environments", "LanguageCode": 1033}]},
        "OwnershipType": "OrganizationOwned",
        "IsActivity": False,
        "HasActivities": False,
        "HasNotes": False,
        "IsAuditEnabled": {"Value": True},
        "PrimaryNameAttribute": "fsi_name",
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": "fsi_Name",
                "DisplayName": {"LocalizedLabels": [{"Label": "Environment Name", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Environment display name", "LanguageCode": 1033}]},
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "MaxLength": 200,
                "FormatName": {"Value": "Text"},
            },
        ],
    }


# ============================================================================
# Column Definitions
# ============================================================================

HISTORY_TABLE_COLUMNS = [
    # Correlation and Scope
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_RunId",
        "DisplayName": {"LocalizedLabels": [{"Label": "Run ID", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "GUID correlating all records in one execution run", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "MaxLength": 36,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_Scope",
        "DisplayName": {"LocalizedLabels": [{"Label": "Scope", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_scope')",
    },
    # Environment Context (optional for tenant-scope validations)
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_EnvironmentId",
        "DisplayName": {"LocalizedLabels": [{"Label": "Environment ID", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Power Platform environment ID (null for tenant scope)", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 100,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_EnvironmentName",
        "DisplayName": {"LocalizedLabels": [{"Label": "Environment Name", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Display name for readability", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 200,
        "FormatName": {"Value": "Text"},
    },
    # Zone Classification (denormalized per user decision)
    {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_Zone",
        "DisplayName": {"LocalizedLabels": [{"Label": "Zone", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Zone at time of validation (denormalized)", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_zone')",
    },
    # Validation Result
    {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_Severity",
        "DisplayName": {"LocalizedLabels": [{"Label": "Severity", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Overall validation result", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_severity')",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_ValidationType",
        "DisplayName": {"LocalizedLabels": [{"Label": "Validation Type", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "UnifiedAuditLog, MailboxAudit, PurviewRetention, EnvironmentAudit, EnvironmentRetention, Orchestrator", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "MaxLength": 100,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_RawValue",
        "DisplayName": {"LocalizedLabels": [{"Label": "Raw Value", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Actual config values checked (e.g., AuditEnabled=true,RetentionDays=90)", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 4000,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_Reason",
        "DisplayName": {"LocalizedLabels": [{"Label": "Reason", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Human-readable explanation", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 4000,
        "FormatName": {"Value": "Text"},
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_RemediationHint",
        "DisplayName": {"LocalizedLabels": [{"Label": "Remediation Hint", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Suggested fix for Phase 3 alerting", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 2000,
        "FormatName": {"Value": "Text"},
    },
    # Metadata
    {
        "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": "fsi_Timestamp",
        "DisplayName": {"LocalizedLabels": [{"Label": "Timestamp", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "When validation ran", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "Format": "DateAndTime",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
        "SchemaName": "fsi_CheckCount",
        "DisplayName": {"LocalizedLabels": [{"Label": "Check Count", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Number of individual checks in this result", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MinValue": 0,
        "MaxValue": 999999,
    },
]


REGISTRY_TABLE_COLUMNS = [
    # Environment Identification
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_EnvironmentId",
        "DisplayName": {"LocalizedLabels": [{"Label": "Environment ID", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Power Platform environment GUID (unique)", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "MaxLength": 100,
        "FormatName": {"Value": "Text"},
    },
    # Zone Classification
    {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_Zone",
        "DisplayName": {"LocalizedLabels": [{"Label": "Zone", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Assigned governance zone (Unclassified triggers alert)", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_zone')",
    },
    # Environment Metadata
    {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_Status",
        "DisplayName": {"LocalizedLabels": [{"Label": "Status", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_envstatus')",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_EnvironmentType",
        "DisplayName": {"LocalizedLabels": [{"Label": "Environment Type", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_environmenttype')",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_EnvironmentUrl",
        "DisplayName": {"LocalizedLabels": [{"Label": "Environment URL", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Dataverse URL for API calls", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 500,
        "FormatName": {"Value": "Url"},
    },
    # Tracking
    {
        "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": "fsi_DiscoveredOn",
        "DisplayName": {"LocalizedLabels": [{"Label": "Discovered On", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "When first discovered by API", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "Format": "DateAndTime",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": "fsi_LastValidated",
        "DisplayName": {"LocalizedLabels": [{"Label": "Last Validated", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Last successful validation timestamp", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "Format": "DateAndTime",
    },
    # Admin Override
    {
        "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
        "SchemaName": "fsi_OverrideInclude",
        "DisplayName": {"LocalizedLabels": [{"Label": "Override Include", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Admin override to include Trial/Dev environments", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "DefaultValue": False,
    },
    # Notes
    {
        "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
        "SchemaName": "fsi_Notes",
        "DisplayName": {"LocalizedLabels": [{"Label": "Notes", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Admin notes", "LanguageCode": 1033}]},
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 2000,
    },
]


def create_tables(client: ACVClient, dry_run: bool = False) -> None:
    """Create ACV tables with primary name attributes."""
    print("\n[Creating Tables]")

    # Create AuditValidationHistory table
    history_logical_name = "fsi_auditvalidationhistory"
    existing = client.get_entity_metadata(history_logical_name)
    if existing:
        print(f"  {history_logical_name}: already exists")
    elif dry_run:
        print(f"  {history_logical_name}: would create (Org-owned, auditing enabled, immutable)")
    else:
        client.create_entity(get_audit_validation_history_entity())
        print(f"  {history_logical_name}: created")

    # Create EnvironmentRegistry table
    registry_logical_name = "fsi_environmentregistry"
    existing = client.get_entity_metadata(registry_logical_name)
    if existing:
        print(f"  {registry_logical_name}: already exists")
    elif dry_run:
        print(f"  {registry_logical_name}: would create (Org-owned, auditing enabled)")
    else:
        client.create_entity(get_environment_registry_entity())
        print(f"  {registry_logical_name}: created")


def create_columns(client: ACVClient, dry_run: bool = False) -> None:
    """Create columns on ACV tables."""
    print("\n[Creating Columns]")

    # AuditValidationHistory columns
    print("  AuditValidationHistory columns:")
    for col in HISTORY_TABLE_COLUMNS:
        col_name = col["SchemaName"].lower()
        existing = client.get_attribute_metadata("fsi_auditvalidationhistory", col_name)
        if existing:
            print(f"    {col_name}: already exists")
        elif dry_run:
            print(f"    {col_name}: would create")
        else:
            client.create_attribute("fsi_auditvalidationhistory", col)
            print(f"    {col_name}: created")

    # EnvironmentRegistry columns
    print("  EnvironmentRegistry columns:")
    for col in REGISTRY_TABLE_COLUMNS:
        col_name = col["SchemaName"].lower()
        existing = client.get_attribute_metadata("fsi_environmentregistry", col_name)
        if existing:
            print(f"    {col_name}: already exists")
        elif dry_run:
            print(f"    {col_name}: would create")
        else:
            client.create_attribute("fsi_environmentregistry", col)
            print(f"    {col_name}: created")


def create_schema(client: ACVClient, dry_run: bool = False) -> None:
    """
    Create complete Dataverse schema for ACV.

    Prints deployment progress to stdout.
    """
    print("=" * 60)
    print("ACV Dataverse Schema Deployment")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN - No changes will be made ***\n")

    # Step 1: Create option sets (must exist before tables reference them)
    create_optionsets(client, dry_run)

    # Step 2: Create tables
    create_tables(client, dry_run)

    # Step 3: Create columns
    create_columns(client, dry_run)

    print("\n" + "=" * 60)
    if dry_run:
        print("DRY RUN COMPLETE - Review output above")
    else:
        print("SCHEMA DEPLOYMENT COMPLETE")
    print("=" * 60)


def main():
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Create Dataverse schema for ACV",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ACV_TENANT_ID"),
        help="Entra ID tenant ID",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ACV_CLIENT_ID"),
        help="Application (client) ID",
    )
    # Client secret read from ACV_CLIENT_SECRET env var (not CLI arg to avoid shell history exposure)
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ACV_ENVIRONMENT_URL"),
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

    # Validate auth mode
    if not args.interactive and not args.client_id:
        parser.error(
            "Either --interactive or --client-id is required.\n"
            "Use --interactive for manual runs or provide Service Principal credentials."
        )
    if args.interactive and not args.client_id:
        parser.error(
            "--client-id is required for interactive authentication.\n"
            "Register an app in Entra ID and provide --client-id."
        )

    # Get client secret from env var or prompt (never via CLI arg to avoid shell history exposure)
    client_secret = os.environ.get("ACV_CLIENT_SECRET")
    if not args.interactive and args.client_id and not client_secret:
        import getpass
        client_secret = getpass.getpass("Client secret: ")

    try:
        client = ACVClient(
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
