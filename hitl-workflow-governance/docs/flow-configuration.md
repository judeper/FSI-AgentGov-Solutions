# Flow Configuration Guide

## Overview

This guide provides step-by-step instructions for manually building the HITL Workflow Governance Power Automate flows in Power Automate designer.

> **Important:** These are manual build instructions — not exported flow JSON. Build each flow directly in the Power Automate designer following the steps below.

**Flows to Build:**
1. HITL-Scanner (Scheduled Cloud Flow)
2. HITL-Violation-Alert (Automated Cloud Flow)
3. HITL-Exception-Approval (Automated Cloud Flow)

**Prerequisites:**
- Power Automate Premium license
- Power Platform Admin role in target environment
- Access to Dataverse and Teams
- Connection references configured (see [prerequisites](prerequisites.md))
- `Test-HitlWorkflowCompliance.ps1` imported to Azure Automation (or available for local execution)

---

## Flow 1: HITL-Scanner

**Type:** Scheduled Cloud Flow
**Trigger:** Recurrence (Daily at 06:00 UTC)
**Purpose:** Execute HITL checkpoint validation scan across Power Platform environments, detect agents missing required Human in the Loop checkpoints, and persist results to Dataverse

### Build Steps

1. **Create New Flow**
   - Power Automate > Cloud Flows > Scheduled Cloud Flow
   - Flow name: `HITL-Scanner`
   - Recurrence: Daily at 06:00 UTC

2. **Initialize Variables**
   - `timestamp`: Expression `utcNow()`
   - `runId`: Expression `guid()`
   - `tenantId`: Environment variable `fsi_HWG_TenantId`
   - `dataverseUrl`: Environment variable `fsi_HWG_DataverseUrl`
   - `scanFrequencyHours`: Environment variable `fsi_HWG_ScanFrequencyHours` (default: 24)
   - `dryRunMode`: Environment variable `fsi_HWG_DryRunMode` (default: `"true"`)
   - `alertSeverityThreshold`: Environment variable `fsi_HWG_AlertSeverityThreshold` (default: `"High"`)

3. **Execute Azure Automation Runbook**
   - Action: "Create job" (Azure Automation)
   - Runbook: `Test-HitlWorkflowCompliance`
   - Parameters:
     - `TenantId`: Variable `tenantId`
     - `DataverseUrl`: Variable `dataverseUrl`
     - `DryRun`: Variable `dryRunMode`
   - Wait for completion: Yes

4. **Wait for Runbook Completion**
   - Action: "Get job output" (Azure Automation)
   - Poll until job status is `Completed` or `Failed`
   - **Timeout:** Configure 30-minute timeout (PT30M)

5. **Get Runbook Output**
   - Action: "Get job output" (Azure Automation)
   - Parse output as JSON

6. **Parse JSON Output**
   - Action: "Parse JSON"
   - Schema:
     ```json
     {
       "type": "object",
       "properties": {
         "RunId": { "type": "string" },
         "Timestamp": { "type": "string" },
         "OverallStatus": { "type": "string" },
         "TotalAgents": { "type": "integer" },
         "TotalFlows": { "type": "integer" },
         "CheckpointsFound": { "type": "integer" },
         "CheckpointsMissing": { "type": "integer" },
         "Violations": {
           "type": "array",
           "items": {
             "type": "object",
             "properties": {
               "AgentName": { "type": "string" },
               "AgentId": { "type": "string" },
               "EnvironmentName": { "type": "string" },
               "Zone": { "type": "string" },
               "ViolationType": { "type": "string" },
               "ActionType": { "type": "string" },
               "Severity": { "type": "string" },
               "RegulatoryContext": { "type": "string" }
             }
           }
         },
         "AlertRequired": { "type": "boolean" },
         "AlertSeverity": { "type": "string" }
       }
     }
     ```

7. **Write Scan Run Record**
   - Action: "Create a new record" (Dataverse)
   - Table: `fsi_HitlScanRun`
   - Fields:
     - `fsi_name`: Expression `concat('HITL-Run-', variables('runId'))`
     - `fsi_runid`: Variable `runId`
     - `fsi_scantime`: Variable `timestamp`
     - `fsi_overallstatus`: Parsed `OverallStatus`
     - `fsi_totalagents`: Parsed `TotalAgents`
     - `fsi_totalflows`: Parsed `TotalFlows`
     - `fsi_checkpointsfound`: Parsed `CheckpointsFound`
     - `fsi_checkpointsmissing`: Parsed `CheckpointsMissing`
     - `fsi_violationcount`: Length of `Violations` array
     - `fsi_summaryjson`: Full JSON output

