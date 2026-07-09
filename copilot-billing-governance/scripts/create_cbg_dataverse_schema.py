#!/usr/bin/env python3
"""Create Dataverse schema for Copilot Billing Governance (CBG).

Creates the billing-policy, credit-policy, entitlement, materialized-entitlement
cache, coverage-gap aggregate, per-agent cap, and admission-gated approved-group
registry tables with all columns, choice fields, and supporting option sets.

The approved-group registry (``fsi_CbgApprovedGroupPolicy``) adopts the hardened
admission-gate shape used by the Agent Sharing Access Restriction Detector
(``SecurityEnabled`` / ``MailEnabled`` / ``GroupTypes``) rather than cloning the
simpler Unrestricted Agent Sharing Detector registry, so that only proper Entra
security groups can be registered as maker, audience, or billing groups.

Per-feature Copilot credit rates (used by the coverage-gap cost estimate) are
Microsoft-published reference constants documented in
``docs/entitlement-contract.md``; they are intentionally NOT modelled as a
Dataverse table.

Authentication follows the managed-identity-first standard of the shared
``DataverseClient``. The ``--output-docs`` path requires no credentials.

Examples:
    python create_cbg_dataverse_schema.py --output-docs
    python create_cbg_dataverse_schema.py --dry-run --tenant-id <guid> \
        --environment-url https://org.crm.dynamics.com --interactive
"""

import argparse
import logging
import os
import sys
from typing import Optional

import requests

sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "..", "scripts", "shared"))
from dataverse_client import DataverseClient  # noqa: E402

PUBLISHER_PREFIX = "fsi"

logger = logging.getLogger("cbg.schema")


# ---------------------------------------------------------------------------
# Metadata builders
# ---------------------------------------------------------------------------
def _loc(label: str) -> dict:
    """Wrap a label string in a Dataverse LocalizedLabels structure (en-US)."""
    return {"LocalizedLabels": [{"Label": label, "LanguageCode": 1033}]}


def _required(required: bool) -> dict:
    """Return a RequiredLevel structure."""
    return {"Value": "ApplicationRequired" if required else "None"}


def _string(name: str, display: str, desc: str, required: bool = False,
            max_length: int = 100) -> dict:
    """Build a StringAttributeMetadata definition."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": f"{PUBLISHER_PREFIX}_{name}",
        "RequiredLevel": _required(required),
        "DisplayName": _loc(display),
        "Description": _loc(desc),
        "MaxLength": max_length,
        "FormatName": {"Value": "Text"},
    }


def _memo(name: str, display: str, desc: str, required: bool = False,
          max_length: int = 100000) -> dict:
    """Build a MemoAttributeMetadata definition."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.MemoAttributeMetadata",
        "SchemaName": f"{PUBLISHER_PREFIX}_{name}",
        "RequiredLevel": _required(required),
        "DisplayName": _loc(display),
        "Description": _loc(desc),
        "MaxLength": max_length,
        "Format": "Text",
    }


def _picklist(name: str, display: str, desc: str, optionset: str,
              required: bool = False) -> dict:
    """Build a PicklistAttributeMetadata definition bound to a global option set."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.PicklistAttributeMetadata",
        "SchemaName": f"{PUBLISHER_PREFIX}_{name}",
        "RequiredLevel": _required(required),
        "DisplayName": _loc(display),
        "Description": _loc(desc),
        "GlobalOptionSet@odata.bind": f"/GlobalOptionSetDefinitions(Name='{optionset}')",
    }


def _boolean(name: str, display: str, desc: str, default: bool = False,
             required: bool = False) -> dict:
    """Build a BooleanAttributeMetadata definition."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.BooleanAttributeMetadata",
        "SchemaName": f"{PUBLISHER_PREFIX}_{name}",
        "RequiredLevel": _required(required),
        "DisplayName": _loc(display),
        "Description": _loc(desc),
        "DefaultValue": default,
        "OptionSet": {
            "TrueOption": {"Value": 1, "Label": _loc("Yes")},
            "FalseOption": {"Value": 0, "Label": _loc("No")},
        },
    }


def _integer(name: str, display: str, desc: str, required: bool = False,
             min_val: int = 0, max_val: int = 1000000000) -> dict:
    """Build an IntegerAttributeMetadata definition."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.IntegerAttributeMetadata",
        "SchemaName": f"{PUBLISHER_PREFIX}_{name}",
        "RequiredLevel": _required(required),
        "DisplayName": _loc(display),
        "Description": _loc(desc),
        "MinValue": min_val,
        "MaxValue": max_val,
        "Format": "None",
    }


def _decimal(name: str, display: str, desc: str, required: bool = False,
             precision: int = 2, min_val: int = 0, max_val: int = 100000000) -> dict:
    """Build a DecimalAttributeMetadata definition."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.DecimalAttributeMetadata",
        "SchemaName": f"{PUBLISHER_PREFIX}_{name}",
        "RequiredLevel": _required(required),
        "DisplayName": _loc(display),
        "Description": _loc(desc),
        "Precision": precision,
        "MinValue": min_val,
        "MaxValue": max_val,
    }


