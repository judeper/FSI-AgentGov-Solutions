# Agent Access Governance Monitor - Flow Setup Guide

## Overview

Step-by-step guide for deploying the AAM daily agent access validation flow in Power Automate.

This flow provides automated orchestration and alerting for the Agent Access Governance Monitor solution. It runs daily, surfaces drift from baseline configurations, and routes alerts to Microsoft Teams and email based on severity.

> **Deferred Azure Automation (lab model).** For the lab, the validation runbook
> (`Start-AccessValidationRunbook.ps1`) runs **standalone** on a workstation or build
> agent (PowerShell 7.4 via Windows Task Scheduler) and writes results to Dataverse. No
> Azure subscription, Automation Account, premium connector, or always-on service
> principal is required. The daily Power Automate flow is reduced to a **Recurrence
> trigger + a Dataverse read** of the validation-history and violation tables, plus
> alert routing. The Azure Automation path described in some steps below is an
> **optional production upgrade**, not a lab prerequisite — promoting to it later is a
> packaging step, not a code change.

**What this flow does (lab model):**

- Triggers daily on a Recurrence schedule (configurable)
- Reads the latest validation-history and violation rows the standalone runbook wrote to Dataverse
- Surfaces per-environment drift recorded by the runbook
- Writes validation results to the Dataverse append-only audit log (by role design — all scans, not just failures; the runbook performs the write)
- Posts adaptive card to Teams for Critical/Failed/Error severity
- Sends email to distribution list for all drift alerts
- Handles errors with CRITICAL email notification

> **Maintenance Note:** The adaptive card JSON files (`adaptive-card-access-alert.json`, `adaptive-card-zone-access-alert.json`) provide design-time templates for the cards embedded in the flow. If you modify these templates, update the corresponding adaptive card payloads in the flow actions as well to avoid template drift.

## Prerequisites

Before creating the flow, ensure you have:

- [ ] **Standalone runbook host (lab default)**:
  - PowerShell 7.4 on a workstation or build agent
  - `Start-AccessValidationRunbook.ps1` scheduled via Windows Task Scheduler (`pwsh -File ...`)
  - `Microsoft.PowerApps.Administration.PowerShell` module installed
  - Modern OAuth app registration (public-client for `-Interactive` device-code, or a confidential app with a secret for unattended runs). Certificate-thumbprint auth is **not** used — it required the archived MSAL.PS module.
  - Power Platform admin and Dataverse permissions granted to the app
- [ ] **(Optional, production) Azure Automation Account** — only if promoting the runbook off the local host later:
  - `Start-AccessValidationRunbook.ps1` imported as a PowerShell 7.4 runbook
  - `Microsoft.PowerApps.Administration.PowerShell` module installed
  - A managed identity (preferred) or service-principal secret for unattended auth
- [ ] **Dataverse environment** with AAM schema deployed (run `python scripts/deploy.py`)
- [ ] **Runbook identity** configured for Dataverse access:
  - Prefer managed identity where your Power Platform/Dataverse automation supports it; otherwise use a service-principal secret (dev-only legacy fallback) configured for `Start-AccessValidationRunbook.ps1`.
  - The runbook identity has Create permission on the `fsi_accessvalidationhistory` table and Create permission on `fsi_accessviolations` when persisting violations.
  - Assign System Administrator, or a custom role with the required organization-level table privileges.
- [ ] **Microsoft Teams** channel for alert notifications
- [ ] **Email distribution list** for compliance alerts
- [ ] **Connection references** bound in Power Automate:
  - `fsi_cr_teams_accessmonitor` (Microsoft Teams)
  - `fsi_cr_office365_accessmonitor` (Office 365 Outlook)
  - Azure Automation connection to your subscription

## Step 1: Create the Flow

> **Note:** The flow JSON file (`access-validation-flow.json`) was removed per the Solution Content Policy. Build the flow manually in Power Automate designer following the steps below.

