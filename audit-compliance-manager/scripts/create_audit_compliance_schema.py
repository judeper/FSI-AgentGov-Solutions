#!/usr/bin/env python3
"""
Create Dataverse schema for Audit Logging Compliance Automation (ALCA).

Creates the fsi_auditenvironmentcompliance table with all columns,
the fsi_alca_compliancestatus choice field, and an alternate key
on fsi_environmentid for upsert support.

Table: fsi_auditenvironmentcompliance
  - Display Name: Audit Environment Compliance
  - Primary Column: fsi_environmentname (environment display name)
  - Ownership: Organization-owned
  - Auditing: Enabled

Columns:
  - fsi_environmentid      Single Line Text (upsert key)
  - fsi_environmentname    Single Line Text (primary name)
  - fsi_auditenabled       Yes/No (Purview unified audit)
  - fsi_dataverseauditenabled  Yes/No (Dataverse auditing)
  - fsi_lastchecked        DateTime UTC (last compliance check)
  - fsi_compliancestatus   Choice (Compliant/Non-Compliant/Remediation Pending/Error)
  - fsi_remediationdate    DateTime (when remediation applied)
  - fsi_remediatedby       Single Line Text
  - fsi_errormessage       Multi-line Text
  - fsi_lasteventcaptured  DateTime (most recent audit event)

Alternate Key:
  - fsi_environmentid_key on fsi_environmentid (enables upsert by environment GUID)

Seed Data:
  After schema deployment, the table is populated automatically by the
  Test-AuditLoggingCompliance.ps1 detection runbook. No manual seed data
  is required. To verify the schema, run this script with --dry-run first,
  then deploy and execute the detection runbook against a test environment.
"""

import argparse
import os
import sys

from alca_client import ALCAClient

# Publisher prefix for custom entities
PUBLISHER_PREFIX = "fsi"

# ============================================================================
# Choice (OptionSet) Definitions
# ============================================================================

OPTIONSETS = {
    "fsi_alca_compliancestatus": {
        "@odata.type": "Microsoft.Dynamics.CRM.OptionSetMetadata",
        "Name": "fsi_alca_compliancestatus",
        "DisplayName": {
            "LocalizedLabels": [
                {"Label": "ALCA Compliance Status", "LanguageCode": 1033}
            ]
        },
        "Description": {
            "LocalizedLabels": [
                {
                    "Label": "Audit logging compliance status for an environment",
                    "LanguageCode": 1033,
                }
            ]
        },
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.OptionMetadata",
                "Value": 100000000,
                "Label": {
                    "LocalizedLabels": [
                        {"Label": "Compliant", "LanguageCode": 1033}
                    ]
                },
            },
            {
                "@odata.type": "Microsoft.Dynamics.CRM.OptionMetadata",
                "Value": 100000001,
                "Label": {
                    "LocalizedLabels": [
                        {"Label": "Non-Compliant", "LanguageCode": 1033}
                    ]
                },
            },
            {
                "@odata.type": "Microsoft.Dynamics.CRM.OptionMetadata",
                "Value": 100000002,
                "Label": {
                    "LocalizedLabels": [
                        {"Label": "Remediation Pending", "LanguageCode": 1033}
                    ]
                },
            },
            {
                "@odata.type": "Microsoft.Dynamics.CRM.OptionMetadata",
                "Value": 100000003,
                "Label": {
                    "LocalizedLabels": [
                        {"Label": "Error", "LanguageCode": 1033}
                    ]
                },
            },
        ],
    },
}


def create_optionsets(client: ALCAClient, dry_run: bool = False) -> dict:
    """Create all global option sets. Returns counts."""
    print("\n[Creating Global Option Sets]")
    counts = {"created": 0, "skipped": 0}

    for name, definition in OPTIONSETS.items():
        existing = client.get_global_optionset(name)
        if existing:
            print(f"  {name}: already exists, skipping")
            counts["skipped"] += 1
            continue

        if dry_run:
            print(f"  {name}: would create (4 options: Compliant, Non-Compliant, Remediation Pending, Error)")
        else:
            client.create_global_optionset(definition)
            print(f"  {name}: created")
        counts["created"] += 1

    return counts


# ============================================================================
# Table Definition
# ============================================================================

