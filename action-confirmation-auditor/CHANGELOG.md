# Changelog

All notable changes to the Action Confirmation Auditor are documented in this file.

## [1.1.0] - 2026-04-17 - BREAKING

### Changed (BREAKING)

- **Control mapping re-aligned.** Primary control changed from **1.23 (Step-Up Authentication for Agent Operations)** to **2.12 (Human-in-the-Loop Checkpoints)**, with **1.10 (Communication Compliance)** as supporting (FINRA 3110 supervisory review evidence). Control 1.23 is implemented through Entra Authentication Contexts and Conditional Access (see *Conditional Access Automation* and *Session Security Configurator* solutions); ACA validates HITL/approval prompts in agent topics and does not by itself satisfy AAL2/AAL3 step-up authentication. AI Council convergent finding (Opus 4.7 + Goldeneye).
- **Schema: `fsi_IsActive` default flipped to `false`** on `fsi_ActionConfirmationException`. Previously defaulted to `true`, creating a control-bypass window where any newly created exception immediately suppressed violations until the approver acted (up to 14 days). Now exceptions are inactive by default and only the approval branch in the exception-approval flow sets `fsi_IsActive = true`. Existing tenants must republish the schema (`python scripts/create_dataverse_schema.py`) and update the exception-approval flow trigger filter (remove `fsi_isactive eq true`).
- **Runbook output schema additions.** `Start-ActionConfirmationValidationRunbook.ps1` now emits `ActionsMissingConfirmation` and `ActionsWithConfirmation` at the top level of the JSON output (previously only present inside `ZoneSummary[*]`). The Power Automate Parse JSON schema in `docs/flow-configuration.md` already referenced these top-level fields, so prior to this fix the corresponding Dataverse `fsi_actionsmissingconfirmation` / `fsi_actionswithconfirmation` `ApplicationRequired` columns were always written as null (record creation failed).

### Fixed

- **scripts/Start-ActionConfirmationValidationRunbook.ps1**: Replaced remaining `OverallStatus = 'Review'` emission (lines 248, 431, .OUTPUTS doc) with `'Warning'`. CHANGELOG v1.0.3 fixed this in `Test-ActionConfirmationCompliance.ps1` but missed the runbook, which is the primary production path. Removed dead `'Review'` branches from `Export-ActionAuditEvidence.ps1` and `Test-ActionConfirmationCompliance.ps1` switch tables.
- **scripts/private/ACAClient.psm1 `Write-ACAViolation`**: Now persists `fsi_violationtype` from the supplied `Violation.ViolationType`. Previously omitted, breaking cross-solution-integration / dashboard filtering by violation type. (Same gap was fixed in `Test-UserDefinedActionMessages.ps1` per v1.0.3 but the central PSM1 path was missed.)
- **scripts/private/ACAClient.psm1 `Write-ACAValidationHistory`**: `fsi_name` timestamp now correctly converted to UTC before formatting (was emitting local time labelled `Z`, causing drift vs `fsi_validationtime`).
- **scripts/Export-ActionAuditEvidence.ps1**: Evidence JSON is now **deterministic** — recursive key sort + LF-only + UTF-8 no-BOM write — so two exports of identical Dataverse data produce identical SHA-256 hashes. Required for FINRA 4511 / SEC 17a-4 chain-of-custody verification through `Test-EvidenceIntegrity.ps1`.
- **scripts/Export-ActionAuditEvidence.ps1**: Hash companion file now written via `[System.IO.File]::WriteAllText` with explicit `\n` line ending and UTF-8 no BOM, matching GNU `sha256sum` format exactly.
- **scripts/Export-ActionAuditEvidence.ps1**: All three Dataverse queries (`fsi_actionscanrun`, `fsi_actionauditresults`, `fsi_actionconfirmationexceptions`) now follow `@odata.nextLink` via a shared `Invoke-DataversePagedQuery` helper. Previously single-page only — large tenants received truncated evidence packages with hashes computed over partial data.
- **scripts/Export-ActionAuditEvidence.ps1**: Added GUID format validation for `-RunId` parameter before insertion into OData filter (mirrors validation already present in `ACAClient.psm1`).
- **scripts/Export-ActionAuditEvidence.ps1**: Replaced "Azure AD" with "Microsoft Entra ID" in `.PARAMETER TenantId` and `.PARAMETER ClientId` help text (per repo language policy).
- **All script `.NOTES`**: Bumped `Version` from `1.0.2` → `1.1.0` and `Control` references from `1.23` → `2.12 (HITL); supports 1.10 (Communication Compliance / FINRA 3110)` across `Get-AgentActionSettings.ps1`, `ACAClient.psm1`, `Start-ActionConfirmationValidationRunbook.ps1`, `Test-UserDefinedActionMessages.ps1`, `Test-ActionConfirmationCompliance.ps1`, `Get-ExpectedConfirmationPolicy.ps1`, `Test-EvidenceIntegrity.ps1`, `Test-ParameterValidation.ps1`, `Export-ActionAuditEvidence.ps1`. Verbose banner in `Test-ActionConfirmationCompliance.ps1` and `solutionVersion` in evidence package metadata also bumped.
- **README.md**: Updated Related Controls table to reflect 2.12 / 1.10 mapping, added explanatory note about why 1.23 was removed.

