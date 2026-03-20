# Dataverse Schema

Table definitions for the Agent Registry Automation solution.

---

## Schema Overview

```
┌───────────────────────┐       ┌───────────────────────────┐
│  fsi_agentinventory   │──────<│  fsi_registrationrequest  │
│  (master registry)    │       │  (approval tracking)      │
│                       │       └───────────────────────────┘
│  AK: fsi_agentid +   │
│      fsi_environmentid│       ┌───────────────────────────┐
│                       │──────<│  fsi_agentcomplianceevent │
└───────────┬───────────┘       │  (immutable audit log)    │
            │                   │  [LTR-enabled]            │
            │                   └───────────────────────────┘
            │
            ▼                   ┌───────────────────────────┐
┌───────────────────────┐──────<│  fsi_ownershipaudit       │
│  (owner reference)    │       │  (ownership changes)      │
└───────────────────────┘       └───────────────────────────┘

AK = Alternate Key
LTR = Long-Term Retention
```

---

## Table: fsi_agentinventory

Master agent registry. Each record represents a single AI agent discovered in a Power Platform environment.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_agentinventoryid` | Uniqueidentifier | Yes | Primary key (auto-generated) |
| `fsi_name` | String (200) | Yes | Agent display name |
| `fsi_agentid` | String (36) | Yes | Copilot Studio agent ID (GUID). Part of alternate key. |
| `fsi_environmentid` | String (36) | Yes | Power Platform environment ID (GUID). Part of alternate key. |
| `fsi_environmentname` | String (200) | No | Environment display name (populated during discovery) |
| `fsi_botframeworkendpoint` | String (500) | No | Bot Framework endpoint URL from Bots API response |
| `fsi_zone` | Choice | Yes | Governance zone classification |
| `fsi_registrationstatus` | Choice | Yes | Current registration status |
| `fsi_ownerid` | Lookup (User) | No | Current agent owner (Dataverse system user) |
| `fsi_ownerupn` | String (320) | No | Owner UPN (cached for orphan detection when user is disabled) |
| `fsi_ownerdepartment` | String (200) | No | Owner department (from Graph API) |
| `fsi_riskrating` | Choice | No | Risk classification for examiner reporting |
| `fsi_purpose` | Text (2000) | No | Declared agent purpose |
| `fsi_discoveredon` | DateTime | Yes | Timestamp when agent was first discovered |
| `fsi_registeredon` | DateTime | No | Timestamp when registration was approved |
| `fsi_lastscanned` | DateTime | No | Last discovery scan that confirmed agent existence |
| `fsi_isorphaned` | Boolean | No | Whether the agent has been flagged as orphaned |
| `fsi_orphanedon` | DateTime | No | Timestamp when agent was flagged as orphaned |
| `fsi_isquarantined` | Boolean | No | Whether the agent is currently quarantined |
| `fsi_quarantinedon` | DateTime | No | Timestamp when agent was quarantined |
| `fsi_quarantinereason` | String (500) | No | Reason for quarantine |
| `fsi_entrasynced` | Boolean | No | Whether agent has been synced to Entra Agent Registry |
| `fsi_entrasyncedon` | DateTime | No | Last Entra sync timestamp |
| `fsi_metadata` | Text (max) | No | JSON blob for extensible agent metadata |
| `createdon` | DateTime | Auto | Record creation timestamp |
| `modifiedon` | DateTime | Auto | Last modification timestamp |

### Alternate Key

| Key Name | Columns | Purpose |
|----------|---------|---------|
| `fsi_ak_agentinventory_agentenv` | `fsi_agentid`, `fsi_environmentid` | Enables upsert-based idempotent discovery. Flow 1 uses this key to create or update agent records without checking for existence first. |

> **Note:** After schema deployment, the alternate key status may show **Pending** for up to 30 minutes while Dataverse builds the index. Do not enable Flow 1 until the key status is **Active**. Check status in **Power Apps** > **Tables** > **Agent Inventory** > **Keys**.

### Choice: fsi_zone

| Value | Label |
|-------|-------|
| 10001 | Zone 1 — Personal Productivity |
| 10002 | Zone 2 — Team/Departmental |
| 10003 | Zone 3 — Enterprise/Customer-Facing |

### Choice: fsi_registrationstatus

| Value | Label |
|-------|-------|
| 10001 | Discovered |
| 10002 | Registration Pending |
| 10003 | Registered |
| 10004 | Quarantined |
| 10005 | Decommissioned |

### Choice: fsi_riskrating

| Value | Label |
|-------|-------|
| 10001 | Low |
| 10002 | Medium |
| 10003 | High |
| 10004 | Critical |

### Sample Data

```json
{
  "fsi_name": "Customer Service Agent",
  "fsi_agentid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "fsi_environmentid": "env-12345-abcd-6789-ef01-234567890abc",
  "fsi_environmentname": "Production - Customer Service",
  "fsi_zone": 10003,
  "fsi_registrationstatus": 10003,
  "fsi_ownerupn": "jane.smith@contoso.com",
  "fsi_ownerdepartment": "Customer Operations",
  "fsi_riskrating": 10003,
  "fsi_purpose": "Handles customer inquiries using approved knowledge base articles",
  "fsi_discoveredon": "2026-03-15T08:30:00Z",
  "fsi_registeredon": "2026-03-16T14:22:00Z",
  "fsi_lastscanned": "2026-03-20T06:00:00Z",
  "fsi_isorphaned": false,
  "fsi_isquarantined": false,
  "fsi_entrasynced": false
}
```

---

## Table: fsi_registrationrequest

Tracks registration and approval requests for discovered agents. Each request follows an SLA-driven workflow with optional escalation.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_registrationrequestid` | Uniqueidentifier | Yes | Primary key (auto-generated) |
| `fsi_name` | String (200) | Yes | Request title (auto-generated: "Registration — {AgentName}") |
| `fsi_agentinventoryid` | Lookup | Yes | Reference to the agent being registered |
| `fsi_requestedby` | Lookup (User) | Yes | User who initiated the registration |
| `fsi_requestedon` | DateTime | Yes | Request submission timestamp |
| `fsi_requeststatus` | Choice | Yes | Current request status |
| `fsi_zone` | Choice | Yes | Zone classification at time of request |
| `fsi_justification` | Text (2000) | Yes | Business justification for the agent |
| `fsi_approver` | String (320) | No | Assigned approver UPN |
| `fsi_approvaldeadline` | DateTime | No | SLA deadline for approval decision |
| `fsi_approvedon` | DateTime | No | Approval decision timestamp |
| `fsi_approvaloutcome` | Choice | No | Approval decision |
| `fsi_approvercomments` | Text (2000) | No | Approver notes or rejection reason |
| `fsi_escalatedto` | String (320) | No | Escalation approver UPN (if SLA exceeded) |
| `fsi_escalatedon` | DateTime | No | Escalation timestamp |
| `fsi_isescalated` | Boolean | No | Whether the request has been escalated |
| `createdon` | DateTime | Auto | Record creation timestamp |
| `modifiedon` | DateTime | Auto | Last modification timestamp |

