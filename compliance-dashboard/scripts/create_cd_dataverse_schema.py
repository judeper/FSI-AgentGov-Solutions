#!/usr/bin/env python3
"""Create Dataverse schema for Compliance Dashboard.

Defines the five CD tables (fsi_controlmaster, fsi_controlassessment,
fsi_compliancescore, fsi_complianceexception, fsi_complianceevidence)
with all columns, choice fields, relationships, and security roles.

Running with ``--output-docs`` regenerates ``docs/dataverse-schema.md``
from the schema definitions below — no Dataverse connection required.
This is the canonical source of truth for CD schema documentation
(Council Review 2026-04-16 finding #1 mitigation).
"""

from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path
from typing import Optional

# ---------------------------------------------------------------------------
# Publisher prefix
# ---------------------------------------------------------------------------
PUBLISHER_PREFIX = "fsi"

# ---------------------------------------------------------------------------
# Choice (OptionSet) Definitions
# ---------------------------------------------------------------------------

OPTIONSETS = {
    "fsi_cd_pillar": {
        "Name": "fsi_cd_pillar",
        "DisplayName": "Governance Pillar",
        "Options": [
            {"Value": 1, "Label": "Security"},
            {"Value": 2, "Label": "Management"},
            {"Value": 3, "Label": "Reporting"},
            {"Value": 4, "Label": "SharePoint"},
        ],
    },
    "fsi_cd_category": {
        "Name": "fsi_cd_category",
        "DisplayName": "Control Category",
        "Options": [
            {"Value": 1, "Label": "Native Microsoft Feature"},
            {"Value": 2, "Label": "Custom Solution Required"},
            {"Value": 3, "Label": "Process/Documentation Control"},
        ],
    },
    "fsi_cd_status": {
        "Name": "fsi_cd_status",
        "DisplayName": "Compliance Status",
        "Options": [
            {"Value": 1, "Label": "Compliant"},
            {"Value": 2, "Label": "Partial"},
            {"Value": 3, "Label": "Non-Compliant"},
            {"Value": 4, "Label": "Not Applicable"},
        ],
    },
    "fsi_cd_zone": {
        "Name": "fsi_cd_zone",
        "DisplayName": "Governance Zone",
        "Options": [
            {"Value": 1, "Label": "Zone 1 - Personal Productivity"},
            {"Value": 2, "Label": "Zone 2 - Team Collaboration"},
            {"Value": 3, "Label": "Zone 3 - Enterprise Managed"},
        ],
    },
    "fsi_cd_severity": {
        "Name": "fsi_cd_severity",
        "DisplayName": "Exception Severity",
        "Options": [
            {"Value": 1, "Label": "Critical"},
            {"Value": 2, "Label": "High"},
            {"Value": 3, "Label": "Medium"},
            {"Value": 4, "Label": "Low"},
        ],
    },
    "fsi_cd_exceptionstatus": {
        "Name": "fsi_cd_exceptionstatus",
        "DisplayName": "Exception Status",
        "Options": [
            {"Value": 1, "Label": "Open"},
            {"Value": 2, "Label": "In Progress"},
            {"Value": 3, "Label": "Pending Verification"},
            {"Value": 4, "Label": "Closed"},
            {"Value": 5, "Label": "Accepted Risk"},
        ],
    },
    "fsi_cd_slastatus": {
        "Name": "fsi_cd_slastatus",
        "DisplayName": "SLA Status",
        "Options": [
            {"Value": 1, "Label": "On Track"},
            {"Value": 2, "Label": "At Risk"},
            {"Value": 3, "Label": "Breached"},
        ],
    },
    "fsi_cd_evidencetype": {
        "Name": "fsi_cd_evidencetype",
        "DisplayName": "Evidence Type",
        "Options": [
            {"Value": 1, "Label": "Screenshot"},
            {"Value": 2, "Label": "Configuration Export"},
            {"Value": 3, "Label": "Audit Log"},
            {"Value": 4, "Label": "Policy Document"},
            {"Value": 5, "Label": "Test Result"},
            {"Value": 6, "Label": "External Report"},
        ],
    },
}

