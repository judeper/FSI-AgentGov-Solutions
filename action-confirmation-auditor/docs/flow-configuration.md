# Flow Configuration Guide

## Overview

This guide provides step-by-step instructions for manually building the Action Confirmation Auditor (ACA) Power Automate flows in Power Automate designer.

**Flows to Build:**
1. ACA-Scanner (Scheduled Cloud Flow)
2. ACA-Exception-Approval (Automated Cloud Flow)

**Prerequisites:**
- Power Automate Premium for the relevant owner or an allocated Power Automate Process license, as applicable, for the premium connectors
- Power Platform Admin for tenant administration, separate management-application registration for unattended enumeration, and per-environment Dataverse application-user security roles
- Access to Dataverse and Teams; Microsoft 365 E5/E5 Compliance is not a blanket prerequisite for the core scan
- Connection references configured (see deployment guide)
- Azure Automation account with `Start-ActionConfirmationValidationRunbook` imported as a Windows PowerShell 5.1 runbook, `Az.Accounts` 5.0.0+, `Microsoft.PowerApps.Administration.PowerShell`, and the supporting ACA/private/shared scripts deployed with their relative paths intact

Complete the [detailed prerequisites](prerequisites.md), including the worker's
certificate/private-key setup and separate Power Apps administration session.
The wrapper signs into Az.Accounts but does not initialize that session itself.
The managed-identity sample has a different JSON envelope and is not an unchanged
replacement for this flow's runbook.

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
   - `scanFrequencyHours`: Environment variable `fsi_ACA_ScanFrequencyHours` (default: 24)
   - `includeSandbox`: Environment variable `fsi_ACA_IncludeSandbox` (default: `"false"`)
   - `includeDrafts`: Environment variable `fsi_ACA_IncludeDrafts` (default: `"false"`)
   - `confirmationPatternMode`: Environment variable `fsi_ACA_ConfirmationPatternMode` (default: `"standard"`)

3. **Execute Azure Automation Runbook**
   - Action: "Create job" (Azure Automation)
   - Runbook: `Start-ActionConfirmationValidationRunbook`
   - Parameters:
     - `TenantId`: Tenant GUID (configure directly or from environment variable)
     - `ClientId`: Service principal app registration client ID
     - `CertificateThumbprint`: Certificate thumbprint for authentication
     - `DataverseUrl`: Dataverse environment URL
   - **Wait for Job: No** (return the job ID without waiting; step 4 owns completion polling)
   - Retain the **Job ID** (`properties.jobId`) returned by Create job for status, output, and failure diagnostics
   - Before enabling the recurrence, test a fresh worker with the configured identity and a known agent in every intended environment. An Az sign-in or a completed job alone does not demonstrate enumeration or Dataverse authorization

