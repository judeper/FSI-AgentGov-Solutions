# Flow Configuration

Power Automate flow specifications for the FINRA Supervision Workflow solution.

## Flow Overview

| Flow | Trigger | Purpose |
|------|---------|---------|
| FSW-IngestFlaggedItems | Scheduled (15 min) | Poll Communication Compliance for flagged items |
| FSW-AssignmentFlow | Dataverse row created | Route items to supervisory principals |
| FSW-EscalationFlow | Scheduled (hourly) | Monitor SLA and escalate overdue items |
| FSW-ReviewComplete | Dataverse row updated | Log review completion, notify stakeholders |

---

## FSW-IngestFlaggedItems

Polls Communication Compliance API for new flagged items and creates SupervisionQueue records.

### Trigger

**Recurrence**
- Frequency: Minute
- Interval: 15
- Time zone: UTC
- Concurrency Control: On (Degree of Parallelism: 1) — prevents duplicate queue entries if a run exceeds 15 minutes

### Actions

```
1. Initialize variable: lastRunTime (from secure storage)
   - First-run guard: If the Key Vault secret does not exist, initialize lastRunTime
     to addHours(utcNow(), -1) so the first poll retrieves only the last hour of alerts
     instead of failing with HTTP 400 or returning the entire backlog.

2. HTTP - Get Communication Compliance Alerts
   Method: GET
   URI: https://compliance.microsoft.com/api/SupervisoryReview/alerts
   Headers:
     Authorization: Bearer @{outputs('Get_Token')}
   Queries:
     $filter: createdDateTime gt @{variables('lastRunTime')} and status eq 'Active'
     $top: 100
   Note: Uses Purview Communication Compliance API, NOT Graph security/alerts_v2
         (see docs/communication-compliance-setup.md for API access configuration)

> ⚠️ **API Risk:** The `compliance.microsoft.com/api/SupervisoryReview/alerts` endpoint
> is undocumented and not officially supported by Microsoft. It may change or be removed
> without notice. As a fallback, consider using `Connect-IPPSSession` with
> `Get-SupervisoryReviewPolicyV2` cmdlets for programmatic access.

   Note: The $top=100 parameter prevents action execution limit errors when a
         large alert backlog exists (e.g., post-outage or first run). Remaining
         alerts are picked up in subsequent polling cycles.
   Note: The status filter excludes dismissed or resolved alerts so that only
         actionable items enter the supervision queue.

3. Get SupervisionConfig (all active rows)
   Cache outside loop to avoid N+1 queries (matches EscalationFlow pattern at step 2.1)

4. Apply to each: Alert
   4.1 Parse JSON - Extract alert details

   4.2 Condition: Is AI Agent Related?
       - Check if alert source contains 'CopilotStudio' or 'AgentBuilder'

   4.3 If Yes:
       4.3.1 HTTP - Get Agent Details
             URI: <agent metadata source — see note below>
              # NOTE: Power Automate has no single `get agent metadata` endpoint.
              # Recommended sources of agent zone/tier:
              #   (a) `agent-registry-automation` Dataverse table `fsi_agentinventory` —
              #       List rows: filter `fsi_agentid eq '<agent.id>'` to get fsi_zone.
              #   (b) `environment-lifecycle-management` `fsi_environment` zone classification.
              #   (c) Static mapping table maintained by the supervision team.
              # Use `Get rows` (Dataverse connector) to look up zone/tier; do not call
              # api.powerplatform.com directly without a documented endpoint.

       4.3.2 Look up matching config from cached SupervisionConfig
             Filter (in-memory): fsi_zone eq @{agent.zone} and fsi_tier eq @{agent.tier}

       4.3.3 Condition: Random sampling (Zone 1-2)
             - If Zone 3 OR rand(1, 101) <= reviewPercent
              # NOTE: Power Automate `rand(min, max)` upper bound is exclusive
              # (per Microsoft docs). Use `rand(1, 101)` to get inclusive 1..100,
              # otherwise reviewPercent=99 samples 100% (off-by-one).

       4.3.4 Condition: Duplicate check
              - Filter SupervisionQueue: fsi_sourceid eq @{alert.id}
              - If count > 0, skip creation

        4.3.5 Create SupervisionQueue row
             - Queue Number: Auto
             - Source Type: Communication Compliance
             - Source ID: @{alert.id}
             - Agent ID: @{agent.id}
             - Agent Name: @{agent.displayName}
             - Zone: @{agent.zone}
             - Tier: @{agent.tier}
             - Content Preview: @{if(empty(alert.content), '', substring(alert.content, 0, min(length(alert.content), 500)))}
             - Flagged Reason: @{alert.policyName}
             - State: Pending
             - Queued Date: @{utcNow()}
             - SLA Due: @{addHours(utcNow(), config.slaHours)}

5. Update lastRunTime in secure storage
```

