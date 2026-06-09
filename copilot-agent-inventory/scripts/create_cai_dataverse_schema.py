#!/usr/bin/env python3
"""Create the Dataverse schema for the Copilot Agent Inventory solution.

Deploys the canonical eight-entity governance store that serves as the
system-of-record for Copilot Studio and Agent Builder agents discovered
across a tenant. All operations are idempotent (check-then-create), so the
script is safe to re-run.

Canonical entity model (logical names):
  - fsi_copilotagent          (OrganizationOwned): Agent master record
  - fsi_caienvironment        (OrganizationOwned): Power Platform environment
  - fsi_caiagentfeature       (OrganizationOwned): One row per detected feature
  - fsi_caiauthshare          (OrganizationOwned): Auth + sharing posture
  - fsi_caibillingentitlement (OrganizationOwned): Billing / credit entitlement
  - fsi_caiusagesignal        (OrganizationOwned): Source-aggregated usage rollup
  - fsi_caiworkiqstate        (OrganizationOwned): Work IQ config-vs-invoked state
  - fsi_caicompliancestate    (OrganizationOwned): Risk + scan completeness

ARA boundary (ASSUMPTION — flagged for Jude's ratification): this solution
owns the NEW canonical entity fsi_copilotagent. It does NOT modify
agent-registry-automation's legacy fsi_agentinventory. See README.md
"ARA-boundary ratification flag".

Usage:
  # Generate docs/dataverse-schema.md only (no Dataverse connection)
  python create_cai_dataverse_schema.py --output-docs

  # Dry-run against a live tenant (reads to preview, no writes)
  python create_cai_dataverse_schema.py --dry-run --interactive \
      --environment-url https://org.crm.dynamics.com --tenant-id <tenant>

  # Deploy (managed-identity-first; interactive shown for admin workstation)
  python create_cai_dataverse_schema.py --interactive \
      --environment-url https://org.crm.dynamics.com --tenant-id <tenant>
"""

import argparse
import logging
import os
import sys
from pathlib import Path

# Import the shared Dataverse client from scripts/shared.
_SHARED_DIR = Path(__file__).resolve().parent.parent.parent / "scripts" / "shared"
if str(_SHARED_DIR) not in sys.path:
    sys.path.insert(0, str(_SHARED_DIR))
from dataverse_client import DataverseClient  # noqa: E402

logger = logging.getLogger("create_cai_dataverse_schema")

# Publisher prefix for custom entities
PUBLISHER_PREFIX = "fsi"

# =============================================================================
# Shared Option Sets (reused across FSI solutions; existence check first)
# =============================================================================

SHARED_OPTIONSETS = {
    "fsi_acv_zone": {
        "name": "fsi_acv_zone",
        "options": [
            ("Unclassified", 0),
            ("Zone 1", 1),
            ("Zone 2", 2),
            ("Zone 3", 3),
        ],
    },
}

# =============================================================================
# Copilot Agent Inventory (CAI) Option Sets
# =============================================================================
#
# All CAI option sets use the 100000000+ value range (Dataverse custom option
# convention). The featuretype set mirrors the verified botcomponent
# componenttype enum (0-19) PLUS the six many-to-many relationship targets.
# Re-pull the live enum at build time via
# GET GlobalOptionSetDefinitions(Name='botcomponent_componenttype') to catch
# any code >= 20 added since the 2025-10-31 platform docs.

