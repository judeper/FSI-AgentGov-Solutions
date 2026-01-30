# Automation Guide

This guide covers what CAN be automated for pipeline governance - and what cannot.

> **Important:** Full automation of pipeline governance cleanup is not possible due to Power Platform limitations. This guide documents the automation that IS available and directs you to manual procedures where required.

---

## What Can Be Automated

| Capability | Method | Documentation |
|------------|--------|---------------|
| List all environments | PowerShell + PAC CLI | [src/Get-PipelineInventory.ps1](./src/Get-PipelineInventory.ps1) |
| Detect pipeline presence | PowerShell + PAC CLI | Use `-ProbePipelines` switch |
| Send owner notifications | PowerShell + Microsoft Graph | [src/Send-OwnerNotifications.ps1](./src/Send-OwnerNotifications.ps1) |
| Monitor deployment events | Power Automate triggers | This document (below) |
| Alert on new pipelines | Power Automate + Teams | This document (below) |

## What CANNOT Be Automated

| Capability | Reason | Alternative |
|------------|--------|-------------|
| Query DeploymentPipeline table | System table not exposed to "List rows" action | Use pipeline triggers only |
| Identify host associations | No API returns pipeline-to-host mapping | Manual verification in admin portal |
| Force-link environments | No API or CLI command exists | [PORTAL_WALKTHROUGH.md](./PORTAL_WALKTHROUGH.md) |
| Deactivate pipelines directly | Requires host environment access | Manual action in maker portal |

See [LIMITATIONS.md](./LIMITATIONS.md) for technical details.

---

## PowerShell Scripts

### Get-PipelineInventory.ps1

Exports all Power Platform environments to CSV for review, with optional pipeline detection.

**Location:** `src/Get-PipelineInventory.ps1`

**Usage:**

```powershell
# Basic usage - export all environments
.\src\Get-PipelineInventory.ps1 -OutputPath ".\reports\environment-inventory.csv"

# With pipeline probing (recommended) - detects which environments have pipelines
.\src\Get-PipelineInventory.ps1 -OutputPath ".\reports\environment-inventory.csv" -ProbePipelines

# With designated host flag for compliance tracking
.\src\Get-PipelineInventory.ps1 -OutputPath ".\reports\environment-inventory.csv" -ProbePipelines -DesignatedHostId "00000000-0000-0000-0000-000000000000"
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

**Location:** `src/Send-OwnerNotifications.ps1`

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
.\src\Send-OwnerNotifications.ps1 `
    -InputPath ".\reports\non-compliant.csv" `
    -EnforcementDate "2026-03-01" `
    -TestMode

# Send actual notifications (delegated permissions - interactive sign-in)
.\src\Send-OwnerNotifications.ps1 `
    -InputPath ".\reports\non-compliant.csv" `
    -EnforcementDate "2026-03-01" `
    -SupportEmail "platform-ops@contoso.com" `
    -MigrationUrl "https://contoso.service-now.com/migrate" `
    -ExemptionUrl "https://contoso.service-now.com/exemption"

# Send using application permissions (service principal)
.\src\Send-OwnerNotifications.ps1 `
    -InputPath ".\reports\non-compliant.csv" `
    -EnforcementDate "2026-03-01" `
    -SenderEmail "noreply@contoso.com" `
    -SupportEmail "platform-ops@contoso.com"
```

---

## Service Principal Setup for Unattended Automation

For fully automated notification workflows (e.g., scheduled Azure Automation runbooks), configure an Azure AD app registration with application permissions.

### Prerequisites

- Azure AD Global Administrator or Application Administrator role
- Certificate (recommended) or client secret for authentication

### Step 1: Create App Registration