### Connection References

| Connection | Type | Purpose |
|------------|------|---------|
| Dataverse | Premium | Create queue records |
| HTTP with Microsoft Entra ID (preauthorized) | Premium | Purview Communication Compliance API |
| Azure Key Vault | Premium | Store lastRunTime, credentials |

### Error Handling

- On HTTP failure: Log to SupervisionLog with action "IngestError" **and** send
  real-time notification (Teams/Email) to Queue Managers so that persistent API
  unavailability is detected within minutes rather than waiting for the daily SLA
  report to surface the volume drop
- On Dataverse failure: Retry 3 times, then alert Queue Manager
- All errors: Continue processing remaining alerts

---

## FSW-AssignmentFlow

Triggered when a new SupervisionQueue row is created. Assigns to appropriate supervisory principal.

### Trigger

**When a row is added (Dataverse)**
- Table: SupervisionQueue
- Scope: Organization

### Actions

```
1. Get SupervisionConfig
   Filter: fsi_zone eq @{triggerBody().zone} and fsi_tier eq @{triggerBody().tier}

2. Condition: Has Default Principal?

   2.1 If Yes:
       - Assigned Principal = config.defaultPrincipal

   2.2 If No:
       - Get available supervisors (custom logic or round-robin)
       - Assigned Principal = selected supervisor

3. Update SupervisionQueue
   - Assigned Principal: @{assignedPrincipal}
   - Owner: @{assignedPrincipal} (Dataverse Assign action — transfers record ownership
     from the service principal so User-level privileges grant the supervisor access)
   - State: Pending (unchanged — transitions to InReview when the supervisor opens the item; see note below)

4. Create SupervisionLog
   - Queue Item: @{triggerBody().id}
   - Action: Assigned
   - `fsi_actor@odata.bind`: "/systemusers(<service-principal-app-user-guid>)"    // resolve at flow design time; lookup column requires a valid systemuser GUID
   - Timestamp: @{utcNow()}
   - Details: Assigned to @{assignedPrincipal.fullname}

5. Send notification (Teams/Email)
   - To: Assigned Principal
   - Subject: New item requiring supervision review
   - Body: Agent @{agentName}, Flagged for @{flaggedReason}
   - Include: Deep link to queue item
```

### Error Handling

- On Dataverse failure (SupervisionLog creation at step 4): Retry 3 times, then send notification to Queue Managers — a missing audit log entry compromises the FINRA 3110 evidence trail
- On notification failure (step 5): Log to SupervisionLog with action "NotificationError" and continue — assignment is still valid even if notification fails
- All errors: Log error details to SupervisionLog for auditability

### Round-Robin Assignment Logic

For workload balancing when no default principal is configured:

```
1. Get all users with FSW Supervisor role

2. Get current queue counts per supervisor
   - Filter: fsi_state in (1, 2)
   - Group by: Assigned Principal

3. Select supervisor with lowest count

4. If tie, select randomly among tied supervisors
```

### Pending → InReview Transition

