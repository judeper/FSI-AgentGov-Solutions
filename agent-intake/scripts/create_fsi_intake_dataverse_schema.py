#!/usr/bin/env python3
"""Create Dataverse schema for Agent Intake (Express + Standard + Full foundations).

Defines 9 tables that capture the intake decision pack for the Express,
Standard, and Full paths, plus the global option sets used for routing,
review, and MRM handoff state. All operations are idempotent.

Tables:
  - fsi_IntakeRequest (UserOwned): The maker's submitted request — parent record
  - fsi_IntakeDataSource (UserOwned): Per-data-source declaration (1..N per request)
  - fsi_IntakeRiskSignal (UserOwned): Trigger-question outcome and any signals raised
  - fsi_IntakeReview (UserOwned): Reviewer activity (sample audit / Standard / Full)
  - fsi_IntakeApproval (UserOwned): Per-approver decision (sponsor + reviewers)
  - fsi_IntakeDecisionLog (OrganizationOwned): Immutable decision-pack record
  - fsi_IntakeSponsorship (UserOwned): Sponsor attestation evidence (FINRA 3110)
  - fsi_IntakeAuditEvent (OrganizationOwned): Lifecycle event audit trail
  - fsi_IntakeRetentionRecord (OrganizationOwned): Retention-label stamping evidence

Usage:
  # Generate schema docs without contacting Dataverse
  python create_fsi_intake_dataverse_schema.py --output-docs ../docs/dataverse-schema.md

  # Dry-run deployment with interactive auth
  python create_fsi_intake_dataverse_schema.py --interactive --dry-run \\
      --environment-url https://org.crm.dynamics.com

  # Deploy with managed identity (recommended for production)
  # The shared DataverseClient supports MSAL token from any source —
  # callers can supply a managed-identity token via the --token-from-env flag.
"""

import argparse
import os
import sys
from pathlib import Path

# Add repo-shared scripts to path so we can import the shared Dataverse client
_REPO_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(_REPO_ROOT / "scripts" / "shared"))

try:
    from dataverse_client import DataverseClient  # type: ignore
except ImportError:
    DataverseClient = None  # type: ignore  # only required for actual deploy


PUBLISHER_PREFIX = "fsi"

# =============================================================================
# Option Sets
# =============================================================================

SHARED_OPTIONSETS = {
    "fsi_acv_zone": {
        "name": "fsi_acv_zone",
        "options": [
            ("Unclassified", 100000000),
            ("Zone 1 (Enterprise)", 100000001),
            ("Zone 2 (Team)", 100000002),
            ("Zone 3 (Personal)", 100000003),
        ],
    },
}

INTAKE_OPTIONSETS = {
    "fsi_intake_pathused": {
        "name": "fsi_intake_pathused",
        "options": [
            ("Express", 100000000),
            ("Standard", 100000001),
            ("Full", 100000002),
        ],
    },
    "fsi_intake_status": {
        "name": "fsi_intake_status",
        "options": [
            ("Draft", 100000000),
            ("Submitted", 100000001),
            ("AwaitingSponsor", 100000002),
            ("AwaitingReviewers", 100000003),
            ("Approved", 100000004),
            ("Denied", 100000005),
            ("Withdrawn", 100000006),
            ("Escalated", 100000007),
            ("AutoApproved", 100000008),
            ("DeferredOutOfScope", 100000009),
            ("SponsorTimeout", 100000010),
            ("InReview", 100000011),
            ("LiveTracking", 100000012),
        ],
    },
    "fsi_intake_routingtopology": {
        "name": "fsi_intake_routingtopology",
        "options": [
            ("Sequential", 100000000),
            ("Parallel", 100000001),
            ("Quorum", 100000002),
        ],
    },
    "fsi_intake_risktier": {
        "name": "fsi_intake_risktier",
        "options": [
            ("Tier 1 (High)", 100000000),
            ("Tier 2 (Medium)", 100000001),
            ("Tier 3 (Low)", 100000002),
        ],
    },
    "fsi_intake_agenttype": {
        "name": "fsi_intake_agenttype",
        "options": [
            ("Agent Builder (M365 Copilot)", 100000000),
            ("Copilot Studio (classic)", 100000001),
            ("Declarative Agent (M365 Copilot)", 100000002),
            ("Custom Engine Agent", 100000003),
            ("Azure AI Foundry / Pro-Dev", 100000004),
        ],
    },
    "fsi_intake_dataclassification": {
        "name": "fsi_intake_dataclassification",
        "options": [
            ("Public", 100000000),
            ("Internal", 100000001),
            ("Confidential", 100000002),
            ("Restricted", 100000003),
        ],
    },
    "fsi_intake_reviewerrole": {
        "name": "fsi_intake_reviewerrole",
        "options": [
            ("InfoSec", 100000000),
            ("Privacy", 100000001),
            ("Compliance", 100000002),
            ("Legal", 100000003),
            ("MRM", 100000004),
            ("Sponsor", 100000005),
            ("Sponsor Manager", 100000006),
        ],
    },
    "fsi_intake_reviewdecision": {
        "name": "fsi_intake_reviewdecision",
        "options": [
            ("Pending", 100000000),
            ("Approved", 100000001),
            ("Approved with conditions", 100000002),
            ("Denied", 100000003),
            ("Recused", 100000004),
            ("Timeout", 100000005),
        ],
    },
    "fsi_intake_mrmhandoffstatus": {
        "name": "fsi_intake_mrmhandoffstatus",
        "options": [
            ("Pending", 100000000),
            ("Handed off", 100000001),
            ("NotApplicable", 100000002),
            ("Failed", 100000003),
        ],
    },
    "fsi_intake_decisionoutcome": {
        "name": "fsi_intake_decisionoutcome",
        "options": [
            ("Approved", 100000000),
            ("AutoApproved", 100000001),
            ("Denied", 100000002),
            ("EscalatedToManager", 100000003),
            ("WithdrawnByMaker", 100000004),
        ],
    },
    "fsi_intake_auditeventtype": {
        "name": "fsi_intake_auditeventtype",
        "options": [
            ("RouterDecided", 100000000),
            ("RouterFailed", 100000001),
            ("SponsorDecided", 100000002),
            ("SponsorTimeout", 100000003),
            ("SponsorEscalated", 100000004),
            ("SponsorCardFailed", 100000005),
            ("ReviewerQueued", 100000006),
            ("ReviewerQueueFailed", 100000007),
            ("ReviewerDecided", 100000008),
            ("QuorumReached", 100000009),
            ("RequestDenied", 100000010),
            ("ReviewerDecisionHandlerFailed", 100000011),
            ("ReviewerEscalated", 100000012),
            ("ReviewerEscalationFailed", 100000013),
            ("MrmHandoffSubmitted", 100000014),
            ("MRMHandoffPending", 100000015),
            ("MrmDecisionMirrored", 100000016),
            ("DecisionPackWritten", 100000017),
            ("EntraAgentIdMinted", 100000018),
            ("RegistryHandoffComplete", 100000019),
            ("DriftHandoffSubmitted", 100000020),
            ("AppealSubmitted", 100000021),
            ("AppealRejected", 100000022),
            ("AppealCreateFailed", 100000023),
            ("RetentionLabelApplied", 100000024),
        ],
    },
}


