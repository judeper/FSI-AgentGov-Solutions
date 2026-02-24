# Agent Communication Restriction Detector - Dataverse Schema

Auto-generated schema documentation. Do not edit manually.

## Option Sets

### Shared Option Sets (reused from ACV)

| Option Set | Values |
|-----------|--------|
| fsi_acv_zone | Unclassified (0), Zone 1 (1), Zone 2 (2), Zone 3 (3) |
| fsi_acv_severity | Passed (1), Warning (2), GracePeriod (3), Failed (4), Error (5) |

### ACRD-Specific Option Sets

| Option Set | Values |
|-----------|--------|
| fsi_ACRD_violationtype | ZONE_BOUNDARY_VIOLATION (100000000), CROSS_TENANT_VIOLATION (100000001), CROSS_ENVIRONMENT_UNAPPROVED (100000002), MAKER_CHECKER_VIOLATION (100000003) |
| fsi_ACRD_violationstatus | Open (100000000), Acknowledged (100000001), Remediated (100000002), Excepted (100000003) |
| fsi_ACRD_directiontype | OneWay (100000000), Bidirectional (100000001) |
| fsi_ACRD_exceptionstatus | Pending (100000000), Approved (100000001), Denied (100000002), Expired (100000003) |

## Tables

### Agent Comm Violation (`fsi_AgentCommViolation`)

**Ownership:** UserOwned
**Description:** Communication restriction violations detected between agents across zones, environments, or tenants

| Column (SchemaName) | Type | Required | Description |
|-------------------|------|----------|-------------|
| fsi_Name | String(200) | Yes | Primary name attribute |
| fsi_CallingAgentId | String(100) | Yes | GUID of the agent initiating the communication |
| fsi_CallingAgentName | String(500) | Yes | Display name of the calling agent |
| fsi_CalledAgentId | String(100) | Yes | GUID of the agent being called |
| fsi_CalledAgentName | String(500) | Yes | Display name of the called agent |
| fsi_CallingAgentZone | Picklist (fsi_acv_zone) | Yes | Zone classification of the calling agent |
| fsi_CalledAgentZone | Picklist (fsi_acv_zone) | Yes | Zone classification of the called agent |
| fsi_CallingEnvironmentId | String(100) | Yes | Environment GUID of the calling agent |
| fsi_CalledEnvironmentId | String(100) | Yes | Environment GUID of the called agent |
| fsi_ViolationType | Picklist (fsi_ACRD_violationtype) | Yes | Type of communication restriction violation |
| fsi_ViolationStatus | Picklist (fsi_ACRD_violationstatus) | Yes | Current status of the violation |
| fsi_Severity | String(50) | Yes | Violation severity (Critical/High/Medium/Warning) |
| fsi_SkillManifestUrl | String(2000) | No | URL to the skill manifest triggering the violation |
| fsi_MakerCheckViolation | Boolean (default: false) | Yes | Whether this violation involves a maker-checker policy breach |
| fsi_RegulatoryContext | String(2000) | No | FINRA/SOX/GLBA regulatory impact context |
| fsi_DetectedAt | DateTime | Yes | When the violation was detected |
| fsi_RunId | String(36) | No | Correlating scan GUID |
| fsi_Notes | Memo(5000) | No | Additional notes or remediation context |

### Approved Comm Route (`fsi_ApprovedCommRoute`)

**Ownership:** OrganizationOwned
**Description:** Approved zone-to-zone communication routing matrix defining permitted agent interaction paths

| Column (SchemaName) | Type | Required | Description |
|-------------------|------|----------|-------------|
| fsi_Name | String(200) | Yes | Primary name attribute |
| fsi_SourceZone | Picklist (fsi_acv_zone) | Yes | Zone classification of the source agent |
| fsi_TargetZone | Picklist (fsi_acv_zone) | Yes | Zone classification of the target agent |
| fsi_DirectionType | Picklist (fsi_ACRD_directiontype) | Yes | Whether the route is one-way or bidirectional |
| fsi_AllowCrossEnvironment | Boolean (default: false) | Yes | Whether cross-environment communication is permitted on this route |
| fsi_IsActive | Boolean (default: true) | Yes | Whether this approved route is currently active |
| fsi_ApprovedBy | String(200) | Yes | UPN of the administrator who approved this route |
| fsi_ApprovedAt | DateTime | Yes | When the route was approved |
| fsi_ExpiresAt | DateTime | No | Route approval expiration date (optional) |
| fsi_Notes | Memo(5000) | No | Additional notes or justification for approval |

