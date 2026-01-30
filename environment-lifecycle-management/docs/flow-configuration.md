# Power Automate Flow Configuration

Detailed specifications for the three provisioning flows.

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

### Step 1: Get Service Principal Secret

**Action:** Azure Key Vault - Get secret

| Parameter | Value |
|-----------|-------|
| Vault name | `<your-vault-name>` |
| Secret name | `ELM-ServicePrincipal-Secret` |

**Security Configuration:**

```json
"runtimeConfiguration": {
  "secureData": {
    "properties": ["inputs", "outputs"]
  }
}
```

### Step 2: Update Request State

**Action:** Dataverse - Update a row

| Parameter | Value |
|-----------|-------|
| Table | EnvironmentRequest |
| Row ID | `triggerBody()?['fsi_environmentrequestid']` |
| State | `6` (Provisioning) |
| Provisioning Started | `utcNow()` |

### Step 3: Log Provisioning Started

**Action:** Dataverse - Add a new row

| Parameter | Value |
|-----------|-------|
| Table | ProvisioningLog |
| Environment Request | `triggerBody()?['fsi_environmentrequestid']` |
| Sequence | `1` |
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

### Step 4: Create Environment (Scope)

Wrap in error-handling scope:

**Action:** Power Platform for Admins V2 - Create Environment

| Parameter | Value |
|-----------|-------|
| Location | `@{if(equals(triggerBody()?['fsi_region'], 1), 'unitedstates', if(equals(triggerBody()?['fsi_region'], 2), 'europe', if(equals(triggerBody()?['fsi_region'], 3), 'unitedkingdom', 'australia')))}` |
| Display Name | `@{triggerBody()?['fsi_environmentname']}` |
| Environment Type | `@{if(equals(triggerBody()?['fsi_environmenttype'], 1), 'Sandbox', if(equals(triggerBody()?['fsi_environmenttype'], 2), 'Production', 'Developer'))}` |
| Currency | `USD` |
| Language | `1033` |

### Step 5: Poll Until Ready (Do Until)

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

### Step 6: Log Environment Created

**Action:** Dataverse - Add a new row (ProvisioningLog)

| Parameter | Value |
|-----------|-------|
| Sequence | `2` |
| Action | `7` (EnvironmentCreated) |
| Action Details | Include environmentId, environmentUrl |

### Step 7: Enable Managed Environment

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

### Step 8: Log Managed Enabled

Log action `8` (ManagedEnabled) to ProvisioningLog.

### Step 9: Resolve Environment Group ID

**Action:** HTTP with Microsoft Entra ID (preauthorized)

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| URI | `/providers/Microsoft.BusinessAppPlatform/environmentGroups?api-version=2021-04-01` |

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

### Step 10: Assign to Environment Group

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

### Step 11: Log Group Assigned

Log action `9` (GroupAssigned) to ProvisioningLog.

### Step 12: Call Baseline Configuration (Child Flow)

**Action:** Run a Child Flow

| Parameter | Value |
|-----------|-------|
| Child flow | Baseline Configuration Flow |
| environmentId | `outputs('Create_Environment')?['body']?['name']` |
| environmentUrl | `outputs('Create_Environment')?['body']?['properties']?['linkedEnvironmentMetadata']?['instanceUrl']` |
| zone | `triggerBody()?['fsi_zone']` |
| requestId | `triggerBody()?['fsi_environmentrequestid']` |

### Step 13: Update Request Complete

**Action:** Dataverse - Update a row

| Parameter | Value |
|-----------|-------|
| State | `7` (Completed) |
| Environment ID | `outputs('Create_Environment')?['body']?['name']` |
| Environment URL | `outputs('Create_Environment')?['body']?['properties']?['linkedEnvironmentMetadata']?['instanceUrl']` |
| Provisioning Completed | `utcNow()` |

### Step 14: Log Provisioning Completed

Log action `13` (ProvisioningCompleted) to ProvisioningLog.

### Step 15: Notify Requester

**Action:** Office 365 Outlook - Send an email (V2)

| Parameter | Value |
|-----------|-------|
| To | `triggerBody()?['_fsi_requester_value@OData.Community.Display.V1.FormattedValue']` |
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

## Flow 2: Security Group Binding Flow

### Trigger Configuration

| Setting | Value |
|---------|-------|
| Type | Dataverse - When a row is modified |
| Table | EnvironmentRequest |
| Filter rows | `fsi_state eq 6 and fsi_securitygroupid ne null` |

### Step 1: Validate Security Group

**Action:** HTTP with Microsoft Entra ID (preauthorized)

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| Base Resource URL | `https://graph.microsoft.com` |
| URI | `/v1.0/groups/@{triggerBody()?['fsi_securitygroupid']}` |

**Error Handling:** If 404, log error and fail gracefully.

### Step 2: Force Sync Service Principal User

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

### Step 3: Bind Security Group

**Action:** Power Platform for Admins V2 - Update Environment

| Parameter | Value |
|-----------|-------|
| Environment | Environment ID from request |
| Security Group ID | `triggerBody()?['fsi_securitygroupid']` |

### Step 4: Log Security Group Bound

Log action `10` (SecurityGroupBound) to ProvisioningLog.

---

## Flow 3: Baseline Configuration Flow (Child)

### Input Parameters

| Parameter | Type | Required |
|-----------|------|----------|
| environmentId | String | Yes |
| environmentUrl | String | Yes |
| zone | Integer | Yes |
| requestId | GUID | Yes |

### Step 1: Get Organization ID

**Action:** HTTP with Microsoft Entra ID (preauthorized)

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| Base Resource URL | `@{triggerBody()?['environmentUrl']}` |
| URI | `/api/data/v9.2/organizations?$select=organizationid,name` |

Extract: `@first(body('Get_Organization')?['value'])?['organizationid']`

### Step 2: Enable Auditing

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

**Action:** HTTP with Microsoft Entra ID (preauthorized)

| Parameter | Value |
|-----------|-------|
| Method | `PATCH` |
| URI | `https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/environments/@{triggerBody()?['environmentId']}/governanceConfiguration?api-version=2021-04-01` |
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

Log action `11` (BaselineConfigApplied) to ProvisioningLog.

### Return Value

Return success/failure status to parent flow.

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
