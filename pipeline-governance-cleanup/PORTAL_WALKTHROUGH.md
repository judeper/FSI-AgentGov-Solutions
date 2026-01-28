# Portal Walkthrough: Force-Link Environments

This guide provides step-by-step UI procedures for force-linking environments to your designated pipelines host. **These steps cannot be automated** - they require manual admin interaction in the Power Platform admin center and Deployment Pipeline Configuration app.

---

## Overview

Force-linking an environment:
- Removes the environment from its current pipelines host (if any)
- Associates it with your designated pipelines host
- Enables pipelines created in your host to target this environment
- Makers lose access to pipelines configured in the previous host

---

## Prerequisites

Before starting, ensure you have:

- [ ] **Power Platform Admin** role or **Deployment Pipeline Administrator** role
- [ ] Access to your **designated pipelines host environment**
- [ ] **Power Platform Pipelines app** installed on the host
- [ ] Target environment ID (GUID) to force-link
- [ ] Documentation of current pipeline ownership (for communication)
- [ ] **Target environment is a Managed Environment** - Pipeline targets must be Managed Environments

> **Important:** Starting February 2026, Microsoft requires all pipeline target environments to be Managed Environments. If your target environment is not managed, enable it in Power Platform Admin Center before force-linking. See [Microsoft Learn: Managed Environments](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-overview).

---

## Part 1: Verify Pipelines Host Setup

Before force-linking environments, confirm your pipelines host is properly configured.

### Step 1.1: Access Power Platform Admin Center

