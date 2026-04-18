# Agent Registry Automation — Dataverse Schema

> Auto-generated from `scripts/create_dataverse_schema.py`. Do not hand-edit.
> Regenerate with: `python scripts/create_dataverse_schema.py --output-docs docs/dataverse-schema.md`

## Tables

### `fsi_agentinventory` — Agent Inventory

- **Schema name:** `fsi_AgentInventory`
- **Entity set name (OData):** `fsi_agentinventories`
- **Ownership:** UserOwned
- **Primary name attribute:** `fsi_name` (ApplicationRequired, String(500))
- **Description:** Master agent registry for governance tracking and lifecycle management

| Logical name | Schema name | Type | Required | Description |
|--------------|-------------|------|----------|-------------|
| `fsi_agentid` | `fsi_AgentId` | String(100) | Yes | Copilot Studio bot GUID |
| `fsi_environmentid` | `fsi_EnvironmentId` | String(100) | Yes | Power Platform environment ID |
| `fsi_agentname` | `fsi_AgentName` | String(500) | Yes | Agent display name |
| `fsi_environmentname` | `fsi_EnvironmentName` | String(500) | Yes | Environment display name |
| `fsi_agentendpointurl` | `fsi_AgentEndpointUrl` | String(2000) | No | Bot Framework endpoint URL |
| `fsi_registrationstatus` | `fsi_RegistrationStatus` | Choice | Yes | Agent registration lifecycle status |
| `fsi_publishedstatus` | `fsi_PublishedStatus` | Choice | Yes | Agent published state |
| `fsi_zone` | `fsi_Zone` | Choice | Yes | Zone classification |
| `fsi_riskrating` | `fsi_RiskRating` | Choice | No | Agent risk rating |
| `fsi_ownerupn` | `fsi_OwnerUpn` | String(200) | Yes | Agent owner user principal name |
| `fsi_ownerdisplayname` | `fsi_OwnerDisplayName` | String(500) | No | Owner display name |
| `fsi_isorphaned` | `fsi_IsOrphaned` | Boolean | Yes | Whether the agent has no active owner |
| `fsi_entraregistrystatus` | `fsi_EntraRegistryStatus` | String(200) | No | Microsoft Entra Agent Registry sync status |
| `fsi_lastscannedat` | `fsi_LastScannedAt` | DateTime | No | When the agent was last discovered by scan |
| `fsi_registeredat` | `fsi_RegisteredAt` | DateTime | No | When the agent was registered |
| `fsi_approvedby` | `fsi_ApprovedBy` | String(200) | No | Approver UPN |
| `fsi_notes` | `fsi_Notes` | Memo(10000) | No | Notes and comments |
| `fsi_rawjson` | `fsi_RawJson` | Memo(100000) | No | Full API response snapshot |

### `fsi_registrationrequest` — Registration Request

- **Schema name:** `fsi_RegistrationRequest`
- **Entity set name (OData):** `fsi_registrationrequests`
- **Ownership:** UserOwned
- **Primary name attribute:** `fsi_name` (ApplicationRequired, String(500))
- **Description:** Registration request tracking with SLA-driven approval workflow

| Logical name | Schema name | Type | Required | Description |
|--------------|-------------|------|----------|-------------|
| `fsi_agentid` | `fsi_AgentId` | String(100) | Yes | References fsi_agentinventory agent |
| `fsi_environmentid` | `fsi_EnvironmentId` | String(100) | Yes | Power Platform environment ID |
| `fsi_agentname` | `fsi_AgentName` | String(500) | Yes | Agent display name |
| `fsi_requestdate` | `fsi_RequestDate` | DateTime | Yes | When registration request was submitted |
| `fsi_requestedby` | `fsi_RequestedBy` | String(200) | Yes | Requester UPN |
| `fsi_approvalstatus` | `fsi_ApprovalStatus` | Choice | Yes | Registration approval status |
| `fsi_approvedby` | `fsi_ApprovedBy` | String(200) | No | Approver UPN |
| `fsi_approvedat` | `fsi_ApprovedAt` | DateTime | No | When approval was granted |
| `fsi_sladeadline` | `fsi_SlaDeadline` | DateTime | Yes | SLA deadline for approval decision |
| `fsi_escalationtarget` | `fsi_EscalationTarget` | String(200) | No | Skip-level escalation approver UPN |
| `fsi_escalationdate` | `fsi_EscalationDate` | DateTime | No | When the request was escalated |
| `fsi_zone` | `fsi_Zone` | Choice | Yes | Zone classification |
| `fsi_riskrating` | `fsi_RiskRating` | Choice | No | Agent risk rating |
| `fsi_justification` | `fsi_Justification` | Memo(10000) | No | Business justification for registration |
| `fsi_rejectionreason` | `fsi_RejectionReason` | Memo(5000) | No | Reason for rejection |

### `fsi_agentcomplianceevent` — Agent Compliance Event

