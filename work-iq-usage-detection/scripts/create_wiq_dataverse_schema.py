#!/usr/bin/env python3
"""Create Dataverse schema for Work IQ Usage Detection.

Deploys the two solution-owned tables and four global option sets that back
the two-tier (configuration + telemetry) Work IQ usage detection model. The
agent master record (``fsi_copilotagent``) is owned by the
``copilot-agent-inventory`` solution and is NOT created here; this schema only
references it by value through ``fsi_agentid``.

Tables:
  - fsi_wiqstate (OrganizationOwned): One canonical four-state observed-usage
    row per agent per scan run (the join of Tier-A config and Tier-B telemetry).
  - fsi_wiqkpi (OrganizationOwned): Per-run rollup of the three headline KPIs
    and the four-state distribution.

Option sets:
  - fsi_wiq_zone: Governance zone classification.
  - fsi_wiq_configuredtier: Tier-A configuration pathway.
  - fsi_wiq_observedstatus: The canonical four-state observed-usage model.
  - fsi_wiq_telemetrysource: Tier-B telemetry source that observed an invocation.

All operations are idempotent and safe to re-run. ``--output-docs`` regenerates
``docs/dataverse-schema.md`` from these definitions without a Dataverse
connection (standard-library only).
"""

import argparse
import os
import sys
from pathlib import Path

# Publisher prefix for custom entities.
PUBLISHER_PREFIX = "fsi"

# =============================================================================
# Option Sets (picklists use 100000000+ values; zone reuses the 0-3 convention)
# =============================================================================

WIQ_OPTIONSETS = {
    "fsi_wiq_zone": {
        "name": "fsi_wiq_zone",
        "options": [
            ("Unclassified", 0),
            ("Zone 1", 1),
            ("Zone 2", 2),
            ("Zone 3", 3),
        ],
    },
    "fsi_wiq_configuredtier": {
        "name": "fsi_wiq_configuredtier",
        "options": [
            # Tier-A configuration pathway. native-mcp keys on the Azure Resource
            # Graph createdIn value supplied by copilot-agent-inventory.
            ("NotConfigured", 100000000),
            ("NativeMcpCopilotStudio", 100000001),
            ("NativeApiDirect", 100000002),
            ("Adjacent", 100000003),
        ],
    },
    "fsi_wiq_observedstatus": {
        "name": "fsi_wiq_observedstatus",
        "options": [
            # The canonical four-state observed-usage model. Native-configured
            # agents with only adjacent telemetry resolve to ExceptionUnknown,
            # never ObservedInvoking (see docs/architecture.md truth table).
            ("NotConfigured", 100000000),
            ("ConfiguredNotObserved", 100000001),
            ("ObservedInvoking", 100000002),
            ("ExceptionUnknown", 100000003),
        ],
    },
    "fsi_wiq_telemetrysource": {
        "name": "fsi_wiq_telemetrysource",
        "options": [
            ("None", 100000000),
            ("DefenderCloudAppEvents", 100000001),
            ("AppInsightsCustomEvents", 100000002),
            ("PurviewCopilotInteraction", 100000003),
            ("PurviewAIPluginOperation", 100000004),
        ],
    },
}


# =============================================================================
# Column Definition Helpers
# =============================================================================