# ---------------------------------------------------------------------------
# Table and Column Definitions
# ---------------------------------------------------------------------------

TABLES: dict[str, dict] = {
    "fsi_controlmaster": {
        "schema_name": "fsi_ControlMaster",
        "display": "Control Master",
        "description": "Master list of 78 FSI Agent Governance Framework controls",
        "ownership": "Organization",
        "columns": [
            {"SchemaName": "fsi_ControlId", "LogicalName": "fsi_controlid", "Type": "String(10)", "Required": True, "Description": "Control identifier (e.g., 1.1, 2.12)"},
            {"SchemaName": "fsi_Name", "LogicalName": "fsi_name", "Type": "String(200)", "Required": True, "Description": "Control display name (primary column)"},
            {"SchemaName": "fsi_Pillar", "LogicalName": "fsi_pillar", "Type": "Choice (fsi_cd_pillar)", "Required": True, "Description": "Governance pillar (1-4)"},
            {"SchemaName": "fsi_Description", "LogicalName": "fsi_description", "Type": "Memo(4000)", "Required": False, "Description": "Control description"},
            {"SchemaName": "fsi_Zone1Applicable", "LogicalName": "fsi_zone1applicable", "Type": "Boolean", "Required": True, "Description": "Applicable to Zone 1"},
            {"SchemaName": "fsi_Zone2Applicable", "LogicalName": "fsi_zone2applicable", "Type": "Boolean", "Required": True, "Description": "Applicable to Zone 2"},
            {"SchemaName": "fsi_Zone3Applicable", "LogicalName": "fsi_zone3applicable", "Type": "Boolean", "Required": True, "Description": "Applicable to Zone 3"},
            {"SchemaName": "fsi_RegulatoryReference", "LogicalName": "fsi_regulatoryreference", "Type": "String(500)", "Required": False, "Description": "Related regulations (FINRA, SEC, etc.)"},
            {"SchemaName": "fsi_Weight", "LogicalName": "fsi_weight", "Type": "Decimal", "Required": True, "Description": "Control weight for scoring (1.0-3.0)"},
            {"SchemaName": "fsi_Category", "LogicalName": "fsi_category", "Type": "Choice (fsi_cd_category)", "Required": False, "Description": "Control category classification"},
        ],
    },
    "fsi_controlassessment": {
        "schema_name": "fsi_ControlAssessment",
        "display": "Control Assessment",
        "description": "Assessment records for each control, capturing compliance status",
        "ownership": "User",
        "columns": [
            {"SchemaName": "fsi_ControlMasterId", "LogicalName": "fsi_controlmasterid", "Type": "Lookup (fsi_controlmaster)", "Required": True, "Description": "Reference to control master"},
            {"SchemaName": "fsi_AssessmentDate", "LogicalName": "fsi_assessmentdate", "Type": "DateTime", "Required": True, "Description": "Date of assessment"},
            {"SchemaName": "fsi_Status", "LogicalName": "fsi_status", "Type": "Choice (fsi_cd_status)", "Required": True, "Description": "Compliance status"},
            {"SchemaName": "fsi_Zone", "LogicalName": "fsi_zone", "Type": "Choice (fsi_cd_zone)", "Required": True, "Description": "Governance zone being assessed"},
            {"SchemaName": "fsi_Score", "LogicalName": "fsi_score", "Type": "Integer", "Required": True, "Description": "Numeric score (0, 50, 100)"},
            {"SchemaName": "fsi_Assessor", "LogicalName": "fsi_assessor", "Type": "Lookup (systemuser)", "Required": True, "Description": "Person who performed assessment"},
            {"SchemaName": "fsi_Notes", "LogicalName": "fsi_notes", "Type": "Memo(4000)", "Required": False, "Description": "Assessment notes"},
            {"SchemaName": "fsi_NextReviewDate", "LogicalName": "fsi_nextreviewdate", "Type": "DateTime", "Required": False, "Description": "Scheduled next review date"},
            {"SchemaName": "fsi_EvidenceCount", "LogicalName": "fsi_evidencecount", "Type": "Integer", "Required": False, "Description": "Number of linked evidence items"},
        ],
    },
    "fsi_compliancescore": {
        "schema_name": "fsi_ComplianceScore",
        "display": "Compliance Score",
        "description": "Daily compliance score snapshots for trend analysis",
        "ownership": "Organization",
        "columns": [
            {"SchemaName": "fsi_ScoreDate", "LogicalName": "fsi_scoredate", "Type": "Date", "Required": True, "Description": "Score calculation date"},
            {"SchemaName": "fsi_OverallScore", "LogicalName": "fsi_overallscore", "Type": "Decimal", "Required": True, "Description": "Overall compliance score (0-100)"},
            {"SchemaName": "fsi_Pillar1Score", "LogicalName": "fsi_pillar1score", "Type": "Decimal", "Required": False, "Description": "Security pillar score"},
            {"SchemaName": "fsi_Pillar2Score", "LogicalName": "fsi_pillar2score", "Type": "Decimal", "Required": False, "Description": "Management pillar score"},
            {"SchemaName": "fsi_Pillar3Score", "LogicalName": "fsi_pillar3score", "Type": "Decimal", "Required": False, "Description": "Reporting pillar score"},
            {"SchemaName": "fsi_Pillar4Score", "LogicalName": "fsi_pillar4score", "Type": "Decimal", "Required": False, "Description": "SharePoint pillar score"},
            {"SchemaName": "fsi_Zone1Score", "LogicalName": "fsi_zone1score", "Type": "Decimal", "Required": False, "Description": "Zone 1 compliance score"},
            {"SchemaName": "fsi_Zone2Score", "LogicalName": "fsi_zone2score", "Type": "Decimal", "Required": False, "Description": "Zone 2 compliance score"},
            {"SchemaName": "fsi_Zone3Score", "LogicalName": "fsi_zone3score", "Type": "Decimal", "Required": False, "Description": "Zone 3 compliance score"},
            {"SchemaName": "fsi_CompliantCount", "LogicalName": "fsi_compliantcount", "Type": "Integer", "Required": True, "Description": "Count of compliant controls"},
            {"SchemaName": "fsi_PartialCount", "LogicalName": "fsi_partialcount", "Type": "Integer", "Required": True, "Description": "Count of partially compliant controls"},
            {"SchemaName": "fsi_NoncompliantCount", "LogicalName": "fsi_noncompliantcount", "Type": "Integer", "Required": True, "Description": "Count of non-compliant controls"},
            {"SchemaName": "fsi_ExceptionCount", "LogicalName": "fsi_exceptioncount", "Type": "Integer", "Required": True, "Description": "Count of open exceptions"},
        ],
    },
    "fsi_complianceexception": {
        "schema_name": "fsi_ComplianceException",
        "display": "Compliance Exception",
        "description": "Open compliance exceptions requiring remediation",
        "ownership": "User",
        "columns": [
            {"SchemaName": "fsi_Name", "LogicalName": "fsi_name", "Type": "String(200)", "Required": True, "Description": "Exception title (primary column)"},
            {"SchemaName": "fsi_ControlAssessmentId", "LogicalName": "fsi_controlassessmentid", "Type": "Lookup (fsi_controlassessment)", "Required": True, "Description": "Related assessment"},
            {"SchemaName": "fsi_Severity", "LogicalName": "fsi_severity", "Type": "Choice (fsi_cd_severity)", "Required": True, "Description": "Exception severity (Critical/High/Medium/Low)"},
            {"SchemaName": "fsi_ExceptionStatus", "LogicalName": "fsi_exceptionstatus", "Type": "Choice (fsi_cd_exceptionstatus)", "Required": True, "Description": "Exception lifecycle status"},
            {"SchemaName": "fsi_Owner", "LogicalName": "fsi_owner", "Type": "Lookup (systemuser)", "Required": True, "Description": "Assigned remediation owner"},
            {"SchemaName": "fsi_Description", "LogicalName": "fsi_description", "Type": "Memo(4000)", "Required": True, "Description": "Exception description"},
            {"SchemaName": "fsi_RootCause", "LogicalName": "fsi_rootcause", "Type": "Memo(4000)", "Required": False, "Description": "Root cause analysis"},
            {"SchemaName": "fsi_RemediationPlan", "LogicalName": "fsi_remediationplan", "Type": "Memo(4000)", "Required": False, "Description": "Planned remediation steps"},
            {"SchemaName": "fsi_TargetDate", "LogicalName": "fsi_targetdate", "Type": "Date", "Required": True, "Description": "Target remediation date"},
            {"SchemaName": "fsi_ActualCloseDate", "LogicalName": "fsi_actualclosedate", "Type": "Date", "Required": False, "Description": "Actual close date"},
            {"SchemaName": "fsi_DaysOpen", "LogicalName": "fsi_daysopen", "Type": "Integer", "Required": False, "Description": "Days exception has been open (calculated)"},
            {"SchemaName": "fsi_SlaStatus", "LogicalName": "fsi_slastatus", "Type": "Choice (fsi_cd_slastatus)", "Required": False, "Description": "SLA status (On Track/At Risk/Breached)"},
        ],
    },
    "fsi_complianceevidence": {
        "schema_name": "fsi_ComplianceEvidence",
        "display": "Compliance Evidence",
        "description": "Evidence items linked to assessments for audit purposes",
        "ownership": "User",
        "columns": [
            {"SchemaName": "fsi_Name", "LogicalName": "fsi_name", "Type": "String(200)", "Required": True, "Description": "Evidence title (primary column)"},
            {"SchemaName": "fsi_ControlAssessmentId", "LogicalName": "fsi_controlassessmentid", "Type": "Lookup (fsi_controlassessment)", "Required": True, "Description": "Related assessment"},
            {"SchemaName": "fsi_EvidenceType", "LogicalName": "fsi_evidencetype", "Type": "Choice (fsi_cd_evidencetype)", "Required": True, "Description": "Type of evidence"},
            {"SchemaName": "fsi_SourceUrl", "LogicalName": "fsi_sourceurl", "Type": "String(2000)", "Required": False, "Description": "Link to evidence source"},
            {"SchemaName": "fsi_EvidenceDescription", "LogicalName": "fsi_evidencedescription", "Type": "Memo(4000)", "Required": False, "Description": "Evidence description"},
            {"SchemaName": "fsi_CollectedDate", "LogicalName": "fsi_collecteddate", "Type": "DateTime", "Required": True, "Description": "Date evidence was collected"},
            {"SchemaName": "fsi_CollectedBy", "LogicalName": "fsi_collectedby", "Type": "Lookup (systemuser)", "Required": True, "Description": "Person who collected evidence"},
            {"SchemaName": "fsi_Hash", "LogicalName": "fsi_hash", "Type": "String(64)", "Required": False, "Description": "SHA-256 hash for integrity verification"},
        ],
    },
}


