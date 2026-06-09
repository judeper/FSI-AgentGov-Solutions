# Copilot Agent Inventory - Dataverse Schema

Auto-generated schema documentation. Do not edit manually — regenerate with `python scripts/create_cai_dataverse_schema.py --output-docs`.

## Overview

The Copilot Agent Inventory solution uses **8 Dataverse tables**, **11 solution-specific option sets**, and **1 shared option set(s)**, with **96 custom columns** (plus the auto-created primary key and `fsi_Name` on each table). All entities use the `fsi_` publisher prefix.

> **Logical-name convention.** Dataverse logical names are the SchemaName lowercased with NO underscores between words (`fsi_CopilotAgent` -> `fsi_copilotagent`, `fsi_AgentId` -> `fsi_agentid`). Always use logical names in OData `$select` / `$filter` / `$orderby`.

---

## Option Sets

### Shared Option Sets

| Option Set | Values |
|-----------|--------|
| `fsi_acv_zone` | Unclassified (0), Zone 1 (1), Zone 2 (2), Zone 3 (3) |

### CAI-Specific Option Sets

| Option Set | Values |
|-----------|--------|
| `fsi_cai_createdin` | Copilot Studio (100000000), Microsoft 365 Copilot Agent Builder (100000001), Unknown (100000002) |
| `fsi_cai_agenttype` | Standard (100000000), Lite / Agent Builder (100000001), Declarative Agent (100000002), Classic V1 (excluded) (100000003), Unknown (100000004) |
| `fsi_cai_discoverysource` | Azure Resource Graph (100000000), Per-Environment Dataverse Scan (100000001), PPAC Reconciliation (100000002), Reconciled (multi-source) (100000003) |
| `fsi_cai_featuretype` | Topic (100000000), Skill (100000001), Knowledge Source (100000002), Custom GPT (100000003), Copilot Settings (100000004), External Trigger (100000005), File Attachment (100000006), Bot Variable (100000007), Bot Entity (100000008), Dialog (100000009), Dialog Schema (100000021), Trigger (100000010), Language Understanding (100000011), Language Generation (100000012), Bot Translations (100000013), Test Case (100000014), Tool / Plugin (100000015), Connector (100000016), Power Automate Flow (100000017), Environment Variable (100000018), Dataverse Search Grounding (100000019), AI Builder Model (100000020), Other / Unrecognized (100000099) |
| `fsi_cai_componentversion` | V1 (100000000), V2 (100000001), Not Applicable (100000002) |
| `fsi_cai_policytype` | PAYG Billing Policy (100000000), Prepaid Credit Policy (100000001), None (100000002), Unknown (100000003) |
| `fsi_cai_spendscope` | Chat (100000000), SharePoint (100000001), All Surfaces (100000002), Unknown (100000003) |
| `fsi_cai_workiqtier` | None (100000000), MCP in Copilot Studio (per-user license) (100000001), Direct Work IQ API (consumption) (100000002), Unknown (100000003) |
| `fsi_cai_workiqobserved` | Not Observed (100000000), Invoked (100000001), Configured, Not Invoked (100000002), Unknown (100000003) |
| `fsi_cai_risklevel` | Low (100000000), Medium (100000001), High (100000002), Critical (100000003), Unknown (100000004) |
| `fsi_cai_scancompleteness` | Complete (100000000), Incomplete Scan (100000001), Failed (100000002) |

---

## Tables

### Copilot Agent (`fsi_copilotagent`)

**Ownership:** OrganizationOwned  
**Entity set:** `fsi_copilotagents`  
**Primary name column:** `fsi_name`  
**Description:** Canonical agent master record (system-of-record) for Copilot Studio and Agent Builder agents discovered across the tenant

