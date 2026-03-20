# Power Automate Flow Configuration

Detailed specifications for building the six lifecycle governance flows in Power Automate designer.

## Flow Architecture

```
                    ┌─────────────────────────────┐
                    │  Agent 365 Registry          │
                    │  (Entra agent objects)        │
                    └─────────────┬────────────────┘
                                  │
          ┌───────────────────────┼───────────────────────┐
          │                       │                       │
          v                       v                       v
┌─────────────────┐   ┌─────────────────┐   ┌─────────────────┐
│ Flow 1 (Hourly) │   │ Flow 2 (Daily)  │   │ Flow 3 (Daily)  │
│ Enforce-Sponsor │   │ Schedule-Access │   │ Detect-Inactive │
│ Assignment-     │   │ Review-Zone     │   │ Agents-Daily    │
│ OnOnboard       │   │ Based           │   │                 │
└────────┬────────┘   └────────┬────────┘   └────────┬────────┘
         │                     │                      │
         │                     │  (Deny decision)     │  (Inactive)
         │                     └──────┐  ┌────────────┘
         │                            v  v
         │              ┌─────────────────────────────┐
         │              │ Flow 4 (Called)              │
         │              │ Execute-Deactivation         │
         │              │ Workflow                     │
         │              └─────────────┬───────────────┘
         │                            │
         │                            │  (Approved + hold expired)
         │                            v
         │              ┌─────────────────────────────┐
         │              │ Flow 6 (Daily)              │
         │              │ Check-DeletionHold-Daily    │
         │              └─────────────────────────────┘
         │
         │
         v
┌─────────────────┐
│ Flow 5 (Weekly) │──────────────────┐
│ Monitor-Sponsor │                  │  (Sponsor departed)
│ Changes-Weekly  │                  v
└─────────────────┘     ┌─────────────────────┐
                        │ Flow 4 (Called)      │
                        │ Execute-Deactivation │
                        │ Workflow             │
                        └──────────────────────┘
```

**Flow interaction summary:**

| Calling Flow | Triggers Flow 4 When |
|-------------|----------------------|
| Flow 2 | Access review returns a "Deny" decision |
| Flow 3 | Agent exceeds zone inactivity threshold |
| Flow 5 | Sponsor departed and all fallback reassignments fail |

---

## Connections Required

| Connector | Purpose | License |
|-----------|---------|---------|
| **Dataverse** | Read/write lifecycle tables | Included |
| **HTTP with Microsoft Entra ID** | Graph API calls (Agent 365 Registry, Lifecycle Workflows, Access Reviews) | Premium |
| **Microsoft Teams** | Sponsor notification cards | Included |
| **Approvals** | Deactivation and deletion approvals | Included |
| **Power Platform for Admins V2** | Agent activity data from PPAC | Premium |

---

## Feature Flag

> **CRITICAL:** Every flow must check the `IsAgent365LifecycleEnabled` environment variable as its **first action**. If the value is `"false"`, the flow must log a skip event to `fsi_lifecyclecomplianceevent` and terminate with `Cancelled` status and message `"Agent 365 Lifecycle not enabled"`. This gate prevents API calls to Agent 365 endpoints before GA availability.

---

## Flow 1: Enforce-SponsorAssignment-OnOnboard

### Trigger Configuration

| Setting | Value |
|---------|-------|
| Type | Recurrence |
| Frequency | Hour |
| Interval | 1 |

### Variables

Initialize at flow start:

| Variable | Type | Value |
|----------|------|-------|
| `DefaultSponsorUPN` | String | Environment variable `DefaultSponsorUPN` |
| `FSIAllAgentIdentitiesGroupId` | String | Environment variable `FSIAllAgentIdentitiesGroupId` |
| `FSIZone3AgentsGroupId` | String | Environment variable `FSIZone3AgentsGroupId` |
| `DataverseEnvironmentUrl` | String | Environment variable `DataverseEnvironmentUrl` |

### Step 1: Check Feature Flag

**Action:** Environment Variable — Get value

| Parameter | Value |
|-----------|-------|
| Variable | `IsAgent365LifecycleEnabled` |

**Condition:** Value equals `"false"`

**If true:**

1. Log skip event to `fsi_lifecyclecomplianceevent` with `fsi_eventtype` = `"Feature Flag Skip"`
2. **Terminate** with status `Cancelled` and message `"Agent 365 Lifecycle not enabled"`

### Step 2: Get All Agents from Entra

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| Base Resource URL | `https://graph.microsoft.com` |
| Azure AD Resource URI | `https://graph.microsoft.com` |
| URI | `/beta/agentRegistry/agents` |

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

### Step 3: For Each Agent

**Action:** Apply to each on `body('Get_All_Agents')?['value']`

**Concurrency:** Set degree of parallelism to `5` to avoid Graph API throttling.

#### Step 3a: Check If Agent Has Sponsor

**Condition:** `empty(items('For_Each_Agent')?['sponsor'])` equals `true`

