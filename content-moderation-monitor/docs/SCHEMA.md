# Dataverse Schema Reference

Complete schema documentation for the Content Moderation Governance Monitor (CMM) solution.

## Overview

The CMM solution uses three Dataverse tables, two shared option sets, seven environment variables, and four connection references. All entities use the `fsi_` publisher prefix for consistency with the FSI Agent Governance Framework.

---

## Tables

### fsi_moderationbaseline

Per-agent moderation level snapshots used for drift detection comparison. Each record captures a single agent's content moderation configuration at a point in time.

**Logical name:** `fsi_moderationbaseline` (singular)
**Entity set (OData):** `fsi_moderationbaselines` (plural)
**Ownership:** User-owned
**Primary Name Column:** `fsi_name`

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_moderationbaselineid` | Uniqueidentifier | Auto | Primary key |
| `fsi_name` | String (500) | Yes | Record name (`{AgentName}-{Zone}-{Timestamp}`) |
| `fsi_environmentguid` | String (100) | Yes | Power Platform environment GUID |
| `fsi_environmentname` | String (500) | Yes | Environment display name |
| `fsi_zone` | OptionSet (fsi_acv_zone) | Yes | Zone classification |
| `fsi_agentid` | String (100) | Yes | Copilot Studio bot GUID |
| `fsi_agentname` | String (500) | Yes | Agent display name |
| `fsi_moderationlevel` | String (50) | Yes | Captured moderation level (Low/Medium/High) |
| `fsi_isactive` | Boolean | Yes | Current active baseline flag (one active per agent) |
| `fsi_capturedat` | DateTime | Yes | When baseline was captured (UTC) |
| `fsi_capturedby` | String (200) | No | UPN of capturing operator |
| `fsi_rawjson` | Memo (100000) | No | Full JSON snapshot of moderation settings |

**Key behavior:** Only one baseline per agent should be active at a time. When a new baseline is captured, the previous active baseline is deactivated (`fsi_isactive = false`).

### fsi_moderationvalidationhistory

Organization-owned immutable scan summary records. Each record represents one complete validation run across all environments.

**Logical name:** `fsi_moderationvalidationhistory`
**Entity set (OData):** `fsi_moderationvalidationhistory` (explicit singular set name; default auto-plural would be `fsi_moderationvalidationhistorys`)
**Ownership:** Organization-owned (no per-user filtering)
**Primary Name Column:** `fsi_name`
**Immutability:** Records are created once and never updated. This supports audit trail requirements for FINRA 4511 and SEC 17a-3/4.

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_moderationvalidationhistoryid` | Uniqueidentifier | Auto | Primary key |
| `fsi_name` | String (500) | Yes | Record name (`{Status}-{Timestamp}`) |
| `fsi_runid` | String (36) | Yes | GUID correlating all records from one scan |
| `fsi_validationtime` | DateTime | Yes | When scan executed (UTC) |
| `fsi_totalagents` | Integer | Yes | Total agents scanned |
| `fsi_compliantcount` | Integer | Yes | Agents passing moderation checks |
| `fsi_violationcount` | Integer | Yes | Agents with moderation violations |
| `fsi_overallstatus` | String (50) | Yes | Passed, Failed, Warning, or Critical |
| `fsi_environmentsscanned` | String (2000) | No | Comma-separated environment list |
| `fsi_summaryjson` | Memo (100000) | No | Full JSON summary blob |

### fsi_moderationviolation

Per-agent violation records with severity classification and regulatory context. Each record represents one agent whose content moderation level does not meet its zone requirement.

