# Changelog

All notable changes to the Agent Communication Restriction Detector are documented in this file.

## [1.1.1] - 2026-05-04

### Fixed
- Aligned scan and runbook PowerShell requirements with Microsoft Learn guidance that `Microsoft.PowerApps.Administration.PowerShell` uses Windows PowerShell 5.x rather than PowerShell 7.x.
- Added connected-agent schema-name extraction for current Copilot Studio `InvokeConnectedAgentTaskAction` and `ConnectedAgentDefinition` YAML patterns.
- Updated flow prerequisites to include `Az.Accounts` and to document Windows PowerShell 5.1 runbook deployment for the Power Platform admin module.

## [1.1.0] - 2026-04-17

### Breaking

- Runbook output schema augmented with `SkillSnapshot` (array) and top-level `ViolationCount`. Power Automate "Parse JSON" action must be regenerated from a fresh sample (drop phantom `CommunicationPattern`, `ExpectedPolicy`, `ActualConfig`; add `RunType`, `RunId`, `TotalSkills`, `EnvironmentNames`, `Reason`, `Control`, `ZoneSummary`, `Drift`, `AlertRequired`, `AlertSeverity`, `SkillSnapshot`, `ViolationCount`; per-violation `IsCrossEnvironment`, `IsCrossTenant`, `RegulatoryContext`).
- Flow Step 7 column mapping for `fsi_environmentsscanned` changed from `string(TotalEnvironments)` (count) to `EnvironmentNames` (comma-separated environment list, the actual schema intent).
- Flow Step 6 (exception approval) `fsi_exceptionstatus` mapping changed from text label `"Approved"`/`"Denied"` to integer option set values `100000001`/`100000002`. Existing flows using the text labels will silently fail to update the column.
- `Import-ApprovedCommRoutes.ps1`: `ApprovedBy` is now mandatory per row (rows with empty `ApprovedBy` are skipped with warning); `fsi_approvedby` and `fsi_approvedat` are now always set on every CREATE and UPDATE.
- `ACRDClient.psm1` now declares `#requires -Modules @{ ModuleName='Az.Accounts'; ModuleVersion='2.0.0' }`. Importing the module without `Az.Accounts` installed will fail at parse time.

### Fixed

- **CRITICAL — drift detection restored.** `Start-CommRestrictionValidationRunbook.ps1` and `Test-CommRestrictionCompliance.ps1` now persist the `SkillSnapshot` array (id, name, environmentId, manifestUrl) into the runbook output and `scanSummary`. Without this snapshot, the next run's `Compare-Snapshot` had nothing to diff against and drift detection was a no-op.
- **Goldeneye HIGH** — `Start-CommRestrictionValidationRunbook.ps1` now calls `Add-PowerAppsAccount` with the same certificate/tenant/clientId after acquiring the Dataverse token. Without this, `Get-AdminPowerAppEnvironment` (used to enumerate environments) silently fails or prompts in non-interactive runbook context.
- `ACRDClient.psm1` `Get-AgentBots` `$select` clause: replaced invalid `schemaname` with `_ownerid_value` (the bot table has no `schemaname` column; query was returning 400).
- `ACRDClient.psm1` `Get-ACRDSkillRegistration`: `TargetZone` no longer masquerades `SourceZone`'s value — it is now `$null` since `fsi_AgentSkillRegistration` has only one zone column (`fsi_zone`). Comparison logic must treat `TargetZone` as unknown for skill-registration records.
- `ACRDClient.psm1` `Write-ACRDViolation`: violation `fsi_name` truncated to 200 chars (80+80 cap on calling/called agent names) to fit the schema column; `fsi_calledenvironmentid` always set with `'unknown-tenant'` fallback + warning when missing (column is required); `fsi_violationtype` now throws if unmappable rather than silently dropping the column (column is required).
- `Connect-EnvironmentDataverse.ps1`: SecureString token is now properly unwrapped (PS7 `ConvertFrom-SecureString -AsPlainText`, PS5.1 `Marshal.SecureStringToBSTR` fallback) before being placed in the `Authorization` header. Previous code passed the SecureString directly, producing 401 errors.
- `Import-ApprovedCommRoutes.ps1`: Dataverse URL regex broadened to accept sovereign clouds (`.crm.microsoftdynamics.us`, `.crm.microsoftdynamics.de`) and trailing slashes.
- `Export-CommViolationEvidence.ps1`: deterministic JSON canonicalization (recursive key sort, stable record ordering) and LF-only UTF-8 no-BOM file write so re-runs of the same data produce byte-identical hashes (sha256sum-compatible companion file).
- `ACRDClient.psm1` POSTs now use `ConvertTo-Json -Depth 10` to prevent nested object truncation.
- README "Violation Severity Matrix" Maker/Checker row corrected from `Warning | Medium | High` to `Warning | High | Critical` to match `Get-ExpectedCommPolicy.ps1`.
- CHANGELOG: corrected inverted dates (1.0.2 was dated after 1.0.1).
- All embedded `Version:` headers and banner strings synced to `1.1.0` across 11 .ps1 + 1 .psm1.

### Changed

- `prerequisites.md`: clarified that runbook needs `MSAL.PS` (cert auth), `Microsoft.PowerApps.Administration.PowerShell` (env enumeration), and `Az.Accounts` (transitively required by `ACRDClient.psm1`).

## [1.0.2] - 2026-03-08

### Fixed

- ACRDClient.psm1 `Get-ACRDSkillRegistration`: removed non-existent `fsi_isactive` filter and `fsi_ownerid` output mapping; changed `fsi_sourcezone`/`fsi_targetzone` to `fsi_zone` (actual AgentSkillRegistration column)
- Start-CommRestrictionValidationRunbook.ps1: fixed property name mismatch — Compare-CommRestrictionCompliance outputs `AgentId`/`AgentName`, not `CallingAgentId`/`CallingAgentName`
- flow-configuration.md exception approval flow: replaced phantom columns (`fsi_sourceagentid`, `fsi_targetagentid`, `fsi_sourceagentname`, `fsi_targetagentname`, `fsi_communicationpattern`, `fsi_requestedby`, `fsi_requestedon`) with correct schema columns (`fsi_callingagentid`, `fsi_calledagentid`, `fsi_justification`)
- flow-configuration.md scanner flow: added missing `fsi_totalskills` to scan run Dataverse write mapping
- Entity set name in comments: `fsi_commscanruns` → `fsi_commscanrun` in Test-CommRestrictionCompliance.ps1 and Start-CommRestrictionValidationRunbook.ps1

### Changed

- Bumped embedded version strings from 1.0.0 to 1.0.1 across all scripts
- Added `#Requires -Version 7.0` and comment-based help to `scripts/private/Get-ZoneClassification.ps1`

## [1.0.1] - 2026-03-01

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
