#!/usr/bin/env python3
"""Create Dataverse schema for the Agent Eligibility Gateway.

Creates the optional ``fsi_AegDecisionLog`` per-decision audit table (with its
columns, choice fields, and supporting option sets) used to persist the
allow/deny decisions emitted by the Azure API Management gateway. Reuses the
shared ACV zone option set (``fsi_acv_zone``) when present.

The decision-log table is OPTIONAL: the gateway emits a structured telemetry
record for every decision regardless. This table is the landing store when an
organization wants the decisions in Dataverse alongside the rest of the
governance evidence (and surfaced on the Copilot Hub / governance dashboard,
control 3.8). The telemetry sink (Event Hub -> Function / Stream Analytics)
writes rows here; see ``templates/decision-log.sample.json`` for the row shape.

Authentication is managed-identity-first. Pass an externally-acquired token
(``--access-token`` / ``AEG_ACCESS_TOKEN``) or select ``--auth-mode
managed-identity`` / ``workload-identity`` when running inside Azure. Client
secret is a documented dev-only fallback.

Run ``python scripts/create_aeg_dataverse_schema.py --output-docs`` to
regenerate ``docs/dataverse-schema.md`` without any credentials.
"""

import argparse
import os
import sys

import requests

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"))
from dataverse_client import DataverseClient  # noqa: E402

PUBLISHER_PREFIX = "fsi"

# Shared option set reused from ACV - only created if missing.
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
}

