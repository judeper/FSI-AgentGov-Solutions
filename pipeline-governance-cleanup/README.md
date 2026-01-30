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
| List all environments | **Automated** | `pac admin list --json` |
| Detect pipeline presence | **Automated** | `pac pipeline list` (text parsing, no --json) |
| Identify pipelines host association | **Manual** | Check each environment in Deployment Pipeline Configuration app |
| Query DeploymentPipeline table via Power Automate | **Not Supported** | Use pipeline trigger events only |
| Force-link environments | **Manual Only** | [Portal walkthrough](./PORTAL_WALKTHROUGH.md) |
| Send owner notifications | **Automated** | Microsoft Graph (delegated or application permissions) |
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

> **Important:** Starting February 2026, Microsoft requires all pipeline target environments to be Managed Environments. Verify your target environments are managed before force-linking. See [Microsoft Learn: Managed Environments](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-overview).

See [Microsoft Learn: Set Up Pipelines](https://learn.microsoft.com/en-us/power-platform/alm/set-up-pipelines) for host environment setup.

> **Understanding Host Types:** Power Platform pipelines can use the **platform host** (automatically provisioned, infrastructure-managed, limited governance) or a **custom host** (manually configured, full governance control). This solution requires a custom host. If your organization uses the platform host (no "Power Platform Pipelines" app visible in your environment's D365 apps list), you must create a custom host first. See [PORTAL_WALKTHROUGH.md Part 0](./PORTAL_WALKTHROUGH.md#part-0-identify-your-pipelines-host-environment).

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

### Step 7: Post-Migration Cleanup

After force-linking environments to the centralized host:

#### 7.1 Verify Pipeline Functionality

1. Run test deployment through new host
2. Confirm target environment receives solution
3. Validate deployment stage sequencing works correctly

#### 7.2 Communicate with Makers

1. Notify pipeline owners their old pipelines are now orphaned
2. Provide guidance on creating new pipelines in central host
3. Offer assistance with pipeline recreation if needed

**Sample communication:**

> Your pipeline targeting [Environment Name] has been migrated to the corporate pipelines host. Pipelines you created in your personal host can no longer deploy to this environment. To continue using pipelines, request access to the corporate host and recreate your pipeline configurations.

#### 7.3 Document Migration

1. Update tracking table with completion date
2. Record any exceptions or issues encountered
3. Note any pending follow-up items

#### 7.4 Review Old Hosts

1. If old host environment is now unused, consider decommissioning
2. Retain pipelines host for audit trail per retention requirements
3. Do not delete old host until retention period expires

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

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| PAC CLI auth fails | Token expired | Run `pac auth create` to reauthenticate |
| Graph email fails | Missing permissions | Ensure Mail.Send consent granted |
| Cannot find pipelines app | App not installed | Install Power Platform Pipelines on host |
| Force Link fails | Environment protected | Check for environment locks, contact support |
| Environment not listed | Filtered by type | Ensure including all environment types |
| Power Platform Pipelines app not visible | Using platform host instead of custom host | See PORTAL_WALKTHROUGH Part 0; platform host is infrastructure-managed |
| PAC CLI returns no pipelines | Wrong auth context | Run `pac auth list`; must authenticate to HOST environment, not dev/target |
| Users still creating personal pipelines | Force Link controls host association, not creation | See LIMITATIONS.md section 6; restrict "Deployment pipeline default" role |

### Error Recovery Procedures

#### Notification Script Fails Mid-Run

**Symptoms:** Some emails sent, script error, incomplete run

**Recovery:**

1. Check console output for last successful email
2. Filter CSV to remaining records (not yet notified)
3. Re-run with filtered CSV
4. Emails are idempotent - resending is safe (recipients may receive duplicate)

**Prevention:** Use `-TestMode` first to validate CSV and connectivity.

#### Force-Link Fails with "Environment Protected"

**Symptoms:** Force Link button errors or environment doesn't link

**Recovery:**

1. Check for environment locks in Admin Center (Settings > Operations)
2. Verify you have Deployment Pipeline Administrator role
3. Check if environment is in a protected state (backup in progress, copy in progress)
4. Wait 15 minutes and retry
5. If persists, contact Microsoft Support with environment ID and error message

#### Inventory Shows "Unknown" for HasPipelinesEnabled

**Symptoms:** `-ProbePipelines` returns "Unknown" for some environments

**Recovery:**

1. This may indicate insufficient permissions for that environment
2. Verify pac auth profile has admin access to the specific environment
3. Some environments may not support pipeline queries (e.g., Default environment)
4. Mark as "Manual Check Required" in tracking spreadsheet
5. Verify pipeline status manually in admin portal

#### Graph API Returns 403 Forbidden

**Symptoms:** Send-OwnerNotifications fails with permission error

**Recovery:**

1. Verify Mail.Send permission is granted (delegated, not application)
2. Ensure you're running as a user with mailbox (not service account)
3. Check if conditional access policies block Graph access
4. Try `Connect-MgGraph -Scopes "Mail.Send"` to re-consent

#### Environment Appears in Wrong Host After Force-Link

**Symptoms:** Environment shows in old host, not new host

**Recovery:**

1. Wait 15-30 minutes for propagation
2. Refresh browser and clear cache
3. Verify force-link was confirmed (check for confirmation dialog)
4. If still wrong after 1 hour, re-attempt force-link from correct host
5. Contact Microsoft Support if issue persists

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
| [PORTAL_WALKTHROUGH.md](./PORTAL_WALKTHROUGH.md) | Manual force-link UI procedures (includes rollback) |
| [LIMITATIONS.md](./LIMITATIONS.md) | Technical constraints and alternatives |
| [NOTIFICATION_TEMPLATES.md](./NOTIFICATION_TEMPLATES.md) | Email and Teams notification templates |
| [SETUP_CHECKLIST.md](./SETUP_CHECKLIST.md) | Quick deployment checklist |
| [AUDIT_CHECKLIST.md](./AUDIT_CHECKLIST.md) | Compliance evidence checklist for auditors |

## Related Controls

This solution supports:

- [Control 2.3: Change Management and Release Planning](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.3-change-management-and-release-planning.md)
- [Control 2.1: Managed Environments](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.1-managed-environments.md)

## Version

1.0.6 - January 2026

See [CHANGELOG.md](./CHANGELOG.md) for version history.

## License

MIT - See LICENSE in repository root