1. Navigate to [Azure Portal](https://portal.azure.com) > **Azure Active Directory** > **App registrations**
2. Click **New registration**
3. Configure:
   - **Name:** `Pipeline-Governance-Notifications`
   - **Supported account types:** Single tenant (this organization only)
   - **Redirect URI:** Leave blank (not needed for daemon apps)
4. Click **Register**
5. Note the **Application (client) ID** and **Directory (tenant) ID**

### Step 2: Configure API Permissions

1. In your app registration, click **API permissions**
2. Click **Add a permission** > **Microsoft Graph**
3. Select **Application permissions** (not delegated)
4. Add these permissions:
   - `Mail.Send` - Send mail as any user
5. Click **Add permissions**
6. Click **Grant admin consent for [your tenant]**
7. Verify status shows green checkmarks

### Step 3: Create Certificate or Secret

**Option A: Certificate (Security Best Practice)**

1. Go to **Certificates & secrets** > **Certificates** tab
2. Click **Upload certificate**
3. Upload a certificate from your organization's PKI (or self-signed for dev/test)
4. Note the **Thumbprint** value

**Option B: Client Secret (Development Only)**

1. Go to **Certificates & secrets** > **Client secrets** tab
2. Click **New client secret**
3. Set expiration (recommend 90 days maximum)
4. Note the **Value** immediately (it won't be shown again)

> **Security Note:** Client secrets are less secure than certificates and must be rotated frequently. For production FSI environments, use certificates aligned with your organization's PKI policy.

### Step 4: Run Script with Application Permissions

```powershell
# Connect with certificate authentication
Connect-MgGraph -ClientId "your-app-id" -TenantId "your-tenant-id" -CertificateThumbprint "your-thumbprint"

# Run notification script with sender email (required for app permissions)
.\src\Send-OwnerNotifications.ps1 `
    -InputPath ".\reports\non-compliant.csv" `
    -EnforcementDate "2026-03-01" `
    -SenderEmail "noreply@contoso.com" `
    -SupportEmail "platform-ops@contoso.com"
```

### Security Considerations for FSI

| Consideration | Recommendation |
|---------------|----------------|
| **Conditional Access** | Consider policies to restrict app access by IP range (corporate network only) |
| **Audit logging** | Enable Azure AD sign-in logs for the app registration |
| **Certificate rotation** | Align with organizational PKI policy (typically 1-2 years) |
| **Secret rotation** | If using secrets, rotate every 90 days maximum |
| **Documentation** | Document service principal in change management for operational handoff |
| **Least privilege** | Only grant Mail.Send; do not add unnecessary permissions |

### Azure Automation Integration (Optional)

For scheduled runs via Azure Automation:

1. Upload certificate to Azure Automation account (Certificates blade)
2. Create runbook with `Connect-MgGraph` using certificate
3. Schedule runbook for desired frequency
4. Store CSV input in Azure Blob Storage or SharePoint

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

See [FSI-AgentGov Control 1.5: DLP Enforcement](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.5-data-loss-prevention-enforcement.md) for comprehensive DLP guidance.

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
| Catalog | Deployment Pipeline |
| Category | Pipeline Extensibility |
| Table name | Deployment Stage Run |
| Action name | OnDeploymentCompleted |

> **Note:** The trigger names and configuration may vary based on your Dataverse version. If you don't see "Deployment Pipeline" in the catalog, ensure the Power Platform Pipelines app is installed on your host environment.

#### Step 3: Extract Deployment Information

Add a **Compose** action to capture key information:

**Inputs:**
```json
{
  "DeploymentId": "@{triggerOutputs()?['body/OutputParameters/StageRunId']}",
  "DeploymentStatus": "@{triggerOutputs()?['body/OutputParameters/Status']}",
  "PipelineName": "@{triggerOutputs()?['body/OutputParameters/PipelineName']}",
  "StageName": "@{triggerOutputs()?['body/OutputParameters/StageName']}",
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

- **Pipeline:** @{outputs('Compose')?['PipelineName']}
- **Stage:** @{outputs('Compose')?['StageName']}
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
empty(triggerOutputs()?['body/OutputParameters/StageName'])
```

### Build Alert Message

```
concat('Pipeline ', triggerOutputs()?['body/OutputParameters/PipelineName'], ' deployment completed at ', utcNow())
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
| Force-link environments | - | Admin Portal | [PORTAL_WALKTHROUGH.md](./PORTAL_WALKTHROUGH.md) |
| Monitor deployments | Power Automate | - | Trigger-based |
| Track compliance | Custom table | Manual updates | Hybrid approach |

---

## Next Steps

1. Run [Get-PipelineInventory.ps1](./src/Get-PipelineInventory.ps1) to get environment baseline
2. Manually verify pipeline configurations ([PORTAL_WALKTHROUGH.md](./PORTAL_WALKTHROUGH.md))
3. Prepare notification list with owner information
4. Run [Send-OwnerNotifications.ps1](./src/Send-OwnerNotifications.ps1)
5. Set up trigger-based monitoring (this guide)
6. Execute force-link after notification period ([PORTAL_WALKTHROUGH.md](./PORTAL_WALKTHROUGH.md))

See [SETUP_CHECKLIST.md](./SETUP_CHECKLIST.md) for complete deployment checklist.

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
