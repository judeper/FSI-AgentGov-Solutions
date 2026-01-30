# Security Roles

Security role definitions and privilege matrix for Environment Lifecycle Management.

## Role Overview

| Role | Scope | Purpose |
|------|-------|---------|
| **ELM Requester** | User | Submit and track own requests |
| **ELM Approver** | Business Unit | Approve environment requests |
| **ELM Admin** | Organization | Run automation, manage provisioning |
| **ELM Auditor** | Organization | Read-only access for compliance |

## Privilege Depth Reference

| Depth | Scope | Description |
|-------|-------|-------------|
| **User** | Own records | Only records owned by the user |
| **Business Unit** | BU records | Records in user's business unit |
| **Parent: Child BU** | BU + children | Records in BU and child BUs |
| **Organization** | All records | All records in the environment |

---

## ELM Requester

### Purpose

Allows users to submit environment requests and track their own submissions.

### Privilege Matrix

| Table | Create | Read | Write | Delete | Append | AppendTo |
|-------|--------|------|-------|--------|--------|----------|
| **EnvironmentRequest** | User | User | User | - | User | User |
| **ProvisioningLog** | - | User | - | - | - | - |

### Configuration Notes

- **Write (User)** allows editing own Draft requests only
- State machine validation prevents editing after submission
- Row-level security automatically filters to owned records

### Assignment

Assign to all users who may request environments.

---

## ELM Approver

### Purpose

Allows designated approvers to review and approve environment requests within their business unit.

### Privilege Matrix

| Table | Create | Read | Write | Delete | Append | AppendTo |
|-------|--------|------|-------|--------|--------|----------|
| **EnvironmentRequest** | - | BU | BU* | - | - | - |
| **ProvisioningLog** | - | BU | - | - | - | - |

*Write limited to approval fields via field-level security

### Field-Level Security

Create a field security profile to restrict which fields approvers can modify:

| Field | Read | Update |
|-------|------|--------|
| `fsi_state` | Yes | Yes |
| `fsi_approver` | Yes | Yes |
| `fsi_approvedon` | Yes | Yes |
| `fsi_approvalcomments` | Yes | Yes |
| `fsi_environmentname` | Yes | No |
| `fsi_zone` | Yes | No |
| `fsi_businessjustification` | Yes | No |
| All other fields | Yes | No |

### Configuration Steps

1. Create "ELM Approver Fields" field security profile
2. Add all EnvironmentRequest columns to profile
3. Set permissions per matrix above
4. Associate profile with ELM Approver role

### Assignment

Assign to managers and designated approvers. For Zone 3 requests, also assign to Compliance Officers.

---

## ELM Admin

### Purpose

Grants automation (Service Principal) and admin users full access to manage provisioning. **Critical: No Write or Delete on ProvisioningLog.**

### Privilege Matrix

| Table | Create | Read | Write | Delete | Append | AppendTo |
|-------|--------|------|-------|--------|--------|----------|
| **EnvironmentRequest** | Org | Org | Org | - | Org | Org |
| **ProvisioningLog** | Org | Org | **-** | **-** | - | - |

### Immutability Enforcement

The ELM Admin role intentionally **omits** Write and Delete privileges on ProvisioningLog:

| Privilege | Granted | Rationale |
|-----------|---------|-----------|
| `prvCreatefsi_provisioninglog` | Yes | Allow creating log entries |
| `prvReadfsi_provisioninglog` | Yes | Allow reading log entries |
| `prvWritefsi_provisioninglog` | **No** | Prevent modification |
| `prvDeletefsi_provisioninglog` | **No** | Prevent deletion |
| `prvAppendfsi_provisioninglog` | **No** | Not needed |
| `prvAppendTofsi_provisioninglog` | **No** | Not needed |

### Verification

Run the verification script to confirm immutability:

```bash
python scripts/verify_role_privileges.py \
  --environment-url https://<org>.crm.dynamics.com
```

Expected output:

```
Checking ELM Admin role...
  prvCreatefsi_provisioninglog: Organization ✓
  prvReadfsi_provisioninglog: Organization ✓
  prvWritefsi_provisioninglog: Not granted ✓
  prvDeletefsi_provisioninglog: Not granted ✓
Immutability verification: PASSED
```

### Assignment

- Assign to Service Principal application user
- Assign to Platform Operations team members
- Do NOT assign broadly

---

## ELM Auditor

### Purpose

Provides read-only access to all environment requests and provisioning logs for compliance and audit purposes.

### Privilege Matrix

