# Dataverse Schema Reference

## Overview

The Agent Access Governance Monitor uses three Dataverse tables to store access baselines, validation history, and violation records. Tables share option sets with the Agent Configuration Validator (ACV) solution for consistent zone and severity classification.

## Tables

### fsi_accessbaselines

Stores captured access configuration snapshots for each Power Platform environment. Only one active baseline exists per environment at a time.

| Column | Type | Description |
|--------|------|-------------|
| `fsi_environment_guid` | String | Power Platform environment unique identifier |
| `fsi_environment_name` | String | Display name of the environment |
| `fsi_zone` | Picklist | Governance zone classification (fsi_acv_zone) |
| `fsi_bot_limit_sharing_mode` | String | Agent sharing limit setting at capture time |
| `fsi_bot_authoring_sharing_disabled` | Boolean | Whether agent authoring sharing is disabled |
| `fsi_bot_published_limit_sharing_mode` | String | Published agent sharing limit at capture time |
| `fsi_captured_by` | String | UPN or service principal that captured the baseline |
| `fsi_captured_at` | DateTime | Timestamp of baseline capture (UTC) |
| `fsi_is_active` | Boolean | Whether this is the current active baseline |
| `fsi_raw_json` | Memo | Full JSON payload of access settings at capture time |

### fsi_accessvalidationhistory

Immutable audit trail of validation run results. Each record represents one complete validation scan across all environments.

| Column | Type | Description |
|--------|------|-------------|
| `fsi_name` | String | Run display name (auto-generated) |
| `fsi_run_id` | String | Unique GUID identifying the validation run |
| `fsi_zone` | Picklist | Governance zone at time of validation (fsi_acv_zone) (reserved — not currently populated) |
| `fsi_severity` | Picklist | Overall validation result severity (fsi_acv_severity) (reserved — not currently populated) |
| `fsi_validation_time` | DateTime | Timestamp of validation execution (UTC) |
| `fsi_total_environments` | Integer | Number of environments scanned |
| `fsi_compliant_count` | Integer | Environments meeting zone requirements |
| `fsi_violation_count` | Integer | Environments with access violations |
| `fsi_overall_status` | String | Aggregate status (Passed, Warning, Failed, Review) |
| `fsi_summary_json` | Memo | Per-zone breakdown as JSON (Total, Compliant, Violations per zone) |

### fsi_accessviolations

Individual access policy violations detected during validation. Linked to validation runs via `fsi_run_id`.

| Column | Type | Description |
|--------|------|-------------|
| `fsi_name` | String | Violation display name (auto-generated) |
| `fsi_run_id` | String | Links to fsi_accessvalidationhistory run |
| `fsi_environment_guid` | String | Environment where violation was detected |
| `fsi_environment_name` | String | Display name of the environment |
| `fsi_zone` | Picklist | Governance zone of the environment (fsi_acv_zone) |
| `fsi_violation_type` | String | Setting that violated policy (e.g., `bot-limitSharingMode`) |
| `fsi_expected_value` | String | Required value per zone policy |
| `fsi_actual_value` | String | Current environment setting value |
| `fsi_severity` | Picklist | Severity classification (fsi_acv_severity) |
| `fsi_regulatory_context` | String | Applicable regulations (e.g., FINRA 4511, SOX 404) |
| `fsi_detected_at` | DateTime | Timestamp of violation detection (UTC) |
| `fsi_acknowledged` | Boolean | Whether the violation has been acknowledged |
| `fsi_acknowledged_by` | String | Identity that acknowledged the violation |
| `fsi_acknowledged_on` | DateTime | When the violation was acknowledged |
| `fsi_resolved_at` | DateTime | When the violation was resolved |
| `fsi_notes` | Memo | Administrator notes on this violation |

## Option Sets (Shared with ACV)

### fsi_acv_zone

| Value | Label |
|-------|-------|
| 0 | Unclassified |
| 1 | Zone 1 |
| 2 | Zone 2 |
| 3 | Zone 3 |

### fsi_acv_severity

| Value | Label |
|-------|-------|
| 1 | Critical — immediate remediation required |
| 2 | High — remediation within SLA |
| 3 | Warning — review recommended |
| 4 | Info — no action required |

## Environment Variables

| Schema Name | Type | Default | Purpose |
|-------------|------|---------|---------|
| `fsi_AAM_GracePeriodHours` | Decimal | 48 | Hours to exclude newly provisioned environments |
| `fsi_AAM_ScanFrequencyHours` | Decimal | 24 | Interval in hours between automated access compliance scans |
| `fsi_AAM_IncludeSandbox` | String | false | Include sandbox environments in validation |
| `fsi_AAM_BaselineMaxAgeDays` | Decimal | 30 | Alert threshold in days for stale access baselines |
| `fsi_AAM_TeamsGroupId` | String | (empty) | Microsoft Teams group GUID for compliance alert notifications |
| `fsi_AAM_TeamsChannelId` | String | (empty) | Microsoft Teams channel GUID for compliance alert notifications |

## Connection References

| Schema Name | Connector | Purpose |
|-------------|-----------|---------|
| `fsi_cr_dataverse_accessmonitor` | Dataverse | Read/write validation history, violations, baselines |
| `fsi_cr_office365_accessmonitor` | Office 365 Outlook | Email alerts for compliance violations |
| `fsi_cr_teams_accessmonitor` | Microsoft Teams | Adaptive card alerts for drift detection |
| `fsi_cr_azureautomation_accessmonitor` | Azure Automation | Triggering and monitoring validation runbook jobs |

## Entity Relationship Diagram

```
┌─────────────────────────────────┐
│   fsi_accessvalidationhistory   │
│─────────────────────────────────│
│ fsi_run_id (PK, unique)        │──┐
│ fsi_validation_time             │  │
│ fsi_total_environments          │  │
│ fsi_compliant_count             │  │  matched by
│ fsi_violation_count             │  │  fsi_run_id
│ fsi_overall_status              │  │
│ fsi_summary_json                │  │
└─────────────────────────────────┘  │
                                     │
┌─────────────────────────────────┐  │
│     fsi_accessviolations        │  │
│─────────────────────────────────│  │
│ fsi_run_id ─────────────────────│──┘
│ fsi_environment_guid ───────────│──┐
│ fsi_environment_name            │  │
│ fsi_zone                        │  │  same environment
│ fsi_violation_type              │  │
│ fsi_severity                    │  │
│ fsi_detected_at                 │  │
└─────────────────────────────────┘  │
                                     │
┌─────────────────────────────────┐  │
│      fsi_accessbaselines        │  │
│─────────────────────────────────│  │
│ fsi_environment_guid ───────────│──┘
│ fsi_environment_name            │
│ fsi_zone                        │
│ fsi_bot_limit_sharing_mode      │
│ fsi_is_active                   │
│ fsi_captured_at                 │
└─────────────────────────────────┘
```

Violations link to validation runs via `fsi_run_id`. Violations and baselines share `fsi_environment_guid` to correlate access settings with detected issues.