def _label(text: str) -> dict:
    """Build a Dataverse Label structure."""
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
    schema_name: str, display: str, max_length: int, required: bool = True,
    description: str = "",
) -> dict:
    """Build a string column definition."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {
            "Value": "ApplicationRequired" if required else "None"
        },
        "MaxLength": max_length,
        "FormatName": {"Value": "Text"},
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _memo_col(
    schema_name: str, display: str, max_length: int,
    description: str = "",
) -> dict:
    """Build a memo (multiline text) column definition."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.MemoAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "None"},
        "MaxLength": max_length,
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _integer_col(
    schema_name: str, display: str, required: bool = True,
    description: str = "",
) -> dict:
    """Build an integer column definition."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {
            "Value": "ApplicationRequired" if required else "None"
        },
        "MinValue": 0,
        "MaxValue": 2147483647,
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _boolean_col(
    schema_name: str, display: str, default: bool = False,
    description: str = "",
) -> dict:
    """Build a boolean column definition."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "DefaultValue": default,
        "OptionSet": {
            "TrueOption": {"Value": 1, "Label": _label("Yes")},
            "FalseOption": {"Value": 0, "Label": _label("No")},
        },
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _datetime_col(
    schema_name: str, display: str, required: bool = True,
    description: str = "",
) -> dict:
    """Build a datetime column definition."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {
            "Value": "ApplicationRequired" if required else "None"
        },
        "Format": "DateAndTime",
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _picklist_col(
    schema_name: str, display: str, global_optionset_name: str,
    required: bool = True, description: str = "",
) -> dict:
    """Build a picklist column bound to a global option set."""
    defn = {
        "@odata.type": "#Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {
            "Value": "ApplicationRequired" if required else "None"
        },
        "OptionSet": None,
        "GlobalOptionSet@odata.bind": (
            f"/GlobalOptionSetDefinitions(Name='{global_optionset_name}')"
        ),
    }
    if description:
        defn["Description"] = _label(description)
    return defn


# =============================================================================
# Table Column Definitions
# =============================================================================

# fsi_wiqstate: the canonical four-state observed-usage record. One row per
# agent per scan run; the join of Tier-A (configuration) and Tier-B (telemetry).
WIQSTATE_COLUMNS = [
    _string_col("fsi_RunId", "Run ID", 36,
                description="GUID correlating all rows written in one scan run"),
    _string_col("fsi_AgentId", "Agent ID", 100,
                description=("Agent identifier; references fsi_copilotagent owned by "
                             "copilot-agent-inventory (value reference, not a lookup)")),
    _string_col("fsi_AgentName", "Agent Name", 500, required=False,
                description="Agent display name (denormalised from fsi_copilotagent)"),
    _string_col("fsi_EnvironmentGuid", "Environment GUID", 100, required=False,
                description="Power Platform environment GUID"),
    _string_col("fsi_EnvironmentName", "Environment Name", 500, required=False,
                description="Environment display name"),
    _picklist_col("fsi_Zone", "Zone", "fsi_wiq_zone", required=False,
                  description="Governance zone classification for the agent"),
    _picklist_col("fsi_ConfiguredTier", "Configured Tier", "fsi_wiq_configuredtier",
                  description=("Tier-A configuration pathway: NotConfigured / "
                               "NativeMcpCopilotStudio / NativeApiDirect / Adjacent")),
    _picklist_col("fsi_ObservedStatus", "Observed Status", "fsi_wiq_observedstatus",
                  description=("Canonical four-state: NotConfigured / "
                               "ConfiguredNotObserved / ObservedInvoking / ExceptionUnknown")),
    _string_col("fsi_ConfigEvidence", "Config Evidence", 2000, required=False,
                description=("botcomponent / aipluginoperation identifiers that triggered "
                             "the Tier-A classification")),
    _integer_col("fsi_ConfigComponentType", "Config Component Type", required=False,
                 description="botcomponent componenttype sampled for config (e.g. 18/15/16)"),
    _string_col("fsi_CreatedIn", "Created In", 200, required=False,
                description=("Azure Resource Graph createdIn value; native-mcp pathway keys "
                             "on this (supplied by copilot-agent-inventory)")),
    _picklist_col("fsi_TelemetrySource", "Telemetry Source", "fsi_wiq_telemetrysource",
                  required=False,
                  description="Tier-B source that observed the most recent invocation"),
    _datetime_col("fsi_LastConfiguredAt", "Last Configured At", required=False,
                  description="When the Work IQ configuration was first detected"),
    _datetime_col("fsi_LastObservedAt", "Last Observed At", required=False,
                  description="Most recent confirmed Work IQ runtime invocation"),
    _integer_col("fsi_DistinctUserCount", "Distinct User Count", required=False,
                 description=("Distinct invoking users within the lookback window "
                              "(count only; no UPNs stored, to limit PII)")),
    _integer_col("fsi_LookbackDays", "Lookback Days", required=False,
                 description="Telemetry lookback window applied for this row"),
    _boolean_col("fsi_Invoked30d", "Invoked 30d", default=False,
                 description="Confirmed Work IQ invocation within the last 30 days"),
    _boolean_col("fsi_Invoked7dByBusinessUsers", "Invoked 7d By Business Users",
                 default=False,
                 description=("Confirmed invocation within 7 days by business (non-maker, "
                              "non-test) users")),
    _datetime_col("fsi_ScanTime", "Scan Time",
                  description="When this state row was computed"),
    _memo_col("fsi_Notes", "Notes", 4000,
              description="Classifier rationale, including any ExceptionUnknown reason"),
    _memo_col("fsi_RawJson", "Raw JSON", 100000,
              description="Full JSON snapshot of the config + telemetry join inputs"),
]

# fsi_wiqkpi: per-run rollup of the three headline KPIs plus the four-state
# distribution. Do NOT duplicate per-agent detail here.
WIQKPI_COLUMNS = [
    _string_col("fsi_RunId", "Run ID", 36,
                description="GUID correlating this rollup to its fsi_wiqstate rows"),
    _datetime_col("fsi_ScanTime", "Scan Time",
                  description="When the rollup was computed"),
    _picklist_col("fsi_Zone", "Zone", "fsi_wiq_zone", required=False,
                  description="Zone scope of the rollup (Unclassified = tenant-wide)"),
    _integer_col("fsi_ConfiguredCount", "Configured Count",
                 description="KPI 1: agents with Work IQ configured (any tier)"),
    _integer_col("fsi_Invoked30dCount", "Invoked 30d Count",
                 description="KPI 2: agents observed invoking within 30 days"),
    _integer_col("fsi_Invoked7dBusinessUsersCount", "Invoked 7d Business Users Count",
                 description="KPI 3: agents invoked within 7 days by business users"),
    _integer_col("fsi_NotConfiguredCount", "Not Configured Count",
                 description="Four-state distribution: NotConfigured"),
    _integer_col("fsi_ConfiguredNotObservedCount", "Configured Not Observed Count",
                 description="Four-state distribution: ConfiguredNotObserved"),
    _integer_col("fsi_ObservedInvokingCount", "Observed Invoking Count",
                 description="Four-state distribution: ObservedInvoking"),
    _integer_col("fsi_ExceptionUnknownCount", "Exception Unknown Count",
                 description="Four-state distribution: ExceptionUnknown"),
    _integer_col("fsi_TotalAgents", "Total Agents",
                 description="Total agents evaluated in the run"),
    _integer_col("fsi_LookbackDays", "Lookback Days",
                 description="Lookback window applied to the invoked KPIs"),
    _memo_col("fsi_SummaryJson", "Summary JSON", 100000,
              description="Full JSON summary blob for the run"),
]


# =============================================================================
# Table Definitions
# =============================================================================

TABLES = {
    "fsi_wiqstate": {
        "schema_name": "fsi_WIQState",
        "display": "WIQ State",
        "plural": "WIQ States",
        "description": (
            "Canonical four-state Work IQ observed-usage record per agent per scan run "
            "(join of Tier-A configuration and Tier-B telemetry); supports compliance "
            "with FINRA Rule 4511 and SEC Rule 17a-3 evidence retention"
        ),
        "ownership": "OrganizationOwned",
        "columns": WIQSTATE_COLUMNS,
        "entity_set_name": None,
    },
    "fsi_wiqkpi": {
        "schema_name": "fsi_WIQKpi",
        "display": "WIQ KPI",
        "plural": "WIQ KPIs",
        "description": (
            "Per-run rollup of the three headline Work IQ usage KPIs and the four-state "
            "distribution for reporting and governance dashboards"
        ),
        "ownership": "OrganizationOwned",
        "columns": WIQKPI_COLUMNS,
        "entity_set_name": None,
    },
}


# =============================================================================
# Metadata Builders for the Shared DataverseClient
# =============================================================================


def _build_optionset_metadata(os_def: dict) -> dict:
    """Build OptionSetMetadata dict for a global option set."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.OptionSetMetadata",
        "Name": os_def["name"],
        "DisplayName": _label(os_def["name"]),
        "IsGlobal": True,
        "OptionSetType": "Picklist",
        "Options": [
            {
                "@odata.type": "Microsoft.Dynamics.CRM.OptionMetadata",
                "Value": value,
                "Label": _label(label),
            }
            for label, value in os_def["options"]
        ],
    }


