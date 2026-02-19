# Flow Configuration

Power Automate flow specifications for the FINRA Supervision Workflow solution.

## Flow Overview

| Flow | Trigger | Purpose |
|------|---------|---------|
| FSW-IngestFlaggedItems | Scheduled (15 min) | Poll Communication Compliance for flagged items |
| FSW-AssignmentFlow | Dataverse row created | Route items to supervisory principals |
| FSW-EscalationFlow | Scheduled (hourly) | Monitor SLA and escalate overdue items |
| FSW-ReviewComplete | Dataverse row updated | Log review completion, notify stakeholders (Approved/Rejected only) |

---

## FSW-IngestFlaggedItems

Polls Communication Compliance API for new flagged items and creates SupervisionQueue records.

### Trigger

**Recurrence**
- Frequency: Minute
- Interval: 15
- Time zone: UTC

### Actions

```
1. Initialize variable: lastRunTime (from secure storage)

2. HTTP - Get Communication Compliance Policy Matches
   Method: GET
   URI: https://compliance.microsoft.com/api/SupervisoryReview/Alerts
   Headers:
     Authorization: Bearer @{outputs('Get_Token')}
   Queries:
     $filter: CreatedDate gt @{variables('lastRunTime')}
   Note: Do NOT use the Graph API endpoint
         https://graph.microsoft.com/v1.0/security/cases/ediscoveryCases
         — that is the eDiscovery API, not Communication Compliance.
         The security/alerts_v2 endpoint serves Microsoft Defender alerts,
         also not Communication Compliance.
   Alternative - PowerShell connector:
     Cmdlet: Get-ComplianceCase -CaseType SupervisoryReview

3. Apply to each: Alert
   3.1 Parse JSON - Extract alert details

   3.2 Condition: Is AI Agent Related?
       - Check if alert source contains 'CopilotStudio' or 'AgentBuilder'

   3.3 If Yes:
       3.3.1 HTTP - Get Agent Details
             URI: https://api.powerplatform.com/...

       3.3.2 Get SupervisionConfig
             Filter: Zone eq @{agent.zone} and Tier eq @{agent.tier}

       3.3.3 Condition: Random sampling (Zone 1-2)
             - If Zone 3 OR random() < reviewPercent/100

       3.3.4 Create SupervisionQueue row
             - Queue Number: Auto
             - Source Type: Communication Compliance
             - Source ID: @{alert.id}
             - Agent ID: @{agent.id}
             - Agent Name: @{agent.displayName}
             - Zone: @{agent.zone}
             - Tier: @{agent.tier}
             - Content Preview: @{substring(alert.content, 0, 500)}
             - Flagged Reason: @{alert.policyName}
             - State: Pending
             - Queued Date: @{utcNow()}
             - SLA Due: @{addHours(utcNow(), config.slaHours)}

4. Update lastRunTime in secure storage
```

### Connection References

| Connection | Type | Purpose |
|------------|------|---------|
| Dataverse | Premium | Create queue records |
| HTTP with Azure AD | Premium | Communication Compliance API |
| Azure Key Vault | Premium | Store lastRunTime, credentials |

### Error Handling

- On HTTP failure: Log to SupervisionLog with action "IngestError"
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
   Filter: Zone eq @{triggerBody().zone} and Tier eq @{triggerBody().tier}

2. Condition: Has Default Principal?

   2.1 If Yes:
       - Assigned Principal = config.defaultPrincipal

   2.2 If No:
       - Get available supervisors (custom logic or round-robin)
       - Assigned Principal = selected supervisor

3. Update SupervisionQueue
   - Assigned Principal: @{assignedPrincipal}
   - State: Pending (unchanged)

4. Create SupervisionLog
   - Queue Item: @{triggerBody().id}
   - Action: Assigned
   - Actor: System
   - Timestamp: @{utcNow()}
   - Details: Assigned to @{assignedPrincipal.fullname}

