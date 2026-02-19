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