4. **Wait for Runbook Completion**
   - Add a **Do until** loop. Inside it, add a **Delay** of 30 seconds followed by **Get status of job** (Azure Automation), using the retained job ID from Create job
   - Exit when the returned **Status** (`properties.status`) is `Completed`, `Failed`, `Stopped`, or `Suspended`; `Running` or another nonterminal state must not proceed to output parsing
   - Set the loop limits explicitly: **Count: 60**, **Timeout: PT30M**. These are this flow's polling limits, not a Microsoft job-duration guarantee
   - After the loop, add a **Condition** that requires the last status to be exactly `Completed`. Put step 5 and all subsequent successful-scan processing in its **Yes** branch only
   - Route the **No** branch (including a nonterminal status after iteration exhaustion) to error handling with the retained job ID and last status. Do not parse output or write successful scan evidence
   - Configure the polling error handler's **Run after** for **Has failed** and **Has timed out**, so status-request failures and loop timeouts also log/alert and do not enter the successful branch
   - A polling timeout does not stop the remote Automation job. Preserve its job ID for separately authorized investigation or cancellation; do not automatically start a duplicate scan

   The [connector reference](https://learn.microsoft.com/connectors/azureautomation/)
   distinguishes **Wait for Job**, job status, and job output. See also
   [Power Automate loop limits](https://learn.microsoft.com/power-automate/limits-and-config#concurrency-looping-and-debatching-limits).

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
               "EnvironmentId": { "type": "string" },
               "EnvironmentName": { "type": "string" },
               "Zone": { "type": "string" },
               "AgentId": { "type": "string" },
               "AgentName": { "type": "string" },
               "ActionName": { "type": "string" },
               "ActionType": { "type": "string" },
               "ActionCategory": { "type": "string" },
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
     - `fsi_validationtime`: Variable `timestamp`
     - `fsi_overallstatus`: Parsed `OverallStatus`
     - `fsi_totalagents`: Parsed `TotalAgents`
     - `fsi_totalactions`: Parsed `TotalActions`
     - `fsi_actionswithconfirmation`: Expression `sub(body('Parse_JSON')?['TotalActions'], body('Parse_JSON')?['ActionsMissingConfirmation'])`
     - `fsi_actionsmissingconfirmation`: Parsed `ActionsMissingConfirmation`
     - `fsi_violationcount`: Parsed violations array length
     - `fsi_summaryjson`: Full JSON output

8. **For Each Violation**
   - Loop through parsed `Violations` array
   - Action: "Create a new record" (Dataverse)
   - Table: `fsi_ActionAuditResult`
   - Fields:
     - `fsi_name`: Expression `take(concat(items('Apply_to_each')?['ActionName'], ' - Missing Confirmation'), 100)`
     - `fsi_environmentguid`: Parsed `EnvironmentId` from violation item
     - `fsi_environmentname`: Parsed `EnvironmentName` from violation item
     - `fsi_zone`: Parsed `Zone` — map to canonical option set integer: Zone 1 = 100000001, Zone 2 = 100000002, Zone 3 = 100000003 (Unclassified = 100000000)
     - `fsi_agentid`: Parsed `AgentId` from violation item
     - `fsi_agentname`: Parsed `AgentName` from violation item
     - `fsi_actionname`: `ActionName`
     - `fsi_actiontype`: Map to option set integer: ConnectorAction = 100000000, CloudFlowAction = 100000001, PluginAction = 100000002, CustomAction = 100000003, HttpRequest = 100000004
     - `fsi_risklevel`: `ActionCategory` from violation (Write/Delete/Read/ExternalTransfer/Execute)
     - `fsi_confirmationstatus`: Map to option set integer: Present = 100000000, Missing = 100000001, Partial = 100000002, UnableToDetermine = 100000003
     - `fsi_violationstatus`: 100000000 (Open)
     - `fsi_severity`: `Severity` (string value: Critical/High/Medium/Warning)
     - `fsi_runid`: Variable `runId`
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
   - Trigger filters: *(none — fire on every create)*. As of solution v1.1.0 the schema sets `fsi_IsActive` default to **false** on create. The approval branch in step 5 sets `fsi_IsActive = true` only after the approver decides. This prevents a control-bypass window where an unapproved exception would suppress violations.

3. **Get Exception Record**
   - Action: "Get a record" (Dataverse)
   - Table: `fsi_ActionConfirmationException`
   - Record ID: Trigger output `fsi_actionconfirmationexceptionid`

4. **Send Approval Request**
   - Action: "Start and wait for an approval"
   - Approval type: Approve/Reject
   - Title: Expression `concat('ACA Exception: ', triggerOutputs()?['body/fsi_actionname'])`
   - Assigned to: Compliance team (configure the approver email address directly in the approval action — e.g., `compliance-team@contoso.com` or a mail-enabled security group)
   - Details: Include action name, action type, agent ID, environment, business justification
   - **Timeout:** Configure 14-day timeout (ISO 8601: `P14D`). Add a **Run after > Has timed out** branch to update `fsi_isactive` to `false` with note `"Timed out: no approver response within 14 days"` and notify the requestor.

5. **Process Approval Response**

   **If Approved:**
   - Action: "Update a record" (Dataverse)
   - Table: `fsi_ActionConfirmationException`
   - Fields:
     - `fsi_isactive`: `true`
     - `fsi_approvedby`: Approver email from approval response
     - `fsi_approvedat`: Expression `utcNow()`
     - `fsi_justification`: Append approver comments to existing justification text
   - Send notification to requestor: "Exception approved"
   - Post Teams message to compliance channel: Exception approval summary

   **If Rejected:**
   - Action: "Update a record" (Dataverse)
   - Table: `fsi_ActionConfirmationException`
   - Fields:
     - `fsi_isactive`: `false`
     - `fsi_justification`: Append rejection reason from approver comments
   - Send notification to requestor: "Exception rejected" with reason
   - Post Teams message to compliance channel: Exception rejection summary

6. **(Optional) Notify approval channel**
   - The approver decision is already persisted on the `fsi_ActionConfirmationException` row itself (`fsi_approvedby`, `fsi_approvedat`, `fsi_justification`, `fsi_rejectionnotes`, `fsi_isactive`). Do **not** write the approval event into `fsi_ActionAuditResult` — that table models confirmation-step violations, not approval workflow events, and several `ApplicationRequired` columns (`fsi_agentid`, `fsi_actionname`, `fsi_severity`, etc.) would not have meaningful values.
   - If a separate approval audit trail is required, model a new dedicated table (e.g., `fsi_ActionExceptionAuditEvent`) before adding this step.

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
| `fsi_cr_azureautomation_actionconfirmationauditor` | Azure Automation | OAuth user connection for this Power Automate path; separate from the runbook identity |

The [Azure Automation connector](https://learn.microsoft.com/connectors/azureautomation/)
documents managed-identity connection authentication for **Logic Apps**, not
Power Automate. Do not infer that the runbook's managed identity authenticates
the Power Automate connector as well. The connector's service-principal option
uses a client secret; it is not the recommended production credential path here.

**Steps to Create Connection Reference:**
1. Power Automate > Solutions > ACA
2. New > Connection Reference
3. Name: `fsi_cr_dataverse_actionconfirmationauditor`
4. Connector: Dataverse
5. Create connection > Select authentication
6. Save

Repeat for Teams, Office 365 Outlook, and Azure Automation connectors.

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
   - Confirm premium connector licensing, worker module versions, certificate/private-key availability, management-application registration, and Dataverse application-user roles
   - Confirm the worker bootstrap establishes the Power Apps administration session before the wrapper runs; verify `Get-AdminPowerAppEnvironment` and reads of known `bot`/`botcomponent` records in each intended environment
   - Run ACA-Scanner manually > Should succeed
   - Check `fsi_ActionScanRun` table for scan run record
   - Check `fsi_ActionAuditResult` table for violation records (if any)
   - Retain the expected-versus-scanned environment/agent inventory alongside the run output. A zero-agent result is not proof of a complete scan
   - Before scheduling, exercise the polling branches: `Completed` retrieves output; `Failed`/`Stopped`/`Suspended`, status-request failure, iteration exhaustion, and timeout produce failure diagnostics without successful scan evidence. Confirm Create job has **Wait for Job: No** and retain the remote job ID when polling ends without completion. These are deployment acceptance checks, not live results from this documentation review

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

**Issue: ACA-Scanner waits in Create job instead of reaching the polling timeout**
- **Cause:** Create job is configured to wait for completion, or the polling failure/timeout branches are not wired
- **Resolution:** Set **Wait for Job: No**, use the returned job ID in step 4's bounded status loop, and permit output processing only after status `Completed`. Configure failure/timeout run-after handling and check the remote job by its retained ID before any retry; the polling timeout does not cancel it.

**Issue: Azure Automation runbook fails with authentication error**
- **Cause:** Certificate/private key unavailable or expired, missing Power Apps administration session, or missing per-environment Dataverse authorization
- **Resolution:** Verify the worker can resolve the private-key certificate by thumbprint and that its public certificate matches the Entra app registration. Check `TenantId`, `ClientId`, and `CertificateThumbprint`. Confirm management-application registration and the separate Power Apps administration session, then check each environment's Dataverse application user/security role. Graph `Application.Read.All` is not a substitute for either authorization.

**Issue: Flow fails with "Invalid URI" error**
- **Cause:** Dataverse URL or API endpoint malformed
- **Resolution:** Verify the Dataverse URL format (should be `https://org.crm.dynamics.com/`)

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
- **Cause:** Missing Power Apps administration session, missing per-environment Dataverse permissions, or scan filters excluding expected agents
- **Resolution:** Verify enumeration independently, then grant the Dataverse application user read permissions on `bot` and `botcomponent` in each intended environment. Compare against a known-agent inventory and inspect warnings; do not accept zero as proof of no agents or no missing confirmations.

**Issue: Optional Purview correlation is empty**
- **Cause:** Separate runtime, licensing, audit access, query completion, or collection-path limitations
- **Resolution:** Run the helper in PowerShell 7+ with its Graph session and a separate Dataverse-audience token. Review the [optional integration's collection boundary](prerequisites.md#optional-microsoft-purview-dspm-integration); the shipped fallback is not the documented Activity Explorer export cmdlet, and an empty output does not establish complete Copilot activity collection.

---

## Next Steps

After completing flow deployment:
1. Configure environment variables (see main deployment guide)
2. Enable flows in Power Automate
3. Monitor ACA-Scanner flow runs for scan results
4. Train compliance team on exception approval workflow

For comprehensive operational guidance, see the main README.md.
