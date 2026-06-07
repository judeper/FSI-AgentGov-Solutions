# Automation Guide

This guide covers what CAN be automated for pipeline governance - and what cannot.

> **Important:** Full automation of pipeline governance cleanup is not possible due to Power Platform limitations. This guide documents the automation that IS available and directs you to manual procedures where required.

---

## What Can Be Automated

| Capability | Method | Documentation |
|------------|--------|---------------|
| List all environments | PowerShell + PAC CLI, or `Get-AdminPowerAppEnvironment` for admin inventory | [scripts/Get-PipelineInventory.ps1](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/pipeline-governance-cleanup/scripts/Get-PipelineInventory.ps1) |
| Detect pipeline presence | PowerShell + PAC CLI | Use `-ProbePipelines` switch |
| Send owner notifications | PowerShell + Microsoft Graph | [scripts/Send-OwnerNotifications.ps1](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/pipeline-governance-cleanup/scripts/Send-OwnerNotifications.ps1) |
| Monitor deployment events | Power Automate triggers | This document (below) |
| Alert on new pipelines | Power Automate + Teams | This document (below) |

## What CANNOT Be Automated

| Capability | Reason | Alternative |
|------------|--------|-------------|
| Query DeploymentPipeline table | System table not exposed to "List rows" action | Use pipeline triggers only |
| Identify host associations | No API returns pipeline-to-host mapping | Manual verification in admin portal |
| Force-link environments | No Learn-documented API, CLI command, or Microsoft.PowerApps.Administration.PowerShell cmdlet exists | [Portal Walkthrough](./portal-walkthrough.md) |
| Deactivate pipelines directly | Requires host environment access | Manual action in maker portal |

See [Limitations](./limitations.md) for technical details.

---

## PowerShell Scripts

### Get-PipelineInventory.ps1

Exports all Power Platform environments to CSV for review, with optional pipeline detection.

**Location:** `scripts/Get-PipelineInventory.ps1`

**Usage:**

```powershell
# Basic usage - export all environments
.\scripts\Get-PipelineInventory.ps1 -OutputPath ".\reports\environment-inventory.csv"

# With pipeline probing (recommended) - detects which environments have pipelines
.\scripts\Get-PipelineInventory.ps1 -OutputPath ".\reports\environment-inventory.csv" -ProbePipelines

# With designated host flag for compliance tracking
.\scripts\Get-PipelineInventory.ps1 -OutputPath ".\reports\environment-inventory.csv" -ProbePipelines -DesignatedHostId "00000000-0000-0000-0000-000000000000"
```

**Parameters:**

| Parameter | Required | Description |
|-----------|----------|-------------|
| OutputPath | No | Path for CSV output (default: `.\PipelineInventory.csv`) |
| ProbePipelines | No | Probe each environment for pipeline configurations |
| DesignatedHostId | No | Environment ID of your designated pipelines host |

**Output columns:**

| Column | Description |
|--------|-------------|
| EnvironmentId | Power Platform environment GUID |
| EnvironmentName | Display name |
| EnvironmentType | Production, Sandbox, Developer, etc. |
| EnvironmentUrl | Dataverse URL |
| IsManaged | [Check Admin Portal] - not available from `pac admin list` |
| CreatedTime | [Not Available] - not available from `pac admin list` |
| PipelinesHostId | [Manual Check Required] - cannot be determined via API |
| HasPipelinesEnabled | "Yes", "No", "Unknown", or "[Not Probed]" |
| ComplianceStatus | Requires manual verification |
| Notes | Pipeline count or error details |

> **Note:** The `pac admin list --json` command does not return IsManaged or CreatedTime. Verify Managed Environment status in the Power Platform Admin Center.

**What `-ProbePipelines` does:**
- Runs `pac pipeline list --environment <id>` for each environment (note: `--json` is not supported, text output is parsed)
- Detects whether pipelines deploy TO the environment (as a target stage)
- Populates `HasPipelinesEnabled` with "Yes" (with count), "No", or "Unknown"

**What this script does NOT do:**
- It cannot determine which pipelines HOST an environment is linked to
- It cannot query the DeploymentPipeline table directly

