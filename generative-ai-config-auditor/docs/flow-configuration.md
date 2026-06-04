# Generative AI Config Auditor - Flow Setup Guide

## Overview

Step-by-step guide for building the GAC Power Automate flows for automated generative AI configuration validation and approved connection alerting.

This guide covers two flows:

1. **GAC-DailyAudit** -- Daily scheduled scan of generative AI configurations across all environments
2. **GAC-WhitelistAlert** -- Real-time notification when approved AOAI connections are added or modified

> **Important:** These are manual build instructions. This solution does not include exported flow JSON files. Build each flow in the Power Automate designer following the steps below.

## Prerequisites

Before creating the flows, confirm you have:

- [ ] **Azure Automation Account** with:
  - `Start-GenAIConfigValidationRunbook.ps1` imported as a PowerShell 7.4 runbook
  - Certificate uploaded (Certificates blade)
  - Modules installed: MSAL.PS, Microsoft.PowerApps.Administration.PowerShell
  - Application permissions granted as required by Power Platform admin APIs
- [ ] **Dataverse environment** with GAC schema deployed:
  - 5 tables: `fsi_GACBaseline`, `fsi_GACValidationHistory`, `fsi_GACViolation`, `fsi_GACApprovedConnection`, `fsi_GACFeatureInventory`
  - 8 environment variables configured
  - 4 connection references created
- [ ] **Microsoft Teams** channel for alert notifications
- [ ] **Email distribution list** for compliance alerts
- [ ] **Power Automate Premium license** (required for Azure Automation connector)
- [ ] **Connection references** bound in Power Automate:
  - `fsi_cr_dataverse_genaiconfigauditor` (Dataverse)
  - `fsi_cr_teams_genaiconfigauditor` (Microsoft Teams)
  - `fsi_cr_office365_genaiconfigauditor` (Office 365 Outlook)
  - Azure Automation connection to your subscription

---

## Flow 1: GAC-DailyAudit

### Purpose

Runs daily at 6:00 AM UTC, executes the Azure Automation runbook to scan generative AI configurations, writes results to Dataverse, and routes alerts based on severity.

### Step 1: Create the Flow