def _datetime(name: str, display: str, desc: str, required: bool = False) -> dict:
    """Build a DateTimeAttributeMetadata definition (date and time, user-local)."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.DateTimeAttributeMetadata",
        "SchemaName": f"{PUBLISHER_PREFIX}_{name}",
        "RequiredLevel": _required(required),
        "DisplayName": _loc(display),
        "Description": _loc(desc),
        "Format": "DateAndTime",
        "DateTimeBehavior": {"Value": "UserLocal"},
    }


def _primary_name(display: str, desc: str) -> dict:
    """Build the primary-name string attribute (fsi_Name) for a table."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.StringAttributeMetadata",
        "SchemaName": f"{PUBLISHER_PREFIX}_Name",
        "RequiredLevel": {"Value": "ApplicationRequired"},
        "DisplayName": _loc(display),
        "Description": _loc(desc),
        "MaxLength": 200,
        "FormatName": {"Value": "Text"},
    }


def _table(schema_name: str, display: str, collection: str, desc: str,
           primary_display: str, primary_desc: str, entity_set: str) -> dict:
    """Build a table (EntityMetadata) definition with its primary-name attribute.

    ``entity_set`` sets ``EntitySetName`` explicitly rather than relying on Dataverse's
    implicit pluralization, so the OData collection path is deterministic for every
    consumer (e.g. fsi_cbgentitlementmaterialized -> fsi_cbgentitlementmaterializeds and
    fsi_cbgbillingpolicy -> fsi_cbgbillingpolicies).
    """
    return {
        "SchemaName": schema_name,
        "EntitySetName": entity_set,
        "DisplayName": _loc(display),
        "DisplayCollectionName": _loc(collection),
        "Description": _loc(desc),
        "OwnershipType": "OrganizationOwned",
        "IsActivity": False,
        "IsAuditEnabled": {"Value": True},
        "HasActivities": False,
        "HasNotes": False,
        "Attributes": [_primary_name(primary_display, primary_desc)],
        "PrimaryNameAttribute": f"{PUBLISHER_PREFIX}_name",
    }


# ---------------------------------------------------------------------------
# Option sets (CBG-specific, global)
# ---------------------------------------------------------------------------
def _optionset(name: str, display: str, desc: str, labels: list) -> dict:
    """Build a global Picklist option-set definition from an ordered label list."""
    options = []
    for index, label in enumerate(labels):
        options.append({
            "Value": 100000000 + index,
            "Label": _loc(label),
        })
    return {
        "Name": name,
        "DisplayName": _loc(display),
        "Description": _loc(desc),
        "OptionSetType": "Picklist",
        "IsGlobal": True,
        "Options": options,
    }


OPTIONSETS = {
    "fsi_cbg_pathway": _optionset(
        "fsi_cbg_pathway", "Agent Pathway",
        "Classified consumption pathway for an agent (evaluated before eligibility).",
        ["none", "mcp-cs", "mcp-agentbuilder", "api-direct", "metered", "unmapped"],
    ),
    "fsi_cbg_policytype": _optionset(
        "fsi_cbg_policytype", "Billing Policy Type",
        "Whether a policy is pay-as-you-go (Azure subscription) or prepaid Copilot credit.",
        ["PAYG", "Credit"],
    ),
    "fsi_cbg_decision": _optionset(
        "fsi_cbg_decision", "Entitlement Decision",
        "Outcome of a switch-on-pathway entitlement evaluation for an (agent, user) pair.",
        [
            "Allow",
            "Block",
            "Allow - Eligibility N/A",
            "Fail-open - Anomaly",
            "Fail-closed - Zero-rating Unresolved",
        ],
    ),
    "fsi_cbg_spendscope": _optionset(
        "fsi_cbg_spendscope", "Spend Scope",
        "Surface a charge applies to. Chat is credit-eligible; SharePoint stays PAYG.",
        ["Chat - Credit-eligible", "SharePoint - PAYG-only", "Mixed"],
    ),
    "fsi_cbg_userscope": _optionset(
        "fsi_cbg_userscope", "User Scope",
        "Whether a PAYG billing policy applies to all tenant users or only the members "
        "of a specific Entra security group. An all-users scope makes every user "
        "covered for the policy's surface and collapses the blocked set to zero.",
        ["All users", "Specific security group"],
    ),
    "fsi_cbg_blockreason": _optionset(
        "fsi_cbg_blockreason", "Block Reason",
        "Dominant reason a user is blocked from a metered agent (coverage-gap summary).",
        [
            "No eligible cohort",
            "Missing license",
            "Zero-rating unresolved - fail-closed",
            "Not in credit scope",
            "Policy cap exceeded",
            "Unmapped pathway",
        ],
    ),
    "fsi_cbg_grouplayer": _optionset(
        "fsi_cbg_grouplayer", "Group Layer",
        "Which governance layer a registered Entra security group serves.",
        ["Maker", "Audience", "Billing"],
    ),
    "fsi_cbg_enforcementmode": _optionset(
        "fsi_cbg_enforcementmode", "Enforcement Mode",
        "Whether a per-agent cap is enforced via hard-stop or degrades to detect-and-alert.",
        ["Detect-and-alert", "Hard-stop"],
    ),
    "fsi_cbg_zoneclassification": _optionset(
        "fsi_cbg_zoneclassification", "Zone Classification",
        "Governance zone a billing or credit policy applies to.",
        ["Team (Zone 2)", "Enterprise (Zone 3)"],
    ),
}


