# Content Moderation Governance Monitor - Flow Setup Guide

## Overview

Step-by-step guide for deploying the CMM daily content moderation validation flow in Power Automate.

This flow provides automated orchestration and alerting for the Content Moderation Governance Monitor solution. It runs daily at 6:00 AM UTC, executes the Azure Automation runbook, detects drift from baseline moderation configurations, and routes alerts to Microsoft Teams and email based on severity.

**What this flow does:**

- Triggers daily at 6:00 AM UTC (configurable)
- Executes `Start-ModerationValidationRunbook.ps1` in Azure Automation
- Parses validation results including per-agent moderation drift detection
- Writes validation results to Dataverse immutable audit trail (all scans, not just failures)
- Posts adaptive card to Teams for Critical/Failed/Error severity
- Sends email to distribution list for all drift alerts
- Handles errors with CRITICAL email notification

## Prerequisites

Before creating the flow, ensure you have:

- [ ] **Azure Automation Account** with:
  - `Start-ModerationValidationRunbook.ps1` imported as a PowerShell 7.2 runbook
  - Certificate uploaded (Certificates blade)
  - Modules installed: MSAL.PS
  - Application permissions granted as required by Power Platform admin APIs
- [ ] **Dataverse environment** with CMM schema deployed (Phase 2):
  - 3 tables: `fsi_moderationvalidationhistory`, `fsi_moderationbaselines`, `fsi_moderationviolations`
  - 7 environment variables configured
  - 4 connection references created
- [ ] **Microsoft Teams** channel for alert notifications
- [ ] **Email distribution list** for compliance alerts
- [ ] **Power Automate Premium license** (required for Azure Automation connector)
- [ ] **Connection references** bound in Power Automate:
  - `fsi_cr_dataverse_moderationmonitor` (Dataverse)
  - `fsi_cr_teams_moderationmonitor` (Microsoft Teams)
  - `fsi_cr_office365_moderationmonitor` (Office 365 Outlook)
  - Azure Automation connection to your subscription

## Step 1: Import Flow

### Option A: Import from JSON (Recommended)

