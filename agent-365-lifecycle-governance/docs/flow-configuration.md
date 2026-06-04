# Power Automate Flow Configuration

> **Note:** All choice/option-set field filters in OData expressions use integer values, not string labels. Refer to [dataverse-schema.md](./dataverse-schema.md) for the integer↔label mapping.

> **Note:** All environment variable references throughout this document use the **display name** (e.g. `IsAgent365LifecycleEnabled`) for readability. In the Power Automate "Get environment variable" action, supply the **schema name** prefix `fsi_ALG_` (e.g. `fsi_ALG_IsAgent365LifecycleEnabled`). The schema names are defined in `scripts/create_alg_environment_variables.py`.

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
| **HTTP with Microsoft Entra ID** | Graph API calls (Agent 365 `agentInstances`, sponsor-user Lifecycle Workflows, Access Reviews) | Premium |
| **Microsoft Teams** | Sponsor notification cards | Included |
| **Approvals** | Deactivation and deletion approvals | Included |
| **Power Platform for Admins V2** | Agent activity data from PPAC | Premium |

---

## Feature Flag

> **CRITICAL:** Every flow must check the `IsAgent365LifecycleEnabled` environment variable as its **first action**. If the value is `"false"`, the flow must log a skip event to `fsi_lifecyclecomplianceevent` and terminate with `Cancelled` status and message `"Agent 365 Lifecycle not enabled"`. This gate allows flows to be disabled independently of deployment status.

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

1. Log skip event to `fsi_lifecyclecomplianceevent`:
   - `fsi_name`: `"Feature Flag Skip — Flow 1 — @{utcNow()}"`
   - `fsi_eventtype`: `100000015` (Feature Flag Skip)
   - `fsi_eventdetails`: `"Flow skipped — IsAgent365LifecycleEnabled is false"`
   - `fsi_complianceimpact`: `100000000` (None)
   - `fsi_triggeredby`: `"Flow 1: Enforce-SponsorAssignment-OnOnboard"`
   - `fsi_timestamp`: `utcNow()`
2. **Terminate** with status `Cancelled` and message `"Agent 365 Lifecycle not enabled"`

### Step 2: Get All Agents from Entra

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| Base Resource URL | `https://graph.microsoft.com` |
| Microsoft Entra ID Resource URI | `https://graph.microsoft.com` |
| URI | `/beta/agentRegistry/agentInstances` |

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

#### Step 3a: Check If Agent Has Owner

**Condition:** `empty(items('For_Each_Agent')?['ownerIds'])` equals `true`

Initialize per-agent variables before the condition:

- `sponsorObjectId` (String)
- `sponsorUpn` (String)
- `sponsorActive` (Boolean, default `false`)

#### Step 3b: If No Owner — Resolve Default Sponsor

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| URI | `/v1.0/users/@{variables('DefaultSponsorUPN')}?$select=id,userPrincipalName,accountEnabled,displayName,mail` |

**Post-action condition:** Verify `accountEnabled` equals `true`. If the default sponsor account is disabled, terminate with error and alert `FlowAdministrators`.

Set variables after a successful lookup:

- `sponsorObjectId` = `body('Resolve_Default_Sponsor')?['id']`
- `sponsorUpn` = `coalesce(body('Resolve_Default_Sponsor')?['userPrincipalName'], body('Resolve_Default_Sponsor')?['mail'])`
- `sponsorActive` = `body('Resolve_Default_Sponsor')?['accountEnabled']`

#### Step 3c: Assign Sponsor/Owner via PATCH

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `PATCH` |
| URI | `/beta/agentRegistry/agentInstances/@{items('For_Each_Agent')?['id']}` |
| Body | See below |

```json
{
  "ownerIds": ["@{variables('sponsorObjectId')}"]
}
```

> **CRITICAL:** Current Microsoft Graph beta documents `ownerIds` as the updatable owner collection for `agentInstance`. Do not use the stale `sponsor@odata.bind` pattern. If the agent must retain existing owners, merge the existing `ownerIds` array with the default sponsor Object ID before PATCHing.

