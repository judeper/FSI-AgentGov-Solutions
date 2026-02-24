# Changelog

All notable changes to the Agent Communication Restriction Detector are documented in this file.

## [1.0.0] - 2026-02-24

### Added

- Initial release of Agent Communication Restriction Detector
- Dataverse schema: 5 tables, 4 ACRD-specific option sets, 2 shared option sets
- Python deployment scripts for Dataverse infrastructure (schema, environment variables, connection references)
- PowerShell governance scripts for agent communication compliance scanning
- Zone-to-zone communication policy enforcement (Zone 1/2/3)
- Cross-environment and cross-tenant violation detection
- Maker/checker enforcement for agent skill registrations
- Approved communication route management via CSV import
- SHA-256 integrity-hashed evidence export for regulatory examinations
- Azure Automation runbook for scheduled validation
- Teams and email alerting via Power Automate flows
- Regulatory context mapping (FINRA 3110, SOX 404, GLBA 501(b))