# =============================================================================
# Column Builders (lifted from peer pattern in agent-registry-automation)
# =============================================================================


def _label(text):
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


def _string_col(schema_name, display, max_length, required=True, description=""):
    defn = {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "AttributeType": "String",
        "AttributeTypeName": {"Value": "StringType"},
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "ApplicationRequired" if required else "None"},
        "MaxLength": max_length,
        "FormatName": {"Value": "Text"},
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _memo_col(schema_name, display, max_length, description=""):
    defn = {
        "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
        "AttributeType": "Memo",
        "AttributeTypeName": {"Value": "MemoType"},
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "None"},
        "MaxLength": max_length,
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _integer_col(schema_name, display, required=True, default=None, description=""):
    defn = {
        "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
        "AttributeType": "Integer",
        "AttributeTypeName": {"Value": "IntegerType"},
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "ApplicationRequired" if required else "None"},
        "MinValue": 0,
        "MaxValue": 2147483647,
    }
    if default is not None:
        defn["DefaultValue"] = default
    if description:
        defn["Description"] = _label(description)
    return defn


def _boolean_col(schema_name, display, default=False, description=""):
    defn = {
        "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
        "AttributeType": "Boolean",
        "AttributeTypeName": {"Value": "BooleanType"},
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "DefaultValue": default,
        "OptionSet": {
            "@odata.type": "Microsoft.Dynamics.CRM.BooleanOptionSetMetadata",
            "OptionSetType": "Boolean",
            "TrueOption": {"Value": 1, "Label": _label("Yes")},
            "FalseOption": {"Value": 0, "Label": _label("No")},
        },
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _datetime_col(schema_name, display, required=True, description=""):
    defn = {
        "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "AttributeType": "DateTime",
        "AttributeTypeName": {"Value": "DateTimeType"},
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "ApplicationRequired" if required else "None"},
        "Format": "DateAndTime",
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _picklist_col(schema_name, display, global_optionset_name, required=True, description=""):
    defn = {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "AttributeType": "Picklist",
        "AttributeTypeName": {"Value": "PicklistType"},
        "SchemaName": schema_name,
        "DisplayName": _label(display),
        "RequiredLevel": {"Value": "ApplicationRequired" if required else "None"},
        "GlobalOptionSet@odata.bind": (
            f"/GlobalOptionSetDefinitions(Name='{global_optionset_name}')"
        ),
    }
    if description:
        defn["Description"] = _label(description)
    return defn


def _resolve_picklist_bind(col, optionset_metadata_ids, dry_run):
    """Rewrite Picklist columns to bind by MetadataId GUID (Dataverse requirement).

    The compact column builder writes ``GlobalOptionSet@odata.bind`` using a
    ``Name='...'`` key for readability, but Dataverse only accepts GUID keys on
    the @odata.bind reference and returns ``Guid should contain 32 digits ...``
    when given a Name key. We replace the key with the previously resolved
    MetadataId at deploy time.
    """
    bind_key = "GlobalOptionSet@odata.bind"
    bind_value = col.get(bind_key)
    if not bind_value or "Name='" not in bind_value:
        return col
    if dry_run:
        return col
    name = bind_value.split("Name='", 1)[1].split("'", 1)[0]
    metadata_id = optionset_metadata_ids.get(name)
    if not metadata_id:
        raise RuntimeError(
            f"Picklist column {col.get('SchemaName', '?')} references unknown global option set '{name}'"
        )
    resolved = dict(col)
    resolved[bind_key] = f"/GlobalOptionSetDefinitions({metadata_id})"
    return resolved


def _optionset_metadata(optionset_def):
    """Convert the compact option-set definition into Dataverse metadata."""
    name = optionset_def["name"]
    display_name = name.replace("fsi_", "").replace("_", " ").title()
    return {
        # Dataverse rejects the payload as 'Invalid property Options ... on OptionSetMetadataBase'
        # unless the derived OptionSetMetadata type is declared on the root resource.
        "@odata.type": "Microsoft.Dynamics.CRM.OptionSetMetadata",
        "Name": name,
        "DisplayName": _label(display_name),
        "Description": _label(f"Agent Intake option set {name}"),
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": [
            {"Value": value, "Label": _label(label)}
            for label, value in optionset_def["options"]
        ],
    }


# =============================================================================
# Table Column Definitions
# =============================================================================