After running this script, environments with `HasPipelinesEnabled = "Yes"` need manual verification in the Deployment Pipeline Configuration app to identify their host.

### Send-OwnerNotifications.ps1

Sends governance notification emails to environment/pipeline owners.

**Location:** `scripts/Send-OwnerNotifications.ps1`

**Prerequisites:**
- Microsoft Graph PowerShell SDK: `Install-Module Microsoft.Graph`
- Mail.Send permission (delegated or application)

**Authentication modes:**
- **Delegated (default)**: Uses interactive sign-in, sends email as signed-in user
- **Application**: Requires `-SenderEmail` parameter to specify sending user

**Input CSV requirements:**

| Column | Required | Description |
|--------|----------|-------------|
| OwnerEmail | Yes | Email address to notify |
| EnvironmentName | Yes | Environment display name |
| EnvironmentId | Yes | Environment GUID |
| OwnerName | No | Owner's display name (defaults to "Pipeline Owner") |

**Usage:**

```powershell
# Test mode - preview emails without sending
.\scripts\Send-OwnerNotifications.ps1 `
    -InputPath ".\reports\non-compliant.csv" `
    -EnforcementDate "2026-03-01" `
    -TestMode

# Send actual notifications (delegated permissions - interactive sign-in)
.\scripts\Send-OwnerNotifications.ps1 `
    -InputPath ".\reports\non-compliant.csv" `
    -EnforcementDate "2026-03-01" `
    -SupportEmail "platform-ops@contoso.com" `
    -MigrationUrl "https://contoso.service-now.com/migrate" `
    -ExemptionUrl "https://contoso.service-now.com/exemption"

# Send using application permissions (service principal)
.\scripts\Send-OwnerNotifications.ps1 `
    -InputPath ".\reports\non-compliant.csv" `
    -EnforcementDate "2026-03-01" `
    -SenderEmail "noreply@contoso.com" `
    -SupportEmail "platform-ops@contoso.com"
```

---

## Managed Environment Governance Configuration

Use `pac admin set-governance-config` to enforce governance policies on production Managed Environments. This is recommended before deploying solutions through pipelines, to help prevent unvetted solutions from being imported.

**Required role:** Power Platform Admin (or Dynamics 365 admin with environment-level permissions).

