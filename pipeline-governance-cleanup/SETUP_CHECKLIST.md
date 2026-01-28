# Setup Checklist

Quick deployment checklist for the Pipeline Governance Cleanup solution.

> **Legend:**
> - ✓ = Automated (script/flow available)
> - **[MANUAL]** = Requires admin UI interaction
> - ⚠ = Partially automated (requires manual verification)

---

## Prerequisites

- [ ] Identify pipelines host environment ID (GUID)
- [ ] Confirm Power Platform Admin role assigned
- [ ] **[MANUAL]** Install Power Platform Pipelines app on host environment
- [ ] **[MANUAL]** Verify Deployment Pipeline Configuration app is accessible
- [ ] **[MANUAL]** Verify pipelines host is a Managed Environment
- [ ] **[MANUAL]** Verify target environments are Managed Environments (required starting Feb 2026)
- [ ] Install Power Platform CLI (`pac`): [Download](https://learn.microsoft.com/en-us/power-platform/developer/cli/introduction)
- [ ] Install Microsoft Graph PowerShell SDK: `Install-Module Microsoft.Graph`

---

## Phase 1: Discovery

### Environment Inventory (✓ Automated)

- [ ] Authenticate to Power Platform: `pac auth create`
- [ ] Run inventory script:
  ```powershell
  .\src\Get-PipelineInventory.ps1 -OutputPath ".\reports\environment-inventory.csv"
  ```
- [ ] Review output CSV for environment list

### Pipeline Assessment **[MANUAL]**

For each environment in the inventory:

- [ ] Open Power Platform Admin Center
- [ ] Check if Pipelines app is installed
- [ ] Note current pipelines host association (if any)
- [ ] Mark environments needing force-link in your tracking spreadsheet

See [PORTAL_WALKTHROUGH.md](./PORTAL_WALKTHROUGH.md) for detailed steps.

### Tracking Setup

- [ ] Create tracking spreadsheet or Dataverse table:
  - Environment ID
  - Environment Name
  - Owner Email
  - Current Host
  - Status (Pending, Notified, ForceLinked, Exempted)
  - Notes
- [ ] **[MANUAL]** Populate owner information for each non-compliant environment

---

## Phase 2: Communication

### Notification Preparation

- [ ] Set enforcement date (30-60 days from now)
- [ ] Prepare notification list CSV with columns:
  - `OwnerEmail`
  - `EnvironmentName`
  - `EnvironmentId`
  - `OwnerName` (optional)
- [ ] Review notification templates: [NOTIFICATION_TEMPLATES.md](./NOTIFICATION_TEMPLATES.md)
- [ ] Customize ServiceNow/support URLs in templates

### Send Notifications (✓ Automated)

- [ ] Test notification delivery:
  ```powershell
  .\src\Send-OwnerNotifications.ps1 `
      -InputPath ".\reports\non-compliant.csv" `
      -EnforcementDate "2026-03-01" `
      -TestMode
  ```
- [ ] Review test output for correctness
- [ ] Send actual notifications (remove `-TestMode`)
- [ ] Update tracking: Status = "Notified"

> **Tip:** For automation with service principals, add `-SenderEmail "noreply@contoso.com"` to use application permissions instead of delegated.

---

## Phase 3: Response Period

### Exemption Processing **[MANUAL]**

- [ ] Monitor exemption request inbox/form
- [ ] Review business justifications
- [ ] Document approved exemptions in tracking table
- [ ] Communicate exemption decisions to requestors

### Pre-Enforcement Review **[MANUAL]**

- [ ] Re-run inventory script to check for new environments
- [ ] Verify all notifications were received (check bounces)
- [ ] Confirm stakeholder alignment on enforcement date
- [ ] Update tracking with final status for each environment

---

## Phase 4: Enforcement

### Execute Force-Link **[MANUAL]**

For each non-compliant, non-exempted environment:

- [ ] Open Deployment Pipeline Configuration on your host
- [ ] Navigate to Environments > + New
- [ ] Enter environment ID
- [ ] Click Save (or Force Link if already linked elsewhere)
- [ ] Update tracking: Status = "ForceLinked"
- [ ] Document date and admin performing the action

See [PORTAL_WALKTHROUGH.md](./PORTAL_WALKTHROUGH.md) for detailed steps.

### Post-Enforcement Notification (⚠ Partially Automated)

- [ ] Update notification CSV with force-linked environments
- [ ] Send confirmation emails to affected owners
- [ ] Document completion in audit log

---

## Phase 5: Ongoing Monitoring

### Trigger-Based Monitoring (✓ Automated)

- [ ] Create Power Automate flow for deployment alerts
- [ ] Configure Teams channel for notifications
- [ ] Test trigger fires on deployment
- [ ] Document flow in runbook

See [AUTOMATION_GUIDE.md](./AUTOMATION_GUIDE.md) for flow setup.

### Periodic Review **[MANUAL]**

- [ ] Schedule monthly inventory refresh
- [ ] Review new environments for compliance
- [ ] Process new exemption requests
- [ ] Update governance documentation

---

## Quick Links

| Resource | URL |
|----------|-----|
| Power Platform Admin Center | https://admin.powerplatform.microsoft.com |
| Power Apps Maker Portal | https://make.powerapps.com |
| Power Automate | https://make.powerautomate.com |
| Microsoft Learn: Pipelines | https://learn.microsoft.com/en-us/power-platform/alm/pipelines |
| PAC CLI Reference | https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/pipeline |

---

## Solution Documentation

| Guide | Description |
|-------|-------------|
| [README.md](./README.md) | Solution overview and quick start |
| [AUTOMATION_GUIDE.md](./AUTOMATION_GUIDE.md) | What can be automated (and what cannot) |
| [PORTAL_WALKTHROUGH.md](./PORTAL_WALKTHROUGH.md) | Manual UI procedures for force-linking |
| [LIMITATIONS.md](./LIMITATIONS.md) | Technical constraints explained |
| [NOTIFICATION_TEMPLATES.md](./NOTIFICATION_TEMPLATES.md) | Email and Teams templates |

---

## Troubleshooting Quick Reference

| Issue | Solution |
|-------|----------|
| PAC CLI auth fails | Run `pac auth create` to reauthenticate |
| Graph email fails | Ensure Mail.Send permission granted |
| Can't find Pipelines app | Install Power Platform Pipelines on host |
| Force Link button missing | Update Pipelines app, try different browser |
| Environment not found | Verify environment ID GUID is correct |

**Full troubleshooting:** See [LIMITATIONS.md](./LIMITATIONS.md) and [PORTAL_WALKTHROUGH.md](./PORTAL_WALKTHROUGH.md)

---

## Timeline Template

| Week | Activity | Type |
|------|----------|------|
| Week 1 | Run inventory, identify non-compliant environments | ✓ + **MANUAL** |
| Week 2 | Prepare notification list, send notifications | ✓ Automated |
| Week 3-6 | Response period - process exemptions | **MANUAL** |
| Week 7 | Execute force-link on remaining environments | **MANUAL** |
| Week 8+ | Ongoing monitoring via triggers | ✓ Automated |

---

## Automation Summary

| Task | Status | Method |
|------|--------|--------|
| List environments | ✓ Automated | PowerShell + `pac admin list --json` |
| Detect pipeline presence | ✓ Automated | PowerShell + `pac pipeline list` (text parsing) |
| Identify pipeline host | **MANUAL** | Admin Portal inspection |
| Send notifications | ✓ Automated | PowerShell + Graph API (delegated or application) |
| Process exemptions | **MANUAL** | Human review |
| Force-link environments | **MANUAL** | Admin Portal UI |
| Monitor deployments | ✓ Automated | Power Automate triggers |