#### Step 3b: If No Sponsor — Resolve Default Sponsor

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| URI | `/v1.0/users/@{variables('DefaultSponsorUPN')}?$select=id,accountEnabled,displayName,mail` |

**Post-action condition:** Verify `accountEnabled` equals `true`. If the default sponsor account is disabled, terminate with error and alert `FlowAdministrators`.

#### Step 3c: Assign Sponsor via PATCH

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `PATCH` |
| URI | `/beta/agentRegistry/agents/@{items('For_Each_Agent')?['id']}` |
| Body | See below |

```json
{
  "sponsor@odata.bind": "https://graph.microsoft.com/v1.0/users/@{body('Resolve_Default_Sponsor')?['id']}"
}
```

> **CRITICAL:** The sponsor binding must use `@odata.bind` with the sponsor's Object ID (GUID), not the UPN string. Using a UPN returns `400 Bad Request`.

**Headers:**

```json
{
  "Content-Type": "application/json"
}
```

#### Step 3d: Resolve Governance Zone

**Action:** Dataverse — List rows

| Parameter | Value |
|-----------|-------|
| Table | `fsi_environment_policy` |
| Filter rows | `fsi_environmentid eq '@{items('For_Each_Agent')?['environmentId']}'` |
| Top count | `1` |

**Post-action:** Set zone variables based on result:

```
// If no policy record found, default to Zone 2
zone = if(empty(body('Get_Zone_Policy')?['value']), 2, first(body('Get_Zone_Policy')?['value'])?['fsi_governancezone'])

// Inactivity threshold (days)
inactivityThreshold = if(equals(zone, 1), 180, if(equals(zone, 2), 90, 30))

// Review cadence
reviewCadence = if(equals(zone, 1), 'Annual', if(equals(zone, 2), 'Semi-Annual', 'Quarterly'))

// Next review due (days from now)
nextReviewDays = if(equals(zone, 1), 365, if(equals(zone, 2), 180, 90))
```

#### Step 3e: Upsert Agent Lifecycle Record

**Action:** Dataverse — Perform an unbound action (or HTTP to Dataverse API)

| Parameter | Value |
|-----------|-------|
| Method | `PATCH` |
| URI | `/api/data/v9.2/fsi_agentlifecyclerecords(fsi_agentid='@{items('For_Each_Agent')?['id']}',fsi_environmentid='@{items('For_Each_Agent')?['environmentId']}')` |
| Header | `If-Match: *` (upsert) |

**Body:**

```json
{
  "fsi_agentname": "@{items('For_Each_Agent')?['displayName']}",
  "fsi_governancezone": @{variables('zone')},
  "fsi_lifecyclestage": "@{if(empty(items('For_Each_Agent')?['sponsor']), 'Onboarding', 'Active')}",
  "fsi_sponsorupn": "@{body('Resolve_Default_Sponsor')?['mail']}",
  "fsi_sponsorobjectid": "@{body('Resolve_Default_Sponsor')?['id']}",
  "fsi_sponsoractive": true,
  "fsi_sponsorassigneddate": "@{utcNow()}",
  "fsi_inactivitythreshold": @{variables('inactivityThreshold')},
  "fsi_accessreviewstatus": "Not Started",
  "fsi_nextreviewdue": "@{addDays(utcNow(), variables('nextReviewDays'))}",
  "fsi_reviewcadence": "@{variables('reviewCadence')}",
  "fsi_capolicyassigned": false,
  "fsi_deactivationrequested": false,
  "fsi_firstregistered": "@{utcNow()}",
  "fsi_lastupdated": "@{utcNow()}"
}
```

> **Note:** Uses Dataverse alternate key on `fsi_agentid` + `fsi_environmentid` for upsert behavior. Existing records are updated; new records are created.

#### Step 3f: Create Sponsor Assignment Record

**Action:** Dataverse — Add a new row

| Parameter | Value |
|-----------|-------|
| Table | `fsi_sponsorassignment` |
| `fsi_agentid` | Agent ID from loop |
| `fsi_sponsorupn` | Resolved sponsor UPN |
| `fsi_sponsorobjectid` | Resolved sponsor Object ID |
| `fsi_assigneddate` | `utcNow()` |
| `fsi_assignmentmethod` | `"Auto"` or `"Default"` |
| `fsi_isactive` | `true` |

#### Step 3g: Add Agent to Security Groups

**Action (always):** HTTP with Microsoft Entra ID — Add to FSI-AllAgentIdentities

| Parameter | Value |
|-----------|-------|
| Method | `POST` |
| URI | `/v1.0/groups/@{variables('FSIAllAgentIdentitiesGroupId')}/members/$ref` |
| Body | `{"@odata.id": "https://graph.microsoft.com/v1.0/servicePrincipals/@{items('For_Each_Agent')?['servicePrincipalId']}"}` |

**Error handling:** If `400` (already a member), continue without error.

**Condition:** If `zone` equals `3`:

**Action:** HTTP with Microsoft Entra ID — Add to FSI-Zone3-Agents

