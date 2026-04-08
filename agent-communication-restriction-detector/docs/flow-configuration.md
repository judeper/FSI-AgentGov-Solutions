# Agent Communication Restriction Detector - Flow Setup Guide

## Overview

Step-by-step guide for building the ACRD Power Automate flows for automated agent communication restriction scanning and exception approval management.

This guide covers two flows:

1. **ACRD-Scanner** -- Daily scheduled scan of agent-to-agent communication patterns across all environments
2. **ACRD-Exception-Approval** -- Approval workflow triggered when a new communication exception is requested

> **Important:** These are manual build instructions. This solution does not include exported flow JSON files. Build each flow in the Power Automate designer following the steps below.

## Prerequisites

Before creating the flows, confirm you have:

- [ ] **Azure Automation Account** with:
  - `Start-CommRestrictionValidationRunbook.ps1` imported as a PowerShell 7.2 runbook
  - Certificate uploaded (Certificates blade)
  - Modules installed: MSAL.PS, Microsoft.PowerApps.Administration.PowerShell
  - Application permissions granted as required by Power Platform admin APIs
- [ ] **Dataverse environment** with ACRD schema deployed:
  - 5 tables: `fsi_CommScanRun`, `fsi_AgentCommViolation`, `fsi_ApprovedCommRoute`, `fsi_CommException`, `fsi_AgentSkillRegistration`
  - 9 environment variables configured
  - 4 connection references created
- [ ] **Microsoft Teams** channel for alert notifications
- [ ] **Email distribution list** for compliance alerts
- [ ] **Power Automate Premium license** (required for Azure Automation connector)
- [ ] **Connection references** bound in Power Automate:
  - `fsi_cr_dataverse_commrestrictiondetector` (Dataverse)
  - `fsi_cr_teams_commrestrictiondetector` (Microsoft Teams)
  - `fsi_cr_office365_commrestrictiondetector` (Office 365 Outlook)
  - `fsi_cr_azureautomation_commrestrictiondetector` (Azure Automation)

---

## Flow 1: ACRD-Scanner

### Purpose

Runs daily at 6:00 AM UTC, executes the Azure Automation runbook to scan agent-to-agent communication patterns, writes results to Dataverse, and routes alerts based on severity.

### Step 1: Create the Flow