# Agent Eligibility Gateway (AEG) specific option sets. Values use the
# repository-wide 100000000+ convention. These mirror the labels the APIM
# eligibility policy emits in its decision telemetry.
OPTIONSETS = {
    "fsi_aeg_decision": {
        "Name": "fsi_aeg_decision",
        "DisplayName": {"LocalizedLabels": [{"Label": "Gateway Decision", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Allow or deny decision rendered by the gateway", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "Allow", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "Deny", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_aeg_denyreason": {
        "Name": "fsi_aeg_denyreason",
        "DisplayName": {"LocalizedLabels": [{"Label": "Deny Reason", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Reason an allow/deny decision resolved to deny (None for allow)", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "None", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "JwtValidationFailed", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "MissingRequiredClaim", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "OutOfPolicyAudience", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "NotInEligibleCohort", "LanguageCode": 1033}]}},
            {"Value": 100000005, "Label": {"LocalizedLabels": [{"Label": "AgentNonCompliant", "LanguageCode": 1033}]}},
            {"Value": 100000006, "Label": {"LocalizedLabels": [{"Label": "GovernanceStoreUnavailable", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_aeg_pathway": {
        "Name": "fsi_aeg_pathway",
        "DisplayName": {"LocalizedLabels": [{"Label": "Agent Pathway", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Classified billing/runtime pathway used by the entitlement contract", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "None", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "McpCopilotStudio", "LanguageCode": 1033}]}},
            {"Value": 100000002, "Label": {"LocalizedLabels": [{"Label": "McpAgentBuilder", "LanguageCode": 1033}]}},
            {"Value": 100000003, "Label": {"LocalizedLabels": [{"Label": "ApiDirect", "LanguageCode": 1033}]}},
            {"Value": 100000004, "Label": {"LocalizedLabels": [{"Label": "Metered", "LanguageCode": 1033}]}},
            {"Value": 100000005, "Label": {"LocalizedLabels": [{"Label": "Unmapped", "LanguageCode": 1033}]}},
        ],
    },
    "fsi_aeg_channel": {
        "Name": "fsi_aeg_channel",
        "DisplayName": {"LocalizedLabels": [{"Label": "Owned Channel", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Owned channel the gateway fronts (first-party surfaces are out of scope)", "LanguageCode": 1033}]},
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": 100000000, "Label": {"LocalizedLabels": [{"Label": "CustomWeb", "LanguageCode": 1033}]}},
            {"Value": 100000001, "Label": {"LocalizedLabels": [{"Label": "DirectLine", "LanguageCode": 1033}]}},
        ],
    },
}

# Table definition. Organization-owned, audit-enabled: this is an immutable
# regulatory audit trail. Remove Write/Delete privileges post-deployment.
TABLES = {
    "fsi_AegDecisionLog": {
        "SchemaName": "fsi_AegDecisionLog",
        "DisplayName": {"LocalizedLabels": [{"Label": "AEG Decision Log", "LanguageCode": 1033}]},
        "DisplayCollectionName": {"LocalizedLabels": [{"Label": "AEG Decision Logs", "LanguageCode": 1033}]},
        "Description": {"LocalizedLabels": [{"Label": "Immutable per-decision audit log of Agent Eligibility Gateway allow/deny outcomes", "LanguageCode": 1033}]},
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
                "DisplayName": {"LocalizedLabels": [{"Label": "Decision ID", "LanguageCode": 1033}]},
                "Description": {"LocalizedLabels": [{"Label": "Decision identifier (typically the correlation ID)", "LanguageCode": 1033}]},
                "MaxLength": 200,
                "FormatName": {"Value": "Text"},
            }
        ],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_name",
    },
}

# Non-primary columns, keyed by table LOGICAL name.
COLUMNS = {
    "fsi_aegdecisionlog": [
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_CorrelationId",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Correlation ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Correlation ID stamped on the request and the governed response", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_DecisionTime",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Decision Time", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "UTC timestamp when the gateway rendered the decision", "LanguageCode": 1033}]},
            "Format": "DateAndTime",
            "DateTimeBehavior": {"Value": "TimeZoneIndependent"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_AgentId",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Agent ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Identifier of the agent the request targeted", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_UserObjectId",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "User Object ID", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Microsoft Entra object ID (oid) of the caller; pseudonymous, not the UPN", "LanguageCode": 1033}]},
            "MaxLength": 100,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Channel",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Channel", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Owned channel that the gateway fronted", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_aeg_channel')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Pathway",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Pathway", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Classified pathway used by the entitlement contract", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_aeg_pathway')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Decision",
            "RequiredLevel": {"Value": "ApplicationRequired"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Decision", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Allow or deny outcome", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_aeg_decision')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_DenyReason",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Deny Reason", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Reason a decision resolved to deny (None for allow)", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_aeg_denyreason')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_HttpStatus",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "HTTP Status", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "HTTP status code returned to the caller (200 allow, 401/403 deny)", "LanguageCode": 1033}]},
            "MinValue": 0,
            "MaxValue": 599,
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Anomaly",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Anomaly", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "True when the pathway could not be classified and the request was allowed fail-open", "LanguageCode": 1033}]},
            "DefaultValue": False,
            "OptionSet": {
                "TrueOption": {"Value": 1, "Label": {"LocalizedLabels": [{"Label": "Yes", "LanguageCode": 1033}]}},
                "FalseOption": {"Value": 0, "Label": {"LocalizedLabels": [{"Label": "No", "LanguageCode": 1033}]}},
            },
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_PolicyVersion",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Policy Version", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Version string of the gateway policy that rendered the decision", "LanguageCode": 1033}]},
            "MaxLength": 50,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_GatewayInstance",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Gateway Instance", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "API Management instance/region that rendered the decision", "LanguageCode": 1033}]},
            "MaxLength": 200,
            "FormatName": {"Value": "Text"},
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_Zone",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Zone", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "Governance zone classification", "LanguageCode": 1033}]},
            "GlobalOptionSet@odata.bind": "/GlobalOptionSetDefinitions(Name='fsi_acv_zone')",
        },
        {
            "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
            "SchemaName": f"{PUBLISHER_PREFIX}_RawContext",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": {"LocalizedLabels": [{"Label": "Raw Context", "LanguageCode": 1033}]},
            "Description": {"LocalizedLabels": [{"Label": "JSON snapshot of the decision inputs for audit reconstruction", "LanguageCode": 1033}]},
            "MaxLength": 100000,
            "Format": "Text",
        },
    ],
}


def create_optionsets(client: DataverseClient) -> dict:
    """Create global option sets (shared and AEG-specific)."""
    print("\n=== Creating Option Sets ===")
    created = 0
    skipped = 0

    print("\nShared option sets (reused from ACV):")
    for name, metadata in SHARED_OPTIONSETS.items():
        if client.get_global_optionset(name):
            print(f"  {name}: Already exists (reusing)")
            skipped += 1
        else:
            print(f"  {name}: Creating")
            client.create_option_set(metadata)
            created += 1

    print("\nAEG-specific option sets:")
    for name, metadata in OPTIONSETS.items():
        if client.get_global_optionset(name):
            print(f"  {name}: Already exists")
            skipped += 1
        else:
            print(f"  {name}: Creating")
            client.create_option_set(metadata)
            created += 1

    return {"created": created, "skipped": skipped}


def create_tables(client: DataverseClient) -> dict:
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


def create_columns(client: DataverseClient) -> None:
    """Create non-primary columns on tables."""
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