| Parameter | Value |
|-----------|-------|
| Method | `POST` |
| URI | `/v1.0/groups/@{variables('FSIZone3AgentsGroupId')}/members/$ref` |
| Body | `{"@odata.id": "https://graph.microsoft.com/v1.0/servicePrincipals/@{items('For_Each_Agent')?['servicePrincipalId']}"}` |

#### Step 3h: Log Compliance Event

**Action:** Dataverse — Add a new row

| Parameter | Value |
|-----------|-------|
| Table | `fsi_lifecyclecomplianceevent` |
| `fsi_eventtype` | `"Sponsor Assigned"` |
| `fsi_agentid` | Agent ID |
| `fsi_agentname` | Agent display name |
| `fsi_sponsorupn` | Assigned sponsor UPN |
| `fsi_eventdetails` | JSON with assignment method and zone |
| `fsi_complianceimpact` | `"None"` |
| `fsi_eventdate` | `utcNow()` |
| `fsi_correlationid` | `workflow()?['run']?['name']` |

#### Step 3i: Send Teams Notification to Sponsor

**Action:** Microsoft Teams — Post adaptive card in a chat or channel

Send an Adaptive Card (v1.2) to the sponsor with:

- Agent display name and ID
- Governance zone assignment
- Sponsor responsibilities summary
- Link to agent lifecycle record in Dataverse
- "Acknowledge" action button

```json
{
  "type": "AdaptiveCard",
  "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
  "version": "1.2",
  "body": [
    {
      "type": "TextBlock",
      "text": "You have been assigned as sponsor for an AI agent",
      "weight": "Bolder",
      "size": "Medium"
    },
    {
      "type": "FactSet",
      "facts": [
        { "title": "Agent", "value": "@{items('For_Each_Agent')?['displayName']}" },
        { "title": "Zone", "value": "Zone @{variables('zone')}" },
        { "title": "Review Cadence", "value": "@{variables('reviewCadence')}" },
        { "title": "Assigned", "value": "@{utcNow()}" }
      ]
    },
    {
      "type": "TextBlock",
      "text": "As sponsor, you are responsible for periodic access reviews and lifecycle decisions for this agent.",
      "wrap": true
    }
  ],
  "actions": [
    {
      "type": "Action.OpenUrl",
      "title": "View Agent Record",
      "url": "@{variables('DataverseEnvironmentUrl')}/main.aspx?appid=...&pagetype=entityrecord&etn=fsi_agentlifecyclerecord&id=..."
    }
  ]
}
```

---

## Flow 2: Schedule-AccessReview-ZoneBased

### Trigger Configuration

| Setting | Value |
|---------|-------|
| Type | Recurrence |
| Frequency | Day |
| Interval | 1 |
| Start time | `07:00 AM UTC` |

### Step 1: Check Feature Flag

Same pattern as Flow 1, Step 1. Terminate if disabled.

### Part A — Create New Reviews (Scope)

#### Step A1: Query Agents Due for Review

**Action:** Dataverse — List rows

| Parameter | Value |
|-----------|-------|
| Table | `fsi_agentlifecyclerecord` |
| Filter rows | `fsi_nextreviewdue le @{utcNow()} and fsi_lifecyclestage eq 'Active'` |

#### Step A2: For Each Agent Due

**Action:** Apply to each on query results

##### Step A2a: Determine Certifier

```
certifierUPN = if(
  not(empty(items('For_Each_Due')?['fsi_sponsorupn'])),
  items('For_Each_Due')?['fsi_sponsorupn'],
  variables('DefaultSponsorUPN')
)
```

##### Step A2b: Resolve Certifier Object ID

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| URI | `/v1.0/users/@{variables('certifierUPN')}?$select=id` |

##### Step A2c: Create Entra Access Review

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `POST` |
| URI | `/v1.0/identityGovernance/accessReviews/definitions` |

**Body:**

```json
{
  "displayName": "Agent Access Review - @{items('For_Each_Due')?['fsi_agentname']} - @{formatDateTime(utcNow(), 'yyyy-MM-dd')}",
  "descriptionForAdmins": "Periodic access review for AI agent per governance zone policy",
  "descriptionForReviewers": "Review whether this AI agent should retain its current access permissions",
  "scope": {
    "query": "/servicePrincipals/@{items('For_Each_Due')?['fsi_agentid']}",
    "queryType": "MicrosoftGraph"
  },
  "reviewers": [
    {
      "query": "/users/@{body('Resolve_Certifier')?['id']}",
      "queryType": "MicrosoftGraph"
    }
  ],
  "settings": {
    "mailNotificationsEnabled": true,
    "reminderNotificationsEnabled": true,
    "justificationRequiredOnApproval": true,
    "defaultDecisionEnabled": true,
    "defaultDecision": "Deny",
    "instanceDurationInDays": 14,
    "autoApplyDecisionsEnabled": false,
    "recommendationsEnabled": true,
    "recurrence": null
  }
}
```

> **CRITICAL — Default Decision:** The `defaultDecision` must be `"Deny"`. In FSI regulatory contexts, silence equals revocation. If a reviewer does not respond within the review window, the agent's access is recommended for removal. This supports compliance with FINRA Rule 3110 supervisory requirements.

