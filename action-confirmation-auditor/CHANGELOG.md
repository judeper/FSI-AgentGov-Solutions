# Changelog

All notable changes to the Action Confirmation Auditor are documented in this file.

## [1.0.0] - 2026-02-24

### Added

- Initial release of Action Confirmation Auditor
- Dataverse schema: 3 tables, 3 solution-specific option sets, 2 shared option sets
- Python deployment scripts: schema, environment variables, connection references, orchestrator
- PowerShell governance scripts: compliance scan, evidence export
- Zone-based policy enforcement for action confirmation requirements
- Hardcoded zone policies (v1.0): Zone 3 all actions, Zone 2 write/delete/external, Zone 1 advisory
- Exception management for approved confirmation bypasses
- SHA-256 evidence export for regulatory examination
- Azure Automation runbook wrapper for scheduled execution
- Teams/email alerting via Power Automate flow documentation
- Regulatory context mapping (FINRA 3110, GLBA 501(b), SOX 404)
- v1.1 stub for risk classification CSV import
