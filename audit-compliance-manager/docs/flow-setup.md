# Flow Setup Guide -- Audit Configuration Validator

## Overview

This guide covers creating three Power Automate flows that provide automated orchestration, alerting, and approval-gated remediation for the Audit Compliance Manager solution.

**Flows:**

1. **ACV - Tenant Audit Validation (Daily)** — Runs tenant-level validation at 6:00 AM UTC daily
2. **ACV - Environment Audit Validation (Daily)** — Runs environment-level validation at 7:00 AM UTC daily
3. **ALCA - Audit Remediation Approval (Weekly)** — Queries non-compliant environments every Monday at 7:00 AM ET, requests governance approval, then triggers remediation

The validation flows execute Azure Automation runbooks, detect drift from baseline configurations, and route alerts to Microsoft Teams and email based on severity. The remediation flow adds an approval gate before enabling audit logging on non-compliant environments.

**Phase 3 requirements addressed:**

- **AUTO-01:** Daily scheduled flows with Recurrence triggers (6 AM and 7 AM UTC)
- **AUTO-02:** Drift detection integrated via Compare-ValidationBaseline helper
- **AUTO-03:** Teams adaptive card alerts for Failed/Error severity
- **AUTO-04:** Email alerts to distribution list for all non-Passed drift detections

## Prerequisites

Before creating the flows, ensure you have:

- [ ] **Azure subscription** with Automation Account containing:
  - Start-TenantValidationRunbook.ps1 (imported as PowerShell 7.4 runbook)
  - Start-EnvironmentValidationRunbook.ps1 (imported as PowerShell 7.4 runbook)
  - Required PowerShell modules installed (Az.Accounts, ExchangeOnlineManagement 3.0.0-3.9.2, Microsoft.PowerApps.Administration.PowerShell 2.0.180 pinned)
  - Certificate uploaded for service principal authentication
- [ ] **Power Automate Premium license** (required for Azure Automation connector)
- [ ] **Microsoft Teams** with Workflows app installed and channel created for alerts
- [ ] **Exchange Online admin role** (for tenant validation)
- [ ] **Power Platform admin role** (for environment validation)
- [ ] **Dataverse environment** with ACV schema deployed (see [deployment-guide.md](deployment-guide.md))
- [ ] **Certificate-based authentication** configured:
  - Microsoft Entra ID App Registration with certificate
  - Exchange.ManageAsApp API permission (tenant validation)
  - SecurityEvents.Read.All API permission (Purview retention)
  - Power Platform Admin role (environment validation; Entra display name `Power Platform Administrator`)
  - Dataverse System Administrator role in central environment

## Architecture

```
Recurrence Trigger (Daily 6 AM / 7 AM UTC)
    ↓
Initialize Variables (DataverseUrl, TenantId, ClientId, etc.)
    ↓
Azure Automation: Create Job (Start-*ValidationRunbook)
    ↓
Wait For Job (Until loop, 30s delay, max 2 hours)
    ↓
Check Job Failed? → Yes → Send Error Email + Terminate
    ↓ No
Get Job Output (JSON)
    ↓
Parse JSON Results
    ↓
Drift Detection Logic (Compare to Baseline)
    ↓
Alert Routing:
    - Failed/Error → Teams Card + Email (High importance)
    - Warning/GracePeriod → Email (Normal importance)
    - Passed → No alert
```

## Step 1: Azure Automation Setup

### 1.1 Create Automation Account

