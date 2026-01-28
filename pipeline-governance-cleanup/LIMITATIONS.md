# Solution Limitations

This document explains the technical limitations of Power Platform pipelines governance automation and provides alternatives for each constraint.

> **Summary:** Full automation of pipeline governance cleanup is not possible due to Power Platform's architecture. This solution provides partial automation where available and documented manual procedures for the rest.

---

## Critical Limitations

### 1. `pac pipeline link` Command Does NOT Exist

**What the documentation originally claimed:**
```powershell
# THIS COMMAND DOES NOT EXIST:
pac pipeline link --environment-id <target-env-id> --host-environment-id <host-env-id>
```

**Reality:** The Power Platform CLI (`pac`) has only two pipeline-related commands:
- `pac pipeline list` - Lists pipelines in an environment
- `pac pipeline deploy` - Triggers a pipeline deployment

There is no CLI command to link or force-link environments to a pipelines host.

**Source:** [PAC CLI Pipeline Reference](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/pipeline)

**Alternative:** Manual UI in Deployment Pipeline Configuration app. See [PORTAL_WALKTHROUGH.md](./PORTAL_WALKTHROUGH.md).

---

### 2. DeploymentPipeline Table Cannot Be Queried via "List rows"

**What the documentation originally claimed:**
> Use Power Automate "List rows" action to query the DeploymentPipeline table.

**Reality:** The `DeploymentPipeline` table is a system-managed table that is NOT exposed to standard Dataverse query operations in Power Automate. Attempting to use "List rows" with this table will fail or return no results.

**Why:** Microsoft restricts direct query access to pipeline system tables to prevent interference with the pipeline execution engine.

**What IS available:**
- **Pipeline trigger events** - Power Automate can respond to deployment lifecycle events
- **Direct Dataverse API** - With appropriate permissions, advanced users can query via Web API
- **Deployment Pipeline Configuration app** - UI access for administrators

**Alternative:** Use pipeline triggers (`OnDeploymentCompleted`, etc.) for event-based monitoring. See [AUTOMATION_GUIDE.md](./AUTOMATION_GUIDE.md).

---

### 3. Cannot Identify Pipelines Host Association via API

**The problem:** There is no field in the `DeploymentPipeline` table (or related tables) that indicates which host environment the pipeline belongs to. The association is implicit - a pipeline belongs to whichever environment's Dataverse database contains it.

**Why this matters:** You cannot programmatically determine "which environments have pipelines hosted outside the designated host" because:
1. You can't query the DeploymentPipeline table
2. Even if you could, there's no "host environment ID" field
3. Each environment's pipelines live in that environment's Dataverse

**Alternative:**
1. List all environments via PowerShell/PAC CLI
2. Manually check each environment for the Pipelines app
3. Use the Deployment Pipeline Configuration app to see linked environments
4. Build your own tracking table/spreadsheet

---

### 4. Force-Link Is UI-Only

**The problem:** Associating (or force-linking) an environment to a pipelines host can ONLY be done through the Deployment Pipeline Configuration model-driven app UI. There is no:
- API endpoint
- CLI command
- Power Automate action
- PowerShell cmdlet

**Why:** Microsoft designed force-linking as an intentional administrative action with confirmation dialogs to prevent accidental breaking of existing pipeline configurations.

**Alternative:** Document a manual procedure and train administrators. See [PORTAL_WALKTHROUGH.md](./PORTAL_WALKTHROUGH.md).

---

## What CAN Be Automated

Despite the limitations above, several governance tasks can be automated:

| Task | Method | Notes |
|------|--------|-------|
| List all environments | PowerShell + PAC CLI | Full automation |
| Export environment metadata | PowerShell | Environment type, managed status, etc. |
| Resolve user emails | Microsoft Graph API | Look up owner details |
| Send notification emails | Microsoft Graph API | Full automation |
| Post Teams alerts | Power Automate | Full automation |
| Monitor deployments | Power Automate triggers | Event-based only |
| Track compliance status | Custom Dataverse table | Manual updates required |

---

## Microsoft Documentation Sources