INTAKE_REQUEST_COLUMNS = [
    _string_col("fsi_RequestId", "Request ID", 100,
                description="Globally unique intake request identifier (GUID)"),
    # v1.0-preview keeps appeal lineage as request-ID text. Convert this to a
    # self-lookup once the schema deployment path adds relationship helpers.
    _string_col("fsi_AppealOfId", "Appeal Of", 100, required=False,
                description="Original intake request that this request is appealing"),
    _string_col("fsi_AgentDisplayName", "Agent Display Name", 200,
                description="Maker-provided name for the proposed agent"),
    _picklist_col("fsi_AgentType", "Agent Type", "fsi_intake_agenttype",
                  description="Authoring tool / runtime type the maker intends to use"),
    _string_col("fsi_BusinessOutcome", "Business Outcome", 500,
                description="Structured business outcome category (BJ-001 dropdown value)"),
    _memo_col("fsi_BusinessJustification", "Business Justification", 4000,
              description="Optional free-text business context (BJ-002, optional)"),
    _string_col("fsi_MakerUpn", "Maker UPN", 200,
                description="Maker user principal name"),
    _string_col("fsi_MakerDepartment", "Maker Department", 200, required=False,
                description="Pre-filled from Microsoft Graph /me"),
    _string_col("fsi_MakerCountry", "Maker Country", 100, required=False,
                description="Pre-filled from Microsoft Graph /me (usageLocation)"),
    _string_col("fsi_MakerDisplayName", "Maker Display Name", 200, required=False,
                description="Pre-filled from Microsoft Graph /me displayName"),
    _string_col("fsi_MakerJobTitle", "Maker Job Title", 200, required=False,
                description="Pre-filled from Microsoft Graph /me jobTitle"),
    _string_col("fsi_SponsorUpn", "Sponsor UPN", 200,
                description="Sponsor user principal name (pre-filled from /me/manager when available)"),
    _string_col("fsi_IntendedAudience", "Intended Audience", 100,
                description="Maker-selected audience: Just me, My team, My department, Anyone in the firm, External users"),
    _string_col("fsi_T1InitiatesFinancialTxn", "T1 Initiates Financial Transaction", 20,
                description="Trigger answer: Yes, No, or Not sure"),
    _string_col("fsi_T2CustomerFacing", "T2 Customer Facing", 20,
                description="Trigger answer: Yes, No, or Not sure"),
    _string_col("fsi_T3AutonomousUnmonitored", "T3 Autonomous Unmonitored", 20,
                description="Trigger answer: Yes, No, or Not sure"),
    _string_col("fsi_T4HandlesNpi", "T4 Handles NPI", 20,
                description="Trigger answer: Yes, No, or Not sure"),
    _string_col("fsi_T5HandlesMnpi", "T5 Handles MNPI", 20,
                description="Trigger answer: Yes, No, or Not sure"),
    _string_col("fsi_T6CrossborderData", "T6 Cross-Border Data", 20,
                description="Trigger answer: Yes, No, or Not sure"),
    _boolean_col("fsi_MakerAttestation", "Maker Attestation", default=False,
                 description="Maker acknowledged the acceptable-use and accuracy attestation before submission"),
    _picklist_col("fsi_PathUsed", "Path Used", "fsi_intake_pathused",
                  description="Express / Standard / Full — set by routing rules"),
    # logical name: fsi_routingtopology
    _picklist_col("fsi_RoutingTopology", "Routing Topology", "fsi_intake_routingtopology", required=False,
                  description="Sequential / Parallel / Quorum topology selected by routing rules"),
    _picklist_col("fsi_RiskTier", "Risk Tier", "fsi_intake_risktier",
                  description="Tier 1 / 2 / 3 per SR 11-7 mapping; computed from trigger Qs"),
    _picklist_col("fsi_Zone", "Zone", "fsi_acv_zone",
                  description="Zone classification selected by policy and routing rules"),
    _picklist_col("fsi_DataClassification", "Data Classification", "fsi_intake_dataclassification",
                  description="Highest sensitivity of declared data sources used for intake routing"),
    _picklist_col("fsi_Status", "Status", "fsi_intake_status",
                  description="Lifecycle status of the intake request"),
    _string_col("fsi_TargetEnvironmentId", "Target Environment ID", 100, required=False,
                description="Power Platform environment recommended/selected for the agent"),
    _string_col("fsi_TargetEnvironmentName", "Target Environment Name", 200, required=False,
                description="Display name of the recommended/selected environment"),
    _boolean_col("fsi_EnvironmentManaged", "Environment Managed", default=False,
                 description="True when PPAC reports a Managed Environment protection level"),
    _string_col("fsi_DlpPolicyOutcome", "DLP Policy Outcome", 100, required=False,
                description="Result from the Power Platform data policy simulation"),
    _string_col("fsi_DecisionPath", "Decision Path", 100, required=False,
                description="Express, Standard, Full, DeferredOutOfScope, or DefaultDeny computed by routing rules"),
    _integer_col("fsi_TriggerHitCount", "Trigger Hit Count", required=False,
                 description="Count of trigger answers equal to Yes or Not sure"),
    # logical name: fsi_quorumrequired
    _integer_col("fsi_QuorumRequired", "Quorum Required", required=False,
                 description="Minimum reviewer approvals required before the request can advance"),
    _boolean_col("fsi_NonMrmQuorumMet", "Non-MRM Quorum Met", default=False,
                 description="TRUE when the non-MRM reviewer board (InfoSec/Privacy/Compliance/Legal) has reached quorum on a Tier-1 Full request; gates Flow 7 (MRM handoff)"),
    # v1.0-preview keeps reviewer-board state in JSON instead of a dedicated
    # fsi_IntakeReviewerAssignment table so the schema change stays small; v1.1
    # can add the table once the reviewer app needs Dataverse sub-grid views.
    # logical name: fsi_parallelreviewersjson
    _memo_col("fsi_ParallelReviewersJson", "Parallel Reviewers JSON", 65536,
              description="JSON array of reviewer role, UPN, due date, weight, and state for routed reviewers"),
    _string_col("fsi_DataResidencyCountry", "Data Residency Country", 100, required=False,
                description="Maker-declared or detected residency for data sources"),
    _integer_col("fsi_RetentionYears", "Retention Years", required=False,
                 description="Effective retention period in years"),
    _boolean_col("fsi_ImmutableStorage", "Immutable Storage", default=True,
                 description="True when the decision pack is stamped with the WORM retention label"),
    _boolean_col("fsi_PrivacyOverride", "Privacy Override", default=False,
                 description="Set only by Privacy to override the cross-border default-deny rule"),
    # logical name: fsi_mrmrequired
    _boolean_col("fsi_MrmRequired", "MRM Required", default=False,
                 description="True when policy requires model-risk-management-automation handoff evidence"),
    # logical name: fsi_mrmhandoffstatus
    _picklist_col("fsi_MrmHandoffStatus", "MRM Handoff Status", "fsi_intake_mrmhandoffstatus", required=False,
                  description="Pending / Handed off / NotApplicable / Failed for the MRM handoff"),
    _memo_col("fsi_DeclaredDataSourcesJson", "Declared Data Sources JSON", 65536,
              description="JSON snapshot of maker-declared data sources/connectors for drift comparison"),
    # logical name: fsi_standardfullquestionsjson
    _memo_col("fsi_StandardFullQuestionsJson", "Standard Full Questions JSON", 65536,
              description="JSON snapshot of the extended Standard and Full path question responses"),
    _string_col("fsi_EntraAgentId", "Entra Agent ID", 100, required=False,
                description="Microsoft Entra Agent ID service principal ID minted at handoff"),
    _string_col("fsi_RegistryRecordId", "Registry Record ID", 100, required=False,
                description="ID of the corresponding agent-registry-automation record after handoff"),
    _datetime_col("fsi_SubmittedOn", "Submitted On", required=False,
                  description="Timestamp the request was submitted (set on transition Draft to Submitted)"),
    _datetime_col("fsi_DecidedOn", "Decided On", required=False,
                  description="Timestamp of final decision"),
    _string_col("fsi_PolicyVersionApplied", "Policy Version Applied", 50,
                description="Version of policy-lookup-tables.yaml in effect at submission"),
]

