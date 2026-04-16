#!/usr/bin/env python3
"""
Create Dataverse schema for DR Testing Framework.

Creates the DRTestResult table with columns for recording disaster recovery
test executions, RTO measurements, and validation results.

Regulatory alignment:
  - OCC 2011-12 (Third-Party Risk Management) — operational resilience testing
  - FFIEC BCP (Business Continuity Planning) — DR test documentation
  - SEC 17a-4 (Records Preservation) — immutable test evidence retention
  - FINRA 4370 (Business Continuity Plans) — annual DR testing requirements
"""

import argparse
import os
import sys
from typing import Optional

import requests

sys.path.insert(
    0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared")
)
from dataverse_client import DataverseClient

PUBLISHER_PREFIX = "fsi"

# ---------------------------------------------------------------------------
# Option Sets
# ---------------------------------------------------------------------------

OPTIONSETS = {
    "fsi_drt_teststatus": {
        "Name": "fsi_drt_teststatus",
        "DisplayName": {
            "LocalizedLabels": [
                {"Label": "DR Test Status", "LanguageCode": 1033}
            ]
        },
        "Description": {
            "LocalizedLabels": [
                {
                    "Label": "Pass/Fail outcome of a disaster recovery test",
                    "LanguageCode": 1033,
                }
            ]
        },
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {
                "Value": 1,
                "Label": {
                    "LocalizedLabels": [{"Label": "Pass", "LanguageCode": 1033}]
                },
            },
            {
                "Value": 2,
                "Label": {
                    "LocalizedLabels": [{"Label": "Fail", "LanguageCode": 1033}]
                },
            },
        ],
    },
}

# ---------------------------------------------------------------------------
# Table Definitions
# ---------------------------------------------------------------------------

TABLES = {
    "fsi_DRTestResult": {
        "SchemaName": "fsi_DRTestResult",
        "DisplayName": {
            "LocalizedLabels": [
                {"Label": "DR Test Result", "LanguageCode": 1033}
            ]
        },
        "DisplayCollectionName": {
            "LocalizedLabels": [
                {"Label": "DR Test Results", "LanguageCode": 1033}
            ]
        },
        "Description": {
            "LocalizedLabels": [
                {
                    "Label": (
                        "Disaster recovery test execution records with RTO "
                        "measurements and validation results"
                    ),
                    "LanguageCode": 1033,
                }
            ]
        },
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
                "DisplayName": {
                    "LocalizedLabels": [
                        {"Label": "Test Result ID", "LanguageCode": 1033}
                    ]
                },
                "Description": {
                    "LocalizedLabels": [
                        {
                            "Label": "Unique identifier for the DR test result",
                            "LanguageCode": 1033,
                        }
                    ]
                },
                "MaxLength": 100,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_name",
    },
}

# ---------------------------------------------------------------------------
# Column Definitions
# ---------------------------------------------------------------------------

COLUMNS = {
    "fsi_drtestresult": [
        # Test type: AgentRestore, EnvironmentFailover, DataRecovery, FullDR
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_TestType",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Test Type", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "Type of DR test executed: AgentRestore, "
                            "EnvironmentFailover, DataRecovery, FullDR"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 100,
            "FormatName": {"Value": "Text"},
        },
        # UTC timestamp of test execution
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ExecutedOn",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Executed On", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "UTC timestamp when the DR test was executed",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "UserLocal"},
        },
        # Actual recovery time in hours
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DecimalAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ActualRTO",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Actual RTO (hours)", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Actual recovery time objective measured in hours",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "Precision": 2,
            "MinValue": 0,
            "MaxValue": 9999,
        },
        # Target RTO in hours
        {
            "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_TargetRTO",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Target RTO (hours)", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Target recovery time objective in hours",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "Format": "None",
            "MinValue": 0,
            "MaxValue": 9999,
        },
        # Whether actual RTO met the target
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_RTOMet",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "RTO Met", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Whether the actual RTO met the target RTO",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "DefaultValue": False,
            "OptionSet": {
                "TrueOption": {
                    "Value": 1,
                    "Label": {
                        "LocalizedLabels": [
                            {"Label": "Yes", "LanguageCode": 1033}
                        ]
                    },
                },
                "FalseOption": {
                    "Value": 0,
                    "Label": {
                        "LocalizedLabels": [
                            {"Label": "No", "LanguageCode": 1033}
                        ]
                    },
                },
            },
        },
        # Pass/Fail status
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Status",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Status", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Overall pass/fail result of the DR test",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "GlobalOptionSet@odata.bind": (
                "GlobalOptionSetDefinitions(Name='fsi_drt_teststatus')"
            ),
        },
        # JSON array of validation check results
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_ValidationChecks",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Validation Checks", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "JSON array of individual validation check "
                            "results from the DR test execution"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "Format": "Text",
            "MaxLength": 100000,
        },
        # Short correlation ID linking to audit log file
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_CorrelationId",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Correlation ID", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "Short hex correlation ID linking this result "
                            "to the audit log file on disk"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 8,
            "FormatName": {"Value": "Text"},
        },
    ],
}