def _build_table_metadata(table_def: dict) -> dict:
    """Build EntityMetadata dict (table + primary name attribute) for create_table."""
    definition = {
        "@odata.type": "#Microsoft.Dynamics.CRM.EntityMetadata",
        "SchemaName": table_def["schema_name"],
        "DisplayName": _label(table_def["display"]),
        "DisplayCollectionName": _label(table_def["plural"]),
        "Description": _label(table_def["description"]),
        "OwnershipType": table_def["ownership"],
        "IsActivity": False,
        "HasActivities": False,
        "HasNotes": False,
        "IsAuditEnabled": {"Value": True, "CanBeChanged": True},
        "PrimaryNameAttribute": "fsi_name",
        "Attributes": [
            {
                "@odata.type": "#Microsoft.Dynamics.CRM.StringAttributeMetadata",
                "SchemaName": "fsi_name",
                "DisplayName": _label(f"{table_def['display']} Name"),
                "Description": _label("Primary name attribute"),
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "MaxLength": 200,
                "FormatName": {"Value": "Text"},
            },
        ],
    }
    if table_def.get("entity_set_name"):
        definition["EntitySetName"] = table_def["entity_set_name"]
    return definition


# =============================================================================
# Documentation Generator
# =============================================================================


def generate_docs(output_path: str) -> None:
    """Generate Markdown documentation of the Dataverse schema.

    Writes ``dataverse-schema.md`` listing every option set, table, and column
    in Markdown table format. Uses only the in-module definitions, so it runs
    without a Dataverse connection or third-party dependencies.

    Args:
        output_path: Path to write the documentation file.
    """
    lines = [
        "# Work IQ Usage Detection - Dataverse Schema",
        "",
        "Auto-generated by `scripts/create_wiq_dataverse_schema.py --output-docs`.",
        "Do not edit manually.",
        "",
        "> Logical names are the SchemaName lowercased. Dataverse never inserts",
        "> underscores between words, so `fsi_ObservedStatus` has the logical name",
        "> `fsi_observedstatus`. Use logical names in all OData queries.",
        "",
        "The agent master record `fsi_copilotagent` is owned by the",
        "`copilot-agent-inventory` solution and is referenced by value through",
        "`fsi_agentid`; it is not created by this schema.",
        "",
        "## Option Sets",
        "",
        "| Option Set | Values |",
        "|-----------|--------|",
    ]

    for os_name, os_def in WIQ_OPTIONSETS.items():
        values = ", ".join(
            f"{label} ({val})" for label, val in os_def["options"]
        )
        lines.append(f"| {os_name} | {values} |")

    lines.extend(["", "## Tables", ""])

    for _table_name, table_def in TABLES.items():
        logical = table_def["schema_name"].lower()
        lines.extend([
            f"### {table_def['display']} (`{table_def['schema_name']}`, logical `{logical}`)",
            "",
            f"**Ownership:** {table_def['ownership']}",
            "",
            f"**Description:** {table_def['description']}",
            "",
            "| Column (SchemaName) | Logical name | Type | Required | Description |",
            "|---------------------|--------------|------|----------|-------------|",
            "| fsi_Name | fsi_name | String(200) | Yes | Primary name attribute |",
        ])

        for col in table_def["columns"]:
            schema = col["SchemaName"]
            logical_col = schema.lower()
            odata_type = col.get("@odata.type", "")
            required_val = col.get("RequiredLevel", {}).get("Value", "None")
            is_required = "Yes" if required_val == "ApplicationRequired" else "No"
            desc_obj = col.get("Description", {})
            desc = ""
            if desc_obj:
                labels = desc_obj.get("LocalizedLabels", [])
                if labels:
                    desc = labels[0].get("Label", "")

            if "StringAttributeMetadata" in odata_type:
                type_str = f"String({col.get('MaxLength', '')})"
            elif "MemoAttributeMetadata" in odata_type:
                type_str = f"Memo({col.get('MaxLength', '')})"
            elif "IntegerAttributeMetadata" in odata_type:
                type_str = "Integer"
            elif "BooleanAttributeMetadata" in odata_type:
                default = col.get("DefaultValue", False)
                type_str = f"Boolean (default: {str(default).lower()})"
            elif "DateTimeAttributeMetadata" in odata_type:
                type_str = "DateTime"
            elif "PicklistAttributeMetadata" in odata_type:
                bind = col.get("GlobalOptionSet@odata.bind", "")
                os_name = bind.split("'")[1] if "'" in bind else "unknown"
                type_str = f"Picklist ({os_name})"
            else:
                type_str = "Unknown"

            lines.append(
                f"| {schema} | {logical_col} | {type_str} | {is_required} | {desc} |"
            )

        lines.append("")

    output_dir = os.path.dirname(output_path)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"  Documentation written to: {output_path}")


