# Flow Configuration Guide

## Overview

This guide provides step-by-step instructions for manually building the Action Confirmation Auditor (ACA) Power Automate flows in Power Automate designer.

**Flows to Build:**
1. ACA-Scanner (Scheduled Cloud Flow)
2. ACA-Exception-Approval (Automated Cloud Flow)

**Prerequisites:**
- Power Automate Premium license
- Power Platform Admin role in target environment
- Access to Dataverse and Teams
- Connection references configured (see deployment guide)
- Azure Automation account with `Start-ActionConfirmationValidationRunbook` imported

---

## Flow 1: ACA-Scanner

**Type:** Scheduled Cloud Flow
**Trigger:** Recurrence (Daily at 06:00 UTC)
**Purpose:** Execute action confirmation validation scan across Power Platform environments and record results

### Build Steps

1. **Create New Flow**
   - Power Automate > Cloud Flows > Scheduled Cloud Flow
   - Flow name: `ACA-Scanner`
   - Recurrence: Daily at 06:00 UTC

2. **Initialize Variables**
   - `timestamp`: Expression `utcNow()`
   - `runId`: Expression `guid()`
   - `tenantId`: Environment variable `fsi_ACA_TenantId`
   - `dataverseUrl`: Environment variable `fsi_ACA_DataverseUrl`
   - `scanFrequencyHours`: Environment variable `fsi_ACA_ScanFrequencyHours` (default: 24)
   - `dryRunMode`: Environment variable `fsi_ACA_DryRunMode` (default: `"true"`)
   - `alertSeverityThreshold`: Environment variable `fsi_ACA_AlertSeverityThreshold` (default: `"Medium"`)