8. **For Each Violation**
   - Loop through parsed `Violations` array
   - Action: "Create a new record" (Dataverse)
   - Table: `fsi_HitlCheckpointResult`
   - Fields:
     - `fsi_name`: Expression `take(concat(items('Apply_to_each')?['AgentName'], ' - ', items('Apply_to_each')?['ViolationType']), 200)`
     - `fsi_agentid`: `AgentId`
     - `fsi_agentname`: `AgentName`
     - `fsi_environmentname`: `EnvironmentName`
     - `fsi_zone`: `Zone` (mapped to option set value)
     - `fsi_violationtype`: `ViolationType` (string)
     - `fsi_severity`: `Severity` (string: `Critical`, `High`, `Medium`, `Warning`)
     - `fsi_regulatorycontext`: `RegulatoryContext`
     - `fsi_detectedat`: Variable `timestamp`
     - `fsi_runid`: Variable `runId`

> **Note:** `fsi_severity` is a string column in this schema (not a picklist). Filter and bind it as text. `fsi_violationtype` is also a string. There is no `fsi_actiontype` or `fsi_details` column on `fsi_HitlCheckpointResult` — do not bind them.

9. **Check Alert Threshold**
   - **Condition:** `AlertRequired` equals `true`
   - **If true:** Continue to step 10
   - **If false:** End flow

10. **Send Teams Alert**
    - Action: "Post an Adaptive Card to a Teams Channel"
    - Channel: Use `fsi_HWG_TeamsGroupId` and `fsi_HWG_TeamsChannelId`
    - Card content: Use `templates/adaptive-card-hitl-alert.json` with scan summary data
    - Populate template variables from parsed JSON output

**Trigger Configuration:**
- Frequency: Hour
- Interval: Value of `fsi_HWG_ScanFrequencyHours` (default: 24, i.e., daily)
- Time zone: UTC
- Start time: 06:00

---

## Flow 2: HITL-Violation-Alert

**Type:** Automated Cloud Flow
**Trigger:** When a record is created (Dataverse)
**Purpose:** Send immediate notification when Critical or High severity HITL violations are detected, post adaptive card to Teams, and create Planner remediation task

### Build Steps

1. **Create New Flow**
   - Power Automate > Cloud Flows > Automated Cloud Flow
   - Flow name: `HITL-Violation-Alert`
   - Trigger: "When a row is added, modified or deleted"

2. **Configure Trigger**
   - Change type: Added
   - Table name: `fsi_HitlCheckpointResult`
   - Scope: Organization
   - **Filter rows:** `fsi_severity eq 'Critical' or fsi_severity eq 'High'`

   > **Note:** Adjust option set values to match your deployed schema. The filter restricts the trigger to Critical and High severity violations only.

3. **Get Violation Record**
   - Action: "Get a row by ID" (Dataverse)
   - Table: `fsi_HitlCheckpointResult`
   - Row ID: Trigger output `fsi_hitlcheckpointresultid`

4. **Format Adaptive Card**
   - Action: "Compose"
   - Use the adaptive card template from `templates/adaptive-card-hitl-alert.json`
   - Replace template variables with violation record fields:
     - `${AgentName}`: `fsi_agentname`
     - `${EnvironmentName}`: `fsi_environmentname`
     - `${Zone}`: `fsi_zone` (display value)
     - `${ViolationType}`: `fsi_violationtype` (display value)
     - `${Severity}`: `fsi_severity` (display value)
     - `${RegulatoryContext}`: `fsi_regulatorycontext`
     - `${DetectedAt}`: `fsi_detectedat`

5. **Post Adaptive Card to Teams**
   - Action: "Post an Adaptive Card in a chat or channel"
   - Post as: Flow bot
   - Post in: Channel
   - Team: Environment variable `fsi_HWG_TeamsGroupId`
   - Channel: Environment variable `fsi_HWG_TeamsChannelId`
   - Adaptive Card: Output from Compose step

