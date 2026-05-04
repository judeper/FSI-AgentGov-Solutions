# Dataverse Schema

Complete table and column definitions for Environment Lifecycle Management.

## Table Overview

| Table | Logical Name | Ownership | Purpose |
|-------|--------------|-----------|---------|
| **EnvironmentRequest** | `fsi_environmentrequest` | User | Environment request tracking |
| **ProvisioningLog** | `fsi_provisioninglog` | Organization | Immutable audit trail |

## EnvironmentRequest Table

### Table Settings

| Setting | Value | Rationale |
|---------|-------|-----------|
| **Display Name** | Environment Request | |
| **Plural Name** | Environment Requests | |
| **Logical Name** | `fsi_environmentrequest` | FSI publisher prefix |
| **Ownership** | User | Enables row-level security |
| **Enable Auditing** | Yes | All fields, all operations |
| **Primary Column** | Auto-number (see below) | |

### Primary Column (Auto-Number)

| Setting | Value |
|---------|-------|
| **Display Name** | Request Number |
| **Logical Name** | `fsi_requestnumber` |
| **Format** | `REQ-{SEQNUM:5}` |
| **Seed Value** | 1 |
| **Starting Number** | 1 |
| **Example Output** | REQ-00001, REQ-00002 |

### Column Definitions

#### Core Request Fields

| Display Name | Logical Name | Type | Required | Description |
|--------------|--------------|------|----------|-------------|
| Request ID | `fsi_environmentrequestid` | GUID | Auto | Primary key |
| Request Number | `fsi_requestnumber` | Auto Number | Auto | REQ-00001 format |
| Environment Name | `fsi_environmentname` | Text (100) | Yes | DEPT-Purpose-TYPE naming |
| Environment Type | `fsi_environmenttype` | Choice | Yes | Sandbox/Production/Developer |
| Region | `fsi_region` | Choice | Yes | Geographic region |
| Business Justification | `fsi_businessjustification` | Multiline | Yes | Purpose description |

#### Zone Classification Fields

| Display Name | Logical Name | Type | Required | Description |
|--------------|--------------|------|----------|-------------|
| Zone | `fsi_zone` | Choice | Yes | Zone 1/2/3 classification |
| Zone Rationale | `fsi_zonerationale` | Multiline | Zone2/Zone3 | Business justification for zone |
| Zone Auto Flags | `fsi_zoneautoflags` | Text (500) | Auto | Auto-detected triggers (comma-separated) |
| Data Sensitivity | `fsi_datasensitivity` | Choice | Yes | Public/Internal/Confidential/Restricted |
| Expected Users | `fsi_expectedusers` | Choice | Yes | User population estimate |

#### Access Control Fields

| Display Name | Logical Name | Type | Required | Description |
|--------------|--------------|------|----------|-------------|
| Security Group ID | `fsi_securitygroupid` | Text (100) | Zone2/Zone3 | Entra security group GUID |
| Security Group Name | `fsi_securitygroupname` | Text (200) | No | Display name of Entra security group |
| Requester | `fsi_requester` | Lookup (User) | Auto | Request creator |
| Requested On | `fsi_requestedon` | DateTime | Auto | Submission timestamp |

#### Workflow State Fields

| Display Name | Logical Name | Type | Required | Description |
|--------------|--------------|------|----------|-------------|
| State | `fsi_state` | Choice | Workflow | Current workflow state |
| Approver | `fsi_approver` | Lookup (User) | Workflow | Approval authority |
| Approved On | `fsi_approvedon` | DateTime | Workflow | Approval timestamp |
| Approval Comments | `fsi_approvalcomments` | Multiline | Rejection | Required for rejection |

#### Provisioning Result Fields

| Display Name | Logical Name | Type | Required | Description |
|--------------|--------------|------|----------|-------------|
| Environment ID | `fsi_environmentid` | Text (100) | Auto | Power Platform environment GUID |
| Environment URL | `fsi_environmenturl` | URL | Auto | Dataverse instance URL |
| Provisioning Started | `fsi_provisioningstarted` | DateTime | Auto | Flow execution start |
| Provisioning Completed | `fsi_provisioningcompleted` | DateTime | Auto | Flow completion timestamp |

### Choice Field Definitions

#### fsi_er_state (Workflow State)

| Label | Value | Description |
|-------|-------|-------------|
| Draft | 100000001 | User is completing form |
| Submitted | 100000002 | User submitted request |
| PendingApproval | 100000003 | Awaiting approver decision |
| Approved | 100000004 | Approver approved |
| Rejected | 100000005 | Approver rejected |
| Provisioning | 100000006 | Flow executing |
| Completed | 100000007 | Environment ready |
| Failed | 100000008 | Provisioning error |
| Cancelled | 100000009 | User cancelled request |