def get_audit_environment_compliance_entity() -> dict:
    """
    Get AuditEnvironmentCompliance entity definition.

    Organization-owned table with auditing enabled. Used by ALCA detection
    and remediation runbooks to track per-environment compliance status.
    """
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.EntityMetadata",
        "SchemaName": "fsi_AuditEnvironmentCompliance",
        "DisplayName": {
            "LocalizedLabels": [
                {"Label": "Audit Environment Compliance", "LanguageCode": 1033}
            ]
        },
        "DisplayCollectionName": {
            "LocalizedLabels": [
                {"Label": "Audit Environment Compliance", "LanguageCode": 1033}
            ]
        },
        "Description": {
            "LocalizedLabels": [
                {
                    "Label": "Per-environment audit logging compliance status tracked by ALCA detection and remediation runbooks",
                    "LanguageCode": 1033,
                }
            ]
        },
        "OwnershipType": "OrganizationOwned",
        "IsActivity": False,
        "HasActivities": False,
        "HasNotes": False,
        "IsAuditEnabled": {"Value": True},
        "PrimaryNameAttribute": "fsi_environmentname",
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": "fsi_EnvironmentName",
                "DisplayName": {
                    "LocalizedLabels": [
                        {"Label": "Environment Name", "LanguageCode": 1033}
                    ]
                },
                "Description": {
                    "LocalizedLabels": [
                        {
                            "Label": "Power Platform environment display name",
                            "LanguageCode": 1033,
                        }
                    ]
                },
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "MaxLength": 200,
                "FormatName": {"Value": "Text"},
                "IsPrimaryName": True,
            },
        ],
    }


# ============================================================================
# Column Definitions
# ============================================================================

TABLE_COLUMNS = [
    # Environment identification (upsert key)
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_EnvironmentId",
        "DisplayName": {
            "LocalizedLabels": [
                {"Label": "Environment ID", "LanguageCode": 1033}
            ]
        },
        "Description": {
            "LocalizedLabels": [
                {
                    "Label": "Power Platform environment GUID — upsert key",
                    "LanguageCode": 1033,
                }
            ]
        },
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "MaxLength": 100,
        "FormatName": {"Value": "Text"},
    },
    # Purview unified audit status
    {
        "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
        "SchemaName": "fsi_AuditEnabled",
        "DisplayName": {
            "LocalizedLabels": [
                {"Label": "Purview Audit Enabled", "LanguageCode": 1033}
            ]
        },
        "Description": {
            "LocalizedLabels": [
                {
                    "Label": "Whether Purview unified audit log ingestion is enabled",
                    "LanguageCode": 1033,
                }
            ]
        },
        "RequiredLevel": {"Value": "None"},
        "DefaultValue": False,
    },
    # Dataverse audit status
    {
        "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
        "SchemaName": "fsi_DataverseAuditEnabled",
        "DisplayName": {
            "LocalizedLabels": [
                {"Label": "Dataverse Audit Enabled", "LanguageCode": 1033}
            ]
        },
        "Description": {
            "LocalizedLabels": [
                {
                    "Label": "Whether Dataverse org-level auditing is enabled",
                    "LanguageCode": 1033,
                }
            ]
        },
        "RequiredLevel": {"Value": "None"},
        "DefaultValue": False,
    },
    # Last compliance check timestamp
    {
        "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": "fsi_LastChecked",
        "DisplayName": {
            "LocalizedLabels": [
                {"Label": "Last Checked", "LanguageCode": 1033}
            ]
        },
        "Description": {
            "LocalizedLabels": [
                {
                    "Label": "UTC timestamp of last compliance check",
                    "LanguageCode": 1033,
                }
            ]
        },
        "RequiredLevel": {"Value": "None"},
        "Format": "DateAndTime",
    },
    # Compliance status (choice field)
    {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": "fsi_ComplianceStatus",
        "DisplayName": {
            "LocalizedLabels": [
                {"Label": "Compliance Status", "LanguageCode": 1033}
            ]
        },
        "Description": {
            "LocalizedLabels": [
                {
                    "Label": "Current audit compliance status: Compliant (100000000), Non-Compliant (100000001), Remediation Pending (100000002), Error (100000003)",
                    "LanguageCode": 1033,
                }
            ]
        },
        "RequiredLevel": {"Value": "None"},
        "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_alca_compliancestatus')",
    },
    # Remediation tracking
    {
        "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": "fsi_RemediationDate",
        "DisplayName": {
            "LocalizedLabels": [
                {"Label": "Remediation Date", "LanguageCode": 1033}
            ]
        },
        "Description": {
            "LocalizedLabels": [
                {
                    "Label": "When remediation was applied to this environment",
                    "LanguageCode": 1033,
                }
            ]
        },
        "RequiredLevel": {"Value": "None"},
        "Format": "DateAndTime",
    },
    {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": "fsi_RemediatedBy",
        "DisplayName": {
            "LocalizedLabels": [
                {"Label": "Remediated By", "LanguageCode": 1033}
            ]
        },
        "Description": {
            "LocalizedLabels": [
                {
                    "Label": "Identity that performed remediation (Managed Identity or user UPN)",
                    "LanguageCode": 1033,
                }
            ]
        },
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 200,
        "FormatName": {"Value": "Text"},
    },
    # Error tracking
    {
        "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
        "SchemaName": "fsi_ErrorMessage",
        "DisplayName": {
            "LocalizedLabels": [
                {"Label": "Error Message", "LanguageCode": 1033}
            ]
        },
        "Description": {
            "LocalizedLabels": [
                {
                    "Label": "Error details when compliance check or remediation fails",
                    "LanguageCode": 1033,
                }
            ]
        },
        "RequiredLevel": {"Value": "None"},
        "MaxLength": 4000,
    },
    # Last audit event captured
    {
        "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": "fsi_LastEventCaptured",
        "DisplayName": {
            "LocalizedLabels": [
                {"Label": "Last Event Captured", "LanguageCode": 1033}
            ]
        },
        "Description": {
            "LocalizedLabels": [
                {
                    "Label": "Timestamp of most recent audit event found via Search-UnifiedAuditLog",
                    "LanguageCode": 1033,
                }
            ]
        },
        "RequiredLevel": {"Value": "None"},
        "Format": "DateAndTime",
    },
]


