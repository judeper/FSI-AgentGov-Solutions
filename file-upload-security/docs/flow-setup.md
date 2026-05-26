# Power Automate Flow Setup

## Overview

The File Upload Security Configurator includes a Power Automate flow that runs daily file upload compliance validation and routes alerts to Teams and email based on severity.

## Prerequisites

Before deploying the flow:

1. **Dataverse infrastructure deployed** — Run `deploy.py` to create tables, environment variables, and connection references
2. **Azure Automation runbook imported** — Upload `Start-FileUploadValidationRunbook.ps1` to your Automation Account
3. **Baselines captured** — Run `Invoke-FileUploadBaselineCapture.ps1` at least once
4. **Teams channel configured** — Identify the Teams group and channel for violation alerts

## Deployment Steps

### 1. Create Flow in Power Automate

1. Open [Power Automate](https://make.powerautomate.com)
2. Navigate to **My flows** > **Create** > **Scheduled cloud flow**
3. Follow the steps in this guide to build the flow actions and configure connection references

### 2. Configure Variables

After import, edit the flow and update these variables:

| Variable | Value |
|----------|-------|
| `DataverseUrl` | Your Dataverse org URL (e.g., `https://governance.crm.dynamics.com`) |
| `TenantId` | Your Microsoft Entra ID tenant ID |
| `ClientId` | App registration client ID for certificate fallback or workload identity |
| `CertificateThumbprint` | Certificate thumbprint uploaded to Automation Account when managed identity is not available |
| `SubscriptionId` | Azure subscription containing Automation Account |
| `ResourceGroup` | Resource group name (default: `rg-file-upload-security`) |
| `AutomationAccount` | Automation Account name (default: `aa-file-upload-security`) |
| `TeamsGroupId` | Target Teams group (team) ID |
| `TeamsChannelId` | Target Teams channel ID |
| `ComplianceDistributionList` | Email distribution list for alerts |

### 3. Configure Connection References

| Reference | Connector | Action |
|-----------|-----------|--------|
| `fsi_cr_dataverse_fileuploadsecurity` | Dataverse | Select existing connection |
| `fsi_cr_office365_fileuploadsecurity` | Office 365 | Select existing connection |
| `fsi_cr_teams_fileuploadsecurity` | Teams | Select existing connection |
| `fsi_cr_azureautomation_fileuploadsecurity` | Azure Automation | Create or select connection |

### 4. Test

1. Run the flow manually (use **Test** in flow designer)
2. Verify Azure Automation job starts and completes
3. Check Dataverse `fsi_fileuploadvalidationhistory` for new record
4. If violations exist, verify Teams card and email delivery

## Flow Architecture

```
Recurrence (Daily 06:00 UTC)
  │
  ├─ Initialize Variables (10 variables)
  │
  ├─ Scope_Try
  │   ├─ Create Automation Job
  │   ├─ Wait For Job (30s poll, 2h timeout)
  │   ├─ Check Job Failed/Cancelled → Send Failure Email + Terminate
  │   ├─ Get Job Output
  │   ├─ Parse Results (JSON → typed properties)
  │   ├─ Write Validation History (audit-first)
  │   └─ Check Alert Required
  │       ├─ Critical/Failed/Error → Teams Card + Email
  │       └─ Warning → Email Only
  │
  └─ Scope_Catch
      └─ Send Critical Error Email (includes job status)
```

## Alert Routing

| Condition | Teams Card | Email | Importance |
|-----------|-----------|-------|------------|
| Critical severity | Yes | Yes | High |
| Failed status | Yes | Yes | High |
| Error status | Yes | Yes | High |
| Warning severity | No | Yes | Normal |
| Passed | No | No | — |

## Troubleshooting

- **Job never completes:** Check Azure Automation Account modules are installed
- **No Teams card:** Verify TeamsGroupId and TeamsChannelId are correct
- **Parse error:** Ensure runbook outputs valid JSON (check job output in Azure Portal)
- **Connection error:** Re-authenticate connection references in Power Automate

---

*File Upload Security Configurator — Flow Setup Guide — Last Verified: 2026-05-25*
