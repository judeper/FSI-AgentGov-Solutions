# Flow Configuration

Manual build instructions for Power Automate flows in the Agent Registry Automation solution.

---

## Overview

The Agent Registry Automation uses 4 Power Automate flows to manage the agent lifecycle:

| Flow | Purpose | Trigger | Frequency |
|------|---------|---------|-----------|
| **Flow 1:** Discover-UnregisteredAgents-Daily | Scan environments for unregistered agents | Recurrence | Daily |
| **Flow 2:** Enforce-RegistrationApproval-Gate | Process registration requests with SLA | Dataverse trigger | On-demand |
| **Flow 3:** Sync-EntraAgentRegistry | Sync registered agents to Entra | Dataverse trigger | On-demand |
| **Flow 4:** Detect-OrphanedAgents-Weekly | Find agents with departed owners | Recurrence | Weekly |

```
┌─────────────────────────────┐
│  Flow 1: Daily Discovery    │──── Bots API ────┐
│  (Recurrence — daily)       │                   │
└──────────────┬──────────────┘                   │
               │ Upsert                           │
               ▼                                  ▼
┌─────────────────────────────┐      ┌────────────────────┐
│  fsi_agentinventory         │      │  Power Platform    │
│  (Dataverse)                │      │  Environments      │
└──────────────┬──────────────┘      └────────────────────┘
               │
     ┌─────────┼──────────┬──────────────┐
     │         │          │              │
     ▼         ▼          ▼              ▼
┌──────────┐ ┌──────────┐ ┌──────────┐ ┌──────────────┐
│ Flow 2:  │ │ Flow 3:  │ │ Flow 4:  │ │ Compliance   │
│ Approval │ │ Entra    │ │ Orphan   │ │ Event Log    │
│ Gate     │ │ Sync     │ │ Detection│ │              │
└──────────┘ └──────────┘ └──────────┘ └──────────────┘
     │                         │
     ▼                         ▼
┌──────────────────────────────────────┐
│  Microsoft Teams                     │
│  (Notifications + Approvals)         │
└──────────────────────────────────────┘
```

---

## Connection References

Configure these connection references before building the flows.

| Connection Reference | Connector | Purpose |
|---------------------|-----------|---------|
| `fsi_cr_ara_dataverse` | Dataverse | Read/write agent inventory and compliance events |
| `fsi_cr_ara_http_azuread` | HTTP with Microsoft Entra ID | Bots API, Graph API, and Entra Agent Registry calls |
| `fsi_cr_ara_teams` | Microsoft Teams | Post adaptive cards and notifications |
| `fsi_cr_ara_approvals` | Approvals | Process registration approvals |

### Setting Up Connection References

1. Navigate to **Power Apps** > **Solutions** > **Agent Registry Automation**
2. Select **Connection References**
3. For each reference, click **Edit** and select or create an active connection
4. For `fsi_cr_ara_http_azuread`:
   - **Base Resource URL:** `https://api.powerplatform.com`
   - **Microsoft Entra ID Resource URI:** `https://api.powerplatform.com`

---

## Environment Variables

Configure these values before enabling the flows.

| Variable | Type | Description | Example |
|----------|------|-------------|---------|
| `fsi_ARA_TenantId` | String | Microsoft Entra ID tenant ID | `12345678-1234-1234-1234-123456789012` |
| `fsi_ARA_DataverseEnvironment` | String | Dataverse environment URL | `https://contoso.crm.dynamics.com` |
| `fsi_ARA_GovernanceTeamEmail` | String | Governance team email for approvals and notifications | `ai-governance@contoso.com` |
| `fsi_ARA_TeamsChannelId` | String | Teams channel ID for notifications | `19:xxxxx@thread.tacv2` |
| `fsi_ARA_ApprovalDeadlineDays` | String | Number of business days for approval SLA | `5` |
| `fsi_ARA_EntraRegistrySyncEnabled` | String | Feature flag for Entra Agent Registry sync | `false` |
| `fsi_ARA_DefaultTimeZone` | String | Fallback time zone for SLA calculations | `Eastern Standard Time` |

