# Power Automate Flow Configuration

Detailed specifications for the four provisioning flows.

## Flow Architecture

```
                    ┌─────────────────────────────┐
                    │  Copilot Intake Agent       │
                    │  (submits request)          │
                    └─────────────┬───────────────┘
                                  │
                                  v
                    ┌─────────────────────────────┐
                    │  EnvironmentRequest         │
                    │  (state = Submitted)        │
                    └─────────────┬───────────────┘
                                  │
                    ┌─────────────v───────────────┐
                    │  Flow 0: Zone 1 Auto-       │
                    │  Approval (auto-approve     │
                    │  Zone 1 requests)           │
                    └─────────────┬───────────────┘
                                  │
                    ┌─────────────v───────────────┐
                    │  EnvironmentRequest         │
                    │  (state = Approved)         │
                    └─────────────┬───────────────┘
                                  │
                    ┌─────────────v───────────────┐
                    │  Flow 1: Main Provisioning  │
                    │  - Create environment       │
                    │  - Poll until ready         │
                    │  - Enable Managed           │
                    │  - Assign to group          │
                    └─────────────┬───────────────┘
                                  │
          ┌───────────────────────┼───────────────────────┐
          │                       │                       │
          v                       v                       v
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│ Flow 2: Security│   │ Flow 3: Baseline│   │ Notify Requester│
│ Group Binding   │   │ Configuration   │   │ (completion)    │
│ (Zone 2/3 only) │   │ (child flow)    │   │                 │
└─────────────────┘   └─────────────────┘   └─────────────────┘
```

> **Zone 1 Auto-Approval:** Zone 1 requests are auto-approved by Flow 0 (below), which
> transitions `fsi_state` from Submitted (2) to Approved (4) when `fsi_zone eq 1`.
> Zone 2/3 requests require manual approval before reaching the Approved state.

> **Choice Field Mapping:** Copilot Studio outputs string values for choice fields
> (e.g., `"Production"`, `"Confidential"`), but Dataverse stores integer values.
> The bridging Power Automate flow that creates the EnvironmentRequest record must
> map strings to integers before writing:
>
> | Field | String → Integer Mapping |
> |-------|--------------------------|
> | `fsi_environmenttype` | Sandbox=1, Production=2, Developer=3 |
> | `fsi_region` | United States=1, Europe=2, United Kingdom=3, Australia=4 |
> | `fsi_datasensitivity` | Public=1, Internal=2, Confidential=3, Restricted=4 |
> | `fsi_expectedusers` | Just me (1)=1, Small team (2-10)=2, Large team (11-50)=3, Department (50+)=4 |

## Connections Required

| Connector | Purpose | License |
|-----------|---------|---------|
| **Dataverse** | Read/write tables | Included |
| **Power Platform for Admins V2** | Create environment | Premium |
| **HTTP with Microsoft Entra ID** | BAP API, Graph API | Premium |
| **Azure Key Vault** | Retrieve SP credentials | Premium |
| **Office 365 Outlook** | Send notifications | Included |
| **Microsoft Teams** | Post notifications | Included |

---

## Flow 0: Zone 1 Auto-Approval Flow

Zone 1 requests have minimal governance and should be auto-approved without manual intervention.

### Trigger Configuration

| Setting | Value |
|---------|-------|
| Type | Dataverse - When a row is added, modified or deleted |
| Table | EnvironmentRequest |
| Scope | Organization |
| Change type | Add, Modify |
| Filter rows | `fsi_state eq 2 and fsi_zone eq 1` (Submitted + Zone 1) |
| Select columns | `fsi_state,fsi_zone` |
| Concurrency | `{ "concurrency": { "runs": 5 } }` |

### Step 1: Update State to Approved

**Action:** Dataverse - Update a row

| Parameter | Value |
|-----------|-------|
| Table | EnvironmentRequest |
| Row ID | `triggerBody()?['fsi_environmentrequestid']` |
| State | `4` (Approved) |
| Approved On | `utcNow()` |

> **Note:** The `fsi_approver` field is a Lookup (User) type. For auto-approved
> Zone 1 requests, leave `fsi_approver` null — do not set it to a string value.
> The Actor field in the ProvisioningLog (Step 2) records that the approval was
> performed by the system.

