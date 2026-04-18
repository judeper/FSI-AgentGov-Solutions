# Dataverse Schema

Table definitions for the Segregation of Duties Detector.

---

## Schema Overview

```
┌─────────────────────┐     ┌─────────────────────┐
│  fsi_conflictrule   │────<│  fsi_sodviolation   │
│  (rule definitions) │     │  (detected conflicts)│
└─────────────────────┘     └─────────────────────┘
                                     │
                                     │
                                     ▼
                            ┌─────────────────────┐
                            │ fsi_sodexception    │
                            │ (approved exceptions)│
                            └─────────────────────┘
                                     │
                                     ▼
                            ┌─────────────────────┐
                            │  fsi_sodauditlog    │
                            │  (audit trail)      │
                            └─────────────────────┘
```

---

## Table: fsi_conflictrule

Defines incompatible role combinations.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_conflictruleid` | Uniqueidentifier | Yes | Primary key |
| `fsi_name` | String (200) | Yes | Rule name |
| `fsi_category` | Choice | Yes | Conflict category |
| `fsi_rolea` | String (100) | Yes | First role in conflict |
| `fsi_roleacontext` | Choice | Yes | Context for Role A |
| `fsi_roleb` | String (100) | Yes | Second role in conflict |
| `fsi_rolebcontext` | Choice | Yes | Context for Role B |
| `fsi_severity` | Choice | Yes | Violation severity |
| `fsi_description` | Text | No | Rule description |
| `fsi_enabled` | Boolean | Yes | Rule is active |
| `fsi_allowexception` | Boolean | Yes | Exceptions permitted |
| `createdon` | DateTime | Auto | Record creation timestamp |

### Choice: fsi_category

| Value | Label |
|-------|-------|
| 1 | Maker/Checker |
| 2 | Segregation |
| 3 | Privileged Access |

### Choice: fsi_roleacontext / fsi_rolebcontext

| Value | Label |
|-------|-------|
| 1 | Entra ID Directory Role |
| 2 | Entra ID App Role |
| 3 | Power Platform Environment Role |
| 4 | Dataverse Security Role |
| 5 | Custom Application Role |

### Choice: fsi_severity

| Value | Label | Auto-Block |
|-------|-------|------------|
| 1 | Critical | Yes |
| 2 | High | Yes |
| 3 | Medium | No |
| 4 | Low | No |

### Sample Data

```json
{
  "fsi_name": "Agent Developer cannot be Pipeline Approver",
  "fsi_category": 1,
  "fsi_rolea": "Agent Developer",
  "fsi_roleacontext": 4,
  "fsi_roleb": "Pipeline Approver",
  "fsi_rolebcontext": 4,
  "fsi_severity": 1,
  "fsi_description": "Prevents self-approval of agent changes",
  "fsi_enabled": true,
  "fsi_allowexception": true
}
```

---

## Table: fsi_sodviolation

Detected segregation of duties violations.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_sodviolationid` | Uniqueidentifier | Yes | Primary key |
| `fsi_name` | String (200) | Yes | Violation title |
| `fsi_conflictruleid` | Lookup | Yes | Violated rule |
| `fsi_userid` | String (100) | Yes | User principal name |
| `fsi_userobjectid` | String (36) | Yes | Entra ID object ID |
| `fsi_userdisplayname` | String (200) | Yes | User display name |
| `fsi_roleaassignment` | String (200) | Yes | Role A assignment details |
| `fsi_rolebassignment` | String (200) | Yes | Role B assignment details |
| `fsi_environment` | String (100) | No | Environment (if applicable) |
| `fsi_status` | Choice | Yes | Violation status |
| `fsi_detectedon` | DateTime | Yes | Detection timestamp |
| `fsi_resolvedon` | DateTime | No | Resolution timestamp |
| `fsi_resolutiontype` | Choice | No | How violation was resolved |
| `fsi_exceptionid` | Lookup | No | Approved exception (if any) |
| `createdon` | DateTime | Auto | Record creation timestamp |

### Choice: fsi_status

| Value | Label |
|-------|-------|
| 1 | Open |
| 2 | Under Review |
| 3 | Exception Requested |
| 4 | Exception Approved |
| 5 | Resolved - Role Removed |
| 6 | Resolved - User Removed |
| 7 | Closed - False Positive |

### Choice: fsi_resolutiontype

| Value | Label |
|-------|-------|
| 1 | Role A Removed |
| 2 | Role B Removed |
| 3 | Both Roles Removed |
| 4 | User Deactivated |
| 5 | Exception Granted |
| 6 | False Positive |
| 7 | Rule Disabled |