def create_schema(client: DataverseClient) -> dict:
    """Create the complete schema (orchestrator)."""
    errors = 0
    option_set_results = create_optionsets(client)
    table_results = create_tables(client)
    try:
        create_columns(client)
    except Exception as exc:  # noqa: BLE001 - surface and continue summary
        print(f"  Column creation error: {exc}")
        errors += 1
    print("\n=== Schema Creation Complete ===")
    return {
        "errors": errors,
        "option_sets": option_set_results,
        "tables": table_results,
    }


def _label(localized: dict) -> str:
    """Return the en-US label from a Dataverse LocalizedLabels structure."""
    labels = localized.get("LocalizedLabels", []) if localized else []
    return labels[0]["Label"] if labels else ""


def _col_type(col: dict) -> str:
    """Return a friendly type name from a column's @odata.type."""
    odata_type = col.get("@odata.type", "")
    mapping = {
        "StringAttributeMetadata": "String",
        "MemoAttributeMetadata": "Memo",
        "DateTimeAttributeMetadata": "DateTime",
        "PicklistAttributeMetadata": "Option Set",
        "BooleanAttributeMetadata": "Boolean",
        "IntegerAttributeMetadata": "Integer",
    }
    for suffix, friendly in mapping.items():
        if odata_type.endswith(suffix):
            if friendly == "String":
                return f"String ({col.get('MaxLength', '')})"
            return friendly
    return odata_type.split(".")[-1] or "Unknown"


def _bound_optionset(col: dict) -> str:
    """Return the global option-set name a picklist column binds to."""
    bind = col.get("GlobalOptionSet@odata.bind", "")
    if "Name='" in bind:
        return bind.split("Name='", 1)[1].rstrip("')")
    return ""


