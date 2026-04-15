# Changelog

All notable changes to the Generative AI Config Auditor are documented in this file.

## [1.0.1] - 2026-04-15

### Fixed

- Write-Output contamination in Object output mode changed to Write-Host

## [1.0.0] - 2026-02-24

### Added

- Initial release of Generative AI Config Auditor
- Dataverse schema: 5 tables, 3 solution-specific option sets, 2 shared option sets
- Python deployment scripts: schema, environment variables, connection references, orchestrator
- PowerShell governance scripts: compliance scan, baseline capture, evidence export
- Zone-based policy enforcement for Azure OpenAI, generative orchestration, generative answers
- Approved AOAI connection whitelist management with CSV import
- SHA-256 evidence export for regulatory examination
- Azure Automation runbook wrapper for scheduled execution
- Teams/email alerting via Power Automate flow documentation
- Baseline drift detection for generative AI configuration changes
- Regulatory context mapping (FINRA 3110, GLBA 501(b), SOX 404)