> **Scope note:** `pac admin set-governance-config` configures the Managed Environment protection level and solution checker mode only. It does not expose flags to disable unmanaged customizations or to enable deployment pipelines. Deployment pipelines are enabled by installing the Power Platform Pipelines app and configuring a host environment (see the [README Prerequisites](../README.md#prerequisites) and [portal walkthrough](portal-walkthrough.md)).

### Recommended configuration

```powershell
# Apply FSI-recommended governance settings (Managed Environment + solution checker warn)
.\scripts\Set-GovernanceConfig.ps1 `
    -EnvironmentId "00000000-0000-0000-0000-000000000000" `
    -ProtectionLevel "Standard" `
    -SolutionCheckerMode "warn"

# For stricter enforcement (blocks imports with critical solution checker findings)
.\scripts\Set-GovernanceConfig.ps1 `
    -EnvironmentId "00000000-0000-0000-0000-000000000000" `
    -ProtectionLevel "Standard" `
    -SolutionCheckerMode "block"
```

**Script location:** [`scripts/Set-GovernanceConfig.ps1`](../scripts/Set-GovernanceConfig.ps1)

### Configuration flags

| Flag | Effect |
|------|--------|
| `--protection-level Standard` | Enables Managed Environments for the environment (required parameter) |
| `--protection-level Basic` | Disables Managed Environments for the environment |
| `--solution-checker-mode warn` | Logs solution checker findings without blocking import |
| `--solution-checker-mode block` | Prevents import of solutions with critical findings |
| `--solution-checker-mode none` | Disables solution checker validation |

### Verification

The `pac` CLI does not currently expose a governance-config read command. Verify the applied settings in the Power Platform Admin Center (PPAC): **Environments** → select environment → **Settings** → **Governance**.

> **Note:** Start with `warn` mode in non-production environments to assess solution checker impact before enforcing `block` in production.

---

## Authentication for Unattended Automation

Use the strongest authentication pattern available in the runtime that hosts the automation. Microsoft Learn documents `pac auth create --managedIdentity` for Azure Identity-capable environments and federation switches for GitHub/Azure DevOps service-principal auth.

### Authentication priority

| Priority | Pattern | When to use |
|----------|---------|-------------|
| 1 | Managed identity | Azure Automation, Azure VM, Azure Functions, or other Azure-hosted automation |
| 2 | Workload identity federation | GitHub Actions or Azure DevOps automation without stored secrets |
| 3 | Certificate-backed app registration | Scheduled jobs where managed identity or federation is unavailable |
| 4 | Device-code or interactive sign-in | One-off administrator workstation runs |
| 5 | Client secret | Legacy dev-only fallback — replace with managed identity in production |

### Option A: Managed identity (preferred)

```powershell
# PAC CLI uses DefaultAzureCredential when --managedIdentity is provided.
pac auth create --managedIdentity --environment <host-environment-id>

# For a user-assigned managed identity, set AZURE_CLIENT_ID to the identity client ID first.
$env:AZURE_CLIENT_ID = "00000000-0000-0000-0000-000000000000"
pac auth create --managedIdentity --environment <host-environment-id>

# Microsoft Graph PowerShell supports managed identity in Azure-hosted automation.
Connect-MgGraph -Identity
```

Grant the managed identity only the permissions it needs: Power Platform environment access for inventory and `Mail.Send` application permission if it sends notifications.

### Option B: Workload identity federation

Use PAC CLI federation flags for CI/CD where supported:

```powershell
# GitHub Actions OIDC -> Microsoft Entra app
pac auth create --githubFederated --applicationId <app-id> --tenant <tenant-id> --environment <host-environment-id>

# Azure DevOps workload identity federation
pac auth create --azureDevOpsFederated --applicationId <app-id> --tenant <tenant-id> --environment <host-environment-id>
```

### Option C: Certificate-backed app registration

Use a certificate when managed identity and federation are not available.

1. Create a single-tenant Microsoft Entra app registration.
2. Grant Microsoft Graph `Mail.Send` application permission and admin consent.
3. Add the app/service principal to required Power Platform environments if it also runs PAC CLI inventory.
4. Upload a certificate from your organization's PKI.

```powershell
Connect-MgGraph -ClientId "your-app-id" -TenantId "your-tenant-id" -CertificateThumbprint "your-thumbprint"

.\scripts\Send-OwnerNotifications.ps1 `
    -InputPath ".\reports\non-compliant.csv" `
    -EnforcementDate "2026-03-01" `
    -SenderEmail "noreply@contoso.com" `
    -SupportEmail "platform-ops@contoso.com"
```

### Option D: Client secret (legacy dev-only)

Client secrets are a development fallback only. Do not prescribe client secrets for production FSI automation; replace them with managed identity, workload federation, or certificate-backed app auth.

### Security considerations for FSI

| Consideration | Recommendation |
|---------------|----------------|
| **Conditional Access** | Consider policies to restrict app access by workload identity and trusted locations |
| **Audit logging** | Enable Microsoft Entra ID sign-in logs for the identity used by automation |
| **Certificate rotation** | Align with organizational PKI policy (typically 1-2 years) |
| **Secret rotation** | If a legacy dev-only secret is temporarily used, rotate every 90 days maximum and track removal |
| **Documentation** | Document managed identities, federated credentials, or app registrations in change management for operational handoff |
| **Least privilege** | Only grant required permissions such as Mail.Send; do not add broad Graph or Dataverse permissions |

---

## DLP Considerations for Pipeline Governance

Data Loss Prevention (DLP) policies can affect both your governance automation and the pipelines themselves.

### Monitoring Flow Connectors

If using Power Automate for governance monitoring, ensure these connectors are in compatible DLP groups:

| Connector | Required Group | Used For |
|-----------|---------------|----------|
| Dataverse | Business | Pipeline trigger events, tracking table |
| Office 365 Outlook | Business | Email notifications |
| Microsoft Teams | Business | Teams alerts |
| SharePoint | Business | CSV file storage (if applicable) |

**Verify your DLP policy:**
1. Open [Power Platform Admin Center](https://admin.powerplatform.microsoft.com) > **Policies** > **Data policies**
2. Check policies that apply to your governance environment
3. Ensure required connectors are in the Business group (or same group)

### Pipeline Deployment DLP Impacts

DLP policies can also affect pipeline operations themselves:

| Impact | Description | Resolution |
|--------|-------------|------------|
| Dataverse blocked | If Dataverse is blocked in target environments, pipeline linking may fail | Ensure Dataverse is in Business group for all pipeline environments |
| HTTP connectors restricted | Pipeline extensibility features may be blocked | Create DLP exception for pipelines host or whitelist specific HTTP endpoints |
| Cross-environment flows blocked | Governance flows may be unable to access other environments | Use environment groups or policy exceptions |

### FSI Recommendation

Create a dedicated DLP policy for your pipelines host environment:

1. Create new policy scoped to pipelines host environment only
2. Place all pipeline-required connectors in Business group
3. Block high-risk connectors (anonymous HTTP, social media, etc.)
4. Document policy for compliance audit

See [FSI-AgentGov Control 1.5: DLP Enforcement](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.5-data-loss-prevention-dlp-and-sensitivity-labels.md) for comprehensive DLP guidance.

---

## Power Automate Trigger-Based Monitoring

While you cannot query the DeploymentPipeline table directly, you CAN create flows that respond to pipeline events using **Dataverse triggers**.

### Available Pipeline Triggers

Power Platform exposes these pipeline lifecycle events that can trigger Power Automate flows:

| Trigger | Fires When |
|---------|------------|
| OnDeploymentRequested | A deployment is initiated |
| OnPreDeploymentStarted | Pre-deployment validation begins |
| OnPreDeploymentCompleted | Pre-deployment validation finishes |
| OnApprovalStarted | Approval request is created |
| OnApprovalCompleted | Approval is granted or denied |
| OnDeploymentStarted | Deployment execution begins |
| OnDeploymentCompleted | A deployment finishes (success or failure) |

These triggers fire within the pipelines host environment where the pipeline is configured.

### Create Deployment Monitoring Flow

This flow alerts your team when deployments occur.

#### Step 1: Create New Flow

1. Go to [Power Automate](https://make.powerautomate.com)
2. Select your **pipelines host environment**
3. Click **Create** > **Automated cloud flow**
4. Name: `Pipeline Governance - Deployment Alert`
5. Search for trigger: **When an action is performed**
6. Select **Microsoft Dataverse**
7. Click **Create**

#### Step 2: Configure Trigger

| Setting | Value |
|---------|-------|
| Catalog | Microsoft Dataverse Common |
| Category | Power Platform Pipelines |
| Table name | (None) |
| Action name | OnDeploymentCompleted |

> **Note:** Pipeline triggers are available in the pipelines host environment under the Dataverse **When an action is performed** trigger. Approval and pre-deployment events only appear when the corresponding gated extension is enabled. If you don't see **Power Platform Pipelines** as a category, update the Power Platform Pipelines app in the host environment.

#### Step 3: Extract Deployment Information

Add a **Compose** action to capture key information:

**Inputs:**
```json
{
  "DeploymentId": "@{triggerOutputs()?['body/OutputParameters/StageRunId']}",
  "DeploymentStatus": "@{triggerOutputs()?['body/OutputParameters/Status']}",
  "DeploymentPipelineName": "@{triggerOutputs()?['body/OutputParameters/DeploymentPipelineName']}",
  "DeploymentStageName": "@{triggerOutputs()?['body/OutputParameters/DeploymentStageName']}",
  "Timestamp": "@{utcNow()}"
}
```

> **Note:** The exact output parameter names depend on the trigger version. Check the dynamic content panel for available fields.

#### Step 4: Send Teams Alert

1. Add **Microsoft Teams** > **Post message in a chat or channel**
2. Configure:

| Setting | Value |
|---------|-------|
| Post as | Flow bot |
| Post in | Channel |
| Team | Your governance team |
| Channel | Pipeline-Alerts |
| Message | See template below |

**Message Template:**

```
**Pipeline Deployment Completed**

- **Pipeline:** @{outputs('Compose')?['DeploymentPipelineName']}
- **Stage:** @{outputs('Compose')?['DeploymentStageName']}
- **Status:** @{outputs('Compose')?['DeploymentStatus']}
- **Time:** @{outputs('Compose')?['Timestamp']}

Review in [Deployment Pipeline Configuration](https://[your-host-env].crm.dynamics.com)
```

#### Step 5: Save and Test

1. Click **Save**
2. Create a test deployment in your pipelines host
3. Verify the Teams alert is received

### Create New Pipeline Detection Flow (Limited)

You can detect when new pipelines are created by monitoring the first deployment:

1. Use the **OnDeploymentRequested** trigger
2. Query your tracking table/list for the pipeline name
3. If not found, it's a new pipeline - send alert
4. Add pipeline to tracking list

**Limitation:** This only detects pipelines when they're first used, not when created.

---

## Optional Solution Checker Gate

Use solution checker as a quality gate before approving a pipeline deployment. Microsoft Learn documents `pac solution check` as the current CLI command for uploading a solution package to the Power Apps Checker service, with `Solution Checker` as the default rule set.

### Recommended pattern

1. Add a **Pre-export Step Required** or **Pre-deployment Step Required** gated extension to the pipeline stage.
2. Trigger a cloud flow on `OnDeploymentRequested` (pre-export) or `OnPreDeploymentStarted` (pre-deployment).
3. Export or clone the solution source, package it, then run solution checker.
4. Complete or reject the gated step with the corresponding Dataverse unbound action. Use status `20` to complete or `30` to reject.

### Current PAC CLI syntax

```powershell
# Clone the current solution source from Dataverse for inspection/source control
pac solution clone --name <solution-unique-name> --outputDirectory ".\src\<solution-unique-name>"

# If you already have a solution zip from your build, use that file directly.
# Otherwise, package the cloned/unpacked solution before checking.
pac solution pack --folder ".\src\<solution-unique-name>" --zipfile ".\out\<solution-unique-name>.zip" --packagetype Managed

# Run solution checker; choose the geo for your tenant.
pac solution check --path ".\out\<solution-unique-name>.zip" --outputDirectory ".\checker" --geo UnitedStates --ruleSet "Solution Checker"
```

### Severity handling

Solution checker and Power Platform Build Tools use severity levels `Critical`, `High`, `Medium`, `Low`, and `Informational`. For FSI deployment gates, reject the gated step when Critical findings are present, and require documented remediation or approval for High findings. If using rule overrides, store the JSON file in source control and review it through change management.

> **Implementation caveat:** This solution documents the gate pattern only. It does not include exported cloud flow artifacts; build the flow manually in Power Automate following your organization's ALM process.

---

## Custom Tracking with Dataverse

If you want to maintain a governance log, create a custom table (not the system DeploymentPipeline table).

### Create PipelineCleanupLog Table

1. Go to [Power Apps](https://make.powerapps.com)
2. Select your governance environment (can be the pipelines host)
3. Go to **Tables** > **New table**
4. Configure:

| Setting | Value |
|---------|-------|
| Display name | Pipeline Cleanup Log |
| Plural name | Pipeline Cleanup Logs |
| Primary column | Environment Name |

### Add Columns

| Column | Type | Description |
|--------|------|-------------|
| EnvironmentId | Text | Power Platform environment GUID |
| OwnerEmail | Text | Owner's email address |
| DiscoveredDate | Date and Time | When identified as non-compliant |
| NotificationSentDate | Date and Time | When owner was notified |
| EnforcementDate | Date and Time | Target force-link date |
| Status | Choice | Pending, Notified, ForceLinked, Exempted |
| Notes | Multiline Text | Admin notes |
| ExemptionJustification | Multiline Text | If exempted, the business reason |

### Flow: Update Tracking After Notification

After sending notifications via PowerShell, update the tracking table:

1. Create **Instant cloud flow** with manual trigger
2. Accept CSV file as input (or read from SharePoint)
3. Loop through records
4. For each record, add/update row in PipelineCleanupLog
5. Set Status = "Notified", NotificationSentDate = utcNow()

---

## Validation Flow

Create a flow to check for untracked environments.

### Flow: Weekly Compliance Check

1. **Trigger:** Recurrence (Weekly, Monday 8 AM)
2. **Action:** Run PowerShell script via Azure Automation (or manual export)
3. **Action:** Compare environment list against tracking table
4. **Condition:** If new environments found not in tracking
5. **Action:** Send alert to Platform Ops team

**Note:** Because you cannot query environments or pipelines directly from Power Automate, this flow typically:
- Reads from a SharePoint list/Excel file that's manually updated
- Or triggers an Azure Automation runbook that runs the PowerShell script

---

## Expression Reference

### Get Current Timestamp (UTC)

```
utcNow()
```

### Format Date for Display

```
formatDateTime(triggerOutputs()?['body/Timestamp'], 'MMMM d, yyyy h:mm tt')
```

### Check if Value is Empty

```
empty(triggerOutputs()?['body/OutputParameters/DeploymentStageName'])
```

### Build Alert Message

```
concat('Pipeline ', triggerOutputs()?['body/OutputParameters/DeploymentPipelineName'], ' deployment completed at ', utcNow())
```

---

## Error Handling

### Common Errors

| Error | Cause | Solution |
|-------|-------|----------|
| Trigger not found | Pipelines app not installed | Install Power Platform Pipelines on host |
| 403 Forbidden | Missing role | Add Deployment Pipeline Administrator role |
| No dynamic content | Wrong trigger selected | Ensure using Dataverse action trigger |
| Teams post fails | Bot not added | Add Flow bot to Teams channel |

### Add Error Handling to Flows

1. Configure **run after** settings for error paths
2. Add **Scope** actions for try/catch patterns
3. Send error notifications to ops team

**Run After Configuration:**

```json
{
  "runAfter": {
    "Previous_Action": ["Succeeded", "Failed", "Skipped", "TimedOut"]
  }
}
```

---

## Summary: Automation Boundaries

| Task | Automated | Manual | Notes |
|------|-----------|--------|-------|
| List environments | PowerShell | - | PAC CLI |
| Identify pipeline hosts | - | Admin Portal | No API available |
| Query pipelines | Triggers only | Admin Portal | Cannot use "List rows" |
| Send notifications | PowerShell | - | Microsoft Graph |
| Force-link environments | - | Admin Portal | [Portal Walkthrough](./portal-walkthrough.md) |
| Monitor deployments | Power Automate | - | Trigger-based |
| Track compliance | Custom table | Manual updates | Hybrid approach |

---

## Next Steps

1. Run [Get-PipelineInventory.ps1](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/pipeline-governance-cleanup/scripts/Get-PipelineInventory.ps1) to get environment baseline
2. Manually verify pipeline configurations ([Portal Walkthrough](./portal-walkthrough.md))
3. Prepare notification list with owner information
4. Run [Send-OwnerNotifications.ps1](https://github.com/judeper/FSI-AgentGov-Solutions/blob/main/pipeline-governance-cleanup/scripts/Send-OwnerNotifications.ps1)
5. Set up trigger-based monitoring (this guide)
6. Execute force-link after notification period ([Portal Walkthrough](./portal-walkthrough.md))

See [Setup Checklist](./setup-checklist.md) for complete deployment checklist.

---

## New Environment Detection

Since force-linking is manual (UI-only), organizations need a way to detect newly created environments and alert admins for action.

> **Important:** This automation DETECTS new environments and ALERTS admins. It cannot automatically force-link due to platform limitations.

### Power Automate Flow: New Environment Alert

**Trigger:** Recurrence (recommended: daily)

**Steps:**
1. **List environments** - Power Platform for Admins connector
2. **Filter array** - `createdtime ge @{addDays(utcNow(), -1)}`
3. **Condition** - Check if any new environments found
4. **If yes** - Send email/Teams notification to admin group

**Notification should include:**
- Environment name and ID
- Environment type (Production, Sandbox, etc.)
- Created by (if available)
- Link to PORTAL_WALKTHROUGH for force-link instructions

### Integration with CoE Starter Kit

If using the Center of Excellence (CoE) Starter Kit:
- Environment inventory is already tracked
- Extend existing flows to trigger force-link alerts
- Use CoE admin app for centralized tracking

### Limitations

- No automatic force-linking (manual action required)
- Polling-based (not real-time)
- Requires Power Platform for Admins connector permissions