---

## Table: fsi_sodexception

Approved exceptions for justified role conflicts.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_sodexceptionid` | Uniqueidentifier | Yes | Primary key |
| `fsi_name` | String (200) | Yes | Exception title |
| `fsi_sodviolationid` | Lookup | Yes | Related violation |
| `fsi_userid` | String (100) | Yes | User principal name |
| `fsi_exceptiontype` | Choice | Yes | Exception type |
| `fsi_justification` | Text | Yes | Business justification |
| `fsi_compensatingcontrols` | Text | Yes | Mitigating controls |
| `fsi_monitoringplan` | Text | No | Ongoing monitoring description |
| `fsi_requestedby` | Lookup (User) | Yes | Exception requestor |
| `fsi_requestedon` | DateTime | Yes | Request timestamp |
| `fsi_approvedby` | Lookup (User) | No | Final approver |
| `fsi_approvedon` | DateTime | No | Approval timestamp |
| `fsi_status` | Choice | Yes | Exception status |
| `fsi_effectivedate` | Date | No | Exception start date |
| `fsi_expirationdate` | Date | No | Exception end date |
| `fsi_nextreviewdate` | Date | No | Next review due date |
| `fsi_riskacceptance` | Boolean | No | Risk formally accepted |
| `createdon` | DateTime | Auto | Record creation timestamp |

### Choice: fsi_exceptiontype

| Value | Label | Max Duration |
|-------|-------|--------------|
| 1 | Emergency | 24 hours |
| 2 | Temporary | 30 days |
| 3 | Permanent | Annual review |

### Choice: fsi_status

| Value | Label |
|-------|-------|
| 1 | Requested |
| 2 | Manager Approved |
| 3 | Compliance Review |
| 4 | Approved |
| 5 | Denied |
| 6 | Expired |
| 7 | Revoked |

---

## Table: fsi_sodauditlog

Audit trail for all SoD-related activities.

### Columns

| Column | Type | Required | Description |
|--------|------|----------|-------------|
| `fsi_sodauditlogid` | Uniqueidentifier | Yes | Primary key |
| `fsi_name` | String (200) | Yes | Log entry title |
| `fsi_eventtype` | Choice | Yes | Type of event |
| `fsi_entitytype` | String (50) | Yes | Related entity type |
| `fsi_entityid` | String (36) | Yes | Related entity ID |
| `fsi_userid` | String (100) | Yes | User involved |
| `fsi_performedby` | String (100) | Yes | Action performer |
| `fsi_eventdetails` | Text | No | Detailed event description |
| `fsi_previousvalue` | Text | No | Value before change |
| `fsi_newvalue` | Text | No | Value after change |
| `fsi_ipaddress` | String (50) | No | Source IP address |
| `createdon` | DateTime | Auto | Event timestamp |

### Choice: fsi_eventtype

| Value | Label |
|-------|-------|
| 1 | Violation Detected |
| 2 | Violation Resolved |
| 3 | Exception Requested |
| 4 | Exception Approved |
| 5 | Exception Denied |
| 6 | Exception Expired |
| 7 | Rule Created |
| 8 | Rule Modified |
| 9 | Rule Disabled |
| 10 | Scan Completed |
| 11 | Alert Sent |

---

## Relationships

| Parent Table | Child Table | Relationship |
|--------------|-------------|--------------|
| fsi_conflictrule | fsi_sodviolation | 1:N |
| fsi_sodviolation | fsi_sodexception | 1:N |
| fsi_sodexception | fsi_sodauditlog | Reference |

---

## Security Roles

### SoD Viewer

Read-only access for compliance reviewers.

| Table | Permissions |
|-------|-------------|
| fsi_conflictrule | Read |
| fsi_sodviolation | Read |
| fsi_sodexception | Read |
| fsi_sodauditlog | Read |

### SoD Analyst

Exception processing and violation management.

| Table | Permissions |
|-------|-------------|
| fsi_conflictrule | Read |
| fsi_sodviolation | Read, Update |
| fsi_sodexception | Read, Create, Update |
| fsi_sodauditlog | Read |

### SoD Admin

Full administrative access including rule management.

| Table | Permissions |
|-------|-------------|
| All tables | Read, Create, Update, Delete |

---

## Deployment

### Option 1: Manual Creation

Create tables using Power Apps maker portal following the schema above.

---

*Segregation of Duties Detector v1.1.0*