##### Step A2d: Retrieve Review Instance ID

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| URI | `/v1.0/identityGovernance/accessReviews/definitions/@{body('Create_Access_Review')?['id']}/instances` |

Extract: `first(body('Get_Review_Instances')?['value'])?['id']`

##### Step A2e: Create Access Review Record

**Action:** Dataverse — Add a new row

| Parameter | Value |
|-----------|-------|
| Table | `fsi_accessreview` |
| `fsi_agentid` | Agent ID |
| `fsi_reviewtype` | Zone-based cadence |
| `fsi_reviewstatus` | `"In Progress"` |
| `fsi_reviewstartdate` | `utcNow()` |
| `fsi_reviewduedate` | `addDays(utcNow(), 14)` |
| `fsi_certifierupn` | Certifier UPN |
| `fsi_entrareviewid` | `body('Create_Access_Review')?['id']` |
| `fsi_entrareviewinstanceid` | Instance ID from Step A2d |

##### Step A2f: Update Lifecycle Record

**Action:** Dataverse — Update a row

| Parameter | Value |
|-----------|-------|
| Table | `fsi_agentlifecyclerecord` |
| `fsi_accessreviewstatus` | `"In Progress"` |
| `fsi_nextreviewdue` | Calculate from zone cadence (Annual/Semi-Annual/Quarterly) |
| `fsi_lastupdated` | `utcNow()` |

##### Step A2g: Log Compliance Event

Log `fsi_eventtype` = `"Access Review Created"` with `fsi_complianceimpact` = `"None"`.

### Part B — Check Overdue Reviews (Scope)

#### Step B1: Query Overdue Reviews

**Action:** Dataverse — List rows

| Parameter | Value |
|-----------|-------|
| Table | `fsi_accessreview` |
| Filter rows | `fsi_reviewstatus eq 'In Progress' and fsi_reviewduedate lt @{utcNow()}` |

#### Step B2: For Each Overdue Review

1. **Update review status:** Set `fsi_reviewstatus` to `"Overdue"`
2. **Send Teams escalation:** Post message to `EscalationApproverUPN` with agent name, original due date, and days overdue
3. **Log compliance event:** `fsi_eventtype` = `"Access Review Overdue"`, `fsi_complianceimpact` = `"High"`

### Part C — Poll Completed Reviews (Scope)

#### Step C1: Query In-Progress Reviews with Instance ID

**Action:** Dataverse — List rows

| Parameter | Value |
|-----------|-------|
| Table | `fsi_accessreview` |
| Filter rows | `fsi_reviewstatus eq 'In Progress' and fsi_entrareviewinstanceid ne null` |

#### Step C2: For Each Review — Check Decisions

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| URI | `/v1.0/identityGovernance/accessReviews/definitions/@{items('For_Each_Review')?['fsi_entrareviewid']}/instances/@{items('For_Each_Review')?['fsi_entrareviewinstanceid']}/decisions` |

**Post-action logic:**

1. If decisions array is non-empty and all decisions are present:
   - Mark `fsi_reviewstatus` = `"Completed"`
   - Set `fsi_reviewcompleteddate` = `utcNow()`
   - Store `fsi_reviewoutcome` = decision summary
2. If **any** decision is `"Deny"`:
   - Log compliance event: `fsi_eventtype` = `"Access Review Denied"`, `fsi_complianceimpact` = `"Critical"`
   - **Trigger Flow 4** (Execute-DeactivationWorkflow) with agent ID and reason `"Access Review Denied"`

---

## Flow 3: Detect-InactiveAgents-Daily

### Trigger Configuration

| Setting | Value |
|---------|-------|
| Type | Recurrence |
| Frequency | Day |
| Interval | 1 |
| Start time | `06:00 AM UTC` |

### Step 1: Check Feature Flag

Same pattern as Flow 1, Step 1. Terminate if disabled.

### Step 2: Get Active Agents

**Action:** Dataverse — List rows

| Parameter | Value |
|-----------|-------|
| Table | `fsi_agentlifecyclerecord` |
| Filter rows | `fsi_lifecyclestage eq 'Active'` |

### Step 3: For Each Active Agent

**Action:** Apply to each on query results

#### Step 3a: Query Entra Sign-in Logs (API 11)

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| URI | `/v1.0/auditLogs/signIns?$filter=appId eq '@{items('For_Each_Active')?['fsi_agentid']}'&$top=1&$orderby=createdDateTime desc` |

Extract: `first(body('Get_SignIn_Logs')?['value'])?['createdDateTime']`

> This is the most authoritative source for agent activity.

#### Step 3b: Query PPAC Bots API (API 10)

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| Base Resource URL | `https://api.bap.microsoft.com` |
| Azure AD Resource URI | `https://api.bap.microsoft.com` |
| URI | `/providers/Microsoft.BusinessAppPlatform/environments/@{items('For_Each_Active')?['fsi_environmentid']}/bots?api-version=2021-04-01` |