### Step 2: Log Auto-Approval

**Action:** Dataverse - Add a new row (ProvisioningLog)

| Parameter | Value |
|-----------|-------|
| Name (Log ID) | `concat('LOG-', triggerBody()?['fsi_requestnumber'], '-1')` |
| Environment Request | `triggerBody()?['fsi_environmentrequestid']` |
| Sequence | `1` |
| Action | `4` (Approved) |
| Actor | `System` |
| Actor Type | `3` (System) |
| Timestamp | `utcNow()` |
| Success | `true` |
| Correlation ID | `workflow()?['run']?['name']` |
| Action Details | `{"autoApproved": true, "reason": "Zone 1 - minimal governance"}` |

> **Naming Convention:** All ProvisioningLog rows require the `fsi_name` (Name / Log ID)
> primary name column. Use the pattern `LOG-{requestNumber}-{sequence}` (e.g.,
> `LOG-REQ-001-1`) for consistent, traceable log entries across all flows.

> **Note:** This flow automatically transitions Zone 1 requests to Approved state,
> which then triggers the Main Provisioning Flow (Flow 1).

### Error Handling Scope

Wrap the auto-approval steps in an error-handling scope:

```json
{
  "Handle_AutoApproval_Error": {
    "type": "Scope",
    "actions": {
      "Log_AutoApproval_Failed": {
        "type": "Dataverse - Add a new row",
        "inputs": {
          "table": "ProvisioningLog",
          "name": "concat('LOG-', triggerBody()?['fsi_requestnumber'], '-ERR-1')",
          "environmentRequest": "triggerBody()?['fsi_environmentrequestid']",
          "sequence": 1,
          "action": "4",
          "actorType": "3",
          "success": false,
          "correlationId": "workflow()?['run']?['name']",
          "actionDetails": "{\"error\": \"@{actions('Update_State_to_Approved')?['error']?['message']}\"}"
        }
      },
      "Notify_Admin_AutoApproval_Failed": {
        "type": "Office 365 Outlook - Send an email (V2)",
        "inputs": {
          "to": "<admin-distribution-list>",
          "subject": "Zone 1 Auto-Approval Failed: @{triggerBody()?['fsi_requestnumber']}",
          "body": "Auto-approval failed for request @{triggerBody()?['fsi_requestnumber']}. The request remains in Submitted state. Error: @{actions('Update_State_to_Approved')?['error']?['message']}"
        }
      }
    },
    "runAfter": {
      "Auto_Approval_Scope": ["Failed", "TimedOut"]
    }
  }
}
```

> **⚠ Zone 2/3 Approval Routing (Not Yet Implemented):** Zone 2 and Zone 3 requests
> require a separate approval routing flow to transition from Submitted (2) →
> PendingApproval (3) → Approved (4). Without this flow, Zone 2/3 requests will
> remain in Submitted state and never reach provisioning. Implementation should use:
>
> - **Trigger:** Dataverse – When a row is added, modified or deleted (Add, Modify), filter `fsi_state eq 2 and fsi_zone ne 1`
> - **Step 1:** Set `fsi_state` to PendingApproval (3), log action `3` (PendingApproval) to ProvisioningLog
> - **Step 2 (Zone 2):** Start approval via the Approvals connector — single approval routed to requester's manager. Resolve manager via Graph API: `GET /v1.0/users/{requester-upn}/manager`
> - **Step 2 (Zone 3):** Start sequential approval — first to requester's manager, then to compliance officer (configured via environment variable or Dataverse lookup)
> - **On Approve:** Set `fsi_state` to Approved (4), `fsi_approver` to approver (Lookup), `fsi_approvedon` to `utcNow()`, log action `4` (Approved) to ProvisioningLog
> - **On Reject:** Set `fsi_state` to Rejected (5), `fsi_approvalcomments` to rejection reason, log action `5` (Rejected) to ProvisioningLog, notify requester via email
> - **Error Handling:** If approval times out (configurable, default 7 days), set `fsi_state` to Rejected (5) with timeout reason
>
> **Workaround (until implemented):** Zone 2/3 requests can be manually advanced by
> an ELM Admin updating `fsi_state` to Approved (4) in the model-driven app, which
> will trigger Flow 1 (Main Provisioning).
>
> **⚠ Segregation-of-Duties Caveat:** This workaround bypasses the segregation-of-duties
> controls described in [security-roles.md](./security-roles.md). The ELM Admin who
> manually approves also has write access to the request, meaning the same person could
> both submit and approve. Until the approval routing flow is implemented, organizations
> should enforce a compensating control: require that the ELM Admin who advances the
> request is not the original requester. Document each manual approval in the
> ProvisioningLog with action `4` (Approved), Actor set to the admin's UPN, and
> Action Details noting `{"manualApproval": true, "reason": "<justification>"}`.
>
> This is tracked as a planned implementation item.