#### Step 3c-alt: If Owner Exists — Resolve Current Owner

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| URI | `/v1.0/users/@{first(items('For_Each_Agent')?['ownerIds'])}?$select=id,userPrincipalName,accountEnabled,displayName,mail` |

Set the same `sponsorObjectId`, `sponsorUpn`, and `sponsorActive` variables from the resolved owner response. If the owner ID does not resolve to a user, route the agent through the exception path, alert `FlowAdministrators`, and do not overwrite owner data with the default sponsor unless firm policy explicitly permits reassignment.

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

**Post-action:** Set source and zone variables based on result.

> **Important — option set integer mapping:** `fsi_environment_policy.fsi_governancezone` is the ELM-owned `fsi_acv_zone` option set (`Unclassified=100000000`, `Zone 1=100000001`, `Zone 2=100000002`, `Zone 3=100000003`). The local `fsi_ALG_governancezone` option set on `fsi_agentlifecyclerecord` uses `Zone 1=100000000`, `Zone 2=100000001`, `Zone 3=100000002`. Remap ELM values before writing ALG records.

```
// Source identifiers. Current Agent 365 agentInstances do not always expose a Power Platform environment ID.
agentInstanceId = items('For_Each_Agent')?['id']
agentSourceId = coalesce(items('For_Each_Agent')?['sourceAgentId'], items('For_Each_Agent')?['id'])
agentEnvironmentId = coalesce(items('For_Each_Agent')?['environmentId'], items('For_Each_Agent')?['originatingStore'], 'agent-365-registry')
agentIdentityId = items('For_Each_Agent')?['agentIdentityId']

// Raw ELM option-set integer, or Zone 2 default when no policy is available.
elmZoneOption = if(empty(body('Get_Zone_Policy')?['value']), 100000002, first(body('Get_Zone_Policy')?['value'])?['fsi_governancezone'])

// ALG option-set integer for Dataverse writes.
zoneOption = if(equals(elmZoneOption, 100000001), 100000000, if(equals(elmZoneOption, 100000003), 100000002, 100000001))

// Human-readable zone number (1/2/3) used only for local branching.
zone = add(sub(zoneOption, 100000000), 1)

// Inactivity threshold (days)
inactivityThreshold = if(equals(zone, 1), 180, if(equals(zone, 2), 90, 30))

// Review cadence (integer for Dataverse, display text for notifications)
// Cadence option set: Annual=100000000, Semi-Annual=100000001, Quarterly=100000002
reviewCadence = if(equals(zone, 1), 100000000, if(equals(zone, 2), 100000001, 100000002))
reviewCadenceLabel = if(equals(zone, 1), 'Annual', if(equals(zone, 2), 'Semi-Annual', 'Quarterly'))

// Next review due (days from now)
nextReviewDays = if(equals(zone, 1), 365, if(equals(zone, 2), 180, 90))
```

#### Step 3e: Upsert Agent Lifecycle Record

**Action:** Dataverse — Perform an unbound action (or HTTP to Dataverse API)

| Parameter | Value |
|-----------|-------|
| Method | `PATCH` |
| URI | `/api/data/v9.2/fsi_agentlifecyclerecords(fsi_agentid='@{variables('agentInstanceId')}',fsi_environmentid='@{variables('agentEnvironmentId')}')` |
| Header | `If-Match: *` (upsert) |

> **Prerequisite:** The composite alternate key (`fsi_agentid` + `fsi_environmentid`) on `fsi_agentlifecyclerecord` must be deployed by `scripts/create_alg_dataverse_schema.py`. If the key is missing, this PATCH returns `404 KeyAttributesDoesNotExist`.

**Body:**

