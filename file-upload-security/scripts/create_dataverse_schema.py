#!/usr/bin/env python3
"""Create Dataverse schema for File Upload Security Configurator.

Creates three tables with idempotent column provisioning:
  - fsi_fileupload_baseline      (UserOwned)
  - fsi_fileupload_validationhistory (OrgOwned / immutable)
  - fsi_fileupload_violation     (UserOwned)

Reuses shared option sets: fsi_acv_zone, fsi_acv_severity.

Usage:
  python create_dataverse_schema.py --tenant-id <tid> --url <url> [--dry-run]
"""

import argparse
import os
import sys

from fus_client import FUSClient

# ── Shared Constants ──────────────────────────────────────────────
PUBLISHER_PREFIX = "fsi"
SOLUTION_NAME = "FileUploadSecurity"


# ── Column Definition Helpers ──────────────────────────────────────

def _label(text: str) -> dict:
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
    schema: str, display: str, max_length: int = 200, required: bool = False
) -> dict:
    return {
        "@odata.type": "#Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": schema,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "ApplicationRequired" if required else "None"},
        "MaxLength": max_length,
        "FormatName": {"Value": "Text"},
    }


def _memo_col(schema: str, display: str, max_length: int = 10000) -> dict:
    return {
        "@odata.type": "#Microsoft.Dynamics.CRM.MemoAttributeMetadata",
        "SchemaName": schema,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "None"},
        "MaxLength": max_length,
        "Format": "Text",
    }


def _int_col(schema: str, display: str, min_val: int = 0, max_val: int = 100000) -> dict:
    return {
        "@odata.type": "#Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
        "SchemaName": schema,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "None"},
        "MinValue": min_val,
        "MaxValue": max_val,
        "Format": "None",
    }


def _bool_col(schema: str, display: str, default: bool = False) -> dict:
    return {
        "@odata.type": "#Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
        "SchemaName": schema,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "None"},
        "DefaultValue": default,
        "OptionSet": {
            "TrueOption": {"Value": 1, "Label": _label("Yes")},
            "FalseOption": {"Value": 0, "Label": _label("No")},
        },
    }


def _datetime_col(schema: str, display: str) -> dict:
    return {
        "@odata.type": "#Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": schema,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "None"},
        "Format": "DateAndTime",
        "DateTimeBehavior": {"Value": "UserLocal"},
    }


def _picklist_col(schema: str, display: str, global_option_set: str) -> dict:
    return {
        "@odata.type": "#Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": schema,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "None"},
        "GlobalOptionSet@odata.bind": (
            f"/GlobalOptionSetDefinitions(Name='{global_option_set}')"
        ),
    }


def _decimal_col(
    schema: str, display: str, precision: int = 2,
    min_val: float = 0, max_val: float = 100,
) -> dict:
    return {
        "@odata.type": "#Microsoft.Dynamics.CRM.DecimalAttributeMetadata",
        "SchemaName": schema,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "None"},
        "Precision": precision,
        "MinValue": min_val,
        "MaxValue": max_val,
    }


# ── Table Definitions ──────────────────────────────────────────────

BASELINE_COLUMNS = [
    ("fsi_agent_id", "string", lambda: _string_col("fsi_agent_id", "Agent ID", 200, True)),
    ("fsi_agent_name", "string", lambda: _string_col("fsi_agent_name", "Agent Name", 500)),
    ("fsi_environment_id", "string", lambda: _string_col("fsi_environment_id", "Environment ID", 200)),
    ("fsi_environment_name", "string", lambda: _string_col("fsi_environment_name", "Environment Name", 500)),
    ("fsi_zone", "picklist", lambda: _picklist_col("fsi_zone", "Zone", "fsi_acv_zone")),
    ("fsi_file_upload_enabled", "boolean", lambda: _bool_col("fsi_file_upload_enabled", "File Upload Enabled")),
    ("fsi_content_moderation_level", "string", lambda: _string_col("fsi_content_moderation_level", "Content Moderation Level", 50)),
    ("fsi_baseline_captured_on", "datetime", lambda: _datetime_col("fsi_baseline_captured_on", "Baseline Captured On")),
    ("fsi_baseline_captured_by", "string", lambda: _string_col("fsi_baseline_captured_by", "Baseline Captured By", 200)),
    ("fsi_owner_email", "string", lambda: _string_col("fsi_owner_email", "Owner Email", 320)),
    ("fsi_notes", "memo", lambda: _memo_col("fsi_notes", "Notes")),
]

