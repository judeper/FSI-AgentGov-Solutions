# Pipeline Governance Cleanup

Discover, notify, and clean up personal Power Platform pipelines before enforcing centralized ALM governance.

> **Important:** This solution requires both **automated scripts** AND **manual admin actions**. Force-linking environments to a custom pipelines host cannot be automated - it requires UI interaction in the Deployment Pipeline Configuration app. See [LIMITATIONS.md](./LIMITATIONS.md) for details.

## What This Solution Does

- **Inventories** Power Platform environments via PowerShell (automated)
- **Identifies** environments with pipeline configurations (manual verification required)
- **Notifies** owners via email before enforcement (automated)
- **Provides guidance** for force-linking environments (manual admin action)
- **Monitors** for compliance using trigger-based alerts (automated)

**This is an ALM governance solution** - it helps organizations transition from ad-hoc personal pipelines to centralized, governed ALM infrastructure.

## Known Limitations

| Capability | Status | Alternative |
|------------|--------|-------------|
| List all environments | **Automated** | PowerShell script via PAC CLI |
| Detect pipeline presence | **Automated** | Use `-ProbePipelines` switch |
| Identify pipelines host association | **Manual** | Check each environment in Deployment Pipeline Configuration app |
| Query DeploymentPipeline table via Power Automate | **Not Supported** | Use pipeline trigger events only |
| Force-link environments | **Manual Only** | [Portal walkthrough](./PORTAL_WALKTHROUGH.md) |
| Send owner notifications | **Automated** | PowerShell script via Microsoft Graph |
| Monitor new deployments | **Automated** | Power Automate trigger events |

See [LIMITATIONS.md](./LIMITATIONS.md) for detailed explanation of technical constraints.

## Who Should Use This

| Audience | Use Case |
|----------|----------|
| Power Platform Admins | Enforce centralized pipelines host policy |
| ALM/DevOps Teams | Clean up legacy personal pipelines before enforcement |
| Agent Governance Committee | Ensure all agent deployments use governed infrastructure |
| Compliance Teams | Document pipeline governance for audit |

## Prerequisites

### 1. Pipelines Host Environment

You must have a designated pipelines host environment:

1. Identify or create your organization's pipelines host environment
2. Ensure it's a Managed Environment
3. **Install Power Platform Pipelines app** (required for Deployment Pipeline Configuration)
4. Verify the Deployment Pipeline Configuration model-driven app is accessible
5. Note the environment ID for configuration