5. Send notification (Teams/Email)
   - To: Assigned Principal
   - Subject: New item requiring supervision review
   - Body: Agent @{agentName}, Flagged for @{flaggedReason}
   - Include: Deep link to queue item
```

### Round-Robin Assignment Logic

For workload balancing when no default principal is configured:

```
1. Get all users with FSW Supervisor role

2. Get current queue counts per supervisor
   - Filter: State in (Pending, In Review)
   - Group by: Assigned Principal

3. Select supervisor with lowest count

4. If tie, select randomly among tied supervisors
```

---

## FSW-EscalationFlow

Scheduled flow that monitors SLA compliance and escalates overdue items.

### Trigger

**Recurrence**
- Frequency: Hour
- Interval: 1
- Time zone: UTC

### Actions

```
1. List SupervisionQueue - Approaching SLA
   Filter: State in (Pending, In Review)
           and SLA Due lt @{addHours(utcNow(), 2)}
           and SLA Due gt @{utcNow()}

   1.1 Apply to each: Send reminder
       - Teams notification to Assigned Principal
       - "Item @{queueNumber} SLA due in @{dateDiff} hours"

2. List SupervisionQueue - SLA Breached
   Filter: State in (Pending, In Review)
           and State ne Escalated
           and SLA Due lt @{utcNow()}

   2.1 Apply to each: Check escalation threshold
       2.1.1 Get SupervisionConfig

       2.1.2 Calculate hours since queued
             hoursSinceQueued = dateDiff(queuedDate, utcNow(), 'Hour')

       2.1.3 Condition: hoursSinceQueued >= escalationHours?

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

Triggered when a supervisor completes a review (State changes to Approved or Rejected).

> **Note:** This flow does NOT trigger on State = Escalated. Escalation is handled
> exclusively by FSW-EscalationFlow to prevent infinite escalation cycles. If both
> flows acted on escalated items, a loop could occur: EscalationFlow sets
> State = Escalated → ReviewComplete resets State = Pending → EscalationFlow
> re-escalates the same item.

### Trigger

**When a row is modified (Dataverse)**
- Table: SupervisionQueue
- Scope: Organization
- Filter: State has changed AND State in (Approved, Rejected)

### Actions

```
1. Create SupervisionLog
   - Queue Item: @{triggerBody().id}
   - Action: @{triggerBody().reviewOutcome} (mapped to action choice)
   - Actor: @{triggerBody().reviewedBy.fullname}
   - Timestamp: @{utcNow()}
   - Details: @{triggerBody().reviewNotes}

2. Update State (already set by trigger)
   - Close workflow

3. Optional: Notify requester/stakeholders
   - If Rejected, may need follow-up action

4. Update metrics (increment counters for dashboard)
```

---

## Connection Security

### Service Principal Authentication

All flows should use a dedicated service principal:

1. Create app registration: `FSW-Automation-SP`
2. Grant API permissions:
   - Purview: Compliance Administrator role (for Communication Compliance access)
   - Dataverse: `user_impersonation`
3. Create client secret, store in Key Vault
4. Use "HTTP with Azure AD" connector

### Least Privilege

| Flow | Required Permissions |
|------|---------------------|
| IngestFlaggedItems | Purview: Compliance Administrator role |
| AssignmentFlow | Dataverse: FSW Admin role |
| EscalationFlow | Dataverse: FSW Admin role |
| ReviewComplete | Dataverse: FSW Admin role |

---

## Testing Checklist

- [ ] IngestFlow creates queue items from test alerts
- [ ] AssignmentFlow routes to correct supervisor by zone/tier
- [ ] EscalationFlow sends reminders at correct thresholds
- [ ] EscalationFlow escalates after configured hours
- [ ] ReviewComplete logs all outcomes correctly
- [ ] Notifications delivered to correct recipients
- [ ] SLA calculations correct across time zones
