# Dataverse Schema

Table definitions for the Scope Drift Monitor.

---

## Schema Overview

```
┌─────────────────────┐     ┌─────────────────────┐
│  fsi_agentscope     │────<│  fsi_scopeviolation │
│  (scope definitions)│     │  (drift detections) │
└─────────────────────┘     └─────────────────────┘
         │                            │
         │                            ▼
         │                  ┌─────────────────────┐
         │                  │ fsi_expansionrequest│
         │                  │ (scope changes)     │
         │                  └─────────────────────┘
         │
         ▼
┌─────────────────────┐     ┌─────────────────────┐
│  fsi_scopeitem      │     │  fsi_detectionrun   │
│  (allowed resources)│     │  (run audit trail)  │
└─────────────────────┘     └─────────────────────┘
```

---

## Table: fsi_agentscope

Master scope definition for each AI agent.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_agentscopeid` | Uniqueidentifier | Yes | Primary key |
| `fsi_name` | String (200) | Yes | Agent display name |
| `fsi_agentid` | String (36) | Yes | Copilot Studio agent ID |
| `fsi_environmentid` | String (36) | Yes | Power Platform environment ID |
| `fsi_zone` | Choice | Yes | Governance zone |
| `fsi_owner` | Lookup (User) | Yes | Agent owner |
| `fsi_dataowner` | Lookup (User) | No | Data steward |
| `fsi_purpose` | Text | Yes | Declared agent purpose |
| `fsi_status` | Choice | Yes | Scope status |
| `fsi_lastvalidated` | DateTime | No | Last scope validation |
| `fsi_nextreview` | Date | No | Next scheduled review |
| `fsi_allowedconnectors` | Text | No | JSON array of connector names |
| `fsi_allowedsites` | Text | No | JSON array of SharePoint URLs |
| `fsi_allowedtables` | Text | No | JSON array of Dataverse tables |
| `fsi_allowedapis` | Text | No | JSON array of external API URLs |
| `createdon` | DateTime | Auto | Record creation timestamp |
| `modifiedon` | DateTime | Auto | Last modification |

### Choice: fsi_zone

| Value | Label |
|-------|-------|
| 1 | Zone 1 - Personal Productivity |
| 2 | Zone 2 - Team Collaboration |
| 3 | Zone 3 - Enterprise Managed |

### Choice: fsi_status

| Value | Label |
|-------|-------|
| 1 | Draft |
| 2 | Active |
| 3 | Under Review |
| 4 | Suspended |
| 5 | Archived |

### Sample Data

```json
{
  "fsi_name": "Customer Service Agent",
  "fsi_agentid": "12345678-1234-1234-1234-123456789012",
  "fsi_environmentid": "87654321-4321-4321-4321-210987654321",
  "fsi_zone": 3,
  "fsi_purpose": "Answer customer inquiries using approved knowledge sources",
  "fsi_status": 2,
  "fsi_allowedconnectors": "[\"SharePoint\", \"Dataverse\"]",
  "fsi_allowedsites": "[\"https://contoso.sharepoint.com/sites/CustomerKB\"]",
  "fsi_allowedtables": "[\"contact\", \"case\", \"knowledgearticle\"]",
  "fsi_allowedapis": "[]"
}
```

---

## Table: fsi_scopeitem

Individual scope items with detailed configuration.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_scopeitemid` | Uniqueidentifier | Yes | Primary key |
| `fsi_agentscopeid` | Lookup | Yes | Parent scope |
| `fsi_itemtype` | Choice | Yes | Type of resource |
| `fsi_resourcename` | String (200) | Yes | Resource identifier |
| `fsi_resourceurl` | String (500) | No | Full URL if applicable |
| `fsi_accesslevel` | Choice | Yes | Permitted access level |
| `fsi_justification` | Text | No | Why this access is needed |
| `fsi_approvedby` | Lookup (User) | No | Approver |
| `fsi_approvedon` | DateTime | No | Approval date |
| `fsi_expiredate` | Date | No | Expiration date (optional) |
| `fsi_enabled` | Boolean | Yes | Item is active |
| `createdon` | DateTime | Auto | Record creation |

### Choice: fsi_itemtype

| Value | Label |
|-------|-------|
| 1 | Connector |
| 2 | SharePoint Site |
| 3 | SharePoint Library |
| 4 | Dataverse Table |
| 5 | External API |
| 6 | File Share |
| 7 | Database |

### Choice: fsi_accesslevel

| Value | Label |
|-------|-------|
| 1 | Read Only |
| 2 | Read/Write |
| 3 | Full Control |

---

## Table: fsi_scopeviolation