**Logical name:** `fsi_moderationviolation` (singular)
**Entity set (OData):** `fsi_moderationviolations` (plural)
**Ownership:** User-owned
**Primary Name Column:** `fsi_name`

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_moderationviolationid` | Uniqueidentifier | Auto | Primary key |
| `fsi_name` | String (500) | Yes | Record name (`{AgentName}-{Zone}-{Date}`) |
| `fsi_environmentguid` | String (100) | Yes | Power Platform environment GUID |
| `fsi_environmentname` | String (500) | Yes | Environment display name |
| `fsi_agentid` | String (100) | Yes | Violating agent's bot GUID |
| `fsi_agentname` | String (500) | Yes | Agent display name |
| `fsi_zone` | OptionSet (fsi_acv_zone) | Yes | Zone classification |
| `fsi_expectedlevel` | String (50) | Yes | Zone-required moderation level |
| `fsi_actuallevel` | String (50) | Yes | Agent's current moderation level |
| `fsi_severity` | String (50) | Yes | Violation severity (Critical/High/Medium/Warning) |
| `fsi_regulatorycontext` | String (2000) | No | FINRA/SOX/GLBA regulatory impact context |
| `fsi_detectedat` | DateTime | Yes | When violation was detected (UTC) |
| `fsi_runid` | String (36) | No | Correlating scan run GUID |

---

## Shared Option Sets

These option sets are shared with the Audit Configuration Validator (ACV) solution for cross-solution consistency.

### fsi_acv_zone

Zone classification for governance grouping.

| Value | Label |
|-------|-------|
| 100000000 | Unclassified |
| 100000001 | Zone 1 (Personal Productivity) |
| 100000002 | Zone 2 (Team Collaboration) |
| 100000003 | Zone 3 (Enterprise Managed) |

### fsi_acv_severity

Severity classification for validation outcomes. Shared with the Audit Configuration Validator (ACV) solution. Note: CMM's `fsi_severity` column uses a String type rather than this option set because CMM severity labels (Critical/High/Medium/Warning) differ from ACV labels. The option set is retained in the schema for cross-solution consistency but is not bound to any CMM column.

| Value | Label |
|-------|-------|
| 100000000 | Passed |
| 100000001 | Warning |
| 100000002 | GracePeriod |
| 100000003 | Failed |
| 100000004 | Error |

---

## Environment Variables

All environment variables use the `fsi_CMM_` prefix. Values are read by PowerShell scripts via `Get-CMMEnvironmentVariable` in `CMMClient.psm1`.

| Schema Name | Type | Default | Purpose |
|-------------|------|---------|---------|
| `fsi_CMM_ScanFrequencyHours` | Integer | 24 | Hours between scheduled validation runs |
| `fsi_CMM_GracePeriodHours` | Integer | 48 | Hours before newly provisioned environments are validated |
| `fsi_CMM_IncludeSandbox` | Boolean | false | Whether to include sandbox environments in validation |
| `fsi_CMM_IncludeDrafts` | Boolean | false | Whether to include draft (unpublished) agents |
| `fsi_CMM_BaselineMaxAgeDays` | Integer | 30 | Days before an active baseline is flagged as stale |
| `fsi_CMM_TeamsGroupId` | String | — | Microsoft 365 Group ID for Teams alert channel |
| `fsi_CMM_TeamsChannelId` | String | — | Teams channel ID for alert delivery |

---

## Connection References

Power Automate connection references for the CMM flow.

| Schema Name | Connector | Purpose |
|-------------|-----------|---------|
| `fsi_cr_dataverse_moderationmonitor` | Microsoft Dataverse | Read/write validation results, baselines, violations |
| `fsi_cr_office365_moderationmonitor` | Office 365 Outlook | Email alerts for high/critical violations |
| `fsi_cr_teams_moderationmonitor` | Microsoft Teams | Teams adaptive card alert delivery |
| `fsi_cr_azureautomation_moderationmonitor` | Azure Automation | Invoke validation runbook from Power Automate flow |

---

## Entity Relationship Diagram

```
┌─────────────────────────────┐
│  fsi_moderationbaselines    │
│  (per-agent snapshots)      │
│  ─────────────────────────  │
│  fsi_agentid ◄──────────────┼────────────────────────┐
│  fsi_environmentguid        │                        │
│  fsi_moderationlevel        │                        │
│  fsi_isactive               │                        │
│  fsi_zone (fsi_acv_zone)    │                        │
└─────────────────────────────┘                        │
                                                       │ (agent_id
┌─────────────────────────────┐                        │  correlation)
│ fsi_moderationvalidation-   │                        │
│       history               │                        │
│  (immutable scan summaries) │      ┌─────────────────┴───────────┐
│  ─────────────────────────  │      │  fsi_moderationviolations   │
│  fsi_runid ◄────────────────┼──────┤  (per-agent violations)     │
│  fsi_totalagents            │      │  ─────────────────────────  │
│  fsi_compliantcount         │ run  │  fsi_agentid                │
│  fsi_violationcount         │  id  │  fsi_agentname              │
│  fsi_overallstatus          │      │  fsi_expectedlevel          │
│  fsi_summaryjson            │      │  fsi_actuallevel            │
└─────────────────────────────┘      │  fsi_severity (string)       │
                                     │  fsi_runid                  │
                                     │  fsi_zone (fsi_acv_zone)    │
                                     └─────────────────────────────┘
```

**Relationships:**

- `fsi_moderationvalidationhistory` → `fsi_moderationviolations`: Correlated by `fsi_runid` (logical, not Dataverse lookup)
- `fsi_moderationbaselines` → `fsi_moderationviolations`: Correlated by `fsi_agentid` (logical, for drift detection comparison)

---

*Content Moderation Governance Monitor — Dataverse Schema Reference v1.0.3*