1. Go to [make.powerautomate.com](https://make.powerautomate.com)
2. Select your governance environment
3. Click **Create** > **Scheduled cloud flow**
4. Name: `ACRD - Communication Restriction Validation (Daily)`
5. Set schedule:
   - Start: Today
   - Repeat every: **1 Day**
   - At: **6:00 AM**
   - Time zone: **UTC**
6. Click **Create**

### Step 2: Initialize Variables

Add these **Initialize variable** actions immediately after the trigger:

| Variable | Type | Default Value | Description |
|----------|------|---------------|-------------|
| `DataverseUrl` | String | `https://governance.crm.dynamics.com` | Your Dataverse environment URL |
| `TenantId` | String | `{{TENANT_DOMAIN}}` | Microsoft Entra ID tenant identifier |
| `ClientId` | String | `{{CLIENT_ID}}` | App registration client ID |
| `CertificateThumbprint` | String | `{{CERTIFICATE_THUMBPRINT}}` | Certificate thumbprint in Azure Automation |
| `SubscriptionId` | String | `{{AZURE_SUBSCRIPTION}}` | Azure subscription containing Automation Account |
| `ResourceGroup` | String | `{{RESOURCE_GROUP}}` | Resource group with Automation Account |
| `AutomationAccount` | String | `{{AUTOMATION_ACCOUNT}}` | Azure Automation Account name |
| `TeamsGroupId` | String | `{{TEAMS_GROUP_ID}}` | Teams group (team) ID for alerts |
| `TeamsChannelId` | String | `{{TEAMS_CHANNEL_ID}}` | Teams channel ID for alerts |
| `ComplianceDistributionList` | String | `{{COMPLIANCE_EMAIL}}` | Email DL for all alerts |

### Step 3: Execute Azure Automation Runbook

1. Add action: **Azure Automation** > **Create job**
2. Configure:
   - Subscription: `SubscriptionId` variable
   - Resource Group: `ResourceGroup` variable
   - Automation Account: `AutomationAccount` variable
   - Runbook Name: `Start-CommRestrictionValidationRunbook`
   - Runbook Parameters:
     - `TenantId`: `TenantId` variable
     - `ClientId`: `ClientId` variable
     - `CertificateThumbprint`: `CertificateThumbprint` variable
     - `DataverseUrl`: `DataverseUrl` variable
3. Rename action: `Create_Automation_Job`

### Step 4: Wait for Job Completion

1. Add action: **Azure Automation** > **Wait for job**
2. Configure:
   - Job ID: `Create_Automation_Job` output jobId
   - Timeout: 7200 seconds (2 hours)
   - Polling interval: 30 seconds
3. Rename action: `Wait_For_Job`

### Step 5: Get Job Output

1. Add action: **Azure Automation** > **Get job output**
2. Configure:
   - Job ID: same jobId from Step 3
3. Rename action: `Get_Job_Output`

### Step 6: Parse JSON Results

1. Add action: **Data Operations** > **Parse JSON**
2. Content: `Get_Job_Output` output
3. Schema: Use the following schema (generate from a sample runbook output):

```json
{
    "type": "object",
    "properties": {
        "RunId": { "type": "string" },
        "Timestamp": { "type": "string" },
        "OverallStatus": { "type": "string" },
        "TotalAgents": { "type": "integer" },
        "TotalEnvironments": { "type": "integer" },
        "ViolationCount": { "type": "integer" },
        "AlertRequired": { "type": "boolean" },
        "AlertSeverity": { "type": "string" },
        "Violations": {
            "type": "array",
            "items": {
                "type": "object",
                "properties": {
                    "AgentId": { "type": "string" },
                    "AgentName": { "type": "string" },
                    "EnvironmentId": { "type": "string" },
                    "EnvironmentName": { "type": "string" },
                    "SourceZone": { "type": "string" },
                    "TargetZone": { "type": "string" },
                    "ViolationType": { "type": "string" },
                    "TargetAgentId": { "type": "string" },
                    "TargetAgentName": { "type": "string" },
                    "CommunicationPattern": { "type": "string" },
                    "ExpectedPolicy": { "type": "string" },
                    "ActualConfig": { "type": "string" },
                    "Severity": { "type": "string" },
                    "RegulatoryContext": { "type": "string" }
                }
            }
        }
    }
}
```

4. Rename action: `Parse_Results`

### Step 7: Write Scan Run to Dataverse

> **Why this runs before alerting:** The audit trail record is created regardless of whether alerting succeeds or fails. This supports compliance with FINRA 4511 and SEC 17a-3 audit trail requirements.

1. Add action: **Dataverse** > **Add a new row**
2. Table: `Comm Scan Run` (`fsi_CommScanRun`)
3. Connection reference: `fsi_cr_dataverse_commrestrictiondetector`
4. Column mapping:

| Flow Expression | Dataverse Column | Type | Description |
|----------------|------------------|------|-------------|
| `"ACRDRun-" + Timestamp` | `fsi_name` | String | Display name with scan timestamp |
| `RunId` | `fsi_runid` | String | Unique run identifier |
| `OverallStatus` | `fsi_overallstatus` | String | Passed, Failed, or Error |
| `ViolationCount` | `fsi_violationcount` | Integer | Number of violations detected |
| `TotalAgents` | `fsi_totalagents` | Integer | Total agents scanned |
| `string(TotalEnvironments)` | `fsi_environmentsscanned` | String | Environments scanned |
| Full JSON output | `fsi_summaryjson` | Memo | Complete runbook output |
| `Timestamp` | `fsi_validationtime` | DateTime | Scan execution timestamp |

5. Rename action: `Write_Scan_Run`

### Step 8: Check if Alert Required

1. Add action: **Condition**
2. Condition: `AlertRequired` is equal to `true`
3. Configure **Run after**: `Write_Scan_Run` -- set to run after **Succeeded** and **Failed** (so alerting proceeds even if the Dataverse write fails)
4. Rename action: `Check_Alert_Required`

### Step 9: If Yes -- Post Teams Adaptive Card

1. In the **Yes** branch, add: **Microsoft Teams** > **Post adaptive card in a chat or channel**
2. Connection reference: `fsi_cr_teams_commrestrictiondetector`
3. Post in: Channel
4. Team: `TeamsGroupId` variable
5. Channel: `TeamsChannelId` variable
6. Adaptive Card JSON (summary template):

```json
{
    "type": "AdaptiveCard",
    "$schema": "http://adaptivecards.io/schemas/adaptive-card.json",
    "version": "1.4",
    "body": [
        {
            "type": "TextBlock",
            "text": "Agent Communication Restriction Alert",
            "weight": "Bolder",
            "size": "Large",
            "color": "Attention"
        },
        {
            "type": "FactSet",
            "facts": [
                { "title": "Status", "value": "${OverallStatus}" },
                { "title": "Severity", "value": "${AlertSeverity}" },
                { "title": "Violations", "value": "${ViolationCount}" },
                { "title": "Agents Scanned", "value": "${TotalAgents}" },
                { "title": "Environments", "value": "${TotalEnvironments}" },
                { "title": "Scan Time", "value": "${Timestamp}" }
            ]
        }
    ]
}
```

7. Rename action: `Post_Teams_Card`

### Step 10: If Yes -- Send Email Alert

1. Still in the **Yes** branch, add: **Office 365 Outlook** > **Send an email (V2)**
2. Connection reference: `fsi_cr_office365_commrestrictiondetector`
3. Configure:
   - To: `ComplianceDistributionList` variable
   - Subject: `[ACRD Alert- @{AlertSeverity}] Agent Communication Violations Detected`
   - Importance: High (for Critical/Failed/Error), Normal (for Warning)
   - Body: HTML table with violation summary, zone breakdown, communication pattern details, and agent-level details
4. Rename action: `Send_Alert_Email`

### Step 11: Error Handling (Scope_Catch)

1. Wrap steps 3-10 in a **Scope** named `Scope_Main`
2. Add a parallel **Scope** named `Scope_Catch`
3. Configure `Scope_Catch` to run after `Scope_Main` has **Failed** or **Timed Out**
4. Inside `Scope_Catch`, add **Send an email (V2)**:
   - To: `ComplianceDistributionList` variable
   - Subject: `[CRITICAL] ACRD Flow Execution Failed`
   - Importance: High
   - Body: Include error details from `Scope_Main` result

### Alert Routing Summary

| Severity | Teams Card | Email | Email Importance |
|----------|-----------|-------|-----------------|
| Critical | Yes | Yes | High |
| Failed | Yes | Yes | High |
| Error | Yes | Yes | High |
| High | Yes | Yes | High |
| Warning | No | Yes | Normal |
| Passed/Info | No | No | -- |

---

## Flow 2: ACRD-Exception-Approval

### Purpose

Provides a structured approval workflow when agents require exceptions to blocked communication patterns. Triggered automatically when a new communication exception record is created in Dataverse, routes the request to the governance team for approval, and updates the exception status accordingly.

### Step 1: Create the Flow

1. Go to [make.powerautomate.com](https://make.powerautomate.com)
2. Select your governance environment
3. Click **Create** > **Automated cloud flow**
4. Name: `ACRD - Communication Exception Approval`
5. Choose trigger: **Dataverse** > **When a row is added, modified or deleted**
6. Click **Create**

### Step 2: Configure Trigger

1. Change type: **Create**
2. Table name: `Comm Exception` (`fsi_CommException`)
3. Scope: **Organization** (all users)
4. Connection reference: `fsi_cr_dataverse_commrestrictiondetector`

### Step 3: Get Exception Details

1. Add action: **Dataverse** > **Get a row by ID**
2. Table name: `Comm Exception` (`fsi_CommException`)
3. Row ID: Trigger row ID
4. Select columns: `fsi_name, fsi_sourceagentid, fsi_sourceagentname, fsi_targetagentid, fsi_targetagentname, fsi_sourcezone, fsi_targetzone, fsi_communicationpattern, fsi_justification, fsi_requestedby, fsi_requestedon`
5. Connection reference: `fsi_cr_dataverse_commrestrictiondetector`
6. Rename action: `Get_Exception_Details`

### Step 4: Send Approval Email

1. Add action: **Approvals** > **Start and wait for an approval**
2. Configure:
   - Approval type: **Approve/Reject - First to respond**
   - Title: `[ACRD Exception] @{fsi_sourceagentname} -> @{fsi_targetagentname} (@{fsi_communicationpattern})`
   - Assigned to: `{{COMPLIANCE_EMAIL}}`
   - Details (HTML):
     ```
     <h3>Communication Exception Request</h3>
     <table>
       <tr><td><b>Source Agent:</b></td><td>@{fsi_sourceagentname} (@{fsi_sourceagentid})</td></tr>
       <tr><td><b>Target Agent:</b></td><td>@{fsi_targetagentname} (@{fsi_targetagentid})</td></tr>
       <tr><td><b>Source Zone:</b></td><td>@{fsi_sourcezone}</td></tr>
       <tr><td><b>Target Zone:</b></td><td>@{fsi_targetzone}</td></tr>
       <tr><td><b>Pattern:</b></td><td>@{fsi_communicationpattern}</td></tr>
       <tr><td><b>Justification:</b></td><td>@{fsi_justification}</td></tr>
       <tr><td><b>Requested By:</b></td><td>@{fsi_requestedby}</td></tr>
       <tr><td><b>Requested On:</b></td><td>@{fsi_requestedon}</td></tr>
     </table>
     ```
   - Item link: Link to the Dataverse record
3. Rename action: `Wait_For_Approval`

### Step 5: Check Approval Response

1. Add action: **Condition**
2. Condition: `Outcome` is equal to `Approve`
3. Rename action: `Check_Approval_Outcome`

### Step 6: If Approved -- Update Exception Status

1. In the **Yes** branch, add: **Dataverse** > **Update a row**
2. Table name: `Comm Exception` (`fsi_CommException`)
3. Row ID: Trigger row ID
4. Column mapping:
   - `fsi_exceptionstatus`: `Approved` (option set value)
   - `fsi_approvedby`: Approver display name from approval response
   - `fsi_approvedat`: `utcNow()`
5. Connection reference: `fsi_cr_dataverse_commrestrictiondetector`
6. Rename action: `Update_Exception_Approved`

### Step 7: If Denied -- Update Exception Status

1. In the **No** branch, add: **Dataverse** > **Update a row**
2. Table name: `Comm Exception` (`fsi_CommException`)
3. Row ID: Trigger row ID
4. Column mapping:
   - `fsi_exceptionstatus`: `Denied` (option set value)
   - `fsi_approvedby`: Responder display name from approval response
   - `fsi_approvedat`: `utcNow()`
5. Connection reference: `fsi_cr_dataverse_commrestrictiondetector`
6. Rename action: `Update_Exception_Denied`

### Step 8: Log to Audit Trail

After either branch (use a common action after the condition):

1. Add action: **Dataverse** > **Add a new row**
2. Table: `Comm Scan Run` (`fsi_CommScanRun`)
3. Column mapping:
   - `fsi_name`: `"ExceptionDecision-" + utcNow()`
   - `fsi_overallstatus`: `"Info"`
   - `fsi_summaryjson`: JSON object with exception ID, decision (Approved/Denied), approver, comments, source/target agent details
   - `fsi_validationtime`: `utcNow()`
4. Rename: `Log_Exception_Decision`

### Step 9: Send Notification to Requester

1. Add action: **Office 365 Outlook** > **Send an email (V2)**
2. Connection reference: `fsi_cr_office365_commrestrictiondetector`
3. Configure:
   - To: `fsi_requestedby`(requester email from exception record)
   - Subject: `[ACRD Exception @{Outcome}] @{fsi_sourceagentname} -> @{fsi_targetagentname}`
   - Body: HTML with decision details, approver comments, and next steps
   - Importance: Normal
4. Rename action: `Send_Requester_Notification`

### Step 10: Test the Flow

1. Click **Test** > **Manually**
2. In another browser tab, open the Dataverse `fsi_CommException` table
3. Add a test record with:
   - Source and target agent names
   - Communication pattern (e.g., "Cross-Zone")
   - Justification text
4. Verify:
   - Approval email arrives at the compliance DL
   - Approve or deny the request
   - Exception record status is updated in Dataverse
   - Audit trail record is written to `fsi_CommScanRun`
   - Requester receives notification email
   - Flow run completes without errors

---

## Troubleshooting

### Azure Automation Job Failures

- **Job stuck in "Running"**: Check Azure Automation job logs; may be waiting for module install
- **Job completes but output is empty**: Verify runbook parameters, check Write-Verbose output
- **Authentication errors**: Verify certificate thumbprint, check certificate expiration
- **Module not found**: Install MSAL.PS in Automation Account (Modules blade)
- **Timeout (2-hour limit)**: The Wait_For_Job loop times out after 2 hours; increase if scanning many agents

### Dataverse Write Failures

| Error Code | Cause | Resolution |
|-----------|-------|------------|
| 403 Forbidden | Identity lacks Create permission on ACRD tables | Assign security role with Organization-level Create |
| 404 Not Found | Table not deployed to environment | Deploy Dataverse schema (`scripts/deploy.py`) |
| 400 Bad Request | Schema mismatch (column names do not match) | Verify column names match the schema deployed |

### Teams Channel Not Found

- Verify `TeamsGroupId` and `TeamsChannelId` variables match your target channel
- Confirm the Teams connection has permissions to post to the channel
- Check that `fsi_cr_teams_commrestrictiondetector` connection reference is properly bound
- Test channel posting manually in Power Automate to isolate permissions issues

### Parse JSON Schema Mismatch

- The Parse_Results schema must match the runbook output structure exactly
- If the runbook output changes (e.g., new fields added), update the schema in the flow
- Key ACRD schema differences from other solutions: `SourceZone`/`TargetZone` fields per violation, `TargetAgentId`/`TargetAgentName` for communication target, `CommunicationPattern` for the detected pattern type

### Approval Flow Issues

- **Approval not received**: Verify the `{{COMPLIANCE_EMAIL}}` distribution list is correct and members have Power Automate licenses
- **Approval times out**: The default approval timeout is 30 days; configure a custom timeout if needed
- **Exception status not updating**: Check Dataverse permissions for the flow connection identity

### Flow Errors (Scope_Catch)

- If you receive a "[CRITICAL] ACRD Flow Execution Failed" email, the flow itself encountered an error
- Check the flow run history for the specific action that failed
- Common causes: expired connections, permission changes, Azure Automation account unavailable

---

*Agent Communication Restriction Detector -- Flow Setup Guide v1.0.0*