CAI_OPTIONSETS = {
    "fsi_cai_createdin": {
        "name": "fsi_cai_createdin",
        "options": [
            ("Copilot Studio", 100000000),
            ("Microsoft 365 Copilot Agent Builder", 100000001),
            ("Unknown", 100000002),
        ],
    },
    "fsi_cai_agenttype": {
        "name": "fsi_cai_agenttype",
        "options": [
            ("Standard", 100000000),
            ("Lite / Agent Builder", 100000001),
            ("Declarative Agent", 100000002),
            ("Classic V1 (excluded)", 100000003),
            ("Unknown", 100000004),
        ],
    },
    "fsi_cai_discoverysource": {
        "name": "fsi_cai_discoverysource",
        "options": [
            ("Azure Resource Graph", 100000000),
            ("Per-Environment Dataverse Scan", 100000001),
            ("PPAC Reconciliation", 100000002),
            ("Reconciled (multi-source)", 100000003),
        ],
    },
    "fsi_cai_featuretype": {
        "name": "fsi_cai_featuretype",
        "options": [
            # botcomponent componenttype-derived (V1 + V2 collapsed to a feature)
            ("Topic", 100000000),
            ("Skill", 100000001),
            ("Knowledge Source", 100000002),
            ("Custom GPT", 100000003),
            ("Copilot Settings", 100000004),
            ("External Trigger", 100000005),
            ("File Attachment", 100000006),
            ("Bot Variable", 100000007),
            ("Bot Entity", 100000008),
            ("Dialog", 100000009),
            ("Dialog Schema", 100000021),  # componenttype code 8 (distinct from code 4 Dialog)
            ("Trigger", 100000010),
            ("Language Understanding", 100000011),
            ("Language Generation", 100000012),
            ("Bot Translations", 100000013),
            ("Test Case", 100000014),
            # many-to-many relationship targets
            ("Tool / Plugin", 100000015),
            ("Connector", 100000016),
            ("Power Automate Flow", 100000017),
            ("Environment Variable", 100000018),
            ("Dataverse Search Grounding", 100000019),
            ("AI Builder Model", 100000020),
            ("Other / Unrecognized", 100000099),
        ],
    },
    "fsi_cai_componentversion": {
        "name": "fsi_cai_componentversion",
        "options": [
            ("V1", 100000000),
            ("V2", 100000001),
            ("Not Applicable", 100000002),
        ],
    },
    "fsi_cai_policytype": {
        "name": "fsi_cai_policytype",
        "options": [
            ("PAYG Billing Policy", 100000000),
            ("Prepaid Credit Policy", 100000001),
            ("None", 100000002),
            ("Unknown", 100000003),
        ],
    },
    "fsi_cai_spendscope": {
        "name": "fsi_cai_spendscope",
        "options": [
            ("Chat", 100000000),
            ("SharePoint", 100000001),
            ("All Surfaces", 100000002),
            ("Unknown", 100000003),
        ],
    },
    "fsi_cai_workiqtier": {
        "name": "fsi_cai_workiqtier",
        "options": [
            ("None", 100000000),
            ("MCP in Copilot Studio (per-user license)", 100000001),
            ("Direct Work IQ API (consumption)", 100000002),
            ("Unknown", 100000003),
        ],
    },
    "fsi_cai_workiqobserved": {
        "name": "fsi_cai_workiqobserved",
        "options": [
            ("Not Observed", 100000000),
            ("Invoked", 100000001),
            ("Configured, Not Invoked", 100000002),
            ("Unknown", 100000003),
        ],
    },
    "fsi_cai_risklevel": {
        "name": "fsi_cai_risklevel",
        "options": [
            ("Low", 100000000),
            ("Medium", 100000001),
            ("High", 100000002),
            ("Critical", 100000003),
            ("Unknown", 100000004),
        ],
    },
    "fsi_cai_scancompleteness": {
        "name": "fsi_cai_scancompleteness",
        "options": [
            ("Complete", 100000000),
            ("Incomplete Scan", 100000001),
            ("Failed", 100000002),
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
        "RequiredLevel": {"Value": "None"},
        "DefaultValue": default,
        "OptionSet": {
            "TrueOption": {
                "Value": 1,
                "Label": _label("Yes"),
            },
            "FalseOption": {
                "Value": 0,
                "Label": _label("No"),
            },
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

# --- 1. fsi_CopilotAgent (Agent master / system of record) -------------------
COPILOTAGENT_COLUMNS = [
    _string_col("fsi_AgentId", "Agent ID", 100,
                description="Copilot Studio bot GUID (ARG 'name' / Dataverse botid)"),
    _string_col("fsi_AgentName", "Agent Name", 500,
                description="Agent display name (ARG properties.displayName)"),
    _string_col("fsi_EnvironmentId", "Environment ID", 100,
                description="Power Platform environment GUID this agent lives in"),
    _string_col("fsi_SchemaName", "Schema Name", 200, required=False,
                description="Dataverse schemaName of the agent"),
    _string_col("fsi_OwnerUpn", "Owner UPN", 200, required=False,
                description="Agent owner user principal name"),
    _string_col("fsi_OwnerId", "Owner Object ID", 100, required=False,
                description="Agent owner Microsoft Entra ID object GUID"),
    _picklist_col("fsi_CreatedIn", "Created In", "fsi_cai_createdin",
                  required=False,
                  description="Authoring surface; the zero-rating entitlement classifier keys on this"),
    _picklist_col("fsi_AgentType", "Agent Type", "fsi_cai_agenttype",
                  required=False,
                  description="Standard / Lite-Agent-Builder / Declarative; drives scan completeness"),
    _string_col("fsi_PublishedState", "Published State", 100, required=False,
                description="Publish/state status derived from statecode + lastPublishedAt"),
    _string_col("fsi_AuthMode", "Auth Mode", 100, required=False,
                description="bot.authenticationmode (No-auth / Microsoft / manual)"),
    _string_col("fsi_BotId", "Bot ID", 100, required=False,
                description="Identity botId from ARG"),
    _string_col("fsi_EntraAppId", "Entra App ID", 100, required=False,
                description="Microsoft Entra ID application (client) ID bound to the agent"),
    _string_col("fsi_EntraAgentId", "Entra Agent ID", 100, required=False,
                description="Microsoft Entra Agent ID (preview field)"),
    _boolean_col("fsi_IsManaged", "Is Managed", default=False,
                 description="Managed flag (preview; null for Agent Builder agents)"),
    _string_col("fsi_Region", "Region", 100, required=False,
                description="Environment region / location"),
    _picklist_col("fsi_DiscoverySource", "Discovery Source",
                  "fsi_cai_discoverysource", required=False,
                  description="Which discovery layer last wrote this row"),
    _datetime_col("fsi_CreatedOn", "Created On", required=False,
                  description="Agent creation timestamp (ARG createdAt)"),
    _datetime_col("fsi_ModifiedOn", "Modified On", required=False,
                  description="Agent last-modified timestamp"),
    _datetime_col("fsi_LastPublishedAt", "Last Published At", required=False,
                  description="Last publish timestamp (ARG lastPublishedAt)"),
    _datetime_col("fsi_LastScannedAt", "Last Scanned At",
                  description="When this inventory row was last refreshed"),
    _string_col("fsi_RunId", "Run ID", 36, required=False,
                description="GUID correlating all records from one scan run"),
    _memo_col("fsi_RawJson", "Raw JSON", 100000,
              description="Full ARG / bot JSON snapshot for evidence and reparse"),
]

# --- 2. fsi_CaiEnvironment ---------------------------------------------------
ENVIRONMENT_COLUMNS = [
    _string_col("fsi_EnvironmentId", "Environment ID", 100,
                description="Power Platform environment GUID"),
    _string_col("fsi_EnvironmentName", "Environment Name", 500,
                description="Environment display name"),
    _string_col("fsi_EnvironmentUrl", "Environment URL", 400, required=False,
                description="Source-environment Dataverse Web API base URL; the "
                            "Work IQ solution joins this to resolve per-env URLs"),
    _string_col("fsi_Region", "Region", 100, required=False,
                description="Environment region / location"),
    _string_col("fsi_EnvironmentType", "Environment Type", 100, required=False,
                description="Production / Sandbox / Trial / Default / Developer"),
    _boolean_col("fsi_IsManaged", "Is Managed Environment", default=False,
                 description="Whether this is a Managed Environment"),
    _picklist_col("fsi_Zone", "Zone", "fsi_acv_zone", required=False,
                  description="Governance zone classification"),
    _integer_col("fsi_AgentCount", "Agent Count", required=False,
                 description="Number of agents discovered in this environment"),
    _memo_col("fsi_DeltaLink", "Delta Link", 100000,
              description="Dataverse @odata.deltaLink for incremental change tracking"),
    _datetime_col("fsi_LastScannedAt", "Last Scanned At",
                  description="When this environment was last scanned"),
    _string_col("fsi_RunId", "Run ID", 36, required=False,
                description="Correlating scan run GUID"),
]

# --- 3. fsi_CaiAgentFeature (one row per detected feature) --------------------
AGENTFEATURE_COLUMNS = [
    _string_col("fsi_AgentId", "Agent ID", 100,
                description="Parent agent bot GUID"),
    _string_col("fsi_EnvironmentId", "Environment ID", 100, required=False,
                description="Environment GUID the feature was detected in"),
    _picklist_col("fsi_FeatureType", "Feature Type", "fsi_cai_featuretype",
                  description="Feature class (botcomponent type or M:M relationship target)"),
    _integer_col("fsi_ComponentType", "Component Type Code", required=False,
                 description="Raw botcomponent_componenttype code (0-19), if applicable"),
    _picklist_col("fsi_ComponentVersion", "Component Version",
                  "fsi_cai_componentversion", required=False,
                  description="V1 / V2 pairing of the source component"),
    _string_col("fsi_SourceObjectId", "Source Object ID", 100,
                description="botcomponentid or many-to-many target record GUID"),
    _string_col("fsi_SourceObjectName", "Source Object Name", 500, required=False,
                description="Display name of the source component / target"),
    _boolean_col("fsi_IsEnabled", "Is Enabled", default=True,
                 description="Whether the feature is enabled on the agent"),
    _string_col("fsi_RelationshipName", "Relationship Name", 200, required=False,
                description="botcomponent navigation property the feature was matched through"),
    _datetime_col("fsi_LastScannedAt", "Last Scanned At",
                  description="When this feature row was last refreshed"),
    _string_col("fsi_RunId", "Run ID", 36, required=False,
                description="Correlating scan run GUID"),
]

# --- 4. fsi_CaiAuthShare -----------------------------------------------------
AUTHSHARE_COLUMNS = [
    _string_col("fsi_AgentId", "Agent ID", 100,
                description="Agent bot GUID"),
    _string_col("fsi_EnvironmentId", "Environment ID", 100, required=False,
                description="Environment GUID"),
    _string_col("fsi_AuthMode", "Auth Mode", 100, required=False,
                description="No auth / Authenticate with Microsoft / Authenticate manually"),
    _string_col("fsi_AuthProvider", "Auth Provider", 200, required=False,
                description="Identity provider (e.g., Microsoft Entra ID, Generic OAuth2)"),
    _boolean_col("fsi_RequireSignIn", "Require Sign In", default=False,
                 description="Whether 'Require users to sign in' is ON"),
    _boolean_col("fsi_EntraAuthAsserted", "Entra Auth Asserted", default=False,
                 description="Derived: Entra-ID auth AND Require-sign-in ON (audience-control predicate)"),
    _memo_col("fsi_ViewerGroups", "Viewer Groups", 10000,
              description="Security groups granted chat viewer access (JSON)"),
    _memo_col("fsi_EditorPrincipals", "Editor Principals", 10000,
              description="Individual principals granted editor access (JSON)"),
    _integer_col("fsi_SharedWithViewerCount", "Shared With Viewer Count",
                 required=False,
                 description="Count of viewer principals/groups"),
    _integer_col("fsi_SharedWithEditorCount", "Shared With Editor Count",
                 required=False,
                 description="Count of editor principals"),
    _string_col("fsi_LimitSharingMode", "Limit Sharing Mode", 100, required=False,
                description="Managed-environment bot-limitSharingMode value"),
    _datetime_col("fsi_LastScannedAt", "Last Scanned At",
                  description="When this posture was last scanned"),
    _string_col("fsi_RunId", "Run ID", 36, required=False,
                description="Correlating scan run GUID"),
]

# --- 5. fsi_CaiBillingEntitlement (downstream-populated shell) ----------------
BILLINGENTITLEMENT_COLUMNS = [
    _string_col("fsi_AgentId", "Agent ID", 100, required=False,
                description="Agent bot GUID (null for tenant-level policy rows)"),
    _string_col("fsi_PolicyId", "Policy ID", 200, required=False,
                description="Billing or credit policy identifier"),
    _picklist_col("fsi_PolicyType", "Policy Type", "fsi_cai_policytype",
                  required=False,
                  description="PAYG / Prepaid credit policy / None"),
    _string_col("fsi_UserScopeGroupId", "User Scope Group ID", 100, required=False,
                description="Microsoft Entra ID group GUID scoping the policy"),
    _picklist_col("fsi_SpendScope", "Spend Scope", "fsi_cai_spendscope",
                  required=False,
                  description="Surface the policy allocation applies to (credit policy is Chat-only today)"),
    _string_col("fsi_BudgetState", "Budget State", 100, required=False,
                description="Active / Exhausted / Alerting"),
    _boolean_col("fsi_ZeroRatingEligible", "Zero Rating Eligible", default=False,
                 description="Fail-closed default False pending the June 2026 Licensing Guide; "
                             "CS-built generative answers and tenant-grounded responses remain billable"),
    _string_col("fsi_EntitlementBasis", "Entitlement Basis", 1000, required=False,
                description="Note on the license + createdIn basis for the entitlement decision"),
    _datetime_col("fsi_LastEvaluatedAt", "Last Evaluated At", required=False,
                  description="When the entitlement was last evaluated"),
    _string_col("fsi_RunId", "Run ID", 36, required=False,
                description="Correlating scan run GUID"),
]

# --- 6. fsi_CaiUsageSignal ---------------------------------------------------
USAGESIGNAL_COLUMNS = [
    _string_col("fsi_AgentId", "Agent ID", 100,
                description="Agent bot GUID"),
    _string_col("fsi_EnvironmentId", "Environment ID", 100, required=False,
                description="Environment GUID"),
    _datetime_col("fsi_LastInteractionUtc", "Last Interaction (UTC)",
                  required=False,
                  description="Most recent interaction timestamp"),
    _integer_col("fsi_Interactions30d", "Interactions (30d)", required=False,
                 description="Interaction count over the rolling 30-day window"),
    _integer_col("fsi_UniqueUsers30d", "Unique Users (30d)", required=False,
                 description="Distinct users over the rolling 30-day window"),
    _integer_col("fsi_Sessions30d", "Sessions (30d)", required=False,
                 description="Session count over the rolling 30-day window"),
    _integer_col("fsi_AggregationWindowDays", "Aggregation Window (days)",
                 required=False,
                 description="Rollup window length in days (default 30)"),
    _string_col("fsi_SignalSource", "Signal Source", 200, required=False,
                description="Source of the aggregate (e.g., msdyn_botsession, App Insights)"),
    _datetime_col("fsi_LastAggregatedAt", "Last Aggregated At",
                  description="When the usage rollup was last computed"),
    _string_col("fsi_RunId", "Run ID", 36, required=False,
                description="Correlating scan run GUID"),
]

# --- 7. fsi_CaiWorkIqState (downstream-populated by work-iq-usage-detection) --
WORKIQSTATE_COLUMNS = [
    _string_col("fsi_AgentId", "Agent ID", 100,
                description="Agent bot GUID"),
    _string_col("fsi_EnvironmentId", "Environment ID", 100, required=False,
                description="Environment GUID"),
    _boolean_col("fsi_Configured", "Configured", default=False,
                 description="Whether Work IQ / semantic search is configured"),
    _picklist_col("fsi_ConfiguredTier", "Configured Tier", "fsi_cai_workiqtier",
                  required=False,
                  description="Entitlement split: MCP-in-Copilot-Studio vs Direct Work IQ API"),
    _picklist_col("fsi_ObservedStatus", "Observed Status",
                  "fsi_cai_workiqobserved", required=False,
                  description="Config-vs-invoked classifier result"),
    _boolean_col("fsi_PerUserLicenseRequired", "Per-User License Required",
                 default=False,
                 description="MCP-in-Copilot-Studio path requires a per-user M365 Copilot license"),
    _integer_col("fsi_ConfigSourceComponentType", "Config Source Component Type",
                 required=False,
                 description="botcomponent type where config was resolved (18/15/16) — sample to confirm"),
    _datetime_col("fsi_LastObservedUtc", "Last Observed (UTC)", required=False,
                  description="Most recent observed (invoked) signal timestamp"),
    _datetime_col("fsi_LastScannedAt", "Last Scanned At",
                  description="When this state row was last refreshed"),
    _string_col("fsi_RunId", "Run ID", 36, required=False,
                description="Correlating scan run GUID"),
]

# --- 8. fsi_CaiComplianceState ----------------------------------------------
COMPLIANCESTATE_COLUMNS = [
    _string_col("fsi_AgentId", "Agent ID", 100,
                description="Agent bot GUID"),
    _string_col("fsi_EnvironmentId", "Environment ID", 100, required=False,
                description="Environment GUID"),
    _picklist_col("fsi_RiskLevel", "Risk Level", "fsi_cai_risklevel",
                  required=False,
                  description="Aggregated risk level for the agent"),
    _picklist_col("fsi_ScanCompleteness", "Scan Completeness",
                  "fsi_cai_scancompleteness",
                  description="Complete / Incomplete Scan (Lite/Agent-Builder) / Failed"),
    _string_col("fsi_ScanCompletenessReason", "Scan Completeness Reason", 1000,
                required=False,
                description="Why a scan is incomplete (e.g., no public API returns full Agent Builder definition)"),
    _integer_col("fsi_ViolationCount", "Violation Count", required=False,
                 description="Number of open violations rolled up for the agent"),
    _memo_col("fsi_ViolationsJson", "Violations JSON", 100000,
              description="Structured violations[] rollup for the agent"),
    _datetime_col("fsi_LastCheckedUtc", "Last Checked (UTC)",
                  description="When compliance state was last evaluated"),
    _string_col("fsi_RunId", "Run ID", 36, required=False,
                description="Correlating scan run GUID"),
]


# =============================================================================
# Table Definitions (logical name -> definition)
# =============================================================================
#
# All tables are OrganizationOwned: this is a tenant-wide governance
# system-of-record, not user-scoped data. Linkage between the agent master and
# the satellite tables is modeled via fsi_agentid + fsi_environmentid string
# columns plus alternate keys for idempotent upsert (the proven repo pattern,
# mirroring agent-registry-automation's fsi_AgentEnvUniqueKey). Promoting these
# to native Dataverse lookups is a documented future enhancement.

TABLES = {
    "fsi_copilotagent": {
        "schema_name": "fsi_CopilotAgent",
        "display": "Copilot Agent",
        "plural": "Copilot Agents",
        "description": (
            "Canonical agent master record (system-of-record) for Copilot "
            "Studio and Agent Builder agents discovered across the tenant"
        ),
        "ownership": "OrganizationOwned",
        "columns": COPILOTAGENT_COLUMNS,
        "entity_set_name": "fsi_copilotagents",
        "alt_keys": [
            {
                "schema_name": "fsi_AgentEnvKey",
                "display": "Agent + Environment Key",
                "key_attributes": ["fsi_agentid", "fsi_environmentid"],
            }
        ],
    },
    "fsi_caienvironment": {
        "schema_name": "fsi_CaiEnvironment",
        "display": "CAI Environment",
        "plural": "CAI Environments",
        "description": (
            "Power Platform environment inventory with zone classification "
            "and per-environment delta-change-tracking watermark"
        ),
        "ownership": "OrganizationOwned",
        "columns": ENVIRONMENT_COLUMNS,
        "entity_set_name": "fsi_caienvironments",
        "alt_keys": [
            {
                "schema_name": "fsi_EnvKey",
                "display": "Environment Key",
                "key_attributes": ["fsi_environmentid"],
            }
        ],
    },
    "fsi_caiagentfeature": {
        "schema_name": "fsi_CaiAgentFeature",
        "display": "CAI Agent Feature",
        "plural": "CAI Agent Features",
        "description": (
            "Capability-composition layer: one row per detected feature "
            "(botcomponent or many-to-many relationship target) per agent"
        ),
        "ownership": "OrganizationOwned",
        "columns": AGENTFEATURE_COLUMNS,
        "entity_set_name": "fsi_caiagentfeatures",
        "alt_keys": [
            {
                "schema_name": "fsi_AgentFeatureKey",
                "display": "Agent + Source Object Key",
                "key_attributes": ["fsi_agentid", "fsi_sourceobjectid"],
            }
        ],
    },
    "fsi_caiauthshare": {
        "schema_name": "fsi_CaiAuthShare",
        "display": "CAI Auth Share",
        "plural": "CAI Auth Shares",
        "description": (
            "Per-agent authentication and sharing posture, including the "
            "Entra-ID-auth + Require-sign-in audience-control predicate"
        ),
        "ownership": "OrganizationOwned",
        "columns": AUTHSHARE_COLUMNS,
        "entity_set_name": "fsi_caiauthshares",
        "alt_keys": [
            {
                "schema_name": "fsi_AuthShareKey",
                "display": "Agent + Environment Key",
                "key_attributes": ["fsi_agentid", "fsi_environmentid"],
            }
        ],
    },
    "fsi_caibillingentitlement": {
        "schema_name": "fsi_CaiBillingEntitlement",
        "display": "CAI Billing Entitlement",
        "plural": "CAI Billing Entitlements",
        "description": (
            "Billing / credit entitlement shell (populated downstream by the "
            "billing-governance solution); zero-rating defaults fail-closed"
        ),
        "ownership": "OrganizationOwned",
        "columns": BILLINGENTITLEMENT_COLUMNS,
        "entity_set_name": "fsi_caibillingentitlements",
        "alt_keys": [],
    },
    "fsi_caiusagesignal": {
        "schema_name": "fsi_CaiUsageSignal",
        "display": "CAI Usage Signal",
        "plural": "CAI Usage Signals",
        "description": (
            "Source-aggregated per-agent usage rollup (30-day interactions, "
            "unique users, sessions); never stores transcript rows"
        ),
        "ownership": "OrganizationOwned",
        "columns": USAGESIGNAL_COLUMNS,
        "entity_set_name": "fsi_caiusagesignals",
        "alt_keys": [
            {
                "schema_name": "fsi_UsageSignalKey",
                "display": "Agent + Environment Key",
                "key_attributes": ["fsi_agentid", "fsi_environmentid"],
            }
        ],
    },
    "fsi_caiworkiqstate": {
        "schema_name": "fsi_CaiWorkIqState",
        "display": "CAI Work IQ State",
        "plural": "CAI Work IQ States",
        "description": (
            "Work IQ config-vs-invoked state shell (populated downstream by "
            "work-iq-usage-detection); emits configuredTier"
        ),
        "ownership": "OrganizationOwned",
        "columns": WORKIQSTATE_COLUMNS,
        "entity_set_name": "fsi_caiworkiqstates",
        "alt_keys": [
            {
                "schema_name": "fsi_WorkIqStateKey",
                "display": "Agent + Environment Key",
                "key_attributes": ["fsi_agentid", "fsi_environmentid"],
            }
        ],
    },
    "fsi_caicompliancestate": {
        "schema_name": "fsi_CaiComplianceState",
        "display": "CAI Compliance State",
        "plural": "CAI Compliance States",
        "description": (
            "Per-agent risk level, scan completeness (incomplete-scan marker "
            "for Lite/Agent-Builder), and violations rollup"
        ),
        "ownership": "OrganizationOwned",
        "columns": COMPLIANCESTATE_COLUMNS,
        "entity_set_name": "fsi_caicompliancestates",
        "alt_keys": [
            {
                "schema_name": "fsi_ComplianceStateKey",
                "display": "Agent + Environment Key",
                "key_attributes": ["fsi_agentid", "fsi_environmentid"],
            }
        ],
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
    """Build EntityMetadata dict (table + primary name attribute)."""
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
                "@odata.type": (
                    "#Microsoft.Dynamics.CRM.StringAttributeMetadata"
                ),
                "SchemaName": "fsi_Name",
                "DisplayName": _label(f"{table_def['display']} Name"),
                "Description": _label("Primary name attribute"),
                "RequiredLevel": {"Value": "ApplicationRequired"},
                "MaxLength": 850,
                "FormatName": {"Value": "Text"},
                "IsPrimaryName": True,
            },
        ],
    }
    if table_def.get("entity_set_name"):
        definition["EntitySetName"] = table_def["entity_set_name"]
    return definition


def _build_entity_key_metadata(key_def: dict) -> dict:
    """Build EntityKeyMetadata dict for an alternate key (idempotent upsert)."""
    return {
        "@odata.type": "Microsoft.Dynamics.CRM.EntityKeyMetadata",
        "SchemaName": key_def["schema_name"],
        "DisplayName": _label(key_def["display"]),
        "KeyAttributes": key_def["key_attributes"],
    }


# =============================================================================
# Documentation Generator
# =============================================================================


def generate_docs(output_path: str) -> None:
    """Generate Markdown documentation of the Dataverse schema.

    Writes docs/dataverse-schema.md listing every option set, table, column,
    and alternate key. This file is the single source of truth for logical
    column names used in scanner OData queries.

    Args:
        output_path: Path to write the documentation file.
    """
    total_cols = sum(len(t["columns"]) for t in TABLES.values())
    lines = [
        "# Copilot Agent Inventory - Dataverse Schema",
        "",
        (
            "Auto-generated schema documentation. Do not edit manually — regenerate"
            " with `python scripts/create_cai_dataverse_schema.py --output-docs`."
        ),
        "",
        "## Overview",
        "",
        f"The Copilot Agent Inventory solution uses **{len(TABLES)} Dataverse "
        f"tables**, **{len(CAI_OPTIONSETS)} solution-specific option sets**, and "
        f"**{len(SHARED_OPTIONSETS)} shared option set(s)**, with "
        f"**{total_cols} custom columns** (plus the auto-created primary key and "
        "`fsi_Name` on each table). All entities use the `fsi_` publisher "
        "prefix.",
        "",
        (
            "> **Logical-name convention.** Dataverse logical names are the "
            "SchemaName lowercased with NO underscores between words "
            "(`fsi_CopilotAgent` -> `fsi_copilotagent`, `fsi_AgentId` -> "
            "`fsi_agentid`). Always use logical names in OData `$select` / "
            "`$filter` / `$orderby`."
        ),
        "",
        "---",
        "",
        "## Option Sets",
        "",
        "### Shared Option Sets",
        "",
        "| Option Set | Values |",
        "|-----------|--------|",
    ]

    for os_name, os_def in SHARED_OPTIONSETS.items():
        values = ", ".join(
            f"{label} ({val})" for label, val in os_def["options"]
        )
        lines.append(f"| `{os_name}` | {values} |")

    lines.extend([
        "",
        "### CAI-Specific Option Sets",
        "",
        "| Option Set | Values |",
        "|-----------|--------|",
    ])

    for os_name, os_def in CAI_OPTIONSETS.items():
        values = ", ".join(
            f"{label} ({val})" for label, val in os_def["options"]
        )
        lines.append(f"| `{os_name}` | {values} |")

    lines.extend(["", "---", "", "## Tables", ""])

    for _, table_def in TABLES.items():
        logical = table_def["schema_name"].lower()
        lines.extend([
            f"### {table_def['display']} (`{logical}`)",
            "",
            f"**Ownership:** {table_def['ownership']}  ",
            f"**Entity set:** `{table_def.get('entity_set_name', logical + 's')}`  ",
            "**Primary name column:** `fsi_name`  ",
            f"**Description:** {table_def['description']}",
            "",
            "| Column (SchemaName) | Logical name | Type | Required | Description |",
            "|---------------------|--------------|------|----------|-------------|",
            "| `fsi_Name` | `fsi_name` | String(850) | Yes | Primary name attribute |",
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
                type_str = f"Picklist (`{os_name}`)"
            else:
                type_str = "Unknown"

            lines.append(
                f"| `{schema}` | `{logical_col}` | {type_str} | "
                f"{is_required} | {desc} |"
            )

        alt_keys = table_def.get("alt_keys", [])
        if alt_keys:
            lines.append("")
            for key_def in alt_keys:
                attrs = ", ".join(f"`{a}`" for a in key_def["key_attributes"])
                lines.append(
                    f"**Alternate key** `{key_def['schema_name']}`: "
                    f"({attrs}) — idempotent upsert key."
                )
        lines.append("")

    output_dir = os.path.dirname(output_path)
    if output_dir:
        os.makedirs(output_dir, exist_ok=True)
    with open(output_path, "w", encoding="utf-8") as handle:
        handle.write("\n".join(lines))
    logger.info("Documentation written to: %s", output_path)


# =============================================================================
# Deployment Functions
# =============================================================================


def create_optionsets(
    client: DataverseClient, optionsets: dict, label: str, dry_run: bool = False
) -> None:
    """Create or verify a group of global option sets (idempotent)."""
    logger.info("[%s]", label)
    for os_name, os_def in optionsets.items():
        if dry_run:
            existing = client.get_global_optionset(os_name)
            if existing:
                logger.info("  %s: exists, would skip", os_name)
            else:
                logger.info("  [DRY RUN] %s: would create", os_name)
            continue
        result = client.create_option_set(_build_optionset_metadata(os_def))
        if result is None:
            logger.info("  %s: already exists, skipping", os_name)
        else:
            logger.info("  %s: created", os_name)


def create_table_with_columns(
    client: DataverseClient,
    table_name: str,
    table_def: dict,
    dry_run: bool = False,
) -> None:
    """Create a table, its columns, and alternate keys (idempotent)."""
    logical_name = table_name.lower()

    table_exists = client.check_table_exists(logical_name)
    if table_exists:
        logger.info("  %s: already exists, skipping table creation", logical_name)
    elif dry_run:
        logger.info("  [DRY RUN] %s: would create table", logical_name)
    else:
        client.create_table(_build_table_metadata(table_def))
        logger.info("  %s: created", logical_name)

    logger.info("  %s columns:", logical_name)
    for col in table_def["columns"]:
        col_logical = col["SchemaName"].lower()
        if not table_exists and dry_run:
            logger.info("    [DRY RUN] %s: would create (new table)", col_logical)
            continue
        existing_col = client.get_attribute_metadata(logical_name, col_logical)
        if existing_col:
            logger.info("    %s: already exists, skipping", col_logical)
        elif dry_run:
            logger.info("    [DRY RUN] %s: would create", col_logical)
        else:
            client.create_column(logical_name, col)
            logger.info("    %s: created", col_logical)

    for key_def in table_def.get("alt_keys", []):
        key_schema = key_def["schema_name"]
        if not table_exists and dry_run:
            logger.info("    [DRY RUN] key %s: would create (new table)", key_schema)
            continue
        if dry_run:
            existing_key = client.get_entity_key(logical_name, key_schema.lower())
            if existing_key:
                logger.info("    key %s: exists, would skip", key_schema)
            else:
                logger.info("    [DRY RUN] key %s: would create", key_schema)
            continue
        result = client.ensure_entity_key(
            logical_name, _build_entity_key_metadata(key_def)
        )
        if result is None:
            logger.info("    key %s: already exists, skipping", key_schema)
        else:
            logger.info("    key %s: created (async system job)", key_schema)


def create_schema(client: DataverseClient, dry_run: bool = False) -> None:
    """Orchestrate full schema deployment (idempotent — safe to re-run).

    Order: shared option sets -> CAI option sets -> tables -> columns -> keys.
    """
    logger.info("=" * 60)
    logger.info("Copilot Agent Inventory - Dataverse Schema Deployment")
    logger.info("=" * 60)
    if dry_run:
        logger.info("*** DRY RUN - No changes will be made ***")

    create_optionsets(
        client, SHARED_OPTIONSETS, "Creating/Verifying Shared Option Sets", dry_run
    )
    create_optionsets(
        client, CAI_OPTIONSETS, "Creating CAI-Specific Option Sets", dry_run
    )

    logger.info("[Creating Tables, Columns, and Alternate Keys]")
    for table_name, table_def in TABLES.items():
        logger.info("  --- %s (%s) ---", table_def["display"], table_def["ownership"])
        create_table_with_columns(client, table_name, table_def, dry_run)

    logger.info("=" * 60)
    if dry_run:
        logger.info("DRY RUN COMPLETE - Review output above")
    else:
        logger.info("SCHEMA DEPLOYMENT COMPLETE")
    logger.info("  Shared option sets: %d", len(SHARED_OPTIONSETS))
    logger.info("  CAI option sets: %d", len(CAI_OPTIONSETS))
    logger.info("  Tables: %d", len(TABLES))
    logger.info("  Columns: %d", sum(len(t["columns"]) for t in TABLES.values()))
    logger.info("=" * 60)


# =============================================================================
# CLI Entry Point
# =============================================================================


def main() -> None:
    """CLI entry point for schema deployment."""
    parser = argparse.ArgumentParser(
        description="Create the Dataverse schema for Copilot Agent Inventory",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  # Generate schema documentation only\n"
            "  python create_cai_dataverse_schema.py --output-docs\n\n"
            "  # Dry run with interactive auth\n"
            "  python create_cai_dataverse_schema.py --dry-run --interactive \\\n"
            "    --environment-url https://org.crm.dynamics.com --tenant-id <tenant>\n\n"
            "  # Deploy with managed identity (Azure-hosted runner)\n"
            "  python create_cai_dataverse_schema.py --auth-mode managed-identity \\\n"
            "    --environment-url https://org.crm.dynamics.com --tenant-id <tenant>\n"
        ),
    )
    parser.add_argument(
        "--tenant-id",
        default=os.environ.get("CAI_TENANT_ID"),
        help="Microsoft Entra ID tenant ID (or set CAI_TENANT_ID env var)",
    )
    parser.add_argument(
        "--client-id",
        default=os.environ.get("CAI_CLIENT_ID"),
        help="App / service principal client ID (or set CAI_CLIENT_ID env var)",
    )
    parser.add_argument(
        "--client-secret",
        default=os.environ.get("CAI_CLIENT_SECRET"),
        help="Legacy dev-only client secret (or set CAI_CLIENT_SECRET env var)",
    )
    parser.add_argument(
        "--environment-url",
        default=os.environ.get("CAI_ENVIRONMENT_URL"),
        help="Governance Dataverse environment URL (or set CAI_ENVIRONMENT_URL)",
    )
    parser.add_argument(
        "--auth-mode",
        choices=[
            "interactive", "managed-identity", "workload-identity",
            "certificate", "client-secret",
        ],
        default=os.environ.get("CAI_AUTH_MODE"),
        help="Authentication mode; prefer managed-identity / workload-identity for automation",
    )
    parser.add_argument(
        "--interactive",
        action="store_true",
        help="Use interactive browser authentication (admin workstation runs)",
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
    parser.add_argument(
        "--log-level",
        default=os.environ.get("CAI_LOG_LEVEL", "INFO"),
        help="Logging level (DEBUG, INFO, WARNING, ERROR)",
    )
    args = parser.parse_args()

    logging.basicConfig(
        level=getattr(logging, str(args.log_level).upper(), logging.INFO),
        format="%(message)s",
    )

    # Handle --output-docs (no connection needed)
    if args.output_docs:
        script_dir = Path(__file__).resolve().parent
        docs_path = script_dir.parent / "docs" / "dataverse-schema.md"
        generate_docs(str(docs_path))
        logger.info("Documentation generation complete.")
        sys.exit(0)

    if not args.environment_url:
        parser.error("--environment-url or CAI_ENVIRONMENT_URL required")
    if not args.tenant_id:
        parser.error("--tenant-id or CAI_TENANT_ID required")

    auth_mode = (
        "interactive" if args.interactive
        else (args.auth_mode or ("client-secret" if args.client_secret else "managed-identity"))
    )

    try:
        # The shared client is constructed live for both --dry-run and live
        # runs: writes are gated locally in create_schema() so dry-run reads
        # still hit the tenant for an accurate preview.
        client = DataverseClient(
            tenant_id=args.tenant_id,
            environment_url=args.environment_url,
            client_id=args.client_id,
            client_secret=args.client_secret,
            interactive=args.interactive,
            auth_mode=auth_mode,
        )
        create_schema(client, dry_run=args.dry_run)
    except Exception as exc:  # surface a clean message, non-zero exit
        logger.error("Error: %s", exc)
        sys.exit(1)


if __name__ == "__main__":
    main()