# ============================================================================
# Alternate Key Definition
# ============================================================================

ALTERNATE_KEY = {
    "SchemaName": "fsi_environmentid_key",
    "DisplayName": {
        "LocalizedLabels": [
            {"Label": "Environment ID Key", "LanguageCode": 1033}
        ]
    },
    "KeyAttributes": ["fsi_environmentid"],
}


# ============================================================================
# Schema Deployment Functions
# ============================================================================

def create_table(client: ALCAClient, dry_run: bool = False) -> dict:
    """Create the AuditEnvironmentCompliance table."""
    print("\n[Creating Table]")
    counts = {"created": 0, "skipped": 0}

    logical_name = "fsi_auditenvironmentcompliance"
    existing = client.get_entity_metadata(logical_name)
    if existing:
        print(f"  {logical_name}: already exists")
        counts["skipped"] += 1
    elif dry_run:
        print(f"  {logical_name}: would create (Org-owned, auditing enabled, primary: fsi_environmentname)")
    else:
        client.create_entity(get_audit_environment_compliance_entity())
        print(f"  {logical_name}: created")
        counts["created"] += 1
    if not dry_run:
        client.publish_all_customizations()
        client.wait_for_entity_metadata_readiness(logical_name)
        print(f"  {logical_name}: metadata ready")

    return counts


def create_columns(client: ALCAClient, dry_run: bool = False) -> dict:
    """Create columns on AuditEnvironmentCompliance table."""
    print("\n[Creating Columns]")
    counts = {"created": 0, "skipped": 0}

    entity = "fsi_auditenvironmentcompliance"
    if not dry_run:
        client.publish_all_customizations()
        client.wait_for_entity_metadata_readiness(entity)
        existing_columns = client.list_attribute_logical_names(entity)
    else:
        # Avoid propagation retries when the table is only being previewed.
        existing_columns = (
            client.list_attribute_logical_names(entity)
            if client.get_entity_metadata(entity) is not None
            else set()
        )
    for col in TABLE_COLUMNS:
        col_name = col["SchemaName"].lower()
        if col_name in existing_columns:
            print(f"  {col_name}: already exists")
            counts["skipped"] += 1
        elif dry_run:
            odata_type = col.get("@odata.type", "").split(".")[-1]
            print(f"  {col_name}: would create ({odata_type})")
        else:
            client.create_attribute(entity, col)
            client.publish_all_customizations()
            client.wait_for_attribute_metadata_readiness(entity, col_name)
            existing_columns.add(col_name)
            print(f"  {col_name}: created")
            counts["created"] += 1

    return counts


def create_alternate_key(client: ALCAClient, dry_run: bool = False) -> dict:
    """Create alternate key on fsi_environmentid for upsert support."""
    print("\n[Creating Alternate Key]")
    counts = {"created": 0, "skipped": 0}

    entity = "fsi_auditenvironmentcompliance"
    key_name = ALTERNATE_KEY["SchemaName"].lower()

    # Check if key already exists
    existing_keys = client.get_alternate_keys(entity)
    key_exists = any(
        k.get("SchemaName", "").lower() == key_name
        for k in existing_keys
    )

    if key_exists:
        print(f"  {key_name}: already exists")
        counts["skipped"] += 1
    elif dry_run:
        print(f"  {key_name}: would create (on fsi_environmentid)")
    else:
        client.create_alternate_key(entity, ALTERNATE_KEY)
        print(f"  {key_name}: created")
        counts["created"] += 1

    return counts


