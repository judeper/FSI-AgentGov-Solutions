# Dataverse Schema Reference

Complete schema documentation for the Generative AI Config Auditor (GAC) solution.

## Overview

The GAC solution uses five Dataverse tables, three solution-specific option sets, two shared option sets, eight environment variables, and four connection references. All entities use the `fsi_` publisher prefix for consistency with the FSI Agent Governance Framework.

---

## Tables

### fsi_GACBaseline

Per-agent generative AI configuration snapshots used for drift detection. Each record captures a single agent's generative AI feature settings at a point in time.

**Ownership:** UserOwned
**Primary Name Column:** `fsi_Name`
**Description:** Per-agent generative AI configuration snapshots for governance comparison and drift detection

| Column (SchemaName) | Type | Required | Description |
|-------------------|------|----------|-------------|
| `fsi_GACBaselineId` | Uniqueidentifier | Auto | Primary key |
| `fsi_Name` | String(200) | Yes | Record name (`{AgentName}-{Zone}-{Timestamp}`) |
| `fsi_EnvironmentGuid` | String(100) | Yes | Power Platform environment GUID |
| `fsi_EnvironmentName` | String(500) | Yes | Environment display name |
| `fsi_Zone` | Picklist (fsi_acv_zone) | Yes | Zone classification |
| `fsi_AgentId` | String(100) | Yes | Copilot Studio bot GUID |
| `fsi_AgentName` | String(500) | Yes | Agent display name |
| `fsi_AzureOpenAIEnabled` | Boolean (default: false) | Yes | Whether Azure OpenAI integration is enabled |
| `fsi_OrchestrationMode` | Picklist (fsi_GAC_orchestrationmode) | Yes | Agent orchestration mode (Classic/Generative/Custom) |
| `fsi_KnowledgeSourceCount` | Integer | No | Number of knowledge sources configured |
| `fsi_GenerativeAnswersNodeCount` | Integer | No | Number of generative answers nodes in topic tree |
| `fsi_AoaiConnectionId` | String(200) | No | Azure OpenAI connection reference identifier |
| `fsi_AoaiEndpoint` | String(500) | No | Azure OpenAI endpoint URL |
| `fsi_KnowledgeSources` | Memo(10000) | No | JSON array of knowledge source configurations |
| `fsi_IsActive` | Boolean (default: true) | Yes | Current active baseline flag (one active per agent) |
| `fsi_CapturedAt` | DateTime | Yes | When baseline was captured (UTC) |
| `fsi_CapturedBy` | String(200) | No | UPN of capturing operator |
| `fsi_RawJson` | Memo(100000) | No | Full JSON snapshot of generative AI configuration |

**Key behavior:** Only one baseline per agent should be active at a time. When a new baseline is captured, the previous active baseline is deactivated (`fsi_IsActive = false`).

### fsi_GACValidationHistory

Organization-owned immutable scan summary records. Each record represents one complete validation run across all environments.

**Ownership:** OrganizationOwned
**Primary Name Column:** `fsi_Name`
**Immutability:** Records are created once and never updated. This supports audit trail requirements for FINRA 4511 and SEC 17a-3/4.
**Description:** Immutable scan summary records for regulatory evidence

| Column (SchemaName) | Type | Required | Description |
|-------------------|------|----------|-------------|
| `fsi_GACValidationHistoryId` | Uniqueidentifier | Auto | Primary key |
| `fsi_Name` | String(200) | Yes | Record name (`{Status}-{Timestamp}`) |
| `fsi_RunId` | String(36) | Yes | GUID correlating all records from one scan |
| `fsi_ValidationTime` | DateTime | Yes | When scan executed (UTC) |
| `fsi_TotalAgents` | Integer | Yes | Total agents scanned |
| `fsi_CompliantCount` | Integer | Yes | Agents passing generative AI config checks |
| `fsi_ViolationCount` | Integer | Yes | Agents with generative AI config violations |
| `fsi_OverallStatus` | String(50) | Yes | Passed, Failed, Warning, or Critical |
| `fsi_EnvironmentsScanned` | String(2000) | No | Comma-separated environment list |
| `fsi_SummaryJson` | Memo(100000) | No | Full JSON summary blob |

### fsi_GACViolation

