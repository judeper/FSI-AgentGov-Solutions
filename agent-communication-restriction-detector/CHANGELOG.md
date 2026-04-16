# Changelog

All notable changes to the Agent Communication Restriction Detector are documented in this file.

## [1.0.2] - 2026-04-08

### Fixed

- ACRDClient.psm1 `Get-ACRDSkillRegistration`: removed non-existent `fsi_isactive` filter and `fsi_ownerid` output mapping; changed `fsi_sourcezone`/`fsi_targetzone` to `fsi_zone` (actual AgentSkillRegistration column)
- Start-CommRestrictionValidationRunbook.ps1: fixed property name mismatch — Compare-CommRestrictionCompliance outputs `AgentId`/`AgentName`, not `CallingAgentId`/`CallingAgentName`
- flow-configuration.md exception approval flow: replaced phantom columns (`fsi_sourceagentid`, `fsi_targetagentid`, `fsi_sourceagentname`, `fsi_targetagentname`, `fsi_communicationpattern`, `fsi_requestedby`, `fsi_requestedon`) with correct schema columns (`fsi_callingagentid`, `fsi_calledagentid`, `fsi_justification`)
- flow-configuration.md scanner flow: added missing `fsi_totalskills` to scan run Dataverse write mapping
- Entity set name in comments: `fsi_commscanruns` → `fsi_commscanrun` in Test-CommRestrictionCompliance.ps1 and Start-CommRestrictionValidationRunbook.ps1

### Changed

- Bumped embedded version strings from 1.0.0 to 1.0.1 across all scripts
- Added `#Requires -Version 7.0` and comment-based help to `scripts/private/Get-ZoneClassification.ps1`

## [1.0.1] - 2026-04-15

### Fixed

- Entity set `fsi_commscanruns` → `fsi_commscanrun` in ACRDClient.psm1 and Export script (matches schema EntitySetName)
- Exception column `fsi_targetagentid` → `fsi_calledagentid` in ACRDClient.psm1 (matches schema)
- README status updated from "In Development" to "Released"

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