### Choice: fsi_requeststatus

| Value | Label |
|-------|-------|
| 10001 | Submitted |
| 10002 | Under Review |
| 10003 | Approved |
| 10004 | Rejected |
| 10005 | Escalated |
| 10006 | Timed Out |
| 10007 | Cancelled |

### Choice: fsi_approvaloutcome

| Value | Label |
|-------|-------|
| 10001 | Approved |
| 10002 | Rejected |
| 10003 | Timed Out |

### Sample Data

```json
{
  "fsi_name": "Registration — Customer Service Agent",
  "fsi_requestedon": "2026-03-15T09:00:00Z",
  "fsi_requeststatus": 10003,
  "fsi_zone": 10003,
  "fsi_justification": "Required for customer-facing inquiry handling. Uses approved KB articles only.",
  "fsi_approver": "governance-committee@contoso.com",
  "fsi_approvaldeadline": "2026-03-22T09:00:00Z",
  "fsi_approvedon": "2026-03-16T14:22:00Z",
  "fsi_approvaloutcome": 10001,
  "fsi_approvercomments": "Approved — agent scope limited to Customer KB site.",
  "fsi_isescalated": false
}
```

---

## Table: fsi_agentcomplianceevent

Immutable compliance event log for all agent lifecycle actions. Designed for Dataverse Long-Term Retention (LTR) to support 7-year SEC 17a-3/4 retention requirements.