Extract `lastModifiedTime` and `publishedOn` for the matching agent.

#### Step 3c: Determine Last Activity Date

```
// Take the maximum non-null date across all sources
signInDate = outputs from Step 3a (may be null)
ppacModifiedDate = outputs from Step 3b lastModifiedTime (may be null)
ppacPublishedDate = outputs from Step 3b publishedOn (may be null)

// Compose: pick the latest non-null value
lastActivityDate = max(signInDate, ppacModifiedDate, ppacPublishedDate)
activitySource = <name of source that provided the latest date>
```

> **CRITICAL:** If ALL sources return null, set `activitySource` = `"Unknown"` and do NOT trigger deactivation. Absence of data does not confirm inactivity — the agent may be active through channels not captured by available APIs.

#### Step 3d: Calculate Inactivity

```
inactivityDays = dateDifference(lastActivityDate, utcNow())  // in days
zoneThreshold = items('For_Each_Active')?['fsi_inactivitythreshold']
```

#### Step 3e: Evaluate Inactivity

**Condition:** `inactivityDays` > `zoneThreshold` AND `activitySource` does not equal `"Unknown"`

**If true:**

1. Update `fsi_agentlifecyclerecord`:
   - `fsi_lifecyclestage` = `"Inactive"`
   - `fsi_lastactivitydate` = `lastActivityDate`
   - `fsi_lastupdated` = `utcNow()`

2. Log compliance event: `fsi_eventtype` = `"Inactivity Detected"`, `fsi_complianceimpact` = `"Medium"`

3. **Trigger Flow 4** (Execute-DeactivationWorkflow) with agent ID and reason `"Inactivity Threshold Exceeded (X days)"`

**If false (or source is Unknown):**

1. Update `fsi_lastactivitydate` if a valid date was found
2. If source is `"Unknown"`, log compliance event: `fsi_eventtype` = `"Activity Data Unavailable"`, `fsi_complianceimpact` = `"Low"`

---

## Flow 4: Execute-DeactivationWorkflow

### Trigger Configuration

| Setting | Value |
|---------|-------|
| Type | When a flow is called (Instant — Child flow) |
| Inputs | See below |

**Input Parameters:**

| Parameter | Type | Required | Description |
|-----------|------|----------|-------------|
| `agentId` | String | Yes | Entra agent Object ID |
| `agentName` | String | Yes | Agent display name |
| `reason` | String | Yes | Deactivation reason |
| `requestedBy` | String | Yes | UPN of requesting flow or user |
| `environmentId` | String | Yes | Environment ID |

### Step 1: Check Feature Flag

Same pattern as Flow 1, Step 1. Terminate if disabled.

### Step 2: Check for Duplicate Request

**Action:** Dataverse — List rows

| Parameter | Value |
|-----------|-------|
| Table | `fsi_deactivationrequest` |
| Filter rows | `fsi_agentid eq '@{triggerBody()?['agentId']}' and fsi_requeststatus eq 'Pending'` |
| Top count | `1` |

**Condition:** If result is non-empty, log `"Duplicate Request Skipped"` and terminate with `Cancelled` status.

### Step 3: Create Deactivation Request Record

**Action:** Dataverse — Add a new row

| Parameter | Value |
|-----------|-------|
| Table | `fsi_deactivationrequest` |
| `fsi_agentid` | `triggerBody()?['agentId']` |
| `fsi_agentname` | `triggerBody()?['agentName']` |
| `fsi_reason` | `triggerBody()?['reason']` |
| `fsi_requestedby` | `triggerBody()?['requestedBy']` |
| `fsi_requeststatus` | `"Pending"` |
| `fsi_requestdate` | `utcNow()` |

### Step 4: Send Deactivation Approval

**Action:** Approvals — Start and wait for an approval

| Parameter | Value |
|-----------|-------|
| Approval type | Approve/Reject — First to respond |
| Title | `Agent Deactivation: @{triggerBody()?['agentName']}` |
| Assigned to | Sponsor UPN (resolved from lifecycle record) |
| Details | Include agent name, reason, zone, last activity date |
| Item link | Deep link to deactivation request record |

**Timeout:** 5 business days (PT120H)

**On timeout:** Escalate to `EscalationApproverUPN` with a second approval request.

### Step 5: Condition — Approved?

**Condition:** `outcome eq 'Approve'`

#### If Approved:

##### Step 5a: Disable Agent Service Principal

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `PATCH` |
| URI | `/v1.0/servicePrincipals/@{triggerBody()?['agentId']}` |
| Body | `{"accountEnabled": false}` |

**Headers:**

```json
{
  "Content-Type": "application/json"
}
```

##### Step 5b: Calculate Deletion Hold Period

```
// Zone-based hold periods
holdDays = if(equals(zone, 3), 90, 30)
// Zone 1 and 2: 30 days; Zone 3: 90 days
deletionHoldExpiry = addDays(utcNow(), holdDays)
```

##### Step 5c: Update Deactivation Request

**Action:** Dataverse — Update a row