### Finding Teams Channel ID

1. Open Microsoft Teams
2. Right-click the target channel > **Get link to channel**
3. Extract the `channelId` parameter from the URL (URL-decode if necessary)

---

## Flow 1: Discover-UnregisteredAgents-Daily

### Purpose

Scans all Power Platform environments daily using the Bots API to discover AI agents. Creates or updates agent inventory records using an alternate-key upsert. Agents discovered in Zone 3 environments without prior registration are automatically quarantined.

### Trigger

**Recurrence**
- **Frequency:** Day
- **Interval:** 1
- **Start time:** Configure for off-peak hours (e.g., `06:00 UTC`)
- **Time zone:** UTC

### Step-by-Step Build Instructions

#### Step 1: Create the Flow

1. Navigate to **Power Automate** > **My Flows** > **New flow** > **Scheduled cloud flow**
2. Name: `ARA-Discover-UnregisteredAgents-Daily`
3. Configure the recurrence trigger as described above

#### Step 2: Initialize Variables

Add these **Initialize variable** actions:

| Variable Name | Type | Initial Value |
|--------------|------|---------------|
| `varTenantId` | String | `@{parameters('fsi_ARA_TenantId')}` |
| `varDiscoveryCorrelationId` | String | `@{guid()}` |
| `varDiscoveredCount` | Integer | `0` |
| `varNewCount` | Integer | `0` |
| `varQuarantinedCount` | Integer | `0` |
| `varEnvironments` | Array | `[]` |
| `varCurrentTimestamp` | String | `@{utcNow()}` |

#### Step 3: Get Environment List

Add **HTTP with Microsoft Entra ID** action:

- **Method:** GET
- **URI:** `https://api.powerplatform.com/appmanagement/environments?api-version=2022-03-01-preview&$filter=properties/environmentSku ne 'Developer'`
- **Authentication:** Use `fsi_cr_ara_http_azuread` connection reference
- **Headers:**
  - `Content-Type`: `application/json`

> **Note:** This filters out Developer-type environments. To include sandbox environments, remove the `$filter` parameter or set the `fsi_ARA_IncludeSandboxEnvironments` environment variable.

#### Step 4: Parse Environment Response

Add **Parse JSON** action:

- **Content:** Body from Step 3
- **Schema:** Use the schema from a sample Bots API environments response. Key fields: `value[].id`, `value[].name`, `value[].properties.displayName`, `value[].properties.environmentSku`

#### Step 5: Loop Through Environments

Add **Apply to each** action on the `value` array from Step 4.

> **⚠ Concurrency:** Set concurrency control to **1** (sequential). The Bots API may rate-limit parallel requests.

Inside the loop:

##### Step 5a: Get Bots for Environment

Add **HTTP with Microsoft Entra ID** action:

- **Method:** GET
- **URI:** `https://api.powerplatform.com/appmanagement/environments/@{items('Apply_to_each')?['name']}/bots?api-version=2022-03-01-preview`
- **Configure Run After:** Set to run on **success** and **failure** (some environments may not have Bots API access)

##### Step 5b: Check for Successful Response

Add **Condition** — check if `outputs('Get_Bots')?['statusCode']` equals `200`.

##### Step 5c: Parse Bots Response (Yes Branch)

Add **Parse JSON** on the body from Step 5a. Key fields: `value[].name`, `value[].properties.displayName`, `value[].properties.botFrameworkEndpoint`

> **Note:** The exact field path for `botFrameworkEndpoint` needs live API confirmation. The flow includes error handling if this field is missing.

##### Step 5d: Loop Through Bots

Add **Apply to each** on the `value` array from Step 5c.

Inside the inner loop:

##### Step 5d-i: Determine Zone Classification

Add **Compose** action to classify the environment's zone. Use a lookup against environment metadata or a static mapping:

```json
if(
  contains(items('Apply_to_each')?['properties']?['environmentSku'], 'Production'),
  10003,
  if(
    contains(items('Apply_to_each')?['properties']?['environmentSku'], 'Teams'),
    10002,
    10001
  )
)
```

