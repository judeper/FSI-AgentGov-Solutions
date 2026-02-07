# Session Security Configurator - Flow Setup Guide

## Overview

Step-by-step guide for deploying the SSC daily session validation flow in Power Automate.

This flow provides automated orchestration and alerting for the Session Security Configurator solution. It runs daily at 6:00 AM UTC, executes the Azure Automation runbook, detects drift from baseline configurations, and routes alerts to Microsoft Teams and email based on severity.

**What this flow does:**

- Triggers daily at 6:00 AM UTC (configurable)
- Executes `Start-SessionValidationRunbook.ps1` in Azure Automation
- Parses validation results with drift detection
- Posts adaptive card to Teams for Failed/Error severity
- Sends email to distribution list for all drift alerts
- Handles errors with CRITICAL email notification

## Prerequisites

Before creating the flow, ensure you have:

- [ ] **Azure Automation Account** with:
  - Start-SessionValidationRunbook.ps1 imported as a PowerShell 7.2 runbook
  - Certificate uploaded (Certificates blade)
  - Modules installed: Microsoft.Graph.Identity.SignIns, MSAL.PS
  - Application permissions granted: Policy.Read.All, Directory.Read.All
- [ ] **Dataverse environment** with SSC schema deployed (run `python scripts/deploy.py`)
- [ ] **Microsoft Teams** channel for alert notifications
- [ ] **Email distribution list** for compliance alerts
- [ ] **Power Automate Premium license** (required for Azure Automation connector)
- [ ] **Connection references** bound in Power Automate:
  - fsi_cr_teams_sessionvalidation (Microsoft Teams)
  - fsi_cr_office365_sessionvalidation (Office 365 Outlook)
  - Azure Automation connection to your subscription

## Step 1: Import Flow

### Option A: Import from JSON (Recommended)