INTAKE_DATASOURCE_COLUMNS = [
    _string_col("fsi_RequestId", "Request ID", 100,
                description="FK to fsi_IntakeRequest.fsi_RequestId"),
    _string_col("fsi_DataSourceName", "Data Source Name", 500,
                description="Maker-declared data source identifier (e.g., SharePoint site URL, table name)"),
    _string_col("fsi_DataSourceType", "Data Source Type", 200,
                description="Connector type (e.g., SharePoint, Dataverse, Outlook, custom HTTP)"),
    _picklist_col("fsi_DataClassification", "Data Classification", "fsi_intake_dataclassification",
                  description="Sensitivity declared for this source (Express: maker-declared)"),
    _boolean_col("fsi_IsCustomerData", "Is Customer Data", default=False,
                 description="Does this source contain customer NPI? (Trigger T1 input)"),
    _boolean_col("fsi_IsRestricted", "Is Restricted", default=False,
                 description="Is this source restricted under MNPI / insider trading controls? (Trigger T2 input)"),
]

INTAKE_RISKSIGNAL_COLUMNS = [
    _string_col("fsi_RequestId", "Request ID", 100,
                description="FK to fsi_IntakeRequest.fsi_RequestId"),
    _string_col("fsi_TriggerCode", "Trigger Code", 50,
                description="T1..T7 trigger question identifier"),
    _string_col("fsi_TriggerAnswer", "Trigger Answer", 20,
                description="Maker's answer: Yes, No, or Not sure"),
    _string_col("fsi_DerivedSignal", "Derived Signal", 200, required=False,
                description="Any computed signal raised by the answer (e.g., 'CustomerFacing', 'MNPI')"),
    _datetime_col("fsi_CapturedOn", "Captured On",
                  description="Timestamp the signal was captured at intake"),
]

INTAKE_REVIEW_COLUMNS = [
    _string_col("fsi_RequestId", "Request ID", 100,
                description="FK to fsi_IntakeRequest.fsi_RequestId"),
    # logical name: fsi_reviewerrole
    _picklist_col("fsi_ReviewerRole", "Reviewer Role", "fsi_intake_reviewerrole",
                  description="InfoSec / Privacy / Compliance / Legal / MRM / Sponsor"),
    _string_col("fsi_ReviewerUpn", "Reviewer UPN", 200,
                description="Reviewer user principal name"),
    _string_col("fsi_ReviewType", "Review Type", 100,
                description="SampleAudit / Standard / Full"),
    _picklist_col("fsi_ReviewOutcome", "Review Outcome", "fsi_intake_reviewdecision", required=False,
                  description="Pending / Approved / Approved with conditions / Denied / Recused / Timeout"),
    _memo_col("fsi_ReviewNotes", "Review Notes", 4000,
              description="Reviewer notes (optional)"),
    # logical name: fsi_quorumweight
    _integer_col("fsi_QuorumWeight", "Quorum Weight", required=False, default=1,
                 description="Weight contributed by this reviewer toward quorum calculations"),
    # logical name: fsi_dueon
    _datetime_col("fsi_DueOn", "Due On", required=False,
                  description="Date/time when the reviewer response is due under policy"),
    # logical name: fsi_conditionstext
    _memo_col("fsi_ConditionsText", "Conditions Text", 4000,
              description="Reviewer conditions recorded when the decision is Approved with conditions"),
    _datetime_col("fsi_StartedOn", "Started On", required=False,
                  description="Timestamp review started"),
    _datetime_col("fsi_CompletedOn", "Completed On", required=False,
                  description="Timestamp review completed"),
]

