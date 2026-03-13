# Dataverse Schema Reference

## Tables

### fsi_fileupload_baseline

**Ownership:** UserOwned
**Purpose:** Approved file upload configuration baseline per agent. Captures the "known good" state that automated validation compares against for drift detection.

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_agent_id` | String(200) | Yes | Copilot Studio agent ID |
| `fsi_agent_name` | String(500) | No | Agent display name |
| `fsi_environment_id` | String(200) | No | Power Platform environment ID |
| `fsi_environment_name` | String(500) | No | Environment display name |
| `fsi_zone` | Picklist | No | Governance zone (fsi_acv_zone: Zone 1/2/3) |
| `fsi_file_upload_enabled` | Boolean | No | Whether file upload is enabled |
| `fsi_content_moderation_level` | String(50) | No | Content moderation level (Low/Medium/High/Highest) |
| `fsi_baseline_captured_on` | DateTime | No | When baseline was captured |
| `fsi_baseline_captured_by` | String(200) | No | Who captured the baseline |
| `fsi_owner_email` | String(320) | No | Agent owner email |
| `fsi_notes` | Memo(10000) | No | Notes |

### fsi_fileupload_validationhistory

**Ownership:** OrganizationOwned (immutable audit trail)
**Purpose:** Immutable record of each compliance validation scan. Supports FINRA 4511 audit trail requirements.

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_run_id` | String(100) | Yes | Unique validation run identifier |
| `fsi_run_timestamp` | DateTime | No | When the scan ran |
| `fsi_validation_time` | DateTime | No | Validation completion time (written by flow and FUSClient) |
| `fsi_total_agents` | Integer | No | Total agents scanned |
| `fsi_compliant_count` | Integer | No | Agents passing validation |
| `fsi_violation_count` | Integer | No | Agents with violations |
| `fsi_file_upload_enabled_count` | Integer | No | Agents with file uploads enabled |
| `fsi_overall_status` | String(50) | No | Overall validation status (Passed/Warning/Failed/Error) |
| `fsi_compliance_rate` | Decimal(2) | No | Compliance percentage (0-100) |
| `fsi_environments_scanned` | Integer | No | Number of environments scanned |
| `fsi_scan_duration_seconds` | Integer | No | Scan duration in seconds |
| `fsi_summary_json` | Memo(10000) | No | Full validation result as JSON |
| `fsi_notes` | Memo(10000) | No | Run notes |

### fsi_fileupload_violation

**Ownership:** UserOwned
**Purpose:** Active file upload policy violations requiring remediation. Each record represents a specific non-compliant configuration.

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_agent_id` | String(200) | Yes | Agent ID |
| `fsi_agent_name` | String(500) | No | Agent display name |
| `fsi_environment_id` | String(200) | No | Environment ID |
| `fsi_environment_name` | String(500) | No | Environment display name |
| `fsi_zone` | Picklist | No | Governance zone |
| `fsi_severity` | Picklist | No | Violation severity (fsi_acv_severity) |
| `fsi_violation_type` | String(100) | No | Type: Zone3_FileUploadEnabled_NoApproval, Zone3_FileUploadEnabled_InsufficientModeration, Zone2_FileUploadEnabled_InsufficientModeration, Zone2_FileUploadEnabled_NoApproval, Unknown_Zone_FileUploadEnabled, Zone1_NoModeration, EvaluationFailed |
| `fsi_file_upload_expected` | String(50) | No | Expected file upload status per zone (e.g., "Enabled", "Disabled", "Indeterminate") |
| `fsi_file_upload_actual` | String(50) | No | Actual file upload status (e.g., "Enabled", "Disabled", "Indeterminate") |
| `fsi_content_moderation_level` | String(50) | No | Current moderation level |
| `fsi_content_moderation_minimum` | String(50) | No | Minimum required moderation |
| `fsi_detected_on` | DateTime | No | When violation was detected |
| `fsi_run_id` | String(100) | No | Associated validation run |
| `fsi_owner_email` | String(320) | No | Agent owner email |
| `fsi_remediation_notes` | Memo(10000) | No | Remediation guidance |
| `fsi_resolved` | Boolean | No | Whether violation is resolved |
| `fsi_resolved_on` | DateTime | No | When violation was resolved |

## Shared Option Sets

These option sets are shared across ACV/SSC/AAM/CMM/FUS solutions:

### fsi_acv_zone

| Value | Label |
|-------|-------|
| 1 | Zone 1 - Personal |
| 2 | Zone 2 - Team |
| 3 | Zone 3 - Enterprise |

### fsi_acv_severity

| Value | Label |
|-------|-------|
| 0 | Info |
| 1 | Low |
| 2 | Medium |
| 3 | High |
| 4 | Critical |

## Environment Variables

| Schema Name | Type | Default | Description |
|-------------|------|---------|-------------|
| `fsi_FUS_GracePeriodHours` | Decimal | 24 | Hours before drift violations are raised. Note: Dataverse env var default is 24; PowerShell scripts default to 48 if env var is not set. The Dataverse value takes precedence at runtime. |
| `fsi_FUS_ScanFrequencyHours` | Decimal | 24 | Automated scan interval |
| `fsi_FUS_IncludeSandbox` | String | false | Include sandbox environments |
| `fsi_FUS_IncludeDrafts` | String | false | Include draft agents |
| `fsi_FUS_BaselineMaxAgeDays` | Decimal | 90 | Max baseline age before stale |
| `fsi_FUS_TeamsGroupId` | String | — | Teams group for alerts |
| `fsi_FUS_TeamsChannelId` | String | — | Teams channel for alerts |

## Connection References

| Logical Name | Connector | Purpose |
|-------------|-----------|---------|
| `fsi_cr_dataverse_fileuploadsecurity` | Dataverse | Baseline/violation storage |
| `fsi_cr_office365_fileuploadsecurity` | Office 365 | Email notifications |
| `fsi_cr_teams_fileuploadsecurity` | Teams | Adaptive card alerts |
| `fsi_cr_azureautomation_fileuploadsecurity` | Azure Automation | Runbook trigger and monitoring |

---

*File Upload Security Configurator — Schema Reference*