1. Navigate to [make.powerautomate.com](https://make.powerautomate.com)
2. Select your target environment (same environment where SSC schema is deployed)
3. Click **My flows** > **Import** > **Import Package (Legacy)**
4. Upload `src/session-validation-flow.json` from this repository
5. Map connection references:
   - **Azure Automation** → Create new connection or select existing
   - **Microsoft Teams** → fsi_cr_teams_sessionvalidation
   - **Office 365 Outlook** → fsi_cr_office365_sessionvalidation
6. Click **Import**

### Option B: Manual Creation

If importing fails or you need to customize the flow:

1. Go to [make.powerautomate.com](https://make.powerautomate.com)
2. Click **Create** > **Scheduled cloud flow**
3. Name: `SSC - Session Validation (Daily)`
4. Set schedule:
   - Start: Today
   - Repeat every: **1 Day**
   - At: **6:00 AM**
   - Time zone: **UTC**
5. Click **Create**
6. Follow the flow structure defined in `src/session-validation-flow.json`

## Step 2: Configure Variables

Update these variables in the flow designer (Initialize Variable actions):

| Variable | Type | Default Value | Description |
|----------|------|---------------|-------------|
| DataverseUrl | String | https://governance.crm.dynamics.com | Your Dataverse environment URL (where SSC schema is deployed) |
| TenantId | String | contoso.onmicrosoft.com | Azure AD tenant identifier |
| ClientId | String | your-client-id-here | App registration client ID (same one used for certificate auth) |
| CertificateThumbprint | String | your-thumbprint | Certificate thumbprint uploaded to Azure Automation |
| SubscriptionId | String | your-subscription-id-here | Azure subscription containing Automation Account |
| ResourceGroup | String | rg-session-validation | Resource group with Automation Account |
| AutomationAccount | String | aa-session-validator | Azure Automation Account name |
| TeamsChannelId | String | your-channel-id-here | Teams channel ID for drift alerts (get from channel link) |
| ComplianceDistributionList | String | alerts@your-org.com | Email distribution list for all alerts |
| Zone | String | Zone3 | Governance zone to validate (Zone1, Zone2, or Zone3) |

**How to get Teams Channel ID:**

1. In Microsoft Teams, right-click the channel > **Get link to channel**
2. The URL format is: `...teams.microsoft.com/l/channel/[CHANNEL_ID]/...`
3. Copy the CHANNEL_ID portion (starts with `19:`)

**How to get Dataverse URL:**

1. Navigate to [make.powerapps.com](https://make.powerapps.com)
2. Select your environment
3. Click **Settings** (gear icon) > **Session details**
4. Copy the **Instance url** (e.g., `https://org.crm.dynamics.com`)

## Step 3: Test the Flow

### 3.1 Manual Test Run

1. Click **Test** in the flow editor
2. Select **Manually**
3. Click **Test** to start
4. Monitor the flow run in real-time

### 3.2 Verify Each Step

Watch for these key actions to complete successfully:

- **Create_Automation_Job**: Runbook job created (returns jobId)
- **Wait_For_Job**: Job status polling (max 2 hours, 30-second intervals)
- **Get_Job_Output**: JSON output retrieved from completed runbook
- **Parse_Results**: JSON schema validation passes
- **Check_Alert_Required**: Condition evaluates based on AlertRequired flag
- **Post_Teams_Card** (if Failed/Error): Adaptive card posted to Teams
- **Send_Alert_Email** (if alert required): Email sent to distribution list

### 3.3 Expected Outcomes

**If validation passes (no drift):**
- Flow completes successfully
- No Teams card posted
- No email sent
- Check Azure Automation job output for "OverallStatus": "Passed"

**If validation fails or drift detected:**
- Flow completes successfully
- **Failed/Error**: Teams card posted + email sent (High importance)
- **Warning**: Email sent only (Normal importance)
- Check Teams channel for adaptive card with drift details
- Check email for HTML table with validator results

## Step 4: Enable Daily Schedule

1. After successful test, the Recurrence trigger activates automatically
2. Flow runs daily at 6:00 AM UTC
3. Monitor first 3 days of automated runs for consistency
4. Check run history: **My flows** > **SSC - Session Validation (Daily)** > **Run history**

**Best practice:** Stagger zone validations if running multiple flows:
- Zone 1: 6:00 AM UTC
- Zone 2: 6:15 AM UTC
- Zone 3: 6:30 AM UTC

This avoids Azure Automation load spikes and makes debugging easier.

## Step 5: Capture Initial Baseline

After the flow is running, capture the initial baseline for drift detection:

```powershell
# Run from PowerShell 7 with Graph SDK and MSAL.PS installed

.\Invoke-BaselineCapture.ps1 `
    -Zone Zone3 `
    -DataverseUrl "https://your-org.crm.dynamics.com" `
    -TenantId "your-tenant.onmicrosoft.com" `
    -ClientId "your-client-id" `
    -CertificateThumbprint "your-cert-thumbprint" `
    -Interactive
```

**Why this matters:**

- The first validation run will have `IsFirstRun: true` in the output
- Drift detection requires a baseline to compare against
- Without a baseline, every non-Passed result triggers an alert
- Capture baseline after confirming your CA policies are correctly configured

**Re-capture baselines when:**

- You make approved changes to session controls CA policies
- You update authentication strength requirements
- You modify PIM role settings for privileged roles
- After any intentional change to Zone 1/2/3 session security configuration

## Multi-Zone Deployment

To validate all three zones, create three flow instances:

### Clone and Configure

1. In Power Automate, select the original flow
2. Click **Save As** to create a copy
3. Rename: `SSC - Session Validation Zone1 (Daily)`
4. Update the **Zone** variable to `Zone1`
5. Update the **ResourceGroup** variable if using separate Automation Accounts per zone
6. Adjust schedule to stagger start times (e.g., 6:00, 6:15, 6:30 AM UTC)
7. Repeat for Zone 2

### Optional: Zone-Specific Channels

For better alert organization:

- Create separate Teams channels: `#session-security-zone1`, `#session-security-zone2`, `#session-security-zone3`
- Update `TeamsChannelId` variable in each flow to route to zone-specific channel
- Keep email distribution list the same (compliance team needs all alerts)

## Alert Routing Summary

The flow routes alerts based on validation status and drift detection:

| Condition | Teams Card | Email | Importance | Meaning |
|-----------|-----------|-------|-----------|---------|
| Failed | Yes | Yes | High | Session controls do not meet zone requirements |
| Error | Yes | Yes | High | Validation script encountered an error (infrastructure issue) |
| Warning | No | Yes | Normal | Minor drift or non-critical gap |
| Passed (with drift) | No | Yes | Normal | Configuration changed but still meets requirements |
| Passed (no drift) | No | No | — | Configuration stable, no alerts needed |
| Flow error | No | Yes (CRITICAL) | High | Power Automate flow itself failed |

**Drift detection logic:**

- Compares current validation status to most recent Passed baseline in Dataverse
- If no baseline exists: `IsFirstRun: true`, every non-Passed triggers alert
- If baseline exists: Drift detected when current status differs from baseline
- Fails open: If Dataverse query fails, assumes drift and sends alert

## Troubleshooting

### Flow Fails at Create_Automation_Job

**Symptom:** "ResourceNotFound" or "InvalidResourceReference" error

**Cause:** SubscriptionId, ResourceGroup, or AutomationAccount variables are incorrect

**Solution:**

1. Verify variable values match your Azure resources:
   ```bash
   # In Azure Portal, navigate to Automation Account
   # Note: Subscription ID, Resource Group name, Account name
   ```
2. Check Azure Automation connection is authenticated:
   - Click **Connections** in Power Automate
   - Find **Azure Automation** connection
   - Click **Edit** > **Test connection**
   - Re-authenticate if needed
3. Ensure runbook "Start-SessionValidationRunbook" exists in Automation Account

### Parse JSON Fails

**Symptom:** "InvalidTemplate" or schema validation error in Parse_Results action

**Cause:** Runbook output is not valid JSON or schema mismatch

**Solution:**

1. Check runbook output in Azure Portal:
   - **Automation Account** > **Jobs** > Select most recent job > **Output**
2. Verify output is pure JSON (no Write-Host statements in runbook)
3. Compare output schema to Parse JSON schema in flow:
   - Runbook should output: RunType, Timestamp, Zone, OverallStatus, Reason, Validators, Drift, AlertRequired, AlertSeverity
4. If schema changed, update Parse JSON schema to match

### No Teams Card Posted

**Symptom:** Email received, but Teams card not posted

**Cause:** Several possible reasons

**Solution:**

1. Verify `TeamsChannelId` variable is correct:
   - Right-click Teams channel > Get link to channel
   - Extract channel ID from URL (format: `19:xxxx...@thread.tacv2`)
2. Check Teams connection reference is bound:
   - **Solutions** > **Default Solution** > **Connection References**
   - Find `fsi_cr_teams_sessionvalidation`
   - Ensure status is **Connected**
3. Confirm `OverallStatus` is "Failed" or "Error":
   - Check Parse_Results output in flow run history
   - Teams card only posts for Failed/Error (Warning goes to email only)
4. Verify Teams Workflows app is installed in the team

### No Alerts Despite Drift

**Symptom:** Flow runs successfully, but no alerts sent

**Cause:** AlertRequired flag is false or drift not detected

**Solution:**

1. Check if baseline exists:
   ```powershell
   # Run Invoke-BaselineCapture.ps1 first to create baseline
   .\Invoke-BaselineCapture.ps1 -Zone Zone3 -DataverseUrl "..." -Interactive
   ```
2. Verify drift detection in runbook output:
   - Review job output in Azure Portal
   - Check `Drift.DriftDetected` and `Drift.IsFirstRun` values
3. Confirm `AlertRequired` is true in Parse_Results output
4. Review flow run history to see which condition branches were taken

### Email Distribution List Not Working

**Symptom:** Flow succeeds, but emails not delivered

**Cause:** Distribution list doesn't exist or isn't mail-enabled

**Solution:**

1. Verify distribution list in Exchange Online:
   ```powershell
   Get-DistributionGroup -Identity "compliance-alerts@contoso.com"
   ```
2. Check that it's mail-enabled and accepts external email
3. Test by sending a manual email to the distribution list
4. Verify membership includes expected recipients
5. Check spam/junk folders for initial test emails

### Runbook Times Out (Wait_For_Job exceeds 2 hours)

**Symptom:** Flow fails with "ActionTimedOut" error

**Cause:** Runbook execution exceeds 2-hour limit (very rare for SSC)

**Solution:**

1. Check runbook execution time in Azure Portal:
   - Typical SSC validation: 2-5 minutes
   - If > 30 minutes, investigate runbook performance
2. Verify Graph API queries are not timing out:
   - Check for throttling (HTTP 429 errors)
   - Review `Get-MgIdentityConditionalAccessPolicy` performance
3. Consider skipping PIM validation if permissions are limited:
   - Add `SkipPimValidation: true` to runbook parameters
4. If persistent, increase Wait_For_Job timeout limit in flow (max: 30 days)

### Certificate Authentication Failures

**Symptom:** Runbook fails with "Certificate not found" or "Authentication failed"

**Cause:** Certificate not uploaded to Azure Automation or thumbprint mismatch

**Solution:**

1. Verify certificate in Azure Automation:
   - **Automation Account** > **Certificates**
   - Check certificate exists and is not expired
2. Compare thumbprints:
   - Copy thumbprint from Azure Automation certificate
   - Update `CertificateThumbprint` variable in flow to match exactly
3. Ensure certificate has private key:
   ```powershell
   # Export certificate with private key when uploading to Azure Automation
   Export-PfxCertificate -Cert $cert -FilePath "cert.pfx" -Password $pwd
   ```
4. Verify app registration has correct permissions:
   - Policy.Read.All (Microsoft Graph)
   - Directory.Read.All (Microsoft Graph)
   - Permissions granted admin consent

## Related Documentation

- **RUNBOOK_REFERENCE.md** — Detailed runbook parameter reference
- **BASELINE_MANAGEMENT.md** — Best practices for baseline capture and updates
- **DATAVERSE_DEPLOYMENT.md** — SSC schema deployment guide
- **AUTHENTICATION.md** — Certificate-based authentication setup

---

**Version:** 1.0.0
**Last Updated:** 2026-02-07
**Solution:** Session Security Configurator
**Phase:** 3 - Automation and Alerting
