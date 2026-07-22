# Copilot Agent Inventory - Dataverse Schema

Auto-generated schema documentation. Do not edit manually — regenerate with `python scripts/create_cai_dataverse_schema.py --output-docs`.

## Overview

The Copilot Agent Inventory solution uses **9 Dataverse tables**, **22 solution-specific option sets**, and **1 shared option set(s)**, with **167 custom columns** (plus the auto-created primary key and `fsi_Name` on each table). All entities use the `fsi_` publisher prefix.

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
| `fsi_cai_agenttype` | Standard (100000000), Lite / Agent Builder (100000001), Declarative Agent (100000002), Custom Engine Agent (100000005), Classic V1 (excluded) (100000003), Unknown (100000004) |
| `fsi_cai_discoverysource` | Azure Resource Graph (100000000), Per-Environment Dataverse Scan (100000001), PPAC Reconciliation (100000002), Reconciled (multi-source) (100000003), Package Management API (100000004) |
| `fsi_cai_featuretype` | Topic (100000000), Skill (100000001), Knowledge Source (100000002), Custom GPT (100000003), Copilot Settings (100000004), External Trigger (100000005), File Attachment (100000006), Bot Variable (100000007), Bot Entity (100000008), Dialog (100000009), Dialog Schema (100000021), Trigger (100000010), Language Understanding (100000011), Language Generation (100000012), Bot Translations (100000013), Test Case (100000014), Tool / Plugin (100000015), Connector (100000016), Power Automate Flow (100000017), Environment Variable (100000018), Dataverse Search Grounding (100000019), AI Builder Model (100000020), People (Org Chart & Profile) (100000022), Other / Unrecognized (100000099) |
| `fsi_cai_componentversion` | V1 (100000000), V2 (100000001), Not Applicable (100000002) |
| `fsi_cai_policytype` | PAYG Billing Policy (100000000), Prepaid Credit Policy (100000001), None (100000002), Unknown (100000003) |
| `fsi_cai_spendscope` | Chat (100000000), SharePoint (100000001), All Surfaces (100000002), Unknown (100000003) |
| `fsi_cai_workiqtier` | None (100000000), MCP in Copilot Studio (per-user license) (100000001), Direct Work IQ API (consumption) (100000002), Unknown (100000003) |
| `fsi_cai_workiqobserved` | Not Observed (100000000), Invoked (100000001), Configured, Not Invoked (100000002), Unknown (100000003) |
| `fsi_cai_risklevel` | Low (100000000), Medium (100000001), High (100000002), Critical (100000003), Unknown (100000004) |
| `fsi_cai_scancompleteness` | Complete (100000000), Incomplete Scan (100000001), Failed (100000002) |
| `fsi_cai_scanrunstatus` | Complete (100000000), Incomplete (100000001), Failed (100000002), Dry Run (100000003) |
| `fsi_cai_agent365requestedmode` | Present (100000000), Absent (100000001), Auto (100000002) |
| `fsi_cai_agent365resolvedstate` | Present (100000000), Absent (100000001), NotDetected (100000002), Inconclusive (100000003) |
| `fsi_cai_agent365detectionconfidence` | OperatorDeclared (100000000), Confirmed (100000001), Heuristic (100000002), Inconclusive (100000003), NotApplicable (100000004) |
| `fsi_cai_layerstatus` | Full (100000000), Deferred (100000001), Unsupported (100000002), Partial (100000003), Failed (100000004), Dry Run (100000005) |
| `fsi_cai_detectionsource` | Dataverse Botcomponent Scan (100000000), Declarative Manifest (Local App Package) (100000001), Declarative Manifest (Source/CI Repo) (100000002), Declarative Manifest (Export Adapter - Future) (100000003), Unknown (100000099) |
| `fsi_cai_detectionconfidence` | Declared (Manifest) (100000000), Configured (Dataverse) (100000001), Inferred (100000002), Unknown (100000099) |
| `fsi_cai_ownerentitlement` | Paid Copilot (100000000), Copilot Chat Only (100000001), Unknown (100000002) |
| `fsi_cai_ownersource` | Dataverse Owner (100000000), Agent Registry Export (100000001), Unresolved (100000002) |
| `fsi_cai_ownermatchconfidence` | Exact (100000000), Heuristic (100000001), Unmatched (100000002) |
| `fsi_cai_packagestatus` | None (100000000), Some (100000001), All (100000002) |

