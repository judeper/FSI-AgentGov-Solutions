# Configuration — Cross-Solution Integration

## Environment Variables

The integration layer uses the following environment variables (set via Dataverse environment variables or PowerShell parameters):

| Variable | Default | Description |
|----------|---------|-------------|
| `fsi_INT_DataverseUrl` | — | Dataverse environment URL (required) |
| `fsi_INT_TenantId` | — | Microsoft Entra tenant ID (required) |
| `fsi_INT_ClientId` | — | App registration client ID for service principal auth |
| `fsi_INT_TeamsGroupId` | — | Teams group for alert notifications (optional) |
| `fsi_INT_TeamsChannelId` | — | Teams channel for alert notifications (optional) |
| `fsi_INT_IncludeSandbox` | `false` | Include sandbox environments in assessment sync |
| `fsi_INT_DashboardFeedSchedule` | `Daily 6:30 AM UTC` | CD-SolutionFeedCollector schedule |

## Solution Connection Configuration

Each Tier 2 solution's Dataverse tables must be accessible from the integration environment. For single-environment deployments, this is automatic. For cross-environment scenarios:

### Same Dataverse Environment (Recommended)

All solutions deployed to the same environment. The integration layer queries tables directly.

```powershell
$params = @{
    DataverseUrl = "https://org.crm.dynamics.com"
    TenantId     = "tenant-guid"
    Interactive  = $true
}
.\Sync-SolutionAssessments.ps1 @params
```

### Cross-Environment (Advanced)

Cross-environment deployment is not currently supported by `Sync-SolutionAssessments.ps1`, which accepts a single `-DataverseUrl` parameter. All Tier 2 solution tables must be accessible from that environment.

If cross-environment support is required, extend the script to accept per-solution URLs or use virtual tables/Dataverse data integration to surface remote tables locally.

```powershell
# Single-environment only (current implementation)
$params = @{
    DataverseUrl = "https://org.crm.dynamics.com"
    TenantId     = "tenant-guid"
    Interactive  = $true
}
.\Sync-SolutionAssessments.ps1 @params
```

## Security Roles

The service principal or interactive user needs:

| Solution | Required Role | Access Level |
|----------|--------------|-------------|
| ACV | ACV Viewer (or custom) | Read `fsi_auditvalidationhistory` |
| SSC | SSC Viewer (or custom) | Read `fsi_validationhistory` |
| AAM | AAM Viewer (or custom) | Read `fsi_accessvalidationhistory` |
| CMM | CMM Viewer (or custom) | Read `fsi_moderationvalidationhistory` |
| FUS | FUS Viewer (or custom) | Read `fsi_fileupload_validationhistory` |
| CAA | CAA Viewer (or custom) | Read `fsi_capolicyvalidationhistory` |
| CD | CD Assessor | Create/Update `fsi_controlassessment`, `fsi_complianceevidence` |

## Scheduling

### Power Automate (Recommended)

Deploy the `CD-SolutionFeedCollector` flow. Default schedule: daily at 6:30 AM UTC (30 minutes after most Tier 2 solution daily scans complete at 6:00 AM UTC).

### Azure Automation (Alternative)

Use `Sync-SolutionAssessments.ps1` with Azure Automation:

1. Import `IntegrationConfig.psm1` as module
2. Create runbook importing the sync script
3. Configure schedule and credentials
4. Set `-DryRun` for initial testing

### Manual Execution

```powershell
Import-Module .\IntegrationConfig.psm1
.\Sync-SolutionAssessments.ps1 -DataverseUrl "https://org.crm.dynamics.com" -TenantId "guid" -Interactive -DryRun
```

---

*Configuration Guide v1.0.0 — February 2026*
