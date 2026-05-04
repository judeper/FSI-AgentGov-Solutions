# Pipeline Governance Cleanup

> **Status:** Completed

Discover, notify, and clean up personal Power Platform pipelines before enforcing centralized ALM governance.

> **Important:** This solution requires both **automated scripts** AND **manual admin actions**. Force-linking environments to a custom pipelines host cannot be automated - it requires UI interaction in the Deployment Pipeline Configuration app. See [Limitations](docs/limitations.md) for details.

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
| Force-link environments | **Manual Only** | [Portal walkthrough](docs/portal-walkthrough.md) |
| Send owner notifications | **Automated** | Microsoft Graph (delegated or application permissions) |
| Monitor new deployments | **Automated** | Power Automate trigger events |

See [Limitations](docs/limitations.md) for detailed explanation of technical constraints.

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
2. Use a dedicated Production or Sandbox environment with a Dataverse database for the custom host (Microsoft recommends a dedicated Production host)
3. **Install Power Platform Pipelines app** (required for Deployment Pipeline Configuration)
4. Verify the Deployment Pipeline Configuration model-driven app is accessible
5. Note the environment ID for configuration

> **Important:** All target environments used in pipelines must be Managed Environments. Starting February 2026, Microsoft will start enabling Managed Environments for pipeline targets that are not already enabled. Review targets now and either enable them manually or configure the pipelines host setting for automatic conversion. See [Microsoft Learn: Managed Environments](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-overview).

