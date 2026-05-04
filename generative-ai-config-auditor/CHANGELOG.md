# Changelog

All notable changes to the Generative AI Config Auditor are documented in this file.

## [1.1.1] - 2026-05-04

### Fixed

- Refreshed Copilot Studio generative AI terminology to match Microsoft Learn labels for **Allow ungrounded responses** (AI general knowledge) and **Work IQ** (semantic search), while preserving existing Dataverse logical column names.
- Extended `Get-AgentGenAISettings.ps1` to detect nested `aiSettings` / `generativeMode`-style JSON and current feature aliases for Allow ungrounded responses and Work IQ.
- Corrected deployment documentation to require PowerShell 7.4 runbooks, matching the solution scripts' `#Requires -Version 7.4` declarations.
- Clarified Power Platform admin center Copilot settings guidance and separated it from Microsoft 365 admin center agent/action governance controls.

## [1.1.0] - 2026-04-17

### Fixed

- **Critical:** Save-GACBaseline boolean coercion bug — `[bool]$AzureOpenAIEnabled` parameter received string values ("Yes"/"No") which PowerShell coerced to `$true` for any non-empty string, causing baselines to falsely record AOAI as enabled. Caller now converts string state to `[bool]` before invocation.
- **Critical:** Baseline persistence omitted ModelKnowledgeEnabled and SemanticSearchEnabled toggles even though schema columns exist; runbook drift detection compared only AOAI/orchestration/genanswers. Both toggles are now persisted via `fsi_modelknowledgeenabled`/`fsi_semanticsearchenabled` and surfaced in drift detection.
- **Critical:** Compliance scan returned a green PASS when zero agents enumerated — masking authentication or Dataverse failures. Test-GenAIConfigCompliance now throws unless `-AllowEmptyResultSet` is supplied. Runbook wraps the scan in a fail-closed catch that records an `AuditControlBypass` Critical run when the scan fails.
- **Critical:** AOAI connection whitelist validation silently skipped when the approved-connections store could not be loaded. Compare-GenAIConfigCompliance now emits a Critical `AuditControlBypass` violation in Zone 2/3 when the whitelist is unavailable, and an `UnresolvedAoaiConnection` violation when AOAI is enabled but the connection ID could not be extracted.
- **High:** Az.Accounts cmdlet `Get-AzAccessToken -ResourceUrl` is deprecated in newer module versions. Connect-EnvironmentDataverse, Import-ApprovedAoaiConnections, and GACClient.psm1 now use `-ResourceUri` with a backward-compatible `-ResourceUrl` fallback.
- **High:** Import-ApprovedAoaiConnections idempotency key was ConnectionId-only; the same connection approved for multiple zones with different policies created duplicate or overwriting records. Idempotency key is now (ConnectionId, Zone).
- **High:** `ApprovedBy` is required by the Dataverse schema but the importer treated it as optional and silently omitted it. Importer now fails-closed per row when neither `-ApprovedBy` nor an `ApprovedBy` CSV column is provided.
- **High:** AgentId GUID values surfaced from Power Platform APIs occasionally include enclosing braces `{}` which Dataverse rejects. Save-GACBaseline now trims braces.
- Regulatory citations standardized: `FINRA 3110` → `FINRA Rule 3110(a)(1)` (with "supports supervisory expectations" qualifier), `SEC 17a-3`/`17a-4` → `SEC Rule 17a-3`/`17a-4`, `SOX 404` → `SOX Section 404`, `GLBA 501(b)` → `GLBA Section 501(b)`.

### Changed

- `#Requires -Version` bumped from 7.0 to 7.4 across all entry-point scripts to align with `Get-Date -AsUTC` and shared module expectations.
- `bot_botsettings` query in Get-AgentGenAISettings clarified as an optional extension table — fall-through behavior is expected when customers have not added platform-side fsi_* columns.

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