### Agent Skill Registration (`fsi_AgentSkillRegistration`)

**Ownership:** OrganizationOwned
**Description:** Point-in-time skill configuration snapshots for agents, capturing inter-agent communication capabilities

| Column (SchemaName) | Type | Required | Description |
|-------------------|------|----------|-------------|
| fsi_Name | String(200) | Yes | Primary name attribute |
| fsi_AgentId | String(100) | Yes | Copilot Studio bot GUID |
| fsi_AgentName | String(500) | Yes | Agent display name |
| fsi_EnvironmentId | String(100) | Yes | Power Platform environment GUID |
| fsi_EnvironmentName | String(500) | Yes | Environment display name |
| fsi_Zone | Picklist (fsi_acv_zone) | Yes | Zone classification of the agent |
| fsi_SkillName | String(500) | Yes | Name of the registered skill |
| fsi_TargetAgentId | String(100) | No | GUID of the target agent for this skill |
| fsi_TargetAgentName | String(500) | No | Display name of the target agent |
| fsi_TargetEnvironmentId | String(100) | No | Environment GUID of the target agent |
| fsi_ManifestUrl | String(2000) | No | URL to the skill manifest definition |
| fsi_CapturedAt | DateTime | Yes | When the skill registration snapshot was captured |
| fsi_RunId | String(36) | No | Correlating scan GUID |
| fsi_RawJson | Memo(100000) | No | Full JSON snapshot of the skill configuration |

### Comm Exception (`fsi_CommException`)

**Ownership:** UserOwned
**Description:** Approved exceptions to communication restriction policies with justification and expiration tracking

| Column (SchemaName) | Type | Required | Description |
|-------------------|------|----------|-------------|
| fsi_Name | String(200) | Yes | Primary name attribute |
| fsi_CallingAgentId | String(100) | No | GUID of the calling agent (optional for zone-level exceptions) |
| fsi_CalledAgentId | String(100) | No | GUID of the called agent (optional for zone-level exceptions) |
| fsi_SourceZone | Picklist (fsi_acv_zone) | Yes | Zone classification of the source |
| fsi_TargetZone | Picklist (fsi_acv_zone) | Yes | Zone classification of the target |
| fsi_ExceptionStatus | Picklist (fsi_ACRD_exceptionstatus) | Yes | Current status of the exception request |
| fsi_Justification | Memo(5000) | No | Business justification for the exception |
| fsi_ApprovedBy | String(200) | No | UPN of the administrator who approved the exception |
| fsi_ApprovedAt | DateTime | No | When the exception was approved |
| fsi_ExpiresAt | DateTime | No | Exception expiration date (optional) |
| fsi_IsActive | Boolean (default: true) | Yes | Whether this exception is currently active |

### Comm Scan Run (`fsi_CommScanRun`)

**Ownership:** OrganizationOwned
**Description:** Immutable scan summary records for regulatory evidence (supports compliance with FINRA 4511, SEC 17a-3)

| Column (SchemaName) | Type | Required | Description |
|-------------------|------|----------|-------------|
| fsi_Name | String(200) | Yes | Primary name attribute |
| fsi_RunId | String(36) | Yes | GUID correlating all records in one scan run |
| fsi_ValidationTime | DateTime | Yes | When scan executed |
| fsi_TotalAgents | Integer | Yes | Total agents scanned |
| fsi_TotalSkills | Integer | Yes | Total skills discovered across all agents |
| fsi_ViolationCount | Integer | Yes | Communication restriction violations detected |
| fsi_OverallStatus | String(50) | Yes | Passed/Failed/Warning/Critical |
| fsi_EnvironmentsScanned | String(2000) | No | Comma-separated environments covered |
| fsi_SummaryJson | Memo(100000) | No | Full JSON summary blob |