HISTORY_COLUMNS = [
    ("fsi_run_id", "string", lambda: _string_col("fsi_run_id", "Run ID", 100, True)),
    ("fsi_run_timestamp", "datetime", lambda: _datetime_col("fsi_run_timestamp", "Run Timestamp")),
    ("fsi_validation_time", "datetime", lambda: _datetime_col("fsi_validation_time", "Validation Time")),
    ("fsi_total_agents", "integer", lambda: _int_col("fsi_total_agents", "Total Agents")),
    ("fsi_compliant_count", "integer", lambda: _int_col("fsi_compliant_count", "Compliant Count")),
    ("fsi_violation_count", "integer", lambda: _int_col("fsi_violation_count", "Violation Count")),
    ("fsi_file_upload_enabled_count", "integer", lambda: _int_col("fsi_file_upload_enabled_count", "File Upload Enabled Count")),
    ("fsi_overall_status", "string", lambda: _string_col("fsi_overall_status", "Overall Status", 50)),
    ("fsi_compliance_rate", "decimal", lambda: _decimal_col("fsi_compliance_rate", "Compliance Rate %")),
    ("fsi_environments_scanned", "integer", lambda: _int_col("fsi_environments_scanned", "Environments Scanned")),
    ("fsi_scan_duration_seconds", "integer", lambda: _int_col("fsi_scan_duration_seconds", "Scan Duration (s)", 0, 86400)),
    ("fsi_summary_json", "memo", lambda: _memo_col("fsi_summary_json", "Summary JSON")),
    ("fsi_notes", "memo", lambda: _memo_col("fsi_notes", "Run Notes")),
]

VIOLATION_COLUMNS = [
    ("fsi_agent_id", "string", lambda: _string_col("fsi_agent_id", "Agent ID", 200, True)),
    ("fsi_agent_name", "string", lambda: _string_col("fsi_agent_name", "Agent Name", 500)),
    ("fsi_environment_id", "string", lambda: _string_col("fsi_environment_id", "Environment ID", 200)),
    ("fsi_environment_name", "string", lambda: _string_col("fsi_environment_name", "Environment Name", 500)),
    ("fsi_zone", "picklist", lambda: _picklist_col("fsi_zone", "Zone", "fsi_acv_zone")),
    ("fsi_severity", "picklist", lambda: _picklist_col("fsi_severity", "Severity", "fsi_acv_severity")),
    ("fsi_violation_type", "string", lambda: _string_col("fsi_violation_type", "Violation Type", 100)),
    ("fsi_file_upload_expected", "string", lambda: _string_col("fsi_file_upload_expected", "File Upload Expected", 50)),
    ("fsi_file_upload_actual", "string", lambda: _string_col("fsi_file_upload_actual", "File Upload Actual", 50)),
    ("fsi_content_moderation_level", "string", lambda: _string_col("fsi_content_moderation_level", "Content Moderation Level", 50)),
    ("fsi_content_moderation_minimum", "string", lambda: _string_col("fsi_content_moderation_minimum", "Minimum Required Moderation", 50)),
    ("fsi_detected_on", "datetime", lambda: _datetime_col("fsi_detected_on", "Detected On")),
    ("fsi_run_id", "string", lambda: _string_col("fsi_run_id", "Run ID", 100)),
    ("fsi_owner_email", "string", lambda: _string_col("fsi_owner_email", "Owner Email", 320)),
    ("fsi_remediation_notes", "memo", lambda: _memo_col("fsi_remediation_notes", "Remediation Notes")),
    ("fsi_resolved", "boolean", lambda: _bool_col("fsi_resolved", "Resolved")),
    ("fsi_resolved_on", "datetime", lambda: _datetime_col("fsi_resolved_on", "Resolved On")),
]


