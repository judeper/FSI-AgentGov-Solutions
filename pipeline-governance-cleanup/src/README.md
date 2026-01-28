# Source Files

PowerShell scripts and automation artifacts for pipeline governance cleanup.

## Scripts

| Script | Description | Prerequisites |
|--------|-------------|---------------|
| [Get-PipelineInventory.ps1](./Get-PipelineInventory.ps1) | Exports Power Platform environment inventory | PAC CLI |
| [Send-OwnerNotifications.ps1](./Send-OwnerNotifications.ps1) | Sends governance notifications to owners | Microsoft Graph SDK |

## Get-PipelineInventory.ps1

Exports all Power Platform environments to CSV for governance review.

### Prerequisites

- Power Platform CLI (`pac`): [Install](https://learn.microsoft.com/en-us/power-platform/developer/cli/introduction)
- Power Platform Admin role
- Optional: Microsoft Graph PowerShell SDK for email resolution

### Usage

```powershell
# Authenticate to Power Platform first
pac auth create

# Basic inventory export
.\Get-PipelineInventory.ps1 -OutputPath ".\reports\environment-inventory.csv"

# With user email resolution (requires Graph permissions)
.\Get-PipelineInventory.ps1 -OutputPath ".\reports\environment-inventory.csv" -IncludeUserDetails
```

### Output

CSV file with columns:
- EnvironmentId
- EnvironmentName
- EnvironmentType
- EnvironmentUrl
- IsManaged
- CreatedTime
- PipelinesHostId (requires manual verification)
- HasPipelinesEnabled (requires manual verification)
- ComplianceStatus (requires manual verification)
- Notes

### Limitations

This script lists environments only. It **cannot**:
- Identify which environments have pipelines enabled
- Determine pipelines host associations
- Query the DeploymentPipeline table

Manual verification is required after running this script. See [PORTAL_WALKTHROUGH.md](../PORTAL_WALKTHROUGH.md).

---

## Send-OwnerNotifications.ps1

Sends email notifications to environment/pipeline owners via Microsoft Graph.

### Prerequisites

- Microsoft Graph PowerShell SDK: `Install-Module Microsoft.Graph`
- Mail.Send permission (delegated or application)

### Input CSV Format

| Column | Required | Description |
|--------|----------|-------------|
| OwnerEmail | Yes | Email address to notify |
| EnvironmentName | Yes | Environment display name |
| EnvironmentId | Yes | Environment GUID |
| OwnerName | No | Owner's name (defaults to "Pipeline Owner") |

### Usage

```powershell
# Test mode - preview emails without sending
.\Send-OwnerNotifications.ps1 `
    -InputPath ".\reports\non-compliant.csv" `
    -EnforcementDate "2026-03-01" `
    -TestMode

# Send actual notifications
.\Send-OwnerNotifications.ps1 `
    -InputPath ".\reports\non-compliant.csv" `
    -EnforcementDate "2026-03-01" `
    -SupportEmail "platform-ops@contoso.com" `
    -MigrationUrl "https://contoso.service-now.com/migrate" `
    -ExemptionUrl "https://contoso.service-now.com/exemption"
```

### Parameters

| Parameter | Required | Default | Description |
|-----------|----------|---------|-------------|
| InputPath | Yes | - | Path to CSV with owner information |
| EnforcementDate | Yes | - | Date when enforcement actions will occur |
| TestMode | No | false | Preview emails without sending |
| SupportEmail | No | platform-ops@company.com | Support team email |
| MigrationUrl | No | (placeholder) | URL for migration request form |
| ExemptionUrl | No | (placeholder) | URL for exemption request form |

---

## Workflow

```
1. Run Get-PipelineInventory.ps1
   ↓
2. Manually verify pipeline status (PORTAL_WALKTHROUGH.md)
   ↓
3. Prepare non-compliant CSV with owner info
   ↓
4. Run Send-OwnerNotifications.ps1 (test first)
   ↓
5. Wait for notification period
   ↓
6. Execute force-link manually (PORTAL_WALKTHROUGH.md)
```

---

## Future Additions

| Artifact | Status | Description |
|----------|--------|-------------|
| Export-ComplianceReport.ps1 | Planned | Generate compliance summary report |
| Teams adaptive card JSON | Available | See [NOTIFICATION_TEMPLATES.md](../NOTIFICATION_TEMPLATES.md) |

---

## Contributing

If you create reusable scripts or automation artifacts:

1. Follow PowerShell best practices (comment-based help, parameter validation)
2. Document prerequisites and permissions
3. Include example usage
4. Submit a pull request