| Column (SchemaName) | Logical name | Type | Required | Description |
|---------------------|--------------|------|----------|-------------|
| `fsi_Name` | `fsi_name` | String(850) | Yes | Primary name attribute |
| `fsi_AgentId` | `fsi_agentid` | String(100) | Yes | Copilot Studio bot GUID (ARG 'name' / Dataverse botid) |
| `fsi_AgentName` | `fsi_agentname` | String(500) | Yes | Agent display name (ARG properties.displayName) |
| `fsi_EnvironmentId` | `fsi_environmentid` | String(100) | Yes | Power Platform environment GUID this agent lives in |
| `fsi_SchemaName` | `fsi_schemaname` | String(200) | No | Dataverse schemaName of the agent |
| `fsi_OwnerUpn` | `fsi_ownerupn` | String(200) | No | Agent owner user principal name |
| `fsi_OwnerId` | `fsi_ownerid` | String(100) | No | Agent owner Microsoft Entra ID object GUID |
| `fsi_CreatedIn` | `fsi_createdin` | Picklist (`fsi_cai_createdin`) | No | Authoring surface; the zero-rating entitlement classifier keys on this |
| `fsi_AgentType` | `fsi_agenttype` | Picklist (`fsi_cai_agenttype`) | No | Standard / Lite-Agent-Builder / Declarative; drives scan completeness |
| `fsi_PublishedState` | `fsi_publishedstate` | String(100) | No | Publish/state status derived from statecode + lastPublishedAt |
| `fsi_AuthMode` | `fsi_authmode` | String(100) | No | bot.authenticationmode (No-auth / Microsoft / manual) |
| `fsi_BotId` | `fsi_botid` | String(100) | No | Identity botId from ARG |
| `fsi_EntraAppId` | `fsi_entraappid` | String(100) | No | Microsoft Entra ID application (client) ID bound to the agent |
| `fsi_EntraAgentId` | `fsi_entraagentid` | String(100) | No | Microsoft Entra Agent ID (preview field) |
| `fsi_IsManaged` | `fsi_ismanaged` | Boolean (default: false) | No | Managed flag (preview; null for Agent Builder agents) |
| `fsi_Region` | `fsi_region` | String(100) | No | Environment region / location |
| `fsi_DiscoverySource` | `fsi_discoverysource` | Picklist (`fsi_cai_discoverysource`) | No | Which discovery layer last wrote this row |
| `fsi_CreatedOn` | `fsi_createdon` | DateTime | No | Agent creation timestamp (ARG createdAt) |
| `fsi_ModifiedOn` | `fsi_modifiedon` | DateTime | No | Agent last-modified timestamp |
| `fsi_LastPublishedAt` | `fsi_lastpublishedat` | DateTime | No | Last publish timestamp (ARG lastPublishedAt) |
| `fsi_LastScannedAt` | `fsi_lastscannedat` | DateTime | Yes | When this inventory row was last refreshed |
| `fsi_RunId` | `fsi_runid` | String(36) | No | GUID correlating all records from one scan run |
| `fsi_RawJson` | `fsi_rawjson` | Memo(100000) | No | Full ARG / bot JSON snapshot for evidence and reparse |

**Alternate key** `fsi_AgentEnvKey`: (`fsi_agentid`, `fsi_environmentid`) — idempotent upsert key.

### CAI Environment (`fsi_caienvironment`)

**Ownership:** OrganizationOwned  
**Entity set:** `fsi_caienvironments`  
**Primary name column:** `fsi_name`  
**Description:** Power Platform environment inventory with zone classification and per-environment delta-change-tracking watermark

| Column (SchemaName) | Logical name | Type | Required | Description |
|---------------------|--------------|------|----------|-------------|
| `fsi_Name` | `fsi_name` | String(850) | Yes | Primary name attribute |
| `fsi_EnvironmentId` | `fsi_environmentid` | String(100) | Yes | Power Platform environment GUID |
| `fsi_EnvironmentName` | `fsi_environmentname` | String(500) | Yes | Environment display name |
| `fsi_EnvironmentUrl` | `fsi_environmenturl` | String(400) | No | Source-environment Dataverse Web API base URL; the Work IQ solution joins this to resolve per-env URLs |
| `fsi_Region` | `fsi_region` | String(100) | No | Environment region / location |
| `fsi_EnvironmentType` | `fsi_environmenttype` | String(100) | No | Production / Sandbox / Trial / Default / Developer |
| `fsi_IsManaged` | `fsi_ismanaged` | Boolean (default: false) | No | Whether this is a Managed Environment |
| `fsi_Zone` | `fsi_zone` | Picklist (`fsi_acv_zone`) | No | Governance zone classification |
| `fsi_AgentCount` | `fsi_agentcount` | Integer | No | Number of agents discovered in this environment |
| `fsi_DeltaLink` | `fsi_deltalink` | Memo(100000) | No | Dataverse @odata.deltaLink for incremental change tracking |
| `fsi_LastScannedAt` | `fsi_lastscannedat` | DateTime | Yes | When this environment was last scanned |
| `fsi_RunId` | `fsi_runid` | String(36) | No | Correlating scan run GUID |