---

## Flow 1: Main Provisioning Flow

### Trigger Configuration

| Setting | Value |
|---------|-------|
| Type | Dataverse - When a row is modified |
| Table | EnvironmentRequest |
| Scope | Organization |
| Filter rows | `fsi_state eq 4` (Approved) |
| Select columns | All |

### Variables

Initialize at flow start:

| Variable | Type | Expression |
|----------|------|------------|
| `pollCount` | Integer | `0` |
| `maxPolls` | Integer | `120` |
| `logSequence` | Integer | `0` (populated dynamically in Step 1b) |
| `environmentGroupName` | String | See expression below |
| `resolvedGroupId` | String | (populated later) |
| `auditRetentionDays` | Integer | See expression below |
| `sessionTimeoutMinutes` | Integer | See expression below |

**Zone-based expressions:**

```
// environmentGroupName
if(equals(triggerBody()?['fsi_zone'], 1),
  'FSI-Zone1-PersonalProductivity',
  if(equals(triggerBody()?['fsi_zone'], 2),
    'FSI-Zone2-TeamCollaboration',
    'FSI-Zone3-EnterpriseManagedEnvironment'
  )
)

// auditRetentionDays
if(equals(triggerBody()?['fsi_zone'], 3), 2557,
  if(equals(triggerBody()?['fsi_zone'], 2), 365, 180)
)

// sessionTimeoutMinutes
if(equals(triggerBody()?['fsi_zone'], 3), 120,
  if(equals(triggerBody()?['fsi_zone'], 2), 480, 1440)
)
```

### Step 1: Update Request State

**Action:** Dataverse - Update a row

| Parameter | Value |
|-----------|-------|
| Table | EnvironmentRequest |
| Row ID | `triggerBody()?['fsi_environmentrequestid']` |
| State | `6` (Provisioning) |
| Provisioning Started | `utcNow()` |

### Step 1b: Query Current Log Sequence

**Action:** Dataverse - List rows

| Parameter | Value |
|-----------|-------|
| Table | ProvisioningLog |
| Filter rows | `_fsi_environmentrequest_value eq '@{triggerBody()?['fsi_environmentrequestid']}'` |
| Sort by | `fsi_sequence desc` |
| Row count | `1` |

**Post-Action:** Set `logSequence` variable:

```
if(
  empty(outputs('Query_Current_Log_Sequence')?['body/value']),
  0,
  first(outputs('Query_Current_Log_Sequence')?['body/value'])?['fsi_sequence']
)
```

> **Why dynamic sequencing:** Prior flows (Flow 0 for Zone 1 auto-approval, or
> the approval routing flow for Zone 2/3) may have already created ProvisioningLog
> entries. Querying the current max sequence prevents duplicate `fsi_name` and
> `fsi_sequence` values, ensuring the immutable audit trail remains consistent.

### Step 2: Log Provisioning Started

**Action:** Dataverse - Add a new row

| Parameter | Value |
|-----------|-------|
| Table | ProvisioningLog |
| Name (Log ID) | `concat('LOG-', triggerBody()?['fsi_requestnumber'], '-', string(add(variables('logSequence'), 1)))` |
| Environment Request | `triggerBody()?['fsi_environmentrequestid']` |
| Sequence | `add(variables('logSequence'), 1)` |
| Action | `6` (ProvisioningStarted) |
| Actor | `<Service-Principal-AppId>` |
| Actor Type | `2` (ServicePrincipal) |
| Timestamp | `utcNow()` |
| Success | `true` |
| Correlation ID | `workflow()?['run']?['name']` |
| Action Details | See JSON below |