# ---------------------------------------------------------------------------
# Documentation Generator (--output-docs)
# ---------------------------------------------------------------------------


def generate_docs(output_path: str) -> None:
    """Generate Markdown documentation of the Dataverse schema.

    Writes a ``docs/dataverse-schema.md`` file with all tables, columns,
    option sets, and relationships rendered as Markdown tables.

    Args:
        output_path: Filesystem path for the generated Markdown file.
    """
    lines: list[str] = [
        "# Compliance Dashboard — Dataverse Schema Reference",
        "",
        "<!-- Auto-generated by create_cd_dataverse_schema.py --output-docs -->",
        "<!-- Do not edit manually — regenerate with: -->",
        "<!-- python scripts/create_cd_dataverse_schema.py --output-docs -->",
        "",
    ]

    # Option Sets
    lines.extend(["## Option Sets", ""])
    for os_name, os_def in OPTIONSETS.items():
        lines.extend([
            f"### {os_def['DisplayName']} (`{os_name}`)",
            "",
            "| Value | Label |",
            "|-------|-------|",
        ])
        for opt in os_def["Options"]:
            lines.append(f"| {opt['Value']} | {opt['Label']} |")
        lines.append("")

    # Tables
    lines.extend(["## Tables", ""])
    for table_name, table_def in TABLES.items():
        lines.extend([
            f"### {table_def['display']} (`{table_def['schema_name']}`)",
            "",
            f"**Logical Name:** `{table_name}`  ",
            f"**Ownership:** {table_def['ownership']}  ",
            f"**Description:** {table_def['description']}",
            "",
            "| SchemaName | Logical Name | Type | Required | Description |",
            "|-----------|-------------|------|----------|-------------|",
        ])
        for col in table_def["columns"]:
            req = "Yes" if col["Required"] else "No"
            lines.append(
                f"| {col['SchemaName']} | {col['LogicalName']} "
                f"| {col['Type']} | {req} | {col['Description']} |"
            )
        lines.append("")

    # Relationships
    lines.extend([
        "## Relationships",
        "",
        "| Parent Table | Child Table | Relationship |",
        "|-------------|-------------|--------------|",
        "| fsi_controlmaster | fsi_controlassessment | 1:N |",
        "| fsi_controlassessment | fsi_complianceexception | 1:N |",
        "| fsi_controlassessment | fsi_complianceevidence | 1:N |",
        "",
        "---",
        "",
        "*Auto-generated from create_cd_dataverse_schema.py schema definitions.*",
        "",
    ])

    output_dir = os.path.dirname(output_path)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines))
    print(f"  Schema documentation written to: {output_path}")


