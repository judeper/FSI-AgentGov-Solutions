# HITL Workflow Governance - Dataverse Schema

Auto-generated schema documentation. Do not edit manually.

## Option Sets

### Shared Option Sets (reused from ACV)

| Option Set | Values |
|-----------|--------|
| fsi_acv_zone | Unclassified (0), Zone 1 (1), Zone 2 (2), Zone 3 (3) |
| fsi_acv_severity | Passed (1), Warning (2), GracePeriod (3), Failed (4), Error (5) |

### HWG-Specific Option Sets

| Option Set | Values |
|-----------|--------|
| fsi_HWG_checkpointtype | RequestForInformation (100000000), MultistageApproval (100000001), CustomHitl (100000002) |
| fsi_HWG_checkpointstatus | Present (100000000), Missing (100000001), Partial (100000002), UnableToDetermine (100000003) |
| fsi_HWG_violationstatus | Open (100000000), Acknowledged (100000001), Excepted (100000002), Resolved (100000003) |

## Tables

### HITL Checkpoint Result (`fsi_HitlCheckpointResult`)

**Ownership:** UserOwned
**Description:** Per-agent HITL checkpoint scan results tracking Human in the Loop checkpoint presence for agent flows across Power Platform environments

| Column (SchemaName) | Type | Required | Description |
|-------------------|------|----------|-------------|
| fsi_Name | String(200) | Yes | Primary name attribute |
| fsi_EnvironmentGuid | String(100) | Yes | Power Platform environment GUID |
| fsi_EnvironmentName | String(500) | Yes | Environment display name |
| fsi_Zone | Picklist (fsi_acv_zone) | Yes | Zone classification |
| fsi_AgentId | String(100) | Yes | Copilot Studio bot GUID |
| fsi_AgentName | String(500) | Yes | Agent display name |
| fsi_FlowName | String(500) | No | Agent flow name |
| fsi_FlowId | String(100) | No | Agent flow GUID |
| fsi_CheckpointType | Picklist (fsi_HWG_checkpointtype) | Yes | Type of HITL checkpoint |
| fsi_CheckpointName | String(500) | No | Name of the HITL action/step |
| fsi_CheckpointStatus | Picklist (fsi_HWG_checkpointstatus) | Yes | Whether checkpoint is present/missing |
| fsi_AssignedReviewers | String(2000) | No | Configured reviewer email addresses |
| fsi_InputCount | Integer | No | Number of RFI inputs configured |
| fsi_HasHitlCheckpoint | Boolean (default: false) | Yes | Whether agent flow has at least one HITL checkpoint |
| fsi_ViolationStatus | Picklist (fsi_HWG_violationstatus) | Yes | Current violation lifecycle status |
| fsi_ViolationType | String(200) | No | e.g., MissingHitlCheckpoint, MissingReviewer, InsufficientInputs |
| fsi_Severity | String(50) | Yes | Critical/High/Medium/Warning |
| fsi_RegulatoryContext | String(2000) | No | FINRA/SOX regulatory impact context |
| fsi_DetectedAt | DateTime | Yes | When detected |
| fsi_RunId | String(36) | No | Correlating scan GUID |

### HITL Checkpoint Exception (`fsi_HitlCheckpointException`)

**Ownership:** UserOwned
**Description:** Approved exceptions for agents not requiring HITL checkpoints, with expiration and audit trail

| Column (SchemaName) | Type | Required | Description |
|-------------------|------|----------|-------------|
| fsi_Name | String(200) | Yes | Primary name attribute |
| fsi_EnvironmentGuid | String(100) | No | Power Platform environment GUID (optional for global exceptions) |
| fsi_AgentId | String(100) | No | Copilot Studio bot GUID (optional for broad exceptions) |
| fsi_FlowName | String(500) | No | Agent flow name (optional filter) |
| fsi_Zone | Picklist (fsi_acv_zone) | Yes | Zone this exception applies to |
| fsi_ExceptionScope | String(200) | Yes | Scope (AllFlows, SpecificFlow, ReadOnlyActions) |
| fsi_ApprovedBy | String(200) | Yes | UPN of approving administrator |
| fsi_ApprovedAt | DateTime | Yes | When approved |
| fsi_ExpiresAt | DateTime | No | Exception expiration date (optional) |
| fsi_Justification | Memo(5000) | No | Business justification for the exception |
| fsi_IsActive | Boolean (default: true) | Yes | Whether this exception is currently active |

### HITL Scan Run (`fsi_HitlScanRun`)

**Ownership:** OrganizationOwned
**Description:** Immutable scan execution audit trail for regulatory evidence (supports compliance with FINRA Rule 4511(a), SEC Rule 17a-3)

| Column (SchemaName) | Type | Required | Description |
|-------------------|------|----------|-------------|
| fsi_Name | String(200) | Yes | Primary name attribute |
| fsi_RunId | String(36) | Yes | GUID correlating all records in one scan run |
| fsi_ScanTime | DateTime | Yes | When scan executed |
| fsi_TotalAgents | Integer | Yes | Total agents scanned |
| fsi_TotalFlows | Integer | Yes | Total agent flows evaluated |
| fsi_AgentsWithHitl | Integer | No | Agents with at least one HITL checkpoint |
| fsi_AgentsMissingHitl | Integer | No | Agents missing required HITL checkpoints |
| fsi_TotalCheckpoints | Integer | No | Total HITL checkpoints found across all agents |
| fsi_CompliantCount | Integer | No | Number of compliant agents in this scan run |
| fsi_CheckpointsFound | Integer | Yes | HITL checkpoints detected |
| fsi_CheckpointsMissing | Integer | Yes | Required HITL checkpoints not found |
| fsi_ViolationCount | Integer | Yes | Total violations detected in this scan run |
| fsi_OverallStatus | String(50) | Yes | Passed/Failed/Warning/Critical |
| fsi_EnvironmentsScanned | String(2000) | No | Comma-separated environments covered |
| fsi_SummaryJson | Memo(100000) | No | Full JSON summary blob |