3. **Execute Azure Automation Runbook**
   - Action: "Create job" (Azure Automation)
   - Runbook: `Start-ActionConfirmationValidationRunbook`
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
         "TotalActions": { "type": "integer" },
         "ActionsMissingConfirmation": { "type": "integer" },
         "Violations": {
           "type": "array",
           "items": {
             "type": "object",
             "properties": {
               "ActionName": { "type": "string" },
               "ActionType": { "type": "string" },
               "ConfirmationStatus": { "type": "string" },
               "Severity": { "type": "string" }
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
   - Table: `fsi_ActionScanRun`
   - Fields:
     - `fsi_name`: Expression `concat('ACA-Run-', variables('runId'))`
     - `fsi_runid`: Variable `runId`
     - `fsi_timestamp`: Variable `timestamp`
     - `fsi_overallstatus`: Parsed `OverallStatus`
     - `fsi_totalagents`: Parsed `TotalAgents`
     - `fsi_totalactions`: Parsed `TotalActions`
     - `fsi_actionsmissingconfirmation`: Parsed `ActionsMissingConfirmation`
     - `fsi_resultjson`: Full JSON output

8. **For Each Violation**
   - Loop through parsed `Violations` array
   - Action: "Create a new record" (Dataverse)
   - Table: `fsi_ActionAuditResult`
   - Fields:
     - `fsi_name`: Expression `take(concat(items('Apply_to_each')?['ActionName'], ' - Missing Confirmation'), 100)`
     - `fsi_actionname`: `ActionName`
     - `fsi_actiontype`: `ActionType`
     - `fsi_confirmationstatus`: `ConfirmationStatus`
     - `fsi_severity`: `Severity` (mapped to option set value)
     - `fsi_scanrunid`: Variable `runId`
     - `fsi_detectedat`: Variable `timestamp`

9. **Check Alert Threshold**
   - **Condition:** `AlertRequired` equals `true`
   - **If true:** Continue to step 10
   - **If false:** End flow

10. **Send Teams Alert**
    - Action: "Post an Adaptive Card to a Teams Channel"
    - Channel: Use `fsi_ACA_TeamsGroupId` and `fsi_ACA_TeamsChannelId`
    - Card content:
      - Title: "ACA Scan Alert"
      - Summary: Total agents scanned, actions missing confirmation, highest severity
      - Violation table: Action name, type, severity
      - Link to Dataverse scan run record

11. **Send Email Notification**
    - Action: "Send an email (V2)" (Office 365 Outlook)
    - To: Compliance team distribution list
    - Subject: `ACA Alert: [AlertSeverity] - [ActionsMissingConfirmation] actions missing confirmation`
    - Body: Same content as Teams card in HTML format

**Trigger Configuration:**
- Frequency: Hour
- Interval: Value of `fsi_ACA_ScanFrequencyHours` (default: 24, i.e., daily)
- Time zone: UTC
- Start time: 06:00

---

## Flow 2: ACA-Exception-Approval

**Type:** Automated Cloud Flow
**Trigger:** When a record is created (Dataverse)
**Purpose:** Route confirmation exception requests to compliance team for approval

### Build Steps

1. **Create New Flow**
   - Power Automate > Cloud Flows > Automated Cloud Flow
   - Flow name: `ACA-Exception-Approval`
   - Trigger: "When a record is created"

2. **Configure Trigger**
   - Entity: `fsi_ActionConfirmationException`
   - Message: 1 (Create only)
   - Scope: 4 (Organization)
   - Trigger filters: `fsi_isactive eq true` (active exception requests pending approval; fsi_IsActive defaults to true on create)

3. **Get Exception Record**
   - Action: "Get a record" (Dataverse)
   - Table: `fsi_ActionConfirmationException`
   - Record ID: Trigger output `fsi_actionconfirmationexceptionid`

4. **Send Approval Request**
   - Action: "Start and wait for an approval"
   - Approval type: Approve/Reject
   - Title: Expression `concat('ACA Exception: ', triggerOutputs()?['body/fsi_actionname'], ' - ', triggerOutputs()?['body/fsi_agentname'])`
   - Assigned to: Compliance team (configure the approver email address directly in the approval action — e.g., `compliance-team@contoso.com` or a mail-enabled security group)
   - Details: Include action name, action type, agent name, environment, business justification, requestor
   - **Timeout:** Configure 14-day timeout (ISO 8601: `P14D`). Add a **Run after > Has timed out** branch to update `fsi_isactive` to `false` with note `"Timed out: no approver response within 14 days"` and notify the requestor.

5. **Process Approval Response**

   **If Approved:**
   - Action: "Update a record" (Dataverse)
   - Table: `fsi_ActionConfirmationException`
   - Fields:
     - `fsi_isactive`: `true`
     - `fsi_approvedby`: Approver email from approval response
     - `fsi_approvedat`: Expression `utcNow()`
     - `fsi_approvalnotes`: Approver comments from approval response
   - Send notification to requestor: "Exception approved"
   - Post Teams message to compliance channel: Exception approval summary

   **If Rejected:**
   - Action: "Update a record" (Dataverse)
   - Table: `fsi_ActionConfirmationException`
   - Fields:
     - `fsi_isactive`: `false`
     - `fsi_rejectedby`: Approver email from approval response
     - `fsi_rejectionnotes`: Approver comments (rejection reason)
   - Send notification to requestor: "Exception rejected" with reason
   - Post Teams message to compliance channel: Exception rejection summary

6. **Log to Audit Trail**
   - Action: "Create a new record" (Dataverse)
   - Table: `fsi_ActionAuditResult` (or dedicated audit log)
   - Fields: Record the approval/rejection event with timestamp, approver, and outcome

**Trigger Configuration:**
```
Entity: fsi_ActionConfirmationException
Message: Create only
Scope: Organization
```

---

## Error Handling

Both flows make API calls (Azure Automation, Dataverse, Teams) that can fail transiently. Apply these patterns to each flow.

### Scope-Based Try/Catch Pattern

Wrap the main logic of each flow in a **Scope** action (acts as a "try" block), then add parallel branches for error handling:

1. **Scope: Main Logic** -- Contains all flow steps
2. **Scope: Catch** -- Configure **Run after** to execute only when Main Logic has **Failed**, **Timed out**, or been **Cancelled**
   - Log error details to `fsi_ActionScanRun` (for ACA-Scanner) or a dedicated error log
   - Send Teams alert with failure context (flow name, error message, run ID)
   - Set appropriate status so the issue is visible in Dataverse

### Run-After Configuration

For critical actions (Azure Automation jobs, Dataverse writes, Teams posts), configure **Run after** settings:

- **Is successful** -- Continue normal flow
- **Has failed** -- Branch to error handling (log error, send alert, terminate gracefully)
- **Has timed out** -- Treat as transient failure, log and alert

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
| `fsi_cr_dataverse_actionconfirmationauditor` | Dataverse | Service Principal or User |
| `fsi_cr_teams_actionconfirmationauditor` | Microsoft Teams | Current User |
| `fsi_cr_office365_actionconfirmationauditor` | Office 365 Outlook | Current User |
| `fsi_cr_azureautomation_actionconfirmationauditor` | Azure Automation | Service Principal |
| `fsi_cr_approvals_actionconfirmationauditor` | Approvals | Current User |

**Steps to Create Connection Reference:**
1. Power Automate > Solutions > ACA
2. New > Connection Reference
3. Name: `fsi_cr_dataverse_actionconfirmationauditor`
4. Connector: Dataverse
5. Create connection > Select authentication
6. Save

Repeat for Teams, Office 365 Outlook, Azure Automation, and Approvals connectors.

---

## Flow Binding

After creating connection references:

1. Open each flow in edit mode
2. Navigate to **Data** > **Connection References**
3. For each connection reference in the flow:
   - Select the matching connection from the dropdown
   - Verify authentication method
4. Save and publish flow

---

## Deployment Validation

After building all flows:

1. **Scanner Flow Test**
   - Run ACA-Scanner manually > Should succeed
   - Check `fsi_ActionScanRun` table for scan run record
   - Check `fsi_ActionAuditResult` table for violation records (if any)

2. **Alert Test**
   - Verify Teams card posted to configured channel (if violations found)
   - Verify email sent to compliance team

3. **Exception Request Test**
   - Create a test record in `fsi_ActionConfirmationException`
   - Verify ACA-Exception-Approval flow triggered
   - Verify approval request sent to compliance approver
   - Approve > Verify `fsi_isactive` set to `true`
   - Reject test > Verify `fsi_isactive` set to `false` with rejection notes

4. **End-to-End Flow**
   - Run scan > Violations detected > Exception submitted > Approved > Exception active for future scans

---

## Troubleshooting

**Issue: Azure Automation runbook fails with authentication error**
- **Cause:** Service principal credentials expired or insufficient permissions
- **Resolution:** Verify the Azure Automation Run As account or Managed Identity has Power Platform Admin permissions. Check `fsi_ACA_ClientId` and `fsi_ACA_TenantId` environment variables.

**Issue: Flow fails with "Invalid URI" error**
- **Cause:** Dataverse URL or API endpoint malformed
- **Resolution:** Verify `fsi_ACA_DataverseUrl` environment variable format (should be `https://org.crm.dynamics.com/`)

**Issue: Trigger not firing when exception record created**
- **Cause:** Trigger filter may be excluding records
- **Resolution:** Remove or adjust trigger filter, test with manual run

**Issue: Teams card not rendering**
- **Cause:** JSON schema mismatch or invalid channel/group ID
- **Resolution:** Validate `fsi_ACA_TeamsGroupId` and `fsi_ACA_TeamsChannelId` formats

**Issue: Dataverse connector "Access denied"**
- **Cause:** Connection user lacks required permissions
- **Resolution:** Verify user has Dataverse System Administrator or equivalent security role

**Issue: Scan results show zero agents**
- **Cause:** Service principal lacks permissions to read bot/botcomponent tables
- **Resolution:** Grant Dataverse read permissions on `bot` and `botcomponent` system tables to the service principal

---

## Next Steps

After completing flow deployment:
1. Configure environment variables (see main deployment guide)
2. Set `fsi_ACA_DryRunMode` to `"false"` when ready for production
3. Enable flows in Power Automate
4. Monitor ACA-Scanner flow runs for scan results
5. Train compliance team on exception approval workflow

For comprehensive operational guidance, see the main README.md.