```json
{
  "requestNumber": "@{triggerBody()?['fsi_requestnumber']}",
  "environmentName": "@{triggerBody()?['fsi_environmentname']}",
  "zone": @{triggerBody()?['fsi_zone']},
  "region": "@{triggerBody()?['fsi_region']}"
}
```

### Step 3: Create Environment (Scope)

Wrap in error-handling scope:

**Action:** Power Platform for Admins V2 - Create Environment

| Parameter | Value |
|-----------|-------|
| Location | `@{if(equals(triggerBody()?['fsi_region'], 1), 'unitedstates', if(equals(triggerBody()?['fsi_region'], 2), 'europe', if(equals(triggerBody()?['fsi_region'], 3), 'unitedkingdom', 'australia')))}` |
| Display Name | `@{triggerBody()?['fsi_environmentname']}` |
| Environment Type | `@{if(equals(triggerBody()?['fsi_environmenttype'], 1), 'Sandbox', if(equals(triggerBody()?['fsi_environmenttype'], 2), 'Production', 'Developer'))}` |
| Currency | `USD` |
| Language | `1033` |

### Step 4: Poll Until Ready (Do Until)

**Do Until Configuration:**

| Setting | Value |
|---------|-------|
| Condition | `or(equals(body('Get_Environment')?['properties']?['provisioningState'], 'Succeeded'), equals(body('Get_Environment')?['properties']?['provisioningState'], 'Failed'))` |
| Limit Count | `120` |
| Timeout | `PT60M` |

**Loop Actions:**

1. **Delay:** 30 seconds
2. **Get Environment:** Power Platform for Admins V2
3. **Increment pollCount:** Add 1
4. **Check for timeout:** If `pollCount >= maxPolls`, terminate

### Step 5: Log Environment Created

**Action:** Dataverse - Add a new row (ProvisioningLog)

| Parameter | Value |
|-----------|-------|
| Name (Log ID) | `concat('LOG-', triggerBody()?['fsi_requestnumber'], '-', string(add(variables('logSequence'), 2)))` |
| Environment Request | `triggerBody()?['fsi_environmentrequestid']` |
| Sequence | `add(variables('logSequence'), 2)` |
| Action | `7` (EnvironmentCreated) |
| Action Details | Include environmentId, environmentUrl |

### Step 6: Enable Managed Environment

**Action:** HTTP with Microsoft Entra ID (preauthorized)

| Parameter | Value |
|-----------|-------|
| Method | `POST` |
| Base Resource URL | `https://api.bap.microsoft.com` |
| Azure AD Resource URI | `https://api.bap.microsoft.com` |
| URI | `/providers/Microsoft.BusinessAppPlatform/environments/@{outputs('Create_Environment')?['body']?['name']}/enableGovernanceConfiguration?api-version=2021-04-01` |
| Body | `{"protectionLevel": "Standard"}` |

**Headers:**

```json
{
  "Content-Type": "application/json"
}
```

**Retry Policy:**

```json
{
  "type": "exponential",
  "count": 3,
  "interval": "PT30S",
  "minimumInterval": "PT10S",
  "maximumInterval": "PT1H"
}
```

### Step 7: Log Managed Enabled

Log action `8` (ManagedEnabled) to ProvisioningLog with Name (Log ID) `concat('LOG-', triggerBody()?['fsi_requestnumber'], '-', string(add(variables('logSequence'), 3)))`.

### Step 8: Resolve Environment Group ID

**Action:** HTTP with Microsoft Entra ID (preauthorized)

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| Base Resource URL | `https://api.bap.microsoft.com` |
| Azure AD Resource URI | `https://api.bap.microsoft.com` |
| URI | `/providers/Microsoft.BusinessAppPlatform/environmentGroups?api-version=2021-04-01` |

**Retry Policy:**

```json
{
  "type": "exponential",
  "count": 3,
  "interval": "PT30S",
  "minimumInterval": "PT10S",
  "maximumInterval": "PT1H"
}
```