6. **Create Planner Remediation Task**
   - Action: "Create a task" (Planner)
   - Group ID: Environment variable `fsi_HWG_TeamsGroupId`
   - Plan ID: Environment variable `fsi_HWG_PlannerPlanId`
   - Title: Expression `concat('HITL Violation: ', triggerOutputs()?['body/fsi_agentname'], ' - ', triggerOutputs()?['body/fsi_violationtype'])`
   - Due date: Expression based on zone SLA:
     - Zone 3: `addHours(utcNow(), 4)`
     - Zone 2: `addHours(utcNow(), 24)`
     - Zone 1: `addHours(utcNow(), 72)`
   - Description: Include violation details, agent name, environment, zone, and link to Dataverse record
   - Assigned to: Compliance team (from environment variable `fsi_HWG_ComplianceApproverEmail`)

7. **Update Violation Record**
   - Action: "Update a row" (Dataverse)
   - Table: `fsi_HitlCheckpointResult`
   - Set `fsi_alertsentat` to `utcNow()`

**Trigger Configuration:**
```
Table: fsi_HitlCheckpointResult
Change type: Added
Scope: Organization
Filter: fsi_severity eq 'Critical' or fsi_severity eq 'High'
```

---

## Flow 3: HITL-Exception-Approval

**Type:** Automated Cloud Flow
**Trigger:** When a record is created (Dataverse)
**Purpose:** Route HITL checkpoint exception requests to compliance team for approval, update Dataverse on approval or rejection, and notify stakeholders

### Build Steps

1. **Create New Flow**
   - Power Automate > Cloud Flows > Automated Cloud Flow
   - Flow name: `HITL-Exception-Approval`
   - Trigger: "When a row is added, modified or deleted"

2. **Configure Trigger**
   - Change type: Added
   - Table name: `fsi_HitlCheckpointException`
   - Scope: Organization

3. **Get Exception Record**
   - Action: "Get a row by ID" (Dataverse)
   - Table: `fsi_HitlCheckpointException`
   - Row ID: Trigger output `fsi_hitlcheckpointexceptionid`

4. **Send Approval Request**
   - Action: "Start and wait for an approval"
   - Approval type: Approve/Reject — First to respond
   - Title: Expression `concat('HITL Exception: ', triggerOutputs()?['body/fsi_agentname'], ' (', triggerOutputs()?['body/fsi_environmentname'], ')')`
   - Assigned to: Environment variable `fsi_HWG_ComplianceApproverEmail`
   - Details:
     ```
     Agent: [fsi_agentname]
     Environment: [fsi_environmentname]
     Zone: [fsi_zone]
     Violation Type: [fsi_violationtype]
     Business Justification: [fsi_justification]
     Requested By: [fsi_requestedby]
     Requested At: [fsi_requestedat]
     ```
   - **Timeout:** Configure 14-day timeout (ISO 8601: `P14D`)

5. **Handle Timeout**
   - Add a parallel branch with **Run after** > **Has timed out**
   - Action: "Update a row" (Dataverse)
     - Table: `fsi_HitlCheckpointException`
     - `fsi_isactive`: `false`
     - `fsi_approvalnotes`: `"Timed out: no approver response within 14 days"`
   - Action: "Send an email (V2)" to requestor notifying of timeout

6. **Process Approval Response**

   **If Approved:**
   - Action: "Update a row" (Dataverse)
   - Table: `fsi_HitlCheckpointException`
   - Fields:
     - `fsi_isactive`: `true`
     - `fsi_approvedby`: Approver email from approval response
     - `fsi_approvedat`: Expression `utcNow()`
     - `fsi_approvalnotes`: Approver comments from approval response
   - Action: "Send an email (V2)" to requestor: "HITL checkpoint exception approved"
   - Action: "Post message in a chat or channel" to compliance channel with approval summary

   **If Rejected:**
   - Action: "Update a row" (Dataverse)
   - Table: `fsi_HitlCheckpointException`
   - Fields:
     - `fsi_isactive`: `false`
     - `fsi_approvedby`: Responder email (for audit trail)
     - `fsi_approvalnotes`: Responder comments (rejection reason)
   - Action: "Send an email (V2)" to requestor: "HITL checkpoint exception rejected" with reason
   - Action: "Post message in a chat or channel" to compliance channel with rejection summary