#### fsi_er_zone (Governance Zone)

| Label | Value | Description |
|-------|-------|-------------|
| Zone1 | 100000001 | Personal productivity |
| Zone2 | 100000002 | Team collaboration |
| Zone3 | 100000003 | Enterprise managed |

#### fsi_er_environmenttype (Environment Type)

| Label | Value |
|-------|-------|
| Sandbox | 100000001 |
| Production | 100000002 |
| Developer | 100000003 |

#### fsi_er_region (Geographic Region)

| Label | Value | API Code |
|-------|-------|----------|
| United States | 100000001 | unitedstates |
| Europe | 100000002 | europe |
| United Kingdom | 100000003 | unitedkingdom |
| Australia | 100000004 | australia |

#### fsi_er_datasensitivity (Data Sensitivity)

| Label | Value |
|-------|-------|
| Public | 100000001 |
| Internal | 100000002 |
| Confidential | 100000003 |
| Restricted | 100000004 |

#### fsi_er_expectedusers (Expected User Count)

| Label | Value |
|-------|-------|
| Just me (1) | 100000001 |
| Small team (2-10) | 100000002 |
| Large team (11-50) | 100000003 |
| Department (50+) | 100000004 |

### Business Rules

#### Zone Rationale Required

```
Trigger: fsi_zone changes
Condition: fsi_zone = Zone2 OR fsi_zone = Zone3
Action: Set fsi_zonerationale to Business Required
```

#### Security Group Required

```
Trigger: fsi_zone changes
Condition: fsi_zone = Zone2 OR fsi_zone = Zone3
Action: Set fsi_securitygroupid to Business Required
```

#### Approval Comments Required on Rejection

```
Trigger: fsi_state changes
Condition: fsi_state = Rejected
Action: Set fsi_approvalcomments to Business Required
```

---

## ProvisioningLog Table

### Table Settings

| Setting | Value | Rationale |
|---------|-------|-----------|
| **Display Name** | Provisioning Log | |
| **Plural Name** | Provisioning Logs | |
| **Logical Name** | `fsi_provisioninglog` | FSI publisher prefix |
| **Ownership** | Organization | Prevents user-level edits (immutability) |
| **Enable Auditing** | Yes | Secondary audit trail |
| **Primary Column** | Log ID (auto-generated) | |

### Relationship to EnvironmentRequest

| Setting | Value |
|---------|-------|
| **Type** | Many-to-One |
| **Related Table** | EnvironmentRequest |
| **Lookup Column** | `fsi_environmentrequest` |
| **Delete Behavior** | Restrict |

> **Restrict Delete** helps prevent EnvironmentRequest records from being deleted if ProvisioningLog entries exist.

### Column Definitions

| Display Name | Logical Name | Type | Required | Description |
|--------------|--------------|------|----------|-------------|
| Log ID | `fsi_provisioninglogid` | GUID | Auto | Primary key |
| Environment Request | `fsi_environmentrequest` | Lookup | Yes | Parent request |
| Sequence | `fsi_sequence` | Whole Number | Yes | Action sequence (1, 2, 3...) |
| Action | `fsi_action` | Choice | Yes | Action type |
| Action Details | `fsi_actiondetails` | Multiline | No | JSON payload |
| Actor | `fsi_actor` | Text (200) | Yes | UPN or Service Principal ID |
| Actor Type | `fsi_actortype` | Choice | Yes | User/ServicePrincipal/System |
| Timestamp | `fsi_timestamp` | DateTime | Auto | Auto-set to Now() |
| Success | `fsi_success` | Boolean | Yes | Action succeeded |
| Error Message | `fsi_errormessage` | Multiline | No | Error details if failed |
| Correlation ID | `fsi_correlationid` | Text (100) | Yes | Power Automate run ID |

### Choice Field Definitions

#### fsi_pl_action (Action Type)

| Label | Value | Description |
|-------|-------|-------------|
| RequestCreated | 100000001 | Initial request created |
| ZoneClassified | 100000002 | Auto-classification applied |
| ApprovalRequested | 100000003 | Routed for approval |
| Approved | 100000004 | Approver approved |
| Rejected | 100000005 | Approver rejected |
| ProvisioningStarted | 100000006 | Flow began execution |
| EnvironmentCreated | 100000007 | Environment creation complete |
| ManagedEnabled | 100000008 | Managed Environment enabled |
| GroupAssigned | 100000009 | Added to Environment Group |
| SecurityGroupBound | 100000010 | Security group bound |
| BaselineConfigApplied | 100000011 | Baseline settings applied |
| DLPAssigned | 100000012 | DLP policy applied (reserved — no flow step currently logs this action) |
| ProvisioningCompleted | 100000013 | Full provisioning complete |
| ProvisioningFailed | 100000014 | Provisioning error |
| RollbackInitiated | 100000015 | Rollback started (reserved — no rollback logic currently implemented) |
| RollbackCompleted | 100000016 | Rollback finished (reserved — no rollback logic currently implemented) |

