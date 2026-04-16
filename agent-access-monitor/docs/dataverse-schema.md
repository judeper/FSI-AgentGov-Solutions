# Dataverse Schema Reference

## Overview

The Agent Access Governance Monitor uses three Dataverse tables to store access baselines, validation history, and violation records. Tables share option sets with the Agent Configuration Validator (ACV) solution for consistent zone and severity classification.

## Tables

### fsi_accessbaselines

Stores captured access configuration snapshots for each Power Platform environment. Only one active baseline exists per environment at a time.

| Column | Type | Description |
|--------|------|-------------|
| `fsi_environmentguid` | String | Power Platform environment unique identifier |
| `fsi_environmentname` | String | Display name of the environment |
| `fsi_zone` | OptionSet (fsi_acv_zone) | Governance zone (100000001, 100000002, or 100000003) |
| `fsi_botlimitsharingmode` | String | Agent sharing limit setting at capture time |
| `fsi_botauthoringsharingdisabled` | Boolean | Whether agent authoring sharing is disabled |
| `fsi_botpublishedbotlimitsharingmode` | String | Published agent sharing limit at capture time |
| `fsi_capturedby` | String | UPN or service principal that captured the baseline |
| `fsi_capturedat` | DateTime | Timestamp of baseline capture (UTC) |
| `fsi_isactive` | Boolean | Whether this is the current active baseline |
| `fsi_rawjson` | Memo | Full JSON payload of access settings at capture time |

### fsi_accessvalidationhistory

Immutable audit trail of validation run results. Each record represents one complete validation scan across all environments.

| Column | Type | Description |
|--------|------|-------------|
| `fsi_name` | String | Run display name (auto-generated) |
| `fsi_runid` | String | Unique GUID identifying the validation run |
| `fsi_zone` | OptionSet | Governance zone at time of validation (optional; null for aggregate cross-zone runs; per-zone detail available in `fsi_summaryjson`) |
| `fsi_severity` | OptionSet | Overall validation result severity (maps OverallStatus via `fsi_acv_severity`: Passed→100000000, Warning→100000001, Failed→100000003, Error→100000004) |
| `fsi_validationtime` | DateTime | Timestamp of validation execution (UTC) |
| `fsi_totalenvironments` | Integer | Number of environments scanned |
| `fsi_compliantcount` | Integer | Environments meeting zone requirements |
| `fsi_violationcount` | Integer | Environments with access violations |
| `fsi_overallstatus` | String | Aggregate status (Passed, Warning, Failed, Review) |
| `fsi_summaryjson` | Memo | Per-zone breakdown as JSON (Total, Compliant, Violations per zone) |

### fsi_accessviolations

Individual access policy violations detected during validation. Linked to validation runs via `fsi_runid`.

| Column | Type | Description |
|--------|------|-------------|
| `fsi_name` | String | Violation display name (auto-generated) |
| `fsi_environmentguid` | String | Environment where violation was detected |
| `fsi_environmentname` | String | Display name of the environment |
| `fsi_zone` | OptionSet (fsi_acv_zone) | Governance zone of the environment |
| `fsi_violationtype` | String | Setting that violated policy (e.g., `bot-limitSharingMode`) |
| `fsi_expectedvalue` | String | Required value per zone policy |
| `fsi_actualvalue` | String | Current environment setting value |
| `fsi_severity` | OptionSet (fsi_acv_severity) | Severity classification (option set integer; see fsi_severitylabel for text) |
| `fsi_severitylabel` | String | Original severity string for Critical/High distinction |
| `fsi_regulatorycontext` | String | Applicable regulations (e.g., FINRA 4511, SOX 404) |
| `fsi_detectedat` | DateTime | Timestamp of violation detection (UTC) |
| `fsi_runid` | String | Links to fsi_accessvalidationhistory run |
| `fsi_acknowledged` | Boolean | Whether an administrator has acknowledged this violation |
| `fsi_acknowledgedby` | String | Identity that acknowledged the violation |
| `fsi_acknowledgedon` | DateTime | When the violation was acknowledged (UTC) |
| `fsi_resolvedat` | DateTime | When the violation was resolved (UTC) |
| `fsi_notes` | Memo | Administrator notes on this violation |