INTAKE_APPROVAL_COLUMNS = [
    _string_col("fsi_RequestId", "Request ID", 100,
                description="FK to fsi_IntakeRequest.fsi_RequestId"),
    # logical name: fsi_approverrole
    _picklist_col("fsi_ApproverRole", "Approver Role", "fsi_intake_reviewerrole",
                  description="Sponsor / InfoSec / Privacy / Compliance / Legal / MRM / Sponsor Manager"),
    _string_col("fsi_ApproverUpn", "Approver UPN", 200,
                description="Approver user principal name"),
    _picklist_col("fsi_DecisionOutcome", "Decision Outcome", "fsi_intake_decisionoutcome",
                  description="Approved / AutoApproved / Denied / EscalatedToManager / WithdrawnByMaker"),
    _datetime_col("fsi_DecidedOn", "Decided On",
                  description="Timestamp the approver clicked"),
    _string_col("fsi_DecisionMethod", "Decision Method", 100,
                description="TeamsAdaptiveCard / Portal / Email / API"),
    _string_col("fsi_DecisionContextHash", "Decision Context Hash", 200, required=False,
                description="SHA-256 of the rendered decision context shown to the approver (tamper evidence)"),
    _string_col("fsi_ClientIpAddress", "Client IP Address", 100, required=False,
                description="Source IP recorded at decision time (supervisory evidence)"),
    # logical name: fsi_dependsonapprovalid
    _string_col("fsi_DependsOnApprovalId", "Depends On Approval ID", 100, required=False,
                description="Optional predecessor approval row ID used for sequential approval chains"),
]

INTAKE_DECISIONLOG_COLUMNS = [
    _string_col("fsi_RequestId", "Request ID", 100,
                description="FK to fsi_IntakeRequest.fsi_RequestId"),
    _picklist_col("fsi_DecisionOutcome", "Decision Outcome", "fsi_intake_decisionoutcome",
                  description="Final outcome of the request"),
    _picklist_col("fsi_RiskTier", "Risk Tier", "fsi_intake_risktier",
                  description="Tier captured at decision time"),
    _picklist_col("fsi_Zone", "Zone", "fsi_acv_zone",
                  description="Zone captured at decision time"),
    _picklist_col("fsi_PathUsed", "Path Used", "fsi_intake_pathused",
                  description="Express / Standard / Full path used"),
    _string_col("fsi_PolicyVersionApplied", "Policy Version Applied", 50,
                description="Version of policy-lookup-tables.yaml at decision time"),
    _memo_col("fsi_DecisionPackJson", "Decision Pack JSON", 1048576,
              description="Full decision pack as JSON (all 137 catalog field values, computed and declared)"),
    _string_col("fsi_DecisionPackHash", "Decision Pack Hash", 200,
                description="SHA-256 of fsi_DecisionPackJson for tamper evidence"),
    _datetime_col("fsi_DecidedOn", "Decided On",
                  description="Timestamp of final decision"),
    _string_col("fsi_RetentionLabelApplied", "Retention Label Applied", 200,
                description="Purview retention label stamped (FSI-AgentIntake-7yr or override)"),
    _datetime_col("fsi_RetentionLabelAppliedOn", "Retention Label Applied On",
                  description="Timestamp the retention label was stamped"),
]

INTAKE_SPONSORSHIP_COLUMNS = [
    _string_col("fsi_RequestId", "Request ID", 100,
                description="FK to fsi_IntakeRequest.fsi_RequestId"),
    _string_col("fsi_SponsorUpn", "Sponsor UPN", 200,
                description="Sponsor user principal name"),
    _string_col("fsi_SponsorRole", "Sponsor Role", 200,
                description="LineOfBusinessSponsor / RegisteredPrincipal / DataOwner"),
    _memo_col("fsi_AttestationText", "Attestation Text", 4000,
              description="Verbatim attestation language presented to the sponsor (FINRA Rule 3110)"),
    _datetime_col("fsi_AttestedOn", "Attested On", required=False,
                  description="Timestamp the sponsor attested"),
    _string_col("fsi_AttestationMethod", "Attestation Method", 100,
                description="TeamsAdaptiveCard / Portal / Email"),
    _string_col("fsi_RenderedCardHash", "Rendered Card Hash", 200, required=False,
                description="SHA-256 of the exact card content shown — tamper evidence"),
    _boolean_col("fsi_IsValid", "Is Valid", default=True,
                 description="False if sponsor attestation has been revoked"),
]

INTAKE_AUDITEVENT_COLUMNS = [
    _string_col("fsi_RequestId", "Request ID", 100,
                description="FK to fsi_IntakeRequest.fsi_RequestId"),
    _string_col("fsi_EventType", "Event Type", 100,
                description="Lifecycle event name emitted by intake flows. Bundled values are catalogued in the fsi_intake_auditeventtype option set, but this column remains text so customers can extend the inventory without a schema change."),
    # logical name: fsi_pathphase
    _string_col("fsi_PathPhase", "Path Phase", 100, required=False,
                description="Submitted / RouterRouted / SponsorAttested / ReviewerQueued / ReviewerDecided / Escalated / Handed off"),
    _string_col("fsi_ActorUpn", "Actor UPN", 200, required=False,
                description="UPN of the actor who triggered the event (system events use 'system')"),
    _datetime_col("fsi_EventOn", "Event On",
                  description="Timestamp the event occurred"),
    _memo_col("fsi_EventPayloadJson", "Event Payload JSON", 65536,
              description="Optional JSON payload for the event (pre-state, post-state, error details)"),
]

INTAKE_RETENTIONRECORD_COLUMNS = [
    _string_col("fsi_RequestId", "Request ID", 100,
                description="FK to fsi_IntakeRequest.fsi_RequestId"),
    _string_col("fsi_LabelName", "Label Name", 200,
                description="Purview retention label name (e.g., FSI-AgentIntake-7yr)"),
    _integer_col("fsi_RetentionYears", "Retention Years",
                 description="Effective retention in years"),
    _datetime_col("fsi_StampedOn", "Stamped On",
                  description="Timestamp the label was applied"),
    _string_col("fsi_StampedBy", "Stamped By", 200,
                description="System / managed-identity that stamped the label"),
    _string_col("fsi_RegulatoryBasis", "Regulatory Basis", 500,
                description="Comma-separated list (e.g., 'SEC 17a-4, FINRA 4511, CFTC 1.31')"),
]