**Post-Action:** Filter array to find group by displayName:

```
@first(
  filter(
    body('Get_Environment_Groups')?['value'],
    item()?['properties']?['displayName'],
    variables('environmentGroupName')
  )
)?['name']
```

Set result to `resolvedGroupId` variable.

### Step 9: Assign to Environment Group

**Action:** HTTP with Microsoft Entra ID (preauthorized)

| Parameter | Value |
|-----------|-------|
| Method | `POST` |
| URI | `/providers/Microsoft.BusinessAppPlatform/environmentGroups/@{variables('resolvedGroupId')}/addEnvironments?api-version=2021-04-01` |
| Body | See below |

```json
{
  "environments": [
    {
      "id": "@{outputs('Create_Environment')?['body']?['name']}"
    }
  ]
}
```

**Retry Policy:**

```json
{
  "type": "exponential",
  "count": 3,
  "interval": "PT30S",
  "minimumInterval": "PT10S",
  "maximumInterval": "PT1H"
}
```

### Step 10: Log Group Assigned

Log action `9` (GroupAssigned) to ProvisioningLog with Name (Log ID) `concat('LOG-', triggerBody()?['fsi_requestnumber'], '-', string(add(variables('logSequence'), 4)))`.

### Step 11: Call Baseline Configuration (Child Flow)

**Action:** Run a Child Flow

| Parameter | Value |
|-----------|-------|
| Child flow | Baseline Configuration Flow |
| environmentId | `outputs('Create_Environment')?['body']?['name']` |
| environmentUrl | `outputs('Create_Environment')?['body']?['properties']?['linkedEnvironmentMetadata']?['instanceUrl']` |
| zone | `triggerBody()?['fsi_zone']` |
| requestId | `triggerBody()?['fsi_environmentrequestid']` |
| requestNumber | `triggerBody()?['fsi_requestnumber']` |
| logSequence | `variables('logSequence')` |

**Post-Action:** Update `logSequence` from child flow's return value:

```
Set variable: logSequence = outputs('Call_Baseline_Configuration')?['body']?['finalLogSequence']
```

> **Why:** Flow 3 creates its own ProvisioningLog entries, incrementing from the
> `logSequence` value passed in. The parent flow must adopt the child's final sequence
> so that Steps 12 and 14 continue the numbering without gaps or collisions.

### Step 12: Bind Security Group (Zone 2/3)

**Condition:** `triggerBody()?['fsi_zone'] >= 2 and triggerBody()?['fsi_securitygroupid'] ne null`

If true, bind the security group to the environment before marking provisioning complete.
This eliminates the access window that would exist if binding were deferred to a separate flow.

**Action:** HTTP with Microsoft Entra ID (preauthorized) — Validate Group

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| Base Resource URL | `https://graph.microsoft.com` |
| URI | `/v1.0/groups/@{triggerBody()?['fsi_securitygroupid']}` |

If 404, log error and skip binding.

**Action:** Power Platform for Admins V2 - Update Environment

| Parameter | Value |
|-----------|-------|
| Environment | `outputs('Create_Environment')?['body']?['name']` |
| Security Group ID | `triggerBody()?['fsi_securitygroupid']` |

**Action:** Dataverse - Add a new row (ProvisioningLog)

| Parameter | Value |
|-----------|-------|
| Name (Log ID) | `concat('LOG-', triggerBody()?['fsi_requestnumber'], '-', string(add(variables('logSequence'), 1)))` |
| Environment Request | `triggerBody()?['fsi_environmentrequestid']` |
| Sequence | `add(variables('logSequence'), 1)` |
| Action | `10` (SecurityGroupBound) |
| Actor | `<Service-Principal-AppId>` |
| Actor Type | `2` (ServicePrincipal) |
| Timestamp | `utcNow()` |
| Success | `true` |

### Step 13: Update Request Complete

**Action:** Dataverse - Update a row

| Parameter | Value |
|-----------|-------|
| State | `7` (Completed) |
| Environment ID | `outputs('Create_Environment')?['body']?['name']` |
| Environment URL | `outputs('Create_Environment')?['body']?['properties']?['linkedEnvironmentMetadata']?['instanceUrl']` |
| Provisioning Completed | `utcNow()` |