1. Go to [make.powerautomate.com](https://make.powerautomate.com)
2. Select your target environment (same environment where AAM schema is deployed)
3. Click **Create** > **Scheduled cloud flow**
4. Name: `AAM - Agent Access Validation (Daily)`
5. Set schedule:
   - Start: Today
   - Repeat every: **1 Day**
   - At: **6:00 AM**
   - Time zone: **UTC**
6. Click **Create**

## Step 2: Configure Variables

Update these variables in the flow designer (Initialize Variable actions):

| Variable | Type | Default Value | Description |
|----------|------|---------------|-------------|
| `DataverseUrl` | String | `https://governance.crm.dynamics.com` | Your Dataverse environment URL (where AAM schema is deployed; the flow reads validation results from here) |
| `TeamsGroupId` | String | `your-group-id-here` | Teams group (team) ID for drift alerts |
| `TeamsChannelId` | String | `your-channel-id-here` | Teams channel ID for drift alerts (get from channel link) |
| `ComplianceDistributionList` | String | `alerts@your-org.com` | Email distribution list for all alerts |

> **Production-only (optional Azure Automation upgrade).** The variables below apply
> **only** if you later trigger the runbook from Azure Automation instead of the local
> Task Scheduler host. They are **not** needed for the lab model, where the standalone
> runbook writes to Dataverse and the flow only reads.
>
> | Variable | Type | Description |
> |----------|------|-------------|
> | `TenantId` | String | Microsoft Entra ID tenant identifier |
> | `ClientId` | String | App registration client ID for the runbook identity |
> | `SubscriptionId` | String | Azure subscription containing the Automation Account |
> | `ResourceGroup` | String | Resource group with the Automation Account |
> | `AutomationAccount` | String | Azure Automation Account name |

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

In the lab model the flow uses **three** connection references — the standalone runbook writes results to Dataverse, and the flow **reads** Dataverse and routes alerts:

| Connection Reference | Service | Purpose |
|---------------------|---------|---------|
| `fsi_cr_dataverse_accessmonitor` | Microsoft Dataverse | Read validation-history and violation rows the runbook wrote |
| `fsi_cr_teams_accessmonitor` | Microsoft Teams | Post adaptive card alerts |
| `fsi_cr_office365_accessmonitor` | Office 365 Outlook | Send email alerts |

> **Production-only (optional Azure Automation upgrade).** If you trigger the runbook
> from Azure Automation instead of the local host, add a third connection reference,
> `fsi_cr_azureautomation_accessmonitor` (Azure Automation), to trigger and monitor
> runbook jobs. It is configured manually in Power Automate when binding the Azure
> Automation actions and is not created by the `create_connection_references.py`
> script. This connection requires a Power Automate Premium license; the lab model does
> not.

**To bind connection references:**

1. In Power Automate, open the flow
2. Click **Edit**
3. For each action that shows a connection warning:
   - Click the action
   - Select the appropriate connection from the dropdown
   - If no connection exists, click **Add new connection** and authenticate
4. Save the flow

## Step 4: Validation History Write

> **Why this step matters:** Every scan result is persisted to Dataverse for regulatory audit trail requirements (supports compliance with FINRA 4511, SEC 17a-3). Dataverse persistence is performed by the runbook (`Start-AccessValidationRunbook.ps1` via `-PersistResults`), **before** alerting, so alert delivery failures do not hide the write attempt.

**Dataverse table:** `fsi_accessvalidationhistory` (OrganizationOwned; append-only by role design — see [role-design-append-only.md](role-design-append-only.md))

**Connection reference:** `fsi_cr_dataverse_accessmonitor`

**Column mapping:**

| Flow Expression | Dataverse Column | Type |
|----------------|------------------|------|
| `"Scan-" + Timestamp` | `fsi_name` | String |
| `guid()` | `fsi_runid` | String (GUID) |
| `OverallStatus` | `fsi_overallstatus` | String |
| `length(Violations)` | `fsi_violationcount` | Integer |
| `TotalEnvironments` | `fsi_totalenvironments` | Integer |
| Full JSON output | `fsi_summaryjson` | Memo |
| `Timestamp` | `fsi_validationtime` | DateTime |

**Troubleshooting validation history writes:**

| Error Code | Cause | Resolution |
|-----------|-------|------------|
| 403 Forbidden | Identity lacks Create permission on `fsi_accessvalidationhistory` | Assign security role with Organization-level Create on the table |
| 404 Not Found | Table not deployed to environment | Run `python scripts/deploy.py` to deploy Dataverse schema |
| 400 Bad Request | Schema mismatch (column names don't match) | Verify column names match the schema deployed in Phase 2 |

**Important:** Dataverse persistence is handled by the runbook (via `-PersistResults`), not by a flow action. The flow proceeds to alerting based on the parsed runbook output regardless of persistence outcome.

## Step 5: Test the Flow

### 5.1 Manual Test Run

1. Click **Test** in the flow editor
2. Select **Manually**
3. Click **Test** to start
4. Monitor the flow run in real-time

### 5.2 Verify Each Step

Watch for these key actions to complete successfully:

- **Recurrence**: Trigger fires on schedule
- **List_Validation_History**: Latest validation-history rows retrieved from Dataverse (written by the standalone runbook)
- **List_Violations**: Open violation rows retrieved from Dataverse
- **Parse_Results**: Row data shaped for alert routing
- **Check_Alert_Required**: Condition evaluates based on the latest run's severity
- **Post_Teams_Card** (if Critical/Failed/Error): Adaptive card posted to Teams
- **Send_Alert_Email** (if alert required): Email sent to distribution list

> **Production-only (Azure Automation upgrade):** when triggering the runbook from
> Azure Automation, the flow also includes **Create_Automation_Job** (returns jobId),
> **Wait_For_Job** (status polling), and **Get_Job_Output** (retrieve JSON) ahead of
> Parse_Results.

### 5.3 Expected Outcomes

**If validation passes (no drift):**

- Flow completes successfully
- No Teams card posted
- No email sent
- Validation history record present in Dataverse (written by the runbook)
- The latest `fsi_accessvalidationhistory` row shows `"OverallStatus": "Passed"`

**If validation fails or drift detected:**

- Flow completes successfully
- **Critical/Failed/Error**: Teams card posted + email sent (High importance)
- **High/Warning**: Email sent only (Normal importance)
- Validation history record written to Dataverse
- Check Teams channel for adaptive card with violation and drift details
- Check email for HTML table with zone summary and violation details

## Step 6: Enable Daily Schedule

1. After successful test, the Recurrence trigger activates automatically
2. Flow runs daily at 6:00 AM UTC
3. Monitor first 3 days of automated runs for consistency
4. Check run history: **My flows** > **AAM - Agent Access Validation (Daily)** > **Run history**

## Step 7: Capture Initial Baseline

After the flow is running, capture the initial baseline for drift detection:

```powershell
# Run from PowerShell 7.4 (modern OAuth via Get-AAMAccessToken; no MSAL.PS required)

.\Invoke-AccessBaselineCapture.ps1 `
    -TenantId "your-tenant.onmicrosoft.com" `
    -ClientId "your-client-id" `
    -DataverseUrl "https://your-org.crm.dynamics.com" `
    -Interactive
```

**Why this matters:**

- The first validation run will show `IsFirstRun: true` for all environments
- Drift detection requires a baseline to compare against
- Without a baseline, the runbook skips drift detection per environment
- Capture baseline after confirming your Power Platform access settings are correctly configured

**Re-capture baselines when:**

- You make approved changes to agent sharing scope settings
- You update environment access governance policies
- You add new environments to a governance zone
- After any intentional change to Zone 1/2/3 agent access configuration

**Zone-specific capture:**

```powershell
# Capture only Zone 3 environments (highest risk)
.\Invoke-AccessBaselineCapture.ps1 `
    -TenantId "your-tenant.onmicrosoft.com" `
    -ClientId "your-client-id" `
    -DataverseUrl "https://your-org.crm.dynamics.com" `
    -Zone 3 `
    -Interactive
```

## Alert Routing Summary

| Severity | Teams Card | Email | Email Importance |
|----------|-----------|-------|-----------------|
| Critical | Yes | Yes | High |
| Failed | Yes | Yes | High |
| Error | Yes | Yes | High |
| High | No | Yes | Normal |
| Warning | No | Yes | Normal |
| Passed/Info | No | No | - |

## Troubleshooting

### Runbook Execution Failures (local host)

- **Scheduled task did not run**: Check Task Scheduler history; verify the `pwsh -File` action path and that the host was powered on at the scheduled time
- **Run completes but output is empty**: Verify runbook parameters, check Write-Verbose output
- **Authentication errors**: Re-run `-Interactive` to refresh the device-code sign-in, or verify the service-principal secret has not expired
- **Module not found**: Install Microsoft.PowerApps.Administration.PowerShell (`Install-Module Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser`)

> **Production-only:** when running under Azure Automation, check the Automation job
> logs instead; a job stuck in "Running" may be waiting for a module install, and
> authentication errors point at the managed identity or service-principal secret.

### Teams Channel Not Found

- Verify `TeamsGroupId` and `TeamsChannelId` variables
- Confirm the Teams connection has permissions to post to the channel
- Check that `fsi_cr_teams_accessmonitor` connection reference is properly bound

### Parse JSON Schema Mismatch

- The Parse_Results schema must match the runbook output structure
- If the runbook output changes, update the schema in the flow
- Check Get_Job_Output action output for the raw JSON to debug

### Dataverse Write Failures

See the **Validation History Write** section above for error code resolution.

### Flow Errors (Scope_Catch)

- If you receive a "[CRITICAL] AAM Flow Execution Failed" email, the flow itself encountered an error
- Check the flow run history for the specific action that failed
- Common causes: expired connections, permission changes, Azure Automation account unavailable
