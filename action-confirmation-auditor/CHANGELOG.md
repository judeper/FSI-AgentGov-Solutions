# Changelog

All notable changes to the Action Confirmation Auditor are documented in this file.

## [1.0.2] - 2026-04-15

### Fixed

- **README.md**: Corrected Quick Start CLI flag `--dataverse-url` → `--environment-url` to match actual `create_dataverse_schema.py` argument
- **README.md**: Fixed dry-run example to dot-source script before calling `Test-ActionConfirmationCompliance` function
- **README.md**: Added mandatory auth parameters (`-TenantId`, `-Interactive`) to evidence export example
- **README.md**: Formalized regulation references (FINRA Rule 3110, GLBA Section 501(b), SOX Section 404)
- **docs/prerequisites.md**: Corrected deployment command `--dataverse-url` → `--environment-url`
- **docs/prerequisites.md**: Fixed Dataverse table names from SchemaName format to logical names
- **docs/prerequisites.md**: Updated footer version v1.0.0 → v1.0.2
- **docs/dataverse-schema.md**: Regenerated from schema script to include missing `fsi_ViolationType` column
- **docs/flow-configuration.md**: Added missing required fields to Action Scan Run record creation (`fsi_actionswithconfirmation`)
- **docs/flow-configuration.md**: Added all required fields and option set value mappings to Action Audit Result creation (`fsi_environmentguid`, `fsi_environmentname`, `fsi_zone`, `fsi_agentid`, `fsi_agentname`, `fsi_risklevel`, `fsi_violationstatus`)
- **docs/flow-configuration.md**: Removed undocumented `fsi_cr_approvals_actionconfirmationauditor` connection reference not created by deployment scripts
- **docs/flow-configuration.md**: Aligned troubleshooting guidance with certificate-based service principal authentication
- **scripts/private/ACAClient.psm1**: Fixed `Connect-ACADataverse` to reset `$script:DataverseUrl` on token acquisition failure instead of leaving partial connected state
- **scripts/private/ACAClient.psm1**: Fixed help example to reference `Get-ACALastValidation` (was non-existent `Get-ACAScanRunHistory`)
- **scripts/Export-ActionAuditEvidence.ps1**: Added `#Requires -Modules MSAL.PS` declaration
- **scripts/Test-ActionConfirmationCompliance.ps1**: Fixed help text entity set name `fsi_actionscanruns` → `fsi_actionscanrun`

## [1.0.1] - 2026-04-15

### Fixed

- Aligned all PowerShell scripts with Dataverse schema source of truth:
  - Entity set `fsi_actionscanruns` → `fsi_actionscanrun` (ACAClient.psm1, Export-ActionAuditEvidence.ps1, Start-ActionConfirmationValidationRunbook.ps1)
  - Column `fsi_scantime` → `fsi_validationtime` across all scan run queries
  - Column `fsi_reason` → `fsi_justification` for exception records
  - Removed references to non-existent `fsi_connectorid` column (use `fsi_connectorname`)
  - Removed references to non-existent `fsi_agentname` on exception table
  - Fixed `fsi_compliantcount` → `fsi_actionswithconfirmation` in evidence export
  - Removed non-existent `fsi_actioncategory` from evidence export
- Fixed `Get-ACAExceptions` → `Get-ActionConfirmationExceptions` function call in Test-ActionConfirmationCompliance.ps1
- Fixed exception property access to use PSCustomObject property names (`AgentId`, `ActionName`) instead of raw Dataverse column names
- Standardized bot component lookup field to `_botid_value` (was inconsistently `_parentbotid_value` in ACAClient.psm1)
- Updated README: corrected Quick Start dry-run command, environment variables table, removed false CSV export claim
- Updated flow-configuration.md: corrected environment variables, runbook parameters, Dataverse column names, removed non-existent exception columns
- Updated prerequisites.md: corrected authentication guidance to certificate-based auth
- Added missing `.EXAMPLE` sections to PowerShell comment-based help (ACAClient.psm1, Connect-EnvironmentDataverse.ps1, Get-ExpectedConfirmationPolicy.ps1, Get-ZoneClassification.ps1)

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