**Alternate key** `fsi_EnvKey`: (`fsi_environmentid`) — idempotent upsert key.

### CAI Agent Feature (`fsi_caiagentfeature`)

**Ownership:** OrganizationOwned  
**Entity set:** `fsi_caiagentfeatures`  
**Primary name column:** `fsi_name`  
**Description:** Capability-composition layer: one row per detected feature (botcomponent or many-to-many relationship target) per agent

| Column (SchemaName) | Logical name | Type | Required | Description |
|---------------------|--------------|------|----------|-------------|
| `fsi_Name` | `fsi_name` | String(850) | Yes | Primary name attribute |
| `fsi_AgentId` | `fsi_agentid` | String(100) | Yes | Parent agent bot GUID |
| `fsi_EnvironmentId` | `fsi_environmentid` | String(100) | No | Environment GUID the feature was detected in |
| `fsi_FeatureType` | `fsi_featuretype` | Picklist (`fsi_cai_featuretype`) | Yes | Feature class (botcomponent type or M:M relationship target) |
| `fsi_ComponentType` | `fsi_componenttype` | Integer | No | Raw botcomponent_componenttype code (0-19), if applicable |
| `fsi_ComponentVersion` | `fsi_componentversion` | Picklist (`fsi_cai_componentversion`) | No | V1 / V2 pairing of the source component |
| `fsi_SourceObjectId` | `fsi_sourceobjectid` | String(100) | Yes | botcomponentid or many-to-many target record GUID |
| `fsi_SourceObjectName` | `fsi_sourceobjectname` | String(500) | No | Display name of the source component / target |
| `fsi_IsEnabled` | `fsi_isenabled` | Boolean (default: true) | No | Whether the feature is enabled on the agent |
| `fsi_RelationshipName` | `fsi_relationshipname` | String(200) | No | botcomponent navigation property the feature was matched through |
| `fsi_LastScannedAt` | `fsi_lastscannedat` | DateTime | Yes | When this feature row was last refreshed |
| `fsi_RunId` | `fsi_runid` | String(36) | No | Correlating scan run GUID |

**Alternate key** `fsi_AgentFeatureKey`: (`fsi_agentid`, `fsi_sourceobjectid`) — idempotent upsert key.

### CAI Auth Share (`fsi_caiauthshare`)

**Ownership:** OrganizationOwned  
**Entity set:** `fsi_caiauthshares`  
**Primary name column:** `fsi_name`  
**Description:** Per-agent authentication and sharing posture, including the Entra-ID-auth + Require-sign-in audience-control predicate

| Column (SchemaName) | Logical name | Type | Required | Description |
|---------------------|--------------|------|----------|-------------|
| `fsi_Name` | `fsi_name` | String(850) | Yes | Primary name attribute |
| `fsi_AgentId` | `fsi_agentid` | String(100) | Yes | Agent bot GUID |
| `fsi_EnvironmentId` | `fsi_environmentid` | String(100) | No | Environment GUID |
| `fsi_AuthMode` | `fsi_authmode` | String(100) | No | No auth / Authenticate with Microsoft / Authenticate manually |
| `fsi_AuthProvider` | `fsi_authprovider` | String(200) | No | Identity provider (e.g., Microsoft Entra ID, Generic OAuth2) |
| `fsi_RequireSignIn` | `fsi_requiresignin` | Boolean (default: false) | No | Whether 'Require users to sign in' is ON |
| `fsi_EntraAuthAsserted` | `fsi_entraauthasserted` | Boolean (default: false) | No | Derived: Entra-ID auth AND Require-sign-in ON (audience-control predicate) |
| `fsi_ViewerGroups` | `fsi_viewergroups` | Memo(10000) | No | Security groups granted chat viewer access (JSON) |
| `fsi_EditorPrincipals` | `fsi_editorprincipals` | Memo(10000) | No | Individual principals granted editor access (JSON) |
| `fsi_SharedWithViewerCount` | `fsi_sharedwithviewercount` | Integer | No | Count of viewer principals/groups |
| `fsi_SharedWithEditorCount` | `fsi_sharedwitheditorcount` | Integer | No | Count of editor principals |
| `fsi_LimitSharingMode` | `fsi_limitsharingmode` | String(100) | No | Managed-environment bot-limitSharingMode value |
| `fsi_LastScannedAt` | `fsi_lastscannedat` | DateTime | Yes | When this posture was last scanned |
| `fsi_RunId` | `fsi_runid` | String(36) | No | Correlating scan run GUID |