> **Note:** Zone classification logic should be customized based on your organization's environment naming conventions and metadata. The above is a simplified example.

##### Step 5d-ii: Upsert Agent Record

Add **Dataverse — Update a row** action with alternate key:

- **Table name:** Agent Inventories (`fsi_agentinventories`)
- **Row ID:** `fsi_agentid='@{items('Apply_to_each_Bot')?['name']}',fsi_environmentid='@{items('Apply_to_each')?['name']}'`
- **Columns to set:**
  - `fsi_name`: `@{items('Apply_to_each_Bot')?['properties']?['displayName']}`
  - `fsi_environmentname`: `@{items('Apply_to_each')?['properties']?['displayName']}`
  - `fsi_botframeworkendpoint`: `@{items('Apply_to_each_Bot')?['properties']?['botFrameworkEndpoint']}`
  - `fsi_zone`: Zone value from Step 5d-i
  - `fsi_lastscanned`: `@{utcNow()}`
- **Configure Run After:** Set to run on **success** and **failure** (for new records, the upsert creates; for existing records, it updates)

> **Important:** The alternate key `fsi_ak_agentinventory_agentenv` must be in **Active** status before this step will work. If the key is still **Pending**, the upsert will fail with a 404 error.

##### Step 5d-iii: Check If New Record

Add **Condition** — check if this was a new record creation (HTTP response status 201) vs. update (200/204).

For new records only:

##### Step 5d-iv: Set Default Registration Status

Add **Dataverse — Update a row** to set:
- `fsi_registrationstatus`: `10001` (Discovered)
- `fsi_discoveredon`: `@{utcNow()}`

##### Step 5d-v: Check Zone 3 Auto-Quarantine

Add **Condition** — if zone equals `10003` AND `fsi_registrationstatus` equals `10001` (Discovered):

**Yes branch:**
- Add **Dataverse — Update a row** to set:
  - `fsi_isquarantined`: `true`
  - `fsi_quarantinedon`: `@{utcNow()}`
  - `fsi_quarantinereason`: `Auto-quarantined: Zone 3 agent discovered without prior registration`
  - `fsi_registrationstatus`: `10004` (Quarantined)

##### Step 5d-vi: Log Compliance Event

Add **Dataverse — Add a new row** to `fsi_agentcomplianceevents`:
- `fsi_name`: `Agent Discovered — @{items('Apply_to_each_Bot')?['properties']?['displayName']}`
- `fsi_eventtype`: `10001` (Agent Discovered)
- `fsi_eventsource`: `10001` (Flow 1 — Discovery)
- `fsi_severity`: `10001` (Informational) — or `10004` (High) if quarantined
- `fsi_actorupn`: `system@contoso.com`
- `fsi_environmentid`: `@{items('Apply_to_each')?['name']}`
- `fsi_zone`: Zone value from Step 5d-i
- `fsi_correlationid`: `@{variables('varDiscoveryCorrelationId')}`
- `fsi_occurredon`: `@{utcNow()}`

##### Step 5d-vii: Increment Counters

Add **Increment variable** for `varDiscoveredCount`. If new record, also increment `varNewCount`. If quarantined, also increment `varQuarantinedCount`.

#### Step 6: Send Summary Notification

After the outer loop, add **Microsoft Teams — Post adaptive card in a chat or channel**:

- **Post in:** Channel
- **Team:** Select the governance team
- **Channel:** Use `fsi_ARA_TeamsChannelId` environment variable
- **Adaptive Card:** Include summary with discovered, new, and quarantined counts

#### Step 7: Error Handling

Add a **Scope** around Steps 3–6 with **Configure Run After** set to run on failure. Inside the error scope:
- Log a compliance event with `fsi_eventtype` = system error
- Send an error notification to the governance team

---

## Flow 2: Enforce-RegistrationApproval-Gate

### Purpose

Processes registration requests for discovered agents. Routes approval through Microsoft Teams with SLA tracking, escalation on deadline breach, and compliance event logging.