## Option Sets (Shared with ACV)

### fsi_acv_zone

| Value | Label |
|-------|-------|
| 100000000 | Unclassified |
| 100000001 | Zone 1 |
| 100000002 | Zone 2 |
| 100000003 | Zone 3 |

### fsi_acv_severity

| Value | Label |
|-------|-------|
| 100000000 | Passed |
| 100000001 | Warning |
| 100000002 | GracePeriod |
| 100000003 | Failed |
| 100000004 | Error |

> **Note:** The `fsi_acv_severity` picklist maps Critical and High violations to `100000003` (Failed). To distinguish them, the `fsi_severitylabel` text column stores the original severity string (Critical, High, Warning, Info).

## Environment Variables

| Schema Name | Type | Default | Purpose |
|-------------|------|---------|---------|
| `fsi_AAM_GracePeriodHours` | Decimal | 48 | Hours to exclude newly provisioned environments |
| `fsi_AAM_ScanFrequencyHours` | Decimal | 24 | Interval in hours between automated access compliance scans |
| `fsi_AAM_IncludeSandbox` | String | false | Include sandbox environments in validation |
| `fsi_AAM_BaselineMaxAgeDays` | Decimal | 30 | Alert threshold in days for stale access baselines |
| `fsi_AAM_TeamsGroupId` | String | *(empty)* | Microsoft Teams group GUID for alert notifications |
| `fsi_AAM_TeamsChannelId` | String | *(empty)* | Microsoft Teams channel GUID for alert notifications |
| `fsi_AAM_DataverseUrl` | String | *(empty)* | Dataverse instance URL for API calls (e.g., `https://org.crm.dynamics.com`). Currently initialized as a flow variable (see `docs/flow-configuration.md`, Step 2 — `DataverseUrl`); migrating to an environment variable requires flow restructuring and deployment coordination. |

## Connection References

| Schema Name | Connector | Purpose |
|-------------|-----------|---------|
| `fsi_cr_dataverse_accessmonitor` | Dataverse | Read/write validation history, violations, baselines |
| `fsi_cr_office365_accessmonitor` | Office 365 Outlook | Email alerts for compliance violations |
| `fsi_cr_teams_accessmonitor` | Microsoft Teams | Adaptive card alerts for drift detection |

> **Note:** The Power Automate flow (see `docs/flow-configuration.md`) also uses the Azure Automation connector (`azureautomation`) to execute the validation runbook. This connection must be created manually when building the flow — it is not managed as a solution connection reference by `create_connection_references.py`.

## Entity Relationship Diagram

```
┌─────────────────────────────────┐
│   fsi_accessvalidationhistory   │
│─────────────────────────────────│
│ fsi_runid (PK, unique)         │──┐
│ fsi_validationtime              │  │
│ fsi_totalenvironments           │  │
│ fsi_compliantcount              │  │  matched by
│ fsi_violationcount              │  │  fsi_runid
│ fsi_overallstatus               │  │
│ fsi_summaryjson                 │  │
└─────────────────────────────────┘  │
                                     │
┌─────────────────────────────────┐  │
│     fsi_accessviolations        │  │
│─────────────────────────────────│  │
│ fsi_runid ──────────────────────│──┘
│ fsi_environmentguid ────────────│──┐
│ fsi_environmentname             │  │
│ fsi_zone                        │  │  same environment
│ fsi_violationtype               │  │
│ fsi_severity                    │  │
│ fsi_detectedat                  │  │
└─────────────────────────────────┘  │
                                     │
┌─────────────────────────────────┐  │
│      fsi_accessbaselines        │  │
│─────────────────────────────────│  │
│ fsi_environmentguid ────────────│──┘
│ fsi_environmentname             │
│ fsi_zone                        │
│ fsi_botlimitsharingmode         │
│ fsi_isactive                    │
│ fsi_capturedat                  │
└─────────────────────────────────┘
```

Violations link to validation runs via `fsi_runid`. Violations and baselines share `fsi_environmentguid` to correlate access settings with detected issues.