Per-agent violation records with severity classification and regulatory context. Each record represents one agent whose generative AI configuration does not meet its zone governance policy.

**Ownership:** UserOwned
**Primary Name Column:** `fsi_Name`
**Description:** Per-agent generative AI configuration violations detected during governance scans

| Column (SchemaName) | Type | Required | Description |
|-------------------|------|----------|-------------|
| `fsi_GACViolationId` | Uniqueidentifier | Auto | Primary key |
| `fsi_Name` | String(200) | Yes | Record name (`{AgentName}-{ViolationType}-{Date}`) |
| `fsi_EnvironmentGuid` | String(100) | Yes | Power Platform environment GUID |
| `fsi_EnvironmentName` | String(500) | Yes | Environment display name |
| `fsi_AgentId` | String(100) | Yes | Violating agent's bot GUID |
| `fsi_AgentName` | String(500) | Yes | Agent display name |
| `fsi_Zone` | Picklist (fsi_acv_zone) | Yes | Zone classification |
| `fsi_FeatureType` | Picklist (fsi_GAC_genaifeaturetype) | Yes | Type of generative AI feature in violation |
| `fsi_ExpectedState` | String(500) | Yes | Zone-required configuration state |
| `fsi_ActualState` | String(500) | Yes | Agent's current configuration state |
| `fsi_ConnectionStatus` | Picklist (fsi_GAC_connectionstatus) | No | Azure OpenAI connection approval status |
| `fsi_Severity` | String(50) | Yes | Violation severity (Critical/High/Medium/Warning) |
| `fsi_RegulatoryContext` | String(2000) | No | FINRA/SOX/GLBA regulatory impact context |
| `fsi_TopicName` | String(500) | No | Name of the topic containing the violation |
| `fsi_TopicId` | String(100) | No | GUID of the topic containing the violation |
| `fsi_DetectedAt` | DateTime | Yes | When violation was detected (UTC) |
| `fsi_RunId` | String(36) | No | Correlating scan run GUID |

### fsi_GACApprovedConnection

Approved Azure OpenAI connections whitelist. Records represent AOAI connections that have been vetted and approved for use within specific governance zones.

**Ownership:** UserOwned
**Primary Name Column:** `fsi_Name`
**Description:** Approved Azure OpenAI connection whitelist for zone-based connection governance

| Column (SchemaName) | Type | Required | Description |
|-------------------|------|----------|-------------|
| `fsi_GACApprovedConnectionId` | Uniqueidentifier | Auto | Primary key |
| `fsi_Name` | String(200) | Yes | Display name (`{ConnectionName} ({Zone})`) |
| `fsi_ConnectionId` | String(200) | Yes | Power Platform connection reference identifier (idempotency key) |
| `fsi_ConnectionName` | String(500) | Yes | Display name of the approved connection |
| `fsi_Zone` | Picklist (fsi_acv_zone) | Yes | Zone this connection is approved for |
| `fsi_ResourceGroup` | String(500) | No | Azure resource group containing the AOAI resource |
| `fsi_AoaiEndpoint` | String(1000) | No | Azure OpenAI endpoint URL |
| `fsi_ApprovedBy` | String(200) | Yes | UPN of approving administrator |
| `fsi_ApprovedAt` | DateTime | Yes | When connection was approved |
| `fsi_ExpiresAt` | DateTime | No | Approval expiration date (optional; null = no expiration) |
| `fsi_IsActive` | Boolean (default: true) | Yes | Whether this approval is currently active |
| `fsi_Notes` | Memo(5000) | No | Additional notes or justification for approval |

**Key behavior:** The compliance scan checks `fsi_ConnectionId` and `fsi_Zone` to determine whether an agent's AOAI connection is on the approved whitelist for its governance zone. Only records with `fsi_IsActive = true` are considered during validation.

### fsi_GACFeatureInventory

Per-agent feature tracking table. Provides a current-state inventory of which generative AI features each agent has enabled.

**Ownership:** UserOwned
**Primary Name Column:** `fsi_Name`
**Description:** Per-agent generative AI feature tracking inventory for comprehensive capability visibility