# =============================================================================
# Deployment Functions
# =============================================================================


def create_optionsets(client, dry_run: bool = False) -> None:
    """Create or verify the WIQ global option sets (idempotent)."""
    print("\n[Creating/Verifying Option Sets]")
    for os_name, os_def in WIQ_OPTIONSETS.items():
        if dry_run:
            existing = client.get_global_optionset(os_name)
            print(
                f"  {os_name}: exists, would skip" if existing
                else f"  [DRY RUN] {os_name}: would create"
            )
            continue
        result = client.create_option_set(_build_optionset_metadata(os_def))
        print(
            f"  {os_name}: already exists, skipping" if result is None
            else f"  {os_name}: created"
        )


def create_table_with_columns(
    client, table_name: str, table_def: dict, columns: list, dry_run: bool = False,
) -> None:
    """Create a table and its columns (idempotent)."""
    logical_name = table_name.lower()

    table_exists = client.check_table_exists(logical_name)
    if table_exists:
        print(f"  {logical_name}: already exists, skipping table creation")
    elif dry_run:
        print(f"  [DRY RUN] {logical_name}: would create table")
    else:
        client.create_table(_build_table_metadata(table_def))
        print(f"  {logical_name}: created")

    print(f"  {logical_name} columns:")
    for col in columns:
        col_logical = col["SchemaName"].lower()
        if not table_exists and dry_run:
            print(f"    [DRY RUN] {col_logical}: would create (new table)")
            continue
        existing_col = client.get_attribute_metadata(logical_name, col_logical)
        if existing_col:
            print(f"    {col_logical}: already exists, skipping")
        elif dry_run:
            print(f"    [DRY RUN] {col_logical}: would create")
        else:
            client.create_column(logical_name, col)
            print(f"    {col_logical}: created")