### Trigger

**Dataverse — When a row is added**
- **Table name:** Registration Requests (`fsi_registrationrequests`)
- **Scope:** Organization

### Step-by-Step Build Instructions

#### Step 1: Create the Flow

1. Navigate to **Power Automate** > **My Flows** > **New flow** > **Automated cloud flow**
2. Name: `ARA-Enforce-RegistrationApproval-Gate`
3. Select trigger: **When a row is added** (Dataverse)

#### Step 2: Initialize Variables

| Variable Name | Type | Initial Value |
|--------------|------|---------------|
| `varApprovalDeadlineDays` | Integer | `@{int(parameters('fsi_ARA_ApprovalDeadlineDays'))}` |
| `varGovernanceTeamEmail` | String | `@{parameters('fsi_ARA_GovernanceTeamEmail')}` |
| `varCorrelationId` | String | `@{guid()}` |

#### Step 3: Get Agent Details

Add **Dataverse — Get a row by ID** to retrieve the related `fsi_agentinventory` record using the `fsi_agentinventoryid` lookup from the trigger.

#### Step 4: Calculate SLA Deadline

Add **Compose** action to calculate the approval deadline:

```json
addDays(utcNow(), variables('varApprovalDeadlineDays'))
```

> **Note:** This uses calendar days. For business-day calculation, use the Office 365 Users connector to determine the approver's time zone and exclude weekends. If DLP policies block the Office 365 Users connector, the flow falls back to the `fsi_ARA_DefaultTimeZone` environment variable.

#### Step 5: Update Request Status

Add **Dataverse — Update a row** on the registration request:
- `fsi_requeststatus`: `10002` (Under Review)
- `fsi_approver`: `@{variables('varGovernanceTeamEmail')}`
- `fsi_approvaldeadline`: Result from Step 4

#### Step 6: Log Compliance Event

Add **Dataverse — Add a new row** to `fsi_agentcomplianceevents`:
- `fsi_eventtype`: `10002` (Registration Requested)
- `fsi_eventsource`: `10002` (Flow 2 — Registration)
- `fsi_severity`: `10001` (Informational)
- `fsi_correlationid`: `@{variables('varCorrelationId')}`

#### Step 7: Start Approval

Add **Approvals — Start and wait for an approval**:
- **Approval type:** Approve/Reject — First to respond
- **Title:** `Agent Registration — @{outputs('Get_Agent')?['body/fsi_name']}`
- **Assigned to:** `@{variables('varGovernanceTeamEmail')}`
- **Details:** Include agent name, environment, zone, justification, and SLA deadline
- **Item link:** Link to the agent inventory record in Dataverse
- **Timeout:** `P@{variables('varApprovalDeadlineDays')}D` (ISO 8601 duration)

#### Step 8: Process Approval Outcome

Add **Switch** on `outputs('Start_Approval')?['body/outcome']`:

##### Case: "Approve"

1. Update registration request: `fsi_requeststatus` = `10003` (Approved), `fsi_approvaloutcome` = `10001`
2. Update agent inventory: `fsi_registrationstatus` = `10003` (Registered), `fsi_registeredon` = `utcNow()`
3. If agent was quarantined: clear `fsi_isquarantined`, clear `fsi_quarantinedon`
4. Log compliance event: `fsi_eventtype` = `10003` (Registration Approved)
5. Send Teams notification to requestor

##### Case: "Reject"

1. Update registration request: `fsi_requeststatus` = `10004` (Rejected), `fsi_approvaloutcome` = `10002`
2. Log compliance event: `fsi_eventtype` = `10004` (Registration Rejected)
3. Send Teams notification to requestor with rejection comments

##### Default (Timeout)

1. Update registration request: `fsi_requeststatus` = `10006` (Timed Out), `fsi_approvaloutcome` = `10003`
2. Log compliance event: `fsi_eventtype` = `10013` (Approval Timed Out)
3. Check if escalation is configured:
   - If yes: create a new approval assigned to the escalation approver, update `fsi_isescalated` = `true`, `fsi_escalatedon` = `utcNow()`, log `fsi_eventtype` = `10012` (SLA Escalation)
   - If no: send notification to governance team about unresolved request

