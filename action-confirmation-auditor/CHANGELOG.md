# Changelog

All notable changes to the Action Confirmation Auditor are documented in this file.

## [1.0.1] - 2026-04-16

### Fixed

- Fixed Dataverse entity set name: `fsi_actionscanruns` → `fsi_actionscanrun` (matching explicit entity_set_name in schema)
- Fixed column name mismatch: `fsi_scantime` → `fsi_validationtime` across ACAClient.psm1, Export-ActionAuditEvidence.ps1, Start-ActionConfirmationValidationRunbook.ps1
- Fixed column name mismatch: `fsi_reason` → `fsi_justification` in ACAClient.psm1 and Export-ActionAuditEvidence.ps1
- Fixed flow-configuration.md: `fsi_timestamp` → `fsi_validationtime`, `fsi_resultjson` → `fsi_summaryjson`, `fsi_scanrunid` → `fsi_runid`
- Added missing `fsi_totalagents` to Write-ACAValidationHistory record creation
- Added exception expiration enforcement in Test-ActionConfirmationCompliance.ps1 (FINRA 3110(b)(1))
- Added missing `fsi_ViolationType` column to dataverse-schema.md documentation

### Added

- Added `fsi_RejectedBy`, `fsi_ApprovalNotes`, `fsi_RejectionNotes` columns to fsi_ActionConfirmationException schema for complete approval/rejection audit trail (FINRA 3110(a))
- Added Evidence Retention section to README.md with FINRA 4511, SEC 17a-4, SOX 802 retention guidance
- Created `.ralph-config.json` with domain facts from council review

### Updated

- Product name: "Azure AD" → "Microsoft Entra ID" across all script help text and CLI arguments (7 files)

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