```json
{
  "fsi_agentname": "@{items('For_Each_Agent')?['displayName']}",
  "fsi_governancezone": @{variables('zoneOption')},
  "fsi_lifecyclestage": @{if(empty(items('For_Each_Agent')?['ownerIds']), 100000000, 100000001)},
  "fsi_entraobjectid": "@{variables('agentIdentityId')}",
  "fsi_sponsorupn": "@{variables('sponsorUpn')}",
  "fsi_sponsorobjectid": "@{variables('sponsorObjectId')}",
  "fsi_sponsoractive": @{variables('sponsorActive')},
  "fsi_sponsorassigneddate": "@{utcNow()}",
  "fsi_inactivitythreshold": @{variables('inactivityThreshold')},
  "fsi_accessreviewstatus": 100000000,
  "fsi_nextreviewdue": "@{addDays(utcNow(), variables('nextReviewDays'))}",
  "fsi_reviewcadence": @{variables('reviewCadence')},
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
| `fsi_sponsorupn` | Resolved sponsor UPN |
| `fsi_sponsorobjectid` | Resolved sponsor Object ID |
| `fsi_sponsordisplayname` | `body('Resolve_Default_Sponsor')?['displayName']` |
| `fsi_assignmentdate` | `utcNow()` |
| `fsi_assignmentreason` | `100000000` (Initial Onboarding) or `100000003` (Manual Reassignment) |
| `fsi_assignedby` | `"Flow 1: Enforce-SponsorAssignment-OnOnboard"` |
| `fsi_iscurrent` | `true` |
| `fsi_AgentLifecycleRecordLookup@odata.bind` | `/fsi_agentlifecyclerecords(<lifecycle record GUID>)` |

#### Step 3g: Add Agent to Security Groups

**Action (always):** HTTP with Microsoft Entra ID — Add to FSI-AllAgentIdentities

| Parameter | Value |
|-----------|-------|
| Method | `POST` |
| URI | `/v1.0/groups/@{variables('FSIAllAgentIdentitiesGroupId')}/members/$ref` |
| Body | `{"@odata.id": "https://graph.microsoft.com/v1.0/servicePrincipals/@{variables('agentIdentityId')}"}` |

**Error handling:** If `400` (already a member), continue without error.

**Condition:** If `zone` equals `3`:

**Action:** HTTP with Microsoft Entra ID — Add to FSI-Zone3-Agents

| Parameter | Value |
|-----------|-------|
| Method | `POST` |
| URI | `/v1.0/groups/@{variables('FSIZone3AgentsGroupId')}/members/$ref` |
| Body | `{"@odata.id": "https://graph.microsoft.com/v1.0/servicePrincipals/@{variables('agentIdentityId')}"}` |

#### Step 3h: Log Compliance Event

**Action:** Dataverse — Add a new row

| Parameter | Value |
|-----------|-------|
| Table | `fsi_lifecyclecomplianceevent` |
| `fsi_name` | `"Sponsor Assigned — @{items('For_Each_Agent')?['displayName']} — @{utcNow()}"` |
| `fsi_eventtype` | `100000000` (Sponsor Assigned) |
| `fsi_agentid` | Agent ID |
| `fsi_agentname` | Agent display name |
| `fsi_eventdetails` | JSON with assignment method, zone, and sponsor UPN |
| `fsi_complianceimpact` | `100000000` (None) |
| `fsi_triggeredby` | `"Flow 1: Enforce-SponsorAssignment-OnOnboard"` |
| `fsi_timestamp` | `utcNow()` |
| `fsi_relatedrecordid` | `workflow()?['run']?['name']` |

#### Step 3i: Send Teams Notification to Sponsor

**Action:** Microsoft Teams — Post adaptive card in a chat or channel

Send an Adaptive Card (v1.4) to the sponsor with:

- Agent display name and ID
- Governance zone assignment
- Sponsor responsibilities summary
- Link to agent lifecycle record in Dataverse
- "Acknowledge" action button

```json
{
  "type": "AdaptiveCard",
  "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
  "version": "1.4",
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
        { "title": "Review Cadence", "value": "@{variables('reviewCadenceLabel')}" },
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
| Filter rows | `fsi_nextreviewdue le @{utcNow()} and fsi_lifecyclestage eq 100000001` |

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
    "query": "/servicePrincipals/@{items('For_Each_Due')?['fsi_entraobjectid']}",
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
| `fsi_name` | `"Access Review — @{items('For_Each_Due')?['fsi_agentname']} — @{formatDateTime(utcNow(), 'yyyy-MM-dd')}"` |
| `fsi_reviewtype` | Zone-based cadence |
| `fsi_zonecadence` | `@{items('For_Each_Due')?['fsi_reviewcadence']}` (integer from lifecycle record) |
| `fsi_reviewstatus` | `100000001` (In Progress) |
| `fsi_reviewstartdate` | `utcNow()` |
| `fsi_reviewduedate` | `addDays(utcNow(), 14)` |
| `fsi_certifierupn` | Certifier UPN |
| `fsi_entrareviewid` | `body('Create_Access_Review')?['id']` |
| `fsi_entrareviewinstanceid` | Instance ID from Step A2d |
| `fsi_AgentLifecycleRecordLookup@odata.bind` | `/fsi_agentlifecyclerecords(<lifecycle record GUID>)` |

##### Step A2f: Update Lifecycle Record

**Action:** Dataverse — Update a row

| Parameter | Value |
|-----------|-------|
| Table | `fsi_agentlifecyclerecord` |
| `fsi_accessreviewstatus` | `100000001` (In Progress) |
| `fsi_nextreviewdue` | Calculate from zone cadence (Annual/Semi-Annual/Quarterly) |
| `fsi_lastupdated` | `utcNow()` |

##### Step A2g: Log Compliance Event

Log compliance event:
- `fsi_name`: `"Access Review Started — @{items('For_Each_Due')?['fsi_agentname']} — @{utcNow()}"`
- `fsi_eventtype`: `100000003` (Access Review Started)
- `fsi_complianceimpact`: `100000000` (None)
- `fsi_triggeredby`: `"Flow 2: Schedule-AccessReview-ZoneBased"`
- `fsi_timestamp`: `utcNow()`

### Part B — Check Overdue Reviews (Scope)

#### Step B1: Query Overdue Reviews

**Action:** Dataverse — List rows

| Parameter | Value |
|-----------|-------|
| Table | `fsi_accessreview` |
| Filter rows | `fsi_reviewstatus eq 100000001 and fsi_reviewduedate lt @{utcNow()}` |

#### Step B2: For Each Overdue Review

1. **Update review status:** Set `fsi_reviewstatus` to `100000003` (Overdue)
2. **Send Teams escalation:** Post message to `EscalationApproverUPN` with agent name, original due date, and days overdue
3. **Log compliance event:** `fsi_eventtype` = `100000005` (Access Review Overdue), `fsi_complianceimpact` = `100000003` (High)

### Part C — Poll Completed Reviews (Scope)

#### Step C1: Query In-Progress Reviews with Instance ID

**Action:** Dataverse — List rows

| Parameter | Value |
|-----------|-------|
| Table | `fsi_accessreview` |
| Filter rows | `fsi_reviewstatus eq 100000001 and fsi_entrareviewinstanceid ne null` |

#### Step C2: For Each Review — Check Decisions

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| URI | `/v1.0/identityGovernance/accessReviews/definitions/@{items('For_Each_Review')?['fsi_entrareviewid']}/instances/@{items('For_Each_Review')?['fsi_entrareviewinstanceid']}/decisions` |

**Post-action logic:**

1. If decisions array is non-empty and all decisions are present:
   - Mark `fsi_reviewstatus` = `100000002` (Completed)
   - Set `fsi_decisiondate` = `utcNow()`
   - Store `fsi_certifierdecision` = decision value (`100000000` Approved, `100000001` Denied, or `100000002` Not Reviewed)
2. If **any** decision is `"Deny"`:
   - Log compliance event: `fsi_eventtype` = `100000004` (Access Review Completed), `fsi_complianceimpact` = `100000004` (Critical), with `fsi_certifierdecision` = `100000001` (Denied)
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
| Filter rows | `fsi_lifecyclestage eq 100000001` |

### Step 3: For Each Active Agent

**Action:** Apply to each on query results

#### Step 3a: Query Entra Sign-in Logs (API 11)

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| URI | `/v1.0/auditLogs/signIns?$filter=appId eq '@{variables('agentAppId')}'&$top=1&$orderby=createdDateTime desc` |

Before this call, resolve `agentAppId` from the linked service principal when the Agent 365 registry response provides only `agentIdentityId`/object ID. Microsoft Graph sign-in logs filter `appId` by application/client ID, not agent registry instance ID.

Extract: `first(body('Get_SignIn_Logs')?['value'])?['createdDateTime']`

> This is the most authoritative source for Microsoft Entra sign-in activity when the correct app/client ID is available.

#### Step 3b: Query PPAC Bots API (API 10)

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `GET` |
| Base Resource URL | `https://api.bap.microsoft.com` |
| Microsoft Entra ID Resource URI | `https://api.bap.microsoft.com` |
| URI | `/providers/Microsoft.BusinessAppPlatform/environments/@{items('For_Each_Active')?['fsi_environmentid']}/bots?api-version=2022-03-01-preview` |

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
   - `fsi_lifecyclestage` = `100000003` (Inactive)
   - `fsi_lastactivitydate` = `lastActivityDate`
   - `fsi_lastupdated` = `utcNow()`

2. Log compliance event: `fsi_eventtype` = `100000007` (Inactivity Detected), `fsi_complianceimpact` = `100000002` (Medium)

3. **Trigger Flow 4** (Execute-DeactivationWorkflow) with agent ID and reason `"Inactivity Threshold Exceeded (X days)"`

**If false (or source is Unknown):**

1. Update `fsi_lastactivitydate` if a valid date was found
2. If source is `"Unknown"`, log compliance event: `fsi_eventtype` = `100000007` (Inactivity Detected), `fsi_complianceimpact` = `100000001` (Low), with `fsi_eventdetails` = `"Activity data unavailable — all sources returned null. No deactivation triggered."`

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
| `agentId` | String | Yes | Agent 365 agentInstance ID |
| `entraObjectId` | String | Yes | Microsoft Entra agent identity / service principal object ID, if present |
| `agentName` | String | Yes | Agent display name |
| `reason` | String | Yes | Deactivation reason |
| `requestedBy` | String | Yes | UPN of requesting flow or user |
| `environmentId` | String | Yes | Environment ID |

### Step 1: Check Feature Flag

Same pattern as Flow 1, Step 1. Terminate if disabled.

### Step 2: Resolve Lifecycle Record

**Action:** Dataverse — List rows (or GET by alternate key)

| Parameter | Value |
|-----------|-------|
| Table | `fsi_agentlifecyclerecord` |
| URI | `/api/data/v9.2/fsi_agentlifecyclerecords(fsi_agentid='@{triggerBody()?['agentId']}',fsi_environmentid='@{triggerBody()?['environmentId']}')` |

Store the lifecycle record GUID in a variable `lifecycleRecordId`.

### Step 3: Check for Duplicate Request

**Action:** Dataverse — List rows

| Parameter | Value |
|-----------|-------|
| Table | `fsi_deactivationrequest` |
| Filter rows | `_fsi_agentlifecyclerecordlookup_value eq @{variables('lifecycleRecordId')} and fsi_approvalstatus eq 100000000` |
| Top count | `1` |

**Condition:** If result is non-empty, log compliance event with `fsi_eventtype` = `100000008` (Deactivation Requested) and `fsi_eventdetails` = `"Duplicate deactivation request skipped for agent @{triggerBody()?['agentId']}"`, then terminate with `Cancelled` status.

### Step 4: Create Deactivation Request Record

**Action:** Dataverse — Add a new row

| Parameter | Value |
|-----------|-------|
| Table | `fsi_deactivationrequest` |
| `fsi_name` | `"Deactivation — @{triggerBody()?['agentName']} — @{utcNow()}"` |
| `fsi_triggerreason` | Map from `triggerBody()?['reason']`: Inactivity=`100000000`, Sponsor Departed=`100000001`, Access Review Denied=`100000002`, Manual=`100000003` |
| `fsi_requestedby` | `triggerBody()?['requestedBy']` |
| `fsi_approvalstatus` | `100000000` (Pending) |
| `fsi_requestdate` | `utcNow()` |
| `fsi_AgentLifecycleRecordLookup@odata.bind` | `/fsi_agentlifecyclerecords(<lifecycle record GUID>)` |

### Step 5: Send Deactivation Approval

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

### Step 6: Condition — Approved?

**Condition:** `outcome eq 'Approve'`

#### If Approved:

##### Step 6a: Disable Agent Service Principal

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `PATCH` |
| URI | `/v1.0/servicePrincipals/@{triggerBody()?['entraObjectId']}` |
| Body | `{"accountEnabled": false}` |

**Headers:**

```json
{
  "Content-Type": "application/json"
}
```

##### Step 6b: Calculate Deletion Hold Period

```
// Zone-based hold periods
holdDays = if(equals(zone, 3), 90, 30)
// Zone 1 and 2: 30 days; Zone 3: 90 days
deletionHoldExpiry = addDays(utcNow(), holdDays)
```

##### Step 6c: Update Deactivation Request

**Action:** Dataverse — Update a row

| Parameter | Value |
|-----------|-------|
| `fsi_approvalstatus` | `100000001` (Approved) |
| `fsi_approverupn` | Approver identity |
| `fsi_approvaldate` | `utcNow()` |
| `fsi_approvalnotes` | Approval response comments |
| `fsi_disabledate` | `utcNow()` |
| `fsi_deletionholduntil` | Calculated hold expiry |

##### Step 6d: Update Lifecycle Record

**Action:** Dataverse — Update a row

| Parameter | Value |
|-----------|-------|
| Table | `fsi_agentlifecyclerecord` |
| `fsi_lifecyclestage` | `100000005` (Deactivated) |
| `fsi_deactivationrequested` | `true` |
| `fsi_lastupdated` | `utcNow()` |

##### Step 6e: Log Compliance Event

Log `fsi_eventtype` = `100000011` (Agent Disabled), `fsi_complianceimpact` = `100000003` (High).

##### Step 6f: Notify Sponsor

Send Teams message confirming deactivation with deletion hold expiry date.

#### If Rejected:

##### Step 6g: Update Deactivation Request

Set `fsi_approvalstatus` = `100000002` (Rejected), record rejection comments in `fsi_approvalnotes`.

##### Step 6h: Restore Lifecycle Record

**Action:** Dataverse — Update a row

| Parameter | Value |
|-----------|-------|
| `fsi_lifecyclestage` | `100000001` (Active) |
| `fsi_deactivationrequested` | `false` |
| `fsi_lastupdated` | `utcNow()` |

##### Step 6i: Log Compliance Event

Log `fsi_eventtype` = `100000010` (Deactivation Rejected), `fsi_complianceimpact` = `100000000` (None).

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
| Filter rows | `fsi_sponsoractive eq true and fsi_lifecyclestage ne 100000006` |

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
2. Mark sponsor inactive in `fsi_sponsorassignment`: set `fsi_iscurrent` = `false`, `fsi_enddate` = `utcNow()`
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
4. Log compliance event: `fsi_eventtype` = `100000000` (Sponsor Assigned), `fsi_complianceimpact` = `100000002` (Medium), with `fsi_eventdetails` = `"Sponsor reassigned due to previous sponsor departure"`
5. Send Teams notification to new sponsor

#### Step 4d: If All Fallbacks Fail

1. Increment `orphansDetected`
2. Log compliance event: `fsi_eventtype` = `100000002` (Orphan Detected), `fsi_complianceimpact` = `100000004` (Critical)
3. Send Teams alert to `GovernanceCommitteeUPN`
4. **Trigger Flow 4** (Execute-DeactivationWorkflow) with reason `"Sponsor Departed — No Fallback Available"`

#### Step 4e: Trigger Entra Lifecycle Workflow (If Sponsor Changed)

**Action:** HTTP with Microsoft Entra ID

| Parameter | Value |
|-----------|-------|
| Method | `POST` |
| URI | `/v1.0/identityGovernance/lifecycleWorkflows/workflows/{workflowId}/activate` |
| Body | `subjects` collection containing the affected sponsor user's Microsoft Entra user ID |

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
| Filter rows | `fsi_approvalstatus eq 100000001 and fsi_deletionholduntil lt @{utcNow()} and fsi_deletiondate eq null` |

### Step 3: For Each Expired Hold

**Action:** Apply to each on query results

#### Step 3a: Send Final Confirmation Approval

**Action:** Approvals — Start and wait for an approval

| Parameter | Value |
|-----------|-------|
| Approval type | Approve/Reject — First to respond |
| Title | `FINAL DELETION: @{items('For_Each_Expired')?['fsi_name']}` |
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
| URI | `/v1.0/servicePrincipals/@{body('Get_Lifecycle_Record_For_Expired')?['fsi_entraobjectid']}` |

> **Note:** Retrieve the linked `fsi_agentlifecyclerecord` via the `fsi_AgentLifecycleRecordLookup` lookup to obtain `fsi_entraobjectid` for the DELETE call.

**Error handling:**

| Status Code | Action |
|-------------|--------|
| `204` | Success — proceed to record update |
| `404` | Already deleted externally — mark as deleted, log event |
| Other | Alert `FlowAdministrators`, retry on next daily run |

##### Step 3b-ii: Update Deactivation Request

Set `fsi_deletiondate` = `utcNow()`.

##### Step 3b-iii: Update Lifecycle Record

Set `fsi_lifecyclestage` = `100000006` (Deleted), `fsi_lastupdated` = `utcNow()`.

##### Step 3b-iv: Log Compliance Event

Log `fsi_eventtype` = `100000012` (Agent Deleted), `fsi_complianceimpact` = `100000004` (Critical).

**If rejected (extend hold):**

##### Step 3b-v: Extend Deletion Hold

**Action:** Dataverse — Update a row

| Parameter | Value |
|-----------|-------|
| `fsi_deletionholduntil` | `addDays(utcNow(), 30)` |

##### Step 3b-vi: Log Compliance Event

Log `fsi_eventtype` = `100000018` (Deletion Hold Extended), `fsi_complianceimpact` = `100000002` (Medium), with `fsi_eventdetails` = `"Deletion hold extended by 30 days — final deletion rejected"`.

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

Configure retry policies to honor Microsoft Graph throttling guidance; verify connector behavior for `Retry-After` in the target environment.

### Feature Flag Disabled

All flows terminate gracefully when `IsAgent365LifecycleEnabled` = `"false"`:

1. Log a compliance event with `fsi_eventtype` = `100000015` (Feature Flag Skip) and `fsi_eventdetails` = `"Flow skipped — feature flag disabled"` to `fsi_lifecyclecomplianceevent`
2. Terminate with `Cancelled` status (not `Failed`)
3. No error alerts are generated

### API Permission Errors (403)

1. Log the error with full response body to `fsi_lifecyclecomplianceevent`
2. Send Teams alert to `FlowAdministrators` environment variable
3. Continue processing remaining agents (do not halt the entire run)

### Duplicate Request Prevention

Flows 3, 4, and 5 must check for existing open deactivation requests before creating new ones:

```
Filter: _fsi_agentlifecyclerecordlookup_value eq {lifecycleRecordId} and fsi_approvalstatus eq 100000000
```

If a pending request exists, skip creation and log a compliance event with `fsi_eventtype` = `100000008` (Deactivation Requested) and `fsi_eventdetails` = `"Duplicate deactivation request skipped"`.

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

All flows reference these solution-level environment variables. Schema names are prefixed `fsi_ALG_`; display names below are shown for readability.

| Schema name | Display name | Type | Purpose |
|-------------|--------------|------|---------|
| `fsi_ALG_IsAgent365LifecycleEnabled` | IsAgent365LifecycleEnabled | String | Feature flag — `"true"` or `"false"`. Gates all Agent 365 API calls. |
| `fsi_ALG_DefaultSponsorUPN` | DefaultSponsorUPN | String | Fallback sponsor UPN when no sponsor is assigned or all fallbacks fail |
| `fsi_ALG_GovernanceTeamEmail` | GovernanceTeamEmail | String | Distribution list for compliance notifications |
| `fsi_ALG_GovernanceCommitteeUPN` | GovernanceCommitteeUPN | String | UPN or group for deactivation/deletion approvals |
| `fsi_ALG_EscalationApproverUPN` | EscalationApproverUPN | String | UPN for timeout and overdue review escalations |
| `fsi_ALG_FlowAdministrators` | FlowAdministrators | String | Teams channel or distribution list for flow error alerts |
| `fsi_ALG_SponsorMoverWorkflowId` | SponsorMoverWorkflowId | String | Entra Lifecycle Workflow ID for the sponsor-mover scenario (see prerequisites) |
| `fsi_ALG_SponsorLeaverWorkflowId` | SponsorLeaverWorkflowId | String | Entra Lifecycle Workflow ID for the sponsor-leaver scenario (see prerequisites) |
| `fsi_ALG_FSIAllAgentIdentitiesGroupId` | FSIAllAgentIdentitiesGroupId | String | Entra security group ID for all agent service principals |
| `fsi_ALG_FSIZone3AgentsGroupId` | FSIZone3AgentsGroupId | String | Entra security group ID for Zone 3 agent service principals |
| `fsi_ALG_DataverseEnvironmentUrl` | DataverseEnvironmentUrl | String | Base URL for the Dataverse environment (e.g., `https://org.crm.dynamics.com`) |
| `fsi_ALG_InactivityThresholdZone1` | InactivityThresholdZone1 | Decimal | Days of inactivity before flagging (Zone 1 default: `180`) |
| `fsi_ALG_InactivityThresholdZone2` | InactivityThresholdZone2 | Decimal | Days of inactivity before flagging (Zone 2 default: `90`) |
| `fsi_ALG_InactivityThresholdZone3` | InactivityThresholdZone3 | Decimal | Days of inactivity before flagging (Zone 3 default: `30`) |
| `fsi_ALG_DeletionHoldDays` | DeletionHoldDays | Decimal | Grace period in days before agent deletion executes after deactivation approval (default: `30`). Zone 3 agents typically extend to 90 days; flows apply zone-specific overrides from the zone applicability table. |
| `fsi_ALG_AgentRegistryApiVersion` | AgentRegistryApiVersion | String | Microsoft Graph API version for Agent Registry (`agentInstances`) calls (default: `v1.0`). Pin to a known-good version to avoid breaking changes during preview-to-GA transitions. |

> **Note:** `fsi_ALG_DeletionHoldDays` is deployed by `scripts/create_alg_environment_variables.py` with a default of `30` days. Flow 4 Step 6b currently uses a hard-coded value (default 30, Zone 3 90); to consume the deployed variable instead, replace the hard-coded constant with a Get-environment-variable action referencing `fsi_ALG_DeletionHoldDays` and apply the Zone 3 override (90 days) from the zone applicability table.
> **Note:** `fsi_ALG_AgentRegistryApiVersion` is deployed by `scripts/create_alg_environment_variables.py` with a default of `v1.0`. Flow 1 Step 2 currently constructs the Agent Registry URI with a hard-coded `beta` segment; to consume the deployed variable instead, replace the hard-coded segment with a Get-environment-variable action referencing `fsi_ALG_AgentRegistryApiVersion`. Microsoft Learn documents Agent Registry / package-management APIs as beta/preview and includes May 2026 convergence notices, so leave the default at `v1.0` for production and use `beta` only for non-production validation.

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
| Version | `1.1.5.0` |

### Components to Include

| Component Type | Components |
|---------------|------------|
| Tables | AgentLifecycleRecord, SponsorAssignment, AccessReview, DeactivationRequest, LifecycleComplianceEvent |
| Columns | All `fsi_` prefixed columns on all five tables |
| Security Roles | ALG Administrator, ALG Reviewer, ALG Read Only |
| Cloud Flows | Flow 1–6 (all six lifecycle flows) |
| Connection References | Dataverse, HTTP with Microsoft Entra ID, Microsoft Teams, Approvals, Power Platform for Admins V2 |
| Environment Variables | All 16 variables listed above |

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
8. Advance `fsi_deletionholduntil` to past date, run Flow 6 — verify final confirmation
9. Confirm deletion — verify service principal is removed
10. Check `fsi_lifecyclecomplianceevent` for complete audit trail

---

## Next Steps

After configuring flows:

1. Deploy Dataverse schema — run `create_alg_dataverse_schema.py`
2. Configure environment variables for your tenant
3. [Review troubleshooting guide](./troubleshooting.md)