#### fsi_pl_actortype (Actor Type)

| Label | Value |
|-------|-------|
| User | 100000001 |
| ServicePrincipal | 100000002 |
| System | 100000003 |

### Immutability Enforcement

ProvisioningLog is designed to be **immutable** (append-only):

| Layer | Mechanism |
|-------|-----------|
| **Table Ownership** | Organization-owned (not user-owned) |
| **Security Roles** | No role grants Write or Delete privilege |
| **Create-Only** | ELM Admin role has Create + Read only |
| **Dataverse Auditing** | Captures any bypass attempts |

See [security-roles.md](./security-roles.md) for privilege configuration.

---

## Sample Data

### EnvironmentRequest Sample

```json
{
  "fsi_requestnumber": "REQ-00001",
  "fsi_environmentname": "FIN-QuarterlyReporting-PROD",
  "fsi_environmenttype": 100000002,
  "fsi_region": 100000001,
  "fsi_zone": 100000003,
  "fsi_zonerationale": "Processes quarterly financial reports with customer account data",
  "fsi_zoneautoflags": "CUSTOMER_PII,FINANCIAL_TRANSACTIONS",
  "fsi_datasensitivity": 100000003,
  "fsi_expectedusers": 100000003,
  "fsi_securitygroupid": "12345678-1234-1234-1234-123456789012",
  "fsi_businessjustification": "Quarterly SEC 10-Q reporting automation",
  "fsi_state": 100000007,
  "fsi_environmentid": "87654321-4321-4321-4321-210987654321",
  "fsi_environmenturl": "https://<org>.crm.dynamics.com"
}
```

### ProvisioningLog Sample

```json
{
  "fsi_sequence": 7,
  "fsi_action": 100000007,
  "fsi_actiondetails": {
    "environmentId": "87654321-4321-4321-4321-210987654321",
    "environmentUrl": "https://<org>.crm.dynamics.com",
    "environmentType": "Production",
    "region": "unitedstates"
  },
  "fsi_actor": "ELM-Provisioning-ServicePrincipal",
  "fsi_actortype": 100000002,
  "fsi_success": true,
  "fsi_correlationid": "08585929-1234-5678-abcd-ef1234567890"
}
```

---

## Creation Steps

### Step 1: Create EnvironmentRequest Table

1. Open Power Apps maker portal
2. Select governance environment
3. Tables > New table > New table (advanced)
4. Configure table settings per above
5. Add columns per definitions
6. Create choice columns first (for lookups)
7. Configure auto-number primary column
8. Enable auditing

### Step 2: Create ProvisioningLog Table

1. Tables > New table > New table (advanced)
2. Set ownership to **Organization** (critical for immutability)
3. Add columns per definitions
4. Create relationship to EnvironmentRequest:
   - Lookup column: `fsi_environmentrequest`
   - Delete behavior: **Restrict**
5. Enable auditing

### Step 3: Create Business Rules

1. Open EnvironmentRequest table
2. Business rules > New business rule
3. Create three rules per definitions above
4. Activate each rule

### Step 4: Configure Views

Create views for model-driven app:

| View Name | Filter |
|-----------|--------|
| My Requests | `fsi_requester = currentuser` |
| Pending My Approval | `fsi_state = PendingApproval AND fsi_approver = currentuser` |
| All Pending | `fsi_state = PendingApproval` |
| Provisioning in Progress | `fsi_state = Provisioning` |
| Failed Requests | `fsi_state = Failed` |
| Completed This Month | `fsi_state = Completed AND fsi_provisioningcompleted >= startOfMonth` |

---

## Next Steps

After creating schema:

1. [Configure security roles](./security-roles.md)
2. [Register Service Principal](./service-principal-setup.md)

## Cross-Solution Contract

Other FSI-AgentGov solutions (e.g., conditional-access-automation,
agent-sharing-access-restriction-detector) read zone classification from
this table via `scripts/shared/Get-ZoneClassification.ps1`. The contract
they depend on is:

| Element | Value |
|---------|-------|
| Entity set | `fsi_environmentrequests` |
| Filter column | `fsi_environmentid` (Power Platform environment GUID) |
| Returned column | `fsi_zone` |
| Option values | `100000001`=Zone1, `100000002`=Zone2, `100000003`=Zone3 |
| Returned labels | `Zone1`, `Zone2`, `Zone3` (no spaces) |

Changing any of these is a **breaking change** for downstream solutions.
Bump ELM major version and update the consumers when this contract
changes.