---

## Flow 3: Sync-EntraAgentRegistry

### Purpose

Syncs registered agent metadata to the Entra Agent Registry. This flow is **feature-flagged** and disabled by default. Enable only after confirming Entra Agent Registry API availability.

### Trigger

**Dataverse — When a row is modified**
- **Table name:** Agent Inventories (`fsi_agentinventories`)
- **Scope:** Organization
- **Filter columns:** `fsi_registrationstatus`

### Step-by-Step Build Instructions

#### Step 1: Create the Flow

1. Navigate to **Power Automate** > **My Flows** > **New flow** > **Automated cloud flow**
2. Name: `ARA-Sync-EntraAgentRegistry`
3. Select trigger: **When a row is modified** (Dataverse)
4. Configure filter columns: `fsi_registrationstatus`

#### Step 2: Feature Flag Gate

Add **Condition** — check if `@{parameters('fsi_ARA_EntraRegistrySyncEnabled')}` equals `true`.

**No branch:** Add **Terminate** with status `Succeeded` and message `Entra sync disabled by feature flag`.

#### Step 3: Check Registration Status

Add **Condition** — check if `fsi_registrationstatus` equals `10003` (Registered).

**No branch:** Terminate — only sync registered agents.

#### Step 4: Build Entra Registration Payload

Add **Compose** action:

```json
{
  "displayName": "@{triggerOutputs()?['body/fsi_name']}",
  "agentId": "@{triggerOutputs()?['body/fsi_agentid']}",
  "environmentId": "@{triggerOutputs()?['body/fsi_environmentid']}",
  "ownerUpn": "@{triggerOutputs()?['body/fsi_ownerupn']}",
  "riskClassification": "@{triggerOutputs()?['body/fsi_zone']}",
  "registeredOn": "@{triggerOutputs()?['body/fsi_registeredon']}",
  "frameworkVersion": "FSI-AgentGov-v1.1"
}
```

#### Step 5: Call Entra Agent Registry API

Add **HTTP with Microsoft Entra ID** action:

- **Method:** POST (or PUT for upsert)
- **URI:** `https://graph.microsoft.com/beta/agentRegistrations` *(confirm actual endpoint)*
- **Body:** Output from Step 4
- **Headers:**
  - `Content-Type`: `application/json`

> **Note:** The Entra Agent Registry API endpoint is subject to change. Confirm the actual endpoint and required permissions before enabling this flow.

#### Step 6: Handle Response

Add **Condition** on response status code:

**Success (2xx):**
1. Update agent inventory: `fsi_entrasynced` = `true`, `fsi_entrasyncedon` = `utcNow()`
2. Log compliance event: `fsi_eventtype` = `10010` (Entra Sync Completed)

**Failure:**
1. Log compliance event: `fsi_eventtype` = `10011` (Entra Sync Failed), include error details
2. Send notification to governance team

---

## Flow 4: Detect-OrphanedAgents-Weekly

### Purpose

Checks all registered agents weekly to verify that their owners are still active in Microsoft Entra ID. Agents whose owners have departed, been disabled, or been inactive are flagged as orphaned.

### Trigger

**Recurrence**
- **Frequency:** Week
- **Interval:** 1
- **Start time:** Configure for off-peak hours (e.g., `Saturday 02:00 UTC`)
- **Time zone:** UTC

### Step-by-Step Build Instructions

#### Step 1: Create the Flow

1. Navigate to **Power Automate** > **My Flows** > **New flow** > **Scheduled cloud flow**
2. Name: `ARA-Detect-OrphanedAgents-Weekly`
3. Configure the recurrence trigger as described above

#### Step 2: Initialize Variables

| Variable Name | Type | Initial Value |
|--------------|------|---------------|
| `varCorrelationId` | String | `@{guid()}` |
| `varOrphanCount` | Integer | `0` |
| `varCheckedCount` | Integer | `0` |

#### Step 3: Get Active Agents

