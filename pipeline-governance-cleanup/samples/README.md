# Sample Files

These sample CSV files demonstrate the expected format for solution scripts.

## Files

| File | Purpose | Used By |
|------|---------|---------|
| `environment-inventory-sample.csv` | Sample output from Get-PipelineInventory.ps1 | Reference for expected columns |
| `non-compliant-sample.csv` | Sample input for Send-OwnerNotifications.ps1 | Notification script input |

## Usage

1. Copy these files as templates for your environment
2. Replace sample data with actual values from your tenant
3. Do **not** use sample data in production

## Column Descriptions

### environment-inventory-sample.csv

| Column | Description |
|--------|-------------|
| EnvironmentId | Power Platform environment GUID |
| EnvironmentName | Display name of the environment |
| EnvironmentType | Production, Sandbox, Developer, etc. |
| EnvironmentUrl | Dataverse URL for the environment |
| IsManaged | Whether it's a Managed Environment (check admin portal) |
| CreatedTime | When the environment was created |
| PipelinesHostId | GUID of the host environment (manual lookup required) |
| HasPipelinesEnabled | Yes/No/Unknown based on pipeline probe |
| ComplianceStatus | Current compliance state |
| Notes | Additional information |

### non-compliant-sample.csv

| Column | Description |
|--------|-------------|
| OwnerEmail | Email address of the owner to notify |
| EnvironmentName | Environment display name |
| EnvironmentId | Environment GUID |
| OwnerName | Owner's display name (optional) |

## Version Validation

These samples are validated against script version **1.0.7**. If you're using a different script version, verify column names match before use.

## See Also

- [Get-PipelineInventory.ps1](../src/Get-PipelineInventory.ps1) - Inventory script
- [Send-OwnerNotifications.ps1](../src/Send-OwnerNotifications.ps1) - Notification script
- [AUTOMATION_GUIDE.md](../AUTOMATION_GUIDE.md) - Script documentation
