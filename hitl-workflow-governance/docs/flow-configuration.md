# Flow Configuration Guide

## Overview

This guide provides step-by-step instructions for manually building the HITL Workflow Governance Power Automate flows in Power Automate designer.

> **Important:** These are manual build instructions — not exported flow JSON. Build each flow directly in the Power Automate designer following the steps below.

**Flows to Build:**
1. HITL-Scanner (Scheduled Cloud Flow)
2. HITL-Violation-Alert (Automated Cloud Flow)
3. HITL-Exception-Approval (Automated Cloud Flow)

**Prerequisites:**
- Power Automate license that covers Dataverse and Azure Automation connector usage in your tenant. The Human in the Loop, Approvals, Teams, and Office 365 Outlook connectors are documented as Standard connectors.
- Power Platform Admin role in the target environment
- Access to Dataverse, Azure Automation, Microsoft Teams, Planner, Office 365 Outlook, and Approvals connectors
- Connection references configured (see [Connection References](#connection-references))
- `Start-HitlValidationRunbook.ps1` imported to Azure Automation as the runbook entrypoint

---

## Flow 1: HITL-Scanner

**Type:** Scheduled Cloud Flow
**Trigger:** Recurrence (Daily at 06:00 UTC)
**Purpose:** Execute HITL checkpoint validation across Power Platform environments, detect agents missing required Human in the Loop checkpoints, and persist results to Dataverse.

### Build Steps

1. **Create New Flow**
   - Power Automate > Cloud Flows > Scheduled Cloud Flow
   - Flow name: `HITL-Scanner`
   - Recurrence: Daily at 06:00 UTC

2. **Initialize Variables**
   - `timestamp`: Expression `utcNow()`
   - `runId`: Expression `guid()`
   - `tenantId`: Secure flow configuration or Azure Automation variable for the Microsoft Entra tenant ID
   - `clientId`: Certificate-backed app registration client ID or managed identity client ID used by the runbook
   - `certificateThumbprint`: Certificate thumbprint available to the Automation account
   - `dataverseUrl`: Target Dataverse environment URL

   > The deployment script provisions operational Dataverse variables such as `fsi_HWG_GracePeriodHours`, `fsi_HWG_IncludeSandbox`, and `fsi_HWG_IncludeDrafts`. It does **not** create `fsi_HWG_TenantId`, `fsi_HWG_DataverseUrl`, `fsi_HWG_DryRunMode`, Teams, Planner, or approver variables. Store those flow-only settings in secure flow configuration, Azure Automation assets, or your tenant's approved secretless configuration pattern.

3. **Execute Azure Automation Runbook**
   - Action: **Create job** (Azure Automation)
   - Runbook: `Start-HitlValidationRunbook`
   - Parameters:
     - `TenantId`: variable `tenantId`
     - `ClientId`: variable `clientId`
     - `CertificateThumbprint`: variable `certificateThumbprint`
     - `DataverseUrl`: variable `dataverseUrl`
     - `GracePeriodHours`: Dataverse environment variable `fsi_HWG_GracePeriodHours` or default `72`
     - `IncludeSandbox`: Dataverse environment variable `fsi_HWG_IncludeSandbox`
     - `IncludeDrafts`: Dataverse environment variable `fsi_HWG_IncludeDrafts`

4. **Wait for Runbook Completion**
   - Action: **Get job output** (Azure Automation)
   - Poll until job status is `Completed` or `Failed`
   - Timeout: configure 30-minute timeout (`PT30M`)

5. **Parse JSON Output**
   - Action: **Parse JSON**
   - Content: runbook job output
   - Schema:
     ```json
     {
       "type": "object",
       "properties": {
         "RunType": { "type": "string" },
         "Timestamp": { "type": "string" },
         "TotalAgents": { "type": "integer" },
         "TotalEnvironments": { "type": "integer" },
         "TotalFlows": { "type": "integer" },
         "OverallStatus": { "type": "string" },
         "Reason": { "type": "string" },
         "Controls": { "type": "array", "items": { "type": "string" } },
         "ZoneSummary": { "type": "object" },
         "Violations": {
           "type": "array",
           "items": {
             "type": "object",
             "properties": {
               "AgentId": { "type": "string" },
               "AgentName": { "type": "string" },
               "EnvironmentGuid": { "type": "string" },
               "EnvironmentName": { "type": "string" },
               "Zone": { "type": "string" },
               "FlowName": { "type": "string" },
               "FlowId": { "type": "string" },
               "CheckpointType": { "type": "string" },
               "ViolationType": { "type": "string" },
               "Severity": { "type": "string" },
               "Details": { "type": "string" },
               "RegulatoryContext": { "type": "string" }
             }
           }
         },
         "Drift": { "type": "object" },
         "AlertRequired": { "type": "boolean" },
         "AlertSeverity": { "type": "string" }
       }
     }
     ```

6. **Write Scan Run Record**
   - Action: **Create a new row** (Dataverse)
   - Table: `fsi_HitlScanRun`
   - Fields:
     - `fsi_name`: Expression `concat('HITL-Run-', variables('runId'))`
     - `fsi_runid`: variable `runId`
     - `fsi_scantime`: parsed `Timestamp` or variable `timestamp`
     - `fsi_totalagents`: parsed `TotalAgents`
     - `fsi_totalflows`: parsed `TotalFlows`
     - `fsi_checkpointsfound`: total checkpoints found from `ZoneSummary` when available; otherwise `0`
     - `fsi_checkpointsmissing`: count of `Violations` where `ViolationType` equals `MissingHitlCheckpoint`
     - `fsi_violationcount`: length of `Violations` array
     - `fsi_overallstatus`: parsed `OverallStatus`
     - `fsi_summaryjson`: full JSON output

7. **For Each Violation**
   - Loop through parsed `Violations` array
   - Action: **Create a new row** (Dataverse)
   - Table: `fsi_HitlCheckpointResult`
   - Required fields:
     - `fsi_name`: Expression `take(concat(items('Apply_to_each')?['AgentName'], ' - ', items('Apply_to_each')?['ViolationType']), 200)`
     - `fsi_environmentguid`: `EnvironmentGuid`
     - `fsi_environmentname`: `EnvironmentName`
     - `fsi_zone`: map `Zone1` = `1`, `Zone2` = `2`, `Zone3` = `3`, unknown = `0`
     - `fsi_agentid`: `AgentId`
     - `fsi_agentname`: `AgentName`
     - `fsi_flowname`: `FlowName`
     - `fsi_flowid`: `FlowId`
     - `fsi_checkpointtype`: map `RequestForInformation` = `100000000`, `MultistageApproval` = `100000001`, `CustomHitl` = `100000002`, `AdvancedApprovalsGeneric` = `100000003`, unknown/missing = `100000004` (`NotApplicable`)
     - `fsi_checkpointstatus`: use `100000001` (`Missing`) for `MissingHitlCheckpoint`; otherwise use `100000002` (`Partial`)
     - `fsi_hashitlcheckpoint`: `false` for `MissingHitlCheckpoint`; otherwise `true`
     - `fsi_violationstatus`: `100000000` (`Open`)
     - `fsi_violationtype`: `ViolationType`
     - `fsi_severity`: `Severity` (string: `Critical`, `High`, `Medium`, `Warning`)
     - `fsi_regulatorycontext`: `RegulatoryContext`
     - `fsi_detectedat`: parsed `Timestamp` or variable `timestamp`
     - `fsi_runid`: variable `runId`

   > `fsi_severity` and `fsi_violationtype` are string columns. Do not bind non-existent `fsi_actiontype` or `fsi_details` columns.

8. **Check Alert Threshold**
   - Condition: `AlertRequired` equals `true`
   - If true: continue to Flow 2 pattern or send a Teams alert directly
   - If false: end flow

---

## Flow 2: HITL-Violation-Alert

**Type:** Automated Cloud Flow
**Trigger:** When a row is added (Dataverse)
**Purpose:** Send immediate notification when Critical or High severity HITL violations are detected, post an adaptive card to Teams, and create a Planner remediation task.

### Build Steps

1. **Create New Flow**
   - Flow name: `HITL-Violation-Alert`
   - Trigger: **When a row is added, modified or deleted**

2. **Configure Trigger**
   - Change type: Added
   - Table name: `fsi_HitlCheckpointResult`
   - Scope: Organization
   - Filter rows: `fsi_severity eq 'Critical' or fsi_severity eq 'High'`

3. **Get Violation Record**
   - Action: **Get a row by ID** (Dataverse)
   - Table: `fsi_HitlCheckpointResult`
   - Row ID: trigger output `fsi_hitlcheckpointresultid`

4. **Format Adaptive Card**
   - Action: **Compose**
   - Use `templates/adaptive-card-hitl-alert.json`
   - Replace template variables with:
     - `${AgentName}`: `fsi_agentname`
     - `${EnvironmentName}`: `fsi_environmentname`
     - `${Zone}`: formatted `fsi_zone`
     - `${ViolationType}`: `fsi_violationtype`
     - `${Severity}`: `fsi_severity`
     - `${RegulatoryContext}`: `fsi_regulatorycontext`
     - `${DetectedAt}`: `fsi_detectedat`

   The template targets Adaptive Cards schema `1.5`, which aligns with current Teams Universal Actions host guidance. It intentionally uses `Action.OpenUrl`; add `Action.Execute` only if a bot invoke handler and fallback path are implemented.

5. **Post Adaptive Card to Teams**
   - Action: **Post an Adaptive Card in a chat or channel**
   - Post as: Flow bot
   - Post in: Channel
   - Team and Channel: values from secure flow configuration or connection setup

6. **Create Planner Remediation Task**
   - Action: **Create a task** (Planner)
   - Group ID / Plan ID: values from secure flow configuration
   - Title: `concat('HITL Violation: ', triggerOutputs()?['body/fsi_agentname'], ' - ', triggerOutputs()?['body/fsi_violationtype'])`
   - Due date by zone: Zone 3 = `addHours(utcNow(), 4)`, Zone 2 = `addHours(utcNow(), 24)`, Zone 1 = `addHours(utcNow(), 72)`
   - Assigned to: compliance team owner

7. **Update Violation Record**
   - Action: **Update a row** (Dataverse)
   - Table: `fsi_HitlCheckpointResult`
   - Set `fsi_alertsentat` to `utcNow()`

---

## Flow 3: HITL-Exception-Approval

**Type:** Automated Cloud Flow
**Trigger:** When a row is added (Dataverse)
**Purpose:** Route HITL checkpoint exception requests to compliance reviewers, update Dataverse on approval/rejection/timeout, and notify stakeholders.

### Request Record Requirements

Before this flow starts, create the exception row with these fields:

- `fsi_environmentguid`, `fsi_agentid`, and optionally `fsi_flowname`
- `fsi_zone`
- `fsi_exceptionscope`
- `fsi_justification`
- `fsi_requestedby`
- `fsi_requestedat`
- `fsi_approvalstatus`: `Pending`
- `fsi_isactive`: `false` until approved

`fsi_approvedby` and `fsi_approvedat` are populated by the approval response.

### Build Steps

1. **Create New Flow**
   - Flow name: `HITL-Exception-Approval`
   - Trigger: **When a row is added, modified or deleted**

2. **Configure Trigger**
   - Change type: Added
   - Table name: `fsi_HitlCheckpointException`
   - Scope: Organization
   - Filter rows: `fsi_approvalstatus eq 'Pending' and fsi_isactive eq false`

3. **Get Exception Record**
   - Action: **Get a row by ID** (Dataverse)
   - Table: `fsi_HitlCheckpointException`
   - Row ID: trigger output `fsi_hitlcheckpointexceptionid`

4. **Send Approval Request**
   - Action: **Start and wait for an approval** (Approvals connector)
   - Approval type: Approve/Reject — First to respond, or another documented approval type if your supervisory process requires it
   - Title: `concat('HITL Exception: ', triggerOutputs()?['body/fsi_agentid'], ' (', triggerOutputs()?['body/fsi_environmentguid'], ')')`
   - Assigned to: compliance approver(s) from secure flow configuration
   - Details:
     ```
     Agent ID: [fsi_agentid]
     Environment GUID: [fsi_environmentguid]
     Flow Name: [fsi_flowname]
     Zone: [fsi_zone]
     Exception Scope: [fsi_exceptionscope]
     Business Justification: [fsi_justification]
     Requested By: [fsi_requestedby]
     Requested At: [fsi_requestedat]
     Expires At: [fsi_expiresat]
     ```
   - Timeout: configure 14-day timeout (`P14D`)

5. **Handle Timeout**
   - Add a parallel branch with **Run after** > **Has timed out**
   - Action: **Update a row** (Dataverse)
     - `fsi_isactive`: `false`
     - `fsi_approvalstatus`: `TimedOut`
     - `fsi_approvalnotes`: `Timed out: no approver response within 14 days`
   - Action: **Send an email (V2)** to the requester notifying of timeout

6. **Process Approval Response**

   **If Approved:**
   - Action: **Update a row** (Dataverse)
   - Fields:
     - `fsi_isactive`: `true`
     - `fsi_approvalstatus`: `Approved`
     - `fsi_approvedby`: responder email from the approval response
     - `fsi_approvedat`: `utcNow()`
     - `fsi_approvalnotes`: responder comments from the approval response
   - Notify requester and compliance channel

   **If Rejected:**
   - Action: **Update a row** (Dataverse)
   - Fields:
     - `fsi_isactive`: `false`
     - `fsi_approvalstatus`: `Rejected`
     - `fsi_approvedby`: responder email from the approval response
     - `fsi_approvedat`: `utcNow()`
     - `fsi_approvalnotes`: responder comments from the approval response
   - Notify requester and compliance channel with the rejection reason

---

## Human in the Loop Connector Notes

The Copilot Studio Human in the Loop connector (`shared_advancedapprovals`) is distinct from the standard Power Automate Approvals connector used by Flow 3.

- **Request for Information** (`RequestForInformation`) requires `title`, Outlook `message`, and `assignedTo` parameters. Assignees can be email addresses, UPNs, or Microsoft Entra ID user IDs separated by semicolons. Current Microsoft Learn guidance states only the first response is used, requests are sent through Outlook, and external-tenant assignees are not supported.
- **Run a Multistage Approval** (`StartAndWaitForAnApprovalProcess`) remains preview. Microsoft Learn lists limitations including agent-flow-only availability, no attachments, no ALM/sharing support, no duplicate approver across different stages, and Copilot Credits for AI approval stages.

---

## Connection References

The deployment script creates these solution connection references:

| Connection Reference | API | Purpose |
|----------------------|-----|---------|
| `fsi_cr_dataverse_hitlworkflowgovernance` | Dataverse | Schema, environment variables, scan evidence |
| `fsi_cr_humanintheloop_hitlworkflowgovernance` | Human in the Loop (`shared_advancedapprovals`) | Copilot Studio RFI and multistage approval actions |

Power Automate flows also need manual connections for the connectors they use at runtime:

| Connector | Flow Usage |
|-----------|------------|
| Azure Automation | Create job / read job output for `Start-HitlValidationRunbook` |
| Microsoft Teams | Adaptive card alert posting |
| Office 365 Outlook | Exception approval notifications and RFI delivery behavior |
| Approvals | `Start and wait for an approval` in Flow 3 |
| Planner | Remediation task creation |

Create these connections in Power Automate using your tenant's approved identity model. Prefer managed identity, workload identity federation, or certificate-based service principals for unattended automation where the connector supports it.

---

## Error Handling

All three flows make API calls that can fail transiently. Apply these patterns to each flow:

1. Wrap the main logic in a **Scope** action.
2. Add a catch scope with **Run after** configured for **Failed**, **Timed out**, or **Cancelled**.
3. Log error details to `fsi_HitlScanRun` or the relevant row, then alert the compliance channel.
4. Use exponential retry for Azure Automation HTTP operations and the Dataverse connector's default retry behavior for Dataverse rows.

---

## Deployment Validation

After building all flows:

1. **Scanner Flow Test**
   - Run `HITL-Scanner` manually
   - Verify a row exists in `fsi_HitlScanRun`
   - Verify required fields are populated in `fsi_HitlCheckpointResult` for any violation records

2. **Violation Alert Test**
   - Create a test `fsi_HitlCheckpointResult` row with `fsi_severity = 'Critical'`, required checkpoint fields, and `fsi_violationstatus = 100000000`
   - Verify `HITL-Violation-Alert` triggers
   - Verify the Teams adaptive card and Planner task are created

3. **Exception Approval Test**
   - Create a test `fsi_HitlCheckpointException` row with `fsi_approvalstatus = 'Pending'` and `fsi_isactive = false`
   - Approve the request and verify `fsi_isactive = true`, `fsi_approvalstatus = 'Approved'`, `fsi_approvedby`, and `fsi_approvedat`
   - Create another test, reject it, and verify `fsi_isactive = false` with `fsi_approvalstatus = 'Rejected'` and `fsi_approvalnotes`

4. **End-to-End Flow**
   - Run scan > violations detected > alert sent > exception submitted > approved > exception active for future scans

---

## Next Steps

After completing flow deployment:

1. Configure the Dataverse environment variables listed in README.md.
2. Store tenant, Dataverse URL, certificate, Teams, Planner, and approver settings in approved secure configuration.
3. Enable all three flows in Power Automate.
4. Monitor `HITL-Scanner` flow runs and Dataverse scan history.
5. Train compliance reviewers on exception approval workflow.

For comprehensive operational guidance, see the main [README.md](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/hitl-workflow-governance/README.md).