---

## Tables

### Copilot Agent (`fsi_copilotagent`)

**Ownership:** OrganizationOwned<br>
**Entity set:** `fsi_copilotagents`<br>
**Primary name column:** `fsi_name`<br>
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
| `fsi_PackageId` | `fsi_packageid` | String(100) | No | Package Management API package id (P_...). DISTINCT id space from the Copilot Studio bot GUID; used as the stable key for package-sourced rows and reconciliation via fsi_entraappid |
| `fsi_Publisher` | `fsi_publisher` | String(200) | No | Package vendor/publisher from the Package Management API (not the agent creator or owner) |
| `fsi_SupportedHosts` | `fsi_supportedhosts` | Memo(4000) | No | JSON array of supported host surface identifiers from the Package Management API (supportedHosts[]) |
| `fsi_AvailableTo` | `fsi_availableto` | Picklist (`fsi_cai_packagestatus`) | No | Package availableTo scope from the Package Management API (None / Some / All) |
| `fsi_DeployedTo` | `fsi_deployedto` | Picklist (`fsi_cai_packagestatus`) | No | Package deployedTo scope from the Package Management API (None / Some / All) |
| `fsi_ManifestId` | `fsi_manifestid` | String(200) | No | Declarative-agent manifest identifier from the Package Management API |
| `fsi_ManifestVersion` | `fsi_manifestversion` | String(50) | No | Declarative-agent manifest version string from the Package Management API |
| `fsi_PackageType` | `fsi_packagetype` | String(100) | No | Package Management API copilotPackage.type for this agent (microsoft / external / shared / custom) |
| `fsi_ElementTypes` | `fsi_elementtypes` | Memo(2000) | No | JSON array of copilotPackage.elementTypes reported by the Package Management API (e.g. Bots, DeclarativeAgent, CustomEngineAgent). Used to derive fsi_agenttype |
| `fsi_IsBlocked` | `fsi_isblocked` | Boolean (default: false) | No | Records copilotPackage.isBlocked from the Package Management API; true indicates the package has been blocked from deployment in this tenant |
| `fsi_PackageVersion` | `fsi_packageversion` | String(50) | No | Package Management API copilotPackage.version string. Distinct from fsi_manifestversion (declarative-agent manifest version); this is the package-catalog version label |
| `fsi_AssetId` | `fsi_assetid` | String(100) | No | Package Management API copilotPackage.assetId; cross-references the package asset in the Microsoft catalog |
| `fsi_OwnerEntitlement` | `fsi_ownerentitlement` | Picklist (`fsi_cai_ownerentitlement`) | No | Owner Copilot license class for BI reporting (Paid Copilot / Copilot Chat Only / Unknown). Populated by resolve_owner_entitlement.py; Unknown on any lookup failure or unresolved owner |
| `fsi_OwnerEntitlementEvidence` | `fsi_ownerentitlementevidence` | Memo(4000) | No | Matched service-plan GUIDs and SKU evidence that drove the fsi_ownerentitlement classification. Contains NO PII or UPN values |
| `fsi_OwnerSource` | `fsi_ownersource` | Picklist (`fsi_cai_ownersource`) | No | Provenance of the owner identity: Dataverse Owner, Agent Registry Export (temporary bridge — treat as potentially stale; check fsi_ownerasofdatetime), or Unresolved |
| `fsi_OwnerMatchConfidence` | `fsi_ownermatchconfidence` | Picklist (`fsi_cai_ownermatchconfidence`) | No | Confidence of the owner match: Exact (stable Entra object ID), Heuristic (display name or UPN fuzzy logic), or Unmatched |
| `fsi_OwnerAsOfDateTime` | `fsi_ownerasofdatetime` | DateTime | No | Timestamp of the registry export the owner data was drawn from; staleness signal when fsi_ownersource = Agent Registry Export |