# ---------------------------------------------------------------------------
# Table definitions
# ---------------------------------------------------------------------------
TABLES = {
    "fsi_CbgBillingPolicy": _table(
        "fsi_CbgBillingPolicy", "Billing Policy", "Billing Policies",
        "Pay-as-you-go (PAYG) Copilot billing policy backed by an Azure subscription. "
        "Tenant ceiling is 50 PAYG policies; PAYG provides budget alerts, not a hard-stop.",
        "Policy Name", "Display name of the PAYG billing policy",
        "fsi_cbgbillingpolicies",
    ),
    "fsi_CbgCreditPolicy": _table(
        "fsi_CbgCreditPolicy", "Credit Policy", "Credit Policies",
        "Prepaid Copilot credit policy (standalone hard-stop, no Azure subscription). "
        "Tenant ceiling is 10 credit policies; credit policies are Chat-only today.",
        "Policy Name", "Display name of the prepaid credit policy",
        "fsi_cbgcreditpolicies",
    ),
    "fsi_CbgEntitlement": _table(
        "fsi_CbgEntitlement", "Entitlement", "Entitlements",
        "Policy-level entitlement rule keyed on agent pathway, used by the "
        "switch-on-pathway entitlement engine.",
        "Entitlement Name", "Display name of the entitlement rule",
        "fsi_cbgentitlements",
    ),
    "fsi_CbgEntitlementMaterialized": _table(
        "fsi_CbgEntitlementMaterialized", "Materialized Entitlement",
        "Materialized Entitlements",
        "Per-(agent, user) entitlement decision cache with a time-to-live, materialized "
        "to avoid recomputing the full decision tree on every read.",
        "Cache Key", "Composite agent/user cache key (agentid:userupn)",
        "fsi_cbgentitlementmaterializeds",
    ),
    "fsi_CbgCoverageGap": _table(
        "fsi_CbgCoverageGap", "Coverage Gap", "Coverage Gaps",
        "Per-agent coverage-gap aggregate produced by the pre-enforcement analysis "
        "(monitor-only first). One row per agent, with a capped sample of blocked UPNs.",
        "Agent Display", "Display name of the analyzed agent",
        "fsi_cbgcoveragegaps",
    ),
    "fsi_CbgAgentCap": _table(
        "fsi_CbgAgentCap", "Agent Cap", "Agent Caps",
        "Per-agent monthly credit cap and month-to-date consumption. Enforcement mode "
        "degrades to detect-and-alert where a hard-stop write API is unavailable.",
        "Cap Name", "Display name of the per-agent cap record",
        "fsi_cbgagentcaps",
    ),
    "fsi_CbgApprovedGroupPolicy": _table(
        "fsi_CbgApprovedGroupPolicy", "Approved Group Policy",
        "Approved Group Policies",
        "Admission-gated registry of Entra security groups approved as maker, audience, "
        "or billing groups. Adopts the hardened ASARD shape: groups that are not "
        "security-enabled, or that are mail-enabled, are rejected at admission time.",
        "Group Display Name", "Display name of the approved Entra security group",
        "fsi_cbgapprovedgrouppolicies",
    ),
}