Add **Dataverse — List rows** from `fsi_agentinventories`:

- **Filter rows:** `fsi_registrationstatus eq 10003 and fsi_isorphaned eq false`
- **Select columns:** `fsi_agentinventoryid,fsi_name,fsi_ownerupn,fsi_agentid,fsi_environmentid,fsi_zone`

#### Step 4: Loop Through Agents

Add **Apply to each** on the results from Step 3.

> **Concurrency:** Set to **5** (parallel) for faster processing. Graph API calls are independent per agent.

Inside the loop:

##### Step 4a: Check Owner Status via Graph API

Add **HTTP with Microsoft Entra ID** action:

- **Method:** GET
- **URI:** `https://graph.microsoft.com/v1.0/users/@{items('Apply_to_each')?['fsi_ownerupn']}?$select=accountEnabled,signInActivity,department`
- **Configure Run After:** Set to run on **success** and **failure** (user may not exist)

##### Step 4b: Parse Response

Add **Condition** — check response status:

**404 (User Not Found):**
- User has been deleted → classify as orphaned with reason "Owner Departed"

**200 (User Found):**
- Check `accountEnabled` — if `false`, classify as orphaned with reason "Owner Disabled"
- Check `signInActivity.lastSignInDateTime` — if more than 90 days ago, classify as orphaned with reason "Owner Inactive"

##### Step 4c: Flag as Orphaned (if applicable)

If orphan criteria met:

1. **Dataverse — Update a row** on `fsi_agentinventories`:
   - `fsi_isorphaned`: `true`
   - `fsi_orphanedon`: `@{utcNow()}`

2. **Dataverse — Add a new row** to `fsi_ownershipaudits`:
   - `fsi_changetype`: Appropriate value (10001, 10002, or 10003)
   - `fsi_previousownerupn`: `@{items('Apply_to_each')?['fsi_ownerupn']}`
   - `fsi_previousownerstatus`: `Deleted`, `Disabled`, or `Inactive`
   - `fsi_changedon`: `@{utcNow()}`
   - `fsi_changedby`: `system@contoso.com`

3. **Dataverse — Add a new row** to `fsi_agentcomplianceevents`:
   - `fsi_eventtype`: `10008` (Orphan Detected)
   - `fsi_eventsource`: `10004` (Flow 4 — Orphan Detection)
   - `fsi_severity`: `10003` (Medium)
   - `fsi_correlationid`: `@{variables('varCorrelationId')}`

4. **Increment variable** `varOrphanCount`

##### Step 4d: Increment Checked Counter

Add **Increment variable** for `varCheckedCount`.

#### Step 5: Send Summary Notification

After the loop, add **Microsoft Teams — Post adaptive card**:

- Include: agents checked, orphans found, orphan details
- Post to the governance team channel

#### Step 6: Error Handling

Add a **Scope** around Steps 3–5 with **Configure Run After** on failure:
- Log system error compliance event
- Notify governance team

---

## Known Limitations

- **Bots API preview:** The `2022-03-01-preview` API version may change at GA. Monitor the [Power Platform API documentation](https://learn.microsoft.com/en-us/rest/api/power-platform/) for updates.
- **BotFrameworkEndpoint field:** The exact field path in the Bots API response needs live API confirmation. The flow includes null-check error handling for this field.
- **Office 365 Users connector:** Used for time zone lookup in SLA calculations. If blocked by DLP policies, configure `fsi_ARA_DefaultTimeZone` as a fallback.
- **Entra Agent Registry API:** Flow 3 is disabled by default. The API endpoint and required permissions are subject to change.
- **Graph signInActivity:** Requires Microsoft Entra ID P1/P2 license for the `signInActivity` property in the Graph API response. Without this license, the inactive-owner detection in Flow 4 is limited to account-enabled checks only.
- **Alternate key pending status:** The upsert in Flow 1 requires the alternate key to be in **Active** status. New deployments may need to wait up to 30 minutes after schema creation.

---

*Agent Registry Automation v1.0.0 — FSI Agent Governance Framework*
