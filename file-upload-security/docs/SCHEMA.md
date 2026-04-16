# Dataverse Schema Reference

## Tables

### fsi_fileuploadbaseline

**Ownership:** UserOwned
**Purpose:** Approved file upload configuration baseline per agent. Captures the "known good" state that automated validation compares against for drift detection.

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_agentid` | String(200) | Yes | Copilot Studio agent ID |
| `fsi_agentname` | String(500) | No | Agent display name |
| `fsi_environmentid` | String(200) | No | Power Platform environment ID |
| `fsi_environmentname` | String(500) | No | Environment display name |
| `fsi_zone` | Picklist | No | Governance zone (fsi_acv_zone: Zone 1/2/3) |
| `fsi_fileuploadenabled` | Boolean | No | Whether file upload is enabled |
| `fsi_contentmoderationlevel` | String(50) | No | Content moderation level (Low/Medium/High/Highest) |
| `fsi_baselinecapturedon` | DateTime | No | When baseline was captured |
| `fsi_baselinecapturedby` | String(200) | No | Who captured the baseline |
| `fsi_owneremail` | String(320) | No | Agent owner email |
| `fsi_notes` | Memo(10000) | No | Notes |

### fsi_fileuploadvalidationhistory

**Ownership:** OrganizationOwned (tamper-resistant audit trail)
**Purpose:** Append-only record of each compliance validation scan. Supports FINRA 4511 audit trail requirements.

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_runid` | String(100) | Yes | Unique validation run identifier |
| `fsi_runtimestamp` | DateTime | No | When the scan ran |
| `fsi_validationtime` | DateTime | No | Validation completion time (written by flow and FUSClient) |
| `fsi_totalagents` | Integer | No | Total agents scanned |
| `fsi_compliantcount` | Integer | No | Agents passing validation |
| `fsi_violationcount` | Integer | No | Agents with violations |
| `fsi_fileuploadenabledcount` | Integer | No | Agents with file uploads enabled |
| `fsi_overallstatus` | String(50) | No | Overall validation status (Passed/Warning/Failed/Error) |
| `fsi_compliancerate` | Decimal(2) | No | Compliance percentage (0-100) |
| `fsi_environmentsscanned` | Integer | No | Number of environments scanned |
| `fsi_scandurationseconds` | Integer | No | Scan duration in seconds |
| `fsi_summaryjson` | Memo(10000) | No | Full validation result as JSON |
| `fsi_notes` | Memo(10000) | No | Run notes |

### fsi_fileuploadviolation

**Ownership:** UserOwned
**Purpose:** Active file upload policy violations requiring remediation. Each record represents a specific non-compliant configuration.

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_agentid` | String(200) | Yes | Agent ID |
| `fsi_agentname` | String(500) | No | Agent display name |
| `fsi_environmentid` | String(200) | No | Environment ID |
| `fsi_environmentname` | String(500) | No | Environment display name |
| `fsi_zone` | Picklist | No | Governance zone |
| `fsi_severity` | Picklist | No | Violation severity (fsi_acv_severity) |
| `fsi_violationtype` | String(100) | No | Type: Zone3_FileUploadEnabled_NoApproval, Zone3_FileUploadEnabled_InsufficientModeration, Zone2_FileUploadEnabled_InsufficientModeration, Zone2_FileUploadEnabled_NoApproval, Unknown_Zone_FileUploadEnabled, Zone1_NoModeration, EvaluationFailed |
| `fsi_fileuploadexpected` | String(50) | No | Expected file upload status per zone (e.g., "Enabled", "Disabled", "Indeterminate") |
| `fsi_fileuploadactual` | String(50) | No | Actual file upload status (e.g., "Enabled", "Disabled", "Indeterminate") |
| `fsi_contentmoderationlevel` | String(50) | No | Current moderation level |
| `fsi_contentmoderationminimum` | String(50) | No | Minimum required moderation |
| `fsi_detectedon` | DateTime | No | When violation was detected |
| `fsi_runid` | String(100) | No | Associated validation run |
| `fsi_owneremail` | String(320) | No | Agent owner email |
| `fsi_remediationnotes` | Memo(10000) | No | Remediation guidance |
| `fsi_resolved` | Boolean | No | Whether violation is resolved |
| `fsi_resolvedon` | DateTime | No | When violation was resolved |

## Shared Option Sets

These option sets are shared across ACV/SSC/AAM/CMM/FUS solutions:

### fsi_acv_zone

| Value | Label |
|-------|-------|
| 100000000 | Zone 1 - Personal |
| 100000001 | Zone 2 - Team |
| 100000002 | Zone 3 - Enterprise |

### fsi_acv_severity

| Value | Label |
|-------|-------|
| 100000000 | Info |
| 100000001 | Low |
| 100000002 | Medium |
| 100000003 | High |
| 100000004 | Critical |
| 100000005 | Warning |

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