### Step 14: Log Provisioning Completed

Log action `13` (ProvisioningCompleted) to ProvisioningLog. Compute the final sequence as `add(variables('logSequence'), if(equals(triggerBody()?['fsi_zone'], 1), 1, 2))` — incrementing by 1 for Zone 1 (no security group step), or by 2 for Zone 2/3 (after Step 12's increment). Name (Log ID): `concat('LOG-', triggerBody()?['fsi_requestnumber'], '-', string(<computed final sequence>))`.

### Step 15: Resolve Requester Email

**Action:** Dataverse - Get a row by ID

| Parameter | Value |
|-----------|-------|
| Table | Users (systemusers) |
| Row ID | `triggerBody()?['_fsi_requester_value']` |
| Select columns | `internalemailaddress` |

### Step 16: Notify Requester

**Action:** Office 365 Outlook - Send an email (V2)

| Parameter | Value |
|-----------|-------|
| To | `outputs('Resolve_Requester_Email')?['body/internalemailaddress']` |
| Subject | `Your environment is ready: @{triggerBody()?['fsi_environmentname']}` |
| Body | See template below |

```html
<p>Your environment request has been provisioned successfully.</p>

<h3>Environment Details</h3>
<ul>
  <li><strong>Name:</strong> @{triggerBody()?['fsi_environmentname']}</li>
  <li><strong>URL:</strong> @{outputs('Create_Environment')?['body']?['properties']?['linkedEnvironmentMetadata']?['instanceUrl']}</li>
  <li><strong>Zone:</strong> Zone @{triggerBody()?['fsi_zone']}</li>
  <li><strong>Request:</strong> @{triggerBody()?['fsi_requestnumber']}</li>
</ul>

<h3>Governance Configuration Applied</h3>
<ul>
  <li>Managed Environment: Enabled</li>
  <li>Environment Group: @{variables('environmentGroupName')}</li>
  <li>Audit Retention: @{variables('auditRetentionDays')} days</li>
  <li>Session Timeout: @{variables('sessionTimeoutMinutes')} minutes</li>
</ul>

<p>You can access your environment now.</p>
```

### Error Handling Scope

Wrap the main flow in error-handling scopes:

```json
{
  "Handle_Provisioning_Error": {
    "type": "Scope",
    "actions": {
      "Log_ProvisioningFailed": { ... },
      "Update_Request_Failed": {
        "inputs": {
          "fsi_state": 8
        }
      },
      "Notify_Admin": { ... }
    },
    "runAfter": {
      "Main_Provisioning_Scope": ["Failed", "TimedOut"]
    }
  }
}
```

---

## Flow 2: Security Group Binding Flow (Verification / Retry)

> **Note:** As of the current design, security group binding is performed inline in
> Flow 1, Step 12 (before state transitions to Completed) to eliminate the access
> window. Flow 2 serves as a **verification and retry mechanism** — it detects cases
> where Flow 1's inline binding failed or was skipped, and re-applies the security
> group binding. For environments where Step 12 succeeded, Flow 2's validation
> will confirm the binding is already in place and log accordingly.

### Trigger Configuration

| Setting | Value |
|---------|-------|
| Type | Dataverse - When a row is modified |
| Table | EnvironmentRequest |
| Filter rows | `fsi_state eq 7 and fsi_securitygroupid ne null` |

### Step 1: Validate Security Group

**Action:** HTTP with Microsoft Entra ID (preauthorized)

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| Base Resource URL | `https://graph.microsoft.com` |
| URI | `/v1.0/groups/@{triggerBody()?['fsi_securitygroupid']}` |

**Retry Policy:**

```json
{
  "type": "exponential",
  "count": 3,
  "interval": "PT30S",
  "minimumInterval": "PT10S",
  "maximumInterval": "PT1H"
}
```

**Error Handling:** If 404, log error and fail gracefully.

### Step 2: Force Sync Service Principal User

**Step 2a: Check if SP user already exists**

**Action:** HTTP with Microsoft Entra ID (preauthorized)

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| Base Resource URL | Environment URL from request |
| URI | `/api/data/v9.2/systemusers?$filter=applicationid eq '<service-principal-app-id>'&$select=systemuserid` |

**Condition:** `empty(body('Check_SP_User_Exists')?['value'])` — only proceed to Step 2b if no existing user was found.

**Step 2b: Create SP user (if not exists)**

**Action:** HTTP with Microsoft Entra ID (preauthorized)

| Parameter | Value |
|-----------|-------|
| Method | `POST` |
| Base Resource URL | Environment URL from request |
| URI | `/api/data/v9.2/systemusers` |
| Body | See below |

```json
{
  "domainname": "<service-principal-upn>",
  "applicationid": "<service-principal-app-id>",
  "azureactivedirectoryobjectid": "<service-principal-object-id>",
  "businessunitid@odata.bind": "/businessunits(<root-bu-id>)"
}
```

> **Resolving Placeholder Values:** The placeholders above must be replaced with
> actual values at design time or resolved dynamically at runtime:
>
> | Placeholder | Resolution |
> |-------------|------------|
> | `<service-principal-upn>` | Retrieve from Azure Key Vault secret `ELM-ServicePrincipal-UPN`, or configure as a flow environment variable |
> | `<service-principal-app-id>` | Retrieve from Azure Key Vault secret `ELM-ServicePrincipal-AppId`, or use the same `client_id` used for the HTTP with Entra ID connection |
> | `<service-principal-object-id>` | Retrieve via Graph API: `GET /v1.0/servicePrincipals(appId='<app-id>')` → `id` field, or store in Key Vault secret `ELM-ServicePrincipal-ObjectId` |
> | `<root-bu-id>` | Query from target environment: `GET /api/data/v9.2/businessunits?$filter=parentbusinessunitid eq null&$select=businessunitid` → first result's `businessunitid` |
>
> **Recommended approach:** Store all Service Principal identifiers in Azure Key Vault
> during the registration step (Phase 2 of [SETUP_CHECKLIST.md](../SETUP_CHECKLIST.md)),
> then retrieve them via the Key Vault connector at the start of the flow.

**Retry Policy:**

```json
{
  "type": "exponential",
  "count": 3,
  "interval": "PT30S",
  "minimumInterval": "PT10S",
  "maximumInterval": "PT1H"
}
```

### Step 3: Bind Security Group

**Action:** Power Platform for Admins V2 - Update Environment

| Parameter | Value |
|-----------|-------|
| Environment | Environment ID from request |
| Security Group ID | `triggerBody()?['fsi_securitygroupid']` |

### Step 4: Log Security Group Bound

Log action `10` (SecurityGroupBound) to ProvisioningLog. Query the current max `fsi_sequence` for the request (as in Flow 1 Step 1b) and use `add(maxSequence, 1)` for the sequence and Name (Log ID): `concat('LOG-', triggerBody()?['fsi_requestnumber'], '-', string(add(maxSequence, 1)))`.

---

## Flow 3: Baseline Configuration Flow (Child)

### Input Parameters

| Parameter | Type | Required |
|-----------|------|----------|
| environmentId | String | Yes |
| environmentUrl | String | Yes |
| zone | Integer | Yes |
| requestId | GUID | Yes |
| requestNumber | String | Yes |
| logSequence | Integer | Yes |

### Step 1: Get Organization ID

**Action:** HTTP with Microsoft Entra ID (preauthorized)

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| Base Resource URL | `@{triggerBody()?['environmentUrl']}` |
| URI | `/api/data/v9.2/organizations?$select=organizationid,name` |

Extract: `@first(body('Get_Organization')?['value'])?['organizationid']`

### Step 2: Enable Auditing

> **Error Handling:** Wrap Steps 2–4 in individual Try/Catch scopes so that a failure
> in one configuration step does not prevent subsequent steps from executing. Each scope
> should log a ProvisioningLog entry with `fsi_success = false` and the error message
> if the step fails, then continue to the next step. After all steps complete, evaluate
> whether any failed and return the aggregate status to the parent flow.

**Scope: Apply_Auditing_Settings**

**Action:** HTTP with Microsoft Entra ID (preauthorized)

| Parameter | Value |
|-----------|-------|
| Method | `PATCH` |
| URI | `/api/data/v9.2/organizations(@{variables('orgId')})` |
| Body | See below |

```json
{
  "isauditenabled": true,
  "isuseraccessauditenabled": true,
  "auditretentionperiodv2": @{if(equals(triggerBody()?['zone'], 3), 2557, if(equals(triggerBody()?['zone'], 2), 365, 180))}
}
```

### Step 3: Set Session Timeout

**Scope: Apply_Session_Timeout**

**Action:** HTTP with Microsoft Entra ID (preauthorized)

| Parameter | Value |
|-----------|-------|
| Method | `PATCH` |
| URI | `/api/data/v9.2/organizations(@{variables('orgId')})` |
| Body | See below |

```json
{
  "sessiontimeoutenabled": true,
  "sessiontimeoutinmins": @{if(equals(triggerBody()?['zone'], 3), 120, if(equals(triggerBody()?['zone'], 2), 480, 1440))}
}
```

### Step 4: Configure Sharing Limits (Optional)

**Scope: Apply_Sharing_Limits**

**Action:** HTTP with Microsoft Entra ID (preauthorized)

| Parameter | Value |
|-----------|-------|
| Method | `PATCH` |
| Base Resource URL | `https://api.bap.microsoft.com` |
| Azure AD Resource URI | `https://api.bap.microsoft.com` |
| URI | `/providers/Microsoft.BusinessAppPlatform/environments/@{triggerBody()?['environmentId']}/governanceConfiguration?api-version=2021-04-01` |
| Body | See below |

```json
{
  "settings": {
    "extendedSettings": {
      "limitSharingToSecurityGroups": "@{if(equals(triggerBody()?['zone'], 1), 'false', 'true')}",
      "excludeEnvironmentFromAnalysis": "false"
    }
  }
}
```

### Step 5: Log Baseline Applied

Log action `11` (BaselineConfigApplied) to ProvisioningLog with Name (Log ID) `concat('LOG-', triggerBody()?['requestNumber'], '-', string(add(triggerBody()?['logSequence'], 5)))`.

Include in the Action Details which configuration steps succeeded or failed:

```json
{
  "auditingEnabled": "@{equals(result('Apply_Auditing_Settings'), 'Succeeded')}",
  "sessionTimeoutSet": "@{equals(result('Apply_Session_Timeout'), 'Succeeded')}",
  "sharingLimitsConfigured": "@{equals(result('Apply_Sharing_Limits'), 'Succeeded')}"
}
```

> **Partial Failure:** Set `fsi_success` to `true` only if all scopes succeeded.
> If any scope failed, set `fsi_success` to `false` and include error details in
> `fsi_errormessage` so the parent flow can decide whether to retry or fail.

### Return Value

| Output | Type | Description |
|--------|------|-------------|
| success | Boolean | Whether all configuration steps succeeded |
| finalLogSequence | Integer | The last `fsi_sequence` value written by this flow |

Return success/failure status and the final log sequence number to the parent flow.
The parent flow must update its `logSequence` variable with `finalLogSequence` before
creating subsequent log entries (Steps 12 and 14).

---

## Concurrency Configuration

### Trigger Settings

```json
"runtimeConfiguration": {
  "concurrency": {
    "runs": 5
  }
}
```

Limits concurrent provisioning to 5 environments to prevent API throttling.

---

## Testing

### Test Cases

| Scenario | Expected Result |
|----------|-----------------|
| Zone 1 request approved | Environment created, minimal config |
| Zone 2 request approved | Environment + security group binding |
| Zone 3 request approved | Environment + security group + full baseline |
| Environment creation fails | State = Failed, error logged |
| Polling timeout | State = Failed, timeout logged |
| Security group not found | Error logged, flow continues |

### Manual Test

1. Create test EnvironmentRequest record
2. Set state to Approved (4)
3. Monitor flow execution
4. Verify ProvisioningLog entries
5. Check environment configuration

---

## Next Steps

After configuring flows:

1. [Build Copilot Studio agent](./copilot-agent-setup.md)
2. [Review troubleshooting guide](./troubleshooting.md)
