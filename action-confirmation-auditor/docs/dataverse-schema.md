# Action Confirmation Auditor - Dataverse Schema

Auto-generated schema documentation. Do not edit manually.

## Option Sets

### Shared Option Sets (reused from ACV)

| Option Set | Values |
|-----------|--------|
| fsi_acv_zone | Unclassified (0), Zone 1 (1), Zone 2 (2), Zone 3 (3) |
| fsi_acv_severity | Passed (1), Warning (2), GracePeriod (3), Failed (4), Error (5) |

### ACA-Specific Option Sets

| Option Set | Values |
|-----------|--------|
| fsi_ACA_actiontype | ConnectorAction (100000000), CloudFlowAction (100000001), PluginAction (100000002), CustomAction (100000003), HttpRequest (100000004) |
| fsi_ACA_confirmationstatus | Present (100000000), Missing (100000001), Partial (100000002), UnableToDetermine (100000003) |
| fsi_ACA_violationstatus | Open (100000000), Acknowledged (100000001), Excepted (100000002), Resolved (100000003) |

## Tables

### Action Audit Result (`fsi_ActionAuditResult`)

**Ownership:** UserOwned
**Description:** Per-action violation records tracking step-up confirmation presence for agent operations across Power Platform environments

| Column (SchemaName) | Type | Required | Description |
|-------------------|------|----------|-------------|
| fsi_Name | String(200) | Yes | Primary name attribute |
| fsi_EnvironmentGuid | String(100) | Yes | Power Platform environment GUID |
| fsi_EnvironmentName | String(500) | Yes | Environment display name |
| fsi_Zone | Picklist (fsi_acv_zone) | Yes | Zone classification |
| fsi_AgentId | String(100) | Yes | Copilot Studio bot GUID |
| fsi_AgentName | String(500) | Yes | Agent display name |
| fsi_TopicName | String(500) | No | Name of the topic containing the action |
| fsi_TopicId | String(100) | No | GUID of the topic containing the action |
| fsi_ActionName | String(500) | Yes | Name of the action being audited |
| fsi_ActionType | Picklist (fsi_ACA_actiontype) | Yes | Type of action (ConnectorAction/CloudFlowAction/etc.) |
| fsi_ConnectorName | String(500) | No | Connector name if action is a connector action |
| fsi_HttpMethod | String(20) | No | HTTP method for HTTP request actions |
| fsi_RiskLevel | String(50) | Yes | Zone-based risk level (hardcoded in v1.0) |
| fsi_ConfirmationStatus | Picklist (fsi_ACA_confirmationstatus) | Yes | Whether step-up confirmation is present/missing/partial |
| fsi_ViolationStatus | Picklist (fsi_ACA_violationstatus) | Yes | Current violation lifecycle status |
| fsi_ViolationType | String(200) | No | Violation type identifier (e.g., MissingConfirmation, MissingUserDefinedActionMessage) |
| fsi_Severity | String(50) | Yes | Violation severity (Critical/High/Medium/Warning) |
| fsi_RegulatoryContext | String(2000) | No | FINRA/SOX/GLBA regulatory impact context |
| fsi_DetectedAt | DateTime | Yes | When violation was detected |
| fsi_RunId | String(36) | No | Correlating scan GUID |

### Action Confirmation Exception (`fsi_ActionConfirmationException`)

**Ownership:** UserOwned
**Description:** Approved exceptions for actions that do not require step-up confirmation, with expiration and audit trail

| Column (SchemaName) | Type | Required | Description |
|-------------------|------|----------|-------------|
| fsi_Name | String(200) | Yes | Primary name attribute |
| fsi_EnvironmentGuid | String(100) | No | Power Platform environment GUID (optional for global exceptions) |
| fsi_AgentId | String(100) | No | Copilot Studio bot GUID (optional for broad exceptions) |
| fsi_ActionName | String(500) | Yes | Name of the excepted action |
| fsi_ActionType | Picklist (fsi_ACA_actiontype) | No | Type of action (optional filter) |
| fsi_ConnectorName | String(500) | No | Connector name (optional filter) |
| fsi_Zone | Picklist (fsi_acv_zone) | Yes | Zone this exception applies to |
| fsi_ApprovedBy | String(200) | Yes | UPN of approving administrator |
| fsi_ApprovedAt | DateTime | Yes | When exception was approved |
| fsi_ExpiresAt | DateTime | No | Exception expiration date (optional) |
| fsi_Justification | Memo(5000) | No | Business justification for the exception |
| fsi_RejectedBy | String(200) | No | UPN of administrator who rejected the exception |
| fsi_ApprovalNotes | Memo(5000) | No | Approver comments on approval decision |
| fsi_RejectionNotes | Memo(5000) | No | Approver comments on rejection decision |
| fsi_IsActive | Boolean (default: true) | Yes | Whether this exception is currently active |

### Action Scan Run (`fsi_ActionScanRun`)

**Ownership:** OrganizationOwned
**Description:** Immutable scan execution audit trail for regulatory evidence (supports compliance with FINRA 4511, SEC 17a-3)

| Column (SchemaName) | Type | Required | Description |
|-------------------|------|----------|-------------|
| fsi_Name | String(200) | Yes | Primary name attribute |
| fsi_RunId | String(36) | Yes | GUID correlating all records in one scan run |
| fsi_ValidationTime | DateTime | Yes | When scan executed |
| fsi_TotalAgents | Integer | Yes | Total agents scanned |
| fsi_TotalActions | Integer | Yes | Total actions evaluated across all agents |
| fsi_ActionsWithConfirmation | Integer | Yes | Actions that have step-up confirmation configured |
| fsi_ActionsMissingConfirmation | Integer | Yes | Actions missing required step-up confirmation |
| fsi_ViolationCount | Integer | Yes | Total violations detected in this scan run |
| fsi_OverallStatus | String(50) | Yes | Passed/Failed/Warning/Critical |
| fsi_EnvironmentsScanned | String(2000) | No | Comma-separated environments covered |
| fsi_SummaryJson | Memo(100000) | No | Full JSON summary blob |