def create_schema(client, dry_run: bool = False) -> None:
    """Orchestrate full schema deployment (option sets, then tables/columns)."""
    print("=" * 60)
    print("WIQ Dataverse Schema Deployment")
    print("  Work IQ Usage Detection")
    print("=" * 60)

    if dry_run:
        print("\n*** DRY RUN - No changes will be made ***\n")

    create_optionsets(client, dry_run)

    print("\n[Creating Tables and Columns]")
    for table_name, table_def in TABLES.items():
        print(f"\n  --- {table_def['display']} ({table_def['ownership']}) ---")
        create_table_with_columns(
            client, table_name, table_def, table_def["columns"], dry_run
        )

    print("\n" + "=" * 60)
    print("DRY RUN COMPLETE - Review output above" if dry_run
          else "SCHEMA DEPLOYMENT COMPLETE")
    print(f"  Option sets: {len(WIQ_OPTIONSETS)}")
    print(f"  Tables: {len(TABLES)}")
    total_cols = sum(len(t["columns"]) for t in TABLES.values())
    print(f"  Columns: {total_cols}")
    print("=" * 60)


# =============================================================================
# CLI Entry Point
# =============================================================================


def main() -> None:
    """CLI entry point for schema deployment / documentation generation."""
    parser = argparse.ArgumentParser(
        description="Create Dataverse schema for Work IQ Usage Detection",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Generate schema documentation only (no connection)\n"
            "  python create_wiq_dataverse_schema.py --output-docs\n\n"
            "  # Dry run with interactive auth\n"
            "  python create_wiq_dataverse_schema.py --dry-run --interactive\n\n"
            "  # Deploy (managed-identity-first; client secret is dev-only fallback)\n"
            "  python create_wiq_dataverse_schema.py \\\n"
            "    --tenant-id $WIQ_TENANT_ID \\\n"
            "    --environment-url $WIQ_ENVIRONMENT_URL\n"
        ),
    )
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("WIQ_TENANT_ID"),
        help="Microsoft Entra ID tenant ID (or set WIQ_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("WIQ_CLIENT_ID"),
        help="App registration / user-assigned managed identity client ID "
             "(or set WIQ_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("WIQ_CLIENT_SECRET"),
        help="Client secret (legacy dev-only fallback; prefer managed identity). "
             "Or set WIQ_CLIENT_SECRET env var",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("WIQ_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set WIQ_ENVIRONMENT_URL env var)",
    )
    parser.add_argument(
        "--auth-mode",
        default=os.environ.get("WIQ_AUTH_MODE"),
        choices=[
            "managed-identity", "workload-identity", "certificate",
            "interactive", "client-secret",
        ],
        help="Authentication mode (managed-identity-first). Defaults to the shared "
             "client's resolution order when omitted",
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
        "--output-docs",
        action="store_true",
        help="Generate docs/dataverse-schema.md and exit (no Dataverse connection)",
    )

    args = parser.parse_args()

    # --output-docs needs no connection and no third-party dependencies.
    if args.output_docs:
        script_dir = Path(__file__).resolve().parent
        docs_path = script_dir.parent / "docs" / "dataverse-schema.md"
        generate_docs(str(docs_path))
        print("Documentation generation complete.")
        sys.exit(0)

    if not args.environment_url:
        print("ERROR: --environment-url or WIQ_ENVIRONMENT_URL required")
        sys.exit(1)

    # Import the shared Dataverse client lazily so --output-docs stays
    # dependency-free. The shared client is managed-identity-first.
    shared_dir = Path(__file__).resolve().parent.parent.parent / "scripts" / "shared"
    if str(shared_dir) not in sys.path:
        sys.path.insert(0, str(shared_dir))
    try:
        from dataverse_client import DataverseClient
    except ImportError as exc:
        print(f"ERROR: could not import shared DataverseClient: {exc}", file=sys.stderr)
        sys.exit(1)

    try:
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=args.client_secret,
            interactive=args.interactive,
            auth_mode=args.auth_mode,
        )
        create_schema(client, dry_run=args.dry_run)
    except Exception as exc:  # noqa: BLE001 - surface any deployment error to the operator
        print(f"Error: {exc}", file=sys.stderr)
        sys.exit(1)


if __name__ == "__main__":
    main()