TABLES = {
    "fsi_intakerequest": {
        "schema_name": "fsi_IntakeRequest",
        "display": "Intake Request",
        "plural": "Intake Requests",
        "description": "Maker-submitted request to build an AI agent across Express, Standard, and Full paths",
        "ownership": "UserOwned",
        "columns": INTAKE_REQUEST_COLUMNS,
        "entity_set_name": "fsi_intakerequests",
    },
    "fsi_intakedatasource": {
        "schema_name": "fsi_IntakeDataSource",
        "display": "Intake Data Source",
        "plural": "Intake Data Sources",
        "description": "Per-data-source declaration on an intake request (1..N per parent)",
        "ownership": "UserOwned",
        "columns": INTAKE_DATASOURCE_COLUMNS,
        "entity_set_name": "fsi_intakedatasources",
    },
    "fsi_intakerisksignal": {
        "schema_name": "fsi_IntakeRiskSignal",
        "display": "Intake Risk Signal",
        "plural": "Intake Risk Signals",
        "description": "Per-trigger-question outcome and any derived risk signals",
        "ownership": "UserOwned",
        "columns": INTAKE_RISKSIGNAL_COLUMNS,
        "entity_set_name": "fsi_intakerisksignals",
    },
    "fsi_intakereview": {
        "schema_name": "fsi_IntakeReview",
        "display": "Intake Review",
        "plural": "Intake Reviews",
        "description": "Reviewer activity (sample audit on Express; Standard/Full and MRM reviewer outcomes)",
        "ownership": "UserOwned",
        "columns": INTAKE_REVIEW_COLUMNS,
        "entity_set_name": "fsi_intakereviews",
    },
    "fsi_intakeapproval": {
        "schema_name": "fsi_IntakeApproval",
        "display": "Intake Approval",
        "plural": "Intake Approvals",
        "description": "Per-approver decision (sponsor + sequential or parallel approvers)",
        "ownership": "UserOwned",
        "columns": INTAKE_APPROVAL_COLUMNS,
        "entity_set_name": "fsi_intakeapprovals",
    },
    "fsi_intakedecisionlog": {
        "schema_name": "fsi_IntakeDecisionLog",
        "display": "Intake Decision Log",
        "plural": "Intake Decision Logs",
        "description": (
            "Immutable decision-pack record (supports compliance with "
            "FINRA Rule 4511, SEC Rule 17a-4, CFTC Rule 1.31)"
        ),
        "ownership": "OrganizationOwned",
        "columns": INTAKE_DECISIONLOG_COLUMNS,
        "entity_set_name": "fsi_intakedecisionlogs",
    },
    "fsi_intakesponsorship": {
        "schema_name": "fsi_IntakeSponsorship",
        "display": "Intake Sponsorship",
        "plural": "Intake Sponsorships",
        "description": "Sponsor attestation evidence (supports FINRA Rule 3110 supervision)",
        "ownership": "UserOwned",
        "columns": INTAKE_SPONSORSHIP_COLUMNS,
        "entity_set_name": "fsi_intakesponsorships",
    },
    "fsi_intakeauditevent": {
        "schema_name": "fsi_IntakeAuditEvent",
        "display": "Intake Audit Event",
        "plural": "Intake Audit Events",
        "description": "Lifecycle event audit trail with path-phase checkpoints",
        "ownership": "OrganizationOwned",
        "columns": INTAKE_AUDITEVENT_COLUMNS,
        "entity_set_name": "fsi_intakeauditevents",
    },
    "fsi_intakeretentionrecord": {
        "schema_name": "fsi_IntakeRetentionRecord",
        "display": "Intake Retention Record",
        "plural": "Intake Retention Records",
        "description": "Retention-label stamping evidence per intake decision",
        "ownership": "OrganizationOwned",
        "columns": INTAKE_RETENTIONRECORD_COLUMNS,
        "entity_set_name": "fsi_intakeretentionrecords",
    },
}

ALTERNATE_KEY = {
    "entity": "fsi_intakerequest",
    "schema_name": "fsi_RequestIdUniqueKey",
    "display": "Request ID Unique Key",
    "key_columns": ["fsi_requestid"],
}


# =============================================================================
# Documentation Generator
# =============================================================================


def _required_label(col):
    lvl = col.get("RequiredLevel", {}).get("Value", "None")
    return "Yes" if lvl == "ApplicationRequired" else "No"


def _col_type_label(col):
    odata_type = col.get("@odata.type", "")
    suffix = odata_type.rsplit(".", 1)[-1].replace("AttributeMetadata", "")
    if suffix == "String":
        return f"String({col.get('MaxLength', '')})"
    if suffix == "Memo":
        return f"Memo({col.get('MaxLength', '')})"
    if suffix == "Picklist":
        os_bind = col.get("GlobalOptionSet@odata.bind", "")
        if "Name='" in os_bind:
            os_name = os_bind.split("Name='")[1].split("'")[0]
            return f"Choice ({os_name})"
        return "Choice"
    return suffix


