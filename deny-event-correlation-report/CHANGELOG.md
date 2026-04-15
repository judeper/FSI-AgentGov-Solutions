# Changelog

All notable changes to the Deny Event Correlation Report are documented here.

## [2.0.1] — 2026-04-15

### Fixed

- Critical: Local CSV files are no longer deleted when blob uploads fail (prevents compliance evidence loss)
- Blob upload failures are now tracked and prevent premature file cleanup

## [2.0.0] — February 2026

### Added
- Purview CopilotInteraction extraction script (`Export-CopilotDenyEvents.ps1`)
- Purview DLP extraction script (`Export-DlpCopilotEvents.ps1`)
- Shared Exchange Online connection helper (`Connect-ExchangeOnlineHelper.ps1`)
- Defender CloudAppEvents extraction script (`Export-DefenderCopilotEvents.ps1`)
- Application Insights RAI telemetry extraction script (`Export-RaiTelemetry.ps1`)
- Daily orchestration script (`Invoke-DailyDenyReport.ps1`)
- KQL queries for deny event correlation across 4 data sources (Purview Audit, DLP, Application Insights, Defender CloudAppEvents)
- Architecture documentation, prerequisites guide, and troubleshooting guide
- Support for FINRA 4511, SEC 17a-3/4, GLBA 501(b) regulatory alignment, and FINRA 24-09 / OCC 2011-12 supervisory guidance
