# Changelog

All notable changes to the Agent Communication Restriction Detector are documented in this file.

## [1.0.1] - 2026-04-16

### Fixed

- Fixed Dataverse column name mismatches in ACRDClient.psm1: fsi_scantime → fsi_validationtime, fsi_commscanruns → fsi_commscanrun
- Fixed violation column names to match schema: fsi_environmentguid → fsi_callingenvironmentid, fsi_targetagentid → fsi_calledagentid, fsi_sourcezone → fsi_callingagentzone, fsi_targetzone → fsi_calledagentzone, fsi_skillname → fsi_skillmanifesturl, fsi_targetenvironmentid → fsi_calledenvironmentid
- Removed fsi_compliantcount from scan run write (column not in schema)

### Added

- Created `.ralph-config.json` with domain facts from council review

### Updated

- Product name: "Azure AD" → "Microsoft Entra ID" across 8 script files

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