| Parameter | Value |
|-----------|-------|
| `fsi_requeststatus` | `"Approved"` |
| `fsi_approvedby` | Approver identity |
| `fsi_approveddate` | `utcNow()` |
| `fsi_approvalcomments` | Approval response comments |
| `fsi_deletionholdexpiry` | Calculated hold expiry |
| `fsi_deletioncompleted` | `false` |

##### Step 5d: Update Lifecycle Record

**Action:** Dataverse — Update a row

| Parameter | Value |
|-----------|-------|
| Table | `fsi_agentlifecyclerecord` |
| `fsi_lifecyclestage` | `"Deactivated"` |
| `fsi_deactivationrequested` | `true` |
| `fsi_lastupdated` | `utcNow()` |

##### Step 5e: Log Compliance Event

Log `fsi_eventtype` = `"Agent Deactivated"`, `fsi_complianceimpact` = `"High"`.

##### Step 5f: Notify Sponsor

Send Teams message confirming deactivation with deletion hold expiry date.

#### If Rejected:

##### Step 5g: Update Deactivation Request

Set `fsi_requeststatus` = `"Rejected"`, record rejection comments.

##### Step 5h: Restore Lifecycle Record

**Action:** Dataverse — Update a row

| Parameter | Value |
|-----------|-------|
| `fsi_lifecyclestage` | `"Active"` |
| `fsi_deactivationrequested` | `false` |
| `fsi_lastupdated` | `utcNow()` |

##### Step 5i: Log Compliance Event

Log `fsi_eventtype` = `"Deactivation Rejected"`, `fsi_complianceimpact` = `"None"`.

> **CRITICAL:** This flow must never call the DELETE API on a service principal. Permanent deletion is exclusively the responsibility of Flow 6 (Check-DeletionHold-Daily) after the hold period expires and a final confirmation is obtained.

---

## Flow 5: Monitor-SponsorChanges-Weekly

### Trigger Configuration

| Setting | Value |
|---------|-------|
| Type | Recurrence |
| Frequency | Week |
| Interval | 1 |
| Days | Monday |
| Start time | `07:30 AM UTC` |

### Step 1: Check Feature Flag

Same pattern as Flow 1, Step 1. Terminate if disabled.

### Step 2: Get Agents with Active Sponsors

**Action:** Dataverse — List rows

| Parameter | Value |
|-----------|-------|
| Table | `fsi_agentlifecyclerecord` |
| Filter rows | `fsi_sponsoractive eq true and fsi_lifecyclestage ne 'Deleted'` |

### Step 3: Initialize Summary Variables

| Variable | Type | Value |
|----------|------|-------|
| `sponsorsValidated` | Integer | `0` |
| `sponsorsDeparted` | Integer | `0` |
| `orphansDetected` | Integer | `0` |
| `reassignmentsCompleted` | Integer | `0` |

### Step 4: For Each Agent — Validate Sponsor

**Action:** Apply to each on query results

#### Step 4a: Check Sponsor Account Status

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| URI | `/v1.0/users/@{items('For_Each_Sponsored')?['fsi_sponsorobjectid']}?$select=id,accountEnabled,displayName` |

**Error handling:** If `404` (user not found), treat as departed.

#### Step 4b: Condition — Sponsor Active?

**Condition:** `body('Check_Sponsor')?['accountEnabled']` equals `true`

**If true:** Increment `sponsorsValidated`. Continue to next agent.

**If false (sponsor departed):**

1. Increment `sponsorsDeparted`
2. Mark sponsor inactive in `fsi_sponsorassignment`: set `fsi_isactive` = `false`, `fsi_enddate` = `utcNow()`
3. Update lifecycle record: `fsi_sponsoractive` = `false`

#### Step 4c: Attempt Auto-Reassignment

Try fallback sponsor resolution in order:

1. **Manager of departed sponsor:** GET `/v1.0/users/{sponsorId}/manager`
2. **Default sponsor:** Use `DefaultSponsorUPN` environment variable

For each candidate, verify `accountEnabled` = `true` before assignment.

**If reassignment succeeds:**

1. Increment `reassignmentsCompleted`
2. Create new `fsi_sponsorassignment` record
3. Update lifecycle record with new sponsor
4. Log compliance event: `fsi_eventtype` = `"Sponsor Reassigned"`, `fsi_complianceimpact` = `"Medium"`
5. Send Teams notification to new sponsor

#### Step 4d: If All Fallbacks Fail

1. Increment `orphansDetected`
2. Log compliance event: `fsi_eventtype` = `"Orphan Detected"`, `fsi_complianceimpact` = `"Critical"`
3. Send Teams alert to `GovernanceCommitteeUPN`
4. **Trigger Flow 4** (Execute-DeactivationWorkflow) with reason `"Sponsor Departed — No Fallback Available"`

#### Step 4e: Trigger Entra Lifecycle Workflow (If Sponsor Changed)

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `POST` |
| URI | `/v1.0/identityGovernance/lifecycleWorkflows/workflows/{workflowId}/activate` |
| Body | Subject references for affected agent service principal |

### Step 5: Generate Weekly Summary