These are the authoritative sources confirming the limitations:

### PAC CLI Pipeline Commands

**URL:** https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/pipeline

**Available commands:**
- `pac pipeline list` - List pipelines
- `pac pipeline deploy` - Deploy a pipeline

**Not available:** link, create, delete, configure

### Extend Pipelines in Power Platform

**URL:** https://learn.microsoft.com/en-us/power-platform/alm/extend-pipelines

**What's documented:**
- Pipeline extensibility through Dataverse triggers
- Pre and post deployment customization
- Event-based integration

**What's NOT documented:** Querying pipeline tables, programmatic linking

### Set Up Custom Host for Pipelines

**URL:** https://learn.microsoft.com/en-us/power-platform/alm/custom-host-pipelines

**Key statement:**
> "Link development environments to the pipelines host using the Deployment Pipeline Configuration app"

**Implication:** The documentation only describes UI-based linking, confirming no API exists.

---

## Setting Customer Expectations

When implementing this solution, communicate these realities:

### What This Solution Provides

| Capability | Delivery |
|------------|----------|
| Discovery | PowerShell scripts export environment list |
| Communication | Automated email notifications to owners |
| Tracking | Custom Dataverse table or Excel spreadsheet |
| Monitoring | Trigger-based alerts for deployment events |
| Procedures | Documented manual steps for force-linking |

### What This Solution Does NOT Provide

| Capability | Reality |
|------------|---------|
| Automated enforcement | Admin must manually force-link each environment |
| Self-service cleanup | Makers cannot self-migrate pipelines |
| Pipeline inventory export | Cannot query DeploymentPipeline table |
| Scheduled force-link | Force-link is always manual |
| API-based compliance check | Must use UI or manual verification |

### Recommended Customer Communication

Include this in your governance communications:

> **Pipeline Governance Notice**
>
> Our organization is consolidating deployment pipelines to a centralized host.
>
> **Automated steps:**
> - You will receive email notification before any changes
> - 30-60 day notice period for migration
>
> **Manual steps (performed by admins):**
> - Environments will be force-linked to the corporate host
> - This action cannot be undone without admin intervention
>
> **Your action required:**
> - Migrate pipelines to the corporate host, OR
> - Request an exemption with business justification

---

## Future Considerations

Microsoft's Power Platform roadmap may address some limitations:

### Potential Future Capabilities

| Capability | Status | Notes |
|------------|--------|-------|
| API for pipeline management | Not announced | Would enable full automation |
| CLI force-link command | Not announced | Would enable scripted enforcement |
| Query support for system tables | Unlikely | Security/stability concerns |
| Bulk environment linking | Not announced | Would speed up migrations |

### Workaround Strategies

Until Microsoft provides APIs:

1. **Azure Automation + UI Automation**
   - Use browser automation (Selenium, Playwright) to script the UI
   - High maintenance burden, brittle to UI changes
   - Not recommended for production

2. **Dataverse Web API Direct Access**
   - With System Administrator role, may be able to query/modify system tables
   - Unsupported, may break with updates
   - Not recommended

3. **Microsoft Support Engagement**
   - For large-scale migrations, engage Microsoft support
   - They may have internal tools for bulk operations
   - Recommended for 100+ environment migrations

---

## Summary

| Limitation | Severity | Workaround |
|------------|----------|------------|
| No `pac pipeline link` | **Critical** | Manual UI procedure |
| Can't query DeploymentPipeline | **Critical** | Use triggers only |
| No host association field | **High** | Manual verification |
| Force-link is UI-only | **High** | Documented procedure |
| Can't detect all pipelines | **Medium** | Event-based monitoring |

**Bottom line:** This solution automates what can be automated (discovery, notification, monitoring) and provides clear documentation for the manual steps that remain unavoidable.

---

## See Also

- [AUTOMATION_GUIDE.md](./AUTOMATION_GUIDE.md) - What CAN be automated
- [PORTAL_WALKTHROUGH.md](./PORTAL_WALKTHROUGH.md) - Manual UI procedures
- [README.md](./README.md) - Solution overview