# ---------------------------------------------------------------------------
# Column definitions (keyed by table logical name)
# ---------------------------------------------------------------------------
COLUMNS = {
    "fsi_cbgbillingpolicy": [
        _string("PolicyType", "Policy Type", "Always PAYG for this table; retained for cross-table joins.", max_length=20),
        _string("AzureSubscriptionId", "Azure Subscription ID", "Azure subscription GUID backing this PAYG billing policy.", required=True),
        _string("BillingInstanceId", "Billing Instance ID", "Power Platform admin center billing-policy identifier."),
        _string("EnvironmentName", "Environment Name", "Power Platform environment connected to this billing policy.", max_length=200),
        _boolean("IsConnected", "Is Connected", "Whether the two-step add-then-connect flow has completed (environment connected)."),
        _picklist("SpendScope", "Spend Scope", "Surface this PAYG policy covers (SharePoint grounding stays PAYG).", "fsi_cbg_spendscope"),
        _picklist("UserScope", "User Scope", "Whether this PAYG policy applies to all tenant users or to a specific Entra security group. An all-users scope covers every user for the policy's surface.", "fsi_cbg_userscope"),
        _string("AssignedGroupId", "Assigned Group ID", "Entra security group object ID whose members this PAYG policy covers when UserScope is a specific security group."),
        _decimal("BudgetAlertThreshold", "Budget Alert Threshold", "Budget-alert threshold in tenant currency. Informational alert only; PAYG has no hard-stop.", precision=2, max_val=100000000),
        _boolean("BudgetAlertConfigured", "Budget Alert Configured", "Whether a budget alert has been configured for this policy."),
        _integer("PolicyCountSnapshot", "Policy Count Snapshot", "Observed number of PAYG billing policies in the tenant at last sync (ceiling is 50).", min_val=0, max_val=50),
        _picklist("ZoneClassification", "Zone Classification", "Governance zone this policy applies to.", "fsi_cbg_zoneclassification"),
        _datetime("LastSyncedAt", "Last Synced At", "When this policy record was last reconciled from the platform."),
        _memo("Notes", "Notes", "Free-text operational notes for this policy."),
    ],
    "fsi_cbgcreditpolicy": [
        _string("PolicyType", "Policy Type", "Always Credit for this table; retained for cross-table joins.", max_length=20),
        _string("CreditPolicyId", "Credit Policy ID", "Microsoft 365 admin center Copilot credit-policy identifier.", required=True),
        _integer("PrepaidCreditPack", "Prepaid Credit Pack", "Prepaid credit pack size per month (non-rolling pack is 25,000 credits/month).", min_val=0),
        _integer("CreditsConsumed", "Credits Consumed", "Credits consumed against this policy in the current billing period.", min_val=0),
        _boolean("HardStopEnabled", "Hard Stop Enabled", "Whether the standalone prepaid hard-stop is active for this credit policy."),
        _boolean("NonRolling", "Non Rolling", "Whether the credit pack is non-rolling (unused credits do not carry over).", default=True),
        _picklist("SurfaceScope", "Surface Scope", "Surfaces covered. Credit policies are Chat-only today; SharePoint stays PAYG.", "fsi_cbg_spendscope"),
        _string("AssignedGroupId", "Assigned Group ID", "Entra security group object ID whose members are in this credit scope."),
        _integer("PolicyCountSnapshot", "Policy Count Snapshot", "Observed number of credit policies in the tenant at last sync (ceiling is 10).", min_val=0, max_val=10),
        _picklist("ZoneClassification", "Zone Classification", "Governance zone this policy applies to.", "fsi_cbg_zoneclassification"),
        _datetime("LastSyncedAt", "Last Synced At", "When this policy record was last reconciled from the platform."),
        _memo("Notes", "Notes", "Free-text operational notes for this policy."),
    ],
    "fsi_cbgentitlement": [
        _picklist("Pathway", "Pathway", "Agent pathway this entitlement rule applies to.", "fsi_cbg_pathway", required=True),
        _picklist("PolicyType", "Policy Type", "Billing or credit policy backing this entitlement.", "fsi_cbg_policytype"),
        _boolean("RequiresLicense", "Requires License", "Whether the user must hold a Microsoft 365 Copilot license under this rule."),
        _boolean("RequiresBillingScope", "Requires Billing Scope", "Whether the user must also be in billing scope (mcp-cs generative/grounded answers bill even for licensed users)."),
        _boolean("ZeroRatingResolved", "Zero Rating Resolved", "Whether the zero-rating conflict is resolved for this rule. Default true: the June 2026 Microsoft Copilot Studio Licensing Guide (footnotes 6 & 7) confirms a Copilot-licensed user on a Microsoft 365 surface under their own identity is included in the Microsoft 365 Copilot User SL at no additional charge. Set false to revert to the fail-closed posture. The generative-answer-with-tenant-grounding and beyond-fair-use refinements remain a per-tenant credit-cost caveat, not a change to this base entitlement.", default=True),
        _string("EligibleGroupId", "Eligible Group ID", "Entra security group object ID whose members are eligible under this rule."),
        _picklist("SpendScope", "Spend Scope", "Surface this entitlement governs.", "fsi_cbg_spendscope"),
        _picklist("ZoneClassification", "Zone Classification", "Governance zone this entitlement applies to.", "fsi_cbg_zoneclassification"),
        _memo("Notes", "Notes", "Free-text notes describing the rule rationale and source."),
    ],
    "fsi_cbgentitlementmaterialized": [
        _string("AgentId", "Agent ID", "Unique identifier of the agent for this materialized decision.", required=True),
        _string("UserUpn", "User UPN", "User principal name the decision was computed for.", required=True, max_length=200),
        _picklist("Pathway", "Pathway", "Classified pathway used for this decision.", "fsi_cbg_pathway"),
        _picklist("Decision", "Decision", "Materialized entitlement decision.", "fsi_cbg_decision"),
        _picklist("DecisionReason", "Decision Reason", "Reason code when the decision is a block (nullable for allows).", "fsi_cbg_blockreason"),
        _picklist("SpendScope", "Spend Scope", "Surface the decision applies to.", "fsi_cbg_spendscope"),
        _string("SourcePolicyId", "Source Policy ID", "Identifier of the policy that drove this decision."),
        _datetime("EvaluatedAt", "Evaluated At", "When this decision was computed."),
        _datetime("TtlExpiresAt", "TTL Expires At", "When this cached decision expires and must be recomputed."),
        _memo("Notes", "Notes", "Free-text notes or evaluation trace for this decision."),
    ],
    "fsi_cbgcoveragegap": [
        _string("AgentId", "Agent ID", "Unique identifier of the analyzed agent.", required=True),
        _string("AgentName", "Agent Name", "Display name of the analyzed agent.", max_length=200),
        _picklist("Pathway", "Pathway", "Classified pathway for the agent.", "fsi_cbg_pathway"),
        _integer("EligibleUsers", "Eligible Users", "Count of users eligible to use the agent under current policies.", min_val=0),
        _integer("BlockedUsersCount", "Blocked Users Count", "Count of otherwise-intended users who would be blocked by current policies.", min_val=0),
        _memo("BlockedSampleUpns", "Blocked Sample UPNs", "Capped JSON sample of blocked user UPNs (sample size is bounded to avoid row blow-up)."),
        _picklist("BlockReasonSummary", "Block Reason Summary", "Dominant block reason across the blocked cohort.", "fsi_cbg_blockreason"),
        _picklist("SpendScope", "Spend Scope", "Surface-aware spend scope (Chat vs SharePoint) for this agent.", "fsi_cbg_spendscope"),
        _integer("GroupSizePartition", "Group Size Partition", "Total intended-audience size used to partition large groups above threshold T.", min_val=0),
        _boolean("MonitorOnly", "Monitor Only", "Whether this gap row is monitor-only (no enforcement action taken).", default=True),
        _datetime("AnalyzedAt", "Analyzed At", "When the coverage-gap analysis produced this row."),
        _datetime("RetainUntil", "Retain Until", "Retention horizon after which this aggregate row may be purged."),
        _memo("Notes", "Notes", "Free-text notes for this coverage-gap row."),
    ],
    "fsi_cbgagentcap": [
        _string("AgentId", "Agent ID", "Unique identifier of the capped agent.", required=True),
        _integer("MonthlyCreditCap", "Monthly Credit Cap", "Per-agent monthly credit ceiling.", min_val=0),
        _integer("CreditsConsumedMtd", "Credits Consumed MTD", "Credits consumed by this agent month-to-date.", min_val=0),
        _picklist("EnforcementMode", "Enforcement Mode", "Whether the cap is hard-stopped or degrades to detect-and-alert where no write API exists.", "fsi_cbg_enforcementmode"),
        _boolean("CapEnforced", "Cap Enforced", "Whether enforcement is currently active for this agent."),
        _picklist("ZoneClassification", "Zone Classification", "Governance zone this cap applies to.", "fsi_cbg_zoneclassification"),
        _datetime("LastEvaluatedAt", "Last Evaluated At", "When this cap was last evaluated against consumption."),
        _memo("Notes", "Notes", "Free-text notes for this cap record."),
    ],
    "fsi_cbgapprovedgrouppolicy": [
        _string("GroupId", "Group ID", "Entra security group object ID.", required=True),
        _picklist("GroupLayer", "Group Layer", "Governance layer this group serves (maker, audience, or billing).", "fsi_cbg_grouplayer", required=True),
        _boolean("SecurityEnabled", "Security Enabled", "Whether the Entra group has securityEnabled=true at admission. Groups with securityEnabled=false are rejected.", default=True, required=True),
        _boolean("MailEnabled", "Mail Enabled", "Whether the Entra group has mailEnabled at admission. Mail-enabled distribution groups are rejected.", default=False, required=True),
        _string("GroupTypes", "Group Types", "Comma-separated Entra groupTypes values at admission (e.g. DynamicMembership, Unified).", max_length=500),
        _picklist("ZoneClassification", "Zone Classification", "Governance zone this group applies to.", "fsi_cbg_zoneclassification"),
        _boolean("IsActive", "Is Active", "Whether this group registration is currently active.", default=True, required=True),
        _string("ApprovedBy", "Approved By", "UPN of the person who approved this group.", max_length=200),
        _datetime("ApprovedAt", "Approved At", "When this group was approved."),
        _memo("PolicyNotes", "Policy Notes", "Additional notes or context for this registration."),
    ],
}