See [Microsoft Learn: Set Up Pipelines](https://learn.microsoft.com/en-us/power-platform/alm/set-up-pipelines) for host environment setup.

### 2. Roles Required

| Role | Purpose |
|------|---------|
| Power Platform Admin | Access to all environments, run PowerShell scripts |
| Deployment Pipeline Administrator | Access Deployment Pipeline Configuration app |
| Microsoft Graph Permissions | User.Read.All (for email resolution), Mail.Send (for notifications) |

### 3. Tools Required

| Tool | Installation | Purpose |
|------|--------------|---------|
| Power Platform CLI (pac) | [Download](https://learn.microsoft.com/en-us/power-platform/developer/cli/introduction) | List environments, authenticate |
| Microsoft Graph PowerShell SDK | `Install-Module Microsoft.Graph` | Resolve user emails, send notifications |

### 4. DLP Policy Considerations

If using Power Automate for trigger-based monitoring:

1. Ensure Dataverse connector is in Business group
2. Office 365 Outlook connector for email notifications
3. Microsoft Teams connector for Teams alerts

## Data Model

### System Tables (Pipelines Host Environment)

Power Platform pipelines use several system-managed Dataverse tables. These tables are **not queryable via standard "List rows" actions** - they require pipeline trigger events or direct admin access.

#### DeploymentPipeline

Primary pipeline definition table.

| Column | Type | Description |
|--------|------|-------------|
| deploymentpipelineid | GUID (PK) | Unique identifier |
| name | Text | Pipeline name |
| ownerid | Lookup (User) | Pipeline owner |
| createdon | DateTime | When pipeline was created |
| modifiedon | DateTime | Last modification date |
| statecode | Choice | Active/Inactive |
| statuscode | Choice | Status reason |

#### DeploymentStage

Links pipelines to target environments.

| Column | Type | Description |
|--------|------|-------------|
| deploymentstageid | GUID (PK) | Unique identifier |
| name | Text | Stage name (e.g., "Dev", "Test", "Prod") |
| deploymentpipelineid | Lookup | Parent pipeline |
| targetdeploymentenvironmentid | Lookup | Target environment |
| previousstageid | Lookup | Previous stage (for sequencing) |

#### DeploymentEnvironment

Environment records linked to the pipelines host.

| Column | Type | Description |
|--------|------|-------------|
| deploymentenvironmentid | GUID (PK) | Unique identifier |
| name | Text | Environment display name |
| environmentid | String | Power Platform environment ID |
| environmenttype | Picklist | Environment type (Production, Sandbox, etc.) |
| validationstatus | Picklist | Validation status of the environment link |
| errormessage | Text | Error details if validation failed |

**Important:** The DeploymentPipeline table does NOT have a direct reference to which host environment it belongs to. The relationship is implicit through the environment where the table resides.

### Custom Tracking Table: PipelineCleanupLog (Optional)

For tracking cleanup progress, create a custom table:

| Column | Type | Description |
|--------|------|-------------|
| pipelineid | Text (PK) | Pipeline or environment GUID |
| name | Text | Pipeline/environment name |
| ownername | Text | Owner display name |
| owneremail | Text | Owner email |
| discovereddate | DateTime | When discovered |
| notificationsentdate | DateTime | When owner was notified |
| scheduledremovaldate | DateTime | Target enforcement date |
| status | Choice | Pending, Notified, ForceLinked, Exempted |
| notes | Multiline Text | Admin notes |

## Quick Start

### Step 1: Run Environment Inventory

Use the PowerShell script to list all environments and detect pipelines:

```powershell
# Authenticate to Power Platform
pac auth create

# Run inventory script with pipeline detection
.\src\Get-PipelineInventory.ps1 -OutputPath ".\reports\environment-inventory.csv" -ProbePipelines
```

This produces a CSV with all environments and indicates which have pipelines (`HasPipelinesEnabled` column). **Manual review is required** to identify which pipelines host those environments are linked to.

### Step 2: Manual Pipeline Assessment

For each environment in the inventory:

1. Open [Power Platform Admin Center](https://admin.powerplatform.microsoft.com)
2. Select the environment
3. Check **Resources** > **Dynamics 365 apps** for "Power Platform Pipelines"
4. If installed, note the pipelines host association
5. Mark environments that need force-linking

See [PORTAL_WALKTHROUGH.md](./PORTAL_WALKTHROUGH.md) for detailed steps.

### Step 3: Prepare Notification List

Add owner information to your inventory:

1. Export environments needing action to separate CSV
2. Add `OwnerEmail` and `OwnerName` columns
3. Look up owners in admin center or via Azure AD

### Step 4: Notify Owners

Send notifications to pipeline owners:

```powershell
.\src\Send-OwnerNotifications.ps1 `
    -InputPath ".\reports\non-compliant.csv" `
    -EnforcementDate "2026-03-01" `
    -TestMode  # Remove to send actual emails
```

See [NOTIFICATION_TEMPLATES.md](./NOTIFICATION_TEMPLATES.md) for email templates.

### Step 5: Execute Force-Link (Manual)

After notification period (30-60 days):

1. Open Deployment Pipeline Configuration app on your designated host
2. Navigate to **Environments**
3. Add each non-compliant environment
4. Use **Force Link** button if already linked to another host
5. Document in tracking table/spreadsheet

See [PORTAL_WALKTHROUGH.md](./PORTAL_WALKTHROUGH.md) for complete walkthrough.

### Step 6: Set Up Ongoing Monitoring (Optional)

Use Power Automate triggers to monitor for new pipeline activity:

- `OnDeploymentRequested` - New deployment initiated
- `OnDeploymentCompleted` - Deployment finished

See [AUTOMATION_GUIDE.md](./AUTOMATION_GUIDE.md) for trigger configuration.

## Workflow

```
Environment Inventory (PowerShell)
        |
        v
Manual Pipeline Assessment
        |
        v
Identify Non-Compliant Environments
        |
        v
Notify Owners (PowerShell - 30-60 day warning)
        |
        v
Process Exemption Requests
        |
        v
Execute Force-Link (MANUAL - Admin Portal)
        |
        v
Trigger-Based Monitoring (Power Automate)
```

**Note:** Steps marked MANUAL cannot be automated due to platform limitations.

## Permissions

| Role | Script Access | Portal Access |
|------|---------------|---------------|
| Platform Ops Team | Run all scripts | Full access to Deployment Pipeline Configuration |
| Environment Admins | Run inventory script | Read access to environments |
| Compliance Reviewers | View reports | Read-only portal access |
| Auditors | View reports | View run history |

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| PAC CLI auth fails | Token expired | Run `pac auth create` to reauthenticate |
| Graph email fails | Missing permissions | Ensure Mail.Send consent granted |
| Cannot find pipelines app | App not installed | Install Power Platform Pipelines on host |
| Force Link fails | Environment protected | Check for environment locks, contact support |
| Environment not listed | Filtered by type | Ensure including all environment types |

## FSI Regulatory Alignment

This solution supports compliance with:

| Regulation | Requirement | How This Helps |
|------------|-------------|----------------|
| **OCC 2011-12** | Change management controls | Documents all pipeline changes with audit trail |
| **FFIEC IT Handbook** | Configuration management | Supports centralized deployment infrastructure |
| **SOX 404** | IT general controls | Provides evidence of controlled deployments |
| **FINRA 4511** | Books and records | Maintains inventory and cleanup documentation |

## Documentation

| Guide | Description |
|-------|-------------|
| [AUTOMATION_GUIDE.md](./AUTOMATION_GUIDE.md) | Power Automate trigger-based monitoring |
| [PORTAL_WALKTHROUGH.md](./PORTAL_WALKTHROUGH.md) | Manual force-link UI procedures |
| [LIMITATIONS.md](./LIMITATIONS.md) | Technical constraints and alternatives |
| [NOTIFICATION_TEMPLATES.md](./NOTIFICATION_TEMPLATES.md) | Email and Teams notification templates |
| [SETUP_CHECKLIST.md](./SETUP_CHECKLIST.md) | Quick deployment checklist |

## Related Controls

This solution supports:

- [Control 2.3: Change Management and Release Planning](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.3-change-management-and-release-planning.md)
- [Control 2.1: Managed Environments](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.1-managed-environments.md)

## Version

1.0.3 - January 2026

See [CHANGELOG.md](./CHANGELOG.md) for version history.

## License

MIT - See LICENSE in repository root
