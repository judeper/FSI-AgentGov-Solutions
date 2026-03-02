# Dataverse Schema Reference

Complete schema documentation for the Content Moderation Governance Monitor (CMM) solution.

## Overview

The CMM solution uses three Dataverse tables, two shared option sets, seven environment variables, and four connection references. All entities use the `fsi_` publisher prefix for consistency with the FSI Agent Governance Framework.

---

## Tables

### fsi_moderationbaselines

Per-agent moderation level snapshots used for drift detection comparison. Each record captures a single agent's content moderation configuration at a point in time.

**Ownership:** User-owned
**Primary Name Column:** `fsi_name`

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_moderationbaselineid` | Uniqueidentifier | Auto | Primary key |
| `fsi_name` | String (500) | Yes | Record name (`{AgentName}-{Zone}-{Timestamp}`) |
| `fsi_environment_guid` | String (100) | Yes | Power Platform environment GUID |
| `fsi_environment_name` | String (500) | Yes | Environment display name |
| `fsi_zone` | OptionSet (fsi_acv_zone) | Yes | Zone classification |
| `fsi_agent_id` | String (100) | Yes | Copilot Studio bot GUID |
| `fsi_agent_name` | String (500) | Yes | Agent display name |
| `fsi_moderation_level` | String (50) | Yes | Captured moderation level (Low/Medium/High) |
| `fsi_is_active` | Boolean | Yes | Current active baseline flag (one active per agent) |
| `fsi_captured_at` | DateTime | Yes | When baseline was captured (UTC) |
| `fsi_captured_by` | String (200) | No | UPN of capturing operator |
| `fsi_raw_json` | Memo (100000) | No | Full JSON snapshot of moderation settings |

**Key behavior:** Only one baseline per agent should be active at a time. When a new baseline is captured, the previous active baseline is deactivated (`fsi_is_active = false`).

### fsi_moderationvalidationhistory

Organization-owned immutable scan summary records. Each record represents one complete validation run across all environments.

**Ownership:** Organization-owned (no per-user filtering)
**Primary Name Column:** `fsi_name`
**Immutability:** Records are created once and never updated. This supports audit trail requirements for FINRA 4511 and SEC 17a-3/4.

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_moderationvalidationhistoryid` | Uniqueidentifier | Auto | Primary key |
| `fsi_name` | String (500) | Yes | Record name (`{Status}-{Timestamp}`) |
| `fsi_run_id` | String (36) | Yes | GUID correlating all records from one scan |
| `fsi_validation_time` | DateTime | Yes | When scan executed (UTC) |
| `fsi_total_agents` | Integer | Yes | Total agents scanned |
| `fsi_compliant_count` | Integer | Yes | Agents passing moderation checks |
| `fsi_violation_count` | Integer | Yes | Agents with moderation violations |
| `fsi_overall_status` | String (50) | Yes | Passed, Failed, Warning, or Critical |
| `fsi_environments_scanned` | String (2000) | No | Comma-separated environment list |
| `fsi_summary_json` | Memo (100000) | No | Full JSON summary blob |

### fsi_moderationviolations

Per-agent violation records with severity classification and regulatory context. Each record represents one agent whose content moderation level does not meet its zone requirement.

**Ownership:** User-owned
**Primary Name Column:** `fsi_name`

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_moderationviolationid` | Uniqueidentifier | Auto | Primary key |
| `fsi_name` | String (500) | Yes | Record name (`{AgentName}-{Zone}-{Date}`) |
| `fsi_environment_guid` | String (100) | Yes | Power Platform environment GUID |
| `fsi_environment_name` | String (500) | Yes | Environment display name |
| `fsi_agent_id` | String (100) | Yes | Violating agent's bot GUID |
| `fsi_agent_name` | String (500) | Yes | Agent display name |
| `fsi_zone` | OptionSet (fsi_acv_zone) | Yes | Zone classification |
| `fsi_expected_level` | String (50) | Yes | Zone-required moderation level |
| `fsi_actual_level` | String (50) | Yes | Agent's current moderation level |
| `fsi_severity` | String (50) | Yes | Violation severity (Critical/High/Medium/Warning) |
| `fsi_regulatory_context` | String (2000) | No | FINRA/SOX/GLBA regulatory impact context |
| `fsi_detected_at` | DateTime | Yes | When violation was detected (UTC) |
| `fsi_run_id` | String (36) | No | Correlating scan run GUID |

---

## Shared Option Sets

These option sets are shared with the Audit Configuration Validator (ACV) solution for cross-solution consistency.

### fsi_acv_zone

Zone classification for governance grouping.

| Value | Label |
|-------|-------|
| 0 | Unclassified |
| 1 | Zone 1 (Personal Productivity) |
| 2 | Zone 2 (Team Collaboration) |
| 3 | Zone 3 (Enterprise Managed) |

### fsi_acv_severity

Severity classification for validation outcomes. Shared with the Audit Configuration Validator (ACV) solution. Note: CMM's `fsi_severity` column uses a String type rather than this option set because CMM severity labels (Critical/High/Medium/Warning) differ from ACV labels. The option set is retained in the schema for cross-solution consistency but is not bound to any CMM column.

| Value | Label |
|-------|-------|
| 1 | Passed |
| 2 | Warning |
| 3 | GracePeriod |
| 4 | Failed |
| 5 | Error |

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
│  fsi_agent_id ◄─────────────┼────────────────────────┐
│  fsi_environment_guid       │                        │
│  fsi_moderation_level       │                        │
│  fsi_is_active              │                        │
│  fsi_zone (fsi_acv_zone)    │                        │
└─────────────────────────────┘                        │
                                                       │ (agent_id
┌─────────────────────────────┐                        │  correlation)
│ fsi_moderationvalidation-   │                        │
│       history               │                        │
│  (immutable scan summaries) │      ┌─────────────────┴───────────┐
│  ─────────────────────────  │      │  fsi_moderationviolations   │
│  fsi_run_id ◄───────────────┼──────┤  (per-agent violations)     │
│  fsi_total_agents           │      │  ─────────────────────────  │
│  fsi_compliant_count        │ run  │  fsi_agent_id               │
│  fsi_violation_count        │  id  │  fsi_agent_name             │
│  fsi_overall_status         │      │  fsi_expected_level         │
│  fsi_summary_json           │      │  fsi_actual_level           │
└─────────────────────────────┘      │  fsi_severity (string)       │
                                     │  fsi_run_id                 │
                                     │  fsi_zone (fsi_acv_zone)    │
                                     └─────────────────────────────┘
```

**Relationships:**

- `fsi_moderationvalidationhistory` → `fsi_moderationviolations`: Correlated by `fsi_run_id` (logical, not Dataverse lookup)
- `fsi_moderationbaselines` → `fsi_moderationviolations`: Correlated by `fsi_agent_id` (logical, for drift detection comparison)

---

*Content Moderation Governance Monitor — Dataverse Schema Reference v1.0.0*