# ---------------------------------------------------------------------------
# Relationships
# ---------------------------------------------------------------------------
RELATIONSHIPS = [
    {
        "@odata.type": "#Microsoft.Dynamics.CRM.OneToManyRelationshipMetadata",
        "SchemaName": f"{PUBLISHER_PREFIX}_CbgCoverageGap_CbgEntitlementMaterialized",
        "ReferencedEntity": "fsi_cbgcoveragegap",
        "ReferencingEntity": "fsi_cbgentitlementmaterialized",
        "CascadeConfiguration": {
            "Assign": "NoCascade",
            "Delete": "RemoveLink",
            "Merge": "NoCascade",
            "Reparent": "NoCascade",
            "Share": "NoCascade",
            "Unshare": "NoCascade",
        },
        "Lookup": {
            "SchemaName": f"{PUBLISHER_PREFIX}_RelatedCoverageGapId",
            "RequiredLevel": {"Value": "None"},
            "DisplayName": _loc("Related Coverage Gap"),
            "Description": _loc("Optional link to the per-agent coverage-gap row this decision rolls up to."),
        },
    },
]


# ---------------------------------------------------------------------------
# Alternate keys (idempotent upsert keys; keyed by table logical name)
# ---------------------------------------------------------------------------
# Mirrors copilot-agent-inventory's alt-key pattern so the upserts documented in
# flow-configuration.md (PATCH on a natural key) are idempotent. KeyAttributes use
# LOGICAL (lowercased) column names. Billing/credit policies key on their own policy
# identifier; the materialized cache keys on (agent, user); coverage-gap and agent-cap
# key on the agent; the approved-group registry keys on (group, layer).
ALT_KEYS = {
    "fsi_cbgbillingpolicy": [
        {
            "schema_name": "fsi_CbgBillingPolicyKey",
            "display": "Billing Policy Key",
            "key_attributes": ["fsi_billinginstanceid"],
        },
    ],
    "fsi_cbgcreditpolicy": [
        {
            "schema_name": "fsi_CbgCreditPolicyKey",
            "display": "Credit Policy Key",
            "key_attributes": ["fsi_creditpolicyid"],
        },
    ],
    "fsi_cbgentitlementmaterialized": [
        {
            "schema_name": "fsi_CbgEntMatAgentUserKey",
            "display": "Agent + User Key",
            "key_attributes": ["fsi_agentid", "fsi_userupn"],
        },
    ],
    "fsi_cbgcoveragegap": [
        {
            "schema_name": "fsi_CbgCoverageGapAgentKey",
            "display": "Agent Key",
            "key_attributes": ["fsi_agentid"],
        },
    ],
    "fsi_cbgagentcap": [
        {
            "schema_name": "fsi_CbgAgentCapAgentKey",
            "display": "Agent Key",
            "key_attributes": ["fsi_agentid"],
        },
    ],
    "fsi_cbgapprovedgrouppolicy": [
        {
            "schema_name": "fsi_CbgApprovedGroupKey",
            "display": "Group + Layer Key",
            "key_attributes": ["fsi_groupid", "fsi_grouplayer"],
        },
    ],
}