**Alternate key** `fsi_AuthShareKey`: (`fsi_agentid`, `fsi_environmentid`) — idempotent upsert key.

### CAI Billing Entitlement (`fsi_caibillingentitlement`)

**Ownership:** OrganizationOwned  
**Entity set:** `fsi_caibillingentitlements`  
**Primary name column:** `fsi_name`  
**Description:** Billing / credit entitlement shell (populated downstream by the billing-governance solution); zero-rating defaults fail-closed

| Column (SchemaName) | Logical name | Type | Required | Description |
|---------------------|--------------|------|----------|-------------|
| `fsi_Name` | `fsi_name` | String(850) | Yes | Primary name attribute |
| `fsi_AgentId` | `fsi_agentid` | String(100) | No | Agent bot GUID (null for tenant-level policy rows) |
| `fsi_PolicyId` | `fsi_policyid` | String(200) | No | Billing or credit policy identifier |
| `fsi_PolicyType` | `fsi_policytype` | Picklist (`fsi_cai_policytype`) | No | PAYG / Prepaid credit policy / None |
| `fsi_UserScopeGroupId` | `fsi_userscopegroupid` | String(100) | No | Microsoft Entra ID group GUID scoping the policy |
| `fsi_SpendScope` | `fsi_spendscope` | Picklist (`fsi_cai_spendscope`) | No | Surface the policy allocation applies to (credit policy is Chat-only today) |
| `fsi_BudgetState` | `fsi_budgetstate` | String(100) | No | Active / Exhausted / Alerting |
| `fsi_ZeroRatingEligible` | `fsi_zeroratingeligible` | Boolean (default: false) | No | Fail-closed default False pending the June 2026 Licensing Guide; CS-built generative answers and tenant-grounded responses remain billable |
| `fsi_EntitlementBasis` | `fsi_entitlementbasis` | String(1000) | No | Note on the license + createdIn basis for the entitlement decision |
| `fsi_LastEvaluatedAt` | `fsi_lastevaluatedat` | DateTime | No | When the entitlement was last evaluated |
| `fsi_RunId` | `fsi_runid` | String(36) | No | Correlating scan run GUID |

### CAI Usage Signal (`fsi_caiusagesignal`)

**Ownership:** OrganizationOwned  
**Entity set:** `fsi_caiusagesignals`  
**Primary name column:** `fsi_name`  
**Description:** Source-aggregated per-agent usage rollup (30-day interactions, unique users, sessions); never stores transcript rows

| Column (SchemaName) | Logical name | Type | Required | Description |
|---------------------|--------------|------|----------|-------------|
| `fsi_Name` | `fsi_name` | String(850) | Yes | Primary name attribute |
| `fsi_AgentId` | `fsi_agentid` | String(100) | Yes | Agent bot GUID |
| `fsi_EnvironmentId` | `fsi_environmentid` | String(100) | No | Environment GUID |
| `fsi_LastInteractionUtc` | `fsi_lastinteractionutc` | DateTime | No | Most recent interaction timestamp |
| `fsi_Interactions30d` | `fsi_interactions30d` | Integer | No | Interaction count over the rolling 30-day window |
| `fsi_UniqueUsers30d` | `fsi_uniqueusers30d` | Integer | No | Distinct users over the rolling 30-day window |
| `fsi_Sessions30d` | `fsi_sessions30d` | Integer | No | Session count over the rolling 30-day window |
| `fsi_AggregationWindowDays` | `fsi_aggregationwindowdays` | Integer | No | Rollup window length in days (default 30) |
| `fsi_SignalSource` | `fsi_signalsource` | String(200) | No | Source of the aggregate (e.g., msdyn_botsession, App Insights) |
| `fsi_LastAggregatedAt` | `fsi_lastaggregatedat` | DateTime | Yes | When the usage rollup was last computed |
| `fsi_RunId` | `fsi_runid` | String(36) | No | Correlating scan run GUID |