# No inter-table relationships for this solution
RELATIONSHIPS: list[dict] = []


# ---------------------------------------------------------------------------
# Documentation Generation Helpers
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
    """Look up an option set by name in OPTIONSETS."""
    return OPTIONSETS.get(name)


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
    lines.append(
        "> Auto-generated from `create_drt_dataverse_schema.py`. "
        "Do not edit manually."
    )
    lines.append("")
    lines.append(
        "This schema supports DR test evidence retention required by "
        "OCC 2011-12, FFIEC BCP, SEC 17a-4, and FINRA 4370."
    )
    lines.append("")

    # ── Tables ──────────────────────────────────────────────────────────
    lines.append("## Tables")
    lines.append("")
    lines.append(
        "| SchemaName | Logical Name | Description | Primary Name Attribute |"
    )
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
        primary_attrs = tbl.get("Attributes", [])
        extra_cols = COLUMNS.get(table_logical, [])
        all_cols = primary_attrs + extra_cols

        lines.append(f"### {table_schema_name} (`{table_logical}`)")
        lines.append("")
        lines.append(
            "| SchemaName | Logical Name | Type | Required "
            "| Description | Option Set |"
        )
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
                    os_cell = (
                        f"**{os_name}**: "
                        f"{_format_option_values(os_def.get('Options', []))}"
                    )
                else:
                    os_cell = os_name
            elif ctype == "Boolean":
                opt = col.get("OptionSet", {})
                true_lbl = (
                    _label(opt["TrueOption"]["Label"])
                    if opt.get("TrueOption")
                    else "Yes"
                )
                false_lbl = (
                    _label(opt["FalseOption"]["Label"])
                    if opt.get("FalseOption")
                    else "No"
                )
                os_cell = f"`1` = {true_lbl}, `0` = {false_lbl}"

            lines.append(
                f"| {sn} | {ln} | {ctype} | {required} "
                f"| {desc} | {os_cell} |"
            )

        lines.append("")

    # ── Option Sets ─────────────────────────────────────────────────────
    lines.append("## Option Sets")
    lines.append("")

    for name, osdef in OPTIONSETS.items():
        desc = _label(osdef.get("Description", {}))
        lines.append(f"### {name}")
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
# Schema Deployment Functions
# ---------------------------------------------------------------------------


def create_optionsets(client: DataverseClient, dry_run: bool) -> dict:
    """Create global option sets."""
    print("\n=== Creating Option Sets ===")
    created = 0
    skipped = 0

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


# ---------------------------------------------------------------------------
# CLI Entry Point
# ---------------------------------------------------------------------------


def main() -> None:
    parser = argparse.ArgumentParser(
        description=(
            "Create Dataverse schema for DR Testing Framework "
            "(OCC 2011-12, FFIEC BCP, SEC 17a-4, FINRA 4370)"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("DRT_TENANT_ID"),
        help="Entra ID tenant ID (or set DRT_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("DRT_CLIENT_ID"),
        help="Application (client) ID (or set DRT_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("DRT_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set DRT_ENVIRONMENT_URL env var)",
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
            "Missing required arguments. Provide --tenant-id and "
            "--environment-url (or set DRT_TENANT_ID and "
            "DRT_ENVIRONMENT_URL env vars)"
        )
    if not args.client_id and not args.interactive:
        parser.error(
            "--client-id is required (or set DRT_CLIENT_ID env var) "
            "unless --interactive is specified"
        )

    client_secret = os.environ.get("DRT_CLIENT_SECRET")
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
