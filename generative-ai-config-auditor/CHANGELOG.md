# Changelog

All notable changes to the Generative AI Config Auditor are documented in this file.

## [Unreleased]

### Fixed

- **Critical: `Get-AgentGenAISettings.ps1` botcomponent query used wrong lookup column and component types** — The per-agent topic scan filtered `botcomponents` on `_botid_value` with `componenttype eq 12 or componenttype eq 2`. The bot lookup on the `botcomponent` table is `parentbotid` (logical value `_parentbotid_value`), so `_botid_value` is not a valid filter property and Dataverse returns `400 Bad Request` — silently swallowed by the surrounding `try/catch`, leaving `GenerativeAnswersNodeCount`, `KnowledgeSourceCount`, and `TopicSummary` permanently empty for every agent. The component-type integers were also wrong: in `botcomponent_componenttype`, `12` is *Bot variable (V2)* and `2` is *Bot variable* — not Topic/Dialog. The filter now targets `_parentbotid_value` with topic types `0` (Topic) and `9` (Topic (V2)). References: [Copilot component (botcomponent) table reference — `parentbotid` / `componenttype` choices](https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/botcomponent).
- **`Connect-EnvironmentDataverse.ps1` SecureString token handling** — `Get-AzAccessToken` returns the access token as a `SecureString` by default on Az.Accounts 5.x (older versions return a plain `String`). The interactive auth path returned `$tokenResult.Token` verbatim, so on current Az.Accounts the bearer token became the literal string `System.Security.SecureString`, producing `401 Unauthorized` on every per-environment and ELM Dataverse call made by `Get-AgentGenAISettings.ps1`. The token is now normalized to plain text via `[System.Net.NetworkCredential]`, matching the existing handling in `GACClient.psm1`, `Get-PurviewDLPEvidence.ps1`, and `Import-ApprovedAoaiConnections.ps1`. Reference: [Get-AzAccessToken](https://learn.microsoft.com/powershell/module/az.accounts/get-azaccesstoken) ("the default output type has been changed from a plain text `String` to `SecureString`").

### Documentation

- **`docs/prerequisites.md` API permissions corrected** — Removed the inaccurate "Microsoft Graph `Environment.Read.All` (Application)" row; environment enumeration is performed by `Microsoft.PowerApps.Administration.PowerShell` (`Get-AdminPowerAppEnvironment`) against the Power Platform Admin (BAP) API and is governed by the admin roles already listed, not a Microsoft Graph scope. Documented the Graph permission that `Get-PurviewDLPEvidence.ps1` actually requires: `InformationProtectionPolicy.Read` (Delegated) / `InformationProtectionPolicy.Read.All` (Application). Reference: [List informationProtection labels](https://learn.microsoft.com/graph/api/informationprotectionpolicy-list-labels).
- **`docs/prerequisites.md` module list** — Added `Microsoft.Graph.Authentication` (required by `Get-PurviewDLPEvidence.ps1` for `Invoke-MgGraphRequest`) and `ExchangeOnlineManagement` (optional, for `Get-DlpCompliancePolicy` / `Get-Label`), plus their install commands. Noted that Az.Accounts 5.x SecureString tokens are handled automatically.
- **`docs/flow-configuration.md` Parse JSON schema aligned to runbook output** — The `GAC-DailyAudit` Parse JSON schema documented violation fields (`Feature`, `ExpectedPolicy`, `ActualConfig`) and a `Drift.DriftDetected` property that `Start-GenAIConfigValidationRunbook.ps1` does not emit. Corrected the violation item properties to the actual fields (`AzureOpenAIEnabled`, `OrchestrationMode`, `GenerativeAnswersNodeCount`) and the `Drift` object to `HasDrift` / `IsFirstRun` / `DriftedAgents` / `Details`.

## [1.2.1] - 2026-05-19

### Changed

- **Shared Dataverse client refactor**: All deployment scripts (`create_dataverse_schema.py`, `create_environment_variables.py`, `create_connection_references.py`, `deploy.py`) now use the shared `scripts/shared/dataverse_client.DataverseClient` instead of the solution-local `gac_client.GACClient`. This standardises auth modes (managed-identity, workload-identity, certificate, interactive, client-secret) and retry/backoff handling across all FSI solutions.
- **`gac_client.py` deprecated**: Replaced with a deprecation stub that raises `ImportError` on import directing callers to the shared client. The original 620-line implementation is removed.
- **`Import-ApprovedAoaiConnections.ps1` deduplication** (M-4): Removed the local 56-line `Invoke-DataverseRequest` function and now imports the canonical helper from `GACClient.psm1`. Single source of truth for Dataverse retry/backoff policy in PowerShell governance scripts.
- **Dry-run semantics**: Scripts no longer pass `dry_run=` to `DataverseClient(...)`. Reads now hit the live tenant for accurate preview; only writes are gated locally. Dry-run output is more informative (shows which records would be created vs. already exist).

### Fixed

- **Critical: `Get-PurviewDLPEvidence.ps1` entity-set name** — Dataverse Web API query targeted `fsi_gacvalidationhistories` (auto-plural), but the table is registered with explicit singular `EntitySetName=fsi_gacvalidationhistory`. Every Dataverse evidence call returned 404. Query now matches the schema.
- **Critical: `Export-GenAIConfigEvidence.ps1` solutionVersion** — Evidence JSON tagged `"solutionVersion": "1.0.1"` for every export despite the solution being on v1.2.x for months. Auditors couldn't tell which solution build produced a given evidence file. Now correctly emits `"1.2.1"`.
- **`Get-PurviewDLPEvidence.ps1` token separation** (M-3) — Single token was reused for both Microsoft Graph and Dataverse calls. Graph calls now use `Invoke-MgGraphRequest` (no manual token extraction), and Dataverse calls use a separately acquired token via `[string]$DataverseToken` parameter or `Az.Accounts` fallback (handles Az 12.x+ `SecureString` tokens).
- **PowerShell version pinning** (M-2): `Get-PurviewDLPEvidence.ps1` `#Requires -Version` raised from 7.0 to 7.4 (required for `Az.Accounts` SecureString token handling).
- **Drift comparison completeness** (m-1): `Start-GenAIConfigValidationRunbook.ps1` drift comparison object now includes `ModelKnowledgeEnabled` and `SemanticSearchEnabled` (Allow ungrounded responses and Work IQ). v1.1.0 added baseline persistence for these toggles but the runbook drift comparison still only checked AOAI / orchestration / generative-answers, so Rule 5 and Rule 6 violations never surfaced through the drift path.

### Documentation

- `.NOTES` version blocks aligned to v1.2.1 and PowerShell 7.4 across `Export-GenAIConfigEvidence.ps1`, `private/GACClient.psm1`, `private/Test-ParameterValidation.ps1`, and `private/Connect-EnvironmentDataverse.ps1`.

### Dependencies

- `requirements.txt`: Added `azure-identity>=1.15.0` (required by the shared `DataverseClient` for managed-identity, workload-identity-federation, and certificate authentication modes).

## [1.2.0] - 2026-05-12

### Added

- **Purview DLP and sensitivity label evidence** (`Get-PurviewDLPEvidence.ps1`): Queries Purview Compliance Manager for DLP policies covering generative AI scope (Microsoft 365 Copilot location), reads sensitivity labels applied to AI-related Dataverse tables and SharePoint knowledge sources, and generates a SHA-256 integrity-hashed audit evidence document with policy IDs, label IDs, and application timestamps. Reference: [DLP for Microsoft 365 Copilot](https://learn.microsoft.com/purview/dlp-microsoft365-copilot-location-learn-about).

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
