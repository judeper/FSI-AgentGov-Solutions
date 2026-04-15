#!/usr/bin/env python3
"""
Create Dataverse schema for Copilot Studio Analytics.

Creates the CSASyncWatermark table with all columns and supporting option sets.
Used to track incremental sync state between Dataverse and Application Insights.
"""

import argparse
import os
import sys
from typing import Optional

import requests
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"))
from dataverse_client import DataverseClient

PUBLISHER_PREFIX = "fsi"

# CSA-specific option sets
OPTIONSETS = {
    "fsi_CSA_syncstatus": {
        "Name": "fsi_CSA_syncstatus",
        "DisplayName": {"LocalizedLabels": [{"Label": "Sync Status", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Status of the Dataverse-to-App Insights sync operation", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Success", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Failed", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "InProgress", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "Warning", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_CSA_synctier": {
        "Name": "fsi_CSA_synctier",
        "DisplayName": {"LocalizedLabels": [{"Label": "Sync Tier", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Sync tier level for the CSA pipeline", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Tier1", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Tier2", "LanguageCode": 1033}]}},
        ],
    },
}

# Table definitions
TABLES = {
    "fsi_CSASyncWatermark": {
        "SchemaName": "fsi_CSASyncWatermark",
        "DisplayName": {"LocalizedLabels": [{"Label": "CSA Sync Watermark", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "CSA Sync Watermarks", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Tracks incremental sync state between Dataverse sessions and Application Insights", "LanguageCode": 1033}]},
        "OwnershipType": "OrganizationOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": f"{PUBLISHER_PREFIX}_EnvironmentUrl",
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "DisplayName": {"LocalizedLabels": [{"Label": "Environment URL", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Dataverse environment URL for this sync watermark", "LanguageCode": 1033}]},
                "MaxLength": 500,
                "FormatName": {"Value": "Url"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_environmenturl",
    },
}

# Additional columns (added after table creation)
COLUMNS = {
    "fsi_csasyncwatermark": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_LastSyncTimestamp",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Last Sync Timestamp", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Timestamp of the last successful sync operation", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_RecordsSynced",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Records Synced", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Number of records synced in the last operation", "LanguageCode": 1033}]},
            "MinValue": 0,
            "MaxValue": 2147483647,
            "Format": "None",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_SyncStatus",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Sync Status", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Current status of the sync operation", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_CSA_syncstatus')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_SyncTier",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Sync Tier", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Sync tier level for this watermark entry", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_CSA_synctier')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ErrorMessage",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Error Message", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Error details for failed sync operations", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
    ],
}


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
    """Look up an option set by name across OPTIONSETS."""
    if name in OPTIONSETS:
        return OPTIONSETS[name]
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
    lines.append("> Auto-generated from `create_csa_dataverse_schema.py`. Do not edit manually.")
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
        # Combine the primary attribute(s) defined in TABLES.Attributes with COLUMNS
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

            # Option set info
            os_cell = ""
            os_name = _optionset_name_from_bind(col)
            if os_name:
                os_def = _resolve_optionset(os_name)
                if os_def:
                    os_cell = f"**{os_name}**: {_format_option_values(os_def.get('Options', []))}"
                else:
                    os_cell = os_name

            lines.append(f"| {sn} | {ln} | {ctype} | {required} | {desc} | {os_cell} |")

        lines.append("")

    # Option Sets
    lines.append("## Option Sets")
    lines.append("")

    lines.append("### CSA Option Sets")
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


def create_optionsets(client: DataverseClient, dry_run: bool) -> dict:
    """Create global option sets."""
    print("\n=== Creating Option Sets ===")
    created = 0
    skipped = 0

    print("\nCSA-specific option sets:")
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
                client.create_column(table_logical_name, column_metadata)


def create_schema(client: DataverseClient, dry_run: bool) -> dict:
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


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create Dataverse schema for Copilot Studio Analytics",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--tenant-id", default=os.environ.get("CSA_TENANT_ID"), help="Entra ID tenant ID (or set CSA_TENANT_ID env var)")
    parser.add_argument("--client-id", default=os.environ.get("CSA_CLIENT_ID"), help="Application (client) ID (or set CSA_CLIENT_ID env var)")
    parser.add_argument("--client-secret", default=os.environ.get("CSA_CLIENT_SECRET"), help="Client secret (or set CSA_CLIENT_SECRET env var)")
    parser.add_argument("--environment-url", default=os.environ.get("CSA_ENVIRONMENT_URL"), help="Dataverse environment URL (or set CSA_ENVIRONMENT_URL env var)")
    parser.add_argument("--interactive", action="store_true", help="Use interactive browser authentication")
    parser.add_argument("--dry-run", action="store_true", help="Preview schema operations without API calls")
    parser.add_argument("--output-docs", action="store_true", help="Generate docs/dataverse-schema.md and exit (no credentials required)")
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
        parser.error("Missing required arguments. Provide --tenant-id and --environment-url (or set CSA_TENANT_ID and CSA_ENVIRONMENT_URL env vars)")
    if not args.client_id and not args.interactive:
        parser.error("--client-id is required (or set CSA_CLIENT_ID env var) unless --interactive is specified")

    client_secret = args.client_secret
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