def generate_schema_docs() -> str:
    """Generate a Markdown reference document from the in-memory schema."""
    lines: list[str] = []
    lines.append("# Agent Eligibility Gateway Dataverse Schema")
    lines.append("")
    lines.append("> Auto-generated from `scripts/create_aeg_dataverse_schema.py`. Do not edit manually.")
    lines.append("> Regenerate with `python scripts/create_aeg_dataverse_schema.py --output-docs`.")
    lines.append("")
    lines.append("## Overview")
    lines.append("")
    lines.append(
        "The Agent Eligibility Gateway uses a single optional Dataverse table, "
        "`fsi_aegdecisionlog`, to persist the per-decision audit trail emitted by the "
        "Azure API Management gateway. The table is organization-owned and audit-enabled "
        "so it can serve as an immutable record; remove Write/Delete privileges after "
        "deployment. Persisting decisions here is optional — the gateway emits the same "
        "record to its telemetry sink regardless — but doing so surfaces the decisions on "
        "the Copilot Hub / governance dashboard (control 3.8)."
    )
    lines.append("")

    lines.append("## Tables")
    lines.append("")
    lines.append("| SchemaName | Logical Name | Entity Set | Ownership | Description |")
    lines.append("|---|---|---|---|---|")
    for schema_name, tbl in TABLES.items():
        logical = schema_name.lower()
        entity_set = f"{logical}s"
        ownership = tbl.get("OwnershipType", "")
        desc = _label(tbl.get("Description", {}))
        lines.append(f"| {schema_name} | {logical} | {entity_set} | {ownership} | {desc} |")
    lines.append("")

    lines.append("## Columns")
    lines.append("")
    for table_schema_name, tbl in TABLES.items():
        table_logical = table_schema_name.lower()
        primary_attrs = tbl.get("Attributes", [])
        extra_cols = COLUMNS.get(table_logical, [])
        all_cols = primary_attrs + extra_cols

        lines.append(f"### {table_schema_name} (`{table_logical}`)")
        lines.append("")
        lines.append("| SchemaName | Logical Name | Type | Required | Description | Option Set |")
        lines.append("|---|---|---|---|---|---|")
        for col in all_cols:
            schema_name = col.get("SchemaName", "")
            logical = schema_name.lower()
            ctype = _col_type(col)
            req_val = col.get("RequiredLevel", {}).get("Value", "None")
            required = "Yes" if req_val == "ApplicationRequired" else "No"
            desc = _label(col.get("Description", {}))
            os_cell = ""
            os_name = _bound_optionset(col)
            if os_name:
                os_cell = f"`{os_name}`"
            elif ctype == "Boolean":
                os_cell = "`1` = Yes, `0` = No"
            lines.append(f"| {schema_name} | {logical} | {ctype} | {required} | {desc} | {os_cell} |")
        lines.append("")

    lines.append("## Option Sets")
    lines.append("")
    lines.append("### Shared")
    lines.append("")
    for name, osdef in SHARED_OPTIONSETS.items():
        lines.append(f"#### {name}")
        lines.append("")
        lines.append(_label(osdef.get("Description", {})))
        lines.append("")
        lines.append("| Value | Label |")
        lines.append("|---|---|")
        for opt in osdef.get("Options", []):
            lines.append(f"| {opt['Value']} | {_label(opt['Label'])} |")
        lines.append("")

    lines.append("### Agent Eligibility Gateway")
    lines.append("")
    for name, osdef in OPTIONSETS.items():
        lines.append(f"#### {name}")
        lines.append("")
        lines.append(_label(osdef.get("Description", {})))
        lines.append("")
        lines.append("| Value | Label |")
        lines.append("|---|---|")
        for opt in osdef.get("Options", []):
            lines.append(f"| {opt['Value']} | {_label(opt['Label'])} |")
        lines.append("")

    return "\n".join(lines) + "\n"


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Create Dataverse schema for the Agent Eligibility Gateway",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--tenant-id", default=os.environ.get("AEG_TENANT_ID"), help="Entra ID tenant ID (or set AEG_TENANT_ID env var)")
    parser.add_argument("--client-id", default=os.environ.get("AEG_CLIENT_ID"), help="Application (client) ID; optional for system-assigned managed identity")
    parser.add_argument("--environment-url", default=os.environ.get("AEG_ENVIRONMENT_URL"), help="Dataverse environment URL (or set AEG_ENVIRONMENT_URL env var)")
    parser.add_argument(
        "--auth-mode",
        default=os.environ.get("AEG_AUTH_MODE"),
        choices=["interactive", "managed-identity", "workload-identity", "certificate", "client-secret"],
        help="Authentication mode. Managed-identity-first; prefer managed-identity or workload-identity in Azure.",
    )
    parser.add_argument("--access-token", default=os.environ.get("AEG_ACCESS_TOKEN"), help="Externally-acquired Dataverse bearer token (e.g. from managed identity). Takes precedence over other auth modes.")
    parser.add_argument("--certificate-path", default=os.environ.get("AEG_CERTIFICATE_PATH"), help="Path to certificate for certificate auth")
    parser.add_argument("--certificate-password", default=os.environ.get("AEG_CERTIFICATE_PASSWORD"), help="Optional certificate password")
    parser.add_argument("--interactive", action="store_true", help="Use interactive browser authentication")
    parser.add_argument("--dry-run", action="store_true", help="Preview schema operations without API calls")
    parser.add_argument("--output-docs", action="store_true", help="Generate docs/dataverse-schema.md and exit (no credentials required)")
    args = parser.parse_args()

    # --output-docs short-circuits before any credential handling.
    if args.output_docs:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        solution_root = os.path.dirname(script_dir)
        docs_dir = os.path.join(solution_root, "docs")
        os.makedirs(docs_dir, exist_ok=True)
        out_path = os.path.join(docs_dir, "dataverse-schema.md")
        with open(out_path, "w", encoding="utf-8") as handle:
            handle.write(generate_schema_docs())
        print(f"Schema docs written to {out_path}")
        sys.exit(0)

    if not args.environment_url:
        parser.error("Missing --environment-url (or set AEG_ENVIRONMENT_URL env var)")

    # Resolve the effective auth mode (managed-identity-first).
    auth_mode = args.auth_mode
    if not auth_mode:
        if args.access_token:
            auth_mode = None  # token passthrough; handled by the client
        elif args.interactive:
            auth_mode = "interactive"
        else:
            auth_mode = "client-secret"  # legacy: dev-only fallback

    client_secret = os.environ.get("AEG_CLIENT_SECRET")
    if auth_mode == "client-secret" and not args.access_token and not client_secret:
        # legacy: dev-only - replace with managed identity in production
        import getpass
        client_secret = getpass.getpass("Client secret (dev-only fallback): ")

    try:
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            access_token=args.access_token,
            interactive=args.interactive,
            auth_mode=auth_mode,
            certificate_path=args.certificate_path,
            certificate_password=args.certificate_password,
            dry_run=args.dry_run,
        )

        if args.dry_run:
            print("=== DRY RUN MODE - No changes will be made ===")

        create_schema(client)

        if not args.dry_run:
            print("\nSchema deployment: SUCCESS")
        sys.exit(0)
    except requests.HTTPError as exc:
        print(f"HTTP Error: {exc}", file=sys.stderr)
        sys.exit(2)
    except RuntimeError as exc:
        print(f"Authentication Error: {exc}", file=sys.stderr)
        sys.exit(1)
    except Exception as exc:  # noqa: BLE001 - top-level guard
        print(f"Error: {exc}", file=sys.stderr)
        import traceback
        traceback.print_exc()
        sys.exit(4)


if __name__ == "__main__":
    main()