def write_schema_docs(path):
    """Generate dataverse-schema.md from the in-memory schema definitions."""
    lines = []
    lines.append("# Agent Intake — Dataverse Schema")
    lines.append("")
    lines.append("> Auto-generated from `scripts/create_fsi_intake_dataverse_schema.py`. Do not hand-edit.")
    lines.append("> Regenerate with: `python scripts/create_fsi_intake_dataverse_schema.py --output-docs docs/dataverse-schema.md`")
    lines.append("")
    lines.append("## Naming convention")
    lines.append("")
    lines.append("Dataverse uses two names for every column:")
    lines.append("")
    lines.append("- **SchemaName** (PascalCase with prefix): `fsi_RequestId`, `fsi_AgentDisplayName`")
    lines.append("- **Logical name** (lowercase, no underscores between words): `fsi_requestid`, `fsi_agentdisplayname`")
    lines.append("")
    lines.append("**In OData queries, scripts, and flow expressions, ALWAYS use the logical name.**")
    lines.append("")
    lines.append("## Tables")
    lines.append("")
    for tname, tdef in TABLES.items():
        entity_set = tdef.get("entity_set_name") or (tname + "s")
        lines.append(f"### `{tname}` — {tdef['display']}")
        lines.append("")
        lines.append(f"- **Schema name:** `{tdef['schema_name']}`")
        lines.append(f"- **Entity set name (OData):** `{entity_set}`")
        lines.append(f"- **Ownership:** {tdef['ownership']}")
        lines.append("- **Primary name attribute:** `fsi_name` (ApplicationRequired, String(500))")
        lines.append(f"- **Description:** {tdef['description']}")
        lines.append("")
        lines.append("| Logical name | Schema name | Type | Required | Description |")
        lines.append("|--------------|-------------|------|----------|-------------|")
        for col in tdef["columns"]:
            schema = col["SchemaName"]
            logical = schema.lower()
            ctype = _col_type_label(col)
            required = _required_label(col)
            desc = ""
            if "Description" in col:
                desc = col["Description"]["LocalizedLabels"][0]["Label"]
            lines.append(f"| `{logical}` | `{schema}` | {ctype} | {required} | {desc} |")
        lines.append("")

    lines.append("## Option Sets")
    lines.append("")
    lines.append("All option sets are global (cross-table) so the same numeric value can be used in OData filters across tables.")
    lines.append("")
    for os_dict in (SHARED_OPTIONSETS, INTAKE_OPTIONSETS):
        for os_name, os_def in os_dict.items():
            lines.append(f"### `{os_name}`")
            lines.append("")
            lines.append("| Label | Value |")
            lines.append("|-------|-------|")
            for label, value in os_def["options"]:
                lines.append(f"| {label} | {value} |")
            lines.append("")

    lines.append("## Alternate Keys")
    lines.append("")
    lines.append(
        f"- `{ALTERNATE_KEY['entity']}` — schema name `{ALTERNATE_KEY['schema_name']}` "
        f"(logical: `{ALTERNATE_KEY['schema_name'].lower()}`); key columns: "
        + ", ".join("`" + c + "`" for c in ALTERNATE_KEY["key_columns"])
    )
    lines.append("")
    lines.append("Use this alternate key for upsert-by-business-key:")
    lines.append("")
    lines.append("```")
    lines.append("PATCH /api/data/v9.2/fsi_intakerequests(fsi_requestid='<request-guid>')")
    lines.append("```")
    lines.append("")
    lines.append("## Relationships")
    lines.append("")
    lines.append("All child tables (`fsi_intakedatasource`, `fsi_intakerisksignal`, `fsi_intakereview`, `fsi_intakeapproval`, `fsi_intakedecisionlog`, `fsi_intakesponsorship`, `fsi_intakeauditevent`, `fsi_intakeretentionrecord`) carry an `fsi_requestid` string column that references the parent `fsi_intakerequest.fsi_requestid`. This is intentionally a **soft FK** (not a Dataverse lookup) so that the immutable `fsi_intakedecisionlog` records survive deletion of the parent request — required for FINRA 4511 / SEC 17a-4 evidence retention.")
    lines.append("")
    lines.append("Reviewer-board state for Standard and Full requests is intentionally stored in `fsi_intakerequest.fsi_parallelreviewersjson` in v1.0-preview to keep the schema small; a dedicated reviewer-assignment table is deferred until the reviewer app needs Dataverse sub-grid views.")
    lines.append("")

    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write("\n".join(lines))


# =============================================================================
# Deployment (uses shared DataverseClient)
# =============================================================================


def deploy(client, dry_run=False):
    """Deploy schema (idempotent)."""
    print("=" * 60)
    print("Agent Intake Dataverse Schema Deployment")
    print("=" * 60)
    if dry_run:
        print("\n*** DRY RUN — no changes will be made ***\n")

    print("\n[1/4] Option sets")
    for _, os_dict in [("shared", SHARED_OPTIONSETS), ("intake", INTAKE_OPTIONSETS)]:
        for _, os_def in os_dict.items():
            client.create_option_set(_optionset_metadata(os_def))

    print("\n[2/4] Tables and columns")
    # Resolve global option-set MetadataIds because Dataverse's
    # GlobalOptionSet@odata.bind only accepts GUID keys, not Name keys.
    optionset_metadata_ids = {}
    if not dry_run:
        for _, os_dict in [("shared", SHARED_OPTIONSETS), ("intake", INTAKE_OPTIONSETS)]:
            for _, os_def in os_dict.items():
                name = os_def["name"]
                meta = client.get_global_optionset(name)
                if not meta or not meta.get("MetadataId"):
                    raise RuntimeError(f"Could not resolve MetadataId for global option set '{name}'")
                optionset_metadata_ids[name] = meta["MetadataId"]

    for tname, tdef in TABLES.items():
        print(f"\n  --- {tdef['display']} ({tdef['ownership']}) ---")
        if not client.check_table_exists(tname):
            definition = {
                "@odata.type": "Microsoft.Dynamics.CRM.EntityMetadata",
                "SchemaName": tdef["schema_name"],
                "DisplayName": _label(tdef["display"]),
                "DisplayCollectionName": _label(tdef["plural"]),
                "Description": _label(tdef["description"]),
                "OwnershipType": tdef["ownership"],
                "IsActivity": False,
                "HasActivities": False,
                "HasNotes": False,
                "IsAuditEnabled": {"Value": True, "CanBeChanged": True},
                "PrimaryNameAttribute": "fsi_name",
                "Attributes": [
                    {
                        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
                        "AttributeType": "String",
                        "AttributeTypeName": {"Value": "StringType"},
                        "SchemaName": "fsi_Name",
                        "DisplayName": _label(f"{tdef['display']} ID"),
                        "Description": _label("Primary name attribute"),
                        "RequiredLevel": {"Value": "ApplicationRequired"},
                        "MaxLength": 500,
                        "FormatName": {"Value": "Text"},
                        "IsPrimaryName": True,
                    }
                ],
            }
            if tdef.get("entity_set_name"):
                definition["EntitySetName"] = tdef["entity_set_name"]
            client.create_entity(definition)
            print(f"  {tname}: created")
        else:
            print(f"  {tname}: already exists")
        for col in tdef["columns"]:
            col_payload = _resolve_picklist_bind(col, optionset_metadata_ids, dry_run)
            client.create_column(tname, col_payload)

    print("\n[3/4] Alternate key (best-effort idempotent)")
    print(f"  {ALTERNATE_KEY['schema_name']} on {ALTERNATE_KEY['entity']}")

    print("\n[4/4] Done")