> **Important:** This table should be configured with Dataverse LTR after deployment. Records should not be modified or deleted once created. The table is append-only by design.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_agentcomplianceeventid` | Uniqueidentifier | Yes | Primary key (auto-generated) |
| `fsi_name` | String (200) | Yes | Event title (auto-generated) |
| `fsi_agentinventoryid` | Lookup | No | Reference to the agent (may be null for system-level events) |
| `fsi_eventtype` | Choice | Yes | Type of compliance event |
| `fsi_eventsource` | Choice | Yes | Which flow or process generated the event |
| `fsi_eventdetails` | Text (max) | No | JSON blob with event-specific details |
| `fsi_severity` | Choice | Yes | Event severity |
| `fsi_actorupn` | String (320) | No | UPN of the user or service that triggered the event |
| `fsi_environmentid` | String (36) | No | Environment where the event occurred |
| `fsi_zone` | Choice | No | Zone classification at time of event |
| `fsi_correlationid` | String (36) | No | Correlation ID for tracing related events |
| `fsi_occurredon` | DateTime | Yes | Timestamp when the event occurred |
| `createdon` | DateTime | Auto | Record creation timestamp |

### Choice: fsi_eventtype

| Value | Label |
|-------|-------|
| 10001 | Agent Discovered |
| 10002 | Registration Requested |
| 10003 | Registration Approved |
| 10004 | Registration Rejected |
| 10005 | Agent Quarantined |
| 10006 | Agent Decommissioned |
| 10007 | Ownership Changed |
| 10008 | Orphan Detected |
| 10009 | Orphan Resolved |
| 10010 | Entra Sync Completed |
| 10011 | Entra Sync Failed |
| 10012 | SLA Escalation |
| 10013 | Approval Timed Out |

### Choice: fsi_eventsource

| Value | Label |
|-------|-------|
| 10001 | Flow 1 — Discovery |
| 10002 | Flow 2 — Registration |
| 10003 | Flow 3 — Entra Sync |
| 10004 | Flow 4 — Orphan Detection |
| 10005 | Manual — Admin Action |
| 10006 | Script — Baseline Import |

### Choice: fsi_severity

| Value | Label |
|-------|-------|
| 10001 | Informational |
| 10002 | Low |
| 10003 | Medium |
| 10004 | High |
| 10005 | Critical |

### Sample Data

```json
{
  "fsi_name": "Agent Discovered — Customer Service Agent",
  "fsi_eventtype": 10001,
  "fsi_eventsource": 10001,
  "fsi_severity": 10001,
  "fsi_actorupn": "system@contoso.com",
  "fsi_environmentid": "env-12345-abcd-6789-ef01-234567890abc",
  "fsi_zone": 10003,
  "fsi_correlationid": "corr-98765-abcd-4321-ef01-234567890abc",
  "fsi_occurredon": "2026-03-15T08:30:00Z",
  "fsi_eventdetails": "{\"agentName\":\"Customer Service Agent\",\"environmentName\":\"Production - Customer Service\",\"discoveryMethod\":\"BotsAPI\",\"existingRecord\":false}"
}
```

---

## Table: fsi_ownershipaudit

Tracks ownership changes for agents in the registry. Created when Flow 4 detects orphaned agents or when ownership is manually transferred.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_ownershipauditid` | Uniqueidentifier | Yes | Primary key (auto-generated) |
| `fsi_name` | String (200) | Yes | Audit record title |
| `fsi_agentinventoryid` | Lookup | Yes | Reference to the agent whose ownership changed |
| `fsi_changetype` | Choice | Yes | Type of ownership change |
| `fsi_previousownerupn` | String (320) | No | Previous owner UPN |
| `fsi_previousownerstatus` | String (100) | No | Previous owner's account status (e.g., "Active", "Disabled", "Deleted") |
| `fsi_newownerupn` | String (320) | No | New owner UPN (null if orphaned and not yet reassigned) |
| `fsi_changedon` | DateTime | Yes | Timestamp when the change was detected or applied |
| `fsi_changedby` | String (320) | No | UPN of the person or process that initiated the change |
| `fsi_reason` | Text (2000) | No | Reason for the ownership change |
| `fsi_correlationid` | String (36) | No | Correlation ID linking to related compliance events |
| `createdon` | DateTime | Auto | Record creation timestamp |

### Choice: fsi_changetype

| Value | Label |
|-------|-------|
| 10001 | Owner Departed |
| 10002 | Owner Disabled |
| 10003 | Owner Inactive |
| 10004 | Manual Transfer |
| 10005 | Escalation Transfer |

### Sample Data

```json
{
  "fsi_name": "Ownership Change — Customer Service Agent",
  "fsi_changetype": 10001,
  "fsi_previousownerupn": "john.doe@contoso.com",
  "fsi_previousownerstatus": "Disabled",
  "fsi_newownerupn": null,
  "fsi_changedon": "2026-03-20T06:15:00Z",
  "fsi_changedby": "system@contoso.com",
  "fsi_reason": "Owner account disabled — detected during weekly orphan scan",
  "fsi_correlationid": "corr-55555-abcd-4321-ef01-234567890abc"
}
```

---

## Entity Relationships

| Parent Table | Child Table | Relationship Type | Foreign Key |
|-------------|-------------|-------------------|-------------|
| `fsi_agentinventory` | `fsi_registrationrequest` | 1:N | `fsi_agentinventoryid` |
| `fsi_agentinventory` | `fsi_agentcomplianceevent` | 1:N | `fsi_agentinventoryid` |
| `fsi_agentinventory` | `fsi_ownershipaudit` | 1:N | `fsi_agentinventoryid` |

> **Referential behavior:** All relationships use **Restrict Delete** — an agent inventory record cannot be deleted while related registration requests, compliance events, or ownership audits exist. This supports record integrity for regulatory retention.

---

*Agent Registry Automation v1.0.0 — FSI Agent Governance Framework*
