# Changelog

All notable changes to the Deny Event Correlation Report are documented here.

## [Unreleased]

### Changed

- **App Insights query API-key retirement date corrected to September 30, 2026.**
  Microsoft extended the Application Insights query API-key (`x-api-key`)
  retirement from the originally announced March 31, 2026 to **September 30,
  2026** (Azure Update "Retirement: Transition to Entra ID … by September 30,
  2026", modified 2026-04-21). Updated `docs/prerequisites.md`,
  `docs/troubleshooting.md`, `docs/architecture.md`, and the header notes in
  `scripts/Export-RaiTelemetry.ps1` so they no longer state the API key was
  removed on the (now past) March 31, 2026 date. The extractor already uses
  Entra ID authentication and is unaffected by the retirement either way.
- Added `LAB-VALIDATION.md` documenting static lab-readiness validation against
  authoritative Microsoft sources (Graph `runHuntingQuery`, `Search-UnifiedAuditLog`
  status, Defender `CloudAppEvents` schema, App Insights query API-key retirement).

### Fixed

- **Wave 6 P4b:** Empty catch blocks now log via `Write-Verbose` instead of silently swallowing errors. Output is unchanged unless caller passes `-Verbose`.

## [2.0.4] — 2026-05-23

### Fixed

- **Major**: Replaced placeholder `contoso.onmicrosoft.com` with RFC 2606 `example.onmicrosoft.com` in `scripts/Connect-ExchangeOnlineHelper.ps1:24`, completing the domain sweep started in v2.0.2. (council review MAJ-1)

### Changed

- **Minor**: Updated stale framework footer `v1.2 - January 2026` to `v1.6.0` in `docs/architecture.md:286`, `docs/prerequisites.md:250`, and `docs/troubleshooting.md:276` to match the README front matter. (council review MIN-1)
- **Minor**: Added inline comment in `scripts/Invoke-DailyDenyReport.ps1` Defender invocation block explaining why `$exchangeAuthArgs` is not splatted (Defender uses Microsoft Graph, not Exchange Online). (council review MIN-2)
- **Minor**: Added `.NOTES` clarification in `scripts/Export-RaiTelemetry.ps1` documenting that the script targets the classic Application Insights Logs API endpoint and that workspace-based App Insights resources require the Azure Monitor Logs API. Version header bumped to 1.4. (council review MIN-3)
- **Housekeeping**: Replaced non-ASCII em-dash (U+2014) characters with ASCII hyphens in `scripts/Connect-ExchangeOnlineHelper.ps1`, `scripts/Export-RaiTelemetry.ps1`, and `scripts/Invoke-DailyDenyReport.ps1` for PS 5.1 + PS 7 source-file portability.

## [2.0.3] — 2026-05-15

### Fixed

- **Invoke-DailyDenyReport.ps1**: Added managed identity and certificate-based Exchange Online authentication pass-through to the Purview Audit and DLP extractors so Azure Automation runbooks can use unattended auth end-to-end.
- **Export-CopilotDenyEvents.ps1 / Export-DlpCopilotEvents.ps1**: Reworded Microsoft Graph audit guidance to clarify that `Search-UnifiedAuditLog` remains the production extractor while Graph `/security/auditLog/queries` is a beta migration path that should be tracked for v1.0 readiness.
- **docs/prerequisites.md / docs/architecture.md / docs/troubleshooting.md**: Refreshed authentication guidance to managed identity-first, certificate-based Exchange Online fallback, and legacy dev-only client secret caveats.
- **kql-queries/content-filtered-events.kql**: Added a reusable source normalization block that supports both classic Application Insights `customEvents` and workspace-based `AppEvents` schemas.
- **docs/architecture.md / Export-DefenderCopilotEvents.ps1**: Aligned Defender guidance with the public `CloudAppEvents` schema and fixed Retry-After parsing in the Graph advanced hunting retry path.

## [2.0.2] — 2026

### Fixed

- **Connect-ExchangeOnlineHelper.ps1**: Added unattended authentication paths
  (`-AppId`/`-CertificateThumbprint`/`-Organization` for app-only, `-ManagedIdentity`
  for Azure Automation managed identity). Previously interactive-only — blocked
  unattended runbook execution.
- **Export-DefenderCopilotEvents.ps1**: Replaced unsupported `ActionType ==
  "CopilotMessageCreated"` and `XPIADetected`/`JailbreakDetected` boolean fields
  with the public `CloudAppEvents` schema (`ActionType == "CopilotInteraction"`
  + `parsedFields.ThreatCategory in ("PromptInjection","Jailbreak","XPIA")`).
- **Export-DefenderCopilotEvents.ps1**: Rewrote Graph error-handling to use
  `$_.ErrorDetails.Message` JSON parsing and `HttpResponseHeaders.GetValues()`
  for the Retry-After header (the previous `Headers["Retry-After"]` indexer
  is not implemented on .NET HttpResponseHeaders).
- **Export-DefenderCopilotEvents.ps1**: Fixed ISO-8601 timestamp escape (extra
  backslash on `Z`).
- **Export-DlpCopilotEvents.ps1**: Replaced incorrect Workload literal
  `"MicrosoftCopilot"` with the public Unified Audit Log values
  `"Copilot"` and `"MicrosoftCopilotStudio"`.
- **Export-DlpCopilotEvents.ps1**: Added unattended auth pass-through.
- **Export-RaiTelemetry.ps1**: Added `-AsSecureString` to `Get-AzAccessToken`
  to silence Az.Accounts ≥5.0 deprecation warning and ensure SecureString
  contract.
- **Export-RaiTelemetry.ps1**: Converted recursive 429 retry to iterative
  bounded loop; added 5xx retry path; corrected Retry-After header indexing.
- **Export-RaiTelemetry.ps1**: Documented App Insights API hard limits
  (500K rows / 64MB) and warn at both 10K and 500K row thresholds.
- **Export-CopilotDenyEvents.ps1 / Export-DlpCopilotEvents.ps1**: Pinned
  `ExchangeOnlineManagement` module to version 3.0.0+ (modern REST cmdlets).
  Added unattended auth pass-through to both extractors.
- **Invoke-DailyDenyReport.ps1**: Pinned EXO module 3.0.0+.
- **kql-queries/copilot-deny-events.kql / dlp-copilot-matches.kql**:
  Strengthened header to clarify that `OfficeActivity` flattens audit
  records and `parse_json(OfficeObjectId)` returns a string scalar — the
  queries assume a custom `_CL` table populated from raw Office 365
  Management Activity API JSON. The PowerShell extractors are the
  recommended path for tenants without that custom ingestion.
- **kql-queries/dlp-copilot-matches.kql**: Replaced 7 occurrences of
  `Workload == "MicrosoftCopilot"` with the correct `in
  ("Copilot","MicrosoftCopilotStudio")` literal.
- **kql-queries/cloud-app-events.kql**: Rewrote to align with public
  Defender XDR `CloudAppEvents` schema (`ActionType == "CopilotInteraction"`,
  `ThreatCategory in (...)`).
- **docs/architecture.md**: Removed implied SharePoint storage path (the
  delivered automation only writes to Azure Blob Storage). Narrowed SEC
  17a-4 wording to call out that the solution is one ancillary record
  source, not a complete 17a-4 program.
- **docs/prerequisites.md**: Pinned `ExchangeOnlineManagement` v3.0.0+,
  added Microsoft.Graph.Security install + `Connect-MgGraph` step,
  re-labelled deprecated x-api-key section as "Historical Reference",
  replaced contoso.com with example.com (RFC 2606).
- **docs/troubleshooting.md**: Replaced contoso.com with example.com,
  updated x-api-key wording from "deprecated" to "no longer functional".
- **README.md**: Softened SEC 17a-3/4 and FINRA 4511 wording with
  appropriate caveats; added Microsoft.Graph.Security install note;
  updated Quick Start to recommend `-SkipDefenderEvents` for first-run
  before Graph auth is configured; pinned EXO/Az module versions.
- Both audit-log extractors: added Search-UnifiedAuditLog deprecation
  notice in `.NOTES` pointing toward the future Microsoft Graph
  `auditLogQueries` API path.

## [2.0.1] — 2026-04-15

### Fixed

- Critical: Local CSV files are no longer deleted when blob uploads fail (prevents compliance evidence loss)
- Blob upload failures are now tracked and prevent premature file cleanup

## [2.0.0] — 2026-02-15

### Added
- Purview CopilotInteraction extraction script (`Export-CopilotDenyEvents.ps1`)
- Purview DLP extraction script (`Export-DlpCopilotEvents.ps1`)
- Shared Exchange Online connection helper (`Connect-ExchangeOnlineHelper.ps1`)
- Defender CloudAppEvents extraction script (`Export-DefenderCopilotEvents.ps1`)
- Application Insights RAI telemetry extraction script (`Export-RaiTelemetry.ps1`)
- Daily orchestration script (`Invoke-DailyDenyReport.ps1`)
- KQL queries for deny event correlation across 4 data sources (Purview Audit, DLP, Application Insights, Defender CloudAppEvents)
- Architecture documentation, prerequisites guide, and troubleshooting guide
- Support for FINRA 4511, SEC 17a-3/4, GLBA 501(b) regulatory alignment, and FINRA 24-09 / OCC 2011-12 supervisory guidance