**Alternate key** `fsi_UsageSignalKey`: (`fsi_agentid`, `fsi_environmentid`) — idempotent upsert key.

### CAI Work IQ State (`fsi_caiworkiqstate`)

**Ownership:** OrganizationOwned  
**Entity set:** `fsi_caiworkiqstates`  
**Primary name column:** `fsi_name`  
**Description:** Work IQ config-vs-invoked state shell (populated downstream by work-iq-usage-detection); emits configuredTier

| Column (SchemaName) | Logical name | Type | Required | Description |
|---------------------|--------------|------|----------|-------------|
| `fsi_Name` | `fsi_name` | String(850) | Yes | Primary name attribute |
| `fsi_AgentId` | `fsi_agentid` | String(100) | Yes | Agent bot GUID |
| `fsi_EnvironmentId` | `fsi_environmentid` | String(100) | No | Environment GUID |
| `fsi_Configured` | `fsi_configured` | Boolean (default: false) | No | Whether Work IQ / semantic search is configured |
| `fsi_ConfiguredTier` | `fsi_configuredtier` | Picklist (`fsi_cai_workiqtier`) | No | Entitlement split: MCP-in-Copilot-Studio vs Direct Work IQ API |
| `fsi_ObservedStatus` | `fsi_observedstatus` | Picklist (`fsi_cai_workiqobserved`) | No | Config-vs-invoked classifier result |
| `fsi_PerUserLicenseRequired` | `fsi_peruserlicenserequired` | Boolean (default: false) | No | MCP-in-Copilot-Studio path requires a per-user M365 Copilot license |
| `fsi_ConfigSourceComponentType` | `fsi_configsourcecomponenttype` | Integer | No | botcomponent type where config was resolved (18/15/16) — sample to confirm |
| `fsi_LastObservedUtc` | `fsi_lastobservedutc` | DateTime | No | Most recent observed (invoked) signal timestamp |
| `fsi_LastScannedAt` | `fsi_lastscannedat` | DateTime | Yes | When this state row was last refreshed |
| `fsi_RunId` | `fsi_runid` | String(36) | No | Correlating scan run GUID |

**Alternate key** `fsi_WorkIqStateKey`: (`fsi_agentid`, `fsi_environmentid`) — idempotent upsert key.

### CAI Compliance State (`fsi_caicompliancestate`)

**Ownership:** OrganizationOwned  
**Entity set:** `fsi_caicompliancestates`  
**Primary name column:** `fsi_name`  
**Description:** Per-agent risk level, scan completeness (incomplete-scan marker for Lite/Agent-Builder), and violations rollup

| Column (SchemaName) | Logical name | Type | Required | Description |
|---------------------|--------------|------|----------|-------------|
| `fsi_Name` | `fsi_name` | String(850) | Yes | Primary name attribute |
| `fsi_AgentId` | `fsi_agentid` | String(100) | Yes | Agent bot GUID |
| `fsi_EnvironmentId` | `fsi_environmentid` | String(100) | No | Environment GUID |
| `fsi_RiskLevel` | `fsi_risklevel` | Picklist (`fsi_cai_risklevel`) | No | Aggregated risk level for the agent |
| `fsi_ScanCompleteness` | `fsi_scancompleteness` | Picklist (`fsi_cai_scancompleteness`) | Yes | Complete / Incomplete Scan (Lite/Agent-Builder) / Failed |
| `fsi_ScanCompletenessReason` | `fsi_scancompletenessreason` | String(1000) | No | Why a scan is incomplete (e.g., no public API returns full Agent Builder definition) |
| `fsi_ViolationCount` | `fsi_violationcount` | Integer | No | Number of open violations rolled up for the agent |
| `fsi_ViolationsJson` | `fsi_violationsjson` | Memo(100000) | No | Structured violations[] rollup for the agent |
| `fsi_LastCheckedUtc` | `fsi_lastcheckedutc` | DateTime | Yes | When compliance state was last evaluated |
| `fsi_RunId` | `fsi_runid` | String(36) | No | Correlating scan run GUID |

**Alternate key** `fsi_ComplianceStateKey`: (`fsi_agentid`, `fsi_environmentid`) — idempotent upsert key.