Detected scope drift violations.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_scopeviolationid` | Uniqueidentifier | Yes | Primary key |
| `fsi_name` | String (200) | Yes | Violation title |
| `fsi_agentscopeid` | Lookup | Yes | Agent scope |
| `fsi_violationtype` | Choice | Yes | Type of drift |
| `fsi_resourcename` | String (200) | Yes | Accessed resource |
| `fsi_resourceurl` | String (500) | No | Resource URL |
| `fsi_severity` | Choice | Yes | Violation severity |
| `fsi_status` | Choice | Yes | Violation status |
| `fsi_detectedon` | DateTime | Yes | Detection timestamp |
| `fsi_auditrecordid` | String (100) | No | Source audit record ID |
| `fsi_accessdetails` | Text | No | JSON with access details |
| `fsi_resolvedon` | DateTime | No | Resolution timestamp |
| `fsi_resolutiontype` | Choice | No | How resolved |
| `fsi_expansionrequestid` | Lookup | No | Related expansion request |
| `createdon` | DateTime | Auto | Record creation |

### Choice: fsi_violationtype

| Value | Label |
|-------|-------|
| 1 | Unauthorized Connector |
| 2 | Unauthorized SharePoint Site |
| 3 | Unauthorized Dataverse Table |
| 4 | Unauthorized External API |
| 5 | Expired Scope Item |
| 6 | No Baseline Defined |

### Choice: fsi_severity

| Value | Label |
|-------|-------|
| 1 | Critical |
| 2 | High |
| 3 | Medium |
| 4 | Low |

### Choice: fsi_status

| Value | Label |
|-------|-------|
| 1 | Open |
| 2 | Under Investigation |
| 3 | Expansion Requested |
| 4 | Resolved - Scope Expanded |
| 5 | Resolved - Access Removed |
| 6 | Closed - False Positive |

### Choice: fsi_resolutiontype

| Value | Label |
|-------|-------|
| 1 | Scope Expanded |
| 2 | Agent Remediated |
| 3 | Access Revoked |
| 4 | False Positive |
| 5 | Risk Accepted |

---

## Table: fsi_expansionrequest

Requests to expand agent scope.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_expansionrequestid` | Uniqueidentifier | Yes | Primary key |
| `fsi_name` | String (200) | Yes | Request title |
| `fsi_agentscopeid` | Lookup | Yes | Agent scope |
| `fsi_scopeviolationid` | Lookup | No | Triggering violation |
| `fsi_requesttype` | Choice | Yes | Type of expansion |
| `fsi_resourcename` | String (200) | Yes | Resource to add |
| `fsi_resourceurl` | String (500) | No | Resource URL |
| `fsi_justification` | Text | Yes | Business justification |
| `fsi_requestedby` | Lookup (User) | Yes | Requestor |
| `fsi_requestedon` | DateTime | Yes | Request timestamp |
| `fsi_status` | Choice | Yes | Request status |
| `fsi_dataownerapproval` | Choice | No | Data owner decision |
| `fsi_dataownerapprovedby` | Lookup (User) | No | Data owner approver |
| `fsi_securityapproval` | Choice | No | Security decision |
| `fsi_securityapprovedby` | Lookup (User) | No | Security approver |
| `fsi_completedon` | DateTime | No | Completion timestamp |
| `createdon` | DateTime | Auto | Record creation |

### Choice: fsi_requesttype

| Value | Label |
|-------|-------|
| 1 | Add Connector |
| 2 | Add SharePoint Site |
| 3 | Add Dataverse Table |
| 4 | Add External API |
| 5 | Increase Access Level |

### Choice: fsi_status

| Value | Label |
|-------|-------|
| 1 | Pending |
| 2 | Data Owner Review |
| 3 | Security Review |
| 4 | Approved |
| 5 | Denied |
| 6 | Cancelled |
| 7 | Failed |

### Choice: fsi_dataownerapproval / fsi_securityapproval

| Value | Label |
|-------|-------|
| 1 | Pending |
| 2 | Approved |
| 3 | Denied |
| 4 | Delegated |

---

## Table: fsi_detectionrun

Audit trail of detection run executions for compliance evidence.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_detectionrunid` | Uniqueidentifier | Yes | Primary key |
| `fsi_name` | String (200) | Yes | Run display name |
| `fsi_runstart` | DateTime | Yes | Detection window start |
| `fsi_runend` | DateTime | Yes | Detection window end |
| `fsi_eventsprocessed` | Integer | Yes | Number of audit events processed |
| `fsi_violationscreated` | Integer | Yes | Number of violations created |
| `fsi_activescopescount` | Integer | Yes | Number of active scopes at run time |
| `fsi_summary` | Text | No | JSON summary of run details |
| `createdon` | DateTime | Auto | Record creation timestamp |

---

## Security Roles

### SDM Viewer

Read-only access.

| Table | Permissions |
|-------|-------------|
| fsi_agentscope | Read |
| fsi_scopeitem | Read |
| fsi_scopeviolation | Read |
| fsi_expansionrequest | Read |
| fsi_detectionrun | Read |

### SDM Analyst

Manage violations and requests.

| Table | Permissions |
|-------|-------------|
| fsi_agentscope | Read |
| fsi_scopeitem | Read |
| fsi_scopeviolation | Read, Update |
| fsi_expansionrequest | Read, Create, Update |

### SDM Admin

Full administrative access.

| Table | Permissions |
|-------|-------------|
| All tables | Full |

---

*Scope Drift Monitor v1.1.0*