# ── Deployment Functions ──────────────────────────────────────────

def _create_table(
    client: FUSClient, logical_name: str, display: str,
    plural: str, description: str, ownership: str, columns: list
) -> None:
    """Create a table if it doesn't exist, then add columns."""
    print(f"\n{'='*60}")
    print(f"Table: {logical_name}")
    print(f"{'='*60}")

    if client.check_table_exists(logical_name):
        print(f"  Table already exists — checking columns...")
    else:
        definition = {
            "@odata.type": "#Microsoft.Dynamics.CRM.EntityMetadata",
            "SchemaName": logical_name,
            "DisplayName": _label(display),
            "DisplayCollectionName": _label(plural),
            "Description": _label(description),
            "OwnershipType": ownership,
            "IsActivity": False,
            "HasNotes": False,
            "HasActivities": False,
        }
        client.create_entity(definition)
        print(f"  Table created ({ownership})")

    print(f"  Adding columns:")
    for col_name, col_type, col_factory in columns:
        try:
            client.create_column(logical_name, col_name, col_type, col_factory())
        except Exception as exc:
            print(f"    ERROR creating {col_name}: {exc}")
            continue


def ensure_shared_option_sets(client: FUSClient) -> None:
    """Create shared option sets if they don't already exist."""
    print("\n--- Shared Option Sets ---")

    client.create_option_set(
        "fsi_acv_zone",
        [("Zone 1 - Personal", 1), ("Zone 2 - Team", 2), ("Zone 3 - Enterprise", 3)],
    )
    client.create_option_set(
        "fsi_acv_severity",
        [
            ("Info", 0),
            ("Low", 1),
            ("Medium", 2),
            ("High", 3),
            ("Critical", 4),
            ("Warning", 5),
        ],
    )


def deploy_schema(client: FUSClient) -> None:
    """Deploy all FUS Dataverse tables and columns."""
    ensure_shared_option_sets(client)

    _create_table(
        client,
        logical_name="fsi_fileupload_baseline",
        display="File Upload Baseline",
        plural="File Upload Baselines",
        description="Approved file upload configuration baseline per agent",
        ownership="UserOwned",
        columns=BASELINE_COLUMNS,
    )

    _create_table(
        client,
        logical_name="fsi_fileupload_validationhistory",
        display="File Upload Validation History",
        plural="File Upload Validation History",
        description="Immutable audit trail of file upload compliance scans",
        ownership="OrganizationOwned",
        columns=HISTORY_COLUMNS,
    )

    _create_table(
        client,
        logical_name="fsi_fileupload_violation",
        display="File Upload Violation",
        plural="File Upload Violations",
        description="Active file upload policy violations requiring remediation",
        ownership="UserOwned",
        columns=VIOLATION_COLUMNS,
    )

    print(f"\n{'='*60}")
    print("Schema deployment complete.")
    print(f"{'='*60}")


# ── CLI Entry Point ──────────────────────────────────────────────

def main():
    parser = argparse.ArgumentParser(
        description="Create Dataverse schema for File Upload Security Configurator"
    )
    parser.add_argument("--tenant-id", default=os.environ.get("FUS_TENANT_ID"))
    parser.add_argument("--client-id", default=os.environ.get("FUS_CLIENT_ID"))
    parser.add_argument("--client-secret", default=os.environ.get("FUS_CLIENT_SECRET"))
    parser.add_argument("--url", default=os.environ.get("FUS_DATAVERSE_URL"),
                        help="Dataverse environment URL")
    parser.add_argument("--interactive", action="store_true",
                        help="Use interactive browser auth")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be created without making changes")
    args = parser.parse_args()

    if not args.tenant_id or not args.url:
        parser.error(
            "tenant-id and url are required "
            "(set FUS_TENANT_ID and FUS_DATAVERSE_URL env vars or use flags)"
        )

    client = FUSClient(
        tenant_id=args.tenant_id,
        environment_url=args.url,
        client_id=args.client_id,
        client_secret=args.client_secret,
        interactive=args.interactive,
        dry_run=args.dry_run,
    )

    deploy_schema(client)


if __name__ == "__main__":
    main()
