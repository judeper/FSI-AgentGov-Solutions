# Changelog

All notable changes to the Generative AI Config Auditor are documented in this file.

## [Unreleased]

### Validated

- **Live tenant validation — bot-config-state detection path (2026-06-13, the lab validation tenant).** The five `fsi_GAC*` Dataverse tables and the shared/GAC-specific option sets were deployed, and the detection path was proven end-to-end against disposable-bot fixtures: a Zone 1 fixture with all three generative flags on fired **Critical** (three rules), an all-off fixture produced no row, and an all-nodes-absent fixture fired the new fail-closed **Rule 7** (Warning, never a false Compliant). The SHA-256 evidence digest (prefix `8D55C369`) recomputed to an integrity match, and all disposable fixtures were torn down with the tables verified back to zero — the deployed schema is the retained deliverable. This is **lab evidence** from disposable fixtures, not a production guarantee; customer-tenant evidence comes from running the solution against the customer tenant. The Work IQ usage-telemetry and Purview DLP legs remain out of lab scope (no connectors on the lab validation tenant). Full record: `LAB-VALIDATION.md` → "Live tenant validation outcome — 2026-06-13".

### Changed

- **Zone/severity reconciliation to OPTION A canonical.** Flipped the zone semantics so the strictest generative-AI policy attaches to **Zone 1 (Enterprise)** (was Zone 3) and the advisory policy to Zone 3 (Personal), across `private/Get-ExpectedGenAIPolicy.ps1`, `private/GACClient.psm1`, `Compare-GenAIConfigCompliance.ps1` (whitelist enforcement now policy-derived), `private/Get-GACValidationResults.ps1`, `governance/Import-ApprovedAoaiConnections.ps1`, and the shared `scripts/shared/Get-ZoneClassification.ps1` naming map (enterprise/prod → Zone 1; personal/dev/sandbox → Zone 3). Reconciled the PowerShell zone→integer maps and the `create_dataverse_schema.py` shared option-set declarations to the live canonical set (Unclassified=100000000, Zone1=100000001, Zone2=100000002, Zone3=100000003; create-if-missing → reuse). Confirmed `fsi_GACViolation.fsi_Severity` is a free String (no column-binding change). Added `lab/tests/GacZoneCanonical.Tests.ps1` proving "strictest gen-AI policy ⇔ Zone 1 ⇔ 100000001" (10/10 pass).
- **Detector nested re-path to the live `bot.configuration` keys.** `Get-AgentGenAISettings.ps1` now probes the real nested keys `settings.GenerativeActionsEnabled`, `aISettings.useModelKnowledge`, and `aISettings.isSemanticSearchEnabled` first (legacy flat keys retained as a fallback); a missing node stays "Unable to Determine" (defensive — never a false Compliant). The nested shape was confirmed read-only against the lab validation tenant before the live leg.

### Fixed

- **Rule 7 — fail-closed on indeterminate generative-AI config (commit `a8c2af9`).** The 2026-06-13 live indeterminate test exposed a comparator gap: a bot whose three config-state nodes all resolve to "Unable to Determine", with no other rule firing, would previously have been reported **Compliant** — a false-Compliant on a genuinely unknown posture. `Compare-GenAIConfigCompliance.ps1` now adds **Rule 7 (Indeterminate configuration, fail-closed)**: when all three config-state nodes are "Unable to Determine" and no other rule fired, it emits a `Warning` `IndeterminateConfiguration` violation instead of a silent Compliant. Mirrors the Indeterminate handling already present in the CMM and FUS sibling solutions; the real-agent cross-check confirmed it does not mis-flag normally-configured agents. PSScriptAnalyzer 0 / Pester 10/10 / `py_compile` OK.