- **Schema name:** `fsi_AgentComplianceEvent`
- **Entity set name (OData):** `fsi_agentcomplianceevents`
- **Ownership:** OrganizationOwned
- **Primary name attribute:** `fsi_name` (ApplicationRequired, String(500))
- **Description:** Immutable compliance event log for regulatory evidence (supports compliance with FINRA 4511, SEC 17a-3)

| Logical name | Schema name | Type | Required | Description |
|--------------|-------------|------|----------|-------------|
| `fsi_eventtype` | `fsi_EventType` | Choice | Yes | Event classification |
| `fsi_agentid` | `fsi_AgentId` | String(100) | Yes | Agent bot GUID |
| `fsi_environmentid` | `fsi_EnvironmentId` | String(100) | Yes | Power Platform environment ID |
| `fsi_agentname` | `fsi_AgentName` | String(500) | No | Agent display name |
| `fsi_eventtimestamp` | `fsi_EventTimestamp` | DateTime | Yes | When the event occurred |
| `fsi_actorupn` | `fsi_ActorUpn` | String(200) | No | UPN of person or system that performed the action |
| `fsi_details` | `fsi_Details` | Memo(50000) | No | JSON event details |
| `fsi_zone` | `fsi_Zone` | Choice | No | Zone classification |
| `fsi_frameworkversion` | `fsi_FrameworkVersion` | String(50) | No | FSI-AgentGov version tag |

### `fsi_ownershipaudit` — Ownership Audit

- **Schema name:** `fsi_OwnershipAudit`
- **Entity set name (OData):** `fsi_ownershipaudits`
- **Ownership:** OrganizationOwned
- **Primary name attribute:** `fsi_name` (ApplicationRequired, String(500))
- **Description:** Ownership change audit trail for agent lifecycle governance

| Logical name | Schema name | Type | Required | Description |
|--------------|-------------|------|----------|-------------|
| `fsi_agentid` | `fsi_AgentId` | String(100) | Yes | Agent bot GUID |
| `fsi_environmentid` | `fsi_EnvironmentId` | String(100) | Yes | Power Platform environment ID |
| `fsi_previousownerupn` | `fsi_PreviousOwnerUpn` | String(200) | Yes | Previous owner user principal name |
| `fsi_newownerupn` | `fsi_NewOwnerUpn` | String(200) | Yes | New owner user principal name |
| `fsi_changereason` | `fsi_ChangeReason` | String(500) | No | Reason for ownership change |
| `fsi_changedat` | `fsi_ChangedAt` | DateTime | Yes | When the ownership change occurred |
| `fsi_changedby` | `fsi_ChangedBy` | String(200) | No | System or user UPN that performed the change |
| `fsi_isorphanreassignment` | `fsi_IsOrphanReassignment` | Boolean | Yes | Whether this was an orphan agent reassignment |
| `fsi_details` | `fsi_Details` | Memo(10000) | No | Additional context |

## Option Sets

All option sets are global (cross-table) so the same numeric value can be used in OData filters across tables.

### `fsi_acv_zone`

| Label | Value |
|-------|-------|
| Unclassified | 100000000 |
| Zone 1 | 100000001 |
| Zone 2 | 100000002 |
| Zone 3 | 100000003 |

### `fsi_ara_registrationstatus`

| Label | Value |
|-------|-------|
| Unregistered | 100000000 |
| PendingApproval | 100000001 |
| Registered | 100000002 |
| Rejected | 100000003 |
| Decommissioned | 100000004 |

### `fsi_ara_publishedstatus`

| Label | Value |
|-------|-------|
| Published | 100000000 |
| Draft | 100000001 |
| Quarantined | 100000002 |
| Disabled | 100000003 |

### `fsi_ara_riskrating`

| Label | Value |
|-------|-------|
| Low | 100000000 |
| Medium | 100000001 |
| High | 100000002 |
| Critical | 100000003 |

### `fsi_ara_eventtype`

| Label | Value |
|-------|-------|
| Discovered | 100000000 |
| Registered | 100000001 |
| Approved | 100000002 |
| Rejected | 100000003 |
| Quarantined | 100000004 |
| SLA_Escalated | 100000005 |
| OrphanDetected | 100000006 |
| OwnerChanged | 100000007 |
| Decommissioned | 100000008 |
| EntraSynced | 100000009 |

### `fsi_ara_approvalstatus`

| Label | Value |
|-------|-------|
| Pending | 100000000 |
| Approved | 100000001 |
| Rejected | 100000002 |
| Escalated | 100000003 |
| Expired | 100000004 |

## Alternate Keys

- `fsi_agentinventory` — schema name `fsi_AgentEnvUniqueKey` (logical: `fsi_agentenvuniquekey`); key columns: `fsi_agentid`, `fsi_environmentid`

Use this alternate key for upsert-by-business-key:
```
PATCH /api/data/v9.2/fsi_agentinventories(fsi_agentid='<bot-guid>',fsi_environmentid='<env-guid>')
```