def _entity_key(key_def: dict) -> dict:
    """Build an EntityKeyMetadata definition for an alternate key (idempotent upsert)."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.EntityKeyMetadata",
        "SchemaName": key_def["schema_name"],
        "DisplayName": _loc(key_def["display"]),
        "KeyAttributes": key_def["key_attributes"],
    }


# ---------------------------------------------------------------------------
# Documentation helpers
# ---------------------------------------------------------------------------
def _label(obj: dict) -> str:
    """Extract the English (1033) label from a Dataverse LocalizedLabels structure."""
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
    odata_clean = odata.lstrip("#")
    return mapping.get(odata_clean, odata_clean.split(".")[-1] if odata_clean else "Unknown")


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

    lines.append("# Dataverse Schema Reference")
    lines.append("")
    lines.append("> Auto-generated from `create_cbg_dataverse_schema.py`. Do not edit manually.")
    lines.append("")
    lines.append(
        "All column logical names are the SchemaName lowercased (Dataverse never inserts "
        "underscores between words). Use the **Logical Name** column when writing OData "
        "`$select` / `$filter` queries."
    )
    lines.append("")

    # Tables
    lines.append("## Tables")
    lines.append("")
    lines.append("| SchemaName | Logical Name | Entity Set Name | Description | Primary Name Attribute |")
    lines.append("|---|---|---|---|---|")
    for schema_name, tbl in TABLES.items():
        logical = schema_name.lower()
        desc = _label(tbl.get("Description", {}))
        pna = tbl.get("PrimaryNameAttribute", "")
        esn = tbl.get("EntitySetName", "")
        lines.append(f"| {schema_name} | {logical} | {esn} | {desc} | {pna} |")
    lines.append("")

    # Columns
    lines.append("## Columns")
    lines.append("")
    for table_schema_name, tbl in TABLES.items():
        table_logical = table_schema_name.lower()
        primary_attrs = tbl.get("Attributes", [])
        extra_cols = COLUMNS.get(table_logical, [])
        all_cols = primary_attrs + extra_cols

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

    # Alternate keys
    lines.append("## Alternate Keys")
    lines.append("")
    lines.append(
        "Alternate keys give the flows in `flow-configuration.md` an idempotent "
        "upsert (PATCH on a natural key). Key attributes are logical (lowercased) "
        "column names."
    )
    lines.append("")
    lines.append("| Table (Logical) | Alternate Key | Key Attributes |")
    lines.append("|---|---|---|")
    for table_logical_name, keys in ALT_KEYS.items():
        for key_def in keys:
            attrs = ", ".join(f"`{a}`" for a in key_def["key_attributes"])
            lines.append(f"| {table_logical_name} | {key_def['schema_name']} | {attrs} |")
    lines.append("")

    # Option sets
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

    # Relationships
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


# ---------------------------------------------------------------------------
# Schema deployment
# ---------------------------------------------------------------------------
def create_optionsets(client: DataverseClient, dry_run: bool) -> dict:
    """Create global option sets (CBG-specific)."""
    logger.info("=== Creating Option Sets ===")
    created = 0
    skipped = 0
    for name, metadata in OPTIONSETS.items():
        if client.get_global_optionset(name):
            logger.info("  %s: Already exists", name)
            skipped += 1
        else:
            logger.info("  %s: Creating", name)
            client.create_option_set(metadata)
            created += 1
    return {"created": created, "skipped": skipped}


def create_tables(client: DataverseClient, dry_run: bool) -> dict:
    """Create tables."""
    logger.info("=== Creating Tables ===")
    created = 0
    skipped = 0
    for table_name, metadata in TABLES.items():
        logical_name = table_name.lower()
        if client.check_table_exists(logical_name):
            logger.info("  %s: Already exists", table_name)
            skipped += 1
        else:
            logger.info("  %s: Creating", table_name)
            client.create_table(metadata)
            created += 1
    return {"created": created, "skipped": skipped}


def create_columns(client: DataverseClient, dry_run: bool) -> None:
    """Create columns on tables."""
    logger.info("=== Creating Columns ===")
    for table_logical_name, columns in COLUMNS.items():
        logger.info("%s:", table_logical_name)
        for column_metadata in columns:
            schema_name = column_metadata.get("SchemaName", "")
            col_logical_name = schema_name.lower()
            if client.get_attribute_metadata(table_logical_name, col_logical_name):
                logger.info("  %s: Already exists", schema_name)
            else:
                logger.info("  %s: Creating", schema_name)
                client.create_column(table_logical_name, column_metadata)


def create_relationships(client: DataverseClient, dry_run: bool) -> dict:
    """Create one-to-many relationships (lookup columns)."""
    logger.info("=== Creating Relationships ===")
    created = 0
    skipped = 0
    for rel_metadata in RELATIONSHIPS:
        schema_name = rel_metadata.get("SchemaName", "")
        if client.get_relationship(schema_name):
            logger.info("  %s: Already exists", schema_name)
            skipped += 1
        else:
            logger.info("  %s: Creating", schema_name)
            if not dry_run:
                client.create_relationship(rel_metadata)
            created += 1
    return {"created": created, "skipped": skipped}


def create_alternate_keys(client: DataverseClient, dry_run: bool) -> dict:
    """Create alternate keys for idempotent upsert (async system jobs; idempotent)."""
    logger.info("=== Creating Alternate Keys ===")
    created = 0
    skipped = 0
    for table_logical_name, keys in ALT_KEYS.items():
        for key_def in keys:
            key_schema = key_def["schema_name"]
            if client.get_entity_key(table_logical_name, key_schema.lower()):
                logger.info("  %s.%s: Already exists", table_logical_name, key_schema)
                skipped += 1
            else:
                logger.info("  %s.%s: Creating", table_logical_name, key_schema)
                client.create_entity_key(table_logical_name, _entity_key(key_def))
                created += 1
    return {"created": created, "skipped": skipped}


def create_schema(client: DataverseClient, dry_run: bool) -> dict:
    """Create the complete schema (orchestrator)."""
    option_set_results = create_optionsets(client, dry_run)
    table_results = create_tables(client, dry_run)
    create_columns(client, dry_run)
    alt_key_results = create_alternate_keys(client, dry_run)
    relationship_results = create_relationships(client, dry_run)
    logger.info("=== Schema Creation Complete ===")
    return {
        "errors": 0,
        "option_sets": option_set_results,
        "tables": table_results,
        "alternate_keys": alt_key_results,
        "relationships": relationship_results,
    }


def main() -> None:
    """Parse arguments and create (or document) the CBG Dataverse schema."""
    parser = argparse.ArgumentParser(
        description="Create Dataverse schema for Copilot Billing Governance",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--tenant-id", default=os.environ.get("CBG_TENANT_ID"), help="Entra ID tenant ID (or set CBG_TENANT_ID env var)")
    parser.add_argument("--client-id", default=os.environ.get("CBG_CLIENT_ID"), help="Application (client) ID (or set CBG_CLIENT_ID env var)")
    parser.add_argument("--environment-url", default=os.environ.get("CBG_ENVIRONMENT_URL"), help="Dataverse environment URL (or set CBG_ENVIRONMENT_URL env var)")
    parser.add_argument("--auth-mode", default=os.environ.get("CBG_AUTH_MODE"), help="Auth mode: managed-identity, workload-identity, certificate, interactive, or client-secret")
    parser.add_argument("--interactive", action="store_true", help="Use interactive browser authentication")
    parser.add_argument("--dry-run", action="store_true", help="Preview schema operations without API calls")
    parser.add_argument("--output-docs", action="store_true", help="Generate docs/dataverse-schema.md and exit (no credentials required)")
    args = parser.parse_args()

    logging.basicConfig(level=logging.INFO, format="%(message)s")

    # --output-docs: generate schema reference docs and exit immediately
    if args.output_docs:
        script_dir = os.path.dirname(os.path.abspath(__file__))
        solution_root = os.path.dirname(script_dir)
        docs_dir = os.path.join(solution_root, "docs")
        os.makedirs(docs_dir, exist_ok=True)
        out_path = os.path.join(docs_dir, "dataverse-schema.md")
        md = generate_schema_docs()
        with open(out_path, "w", encoding="utf-8", newline="\n") as fh:
            fh.write(md)
            fh.write("\n")
        logger.info("Schema docs written to %s", out_path)
        sys.exit(0)

    if not args.tenant_id or not args.environment_url:
        parser.error("Missing required arguments. Provide --tenant-id and --environment-url (or set CBG_TENANT_ID and CBG_ENVIRONMENT_URL env vars)")

    # Managed-identity-first: prefer a managed/workload identity supplied via auth-mode.
    # legacy: dev-only — replace with managed identity in production
    client_secret = os.environ.get("CBG_CLIENT_SECRET")
    resolved_auth_mode = args.auth_mode
    if not resolved_auth_mode and not args.interactive and not client_secret and not args.client_id:
        resolved_auth_mode = "managed-identity"

    try:
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=client_secret,
            interactive=args.interactive,
            dry_run=args.dry_run,
            auth_mode=resolved_auth_mode,
        )

        if args.dry_run:
            logger.info("=== DRY RUN MODE - No changes will be made ===")

        create_schema(client, args.dry_run)

        if not args.dry_run:
            logger.info("Schema deployment: SUCCESS")

        sys.exit(0)
    except requests.HTTPError as exc:
        logger.error("HTTP Error: %s", exc)
        sys.exit(2)
    except RuntimeError as exc:
        logger.error("Authentication Error: %s", exc)
        sys.exit(1)


if __name__ == "__main__":
    main()
