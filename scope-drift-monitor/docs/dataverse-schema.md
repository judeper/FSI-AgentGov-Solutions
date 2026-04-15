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
┌─────────────────────┐
│  fsi_scopeitem      │
│  (allowed resources)│
└─────────────────────┘
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
| 10001 | Zone 1 - Personal Productivity |
| 10002 | Zone 2 - Team Collaboration |
| 10003 | Zone 3 - Enterprise Managed |

### Choice: fsi_status

| Value | Label |
|-------|-------|
| 10001 | Draft |
| 10002 | Active |
| 10003 | Under Review |
| 10004 | Suspended |
| 10005 | Archived |

### Sample Data

```json
{
  "fsi_name": "Customer Service Agent",
  "fsi_agentid": "12345678-1234-1234-1234-123456789012",
  "fsi_environmentid": "87654321-4321-4321-4321-210987654321",
  "fsi_zone": 10003,
  "fsi_purpose": "Answer customer inquiries using approved knowledge sources",
  "fsi_status": 10002,
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
| `fsi_name` | String (200) | Yes | Scope item display name |
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
| 10001 | Connector |
| 10002 | SharePoint Site |
| 10003 | SharePoint Library |
| 10004 | Dataverse Table |
| 10005 | External API |
| 10006 | File Share |
| 10007 | Database |

### Choice: fsi_accesslevel

| Value | Label |
|-------|-------|
| 10001 | Read Only |
| 10002 | Read/Write |
| 10003 | Full Control |

---

## Table: fsi_scopeviolation

Detected scope drift violations.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_scopeviolationid` | Uniqueidentifier | Yes | Primary key |
| `fsi_name` | String (200) | Yes | Violation title |
| `fsi_agentscopeid` | Lookup | Recommended | Agent scope (omitted for "No Baseline Defined" violations) |
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
| 10001 | Unauthorized Connector |
| 10002 | Unauthorized SharePoint Site |
| 10003 | Unauthorized Dataverse Table |
| 10004 | Unauthorized External API |
| 10005 | Expired Scope Item |
| 10006 | No Baseline Defined |

### Choice: fsi_severity

| Value | Label |
|-------|-------|
| 10001 | Critical |
| 10002 | High |
| 10003 | Medium |
| 10004 | Low |

### Choice: fsi_status

| Value | Label |
|-------|-------|
| 10001 | Open |
| 10002 | Under Investigation |
| 10003 | Expansion Requested |
| 10004 | Resolved - Scope Expanded |
| 10005 | Resolved - Access Removed |
| 10006 | Closed - False Positive |

### Choice: fsi_resolutiontype

| Value | Label |
|-------|-------|
| 10001 | Scope Expanded |
| 10002 | Agent Remediated |
| 10003 | Access Revoked |
| 10004 | False Positive |
| 10005 | Risk Accepted |

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
| 10001 | Add Connector |
| 10002 | Add SharePoint Site |
| 10003 | Add Dataverse Table |
| 10004 | Add External API |
| 10005 | Increase Access Level |

### Choice: fsi_status

| Value | Label |
|-------|-------|
| 10001 | Pending |
| 10002 | Data Owner Review |
| 10003 | Security Review |
| 10004 | Approved |
| 10005 | Denied |
| 10006 | Cancelled |
| 10007 | Timed Out |

### Choice: fsi_dataownerapproval / fsi_securityapproval

| Value | Label |
|-------|-------|
| 10001 | Pending |
| 10002 | Approved |
| 10003 | Denied |
| 10004 | Delegated |

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

## Design Decisions

### Custom Status Fields vs. statecode/statuscode

All four tables use custom `fsi_status` choice fields instead of Dataverse's built-in `statecode`/`statuscode` system. This is an intentional design decision:

- **Cross-table consistency**: All tables use the same `fsi_status` pattern with publisher-prefixed option values, enabling uniform filtering and reporting across the solution.
- **Deployment portability**: Custom fields travel with the solution and are not affected by target environment state/status configurations.
- **Flow compatibility**: Power Automate expressions reference `fsi_status` directly with numeric comparisons. Built-in state transitions add complexity to flow logic without proportional benefit for this use case.

Deployers who prefer built-in state management may map `fsi_status` transitions to `statecode`/`statuscode` via business rules or plugins.

---

## Violation Record Lifecycle

Resolved `fsi_scopeviolation` records (status 10004 Resolved - Scope Expanded, 10005 Resolved - Access Removed, 10006 Closed - False Positive) accumulate indefinitely. For high-volume FSI environments, implement periodic archival or purge to maintain query performance and manage Dataverse capacity.

**Recommended approach:**

| Strategy | Implementation |
|----------|----------------|
| Bulk Delete Job | Create a Dataverse bulk delete job targeting `fsi_scopeviolation` records where `fsi_status` is in (10004, 10005, 10006) and `modifiedon` is older than retention period (e.g., 90 days) |
| Power Automate Scheduled Flow | Run weekly to move resolved violations older than retention period to an archive table or export to Azure Data Lake |
| Dataverse Retention Policy | Use Dataverse long-term retention (preview) to automatically archive old records while keeping them queryable |

Retention period should align with your organization's audit requirements (e.g., FINRA Rule 3110 requires 3-year retention, GDPR requires purpose-limited retention).

---

*Scope Drift Monitor v1.1.2*