# ---------------------------------------------------------------------------
# CLI
# ---------------------------------------------------------------------------


def main() -> None:
    """CLI entry point for schema deployment or documentation generation."""
    parser = argparse.ArgumentParser(
        description="Create Dataverse schema for Compliance Dashboard",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Generate schema documentation only (no Dataverse connection)\n"
            "  python create_cd_dataverse_schema.py --output-docs\n\n"
            "  # Dry run with interactive auth\n"
            "  python create_cd_dataverse_schema.py --dry-run --interactive\n"
        ),
    )
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("CD_TENANT_ID"),
        help="Microsoft Entra ID tenant ID (or set CD_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("CD_CLIENT_ID"),
        help="App registration client ID (or set CD_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("CD_CLIENT_SECRET"),
        help="Client secret — legacy dev-only fallback (or set CD_CLIENT_SECRET env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("CD_ENVIRONMENT_URL"),
        help="Dataverse environment URL (or set CD_ENVIRONMENT_URL env var)",
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

    if args.output_docs:
        script_dir = Path(__file__).resolve().parent
        docs_path = script_dir.parent / "docs" / "dataverse-schema.md"
        generate_docs(str(docs_path))
        print("Documentation generation complete.")
        sys.exit(0)

    # Deployment mode requires connection parameters
    if not args.tenant_id:
        print("ERROR: --tenant-id or CD_TENANT_ID required for deployment", file=sys.stderr)
        sys.exit(1)
    if not args.environment_url:
        print("ERROR: --environment-url or CD_ENVIRONMENT_URL required for deployment", file=sys.stderr)
        sys.exit(1)

    print("Compliance Dashboard — Dataverse Schema Deployment")
    print("=" * 55)
    if args.dry_run:
        print("\n*** DRY RUN — No changes will be made ***\n")

    print(f"  Option sets: {len(OPTIONSETS)}")
    print(f"  Tables:      {len(TABLES)}")
    total_cols = sum(len(t['columns']) for t in TABLES.values())
    print(f"  Columns:     {total_cols}")
    print("\nNote: Actual Dataverse deployment requires a client module.")
    print("Use --output-docs to generate schema documentation.")


if __name__ == "__main__":
    main()