**Action:** Microsoft Teams — Post message

Post summary to governance channel:

```
Weekly Sponsor Validation Summary — @{formatDateTime(utcNow(), 'yyyy-MM-dd')}
━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
Sponsors Validated:        @{variables('sponsorsValidated')}
Sponsors Departed:         @{variables('sponsorsDeparted')}
Auto-Reassigned:           @{variables('reassignmentsCompleted')}
Orphans Detected:          @{variables('orphansDetected')}
```

---

## Flow 6: Check-DeletionHold-Daily

### Trigger Configuration

| Setting | Value |
|---------|-------|
| Type | Recurrence |
| Frequency | Day |
| Interval | 1 |
| Start time | `05:00 AM UTC` |

### Step 1: Check Feature Flag

Same pattern as Flow 1, Step 1. Terminate if disabled.

### Step 2: Query Expired Deletion Holds

**Action:** Dataverse — List rows

| Parameter | Value |
|-----------|-------|
| Table | `fsi_deactivationrequest` |
| Filter rows | `fsi_requeststatus eq 'Approved' and fsi_deletionholdexpiry lt @{utcNow()} and fsi_deletioncompleted eq false` |

### Step 3: For Each Expired Hold

**Action:** Apply to each on query results

#### Step 3a: Send Final Confirmation Approval

**Action:** Approvals — Start and wait for an approval

| Parameter | Value |
|-----------|-------|
| Approval type | Approve/Reject — First to respond |
| Title | `FINAL DELETION: @{items('For_Each_Expired')?['fsi_agentname']}` |
| Assigned to | `GovernanceCommitteeUPN` (environment variable) |
| Details | Include agent name, original deactivation reason, hold period, and warning that this action is irreversible |

**Timeout:** 3 business days (PT72H). If no response, do NOT auto-delete — extend hold by 30 days and alert `EscalationApproverUPN`.

#### Step 3b: Condition — Confirmed?

**Condition:** `outcome eq 'Approve'`

**If confirmed (delete):**

##### Step 3b-i: Delete Service Principal

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `DELETE` |
| URI | `/v1.0/servicePrincipals/@{items('For_Each_Expired')?['fsi_agentid']}` |

**Error handling:**

| Status Code | Action |
|-------------|--------|
| `204` | Success — proceed to record update |
| `404` | Already deleted externally — mark as deleted, log event |
| Other | Alert `FlowAdministrators`, retry on next daily run |

##### Step 3b-ii: Update Deactivation Request

Set `fsi_deletioncompleted` = `true`, `fsi_deletiondate` = `utcNow()`.

##### Step 3b-iii: Update Lifecycle Record

Set `fsi_lifecyclestage` = `"Deleted"`, `fsi_lastupdated` = `utcNow()`.

##### Step 3b-iv: Log Compliance Event

Log `fsi_eventtype` = `"Agent Deleted"`, `fsi_complianceimpact` = `"Critical"`.

**If rejected (extend hold):**

##### Step 3b-v: Extend Deletion Hold

**Action:** Dataverse — Update a row

| Parameter | Value |
|-----------|-------|
| `fsi_deletionholdexpiry` | `addDays(utcNow(), 30)` |

##### Step 3b-vi: Log Compliance Event

Log `fsi_eventtype` = `"Deletion Hold Extended"`, `fsi_complianceimpact` = `"Medium"`.

---

## Error Handling

All flows should implement consistent error handling using the patterns below.

### Graph API Rate Limiting (429)

Configure retry policies on all HTTP with Microsoft Entra ID actions:

```json
{
  "type": "exponential",
  "count": 3,
  "interval": "PT30S",
  "minimumInterval": "PT10S",
  "maximumInterval": "PT1H"
}
```

The `Retry-After` header from Microsoft Graph is honored automatically by the HTTP connector's exponential backoff.

### Feature Flag Disabled

All flows terminate gracefully when `IsAgent365LifecycleEnabled` = `"false"`:

1. Log a `"Feature Flag Skip"` event to `fsi_lifecyclecomplianceevent`
2. Terminate with `Cancelled` status (not `Failed`)
3. No error alerts are generated

### API Permission Errors (403)

1. Log the error with full response body to `fsi_lifecyclecomplianceevent`
2. Send Teams alert to `FlowAdministrators` environment variable
3. Continue processing remaining agents (do not halt the entire run)

### Duplicate Request Prevention

Flows 3, 4, and 5 must check for existing open deactivation requests before creating new ones:

```
Filter: fsi_agentid eq '{agentId}' and fsi_requeststatus eq 'Pending'
```

If a pending request exists, skip creation and log `"Duplicate Request Skipped"`.

### Scope-Based Error Wrapping

Wrap major flow sections in Scope actions for structured error handling:

```json
{
  "Handle_Error": {
    "type": "Scope",
    "actions": {
      "Log_Error": { "..." },
      "Alert_Admins": { "..." }
    },
    "runAfter": {
      "Main_Processing_Scope": ["Failed", "TimedOut"]
    }
  }
}
```