1. Navigate to [make.powerautomate.com](https://make.powerautomate.com)
2. Select your target environment (same environment where CMM schema is deployed)
3. Click **My flows** > **Import** > **Import Package (Legacy)**
4. Upload `src/moderation-validation-flow.json` from this repository
5. Map connection references:
   - **Azure Automation** — Create new connection or select existing
   - **Microsoft Teams** — `fsi_cr_teams_moderationmonitor`
   - **Office 365 Outlook** — `fsi_cr_office365_moderationmonitor`
   - **Dataverse** — `fsi_cr_dataverse_moderationmonitor`
6. Click **Import**

### Option B: Manual Creation

If importing fails or you need to customize the flow:

1. Go to [make.powerautomate.com](https://make.powerautomate.com)
2. Click **Create** > **Scheduled cloud flow**
3. Name: `CMM - Content Moderation Validation (Daily)`
4. Set schedule:
   - Start: Today
   - Repeat every: **1 Day**
   - At: **6:00 AM**
   - Time zone: **UTC**
5. Click **Create**
6. Follow the flow structure defined in `src/moderation-validation-flow.json`

## Step 2: Configure Variables

Update these variables in the flow designer (Initialize Variable actions):

> **Note:** These variables are currently hardcoded as `InitializeVariable` actions in the flow JSON. The solution already deploys `fsi_CMM_TeamsGroupId` and `fsi_CMM_TeamsChannelId` as Dataverse environment variables. For multi-environment portability, consider migrating flow variables to Dataverse environment variable lookups (via the Dataverse connector) so the flow does not require manual editing per environment.

| Variable | Type | Default Value | Description |
|----------|------|---------------|-------------|
| `DataverseUrl` | String | `your-dataverse-url-here` | Your Dataverse environment URL (where CMM schema is deployed). **Must be changed per environment.** |
| `TenantId` | String | `contoso.onmicrosoft.com` | Microsoft Entra ID tenant identifier |
| `ClientId` | String | `your-client-id-here` | App registration client ID (same one used for certificate auth) |
| `CertificateThumbprint` | String | `your-thumbprint` | Certificate thumbprint uploaded to Azure Automation |
| `SubscriptionId` | String | `your-subscription-id-here` | Azure subscription containing Automation Account |
| `ResourceGroup` | String | `rg-content-moderation-monitor` | Resource group with Automation Account |
| `AutomationAccount` | String | `aa-content-moderation-monitor` | Azure Automation Account name |
| `TeamsGroupId` | String | `your-group-id-here` | Teams group (team) ID for moderation alerts |
| `TeamsChannelId` | String | `your-channel-id-here` | Teams channel ID for moderation alerts (get from channel link) |
| `ComplianceDistributionList` | String | `alerts@your-org.com` | Email distribution list for all alerts |

**How to get Teams Channel ID:**

1. In Microsoft Teams, right-click the channel > **Get link to channel**
2. The URL format is: `...teams.microsoft.com/l/channel/[CHANNEL_ID]/...`
3. Copy the CHANNEL_ID portion (starts with `19:`)

**How to get Teams Group ID:**

1. In Microsoft Teams, right-click the team > **Get link to team**
2. The URL contains the group ID in the `groupId` parameter

**How to get Dataverse URL:**

1. Navigate to [make.powerapps.com](https://make.powerapps.com)
2. Select your environment
3. Click **Settings** (gear icon) > **Session details**
4. Copy the **Instance url** (e.g., `https://org.crm.dynamics.com`)

## Step 3: Bind Connection References

The flow uses four connection references deployed during Phase 2:

| Connection Reference | Service | Purpose |
|---------------------|---------|---------|
| `fsi_cr_dataverse_moderationmonitor` | Dataverse | Write validation history records |
| `fsi_cr_teams_moderationmonitor` | Microsoft Teams | Post adaptive card alerts |
| `fsi_cr_office365_moderationmonitor` | Office 365 Outlook | Send email alerts |
| `fsi_cr_azureautomation_moderationmonitor` | Azure Automation | Execute validation runbook |

**To bind connection references:**

1. In Power Automate, open the flow
2. Click **Edit**
3. For each action that shows a connection warning:
   - Click the action
   - Select the appropriate connection from the dropdown
   - If no connection exists, click **Add new connection** and authenticate
4. Save the flow

## Step 4: Validation History Persistence

> **Important:** Validation history persistence to Dataverse is handled by the **PowerShell runbook** (`Start-ModerationValidationRunbook.ps1`) using the `-PersistResults` switch and `Write-ModerationValidationHistory` in `CMMClient.psm1` — **not** by the Power Automate flow itself. The flow's role is orchestration and alerting; the flow goes directly from `Parse_Results` to `Check_Alert_Required`.

**Dataverse table:** `fsi_ModerationValidationHistory` (OrganizationOwned, immutable)

**How persistence works:**

1. The flow triggers `Start-ModerationValidationRunbook.ps1` via Azure Automation
2. The runbook calls `Write-ModerationValidationHistory` (in `CMMClient.psm1`) to persist scan results to Dataverse
3. The flow receives the runbook output JSON, parses it (`Parse_Results`), and evaluates alert conditions (`Check_Alert_Required`)

**Troubleshooting validation history writes:**

| Error Code | Cause | Resolution |
|-----------|-------|------------|
| 403 Forbidden | Runbook identity lacks Create permission on `fsi_ModerationValidationHistory` | Assign security role with Organization-level Create on the table |
| 404 Not Found | Table not deployed to environment | Deploy Dataverse schema from Phase 2 (`scripts/deploy.py`) |
| 400 Bad Request | Schema mismatch (column names don't match) | Verify column names match the schema deployed in Phase 2 |

## Step 5: Test the Flow

### 5.1 Manual Test Run

1. Click **Test** in the flow editor
2. Select **Manually**
3. Click **Test** to start
4. Monitor the flow run in real-time

### 5.2 Verify Each Step

Watch for these key actions to complete successfully:

- **Create_Automation_Job**: Runbook job created (returns jobId)
- **Wait_For_Job**: Job status polling (max 2 hours, 30-second intervals)
- **Get_Job_Output**: JSON output retrieved from completed runbook (includes Dataverse persistence by the runbook)
- **Parse_Results**: JSON schema validation passes
- **Check_Alert_Required**: Condition evaluates based on AlertRequired flag
- **Post_Teams_Card** (if Critical/Failed/Error): Adaptive card posted to Teams
- **Send_Alert_Email** (if alert required): Email sent to distribution list

### 5.3 Expected Outcomes

**If validation passes (no violations, no drift):**

- Flow completes successfully
- No Teams card posted
- No email sent
- Validation history record written to Dataverse by the runbook
- Check Azure Automation job output for `"OverallStatus": "Passed"`

**If validation fails or drift detected:**

- Flow completes successfully
- **Critical/Failed/Error**: Teams card posted + email sent (High importance)
- **High/Warning**: Email sent only (Normal importance)
- Validation history record written to Dataverse by the runbook
- Check Teams channel for adaptive card with per-agent violation and drift details
- Check email for HTML table with zone summary, agent violations, and drift detection

## Step 6: Enable Daily Schedule

1. After successful test, the Recurrence trigger activates automatically
2. Flow runs daily at 6:00 AM UTC
3. Monitor first 3 days of automated runs for consistency
4. Check run history: **My flows** > **CMM - Content Moderation Validation (Daily)** > **Run history**

## Step 7: Capture Initial Baseline

After the flow is running, capture the initial baseline for drift detection:

```powershell
# Run from PowerShell with MSAL.PS installed

.\Invoke-ModerationBaselineCapture.ps1 `
    -TenantId "your-tenant.onmicrosoft.com" `
    -ClientId "your-client-id" `
    -DataverseUrl "https://your-org.crm.dynamics.com" `
    -Interactive
```

**Why this matters:**

- The first validation run will show `IsFirstRun: true` for all agents
- Drift detection requires a baseline to compare against
- Without a baseline, the runbook skips drift detection per agent
- Capture baseline after confirming your content moderation settings are correctly configured

**Re-capture baselines when:**

- You make approved changes to agent content moderation levels
- You update zone-specific moderation policies
- You add new agents to a governance zone
- After any intentional change to Zone 1/2/3 moderation configuration

**Zone-specific capture:**

```powershell
# Capture only Zone 3 agents (highest risk)
.\Invoke-ModerationBaselineCapture.ps1 `
    -TenantId "your-tenant.onmicrosoft.com" `
    -ClientId "your-client-id" `
    -DataverseUrl "https://your-org.crm.dynamics.com" `
    -Zone 3 `
    -Interactive
```

## Alert Routing Summary

The flow routes alerts based on the `AlertRequired` flag set by the runbook. Only Critical/High violations or weakened drift set `AlertRequired = true`. Medium-severity violations produce a Warning overall status but do **not** trigger alerts — these are recorded in Dataverse validation history only.

| Severity | Teams Card | Email | Email Importance | Notes |
|----------|-----------|-------|-----------------|-------|
| Critical | Yes | Yes | High | |
| Failed | Yes | Yes | High | |
| Error | Yes | Yes | High | |
| High | No | Yes | Normal | |
| Medium | No | No | — | Recorded in Dataverse only; no active alert |
| Warning | No | No | — | Recorded in Dataverse only; no active alert |
| Passed/Info | No | No | — | |

## Known Limitations

### Retry Policies

The seven API connection actions (`Create_Automation_Job`, `Get_Job_Status`, `Get_Job_Output`, `Post_Teams_Card`, `Send_Alert_Email`, `Send_Job_Failure_Email`, `Send_Critical_Error_Email`) have explicit retry policies configured (fixed interval, 3 retries, 30-second delay). These were added to handle transient connector failures (e.g., Teams throttling, temporary Automation API errors) in production governance workflows.

### Environment Variables vs Flow Variables

Flow configuration is currently stored as `InitializeVariable` actions rather than reading from Dataverse environment variables at runtime. The solution deploys environment variables (e.g., `fsi_CMM_TeamsGroupId`, `fsi_CMM_TeamsChannelId`) but the flow does not yet consume them. Migrating to `Get Environment Variable Value` actions would require adding a Dataverse connector reference and rewiring downstream variable references. See [Step 2: Configure Variables](#step-2-configure-variables) for the current approach.

## Troubleshooting

### Dataverse Write Failures

See the **Validation History Persistence** section above for error code resolution (403, 404, 400).

Additional checks:
- Confirm the runbook identity has Create permission on `fsi_ModerationValidationHistory`
- Check that column names in `CMMClient.psm1` match the deployed schema exactly

### Azure Automation Job Failures

- **Job stuck in "Running"**: Check Azure Automation job logs; may be waiting for module install
- **Job completes but output is empty**: Verify runbook parameters, check Write-Verbose output
- **Authentication errors**: Verify certificate thumbprint, check certificate expiration
- **Module not found**: Install MSAL.PS in Automation Account (Modules blade)
- **Timeout (2-hour limit)**: The Wait_For_Job loop times out after 2 hours; increase if scanning many agents

### Teams Channel Not Found

- Verify `TeamsGroupId` and `TeamsChannelId` variables match your target channel
- Confirm the Teams connection has permissions to post to the channel
- Check that `fsi_cr_teams_moderationmonitor` connection reference is properly bound
- Test channel posting manually in Power Automate to isolate permissions issues

### Parse JSON Schema Mismatch

- The Parse_Results schema must match the runbook output structure exactly
- If the runbook output changes (e.g., new fields added), update the schema in the flow
- Check Get_Job_Output action output for the raw JSON to debug
- Key CMM schema differences from other monitors: `TotalAgents` field, agent-level violations with `ExpectedModerationLevel`/`ActualModerationLevel`, `Drift` as an object (not array) with `Details` array

### No Violations Detected but Alert Sent

- Check the `AlertRequired` logic in the runbook — drift alone can trigger alerts
- Review `AlertSeverity` in the runbook output to understand the classification
- Verify zone assignments are current via ELM zone classification or naming convention

### Drift Detection Shows All Agents as First Run

- Baselines have not been captured yet
- Run `Invoke-ModerationBaselineCapture.ps1` to establish initial baselines
- After capture, the next scan will compare against the baseline and detect actual drift

### Adaptive Card Template Updates

> **Note:** The adaptive card exists in two versions: (1) a **standalone template** at `src/adaptive-card-moderation-alert.json` with full features (Violations section, Drift Detection section, `${DocumentationUrl}` placeholder) for reference and testing in the [Adaptive Card Designer](https://adaptivecards.io/designer/), and (2) a **simplified inline version** in the flow JSON `Post_Teams_Card` action adapted for Power Automate's `replace()` expression constraints (FactSet-based zone summary, hardcoded documentation URL). The inline version intentionally omits the Violations and Drift Detection sections because per-agent detail binding requires `$data` templating not supported by Power Automate's expression language. When updating the card structure (header, Run Summary, Zone Summary, actions), changes should be applied to both locations where applicable.

### Flow Errors (Scope_Catch)

- If you receive a "[CRITICAL] CMM Flow Execution Failed" email, the flow itself encountered an error
- Check the flow run history for the specific action that failed
- Common causes: expired connections, permission changes, Azure Automation account unavailable
