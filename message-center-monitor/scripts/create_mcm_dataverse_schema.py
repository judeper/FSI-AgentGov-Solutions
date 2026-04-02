#!/usr/bin/env python3
"""
Create Dataverse schema for Message Center Monitor.

Creates MessageCenterLog table with all columns, choice fields, and supporting
option sets for tracking M365 Message Center posts and agent impact assessments.
"""

import argparse
import os
import sys
from typing import Optional

import requests
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"))
from dataverse_client import DataverseClient

PUBLISHER_PREFIX = "fsi"

# MCM-specific option sets
OPTIONSETS = {
    "fsi_MCM_messagecategory": {
        "Name": "fsi_MCM_messagecategory",
        "DisplayName": {"LocalizedLabels": [{"Label": "Message Category", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Category of the Message Center post", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Feature", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Admin", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Security", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_MCM_messageseverity": {
        "Name": "fsi_MCM_messageseverity",
        "DisplayName": {"LocalizedLabels": [{"Label": "Message Severity", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Severity level of the Message Center post", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "High", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Normal", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "Critical", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_MCM_assessmentstatus": {
        "Name": "fsi_MCM_assessmentstatus",
        "DisplayName": {"LocalizedLabels": [{"Label": "Assessment Status", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Assessment status of a Message Center post for agent impact", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "NotAssessed", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Reviewed", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "ImpactsAgents", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "NoImpact", "LanguageCode": 1033}]}},
        ],
    },
}

# Table definitions
TABLES = {
    "fsi_MessageCenterLog": {
        "SchemaName": "fsi_MessageCenterLog",
        "DisplayName": {"LocalizedLabels": [{"Label": "Message Center Log", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "Message Center Logs", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "M365 Message Center post tracking with agent impact assessments", "LanguageCode": 1033}]},
        "OwnershipType": "OrganizationOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": f"{PUBLISHER_PREFIX}_MessageCenterId",
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "DisplayName": {"LocalizedLabels": [{"Label": "Message Center ID", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "The MC post ID from M365 Message Center", "LanguageCode": 1033}]},
                "MaxLength": 100,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_messagecenterid",
    },
}

# Column definitions for each table
COLUMNS = {
    "fsi_messagecenterlog": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Title",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Title", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Title of the Message Center post", "LanguageCode": 1033}]},
            "MaxLength": 500,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Category",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Category", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Category of the Message Center post", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_MCM_messagecategory')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Severity",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Severity", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Severity level of the Message Center post", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_MCM_messageseverity')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Services",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Services", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Comma-separated list of affected services", "LanguageCode": 1033}]},
            "MaxLength": 2000,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_StartDateTime",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Start Date Time", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Start date and time of the message", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ActionRequiredByDateTime",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Action Required By", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Deadline for required action", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_LastModifiedDateTime",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Last Modified Date Time", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the Message Center post was last modified", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_IsMajorChange",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Is Major Change", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether the post represents a major change", "LanguageCode": 1033}]},
            "DefaultValue": False,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Body",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Body", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Full message body of the Message Center post", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AssessmentStatus",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Assessment Status", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Current assessment status for agent impact", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_MCM_assessmentstatus')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Assessment",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Assessment", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Analyst notes on agent impact assessment", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ImpactsAgents",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Impacts Agents", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether this change impacts AI agents", "LanguageCode": 1033}]},
            "DefaultValue": False,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AssessedBy",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Assessed By", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "UPN of the analyst who assessed the post", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AssessedDate",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Assessed Date", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When the assessment was completed", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ActionsTaken",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Actions Taken", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Record of actions taken in response to the post", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_NotifiedOn",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Notified On", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "When notification was sent for this post", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Tags",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Tags", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Comma-separated tags for categorization", "LanguageCode": 1033}]},
            "MaxLength": 1000,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_HasAttachments",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Has Attachments", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Whether the Message Center post has attachments", "LanguageCode": 1033}]},
            "DefaultValue": False,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
    ],
}