def print_seed_data_instructions() -> None:
    """Print seed data configuration instructions."""
    print("\n[Seed Data Configuration]")
    print("""
  No manual seed data is required. The fsi_auditenvironmentcompliance table
  is populated automatically by the Test-AuditLoggingCompliance.ps1 detection
  runbook during its first execution.

  To verify the schema manually, you can create a test record:

    POST /api/data/v9.2/fsi_auditenvironmentcompliances
    {
      "fsi_environmentname": "Test Environment",
      "fsi_environmentid": "00000000-0000-0000-0000-000000000001",
      "fsi_auditenabled": false,
      "fsi_dataverseauditenabled": false,
      "fsi_compliancestatus": 100000001
    }

  To upsert by environment ID (used by the runbooks):

    PATCH /api/data/v9.2/fsi_auditenvironmentcompliances(fsi_environmentid='<GUID>')
    {
      "fsi_environmentname": "Updated Name",
      "fsi_auditenabled": true,
      "fsi_compliancestatus": 100000000
    }

  Delete the test record after verification:

    DELETE /api/data/v9.2/fsi_auditenvironmentcompliances(<record-id>)
""")


def create_schema(client: ALCAClient, dry_run: bool = False) -> dict:
    """
    Create complete Dataverse schema for ALCA.

    Returns:
        Results dict with success/failure counts
    """
    print("=" * 60)
    print("ALCA Dataverse Schema Deployment")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN - No changes will be made ***\n")

    results = {
        "optionsets": {"created": 0, "skipped": 0},
        "tables": {"created": 0, "skipped": 0},
        "columns": {"created": 0, "skipped": 0},
        "keys": {"created": 0, "skipped": 0},
    }

    # Step 1: Create option sets (must exist before columns reference them)
    results["optionsets"] = create_optionsets(client, dry_run)

    # Step 2: Create table
    results["tables"] = create_table(client, dry_run)

    # Step 3: Create columns
    results["columns"] = create_columns(client, dry_run)

    # Step 4: Create alternate key (columns must exist first)
    results["keys"] = create_alternate_key(client, dry_run)

    # Step 5: Print seed data instructions
    print_seed_data_instructions()

    print("=" * 60)
    if dry_run:
        print("DRY RUN COMPLETE - Review output above")
    else:
        print("SCHEMA DEPLOYMENT COMPLETE")
        total_created = sum(r["created"] for r in results.values())
        total_skipped = sum(r["skipped"] for r in results.values())
        print(f"  Created: {total_created}  Skipped: {total_skipped}")
    print("=" * 60)

    return results


def main() -> None:
    """CLI entry point."""
    parser = argparse.ArgumentParser(
        description="Create Dataverse schema for Audit Logging Compliance Automation (ALCA)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Examples:
  # Dry run (preview changes without deploying)
  python create_audit_compliance_schema.py --tenant-id <id> --client-id <id> --environment-url <url> --interactive --dry-run

  # Interactive browser authentication
  python create_audit_compliance_schema.py --tenant-id <id> --client-id <id> --environment-url <url> --interactive

  # Service principal authentication (set ALCA_CLIENT_SECRET env var)
  export ALCA_CLIENT_SECRET=<secret>
  python create_audit_compliance_schema.py --tenant-id <id> --client-id <id> --environment-url <url>

Environment variables:
  ALCA_TENANT_ID         Entra ID tenant ID
  ALCA_CLIENT_ID         Application (client) ID
  ALCA_CLIENT_SECRET     Client secret
  ALCA_ENVIRONMENT_URL   Dataverse environment URL
        """,
    )

    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ALCA_TENANT_ID"),
        help="Entra ID tenant ID",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ALCA_CLIENT_ID"),
        help="Application (client) ID",
    )
    # Client secret read from ALCA_CLIENT_SECRET env var (not CLI arg to avoid shell history exposure)
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ALCA_ENVIRONMENT_URL"),
        help="Dataverse environment URL (e.g., https://org.crm.dynamics.com)",
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
        "--solution-name",
        default="AuditComplianceManager",
        help="Solution unique name for component registration (default: AuditComplianceManager)",
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

    # legacy: dev-only — replace with managed identity in production
    # Get client secret from env var or prompt (never via CLI arg to avoid shell history exposure)
    client_secret = os.environ.get("ALCA_CLIENT_SECRET")
    if not args.interactive and args.client_id and not client_secret:
        import getpass
        client_secret = getpass.getpass("Client secret: ")

    try:
        client = ALCAClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            interactive=args.interactive,
            dry_run=args.dry_run,
            solution_name=args.solution_name,
        )

        create_schema(client, dry_run=args.dry_run)

    except Exception as e:
        print(f"Error: {e}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
