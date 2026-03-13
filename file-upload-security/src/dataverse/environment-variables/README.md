# Environment Variables

Environment variables are provisioned programmatically via `scripts/create_environment_variables.py`.

See [SCHEMA.md](../../../docs/SCHEMA.md) for variable definitions and defaults.

| Schema Name | Type | Default | Description |
|-------------|------|---------|-------------|
| `fsi_FUS_GracePeriodHours` | Decimal | 24 | Hours before drift violations are raised |
| `fsi_FUS_ScanFrequencyHours` | Decimal | 24 | Automated scan interval |
| `fsi_FUS_IncludeSandbox` | String | false | Include sandbox environments |
| `fsi_FUS_IncludeDrafts` | String | false | Include draft agents |
| `fsi_FUS_BaselineMaxAgeDays` | Decimal | 90 | Max baseline age before stale |
| `fsi_FUS_TeamsGroupId` | String | — | Teams group for alerts |
| `fsi_FUS_TeamsChannelId` | String | — | Teams channel for alerts |

## Deployment-Specific Flow Variables

The following variables in `src/fileupload-validation-flow.json` contain `DEPLOY_PLACEHOLDER_*` values
and **MUST** be updated per-environment before deployment:

| Flow Variable | Placeholder | Example Value | Description |
|---------------|-------------|---------------|-------------|
| `DataverseUrl` | `DEPLOY_PLACEHOLDER_DATAVERSE_URL` | `https://orgname.crm.dynamics.com` | Target Dataverse organization URL |
| `TenantId` | `DEPLOY_PLACEHOLDER_TENANT_ID` | `contoso.onmicrosoft.com` or GUID | Microsoft Entra ID tenant identifier |
| `ClientId` | `DEPLOY_PLACEHOLDER_CLIENT_ID` | `xxxxxxxx-xxxx-xxxx-xxxx-xxxxxxxxxxxx` | Microsoft Entra ID app registration client ID |
| `DocumentationUrl` | `DEPLOY_PLACEHOLDER_DOCUMENTATION_URL` | `https://your-org.github.io/FSI-AgentGov/controls/...` | Documentation link shown in Teams alert cards |