| Table | Create | Read | Write | Delete | Append | AppendTo |
|-------|--------|------|-------|--------|--------|----------|
| **EnvironmentRequest** | - | Org | - | - | - | - |
| **ProvisioningLog** | - | Org | - | - | - | - |

### Configuration Notes

- Strictly read-only across the organization
- No ability to modify any records
- Suitable for compliance officers, internal audit, external auditors

### Assignment

Assign to:

- Compliance team members
- Internal audit team
- External auditors (temporary access during examinations)

---

## Segregation of Duties

### Control Requirements

Per Control 2.8 (Segregation of Duties):

| Constraint | Enforcement |
|------------|-------------|
| Requester cannot approve own request | Workflow validation: `fsi_approver ≠ fsi_requester` |
| Approvers cannot create requests for themselves | Workflow rule prevents self-service bypass |
| Service Principal performs provisioning | Automation identity separate from human approvers |

### Implementation

#### Workflow Validation Rule

Add validation in Power Automate approval flow:

```
Condition: Approver equals Requester
If true: Reject with message "Requester cannot approve their own request"
If false: Continue approval process
```

#### Model-Driven App Validation

Add JavaScript to EnvironmentRequest form:

```javascript
function validateApprover(executionContext) {
    var formContext = executionContext.getFormContext();
    var requester = formContext.getAttribute("fsi_requester").getValue();
    var approver = formContext.getAttribute("fsi_approver").getValue();

    if (requester && approver && requester[0].id === approver[0].id) {
        formContext.ui.setFormNotification(
            "Requester cannot approve their own request",
            "ERROR",
            "approver-validation"
        );
        executionContext.getEventArgs().preventDefault();
    }
}
```

---

## Service Principal Configuration

### Application User Setup

1. Create application user in Dataverse:
   - Settings > Security > Users
   - New user > Application user
   - Application ID: (from Entra app registration)

2. Assign ELM Admin role to application user

3. Verify access:
   - Application user appears in system users
   - ELM Admin role is assigned
   - Business unit is root BU

### Required Privileges Beyond Tables

The Service Principal also needs:

| Privilege | Purpose |
|-----------|---------|
| `prvReadOrganization` | Query organization settings |
| `prvReadUser` | Resolve user lookups |
| `prvReadBusinessUnit` | Business unit context |

These are typically included in System Administrator or can be added to ELM Admin role.

---

## Role Creation Steps

### Step 1: Create Base Roles

1. Open Power Platform admin center
2. Select governance environment
3. Settings > Users + permissions > Security roles
4. Create new role for each (ELM Requester, ELM Approver, ELM Admin, ELM Auditor)

### Step 2: Configure EnvironmentRequest Privileges

For each role:

1. Open role > Custom Entities tab
2. Find `fsi_environmentrequest`
3. Set privileges per matrix above
4. Use circle icons to set depth (User/BU/Org)

### Step 3: Configure ProvisioningLog Privileges

For each role:

1. Custom Entities tab
2. Find `fsi_provisioninglog`
3. Set privileges per matrix above
4. **ELM Admin: Verify NO Write or Delete**

### Step 4: Create Field Security Profile (Approvers)

1. Settings > Security > Field Security Profiles
2. New profile: "ELM Approver Fields"
3. Add EnvironmentRequest fields
4. Set permissions per field-level security table
5. Associate with ELM Approver role

### Step 5: Assign Roles

1. Users + permissions > Users
2. Select user
3. Manage security roles
4. Assign appropriate role(s)

---

## Audit Verification

### Weekly Immutability Check

Run weekly to verify no unauthorized modifications:

```bash
python scripts/validate_immutability.py \
  --environment-url https://<org>.crm.dynamics.com
```

### Role Privilege Audit

Run after any role changes:

```bash
python scripts/verify_role_privileges.py \
  --environment-url https://<org>.crm.dynamics.com \
  --output-path ./reports/role-audit.json
```

### Dataverse Audit Log Query

Query for modification attempts on ProvisioningLog:

```xml
<fetch>
  <entity name="audit">
    <attribute name="createdon"/>
    <attribute name="userid"/>
    <attribute name="operation"/>
    <filter type="and">
      <condition attribute="objecttypecode" operator="eq" value="fsi_provisioninglog"/>
      <condition attribute="operation" operator="in">
        <value>2</value><!-- Update -->
        <value>3</value><!-- Delete -->
      </condition>
    </filter>
  </entity>
</fetch>
```

Any results indicate attempted (but blocked) modifications.

---

## Next Steps

After configuring security roles:

1. [Register Service Principal](./service-principal-setup.md)
2. [Configure Power Automate flows](./flow-configuration.md)