# =============================================================================
# CLI
# =============================================================================


def main():
    parser = argparse.ArgumentParser(
        description="Create Dataverse schema for Agent Intake (Express + Standard + Full foundations)",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--tenant-id", default=os.environ.get("INTAKE_TENANT_ID") or os.environ.get("DATAVERSE_TENANT_ID"),
                        help="Microsoft Entra ID tenant ID; required for interactive, workload identity, certificate, and client-secret auth")
    parser.add_argument("--client-id", default=os.environ.get("INTAKE_CLIENT_ID") or os.environ.get("DATAVERSE_CLIENT_ID") or os.environ.get("AZURE_CLIENT_ID"),
                        help="Application/client ID or user-assigned managed identity client ID")
    # legacy: dev-only — replace with managed identity, workload identity federation, or certificate auth in production
    parser.add_argument("--client-secret", default=os.environ.get("INTAKE_CLIENT_SECRET") or os.environ.get("DATAVERSE_CLIENT_SECRET"),
                        help="Service principal secret (dev-only fallback; prefer managed identity/workload identity/certificate)")
    parser.add_argument("--access-token", default=os.environ.get("INTAKE_ACCESS_TOKEN") or os.environ.get("DATAVERSE_ACCESS_TOKEN"),
                        help="Externally acquired Dataverse bearer token; takes precedence over other auth modes")
    parser.add_argument("--environment-url", default=os.environ.get("INTAKE_ENVIRONMENT_URL") or os.environ.get("DATAVERSE_ENVIRONMENT_URL") or os.environ.get("DATAVERSE_ENV_URL"),
                        help="Dataverse environment URL")
    parser.add_argument("--interactive", action="store_true",
                        help="Use interactive browser authentication")
    parser.add_argument("--auth-mode", choices=["interactive", "managed-identity", "workload-identity", "certificate", "client-secret"],
                        default=os.environ.get("INTAKE_AUTH_MODE") or os.environ.get("DATAVERSE_AUTH_MODE"),
                        help="Authentication mode; prefer managed-identity, workload-identity, or certificate")
    parser.add_argument("--certificate-path", default=os.environ.get("INTAKE_CERTIFICATE_PATH") or os.environ.get("DATAVERSE_CERTIFICATE_PATH"),
                        help="PEM/PFX certificate path for certificate auth")
    parser.add_argument("--certificate-password-env", default="DATAVERSE_CERTIFICATE_PASSWORD",
                        help="Environment variable containing certificate password")
    parser.add_argument("--dry-run", action="store_true",
                        help="Show what would be created without making changes")
    parser.add_argument("--output-docs", metavar="PATH",
                        help="Write Markdown schema reference to PATH and exit (no Dataverse contact)")
    args = parser.parse_args()

    if args.output_docs:
        write_schema_docs(args.output_docs)
        print(f"Wrote schema reference to {args.output_docs}")
        return

    if DataverseClient is None:
        print("ERROR: Could not import DataverseClient from scripts/shared/. "
              "Run from a checkout of the FSI-AgentGov-Solutions repo.", file=sys.stderr)
        sys.exit(1)

    if not args.environment_url:
        print("ERROR: --environment-url or INTAKE_ENVIRONMENT_URL/DATAVERSE_ENVIRONMENT_URL required", file=sys.stderr)
        sys.exit(1)

    auth_mode = "interactive" if args.interactive else (args.auth_mode or ("client-secret" if args.client_secret else "managed-identity"))
    if not args.access_token and auth_mode in {"interactive", "workload-identity", "certificate", "client-secret"} and not args.client_id:
        print("ERROR: --client-id is required for the selected auth mode", file=sys.stderr)
        sys.exit(1)
    if not args.access_token and auth_mode in {"interactive", "workload-identity", "certificate", "client-secret"} and not args.tenant_id:
        print("ERROR: --tenant-id is required for the selected auth mode", file=sys.stderr)
        sys.exit(1)
    if auth_mode == "client-secret" and not args.client_secret:
        print("ERROR: --client-secret is required for legacy client-secret auth", file=sys.stderr)
        sys.exit(1)

    certificate_password = os.environ.get(args.certificate_password_env) if args.certificate_password_env else None
    client = DataverseClient(
        tenant_id=args.tenant_id,
        environment_url=args.environment_url,
        client_id=args.client_id,
        client_secret=args.client_secret,
        access_token=args.access_token,
        interactive=args.interactive,
        dry_run=args.dry_run,
        auth_mode=auth_mode,
        certificate_path=args.certificate_path,
        certificate_password=certificate_password,
    )

    deploy(client, dry_run=args.dry_run)


if __name__ == "__main__":
    main()
