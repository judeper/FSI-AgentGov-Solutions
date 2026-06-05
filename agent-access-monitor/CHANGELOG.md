# Changelog

All notable changes to the Agent Access Governance Monitor.

## [Unreleased]

### Fixed

- **Major (lab validation):** `Get-EnvironmentAccessSettings.ps1` read agent sharing settings from `$env.Internal.governanceConfiguration.settings.extendedSettings`, which is the wrong object path. The authoritative [Power Platform "Limit sharing"](https://learn.microsoft.com/power-platform/admin/managed-environment-sharing-limits) PowerShell guidance and the script's own environment-group / managed-state reads use `$env.Internal.properties.governanceConfiguration` / `$env.Internal.properties.*`. The missing `.properties.` segment caused `bot-limitSharingMode`, `bot-authoringSharingDisabled`, and `bot-publishedBotLimitSharingMode` to read as `null`, which `Compare-ZoneCompliance.ps1` then defaults to `noLimit`/`false` — producing systematic false Critical/High violations in Zone 2/3. Corrected both extraction sites (`Get-ExtendedSetting` and the raw-settings loop). Runtime behavior is not verifiable without a live Managed Environment; the fix is grounded in the authoritative source and internal consistency.
- **Minor (lab validation):** `templates/zone-settings-baseline.json` setting descriptions for `ExcludeSharingToSecurityGroups` were reversed — they described sharing as "restricted to security groups only" when the [authoritative behavior](https://learn.microsoft.com/power-platform/admin/managed-environment-sharing-limits) excludes security-group sharing and limits sharing to individual users. Corrected both `bot-limitSharingMode` and `bot-publishedBotLimitSharingMode` descriptions so violation/evidence output is accurate.
- **Wave 6 P4b:** Empty catch blocks now log via `Write-Verbose` instead of silently swallowing errors. Output is unchanged unless caller passes `-Verbose`.
- **Major (command-existence, second-pass):** `Get-EnvironmentAccessSettings.ps1` called `Get-AdminPowerAppEnvironmentGroup`, which does not exist in the [Microsoft.PowerApps.Administration.PowerShell module](https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/) — the module exposes no environment-group cmdlet. The call could never succeed and emitted a warning on every run. Removed the dead lookup; the environment-group GUID is still captured from `$env.Internal.properties.environmentGroup.id` and the friendly group name stays `null` (resolve from the Power Platform admin center if needed). No change to result-object shape.

## [1.1.2] - 2026-05-23

### Fixed

- **Major**: `scripts/private/AAMClient.psm1` module header `Version:` bumped from `1.1.0` to match the solution version, eliminating audit-evidence version-mismatch ambiguity. (council review M-1)
- **Major**: `scripts/aam_client.py` now lazy-imports `azure.identity` and `azure.core.exceptions` inside `_azure_identity_class()` and `_client_authentication_error_cls()` helpers, mirroring `scripts/shared/dataverse_client.py`. Consumers using only `--access-token` or legacy client-secret authentication no longer require the optional Azure Identity packages at import time. (council review M-2)
- **Major**: `scripts/aam_client.py` `get_global_optionset()` now lowercases the option-set name before the lookup query, matching the shared client's existing fix and preventing a stale 404 followed by a `SchemaNameisNotUnique` 400 on case-mismatched lookups. (council review M-3)

### Changed

- Version strings synchronized to `1.1.2` across `manifest.yaml`, README, `agent-access-monitor.psd1`, script `.SYNOPSIS Version:` headers, evidence export payloads, `zone-settings-baseline.json`, and `docs/evidence-export.md`.
- `Start-AccessValidationRunbook.ps1` replaces two pre-existing `Get-Date -AsUTC` invocations with `(Get-Date).ToUniversalTime().ToString("o")` so the script parses and runs on Windows PowerShell 5.1 in addition to PowerShell 7 (style sweep §10).

## [1.1.1] - 2026-05-13

### Added

- Python deployment entry points now support managed identity and workload identity federation for Dataverse authentication, with client secrets retained only as a legacy dev-only fallback.
- Sharing comparison now normalizes broad-sharing values from adjacent Agent 365 and Agent Builder surfaces (`all`, `AllUsers`, `OrgWide`, and tenant-wide variants) to the Managed Environment `noLimit` equivalent for severity evaluation.

### Fixed

- `Start-AccessValidationRunbook` drift detection now passes the acquired Dataverse token to `Get-EnvironmentAccessSettings.ps1`, preserving ELM-based zone classification during per-environment drift checks.
- Solution version metadata is synchronized to `1.1.1` across the manifest, README, module metadata, script notes, and evidence export payloads.

### Changed

- Documentation clarifies that AAM evaluates Managed Environment agent sharing settings, while Microsoft Graph Package Management and Agent Registry APIs remain preview candidates for future agent inventory expansion.
- Authentication guidance now recommends managed identity or workload identity for unattended Python deployment automation, with certificate app authentication documented for current PowerShell runbook paths.

## [1.1.0] - 2026-05-12

### BREAKING

- Severity bucket reclassification: evidence-export summary buckets (`criticalViolations`, `highViolations`, `warningViolations`) are now driven by `fsi_severitylabel` rather than the `fsi_severity` picklist alone. Critical and High both map to `fsi_severity = 100000003` (Failed) at the picklist level; the prior export code treated `Failed` as Critical, `Warning` as High, and `GracePeriod` as Warning, producing materially incorrect counts. After upgrade, regenerate prior-period evidence to obtain correct buckets. A separate `gracePeriodViolations` count is now emitted.
- `agent-access-monitor.psd1` `FunctionsToExport` replaced. The previous manifest referenced script names (`Test-AgentAccessCompliance`, `Get-EnvironmentAccessSettings`, `Compare-ZoneCompliance`) that are stand-alone runnable `param()` scripts, not functions. The manifest now exports the actual `AAMClient.psm1` helper functions (`Connect-AAMDataverse`, `Get-AAMConnection`, `Get-ValidToken`, `Get-AAMEnvironmentVariable`, `Get-AAMActiveBaseline`, `Write-AAMValidationHistory`, `Write-AAMViolation`, `Save-AAMBaseline`, `Get-AAMLastValidation`). Continue running scripts directly.

### Added

- `Get-AAMValidationResults` violation `$select` now retrieves `fsi_severitylabel` so the export bucketing can disambiguate Critical from High.
- `Export-AgentAccessEvidence` writes evidence JSON canonically (recursive key sort, stable record ordering, LF-only UTF-8 no BOM) for deterministic SHA-256 hashes across operating systems.
- `Export-AgentAccessEvidence` writes the `.sha256` companion file in standard `sha256sum -c`-compatible format (LF terminator, UTF-8 no BOM).
- `create_dataverse_schema.py` now sets explicit `EntitySetName` and `LogicalCollectionName` on `fsi_accessbaselines`, `fsi_accessvalidationhistory`, and `fsi_accessviolations` so the OData entity set names are deterministic across deployments (avoids default pluralization risk for `…history`).
- `AAMClient.Invoke-DataverseRequest` now honors the `Retry-After` response header on 429/5xx for Dataverse throttling.
- All `--interactive` deploy entry points (`deploy.py`, `create_dataverse_schema.py`, `create_environment_variables.py`, `create_connection_references.py`) now require `--client-id` because MSAL `PublicClientApplication` mandates it. Without this the prior `--interactive --dry-run` exited with `client_id is required for interactive authentication`.

### Fixed

- `Test-AgentAccessCompliance` no longer silently demotes a validation-history write failure to a warning. A failed write is now a terminating error so the runbook records a runbook failure rather than producing an evidence trail with no audit-history row (FINRA 4511 / SEC 17a-3 audit integrity).
- `Start-AccessValidationRunbook` drift detection now passes `-DataverseUrl`/`-AccessToken` to the per-environment settings query so zone classification uses the ELM lookup (correct), not the name-based fallback.
- `AAMClient.Get-ValidToken` now warns explicitly when a caller-supplied token is expired and no `ClientId`/`TenantId` is available to refresh it (previous behavior silently returned the stale token, leading to surprise 401s).
- `AAMClient` record `POST` calls (`Write-AAMValidationHistory`, `Write-AAMViolation`, `Save-AAMBaseline`) now use `ConvertTo-Json -Depth 10` to prevent nested-object truncation.
- `Get-ZoneClassification` ELM lookup failure escalated from `Write-Verbose` to `Write-Warning` so silent fallbacks to name-based classification are visible in operator logs.
- `Export-AgentAccessEvidence` `.DESCRIPTION` corrected from "Controls 1.18/1.19" to Control 3.8 (matches script header and framework mapping).
- `Export-AgentAccessEvidence` overall-status computation reorders the `NoData` check first so an empty export is no longer reported as `Passed`.
- `docs/TROUBLESHOOTING.md` `deploy.py` authentication failure remediation: replaced `az login` guidance with MSAL re-authentication instructions (the deployment uses MSAL directly, not the Azure CLI).
- `docs/evidence-export.md` sample `solutionVersion` bumped from `1.0.0` to `1.1.0`.
- All script `.NOTES Version` and module manifest `ModuleVersion` synchronized to `1.1.0`.

### Notes

- Previous CHANGELOG entries had inverted dates (v1.0.3 dated 2026-04-08, v1.0.2 dated 2026-04-15, v1.0.1 dated 2026-07-15). Dates below are corrected to a monotonic order; entry contents are unchanged.

## [1.0.3] - 2026-04-15

### Fixed

- Critical: Zone filter OData query in Get-AAMValidationResults used wrong hashtable keys (`Zone1`/`Zone2`/`Zone3` instead of `1`/`2`/`3`), causing zone filtering to never match
- Critical: Evidence export severity/zone summary stats always zero — added label mapping from Dataverse option set integers to human-readable strings
- High: `fsi_zone` in fsi_accessvalidationhistory schema changed from ApplicationRequired to optional (None) since aggregate runs span multiple zones
- High: Version strings synchronized to 1.0.2 across agent-access-monitor.psd1, Export-AgentAccessEvidence.ps1, Test-AgentAccessCompliance.ps1, Compare-ZoneCompliance.ps1, and AAMClient.psm1
- Medium: Added `#Requires -Modules MSAL.PS` to Invoke-AccessBaselineCapture.ps1 and Export-AgentAccessEvidence.ps1
- Medium: Added `#Requires -Version 7.0` to Compare-ZoneCompliance.ps1
- Medium: Updated adaptive card driftWarning to reference docs/flow-configuration.md instead of removed access-validation-flow.json
- Medium: Corrected primary control IDs in Test-AgentAccessCompliance.ps1 .NOTES from 2.5/2.6 to 3.8
- Medium: Fixed evidence-export.md sample JSON `overallStatus` from "NonCompliant" to "Failed"
- Low: Updated stale documentation references (SCHEMA.md → dataverse-schema.md) in agent-access-monitor.psd1 and .ralph-config.json

## [1.0.2] - 2026-04-08

### Fixed

- Critical: Save-AAMBaseline now maps zone integers (1/2/3) to Dataverse option set values (100000001+) before writing
- Critical: Get-AAMValidationResults zone filter now uses correct option set integers
- Export-AgentAccessEvidence: fixed status comparison from "Compliant" to "Passed" to match validation writer
- Get-ZoneClassification: fixed `fsi_environment_id` → `fsi_environmentid` (Dataverse naming convention)
- dataverse-schema.md: corrected fsi_zone type from Integer to OptionSet, fsi_severity from String to OptionSet, fsi_summaryjson from String to Memo

## [1.0.1] - 2026-03-15

### Changed
- Moved adaptive card templates from `src/` to `templates/` (repository content policy alignment)
- Removed `src/access-validation-flow.json` flow export (see `docs/flow-configuration.md` for manual build instructions)
- Removed `src/` directory — solutions provide documentation and scripts, not Power Platform runtime artifacts

## [1.0.0] - 2026-02-19

### Added — Phase 4: Evidence Export & Framework Integration

#### Evidence Export
- **Export-AgentAccessEvidence.ps1** — Main evidence export script
  - Zone-based filtering (All/1/2/3)
  - Date range support with -FromDate and -ToDate
  - Optional baseline inclusion with -IncludeBaselines
  - JSON output with -Depth 10 (prevents nested object truncation)
  - SHA-256 companion hash files in standard checksum format
  - Interactive and certificate-based authentication modes

- **Get-AAMValidationResults.ps1** (private) — Dataverse query helper
  - Queries fsi_accessvalidationhistory and fsi_accessviolations
  - OData filtering with automatic pagination support

- **Test-EvidenceIntegrity.ps1** — SHA-256 hash verification utility
  - Single file and batch verification modes
  - Cross-platform hash format compatibility (shasum, certutil)

#### Documentation
- **dataverse-schema.md** — Dataverse schema reference (3 tables, option sets, environment variables)
- **evidence-export.md** — Evidence export operations guide with verification procedures
- **troubleshooting.md** — Common issues and resolutions (6 categories)

#### Framework Integration
- Control 3.8 tip admonition linking to Agent Access Governance Monitor solution
- solutions-index.md catalog entry with regulatory alignment (FINRA 4511, SOX 404)

## [0.3.0] - 2026-02-17

### Added
- Start-AccessValidationRunbook.ps1 - Azure Automation runbook wrapper for non-interactive daily access validation with certificate-based auth and structured JSON output
- Invoke-AccessBaselineCapture.ps1 - Operator-initiated baseline capture writing environment access settings to Dataverse with active baseline management
- adaptive-card-access-alert.json - Teams adaptive card template for agent access violation and drift alerts with severity classification
- access-validation-flow.json - Power Automate cloud flow for daily scheduled validation, Dataverse persistence, and conditional Teams/email alerting
- flow-configuration.md - Step-by-step guide for flow import, configuration, connection reference binding, and testing
- Save-AAMBaseline function in AAMClient.psm1 for writing access baseline records with active baseline rotation
- Get-AAMLastValidation function in AAMClient.psm1 for querying validation history (drift detection support)

### Changed
- AAMClient.psm1 now exports 9 functions (was 6): added Save-AAMBaseline, Get-AAMLastValidation, and Get-ValidToken
- Start-AccessValidationRunbook.ps1 enriches ZoneSummary to per-zone objects with Total/Compliant/Violations for flow and adaptive card consumption

## [0.2.0] - 2026-02-09

### Added
- Dataverse integration: `aam_client.py` for Dataverse Web API operations
- Schema deployment: `create_dataverse_schema.py` for 3 tables + shared option sets
- Environment variables: `create_environment_variables.py` for 6 operational parameters
- Connection references: `create_connection_references.py` for Dataverse, O365, Teams
- Deployment orchestrator: `deploy.py` with full/selective/dry-run support
- Test-AgentAccessCompliance.ps1: `-DataverseToken`, `-PersistResults` parameters
- Dataverse environment variable reads for operational parameters (grace period, sandbox inclusion)
- Validation result persistence to `fsi_accessvalidationhistory`
- Violation persistence to `fsi_accessviolations`
- Graceful fallback when Dataverse is unavailable

### Changed
- Write-AAMValidationHistory: added `-RunId` parameter, sets `fsi_name` and `fsi_runid`
- Write-AAMViolation: added `-RunId` parameter, sets `fsi_name`

## [0.1.0] - 2026-02-09

### Added
- Initial solution scaffold
- Get-EnvironmentAccessSettings.ps1 — Query Power Platform environments for agent access settings
- Compare-ZoneCompliance.ps1 — Compare settings against zone-specific requirements
- Test-AgentAccessCompliance.ps1 — Orchestrator with dry-run mode and multiple output formats
- Zone classification via Dataverse baseline lookup (`fsi_accessbaselines`) with naming convention fallback
- Severity classification (Critical/High/Warning/Info) per zone and violation type
- Regulatory context (FINRA 4511, SOX 404) in violation output
- Grace period filtering for newly provisioned environments
- Environment group support for group-level rule visibility

### Known Limitations
- Dataverse persistence not yet implemented (Phase 2)
- M365 Admin Center agent settings not queryable via API (portal-only)