**Alternate key** `fsi_AgentEnvKey`: (`fsi_agentid`, `fsi_environmentid`) — idempotent upsert key.
**Alternate key** `fsi_PackageKey`: (`fsi_packageid`) — idempotent upsert key.

### CAI Environment (`fsi_caienvironment`)

**Ownership:** OrganizationOwned<br>
**Entity set:** `fsi_caienvironments`<br>
**Primary name column:** `fsi_name`<br>
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

**Ownership:** OrganizationOwned<br>
**Entity set:** `fsi_caiagentfeatures`<br>
**Primary name column:** `fsi_name`<br>
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
| `fsi_DetectionSource` | `fsi_detectionsource` | Picklist (`fsi_cai_detectionsource`) | No | Acquisition source that produced this row (Dataverse botcomponent scan or a declarative-manifest adapter) |
| `fsi_DetectionConfidence` | `fsi_detectionconfidence` | Picklist (`fsi_cai_detectionconfidence`) | No | Declared (manifest) vs Configured (Dataverse); declared capabilities may be removed by the user at runtime (v1.7 user_overrides) |
| `fsi_DetectionDetail` | `fsi_detectiondetail` | Memo(4000) | No | JSON provenance for manifest-derived rows: source locator, manifest schema version, and capability sub-settings such as the v1.7 People include_related_content flag |
| `fsi_AgentRefProvisional` | `fsi_agentrefprovisional` | Boolean (default: false) | No | The fsi_agentid is a PROVISIONAL manifest/app id not yet bound to a Dataverse bot GUID (no --id-map match during manifest detection). Downstream joins (Copilot Billing Governance) must reconcile provisional rows before use; queryable so provisional rows can be filtered |
| `fsi_LastScannedAt` | `fsi_lastscannedat` | DateTime | Yes | When this feature row was last refreshed |
| `fsi_RunId` | `fsi_runid` | String(36) | No | Correlating scan run GUID |

**Alternate key** `fsi_AgentFeatureKey`: (`fsi_agentid`, `fsi_sourceobjectid`) — idempotent upsert key.

### CAI Auth Share (`fsi_caiauthshare`)

**Ownership:** OrganizationOwned<br>
**Entity set:** `fsi_caiauthshares`<br>
**Primary name column:** `fsi_name`<br>
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
| `fsi_SharedWithEveryone` | `fsi_sharedwitheveryone` | Boolean (default: false) | No | Per-agent org-wide reach: the agent is shared with 'Everyone in the organization' (derived from the bot accesscontrolpolicy Any / Any-multi-tenant signal during discovery). This is a PER-AGENT posture signal and is NOT the environment-wide bot-limitSharingMode policy; it drives whole-tenant audience handling in expand_audience_upns.py |
| `fsi_AudienceWholeTenant` | `fsi_audiencewholetenant` | Boolean (default: false) | No | 'Everyone in the organization' sharing detected; members are deliberately NOT enumerated (whole-tenant flag) |
| `fsi_AudienceUpnCount` | `fsi_audienceupncount` | Integer | No | Distinct member UPNs resolved by Microsoft Graph transitive group expansion (0 when whole-tenant and not enumerated) |
| `fsi_AudienceTruncated` | `fsi_audiencetruncated` | Boolean (default: false) | No | At least one group exceeded the per-group member cap; the resolved UPN list is partial |
| `fsi_AudienceResolutionStatus` | `fsi_audienceresolutionstatus` | String(100) | No | Complete / Partial / WholeTenantNotEnumerated / Failed / NotResolved — outcome of the UPN expansion |
| `fsi_AudienceResolvedAt` | `fsi_audienceresolvedat` | DateTime | No | When the audience-to-UPN expansion last ran for this agent |
| `fsi_LastScannedAt` | `fsi_lastscannedat` | DateTime | Yes | When this posture was last scanned |
| `fsi_RunId` | `fsi_runid` | String(36) | No | Correlating scan run GUID |

**Alternate key** `fsi_AuthShareKey`: (`fsi_agentid`, `fsi_environmentid`) — idempotent upsert key.

### CAI Billing Entitlement (`fsi_caibillingentitlement`)