1. Navigate to [admin.powerplatform.microsoft.com](https://admin.powerplatform.microsoft.com)
2. Sign in with your admin credentials
3. Select **Environments** from the left navigation

### Step 1.2: Locate Your Pipelines Host

1. Find your designated pipelines host environment in the list
2. Click the environment name to open details
3. Verify:
   - Type is **Production** or **Sandbox** (not Developer)
   - **Managed** shows as "Yes"
   - Dataverse database is provisioned

### Step 1.3: Verify Pipelines App Installation

1. With your host environment selected, click **Resources**
2. Click **Dynamics 365 apps**
3. Look for **Power Platform Pipelines**
4. Status should be **Installed**

If not installed:
1. Click **Install app**
2. Search for "Power Platform Pipelines"
3. Select and install
4. Wait for installation to complete (may take several minutes)

### Step 1.4: Open Deployment Pipeline Configuration App

1. Click **Open** next to Power Platform Pipelines, OR
2. Navigate directly to: `https://[your-host-env].crm.dynamics.com/main.aspx?appid=[app-guid]`
3. You should see the Deployment Pipeline Configuration model-driven app
4. Verify you have access to:
   - **Pipelines** - View existing pipelines
   - **Environments** - Manage linked environments
   - **Stages** - Configure deployment stages

---

## Part 2: Identify Environment's Current Pipeline Status

Before force-linking, understand the environment's current state.

### Step 2.1: Check if Environment Has Pipelines Enabled

1. In Power Platform Admin Center, select the target environment
2. Click **Resources** > **Dynamics 365 apps**
3. Look for **Power Platform Pipelines**

| Status | Meaning |
|--------|---------|
| Not listed | Environment has never been linked to a pipelines host |
| Installed | Environment may have its own pipelines OR is linked to a host |

### Step 2.2: Determine Current Host (if any)

If the environment shows Pipelines installed:

1. Open the environment's URL in a browser
2. Navigate to **Settings** > **Advanced Settings**
3. Look for **Deployment Pipeline Configuration** app
4. If present, this environment may BE a pipelines host
5. Check for existing pipelines targeting other environments

**Note:** There is no direct way to see which host an environment is currently linked to from the target environment. You must check from potential host environments.

### Step 2.3: Check From Your Designated Host

1. Open Deployment Pipeline Configuration on your designated host
2. Click **Environments** in the left navigation
3. Search for the target environment name or ID
4. If listed with status **Active**, it's already linked to your host
5. If not listed, proceed to force-link

---

## Part 3: Force-Link an Environment

### Scenario A: Environment Not Currently Linked

Use this when the target environment has never been linked to any pipelines host.

#### Step 3A.1: Navigate to Environments

1. Open Deployment Pipeline Configuration app on your designated host
2. Click **Environments** in the left navigation
3. You'll see a list of currently linked environments

#### Step 3A.2: Add New Environment

1. Click **+ New** in the command bar
2. In the **New Deployment Environment** form:

| Field | Value |
|-------|-------|
| Name | Friendly name (e.g., "Sales Team Dev") |
| Environment Id | Paste the target environment GUID |
| Environment Type | Select appropriate type |

3. Click **Save**

#### Step 3A.3: Verify Link

1. The environment should appear in your Environments list
2. Status should be **Active**
3. Test by creating a pipeline targeting this environment

---

### Scenario B: Environment Already Linked to Another Host

Use this when the target environment is currently linked to a different pipelines host. **This is the "force-link" scenario.**

#### Step 3B.1: Navigate to Environments

1. Open Deployment Pipeline Configuration app on your designated host
2. Click **Environments** in the left navigation

#### Step 3B.2: Attempt to Add Environment

1. Click **+ New** in the command bar
2. Enter the environment details:

| Field | Value |
|-------|-------|
| Name | Friendly name |
| Environment Id | Target environment GUID |

3. Click **Save**

#### Step 3B.3: Handle "Already Associated" Error

If you see the error:

> "This environment is already associated with another pipelines host"

This indicates the environment is linked to a different host. To proceed:

1. **Communicate with current owner** (recommended)
   - Notify makers who use the current host
   - Provide migration timeline
   - Document acknowledgment

2. **Proceed with force-link:**
   - Look for the **Force Link** button in the command bar
   - Click **Force Link**
   - Confirm the action when prompted

> **Warning:** Force-linking immediately removes the environment from the previous host. Makers using pipelines in that host will lose the ability to deploy to this environment.

#### Step 3B.4: Confirm Force-Link

1. A confirmation dialog will appear:
   > "This will remove the environment from its current pipelines host. Continue?"
2. Click **Confirm** or **Yes**
3. Wait for the operation to complete
4. The environment should now appear in your Environments list

#### Step 3B.5: Verify New Link

1. Refresh the Environments list
2. Find the target environment
3. Status should be **Active**
4. Create a test pipeline targeting this environment to confirm

---

## Part 4: Post-Force-Link Actions

### Step 4.1: Document the Change

Record in your tracking spreadsheet or Dataverse table:

| Field | Value |
|-------|-------|
| Environment ID | Target environment GUID |
| Environment Name | Display name |
| Previous Host | Name/ID of previous host (if known) |
| New Host | Your designated host ID |
| Force-Link Date | Today's date |
| Performed By | Your name/email |
| Reason | Governance consolidation |

### Step 4.2: Notify Affected Users

Send notification to previous pipeline users:

**Subject:** Environment [Name] Pipeline Access Changed

**Body:**
```
The environment [Environment Name] has been consolidated to the corporate
pipelines host as part of our ALM governance initiative.

What changed:
- Pipelines you created in your personal host can no longer deploy to this environment
- New pipelines must be created in the corporate pipelines host

To continue using pipelines:
1. Request access to the corporate pipelines host
2. Recreate your pipeline configurations
3. Contact Platform Ops if you need assistance

Questions? Contact platform-ops@company.com
```

### Step 4.3: Update Compliance Tracking

If using a PipelineCleanupLog table:

1. Find the record for this environment
2. Update:
   - Status = "ForceLinked"
   - Notes = "Force-linked on [date] by [admin]"

---

## Part 5: Bulk Force-Link Process

When force-linking many environments, follow this structured approach.

### Step 5.1: Prepare Environment List

Create a spreadsheet with:

| Environment ID | Environment Name | Owner | Notification Sent | Force-Link Date | Status |
|----------------|------------------|-------|-------------------|-----------------|--------|
| guid-1 | Sales Dev | user@co.com | 2026-01-15 | 2026-02-15 | Pending |
| guid-2 | HR Test | user2@co.com | 2026-01-15 | 2026-02-15 | Pending |

### Step 5.2: Process Environments

For each environment:

1. Open Deployment Pipeline Configuration
2. Click **Environments** > **+ New**
3. Enter Environment ID from your list
4. Click **Save** (or **Force Link** if needed)
5. Update spreadsheet: Status = "ForceLinked"
6. Repeat for next environment

**Tip:** Keep the app open in one browser tab and your spreadsheet in another for efficiency.

### Step 5.3: Verify All Links

After processing all environments:

1. Refresh the Environments list
2. Verify all target environments appear
3. Check Status = Active for each
4. Run a test pipeline to one environment to confirm functionality

---

## Troubleshooting

### Error: "Insufficient privileges"

**Cause:** Missing Deployment Pipeline Administrator role

**Solution:**
1. Go to Power Platform Admin Center
2. Select the pipelines host environment
3. Click **Users** > **Manage users in Dynamics 365**
4. Find your user
5. Assign **Deployment Pipeline Administrator** security role

### Error: "Environment not found"

**Cause:** Invalid environment ID or environment deleted

**Solution:**
1. Verify the environment ID in admin center
2. Ensure environment exists and is active
3. Check for typos in the GUID

### Error: "Force Link button not visible"

**Cause:** May not be available in older versions

**Solution:**
1. Ensure Power Platform Pipelines app is updated
2. Try the operation from a different browser
3. Contact Microsoft Support if persists

### Error: "Operation timed out"

**Cause:** Network issues or service degradation

**Solution:**
1. Wait and retry
2. Check [Power Platform status](https://status.powerplatform.microsoft.com)
3. Try during off-peak hours

### Environment still shows old host after force-link

**Cause:** Caching or propagation delay

**Solution:**
1. Wait 15-30 minutes
2. Refresh the browser
3. Clear browser cache
4. If persists after 1 hour, contact support

---

## Quick Reference

### Admin Center URLs

| Resource | URL |
|----------|-----|
| Power Platform Admin Center | https://admin.powerplatform.microsoft.com |
| Power Apps Maker Portal | https://make.powerapps.com |
| Environment Details | Admin Center > Environments > [Select environment] |

### Key Actions

| Action | Location |
|--------|----------|
| Install Pipelines app | Environment > Resources > Dynamics 365 apps > Install |
| Open Pipeline Config | Environment > Resources > Dynamics 365 apps > Open |
| Add environment | Deployment Pipeline Configuration > Environments > + New |
| Force-link | Deployment Pipeline Configuration > Environments > New > Force Link |

### Required GUIDs

Keep a reference of:
- Your designated pipelines host environment ID
- Target environment IDs to force-link
- Your user ID (for audit trail)

---

## Part 6: Reversing a Force-Link (Rollback)

If you need to move an environment to a different pipelines host after it has been force-linked.

### When to Use

- Force-link was applied to wrong environment
- Business requirement changed requiring different host
- Testing/troubleshooting requires host change
- Team reorganization requires moving to different host

### Understanding Rollback

There is no "unlink" operation. To reverse a force-link, you must force-link the environment to a **different** pipelines host. The environment can only be linked to ONE host at a time.

### Procedure

1. Open **Deployment Pipeline Configuration** app in the **NEW target host** (not the current host)
2. Navigate to **Environments** in the left navigation
3. Click **+ New** to add the environment
4. Enter the environment details (Name, Environment ID)
5. Click **Save**
6. If prompted with "already associated" error, click **Force Link**
7. Confirm the action when prompted

### Impact of Rollback

| Impact | Description |
|--------|-------------|
| **Immediate** | Breaks deployments from the previous host |
| **Pipeline access** | Pipelines in previous host can no longer deploy to this environment |
| **Maker notification** | Pipeline owners in previous host should be notified |
| **No data loss** | Solutions in the environment are not affected |

### Important Notes

- Force-linking is always manual (no API or CLI support)
- Coordinate with pipeline owners in BOTH hosts before executing
- Document the change for audit trail
- Test deployment from new host after rollback

### Rollback Tracking

Update your tracking spreadsheet with rollback details:

| Field | Value |
|-------|-------|
| Environment ID | Target environment GUID |
| Previous Host | Host environment being abandoned |
| New Host | New host environment ID |
| Rollback Date | Today's date |
| Reason | Business justification |
| Performed By | Admin name/email |

---

## See Also

- [LIMITATIONS.md](./LIMITATIONS.md) - Why this cannot be automated
- [AUTOMATION_GUIDE.md](./AUTOMATION_GUIDE.md) - What CAN be automated
- [NOTIFICATION_TEMPLATES.md](./NOTIFICATION_TEMPLATES.md) - Communication templates
- [AUDIT_CHECKLIST.md](./AUDIT_CHECKLIST.md) - Compliance evidence checklist
- [Microsoft Learn: Custom Host Pipelines](https://learn.microsoft.com/en-us/power-platform/alm/custom-host-pipelines)