1. Go to [make.powerautomate.com](https://make.powerautomate.com)
2. Select your governance environment
3. Click **Create** > **Scheduled cloud flow**
4. Name: `GAC - Generative AI Config Validation (Daily)`
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
   - Runbook Name: `Start-GenAIConfigValidationRunbook`
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
                    "Zone": { "type": "string" },
                    "ViolationType": { "type": "string" },
                    "AzureOpenAIEnabled": { "type": "boolean" },
                    "OrchestrationMode": { "type": "string" },
                    "GenerativeAnswersNodeCount": { "type": "integer" },
                    "Severity": { "type": "string" },
                    "RegulatoryContext": { "type": "string" }
                }
            }
        },
        "Drift": {
            "type": "object",
            "properties": {
                "HasDrift": { "type": "boolean" },
                "IsFirstRun": { "type": "boolean" },
                "DriftedAgents": { "type": "integer" },
                "Details": { "type": "array" }
            }
        }
    }
}
```

4. Rename action: `Parse_Results`

### Step 7: Write Validation History to Dataverse

> **Why this runs before alerting:** The audit trail record is created regardless of whether alerting succeeds or fails. This supports compliance with FINRA Rule 4511 and SEC Rule 17a-3 audit trail requirements.

1. Add action: **Dataverse** > **Add a new row**
2. Table: `GAC Validation History` (`fsi_GACValidationHistory`)
3. Connection reference: `fsi_cr_dataverse_genaiconfigauditor`
4. Column mapping:

| Flow Expression | Dataverse Column | Type | Description |
|----------------|------------------|------|-------------|
| `"GACRun-" + Timestamp` | `fsi_name` | String | Display name with scan timestamp |
| `RunId` | `fsi_runid` | String | Unique run identifier |
| `OverallStatus` | `fsi_overallstatus` | String | Passed, Failed, or Error |
| `ViolationCount` | `fsi_violationcount` | Integer | Number of violations detected |
| `TotalAgents` | `fsi_totalagents` | Integer | Total agents scanned |
| `string(TotalEnvironments)` | `fsi_environmentsscanned` | String | Environments scanned |
| Full JSON output | `fsi_summaryjson` | Memo | Complete runbook output |
| `Timestamp` | `fsi_validationtime` | DateTime | Scan execution timestamp |

5. Rename action: `Write_Validation_History`

### Step 8: Check if Alert Required

1. Add action: **Condition**
2. Condition: `AlertRequired` is equal to `true`
3. Configure **Run after**: `Write_Validation_History` -- set to run after **Succeeded** and **Failed** (so alerting proceeds even if the Dataverse write fails)
4. Rename action: `Check_Alert_Required`

### Step 9: If Yes -- Post Teams Adaptive Card

1. In the **Yes** branch, add: **Microsoft Teams** > **Post adaptive card in a chat or channel**
2. Connection reference: `fsi_cr_teams_genaiconfigauditor`
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
            "text": "Generative AI Config Audit Alert",
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
2. Connection reference: `fsi_cr_office365_genaiconfigauditor`
3. Configure:
   - To: `ComplianceDistributionList` variable
   - Subject: `[GAC Alert - @{AlertSeverity}] Generative AI Config Violations Detected`
   - Importance: High (for Critical/Failed/Error), Normal (for Warning)
   - Body: HTML table with violation summary, zone breakdown, and agent-level details
4. Rename action: `Send_Alert_Email`

### Step 11: Error Handling (Scope_Catch)

1. Wrap steps 3-10 in a **Scope** named `Scope_Main`
2. Add a parallel **Scope** named `Scope_Catch`
3. Configure `Scope_Catch` to run after `Scope_Main` has **Failed** or **Timed Out**
4. Inside `Scope_Catch`, add **Send an email (V2)**:
   - To: `ComplianceDistributionList` variable
   - Subject: `[CRITICAL] GAC Flow Execution Failed`
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

## Flow 2: GAC-WhitelistAlert

### Purpose

Sends real-time notifications when approved Azure OpenAI connections are added to or modified in the governance whitelist, providing an audit trail for connection approval changes.

### Step 1: Create the Flow

1. Go to [make.powerautomate.com](https://make.powerautomate.com)
2. Select your governance environment
3. Click **Create** > **Automated cloud flow**
4. Name: `GAC - Approved Connection Change Alert`
5. Choose trigger: **Dataverse** > **When a row is added, modified or deleted**
6. Click **Create**

### Step 2: Configure Trigger

1. Change type: **Create or Update**
2. Table name: `GAC Approved Connections` (`fsi_GACApprovedConnection`)
3. Scope: **Organization** (all users)
4. Select columns: `fsi_isactive, fsi_connectionname, fsi_zone, fsi_aoaiendpoint`
5. Connection reference: `fsi_cr_dataverse_genaiconfigauditor`

### Step 3: Initialize Variables

Add these **Initialize variable** actions:

| Variable | Type | Default Value | Description |
|----------|------|---------------|-------------|
| `ComplianceDistributionList` | String | `{{COMPLIANCE_EMAIL}}` | Compliance team DL |
| `TeamsGroupId` | String | `{{TEAMS_GROUP_ID}}` | Teams group ID |
| `TeamsChannelId` | String | `{{TEAMS_CHANNEL_ID}}` | Teams channel ID |

### Step 4: Determine Change Type

1. Add action: **Condition**
2. Condition: Trigger `SdkMessage` is equal to `Create`
3. Rename: `Check_Change_Type`

### Step 5: If Create -- New Connection Added

1. In the **Yes** branch, add: **Office 365 Outlook** > **Send an email (V2)**
2. Configure:
   - To: `ComplianceDistributionList` variable
   - Subject: `[GAC Whitelist] New AOAI Connection Approved: @{triggerBody()?['fsi_connectionname']}`
   - Body: HTML with connection details (name, zone, AOAI endpoint, approved by, approval date)
   - Importance: Normal
3. Rename: `Send_New_Connection_Email`

### Step 6: If Update -- Connection Modified

1. In the **No** branch, add: **Office 365 Outlook** > **Send an email (V2)**
2. Configure:
   - To: `ComplianceDistributionList` variable
   - Subject: `[GAC Whitelist] AOAI Connection Modified: @{triggerBody()?['fsi_connectionname']}`
   - Body: HTML with connection details and change description (focus on `fsi_isactive` changes)
   - Importance: High (deactivating a connection may affect running agents)
3. Rename: `Send_Modified_Connection_Email`

### Step 7: Log to Audit Trail

After either branch (use a common action after the condition):

1. Add action: **Dataverse** > **Add a new row**
2. Table: `GAC Validation History` (`fsi_GACValidationHistory`)
3. Column mapping:
   - `fsi_name`: `"WhitelistChange-" + utcNow()`
   - `fsi_overallstatus`: `"Info"`
   - `fsi_summaryjson`: JSON object with change type, connection details, and modifier identity
   - `fsi_validationtime`: `utcNow()`
4. Rename: `Log_Whitelist_Change`

### Step 8: Test the Flow

1. Click **Test** > **Manually**
2. In another browser tab, open the Dataverse `fsi_GACApprovedConnection` table
3. Add a test record or modify an existing record's `fsi_isactive` field
4. Verify:
   - Email arrives at the compliance DL
   - Audit trail record is written to `fsi_GACValidationHistory`
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
| 403 Forbidden | Identity lacks Create permission on GAC tables | Assign security role with Organization-level Create |
| 404 Not Found | Table not deployed to environment | Deploy Dataverse schema (`scripts/deploy.py`) |
| 400 Bad Request | Schema mismatch (column names do not match) | Verify column names match the schema deployed |

### Teams Channel Not Found

- Verify `TeamsGroupId` and `TeamsChannelId` variables match your target channel
- Confirm the Teams connection has permissions to post to the channel
- Check that `fsi_cr_teams_genaiconfigauditor` connection reference is properly bound
- Test channel posting manually in Power Automate to isolate permissions issues

### Parse JSON Schema Mismatch

- The Parse_Results schema must match the runbook output structure exactly
- If the runbook output changes (e.g., new fields added), update the schema in the flow
- Key GAC schema differences from CMM: each violation includes `ViolationType` plus the generative AI configuration fields `AzureOpenAIEnabled`, `OrchestrationMode`, and `GenerativeAnswersNodeCount` (instead of CMM's `ExpectedModerationLevel`/`ActualModerationLevel`)

### Flow Errors (Scope_Catch)

- If you receive a "[CRITICAL] GAC Flow Execution Failed" email, the flow itself encountered an error
- Check the flow run history for the specific action that failed
- Common causes: expired connections, permission changes, Azure Automation account unavailable

---

*Generative AI Config Auditor -- Flow Setup Guide v1.1.1*