---

## Environment Variables Reference

All flows reference these solution-level environment variables:

| Variable | Type | Purpose |
|----------|------|---------|
| `IsAgent365LifecycleEnabled` | String | Feature flag — `"true"` or `"false"`. Gates all Agent 365 API calls. |
| `DefaultSponsorUPN` | String | Fallback sponsor UPN when no sponsor is assigned or all fallbacks fail |
| `FSIAllAgentIdentitiesGroupId` | String | Entra security group ID for all agent service principals |
| `FSIZone3AgentsGroupId` | String | Entra security group ID for Zone 3 agent service principals |
| `DataverseEnvironmentUrl` | String | Base URL for the Dataverse environment (e.g., `https://org.crm.dynamics.com`) |
| `EscalationApproverUPN` | String | UPN for timeout and overdue review escalations |
| `GovernanceCommitteeUPN` | String | UPN or group for final deletion confirmations |
| `FlowAdministrators` | String | Teams channel or distribution list for flow error alerts |
| `AgentRegistryApiVersion` | String | Graph API version for agent registry calls (default: `beta`) |
| `InactivityThresholdZone1` | Integer | Days of inactivity before flagging (Zone 1 default: `180`) |
| `InactivityThresholdZone2` | Integer | Days of inactivity before flagging (Zone 2 default: `90`) |
| `InactivityThresholdZone3` | Integer | Days of inactivity before flagging (Zone 3 default: `30`) |
| `DeletionHoldDaysDefault` | Integer | Days to hold before permanent deletion (default: `30`) |
| `DeletionHoldDaysZone3` | Integer | Extended hold period for Zone 3 agents (default: `90`) |

---

## Concurrency Configuration

### Trigger Settings

```json
"runtimeConfiguration": {
  "concurrency": {
    "runs": 1
  }
}
```

All lifecycle flows run with concurrency of `1` to prevent race conditions on shared Dataverse records and duplicate deactivation requests.

---

## Managed Solution Wrapper

All components should be developed inside a Dataverse solution container for managed solution transport.

### Solution Configuration

| Property | Value |
|----------|-------|
| Display Name | Agent 365 Lifecycle Governance |
| Unique Name | `fsi_Agent365LifecycleGovernance` |
| Publisher | FSI Publisher (`fsi`) |
| Version | `1.1.0.0` |

### Components to Include

| Component Type | Components |
|---------------|------------|
| Tables | AgentLifecycleRecord, SponsorAssignment, AccessReview, DeactivationRequest, LifecycleComplianceEvent |
| Columns | All `fsi_` prefixed columns on all five tables |
| Security Roles | ALG Administrator, ALG Reviewer, ALG Read Only |
| Cloud Flows | Flow 1–6 (all six lifecycle flows) |
| Connection References | Dataverse, HTTP with Microsoft Entra ID, Microsoft Teams, Approvals, Power Platform for Admins V2 |
| Environment Variables | All 14 variables listed above |

---

## Testing

### Test Cases

| Scenario | Expected Result |
|----------|-----------------|
| New agent without sponsor | Sponsor assigned, lifecycle record created, Teams notification sent |
| Agent with existing sponsor | Lifecycle record updated, no sponsor change |
| Agent due for access review | Entra access review created, review record logged |
| Access review denied | Deactivation workflow triggered |
| Overdue access review | Escalation sent to EscalationApproverUPN |
| Agent inactive beyond threshold | Lifecycle stage set to Inactive, deactivation triggered |
| All activity sources return null | Agent skipped, "Activity Data Unavailable" logged |
| Deactivation approved | Service principal disabled, deletion hold set |
| Deactivation rejected | Agent restored to Active |
| Sponsor departed with manager fallback | Auto-reassigned to manager |
| Sponsor departed, all fallbacks fail | Orphan detected, governance committee alerted |
| Deletion hold expired and confirmed | Service principal deleted permanently |
| Deletion hold rejected | Hold extended by 30 days |
| Feature flag disabled | All flows terminate gracefully with skip event |
| Duplicate deactivation request | Second request skipped |

### Manual Test Sequence

1. Set `IsAgent365LifecycleEnabled` to `"true"`
2. Create a test agent in Agent 365 Registry (or use a sandbox agent)
3. Run Flow 1 manually — verify sponsor assignment and lifecycle record
4. Advance `fsi_nextreviewdue` to past date, run Flow 2 — verify access review creation
5. Set `fsi_lastactivitydate` to 100+ days ago, run Flow 3 — verify inactivity detection
6. Verify Flow 4 triggers and sends approval
7. Approve deactivation — verify service principal is disabled
8. Advance `fsi_deletionholdexpiry` to past date, run Flow 6 — verify final confirmation
9. Confirm deletion — verify service principal is removed
10. Check `fsi_lifecyclecomplianceevent` for complete audit trail

---

## Next Steps

After configuring flows:

1. Deploy Dataverse schema — run `create_alg_dataverse_schema.py`
2. Configure environment variables for your tenant
3. [Review troubleshooting guide](./troubleshooting.md)