**Trigger Configuration:**
```
Table: fsi_HitlCheckpointException
Change type: Added
Scope: Organization
```

---

## Error Handling

All three flows make API calls (Azure Automation, Dataverse, Teams, Planner) that can fail transiently. Apply these patterns to each flow.

### Scope-Based Try/Catch Pattern

Wrap the main logic of each flow in a **Scope** action (acts as a "try" block), then add parallel branches for error handling:

1. **Scope: Main Logic** — Contains all flow steps
2. **Scope: Catch** — Configure **Run after** to execute only when Main Logic has **Failed**, **Timed out**, or been **Cancelled**
   - Log error details to `fsi_HitlScanRun` (for HITL-Scanner) or a dedicated error log
   - Send Teams alert with failure context (flow name, error message, run ID)
   - Set appropriate status so the issue is visible in Dataverse

### Run-After Configuration

For critical actions (Azure Automation jobs, Dataverse writes, Teams posts), configure **Run after** settings:

- **Is successful** — Continue normal flow
- **Has failed** — Branch to error handling (log error, send alert, terminate gracefully)
- **Has timed out** — Treat as transient failure, log and alert

### Retry Policies

For HTTP actions (Azure Automation job creation, runbook output retrieval):

- **Policy:** Exponential interval
- **Count:** 3 retries
- **Interval:** PT10S (10 seconds initial)
- **Maximum interval:** PT1M (1 minute)

For Dataverse connector actions, the connector applies default retry logic automatically. For Teams posting, configure a fixed retry of 2 attempts with PT5S interval.

---

## Connection References

Before deploying flows, create connection references in Power Automate:

| Connection Reference | API | Type |
|----------------------|-----|------|
| `fsi_cr_dataverse_hitlworkflowgovernance` | Dataverse | Service Principal or User |
| `fsi_cr_teams_hitlworkflowgovernance` | Microsoft Teams | Current User |
| `fsi_cr_office365_hitlworkflowgovernance` | Office 365 Outlook | Current User |
| `fsi_cr_azureautomation_hitlworkflowgovernance` | Azure Automation | Service Principal |
| `fsi_cr_approvals_hitlworkflowgovernance` | Approvals | Current User |
| `fsi_cr_planner_hitlworkflowgovernance` | Planner | Current User |

**Steps to Create Connection Reference:**
1. Power Automate > Solutions > HITL Workflow Governance
2. New > Connection Reference
3. Name: `fsi_cr_dataverse_hitlworkflowgovernance`
4. Connector: Dataverse
5. Create connection > Select authentication
6. Save

Repeat for Teams, Office 365 Outlook, Azure Automation, Approvals, and Planner connectors.

---

## Deployment Validation

After building all flows:

1. **Scanner Flow Test**
   - Run HITL-Scanner manually > Should succeed
   - Check `fsi_HitlScanRun` table for scan run record
   - Check `fsi_HitlCheckpointResult` table for violation records (if any)

2. **Violation Alert Test**
   - Create a test record in `fsi_HitlCheckpointResult` with severity Critical
   - Verify HITL-Violation-Alert flow triggered
   - Verify Teams adaptive card posted to configured channel
   - Verify Planner task created with correct SLA due date

3. **Exception Approval Test**
   - Create a test record in `fsi_HitlCheckpointException`
   - Verify HITL-Exception-Approval flow triggered
   - Verify approval request sent to compliance approver
   - Approve > Verify `fsi_isactive` set to `true`
   - Create another test > Reject > Verify `fsi_isactive` set to `false` with rejection notes

4. **End-to-End Flow**
   - Run scan > Violations detected > Alert sent > Exception submitted > Approved > Exception active for future scans

---

## Next Steps

After completing flow deployment:
1. Configure environment variables (see main deployment guide in README.md)
2. Set `fsi_HWG_DryRunMode` to `"false"` when ready for production
3. Enable all three flows in Power Automate
4. Monitor HITL-Scanner flow runs for scan results
5. Train compliance team on exception approval workflow

For comprehensive operational guidance, see the main [README.md](../README.md).