**Ownership:** OrganizationOwned<br>
**Entity set:** `fsi_caibillingentitlements`<br>
**Primary name column:** `fsi_name`<br>
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

**Ownership:** OrganizationOwned<br>
**Entity set:** `fsi_caiusagesignals`<br>
**Primary name column:** `fsi_name`<br>
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

**Ownership:** OrganizationOwned<br>
**Entity set:** `fsi_caiworkiqstates`<br>
**Primary name column:** `fsi_name`<br>
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

**Ownership:** OrganizationOwned<br>
**Entity set:** `fsi_caicompliancestates`<br>
**Primary name column:** `fsi_name`<br>
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

### CAI Scan Run (`fsi_caiscanrun`)

**Ownership:** OrganizationOwned<br>
**Entity set:** `fsi_caiscanruns`<br>
**Primary name column:** `fsi_name`<br>
**Description:** Run-level BI evidence row with layer statuses, counts, and provenance summaries for each discovery execution

| Column (SchemaName) | Logical name | Type | Required | Description |
|---------------------|--------------|------|----------|-------------|
| `fsi_Name` | `fsi_name` | String(850) | Yes | Primary name attribute |
| `fsi_RunId` | `fsi_runid` | String(100) | Yes | Stable run identifier (GUID/UUIDv7/ULID-compatible) |
| `fsi_StartedAt` | `fsi_startedat` | DateTime | Yes | UTC timestamp when the scan run started |
| `fsi_CompletedAt` | `fsi_completedat` | DateTime | No | UTC timestamp when the scan run completed |
| `fsi_Status` | `fsi_status` | Picklist (`fsi_cai_scanrunstatus`) | Yes | Run outcome: Complete / Incomplete / Failed / Dry Run |
| `fsi_EnvironmentEnumerationStatus` | `fsi_environmentenumerationstatus` | Picklist (`fsi_cai_layerstatus`) | No | Status of environment enumeration for this run |
| `fsi_DataverseLayerStatus` | `fsi_dataverselayerstatus` | Picklist (`fsi_cai_layerstatus`) | No | Execution status of per-environment Dataverse scans |
| `fsi_EnvironmentFailureCount` | `fsi_environmentfailurecount` | Integer | No | Count of per-environment scans that failed |
| `fsi_EnvironmentEnumerationHttpStatus` | `fsi_environmentenumerationhttpstatus` | Integer | No | HTTP status returned by environment enumeration, when available |
| `fsi_EnvironmentEnumerationReason` | `fsi_environmentenumerationreason` | Memo(4000) | No | Sanitized reason for environment enumeration failure or partial status |
| `fsi_Agent365RequestedMode` | `fsi_agent365requestedmode` | Picklist (`fsi_cai_agent365requestedmode`) | No | Requested Agent 365 mode for this run |
| `fsi_Agent365ResolvedState` | `fsi_agent365resolvedstate` | Picklist (`fsi_cai_agent365resolvedstate`) | No | Resolved Agent 365 state observed during execution |
| `fsi_Agent365ResolutionSource` | `fsi_agent365resolutionsource` | String(200) | No | Resolver source that produced the Agent 365 state |
| `fsi_Agent365DetectionConfidence` | `fsi_agent365detectionconfidence` | Picklist (`fsi_cai_agent365detectionconfidence`) | No | Confidence assigned to Agent 365 state detection |
| `fsi_Agent365LayerStatus` | `fsi_agent365layerstatus` | Picklist (`fsi_cai_layerstatus`) | No | Execution status of the Agent 365 detection layer |
| `fsi_ArgLayerStatus` | `fsi_arglayerstatus` | Picklist (`fsi_cai_layerstatus`) | No | Execution status of the Azure Resource Graph layer |
| `fsi_ArgAgentCount` | `fsi_argagentcount` | Integer | No | Count of agents returned by Azure Resource Graph |
| `fsi_ArgHttpStatus` | `fsi_arghttpstatus` | Integer | No | HTTP status returned by the Azure Resource Graph query |
| `fsi_CoreAgentCount` | `fsi_coreagentcount` | Integer | No | Total agent rows emitted to the canonical agent table |
| `fsi_DataverseScannedAgentCount` | `fsi_dataversescannedagentcount` | Integer | No | Count of agents observed via per-environment Dataverse scans |
| `fsi_FeatureCount` | `fsi_featurecount` | Integer | No | Count of feature rows emitted in this run |
| `fsi_AuthShareCount` | `fsi_authsharecount` | Integer | No | Count of auth/share posture rows emitted in this run |
| `fsi_EnvironmentCount` | `fsi_environmentcount` | Integer | No | Count of environments enumerated for this run |
| `fsi_LicenseProbeAttempted` | `fsi_licenseprobeattempted` | Boolean (default: false) | No | Whether the tenant Agent 365 /subscribedSkus probe was attempted |
| `fsi_PackageApiLayerStatus` | `fsi_packageapilayerstatus` | Picklist (`fsi_cai_layerstatus`) | No | Execution status of the Package Management API layer |
| `fsi_PackageApiAttempted` | `fsi_packageapiattempted` | Boolean (default: false) | No | Whether Package Management API discovery was attempted |
| `fsi_PackageApiHttpStatus` | `fsi_packageapihttpstatus` | Integer | No | HTTP status returned by the Package Management API |
| `fsi_PackageApiErrorCode` | `fsi_packageapierrorcode` | String(200) | No | Sanitized Package API error code |
| `fsi_PackageApiReason` | `fsi_packageapireason` | Memo(4000) | No | Sanitized reason text for Package API partial/failed status |
| `fsi_PackageCount` | `fsi_packagecount` | Integer | No | Count of packages returned by Package Management API (nullable when deferred) |
| `fsi_PackageNewRowCount` | `fsi_packagenewrowcount` | Integer | No | Count of package-sourced net-new agent rows |
| `fsi_PackageScanTruncated` | `fsi_packagescantruncated` | Boolean (default: false) | No | Whether package pagination truncated before full completion |
| `fsi_RegistryLayerStatus` | `fsi_registrylayerstatus` | Picklist (`fsi_cai_layerstatus`) | No | Execution status of registry-correlation enrichment |
| `fsi_RegistryRowCount` | `fsi_registryrowcount` | Integer | No | Count of registry rows provided to correlation |
| `fsi_RegistryMatchedCount` | `fsi_registrymatchedcount` | Integer | No | Count of registry rows matched to discovered agents |
| `fsi_RegistryUnmatchedCount` | `fsi_registryunmatchedcount` | Integer | No | Count of registry rows that could not be matched |
| `fsi_RegistryAmbiguousNameSkippedCount` | `fsi_registryambiguousnameskippedcount` | Integer | No | Count of name-collision candidates intentionally skipped |
| `fsi_RegistryInvalidDateWarningCount` | `fsi_registryinvaliddatewarningcount` | Integer | No | Count of invalid-date warnings from registry import |
| `fsi_EntitlementLayerStatus` | `fsi_entitlementlayerstatus` | Picklist (`fsi_cai_layerstatus`) | No | Execution status of owner-entitlement resolution |
| `fsi_EntitlementOwnersConsideredCount` | `fsi_entitlementownersconsideredcount` | Integer | No | Count of owners considered for entitlement resolution |
| `fsi_EntitlementPaidCount` | `fsi_entitlementpaidcount` | Integer | No | Count of owners resolved as Paid Copilot |
| `fsi_EntitlementChatOnlyCount` | `fsi_entitlementchatonlycount` | Integer | No | Count of owners resolved as Copilot Chat Only |
| `fsi_EntitlementUnknownCount` | `fsi_entitlementunknowncount` | Integer | No | Count of owners with Unknown entitlement |
| `fsi_CoverageScopeJson` | `fsi_coveragescopejson` | Memo(100000) | No | Structured layer-scope and toggle metadata for this run |
| `fsi_SummaryJson` | `fsi_summaryjson` | Memo(100000) | No | Structured run summary payload for reproducibility and BI drillthrough |

**Alternate key** `fsi_ScanRunKey`: (`fsi_runid`) — idempotent upsert key.