### Council Review

This release applies fixes from a 2-member AI Council technical review (Opus 4.7 + Goldeneye). Both council members independently identified the control mis-mapping, the runbook `'Review'` regression, the version-string drift, and "Azure AD" naming issues. Opus additionally surfaced the non-deterministic evidence JSON, the `Write-ACAViolation` `fsi_violationtype` omission, the `IsActive` default-true control-bypass vector, and the missing `ActionsMissingConfirmation` / `ActionsWithConfirmation` runbook output fields. Goldeneye additionally surfaced the missing OData pagination in `Export-ActionAuditEvidence.ps1`.

## [1.0.3] - 2026-04-16

### Fixed

- **scripts/private/ACAClient.psm1**: Added missing required fields `fsi_totalagents` and `fsi_violationcount` to `Write-ACAValidationHistory` scan run record
- **scripts/private/ACAClient.psm1**: Added missing `fsi_risklevel` field to `Write-ACAViolation` violation record
- **scripts/Test-ActionConfirmationCompliance.ps1**: Fixed `$validationSummary` to pass `ActionsWithConfirmation`, `ActionsMissingConfirmation`, and `ViolationCount` keys matching `Write-ACAValidationHistory` expectations
- **scripts/Test-ActionConfirmationCompliance.ps1**: Changed `OverallStatus` from non-schema value `Review` to `Warning` to match schema documentation
- **scripts/Test-ActionConfirmationCompliance.ps1**: Exception matching now validates `IsActive`, `ExpiresAt`, and `Zone` fields instead of matching on AgentId|ActionName alone
- **scripts/Get-AgentActionSettings.ps1**: Fixed confirmation status string `Unable to Determine` → `UnableToDetermine` to match schema option set
- **scripts/Get-AgentActionSettings.ps1**: Fixed `ActionsMissingConfirmation` count to include Partial and UnableToDetermine statuses (was only counting Missing)
- **scripts/Export-ActionAuditEvidence.ps1**: Fixed zone filter to use integer picklist value instead of string `'Zone1'` for OData query
- **scripts/governance/Test-UserDefinedActionMessages.ps1**: Added missing required Dataverse fields (`fsi_zone`, `fsi_actionname`, `fsi_actiontype`, `fsi_risklevel`, `fsi_confirmationstatus`, `fsi_violationstatus`) when persisting violations
- **docs/flow-configuration.md**: Added missing violation properties (`EnvironmentId`, `EnvironmentName`, `Zone`, `AgentId`, `AgentName`, `ActionCategory`) to Parse JSON schema
- **scripts/private/Get-ZoneClassification.ps1**: Added missing `#requires -Version 7.0` statement
- **scripts/governance/Import-ActionRiskClassifications.ps1**: Added missing `.EXAMPLE` section to comment-based help
- Updated all script `.NOTES` version references from `1.0.0` to `1.0.2`
- **scripts/Export-ActionAuditEvidence.ps1**: Updated evidence metadata `solutionVersion` from `1.0.0` to `1.0.2`

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