| Column (SchemaName) | Type | Required | Description |
|-------------------|------|----------|-------------|
| `fsi_GACFeatureInventoryId` | Uniqueidentifier | Auto | Primary key |
| `fsi_Name` | String(200) | Yes | Record name (`{AgentName}-{FeatureType}`) |
| `fsi_EnvironmentGuid` | String(100) | Yes | Power Platform environment GUID |
| `fsi_AgentId` | String(100) | Yes | Copilot Studio bot GUID |
| `fsi_AgentName` | String(500) | Yes | Agent display name |
| `fsi_Zone` | Picklist (fsi_acv_zone) | Yes | Zone classification |
| `fsi_FeatureType` | Picklist (fsi_GAC_genaifeaturetype) | Yes | Type of generative AI feature |
| `fsi_FeatureEnabled` | Boolean (default: false) | Yes | Whether this feature is enabled on the agent |
| `fsi_FeatureDetail` | String(2000) | No | Additional detail about feature configuration |
| `fsi_LastScannedAt` | DateTime | Yes | When this feature was last scanned |
| `fsi_RunId` | String(36) | No | Correlating scan GUID |

---

## Option Sets

### Shared Option Sets (reused from ACV)

These option sets are shared with other FSI Agent Governance solutions (Audit Configuration Validator, Content Moderation Monitor) for cross-solution consistency.

#### fsi_acv_zone

Zone classification for governance grouping.

| Value | Label |
|-------|-------|
| 0 | Unclassified |
| 1 | Zone 1 (Personal Productivity) |
| 2 | Zone 2 (Team Collaboration) |
| 3 | Zone 3 (Enterprise Managed) |

#### fsi_acv_severity

Severity classification for validation outcomes.

| Value | Label |
|-------|-------|
| 1 | Passed |
| 2 | Warning |
| 3 | GracePeriod |
| 4 | Failed |
| 5 | Error |

> **Note:** GAC's `fsi_Severity` column on `fsi_GACViolation` uses a String type (Critical/High/Medium/Warning) rather than this option set, because GAC severity labels differ from the shared option set labels. The shared option set is retained in the schema for cross-solution consistency but is not bound to the violation severity column.

### GAC-Specific Option Sets

#### fsi_GAC_orchestrationmode

Orchestration mode for Copilot Studio agents.

| Value | Label | Description |
|-------|-------|-------------|
| 100000000 | Classic | Traditional topic-based orchestration |
| 100000001 | Generative | AI-driven generative orchestration |
| 100000002 | Custom | Custom orchestration configuration |

#### fsi_GAC_genaifeaturetype

Types of generative AI features tracked by the auditor.

| Value | Label | Description |
|-------|-------|-------------|
| 100000000 | AzureOpenAIIntegration | Direct Azure OpenAI service connection |
| 100000001 | GenerativeOrchestration | Generative orchestration mode enabled |
| 100000002 | GenerativeAnswersNode | Generative answers node in topic |
| 100000003 | SearchAndSummarize | Search and summarize content capability |
| 100000004 | GenerativeActions | Generative plugin/action execution |
| 100000005 | KnowledgeSource | External knowledge source integration |

#### fsi_GAC_connectionstatus

Approval status of an AOAI connection relative to the governance whitelist.

| Value | Label | Description |
|-------|-------|-------------|
| 100000000 | Approved | Connection is on the approved whitelist for the zone |
| 100000001 | Unapproved | Connection is not on the approved whitelist |
| 100000002 | Unknown | Connection status could not be determined |
| 100000003 | NotApplicable | Feature does not use an AOAI connection |

---

## Environment Variables

All environment variables use the `fsi_GAC_` prefix. Values are read by PowerShell scripts via the `GACClient.psm1` module.

| Schema Name | Type | Default | Purpose |
|-------------|------|---------|---------|
| `fsi_GAC_ScanFrequencyHours` | Integer | 24 | Hours between scheduled validation runs |
| `fsi_GAC_GracePeriodHours` | Integer | 48 | Hours before newly provisioned environments are validated |
| `fsi_GAC_IncludeSandbox` | Boolean | false | Whether to include sandbox environments in validation |
| `fsi_GAC_IncludeDrafts` | Boolean | false | Whether to include draft (unpublished) agents |
| `fsi_GAC_BaselineMaxAgeDays` | Integer | 30 | Days before an active baseline is flagged as stale |
| `fsi_GAC_TeamsGroupId` | String | -- | Microsoft 365 Group ID for Teams alert channel |
| `fsi_GAC_TeamsChannelId` | String | -- | Teams channel ID for alert delivery |
| `fsi_GAC_AoaiWhitelistEnforced` | Boolean | true | Whether unapproved AOAI connections generate violations (vs. warnings only) |

