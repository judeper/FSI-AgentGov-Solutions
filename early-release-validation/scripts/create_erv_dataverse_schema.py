#!/usr/bin/env python3
"""
Create Dataverse schema for the Early-Release Validation solution.

Creates the ERValidationResult table, which records pre-promotion resilience
validation runs against a Copilot Studio agent before it is promoted into an
early-release (preview) ring. Each row captures one structural check
(fallback coverage, connector resilience, error recovery) or the composite
early-release readiness gate, plus tamper-evident evidence metadata.

Regulatory alignment:
  - OCC 2011-12 / Fed SR 11-7 — pre-deployment validation of model/agent controls
  - SEC 17a-4 (Records Preservation) — immutable validation evidence retention
  - FINRA 4511 (Books and Records) — change/release control evidence
  - FFIEC — operational resilience and change-management testing

This script is offline-capable for documentation generation:
    python create_erv_dataverse_schema.py --output-docs
generates docs/dataverse-schema.md with no credentials required.
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
    "fsi_erv_testtype": {
        "Name": "fsi_erv_testtype",
        "DisplayName": {
            "LocalizedLabels": [
                {"Label": "Early-Release Validation Test Type", "LanguageCode": 1033}
            ]
        },
        "Description": {
            "LocalizedLabels": [
                {
                    "Label": (
                        "Type of early-release resilience validation executed "
                        "against a Copilot Studio agent"
                    ),
                    "LanguageCode": 1033,
                }
            ]
        },
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {
                "Value": 100000000,
                "Label": {
                    "LocalizedLabels": [
                        {"Label": "FallbackCoverageCheck", "LanguageCode": 1033}
                    ]
                },
            },
            {
                "Value": 100000001,
                "Label": {
                    "LocalizedLabels": [
                        {"Label": "ConnectorResilienceCheck", "LanguageCode": 1033}
                    ]
                },
            },
            {
                "Value": 100000002,
                "Label": {
                    "LocalizedLabels": [
                        {"Label": "ErrorRecoveryCheck", "LanguageCode": 1033}
                    ]
                },
            },
            {
                "Value": 100000003,
                "Label": {
                    "LocalizedLabels": [
                        {"Label": "EarlyReleaseReadinessCheck", "LanguageCode": 1033}
                    ]
                },
            },
        ],
    },
    "fsi_erv_teststatus": {
        "Name": "fsi_erv_teststatus",
        "DisplayName": {
            "LocalizedLabels": [
                {"Label": "Early-Release Validation Status", "LanguageCode": 1033}
            ]
        },
        "Description": {
            "LocalizedLabels": [
                {
                    "Label": "Pass/Fail/Skipped outcome of an early-release validation",
                    "LanguageCode": 1033,
                }
            ]
        },
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {
                "Value": 100000000,
                "Label": {
                    "LocalizedLabels": [{"Label": "Pass", "LanguageCode": 1033}]
                },
            },
            {
                "Value": 100000001,
                "Label": {
                    "LocalizedLabels": [{"Label": "Fail", "LanguageCode": 1033}]
                },
            },
            {
                "Value": 100000002,
                "Label": {
                    "LocalizedLabels": [{"Label": "Skipped", "LanguageCode": 1033}]
                },
            },
        ],
    },
}

# ---------------------------------------------------------------------------
# Table Definitions
# ---------------------------------------------------------------------------

TABLES = {
    "fsi_ERValidationResult": {
        "SchemaName": "fsi_ERValidationResult",
        "DisplayName": {
            "LocalizedLabels": [
                {"Label": "Early-Release Validation Result", "LanguageCode": 1033}
            ]
        },
        "DisplayCollectionName": {
            "LocalizedLabels": [
                {"Label": "Early-Release Validation Results", "LanguageCode": 1033}
            ]
        },
        "Description": {
            "LocalizedLabels": [
                {
                    "Label": (
                        "Pre-promotion resilience validation records for "
                        "Copilot Studio agents, with structural findings and "
                        "tamper-evident evidence metadata"
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
                        {"Label": "Validation Run ID", "LanguageCode": 1033}
                    ]
                },
                "Description": {
                    "LocalizedLabels": [
                        {
                            "Label": "Unique identifier for the validation run",
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
    "fsi_ervalidationresult": [
        # Copilot Studio bot component ID under validation
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AgentId",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Agent ID", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "Copilot Studio bot component ID of the agent "
                            "being validated"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 100,
            "FormatName": {"Value": "Text"},
        },
        # Target environment URL (the early-release ring environment)
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EnvironmentUrl",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Environment URL", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Target environment URL for the validation run",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 500,
            "FormatName": {"Value": "Url"},
        },
        # Validation type (global option set)
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
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
                            "Type of validation executed: FallbackCoverageCheck, "
                            "ConnectorResilienceCheck, ErrorRecoveryCheck, "
                            "EarlyReleaseReadinessCheck"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "GlobalOptionSet@odata.bind": (
                "GlobalOptionSetDefinitions(Name='fsi_erv_testtype')"
            ),
        },
        # Pass/Fail/Skipped status (global option set)
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_TestStatus",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Test Status", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Overall pass/fail/skipped result of the validation",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "GlobalOptionSet@odata.bind": (
                "GlobalOptionSetDefinitions(Name='fsi_erv_teststatus')"
            ),
        },
        # JSON document of structured findings (one object per detected gap)
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_FindingDetail",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Finding Detail", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "JSON document of structured findings produced by "
                            "the validation run"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "Format": "Text",
            "MaxLength": 100000,
        },
        # UTC timestamp of execution
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
                        "Label": "UTC timestamp when the validation was executed",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "TimeZoneIndependent"},
        },
        # Solution version under test
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AgentVersion",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Agent Version", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Solution/agent version that was validated",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 50,
            "FormatName": {"Value": "Text"},
        },
        # SHA-256 hash of the finding detail (tamper evidence)
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_EvidenceHash",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Evidence Hash", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "SHA-256 hash (hex) of the finding detail for "
                            "tamper-evident evidence"
                        ),
                        "LanguageCode": 1033,
                    }
                ]
            },
            "MaxLength": 64,
            "FormatName": {"Value": "Text"},
        },
        # Number of resilience gaps detected
        {
            "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_GapCount",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Gap Count", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": "Number of resilience gaps detected by the validation",
                        "LanguageCode": 1033,
                    }
                ]
            },
            "Format": "None",
            "MinValue": 0,
            "MaxValue": 100000,
        },
        # Composite promotion-ready gate
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_PromotionReady",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {
                "LocalizedLabels": [
                    {"Label": "Promotion Ready", "LanguageCode": 1033}
                ]
            },
            "Description": {
                "LocalizedLabels": [
                    {
                        "Label": (
                            "Composite gate: true only when all structural checks "
                            "pass and the early-release readiness probe passes"
                        ),
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
        # Short correlation ID linking this row to the on-disk audit log file
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
                            "Short hex correlation ID linking this result to the "
                            "audit log file on disk and to sibling rows in the run"
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

    # Header
    lines.append("# Dataverse Schema Reference")
    lines.append("")
    lines.append(
        "> Auto-generated from `create_erv_dataverse_schema.py`. "
        "Do not edit manually."
    )
    lines.append("")
    lines.append(
        "This schema records pre-promotion resilience validation evidence for "
        "Copilot Studio agents, supporting OCC 2011-12 / Fed SR 11-7 pre-deployment "
        "validation, SEC 17a-4 evidence retention, and FINRA 4511 change-control "
        "records. It records validation findings, not agent runtime behavior."
    )
    lines.append("")

    # Tables
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

    # Columns (per table)
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

    # Option Sets
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
            "Create Dataverse schema for the Early-Release Validation solution "
            "(OCC 2011-12, Fed SR 11-7, SEC 17a-4, FINRA 4511)"
        ),
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("ERV_TENANT_ID"),
        help="Entra ID tenant ID (or set ERV_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("ERV_CLIENT_ID"),
        help="Application (client) ID (or set ERV_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--access-token",
        default=os.environ.get("ERV_ACCESS_TOKEN"),
        help="Dataverse access token from managed identity or workload federation (or set ERV_ACCESS_TOKEN env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("ERV_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set ERV_ENVIRONMENT_URL env var)",
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

    if not args.environment_url:
        parser.error(
            "Missing required argument. Provide --environment-url "
            "(or set ERV_ENVIRONMENT_URL env var)"
        )
    if not args.access_token and not args.tenant_id:
        parser.error(
            "--tenant-id is required unless --access-token/ERV_ACCESS_TOKEN is provided"
        )
    if not args.access_token and not args.client_id and not args.interactive:
        parser.error(
            "--client-id is required unless --interactive or --access-token is specified"
        )

    client_secret = os.environ.get("ERV_CLIENT_SECRET")
    if not args.access_token and not args.interactive:
        if not client_secret:
            import getpass

            # legacy: dev-only — replace with managed identity in production
            client_secret = getpass.getpass("Client secret: ")

    try:
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            access_token=args.access_token,
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