The AssignmentFlow leaves items in **Pending** state after assignment. The transition to **InReview** (fsi_state = 2) must be implemented via one of:

1. **Model-driven app business rule**: Set fsi_state to InReview when the supervisor opens the form (recommended — no additional flow required)
2. **Client-side JavaScript**: On form load, update state if current user matches Assigned Principal and state is Pending
3. **Additional flow**: Trigger on SupervisionQueue row update when a supervisor writes review notes or changes any review field

Without this transition, the EscalationFlow's filter on `fsi_state in (1, 2)` still captures these items, but the "My Queue" view filtering on InReview will not show newly assigned items until the state is updated.

---

## FSW-EscalationFlow

Scheduled flow that monitors SLA compliance and escalates overdue items.

### Trigger

**Recurrence**
- Frequency: Hour
- Interval: 1
- Time zone: UTC
- Concurrency Control: On (Degree of Parallelism: 1) — prevents double-escalation notifications if a run exceeds 1 hour

### Actions

```
1. List SupervisionQueue - Approaching SLA
   Filter: fsi_state in (1, 2)
           and fsi_sladue lt @{addHours(utcNow(), 2)}
           and fsi_sladue gt @{utcNow()}

   1.1 Apply to each: Send reminder
       - Teams notification to Assigned Principal
       - "Item @{queueNumber} SLA due in @{dateDiff} hours"

2. List SupervisionQueue - SLA Breached
   Filter: fsi_state in (1, 2)
           and fsi_sladue lt @{utcNow()}

   2.1 Get SupervisionConfig (all rows, cached outside loop)

   2.2 Apply to each: Check escalation threshold
       2.2.1 Look up config from cached SupervisionConfig

       2.2.2 Calculate hours since queued
             hoursSinceQueued = dateDiff('Hour', queuedDate, utcNow())

       2.2.3 Condition: hoursSinceQueued >= escalationHours?

             If Yes:
               - Update SupervisionQueue: State = Escalated
               - Create SupervisionLog: Action = Escalated
               - Reassign to config.escalationTo
               - Notify escalation recipient
               - Notify original assignee of escalation

             If No:
               - Send urgent reminder to Assigned Principal
               - Create SupervisionLog: Action = SLABreached

3. Generate daily SLA report
   - Count items by state
   - Calculate SLA compliance %
   - Send to Queue Managers
```

### Error Handling

- On Dataverse failure (SupervisionLog creation at steps 2.2.3): Retry 3 times, then send alert to Queue Managers — missing escalation audit entries compromise the FINRA 3110 evidence trail
- On notification failure: Log to SupervisionLog with action "NotificationError" and continue — the state change and audit log are the critical path
- On SLA report generation failure (step 3): Send error notification to Queue Managers so the daily compliance summary is not silently lost

### Escalation Notification Template

```
Subject: [ESCALATED] Supervision item requires immediate attention

Item: @{queueNumber}
Agent: @{agentName}
Zone: @{zone} | Tier: @{tier}
Flagged: @{flaggedReason}
Queued: @{queuedDate}
SLA Due: @{slaDue}
Original Assignee: @{originalAssignee}

This item has exceeded the escalation threshold and requires immediate review.

[Review Item] - Deep link
```

---

## FSW-ReviewComplete

Triggered when a supervisor completes a review (State changes to Approved/Rejected/Escalated).

### Trigger

**When a row is modified (Dataverse)**
- Table: SupervisionQueue
- Scope: Organization
- Filter: State has changed AND State in (Approved, Rejected, Escalated)

> **Guard against automation-initiated triggers:** The EscalationFlow (step 2.1.3) also sets State = Escalated during automated escalation. To prevent duplicate/conflicting audit log entries, Step 1 below must check whether the state change was initiated by a supervisor or by automation. Add a condition: if `triggerBody()?['_modifiedby_value']` equals the service principal used by EscalationFlow, skip logging and exit the flow — EscalationFlow already logs its own escalation action.