RELATIONSHIPS = []


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

    # ── Header ──────────────────────────────────────────────────────────
    lines.append("# Dataverse Schema Reference")
    lines.append("")
    lines.append("> Auto-generated from `create_mcm_dataverse_schema.py`. Do not edit manually.")
    lines.append("")

    # ── Tables ──────────────────────────────────────────────────────────
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

    # ── Columns (per table) ─────────────────────────────────────────────
    lines.append("## Columns")
    lines.append("")

    for table_schema_name, tbl in TABLES.items():
        table_logical = table_schema_name.lower()
        # Combine the primary attribute(s) defined in TABLES.Attributes with COLUMNS
        primary_attrs = tbl.get("Attributes", [])
        extra_cols = COLUMNS.get(table_logical, [])
        all_cols = primary_attrs + extra_cols

        # Also include any lookup columns coming from relationships
        rel_lookups: list[dict] = []
        for rel in RELATIONSHIPS:
            if rel.get("ReferencingEntity", "").lower() == table_logical:
                lookup = rel.get("Lookup", {})
                if lookup:
                    lk = dict(lookup)
                    lk["@odata.type"] = "Microsoft.Dynamics.CRM.LookupAttributeMetadata"
                    rel_lookups.append(lk)
        all_cols = all_cols + rel_lookups

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
            elif ctype == "Boolean":
                opt = col.get("OptionSet", {})
                true_lbl = _label(opt.get("TrueOption", {}).get("Label", {})) if opt.get("TrueOption") else "Yes"
                false_lbl = _label(opt.get("FalseOption", {}).get("Label", {})) if opt.get("FalseOption") else "No"
                os_cell = f"`1` = {true_lbl}, `0` = {false_lbl}"

            lines.append(f"| {sn} | {ln} | {ctype} | {required} | {desc} | {os_cell} |")

        lines.append("")

    # ── Option Sets ─────────────────────────────────────────────────────
    lines.append("## Option Sets")
    lines.append("")

    lines.append("### MCM Option Sets")
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

    # ── Relationships ───────────────────────────────────────────────────
    if RELATIONSHIPS:
        lines.append("## Relationships")
        lines.append("")
        lines.append("| SchemaName | Referenced Entity | Referencing Entity | Lookup Column |")
        lines.append("|---|---|---|---|")
        for rel in RELATIONSHIPS:
            sn = rel.get("SchemaName", "")
            ref_entity = rel.get("ReferencedEntity", "")
            refing_entity = rel.get("ReferencingEntity", "")
            lookup_sn = rel.get("Lookup", {}).get("SchemaName", "")
            lines.append(f"| {sn} | {ref_entity} | {refing_entity} | {lookup_sn} |")
        lines.append("")

    return "\n".join(lines)


def create_optionsets(client: DataverseClient, dry_run: bool) -> dict:
    """Create global option sets."""
    print("\n=== Creating Option Sets ===")
    created = 0
    skipped = 0

    print("\nMCM-specific option sets:")
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
    if not RELATIONSHIPS:
        print("  No relationships to create")
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


def main():
    parser = argparse.ArgumentParser(
        description="Create Dataverse schema for Message Center Monitor",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--tenant-id", default=os.environ.get("MCM_TENANT_ID"), help="Entra ID tenant ID (or set MCM_TENANT_ID env var)")
    parser.add_argument("--client-id", default=os.environ.get("MCM_CLIENT_ID"), help="Application (client) ID (or set MCM_CLIENT_ID env var)")
    parser.add_argument("--environment-url", default=os.environ.get("MCM_ENVIRONMENT_URL"), help="Dataverse environment URL (or set MCM_ENVIRONMENT_URL env var)")
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
        parser.error("Missing required arguments. Provide --tenant-id and --environment-url (or set MCM_TENANT_ID and MCM_ENVIRONMENT_URL env vars)")
    if not args.client_id and not args.interactive:
        parser.error("--client-id is required (or set MCM_CLIENT_ID env var) unless --interactive is specified")

    client_secret = os.environ.get("MCM_CLIENT_SECRET")
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
