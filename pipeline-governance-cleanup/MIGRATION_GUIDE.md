# Brownfield Migration Guide

This guide provides a structured approach for migrating existing Power Platform pipeline deployments to a centralized governance host. Use this guide when your organization has existing personal pipelines that need consolidation.

---

## When to Use This Guide

Use this guide if your organization has:

- **Existing personal pipelines** - Makers have created pipelines in multiple environments
- **Multiple pipeline hosts** - Discovery found more than one custom host environment
- **Platform host usage** - Some environments use Microsoft's infrastructure-managed host
- **Need for coordinated migration** - You want to migrate without disrupting active deployments

If your organization has **no existing pipelines** (greenfield), see the [Greenfield Quick Start](./README.md#new-deployment-greenfield) section instead.

---

## Migration Phases

### Phase 1: Pre-Migration Assessment

Before migrating, document your current state completely.

#### 1.1 Environment Inventory

Run the inventory script to identify all environments:

```powershell
.\src\Get-PipelineInventory.ps1 -OutputPath ".\reports\pre-migration-inventory.csv" -ProbePipelines
```

#### 1.2 Identify Active Pipelines and Owners

For each environment with `HasPipelinesEnabled = "Yes"`:

1. Open the Deployment Pipeline Configuration app **in the environment where the pipeline was created (the original host)**
2. Navigate to **Pipelines** to see active pipelines
3. Note the pipeline name, owner, and target environments
4. Record the last deployment date

**Create a tracking spreadsheet:**

| Pipeline Name | Owner Email | Source Environment | Target Environments | Last Deployment | Migration Status |
|--------------|-------------|-------------------|---------------------|-----------------|------------------|
| Sales-CI-CD | sales@co.com | Sales-Dev | Sales-Test, Sales-Prod | 2026-01-15 | Pending |

#### 1.3 Map Maker Dependencies

Identify which makers depend on each pipeline:

1. Check pipeline permissions in the Deployment Pipeline Configuration app
2. Review solution ownership in target environments
3. Interview environment owners about deployment frequency

---

### Phase 2: Coexistence Period Management

> **Warning: Avoid Force Linking Environments with In-Flight Deployments**
> Do not execute a Force Link operation on an environment that has an active deployment in progress. The Force Link will orphan the in-flight deployment, and it will not complete. Coordinate with makers to ensure all deployments are complete before migrating an environment.

During migration, both old and new hosts operate in parallel. Plan for a **30-60 day coexistence period**.

#### 2.1 Timeline and Milestones

| Day | Milestone | Action |
|-----|-----------|--------|
| 0 | Discovery Complete | Inventory finalized, tracking spreadsheet created |
| 1-3 | Initial Notification | Send notifications using [NOTIFICATION_TEMPLATES.md](./NOTIFICATION_TEMPLATES.md) |
| 7 | Migration Window Opens | Central host is ready; makers can begin recreating pipelines |
| 14 | First Reminder | Send reminder to makers who haven't migrated |
| 28 | Final Notice | Send escalation notice (final warning) |
| 30-60 | Force-Link Execution | Execute force-link for remaining environments |
| +7 | Post-Migration | Verify all environments, notify completion |

#### 2.2 Communication Milestones

Use templates from [NOTIFICATION_TEMPLATES.md](./NOTIFICATION_TEMPLATES.md) at each milestone:

- **Day 1-3**: Owner Notification template
- **Day 14**: First Reminder (modified subject)
- **Day 28**: Escalation Email template
- **Day 30-60**: Confirmation Email template

#### 2.3 Migration Priority Order

Migrate environments in this order to minimize disruption:

| Priority | Environment Type | Rationale |
|----------|-----------------|-----------|
| 1 | Production (target) | Most critical; migrate first to establish governance |
| 2 | UAT/QA (target) | Second most critical for testing path |
| 3 | Development (source) | Migrate after targets are linked |
| 4 | Sandbox (general) | Lower risk; migrate last |

**Why this order?** Production environments receive deployments. Linking them to the central host first ensures all future deployments are governed. Development environments are where pipelines originate; linking them last gives makers maximum time to adjust.

#### 2.4 Tracking Migration Progress

Update your tracking spreadsheet as environments migrate:

| Environment | Force-Link Date | Verified | Maker Notified | Notes |
|-------------|-----------------|----------|----------------|-------|
| Sales-Prod | 2026-02-01 | Yes | 2026-02-01 | No issues |
| Sales-Test | 2026-02-01 | Yes | 2026-02-01 | |
| Sales-Dev | 2026-02-05 | Yes | 2026-02-05 | Maker recreated pipeline |

---

### Phase 3: Maker Transition Support

When you force-link an environment, makers lose the ability to deploy from their old pipelines. Provide clear guidance for recreating pipelines.

#### 3.1 Pipeline Recreation Steps

**For makers who need to recreate pipelines in the central host:**

1. **Request access to corporate host**
   - Contact Platform Ops or submit a request via your ticketing system
   - Specify which environments you need to deploy to
   - Await role assignment (Deployment Pipeline User or higher)

2. **Open Deployment Pipeline Configuration app**
   - Navigate to the corporate host environment
   - Open the Deployment Pipeline Configuration model-driven app
   - You should see **Pipelines** in the left navigation

3. **Create new pipeline**
   - Click **Pipelines** > **+ New**
   - Enter pipeline name (e.g., "Sales-CI-CD")
   - See [Microsoft Learn: Create a deployment pipeline](https://learn.microsoft.com/en-us/power-platform/alm/set-up-pipelines#create-a-deployment-pipeline)

4. **Add stages**
   - Click **Stages** > **+ New Stage**
   - Configure your deployment path (e.g., Dev → Test → Prod)
   - Link to target environments already associated with the host

5. **Configure permissions**
   - Add team members who need deployment access
   - Set approval requirements if needed

6. **Test with non-production deployment**
   - Run a test deployment to a non-production environment
   - Verify solution deploys correctly
   - Check deployment history in the app

#### 3.2 Self-Service vs Admin-Assisted Migration

| Scenario | Approach | When to Use |
|----------|----------|-------------|
| **Self-Service** | Maker recreates their own pipeline | Maker is comfortable with pipelines; simple pipeline structure |
| **Admin-Assisted** | Platform admin recreates on behalf of maker | Complex pipelines; maker unfamiliar with process; time-sensitive |
| **Template-Based** | Admin provides pre-configured pipeline template | Multiple similar pipelines needed; standardization required |

**Guidance for makers:**

> Your old pipeline in [Old Host] can no longer deploy to [Environment Name]. To continue deployments:
>
> 1. Access the corporate pipelines host: [Link to environment]
> 2. Create a new pipeline following the steps above
> 3. If you need assistance, contact Platform Ops at [support email]
>
> Your solution data in [Environment Name] is unaffected. Only the deployment pipeline configuration needs to be recreated.

---

### Phase 4: Post-Migration Validation

After force-linking all environments, verify the migration succeeded.

#### 4.1 Verification Checklist

- [ ] All target environments appear in central host's **Environments** list
- [ ] All environments show **Status = Active**
- [ ] Test deployment succeeds to at least one production environment
- [ ] Makers confirm they can create and run pipelines in central host
- [ ] Old host environments are documented (do not delete yet)

#### 4.2 Old Host Decommissioning Criteria

**Do NOT delete old host environments until:**

- [ ] All environments have been force-linked for 30+ days
- [ ] No deployment activity in old host for 60+ days
- [ ] Retention period requirements are met (typically 7 years for FSI)
- [ ] Audit evidence has been captured (screenshots, export of pipeline history)

**FSI Retention Note:** Financial services regulations often require 7-year retention of business records. Pipeline deployment history may be considered a business record. Consult your compliance team before deleting any pipelines host environment.

#### 4.3 Documentation for Audit

Retain the following evidence:

| Evidence | Format | Retention |
|----------|--------|-----------|
| Pre-migration inventory CSV | CSV file | 7 years |
| Post-migration inventory CSV | CSV file | 7 years |
| Notification emails sent | Email archive or CSV | 7 years |
| Force-link tracking spreadsheet | Excel/CSV | 7 years |
| Screenshots of old host pipelines | PNG/PDF | 7 years |

---

## Coexistence Failure Scenarios

During the coexistence period, several issues may arise. Use this table to troubleshoot.

| Scenario | Impact | Resolution |
|----------|--------|------------|
| **Maker creates new pipeline in old host** | Pipeline works but deploys from ungoverned host | Communicate with maker; force-link their development environment to disable old host deployments |
| **Force-link fails with "environment protected"** | Environment may have a lock or backup in progress | Wait 15 minutes and retry; check for environment locks in Admin Center; contact Microsoft Support if persists |
| **Maker reports "lost pipelines"** | Expected - old pipelines are orphaned by design | Direct maker to [Pipeline Recreation Steps](#31-pipeline-recreation-steps); this is expected behavior |
| **Concurrent force-link attempts** | Last action wins; unpredictable results | Coordinate among admins: one admin per environment; use tracking spreadsheet to assign ownership |
| **Environment shows in wrong host after force-link** | Caching or propagation delay | Wait 15-30 minutes; refresh browser; re-attempt if still wrong after 1 hour |
| **Maker cannot access central host** | Missing role assignment | Assign Deployment Pipeline User role in central host; verify environment permissions |
| **Test deployment fails** | Misconfiguration or permission issue | Verify stage configuration; check target environment permissions; ensure maker has solution export rights |

---

## Rollback During Migration

If you need to reverse a force-link during the coexistence period:

1. Open the **original host** environment's Deployment Pipeline Configuration app
2. Add the environment back (this will force-link it to the original host)
3. Confirm the action

**Warning:** Each force-link is disruptive to makers using the other host. Coordinate carefully and communicate changes.

See [PORTAL_WALKTHROUGH.md Part 6: Reversing a Force-Link](./PORTAL_WALKTHROUGH.md#part-6-reversing-a-force-link-rollback) for detailed rollback procedures.

---

## Quick Reference

| Document | Purpose |
|----------|---------|
| [PORTAL_WALKTHROUGH.md](./PORTAL_WALKTHROUGH.md) | Step-by-step force-link UI procedures |
| [NOTIFICATION_TEMPLATES.md](./NOTIFICATION_TEMPLATES.md) | Email and Teams templates for communication |
| [LIMITATIONS.md](./LIMITATIONS.md) | Technical constraints and what cannot be automated |
| [AUDIT_CHECKLIST.md](./AUDIT_CHECKLIST.md) | Compliance evidence requirements |

---

## See Also

- [Microsoft Learn: Custom Host Pipelines](https://learn.microsoft.com/en-us/power-platform/alm/custom-host-pipelines)
- [Microsoft Learn: Set Up Pipelines](https://learn.microsoft.com/en-us/power-platform/alm/set-up-pipelines)
- [Microsoft Learn: Set a Default Pipelines Host](https://learn.microsoft.com/en-us/power-platform/alm/set-a-default-pipelines-host)