### Actions

```
1. Create SupervisionLog
   - Queue Item: @{triggerBody().id}
   - Action: Map reviewOutcome to action value (Approved=1→5, Rejected=2→6, Escalated=3→7 per dataverse-schema.md Action picklist)
   - `fsi_actor@odata.bind`: "/systemusers(@{triggerBody().reviewedBy.id})"   // requires reviewer Entra object ID resolved to systemuserid; do not pass display names to Lookup columns
             - `fsi_queueitem@odata.bind`: "/fsi_supervisionqueues(@{triggerBody().queueItemId})"    // lookup to the SupervisionQueue row
   - Timestamp: @{utcNow()}
   - Details: @{triggerBody().reviewNotes}

2. Condition: Outcome = Escalated?

   2.1 If Yes:
       - Get SupervisionConfig
       - Reassign to escalationTo
       - Reset SLA Due
       - Update State to Pending
       - Notify escalation recipient

   2.2 If No (Approved or Rejected):
       - Update State (already set by trigger)
       - Close workflow

3. Optional: Notify requester/stakeholders
   - If Rejected, may need follow-up action

4. Update metrics (increment counters for dashboard)
```

### Error Handling

- On Dataverse failure (SupervisionLog creation at step 1): Retry 3 times, then send alert to Queue Managers — a missing review-completion audit entry is a critical gap in the FINRA 3110 supervision evidence trail
- On reassignment failure (step 2.1): Log to SupervisionLog with action "ReassignmentError", notify Queue Managers, and leave item in current state for manual intervention
- On notification failure (step 3): Log to SupervisionLog with action "NotificationError" and continue — the audit log is the critical path

---

## Connection Security

### Service Principal Authentication

All flows should use a dedicated service principal:

1. Create app registration: `FSW-Automation-SP`
2. Grant API permissions:
   - Microsoft Graph: `User.Read.All`
   - Dataverse: `user_impersonation`
3. Assign directory role: **Compliance Administrator** via Entra ID > Enterprise applications > `FSW-Automation-SP` > Roles and administrators (this is an Entra ID directory role, not an API permission — see docs/communication-compliance-setup.md)
4. Create client secret, store in Key Vault
5. Use "HTTP with Microsoft Entra ID (preauthorized)" connector

### Least Privilege

| Flow | Required Permissions |
|------|---------------------|
| IngestFlaggedItems | Purview: Compliance Administrator, Graph: User.Read.All |
| AssignmentFlow | Dataverse: FSW Admin role |
| EscalationFlow | Dataverse: FSW Admin role |
| ReviewComplete | Dataverse: FSW Admin role |

---

## Environment Variables for Configurable Values

The following values are specified inline in the flow definitions above for clarity, but should be configured using **Power Platform environment variables** to support ALM promotion across dev/test/prod environments:

| Variable Name | Flow | Default | Description |
|--------------|------|---------|-------------|
| `FSW_IngestPollingMinutes` | IngestFlaggedItems | 15 | Polling interval for Communication Compliance API |
| `FSW_EscalationCheckHours` | EscalationFlow | 1 | Interval for escalation threshold checks |
| `FSW_PowerPlatformApiBase` | IngestFlaggedItems | `https://api.powerplatform.com` | Power Platform API base URL |

When deploying to a new environment, create these environment variables in the Power Platform admin center or include them in the solution's `environmentvariabledefinition` table. Flows should reference these variables instead of hardcoded values.

---

## Testing Checklist

- [ ] IngestFlow creates queue items from test alerts
- [ ] AssignmentFlow routes to correct supervisor by zone/tier
- [ ] EscalationFlow sends reminders at correct thresholds
- [ ] EscalationFlow escalates after configured hours
- [ ] ReviewComplete logs all outcomes correctly
- [ ] Notifications delivered to correct recipients
- [ ] SLA calculations correct across time zones