---

## Connection References

Power Automate connection references for the GAC flows.

| Schema Name | Connector | Purpose |
|-------------|-----------|---------|
| `fsi_cr_dataverse_gacmonitor` | Microsoft Dataverse | Read/write validation results, baselines, violations, approved connections |
| `fsi_cr_office365_gacmonitor` | Office 365 Outlook | Email alerts for high/critical violations |
| `fsi_cr_teams_gacmonitor` | Microsoft Teams | Teams adaptive card alert delivery |
| `fsi_cr_azureautomation_gacmonitor` | Azure Automation | Invoke validation runbook from Power Automate flow |

---

## Entity Relationship Diagram

```
┌──────────────────────────────┐
│  fsi_GACBaseline             │
│  (per-agent config snapshots)│
│  ──────────────────────────  │
│  fsi_AgentId ◄───────────────┼──────────────────────────┐
│  fsi_EnvironmentGuid         │                          │
│  fsi_OrchestrationMode       │                          │
│  fsi_AzureOpenAIEnabled      │                          │
│  fsi_AoaiConnectionId        │                          │
│  fsi_IsActive                │                          │
│  fsi_Zone (fsi_acv_zone)     │                          │
└──────────────────────────────┘                          │
                                                          │ (agent_id
┌──────────────────────────────┐                          │  correlation)
│ fsi_GACValidationHistory     │                          │
│  (immutable scan summaries)  │    ┌─────────────────────┴──────────┐
│  ──────────────────────────  │    │  fsi_GACViolation              │
│  fsi_RunId ◄─────────────────┼────┤  (per-agent violations)        │
│  fsi_TotalAgents             │    │  ──────────────────────────    │
│  fsi_ViolationCount          │run │  fsi_AgentId                   │
│  fsi_OverallStatus           │ id │  fsi_FeatureType               │
│  fsi_SummaryJson             │    │  fsi_ExpectedState             │
└──────────────────────────────┘    │  fsi_ActualState               │
                                    │  fsi_Severity (string)         │
┌──────────────────────────────┐    │  fsi_RunId                     │
│  fsi_GACApprovedConnection   │    │  fsi_Zone (fsi_acv_zone)       │
│  (AOAI connection whitelist) │    └────────────────────────────────┘
│  ──────────────────────────  │
│  fsi_ConnectionId ◄──────────┼───────────────────┐
│  fsi_AoaiEndpoint            │                   │ (connection_id
│  fsi_Zone                    │                   │  lookup during
│  fsi_IsActive                │                   │  validation)
│  fsi_ApprovedBy              │    ┌──────────────┴─────────────────┐
└──────────────────────────────┘    │  fsi_GACFeatureInventory       │
                                    │  (per-agent feature tracking)  │
                                    │  ──────────────────────────    │
                                    │  fsi_AgentId                   │
                                    │  fsi_FeatureType               │
                                    │  fsi_FeatureEnabled            │
                                    │  fsi_FeatureDetail             │
                                    │  fsi_Zone (fsi_acv_zone)       │
                                    └────────────────────────────────┘
```

**Relationships:**

- `fsi_GACValidationHistory` -> `fsi_GACViolation`: Correlated by `fsi_RunId` (logical, not Dataverse lookup)
- `fsi_GACBaseline` -> `fsi_GACViolation`: Correlated by `fsi_AgentId` (logical, for drift detection comparison)
- `fsi_GACApprovedConnection` -> `fsi_GACFeatureInventory`: Correlated by `fsi_ConnectionId` (logical, for whitelist validation)
- `fsi_GACFeatureInventory` -> `fsi_GACViolation`: Correlated by `fsi_AgentId` + `fsi_FeatureType` (logical, for feature-level violation tracking)

---

*Generative AI Config Auditor -- Dataverse Schema Reference v1.0.1*