See [Microsoft Learn: Set Up Pipelines](https://learn.microsoft.com/en-us/power-platform/alm/set-up-pipelines) for host environment setup.

> **Understanding Host Types:** Power Platform pipelines can use the **platform host** (automatically provisioned, infrastructure-managed, limited governance) or a **custom host** (manually configured, full governance control). This solution requires a custom host. If your organization uses the platform host (no "Power Platform Pipelines" app visible in your environment's D365 apps list), you must create a custom host first. See [Portal Walkthrough Part 0](docs/portal-walkthrough.md#part-0-identify-your-pipelines-host-environment).

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

---

## New Deployment (Greenfield)

Use this path if your organization has **no existing personal pipelines or custom hosts**. This is a clean-slate implementation.

### Before You Start (Pre-Flight Checklist)

Complete these checks before proceeding:

- [ ] **Confirm no existing custom hosts** - Run [Part 0 of the Portal Walkthrough](docs/portal-walkthrough.md#part-0-identify-your-pipelines-host-environment) to verify no environments have the Power Platform Pipelines app installed
- [ ] **Verify admin role** - Confirm you have Power Platform Admin or Entra Global Admin role
- [ ] **Identify host environment** - Select an environment to become your custom host (must have Dataverse provisioned)
- [ ] **Confirm target environments are (or can be) Managed Environments** - all pipeline targets must be Managed Environments; Microsoft will start enabling unmanaged targets beginning February 2026
- [ ] **Document planned pipeline structure** - Sketch your intended deployment stages (e.g., Dev → Test → Prod)
- [ ] **Identify initial makers** - List users who will need pipeline creation access

### Quick Start for New Implementations

If all pre-flight checks pass, follow these steps:

1. **Verify clean state**
   - Run Part 0 of the [Portal Walkthrough](docs/portal-walkthrough.md) to confirm no custom hosts exist
   - Run `pac pipeline list` across environments—if no pipelines are detected, this is *indicative* of greenfield state
   - **Required:** Manually verify in the Deployment Pipeline Configuration app that no custom hosts exist, even if `pac pipeline list` returns no pipelines. The CLI cannot detect all host configurations.

2. **Create custom host**
   - Install Power Platform Pipelines app in your designated host environment
   - See [Microsoft Learn: Set up a custom host](https://learn.microsoft.com/en-us/power-platform/alm/custom-host-pipelines)

3. **Set as default host**
   - Configure your custom host as the tenant default
   - This routes new pipeline creation to your host
   - See [Microsoft Learn: Set a default pipelines host](https://learn.microsoft.com/en-us/power-platform/alm/set-a-default-pipelines-host)
   - **Verification:** After setting the default host, it may take a few minutes to propagate. Verify by having a user with maker permissions (but not admin) attempt to create a pipeline in a separate development environment. They should be automatically directed to your custom host.

4. **Link development source environments**
   - Add the environments where makers will build solutions (your development source environments) to your custom host via the Deployment Pipeline Configuration app
   - See [Portal Walkthrough Part 3](docs/portal-walkthrough.md#part-3-force-link-an-environment)

5. **Restrict pipeline creation (Security Best Practice)**
   - Grant the **Deployment Pipeline Default** role only to approved makers, or manage access through the **Deployment Pipeline Makers** team in the Deployment Pipeline Configuration app
   - In custom hosts, lightweight pipeline creation is not granted to all users by default
   - See [Portal Walkthrough Part 7](docs/portal-walkthrough.md#part-7-managing-pipeline-creator-access)

6. **Skip to monitoring**
   - No cleanup needed for greenfield deployments
   - Proceed directly to [Step 6: Set Up Ongoing Monitoring](#step-6-set-up-ongoing-monitoring-optional)

> **FSI Note:** For U.S. Financial Services organizations, restricting the **Deployment Pipeline Default** role is a security best practice. It narrows who can create lightweight pipelines in the default custom host. See [Limitations Section 6](docs/limitations.md#6-force-link-controls-environment-host-association) for details on what this controls.

### Greenfield vs Brownfield

| Scenario | Path | Documentation |
|----------|------|---------------|
| **Greenfield** - No existing pipelines | Use Quick Start above | This section |
| **Brownfield** - Existing personal pipelines | Follow full cleanup workflow | [Migration Guide](docs/migration-guide.md) |
| **Mixed** - Some environments have pipelines | Treat as brownfield | [Migration Guide](docs/migration-guide.md) |

---

## Data Model

### System Tables (Pipelines Host Environment)

Power Platform pipelines use system-managed Dataverse tables in the pipelines host environment. Logical names below follow Dataverse convention: the Microsoft Learn `SchemaName` lowercased with no extra underscores. Use [Microsoft Learn: Pipeline table reference](https://learn.microsoft.com/power-platform/developer/pipelines/table-reference) as the source of truth.

These tables are **not queryable via standard Power Automate "List rows" actions** for governance inventory. Use pipeline trigger events, the Deployment Pipeline Configuration app, or supported PAC CLI commands for operational workflows.

#### DeploymentArtifact (`deploymentartifact`)

Stores managed and unmanaged solution artifacts exported during pipeline runs.

| Logical name | Type | Description |
|--------------|------|-------------|
| deploymentartifactid | GUID (PK) | Unique identifier for artifact instances |
| name | Text | Artifact record name |
| artifactversion | Text | Solution artifact version |
| generatedon | DateTime | Date/time when the artifact was generated |
| artifactfile | File | Managed artifact file (not valid for create) |
| artifactfileunmanaged | File | Unmanaged artifact file (not valid for create) |
| ownerid | Owner | Artifact owner |
| statuscode | Status | `1` Active, `2` Inactive |

#### DeploymentPipeline (`deploymentpipeline`)

Stores pipeline configuration records.

| Logical name | Type | Description |
|--------------|------|-------------|
| deploymentpipelineid | GUID (PK) | Unique identifier for pipeline instances |
| name | Text | Pipeline record name |
| description | Text | Optional pipeline description |
| ownerid | Owner | Pipeline owner |
| statuscode | Status | `1` Active, `2` Inactive |

#### DeploymentStage (`deploymentstage`)

Stores deployment-stage configuration such as target environment and prerequisite stage.

| Logical name | Type | Description |
|--------------|------|-------------|
| deploymentstageid | GUID (PK) | Unique identifier for the stage instance |
| name | Text | Stage name (for example, `Dev`, `Test`, `Prod`) |
| description | Text | Optional stage description |
| deploymentpipelineid | Lookup | Parent pipeline |
| targetdeploymentenvironmentid | Lookup | Target deployment environment |
| previousdeploymentstageid | Lookup | Previous stage required before this stage can run |
| ownerid | Owner | Stage owner |
| statuscode | Status | `1` Active, `2` Inactive |

#### DeploymentEnvironment (`deploymentenvironment`)

Stores environment records linked to the pipelines host.

| Logical name | Type | Description |
|--------------|------|-------------|
| deploymentenvironmentid | GUID (PK) | Unique identifier for deployment environment instances |
| name | Text | Deployment environment record name |
| environmentid | String | Power Platform environment ID |
| environmenttype | Picklist | `200000000` Development Environment, `200000001` Target Environment |
| validationstatus | Picklist | `200000000` Pending, `200000001` Success, `200000002` Failed (not valid for create) |
| errormessage | Text | Environment validation failure details |
| ownerid | Owner | Environment record owner |
| statuscode | Status | `1` Active, `2` Inactive |

**Important:** The `deploymentpipeline` table does NOT have a direct reference to which host environment it belongs to. The relationship is implicit through the environment where the table resides.

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
.\scripts\Get-PipelineInventory.ps1 -OutputPath ".\reports\environment-inventory.csv" -ProbePipelines
```

This produces a CSV with all environments and indicates which have pipelines (`HasPipelinesEnabled` column). **Manual review is required** to identify which pipelines host those environments are linked to.

> **Important:** The `-ProbePipelines` output is **directional only**. Text parsing of `pac pipeline list` may produce false negatives if output formatting changes. Do not rely solely on this output for enforcement decisions—require manual validation via the Deployment Pipeline Configuration app before executing force-link operations.

### Step 2: Manual Pipeline Assessment

For each environment in the inventory:

1. Open [Power Platform Admin Center](https://admin.powerplatform.microsoft.com)
2. Select the environment
3. Check **Resources** > **Dynamics 365 apps** for "Power Platform Pipelines"
4. If installed, note the pipelines host association
5. Mark environments that need force-linking

See [Portal Walkthrough](docs/portal-walkthrough.md) for detailed steps.

### Step 3: Prepare Notification List

Add owner information to your inventory:

1. Export environments needing action to separate CSV
2. Add `OwnerEmail` and `OwnerName` columns
3. Look up owners in admin center or via Microsoft Entra ID

### Step 4: Notify Owners

Send notifications to pipeline owners:

```powershell
.\scripts\Send-OwnerNotifications.ps1 `
    -InputPath ".\reports\non-compliant.csv" `
    -EnforcementDate "2026-03-01" `
    -TestMode  # Remove to send actual emails
```

See [Notification Templates](docs/notification-templates.md) for email templates.

### Step 5: Execute Force Link (Manual)

After notification period (30-60 days):

1. Open Deployment Pipeline Configuration app on your designated host
2. Navigate to **Environments**
3. Add each non-compliant environment
4. Use **Force Link** button if already linked to another host
5. Document in tracking table/spreadsheet

See [Portal Walkthrough](docs/portal-walkthrough.md) for complete walkthrough.

### Step 6: Set Up Ongoing Monitoring (Optional)

Use Power Automate triggers to monitor for new pipeline activity:

- `OnDeploymentRequested` - New deployment initiated
- `OnDeploymentCompleted` - Deployment finished

See [Automation Guide](docs/automation-guide.md) for trigger configuration.

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
Execute Force Link (MANUAL - Admin Portal)
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
| Power Platform Pipelines app not visible | Using platform host instead of custom host | See Portal Walkthrough Part 0; platform host is infrastructure-managed |
| PAC CLI returns no pipelines | Wrong auth context | Run `pac auth list`; must authenticate to HOST environment, not dev/target |
| Users still creating personal pipelines | Force Link controls host association, not creation | See Limitations section 6; restrict **Deployment Pipeline Default** or **Deployment Pipeline Makers** access |

### Error Recovery Procedures

#### Notification Script Fails Mid-Run

**Symptoms:** Some emails sent, script error, incomplete run

**Recovery:**

1. Check console output for last successful email
2. Filter CSV to remaining records (not yet notified)
3. Re-run with filtered CSV
4. Emails are idempotent - resending is safe (recipients may receive duplicate)

**Prevention:** Use `-TestMode` first to validate CSV and connectivity.

#### Force Link Fails with "Environment Protected"

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

#### Environment Appears in Wrong Host After Force Link

**Symptoms:** Environment shows in old host, not new host

**Recovery:**

1. Wait 15-30 minutes for propagation
2. Refresh browser and clear cache
3. Verify force-link was confirmed (check for confirmation dialog)
4. If still wrong after 1 hour, re-attempt force-link from correct host
5. Contact Microsoft Support if issue persists

## Data Handling and PII

This solution generates files containing personally identifiable information (PII):

| File | PII Fields | Generated By |
|------|-----------|--------------|
| Environment inventory CSV | OwnerEmail, OwnerName (after manual enrichment) | Get-PipelineInventory.ps1 |
| Non-compliant CSV | OwnerEmail, OwnerName | Manual preparation |
| Notification audit log | Recipient email, environment IDs | Send-OwnerNotifications.ps1 |

**Recommendations for FSI environments:**

- **Classification:** Treat generated CSVs as internal/confidential per your data classification policy
- **Storage:** Store in a location with appropriate access controls (e.g., SharePoint with restricted permissions, not shared drives)
- **Retention:** Retain notification logs and inventory records per your records retention schedule (typically 7 years for FINRA Rule 4511(a))
- **Secure deletion:** After the retention period, securely delete files per your organization's data disposal procedures
- **Access:** Limit access to the Platform Operations team and authorized auditors

> **GLBA Section 501(b):** Organizations subject to GLBA should verify that generated files are stored in compliance with their information security program safeguards.

## FSI Regulatory Alignment

This solution supports compliance with:

| Regulation | Requirement | How This Helps |
|------------|-------------|----------------|
| **OCC 2011-12** (Sound Practices for Model Risk Management) | Change management controls | Documents all pipeline changes with audit trail |
| **FFIEC IT Handbook** | Configuration management | Supports centralized deployment infrastructure |
| **SOX Section 404** | IT general controls — management assessment | Provides evidence of controlled deployments |
| **FINRA Rule 4511(a)** | Books and records retention | Maintains inventory and cleanup documentation |
| **FINRA Rule 3110(a)** | Supervisory system requirements | Pipelines provide approval gates for supervisory control of deployments |

## Documentation

| Document | Description |
|----------|-------------|
| [Setup Checklist](docs/setup-checklist.md) | Step-by-step deployment checklist |
| [Automation Guide](docs/automation-guide.md) | Scheduled automation configuration |
| [Portal Walkthrough](docs/portal-walkthrough.md) | Force-link environments in Power Platform admin |
| [Migration Guide](docs/migration-guide.md) | Brownfield migration from personal pipelines |
| [Notification Templates](docs/notification-templates.md) | Email and Teams notification templates |
| [Audit Checklist](docs/audit-checklist.md) | Compliance audit verification checklist |
| [Limitations](docs/limitations.md) | Known limitations and workarounds |
| [templates/](./templates/) | Sample CSV files for scripts |

## Related Controls

This solution supports:

- [Control 2.3: Change Management and Release Planning](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.3-change-management-and-release-planning.md)
- [Control 2.1: Managed Environments](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.1-managed-environments.md)

## Version

1.2.1 - Microsoft Learn 2026-Q2 refresh

See [CHANGELOG.md](./CHANGELOG.md) for version history.

## License

MIT - See LICENSE in repository root