- **`Get-AgentGenAISettings.ps1` botcomponent query used wrong lookup column and component types** — The per-agent topic scan filtered `botcomponents` on `_botid_value` with `componenttype eq 12 or componenttype eq 2`. The bot lookup on the `botcomponent` table is `parentbotid` (logical value `_parentbotid_value`), so `_botid_value` is not a valid filter property and Dataverse returns `400 Bad Request` — silently swallowed by the surrounding `try/catch`, leaving `GenerativeAnswersNodeCount`, `KnowledgeSourceCount`, and `TopicSummary` permanently empty for every agent. The component-type integers were also wrong: in `botcomponent_componenttype`, `12` is *Bot variable (V2)* and `2` is *Bot variable* — not Topic/Dialog. The filter now targets `_parentbotid_value` with topic types `0` (Topic) and `9` (Topic (V2)). References: [Copilot component (botcomponent) table reference — `parentbotid` / `componenttype` choices](https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/botcomponent).
- **`Connect-EnvironmentDataverse.ps1` SecureString token handling** — `Get-AzAccessToken` returns the access token as a `SecureString` by default on Az.Accounts 5.x (older versions return a plain `String`). The interactive auth path returned `$tokenResult.Token` verbatim, so on current Az.Accounts the bearer token became the literal string `System.Security.SecureString`, producing `401 Unauthorized` on every per-environment and ELM Dataverse call made by `Get-AgentGenAISettings.ps1`. The token is now normalized to plain text via `[System.Net.NetworkCredential]`, matching the existing handling in `GACClient.psm1`, `Get-PurviewDLPEvidence.ps1`, and `Import-ApprovedAoaiConnections.ps1`. Reference: [Get-AzAccessToken](https://learn.microsoft.com/powershell/module/az.accounts/get-azaccesstoken) ("the default output type has been changed from a plain text `String` to `SecureString`").

### Documentation

- **README `Solution Components` tree completed** — Added the two scripts that ship in `scripts/` but were missing from the documented file tree: `Get-PurviewDLPEvidence.ps1` (the v1.2.0 Purview DLP / sensitivity-label evidence collector listed in the Features table) and `private/Get-GACValidationResults.ps1` (Dataverse validation-result reader). No code change; documentation now matches the deployed script set.
- **`docs/prerequisites.md` API permissions corrected** — Removed the inaccurate "Microsoft Graph `Environment.Read.All` (Application)" row; environment enumeration is performed by `Microsoft.PowerApps.Administration.PowerShell` (`Get-AdminPowerAppEnvironment`) against the Power Platform Admin (BAP) API and is governed by the admin roles already listed, not a Microsoft Graph scope. Documented the Graph permission that `Get-PurviewDLPEvidence.ps1` actually requires: `InformationProtectionPolicy.Read` (Delegated) / `InformationProtectionPolicy.Read.All` (Application). Reference: [List informationProtection labels](https://learn.microsoft.com/graph/api/informationprotectionpolicy-list-labels).
- **`docs/prerequisites.md` module list** — Added `Microsoft.Graph.Authentication` (required by `Get-PurviewDLPEvidence.ps1` for `Invoke-MgGraphRequest`) and `ExchangeOnlineManagement` (optional, for `Get-DlpCompliancePolicy` / `Get-Label`), plus their install commands. Noted that Az.Accounts 5.x SecureString tokens are handled automatically.
- **`docs/flow-configuration.md` Parse JSON schema aligned to runbook output** — The `GAC-DailyAudit` Parse JSON schema documented violation fields (`Feature`, `ExpectedPolicy`, `ActualConfig`) and a `Drift.DriftDetected` property that `Start-GenAIConfigValidationRunbook.ps1` does not emit. Corrected the violation item properties to the actual fields (`AzureOpenAIEnabled`, `OrchestrationMode`, `GenerativeAnswersNodeCount`) and the `Drift` object to `HasDrift` / `IsFirstRun` / `DriftedAgents` / `Details`.
- **README technical re-verification (`Last Verified` 2026-05-25 → 2026-07-26).** Re-checked every Microsoft product claim in `README.md` against current Microsoft Learn documentation. Still accurate, no change: **Allow ungrounded responses** remains the Copilot Studio setting name and **AI general knowledge** remains Microsoft's term for the capability it unlocks; classic and generative **orchestration** remain the two documented modes (generative is the default for new agents); **generative answers nodes** and **Azure OpenAI Service** connections as a generative-answers data source both remain documented (Azure OpenAI is reached from the node's *Classic data* option, and classic orchestration still caps Azure OpenAI Service connections at 5); the Power Platform admin center still exposes a centralized **Copilot > Settings** area; the environment-level **Generative AI features** pane and the tenant-level **Publish Copilots with AI features** setting both still exist; the Microsoft 365 admin center still governs agents and AI actions surfaced in Microsoft 365 Copilot; and Microsoft Purview DLP still supports a Microsoft 365 Copilot scope with sensitivity-label-based conditions.
- **Minor**: The README labeled the agent-level semantic search toggle **Work IQ (semantic search)**. Microsoft documents it on the Copilot Studio **Generative AI** settings page as **Tenant graph grounding with semantic search**, and now documents a separate, unrelated **Work IQ MCP** capability (preview) that this solution does not audit. Relabeled the four affected README references to Microsoft's current name and added a naming note recording the prior label, the unchanged Dataverse column (`fsi_semanticsearchenabled`), the unchanged detector key (`aISettings.isSemanticSearchEnabled`), and the pointer to the `work-iq-usage-detection` solution for Work IQ MCP. Also captured two verified product dependencies not previously documented: both **Allow ungrounded responses** and **Tenant graph grounding with semantic search** require generative orchestration, and tenant graph grounding additionally requires the agent's user authentication to be **Authenticate with Microsoft**. Reference: [Knowledge sources summary](https://learn.microsoft.com/microsoft-copilot-studio/knowledge-copilot-studio#knowledge-source-agent-settings).
- **Minor**: The voice platform note cited `microsoft-copilot-studio/voice-configuration`, which Microsoft has since narrowed to *Configure basic voice agents*, while the surrounding text described "Basic and Realtime voice modes". Microsoft now documents IVR as two agent types — **basic voice agents** (classic orchestration) and **real-time voice agents** (generative orchestration, speech-to-speech model). Re-pointed the citations to `voice-overview`, `voice-basic-overview`, `voice-realtime-voice-agents`, and `voice-dtmf`, adopted the current terminology, and noted that voice track selection is coupled to the orchestration mode this solution already audits. No regulatory or record-keeping wording was changed.

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