1. Navigate to [Azure Portal](https://portal.azure.com)
2. Create new **Automation Account**:
   - Name: `aa-audit-validator` (or your preferred name)
   - Region: Same as your primary resources
   - System assigned identity: **Enabled**
3. After creation, navigate to **Certificates** and upload your authentication certificate

### 1.2 Import PowerShell Modules

Navigate to **Automation Account** > **Modules** > **Browse gallery** and import:

| Module | Version | Purpose |
|--------|---------|---------|
| Az.Accounts | 5.0+ | Dataverse Web API token acquisition for runbook drift checks |
| ExchangeOnlineManagement | 3.0.0-3.9.2 | Tenant-level audit configuration checks on current PowerShell 7.4 runtime |
| Microsoft.PowerApps.Administration.PowerShell | 2.0.180 (pinned known-good for ACM app-secret fallback) | Environment discovery and validation |

**Important:** Wait for each module to finish importing before starting the next one (status = "Available").

> **Power Apps compatibility note:** ACM currently pins
> `Microsoft.PowerApps.Administration.PowerShell` to `2.0.180` as the known-good
> version for the validated app-secret fallback path. In ACM evidence, `2.0.217`
> failed `Add-PowerAppsAccount` on that app-secret path with `AADSTS7000215`,
> while the same short-lived secret succeeded on `2.0.180`. Certificate-based
> validation on `2.0.217` succeeded in the same evidence set.

### 1.3 Import Runbooks

1. Navigate to **Automation Account** > **Runbooks** > **Import a runbook**
2. Upload **Start-TenantValidationRunbook.ps1**:
   - Runbook type: **PowerShell**
   - Runtime version: **7.4**
   - Name: `Start-TenantValidationRunbook`
3. Click **Import**, then **Publish**
4. Repeat for **Start-EnvironmentValidationRunbook.ps1**

**Important:** The runbook entry points depend on additional scripts that must also be uploaded to the same Azure Automation Account. Upload all of the following scripts maintaining the directory structure:

| Script | Directory | Purpose |
|--------|-----------|---------|
| `Invoke-TenantAuditValidation.ps1` | scripts/ | Tenant validation orchestrator |
| `Invoke-EnvironmentAuditValidation.ps1` | scripts/ | Environment validation orchestrator |
| `Invoke-EnvironmentDiscovery.ps1` | scripts/ | Environment discovery |
| `Test-UnifiedAuditLog.ps1` | scripts/ | UAL validator |
| `Test-MailboxAudit.ps1` | scripts/ | Mailbox audit validator |
| `Test-PurviewRetention.ps1` | scripts/ | Purview retention validator |
| `Test-EnvironmentAudit.ps1` | scripts/ | Environment audit validator |
| `Test-EnvironmentRetention.ps1` | scripts/ | Environment retention validator |
| `AuditComplianceHelpers.psm1` | scripts/ | Shared helper module (Invoke-WithRetry, etc.) |
| `AuditComplianceHelpers.psd1` | scripts/ | Module manifest |
| `Connect-PowerPlatform.ps1` | scripts/private/ | Authentication helper |
| `Write-ValidationResult.ps1` | scripts/private/ | Dataverse write helper |
| `Compare-ValidationBaseline.ps1` | scripts/private/ | Drift detection helper |
| `Get-ValidationResults.ps1` | scripts/private/ | Evidence query helper |

### 1.4 Configure Runbook Permissions

Grant the App Registration (service principal) the following permissions:

**Microsoft Graph API:**
- SecurityEvents.Read.All (for Purview retention policy queries)

**Exchange Online:**
- Exchange.ManageAsApp (for Get-AdminAuditLogConfig, Get-OrganizationConfig)

**Power Platform:**
- Power Platform Admin role (for Get-AdminPowerAppEnvironment; Entra display name `Power Platform Administrator`)

**Dataverse:**
- System Administrator role in central governance environment (for validation history writes)

See [deployment-guide.md](deployment-guide.md) for detailed permission configuration steps.

## Step 2: Power Automate Flow Creation

### 2.1 Create Tenant Validation Flow

1. Go to [make.powerautomate.com](https://make.powerautomate.com)
2. Click **Create** > **Scheduled cloud flow**
3. Name: `ACV - Tenant Audit Validation (Daily)`
4. Set schedule:
   - Start: Today
   - Repeat every: **1 Day**
   - At: **6:00 AM** (UTC timezone)
5. Click **Create**

**Add variable initializations:**

Add **Initialize variable** actions for each parameter:

- `DataverseUrl` (String): `https://governance.crm.dynamics.com` (your central environment)
- `TenantId` (String): `contoso.onmicrosoft.com` (your tenant ID)
- `ClientId` (String): Your Microsoft Entra ID application client ID
- `CertificateThumbprint` (String): Certificate thumbprint from Azure Automation
- `SubscriptionId` (String): Azure subscription ID
- `ResourceGroup` (String): `rg-audit-validation` (your resource group)
- `AutomationAccount` (String): `aa-audit-validator` (your automation account)
- `TeamsChannelId` (String): Teams channel ID for alerts
- `ComplianceDistributionList` (String): `compliance-alerts@example.com`
- `Zone` (String): `Zone3` (or Zone1/Zone2)
- `CanaryMailboxIdentity` (String, optional): shared mailbox or user mailbox UPN for service-principal canary validation (recommended for app-only runs)

**Add Scope - Try:**

1. Add **Scope** action named `Scope_Try`
2. Inside Scope_Try, add:

**a. Create Automation Job:**
- Action: **Azure Automation - Create job**
- Connection: Create new connection to your Azure subscription
- Subscription: Select your subscription
- Resource Group: `@{variables('ResourceGroup')}`
- Automation Account: `@{variables('AutomationAccount')}`
- Runbook Name: `Start-TenantValidationRunbook`
- Wait for job: **No**
- Parameters:
  ```json
  {
    "Zone": "@{variables('Zone')}",
    "DataverseUrl": "@{variables('DataverseUrl')}",
    "TenantId": "@{variables('TenantId')}",
    "ClientId": "@{variables('ClientId')}",
    "CertificateThumbprint": "@{variables('CertificateThumbprint')}",
    "CanaryMailboxIdentity": "@{variables('CanaryMailboxIdentity')}"
  }
  ```

**b. Wait For Job (Do Until loop):**
- Action: **Do until**
- Condition: `@or(equals(body('Get_Job_Status')?['properties']?['status'], 'Completed'), equals(body('Get_Job_Status')?['properties']?['status'], 'Failed'), equals(body('Get_Job_Status')?['properties']?['status'], 'Stopped'))`
- Limit count: 240
- Timeout: PT2H (2 hours)
- Inside loop:
  - **Delay** 30 seconds
  - **Azure Automation - Get job** using Job ID from Create job output

**c. Check Job Failed:**
- Action: **Condition**
- Expression: `@or(equals(body('Get_Job_Status')?['properties']?['status'], 'Failed'), equals(body('Get_Job_Status')?['properties']?['status'], 'Stopped'))`
- If yes:
  - **Office 365 Outlook - Send an email (V2)**
    - To: `@{variables('ComplianceDistributionList')}`
    - Subject: `[CRITICAL] Tenant Audit Validation Job Failed`
    - Body: Include job status and job ID
    - Importance: **High**
  - **Terminate** with status: Failed

**d. Get Job Output:**
- Action: **Azure Automation - Get job output**
- Job ID: From Create job output

**e. Parse Results:**
- Action: **Parse JSON**
- Content: `@body('Get_Job_Output')`
- Schema: See section 2.2 for JSON schema

**f. Check Alert Required:**
- Action: **Condition**
- Expression: `@equals(body('Parse_Results')?['AlertRequired'], true)`
- If yes:
  - **Check Severity For Teams** (nested Condition):
    - Expression: `@or(equals(body('Parse_Results')?['OverallStatus'], 'Failed'), equals(body('Parse_Results')?['OverallStatus'], 'Error'))`
    - If yes: **Post adaptive card to Teams** (see section 2.4)
  - **Send Alert Email** (Office 365 Outlook):
    - To: `@{variables('ComplianceDistributionList')}`
    - Subject: `[ALERT] Tenant Audit Configuration Drift - @{body('Parse_Results')?['Zone']} - @{body('Parse_Results')?['OverallStatus']}`
    - Body: Include drift details, validator results, validation history link
    - Importance: `@if(or(equals(body('Parse_Results')?['OverallStatus'], 'Failed'), equals(body('Parse_Results')?['OverallStatus'], 'Error')), 'High', 'Normal')`

**Add Scope - Catch:**

1. Add **Scope** action named `Scope_Catch`
2. Configure to run after `Scope_Try` has **Failed, Skipped, or TimedOut**
3. Inside Scope_Catch:
   - **Office 365 Outlook - Send an email (V2)**
     - To: `@{variables('ComplianceDistributionList')}`
     - Subject: `[CRITICAL] Tenant Audit Validation Flow Error`
     - Body: Include flow name and timestamp
     - Importance: **High**

### 2.2 Parse JSON Schema

Use this schema for the **Parse JSON** action in the tenant validation flow:

```json
{
  "type": "object",
  "properties": {
    "RunType": { "type": "string" },
    "Timestamp": { "type": "string" },
    "Zone": { "type": "string" },
    "OverallStatus": { "type": "string" },
    "Reason": { "type": "string" },
    "Validators": {
      "type": "object",
      "properties": {
        "UnifiedAuditLog": {
          "type": "object",
          "properties": {
            "Status": { "type": "string" },
            "Reason": { "type": "string" }
          }
        },
        "MailboxAudit": {
          "type": "object",
          "properties": {
            "Status": { "type": "string" },
            "Reason": { "type": "string" }
          }
        },
        "PurviewRetention": {
          "type": "object",
          "properties": {
            "Status": { "type": "string" },
            "Reason": { "type": "string" }
          }
        }
      }
    },
    "Drift": {
      "type": "object",
      "properties": {
        "Overall": {
          "type": "object",
          "properties": {
            "DriftDetected": { "type": "boolean" },
            "BaselineStatus": { "type": "string" },
            "CurrentStatus": { "type": "string" },
            "BaselineDate": { "type": "string" }
          }
        },
        "PerValidator": { "type": "object" }
      }
    },
    "AlertRequired": { "type": "boolean" },
    "AlertSeverity": { "type": "string" }
  }
}
```

### 2.3 Create Environment Validation Flow

Follow the same pattern as the tenant validation flow with these differences:

**Flow name:** `ACV - Environment Audit Validation (Daily)`

**Schedule:** Daily at **7:00 AM UTC** (1 hour after tenant validation)

**Runbook:** `Start-EnvironmentValidationRunbook`

**Variables:** Remove `Zone` variable (not required for environment validation)

**Runbook parameters:**
```json
{
  "TenantId": "@{variables('TenantId')}",
  "DataverseUrl": "@{variables('DataverseUrl')}",
  "ClientId": "@{variables('ClientId')}",
  "CertificateThumbprint": "@{variables('CertificateThumbprint')}"
}
```

**Parse JSON schema:** Define a schema that includes a `PerEnvironmentResults` array with per-environment validation fields (environment name, audit enabled status, compliance status, severity).

**Alert routing:** After parsing results, use **Apply to each** on `@body('Parse_Results')?['AlertsRequired']` array and send per-environment Teams cards and emails.

### 2.4 Create Audit Remediation Approval Flow

This ALCA flow queries Dataverse for non-compliant environments and requests governance approval before triggering remediation.

**Flow name:** `ALCA - Audit Remediation Approval (Weekly)`

**Schedule:** Weekly on **Monday** at **7:00 AM Eastern** (1 hour after detection runbook)

1. Go to [make.powerautomate.com](https://make.powerautomate.com)
2. Click **Create** > **Scheduled cloud flow**
3. Name: `ALCA - Audit Remediation Approval (Weekly)`
4. Set schedule: Repeat every **1 Week**, on **Monday** at **7:00 AM** (Eastern Standard Time)

**Add variable initializations:**

| Variable | Type | Value |
|----------|------|-------|
| `DataverseEnvironmentUrl` | String | `https://YOUR-ORG.crm.dynamics.com` |
| `TenantDomain` | String | Your tenant domain |
| `GovernanceLeadEmail` | String | Governance lead email address |
| `AutomationAccountName` | String | Azure Automation account name |
| `ResourceGroupName` | String | Azure resource group name |
| `SubscriptionId` | String | Azure subscription ID |
| `NonCompliantCount` | Integer | `0` |
| `RemediationStatus` | String | (empty) |

**Flow actions:**

1. **Query Dataverse** — Use the **Microsoft Dataverse → List rows** action (NOT a raw HTTP GET) against table `Audit Environment Compliances` (`fsi_auditenvironmentcompliance`) with **Filter rows** `fsi_compliancestatus eq 100000001` and **Select columns** `fsi_environmentid,fsi_environmentname,fsi_auditenabled,fsi_dataverseauditenabled,fsi_compliancestatus,fsi_lastchecked`. The Dataverse connector handles auth via the connection reference; if you must use HTTP, configure the **HTTP** action with **Authentication: Active Directory OAuth**, audience `{DataverseEnvironmentUrl}`, and a registered service principal — do not call the API anonymously.
2. **Parse response** and set `NonCompliantCount` to the number of results
3. **Build summary table** — Use a **Select** action to extract environment name, audit status, and last checked timestamp, then a **Create HTML Table** action
4. **Condition: NonCompliantCount > 0** — if no non-compliant environments, skip approval
5. **Start and wait for an approval** — Title: `[AUDIT] Remediation Required — {NonCompliantCount} environment(s)`, Assigned to: `GovernanceLeadEmail`, Details: include the HTML summary table and describe the remediation actions (enable Dataverse org-level and entity-level auditing)
6. **If Approved** — Create an Azure Automation job to run the `Enable-AuditLogging` runbook, then send a confirmation email to the compliance team
7. **If Rejected** — Send a notification email indicating remediation was declined

> **Note:** This flow uses a single-approver model. For regulated environments requiring separation of duties, customize the OData filter to scope by governance zone and assign zone-specific approvers.

### 2.5 Configure Alert Destinations

#### Teams Channel Setup

1. Create a dedicated channel in Microsoft Teams:
   - Team: Governance or Compliance team
   - Channel: `Audit Configuration Alerts`
2. Get the channel ID:
   - Click **...** on channel > **Get link to channel**
   - Extract the channel ID from the URL (between `/channel/` and `/`)
3. Update the `TeamsChannelId` variable in both flows

#### Email Distribution List

1. Create a mail-enabled security group or distribution list:
   - Name: `Compliance Alerts`
   - Email: `compliance-alerts@example.com`
2. Add members: Compliance team, IT admins, governance stakeholders
3. Update the `ComplianceDistributionList` variable in both flows

#### Adaptive Card Templates

The adaptive card templates are provided in the `templates/` directory:

- **adaptive-card-tenant-alert.json** — Tenant drift alert card
- **adaptive-card-environment-alert.json** — Environment drift alert card

These templates use `${placeholder}` syntax. In Power Automate, use the `replace()` function to substitute placeholders with actual values from the runbook output.

## Step 3: Testing

### 3.1 Test Runbooks Directly

Before testing the full flows, verify runbooks work in Azure Automation:

**Tenant runbook test:**

1. Navigate to **Automation Account** > **Runbooks** > **Start-TenantValidationRunbook**
2. Click **Start**
3. Enter parameters:
   - Zone: `Zone3`
   - DataverseUrl: Your central environment URL
   - TenantId: Your tenant ID
   - ClientId: Your app client ID
   - CertificateThumbprint: Your certificate thumbprint
   - CanaryMailboxIdentity (optional): shared mailbox or user mailbox UPN (recommended for service-principal runs)
4. Click **OK** and monitor job output
5. Verify JSON output is returned with expected structure

**Expected output structure:**
```json
{
  "RunType": "TenantValidation",
  "Timestamp": "2026-02-06T14:30:00Z",
  "Zone": "Zone3",
  "OverallStatus": "Passed",
  "Validators": { ... },
  "Drift": { ... },
  "AlertRequired": false
}
```

### 3.2 Test Flows

**Test with manual trigger:**

1. Navigate to the flow in Power Automate
2. Click **Test** > **Manually** > **Test**
3. Monitor the flow run in real-time
4. Verify each action completes successfully
5. Check job output parsing and alert routing logic

**Verify alert content:**

If drift is detected (AlertRequired = true):

- **Teams:** Check that adaptive card appears in the channel with correct drift details
- **Email:** Verify email is received with proper severity (High for Failed/Error, Normal for Warning)

### 3.3 Validate Alert Content

**Teams Adaptive Card verification:**

- [ ] Card displays with red "attention" style border
- [ ] Severity badge shows correct status (Failed, Error, Warning, etc.)
- [ ] Drift information includes baseline status, current status, baseline date
- [ ] Validator results show individual status for each validator
- [ ] "View in Power Platform" link works
- [ ] "View Validation History" link opens Dataverse environment

## Connection References (manual setup before flow build)

`scripts/create_connection_references.py` provisions only Dataverse and Office 365 references. The flows in this guide additionally require:

| Connector | Purpose | Documented in |
|-----------|---------|---------------|
| **Approvals** | Step 5 of the ALCA approval flow | This file (Step 2.5) |
| **Microsoft Teams** | Posting adaptive cards to a governance channel | This file (Step 5) |
| **Azure Automation** | Triggering `Test-AuditLoggingCompliance` / `Enable-AuditLogging` runbooks from a flow (optional pattern) | scheduling-guide.md |

Create these manually via Power Automate → Connections, then add the corresponding Connection References to the solution before importing/building the flows.

**Email verification:**

- [ ] Subject line includes zone (for tenant) or environment name (for environment)
- [ ] Importance is High for Failed/Error, Normal for Warning/GracePeriod
- [ ] HTML formatting displays table correctly
- [ ] Links to Power Platform Admin Center and validation history work

## Step 4: Production Configuration

### 4.1 Environment Variables

Store these values as Power Automate flow variables (initialize at the top of each flow):

| Variable | Value | Notes |
|----------|-------|-------|
| DataverseUrl | https://governance.crm.dynamics.com | Central Dataverse environment URL |
| TenantId | contoso.onmicrosoft.com | Microsoft Entra ID tenant ID |
| ClientId | xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx | Microsoft Entra ID app registration client ID |
| CertificateThumbprint | ABCDEF1234567890... | Certificate thumbprint from Azure Automation |
| SubscriptionId | xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx | Azure subscription ID |
| ResourceGroup | rg-audit-validation | Resource group containing Automation Account |
| AutomationAccount | aa-audit-validator | Automation Account name |
| TeamsChannelId | 19:abcd1234... | Teams channel ID for alerts |
| ComplianceDistributionList | compliance-alerts@example.com | Email distribution list |
| Zone | Zone3 | Governance zone (tenant flow only) |
| CanaryMailboxIdentity | shared-mailbox@example.com | Optional canary mailbox identity for tenant runbook service-principal validation |

**Security best practice:** Consider using Azure Key Vault to store sensitive values (ClientId, CertificateThumbprint) and retrieve them in the flow using the Azure Key Vault connector.

### 4.2 Alert Routing Matrix

This table defines the alert behavior based on validation status:

| Severity | Teams Card | Email | Importance | Meaning |
|----------|------------|-------|------------|---------|
| Error | Yes | Yes | High | Validation script encountered an error (infrastructure issue) |
| Failed | Yes | Yes | High | Audit configuration does not meet zone requirements |
| Warning | No | Yes | Normal | Minor drift or non-critical gap (e.g., missing retention for low-priority record types) |
| GracePeriod | No | Yes | Normal | Audit recently enabled, within 24-hour grace period |
| Passed | No | No | N/A | Configuration meets zone requirements, no drift detected |

**Drift detection logic:**

- **First run (no baseline):** Any non-Passed result triggers drift detection (AlertRequired = true)
- **Subsequent runs:** Drift detected if current status is worse than baseline (numeric severity comparison)
- **Baseline query failure:** Fails open (DriftDetected = true) to avoid suppressing alerts

### 4.3 Monitoring

**Flow run history:**

1. Navigate to **My flows** > **ACV - Tenant Audit Validation (Daily)**
2. Click **Run history** to see all flow executions
3. Click on a run to see detailed action-level logs

**Azure Automation job history:**

1. Navigate to **Automation Account** > **Jobs**
2. Filter by runbook name
3. Click on a job to see output, errors, and execution time

**Dataverse validation history:**

1. Navigate to your central Dataverse environment
2. Open the **Audit Configuration Validator** app
3. View **Tenant Validation History** or **Environment Validation History** tables
4. Filter by date, zone, status to analyze trends

**Key metrics to monitor:**

- Flow success rate (target: >99%)
- Runbook execution time (tenant: 5-10 min with canary, environment: 2-5 min)
- Alert volume by severity (track Failed/Error alerts, investigate spikes)
- Drift frequency (measure stability of audit configuration over time)

## Troubleshooting

### 1. Job Output Truncation

**Symptom:** Parse JSON action fails with "Invalid JSON" error.

**Cause:** Azure Automation job output is limited to 10 MB. Large environment validation runs (50+ environments) may exceed this.

**Solution:**

- Enable `-SkipDiscovery` parameter in environment runbook (after initial discovery)
- Filter environments by zone or type to reduce output size
- Write detailed results to Dataverse only, return summary JSON to flow

### 2. Module Version Drift

**Symptom:** Runbook fails with "Cmdlet not found" or authentication errors.

**Cause:** PowerShell module versions in Azure Automation are out of date.

**Solution:**

1. Navigate to **Automation Account** > **Modules**
2. Check module versions match requirements:
   - Az.Accounts: 5.0+
   - ExchangeOnlineManagement: 3.0.0-3.9.2
   - Microsoft.PowerApps.Administration.PowerShell: 2.0.180 (pinned)
3. Update modules if needed (may require reimporting)

### 3. OData Filter Syntax

**Symptom:** Dataverse queries fail with "Invalid filter" error.

**Cause:** OData filter syntax in Compare-ValidationBaseline helper is malformed.

**Solution:**

- Verify filter syntax: `fsi_zone eq 123456789` (not string, use integer for option set)
- Check field names match schema: `fsi_validationtype`, `fsi_severity`
- Escape single quotes in filter values if needed

### 4. Teams Permissions

**Symptom:** "Post message to channel" action fails with 403 Forbidden.

**Cause:** Power Automate does not have permission to post in the Teams channel.

**Solution:**

1. Ensure Teams Workflows app is installed in the team
2. Grant the flow's service principal access to post messages
3. Test by manually posting a card to the channel first
4. Verify the channel ID is correct (not the team ID)

### 5. Email Distribution List

**Symptom:** Emails are not delivered to all recipients.

**Cause:** Distribution list is not mail-enabled or membership is incorrect.

**Solution:**

1. Verify the distribution list exists in Exchange Online
2. Check that it's mail-enabled (can receive external email)
3. Verify membership includes all required recipients
4. Test by sending a manual email to the distribution list

### 6. Certificate Authentication Failures

**Symptom:** Runbook fails with "Certificate not found" or "Authentication failed".

**Cause:** Certificate is not uploaded to Azure Automation or thumbprint is incorrect.

**Solution:**

1. Navigate to **Automation Account** > **Certificates**
2. Verify certificate is uploaded and not expired
3. Compare thumbprint in flow variable to thumbprint in Azure Automation
4. Ensure certificate has private key and is valid for authentication

### 7. Drift Detection False Positives

**Symptom:** Alerts fire every day even though configuration has not changed.

**Cause:** Baseline query is not finding the last Passed validation.

**Solution:**

- Check Dataverse validation history for existing Passed records
- Verify OData filter in Compare-ValidationBaseline includes correct zone/environment filters
- Add diagnostic logging to Compare-ValidationBaseline to trace baseline query
- Manually query Dataverse to confirm Passed baseline exists

## Related Documentation

- **[AUTHENTICATION.md](authentication.md)** — Entra ID app registration, API permissions, certificate and Managed Identity authentication
- **[deployment-guide.md](deployment-guide.md)** — Deployment, authentication, and Dataverse schema setup
- **[testing-scenarios.md](testing-scenarios.md)** — Testing and troubleshooting scenarios

---

**Version:** 1.0.6
**Last Updated:** 2026-02-06
**Solution:** Audit Configuration Validator
**Phase:** 3 - Automated Orchestration & Alerting
