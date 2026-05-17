# Changelog

All notable changes to the DR Readiness Validation Framework.

---

## [Unreleased]

## [2.0.1] - 2026-05-17

### Changed

- Bumped manifest metadata to v2.0.1 for the 2026-Q2 Microsoft Learn refresh.
- Aligned README, evidence export docs, templates, and generated Dataverse schema wording with current Power Platform backup/restore, Application Insights telemetry, and Microsoft Entra resilience guidance.
- Added access-token authentication paths for managed identity and workload identity callers; client-secret prompts and environment variables are marked legacy dev-only.
- Replaced stale RTO/RPO aggregation examples with probe-duration and validation-coverage semantics used by `Invoke-DRTest.ps1` and `Export-DREvidence.ps1`.
- Renamed the evidence metric `ProbeBudgetComplianceRate` to `ProbeWithinBudgetRate` to avoid over-claiming compliance from a timing probe.

## [2.0.0] - 2026-04-16 — BREAKING

### BREAKING CHANGES

This release renames and reframes the framework as **post-recovery validation and evidence packaging** rather than recovery execution. The previous v1.x naming overstated what the script can do — Power Platform / Copilot Studio environments are tenant-bound metadata managed by Microsoft, and a customer script cannot back them up, restore them, or fail them over. v1.x readers should treat outputs as validation evidence, not recovery execution evidence. See README "What this framework actually does (and does not do)" for the full scope.

- **TestType values renamed.** `AgentRestore` → `AgentReadinessCheck`, `EnvironmentFailover` → `EnvironmentReachabilityCheck`, `DataRecovery` → `DataverseAccessCheck`, `FullDR` → `FullValidation`. Legacy values are still accepted at the CLI and emit a deprecation warning, then map to the new names. Pipelines that hard-code the old strings continue to work for one minor cycle; please migrate.
- **`ActualRTO` / `TargetRTO` / `RTOMet` retired in favour of `ProbeDurationHours` / `ProbeDurationTargetHours` / `ProbeWithinBudget`.** The Dataverse column names (`fsi_actualrto`, `fsi_targetrto`, `fsi_rtomet`) are preserved for v1.x compatibility but their **stored semantics changed** — they now represent the wall-clock duration of the read-only validation, NOT the recovery time of the underlying restore. Update any dashboards or downstream consumers accordingly.
- **`ActualRPO` / `TargetRPO` / `RPOMet` retired in favour of `MinutesSinceLastResult` / `MaxMinutesSinceLastResult` / `LastResultWithinThreshold`.** These are cadence-freshness metrics, not regulator-grade RPO. The previous claim that `ActualRPO = "time since last DR-test row written"` was dressed up as a backup recency measurement and that was misleading.
- **Fail-closed authentication.** Missing `TenantId`/`ClientId`/`ClientSecret` is now an error in non-DryRun runs. Pass the new `-AllowConnectivityOnly` switch to opt in to a network-only check that records "Probe" results without authenticated validation. v1.x silently fell through to PASS on auth failure, which produced false-positive evidence rows.
- **PowerShell 7.1+ required.** `#Requires -Version` bumped from 7.0 to 7.1. The script always used `Get-Date -AsUTC`, which was added in 7.1; v1.x would crash at runtime on PS 7.0.
- **`Export-DREvidence.ps1` exit codes.** Statuses `Compliant`/`NonCompliant`/`Incomplete` renamed to `Validated`/`ValidationFailures`/`IncompleteValidationCoverage`. New exit code `2` for `NoData` and `IncompleteValidationCoverage` (was `0`); failures still exit `1`.

### Fixed

- **Pagination on Dataverse reads.** `Export-DREvidence.ps1` now follows `@odata.nextLink` so evidence exports across more than 5000 rows no longer silently truncate.
- **Authoritative record counts.** `Test-DataRecovery` (now `DataverseAccessCheck`) uses `?$count=true&$top=0` and reads `@odata.count` instead of returning the page-size of the value array.
- **`fsi_executedon` `DateTimeBehavior` corrected to `TimeZoneIndependent`.** v1.x set `UserLocal`, which silently shifted timestamps based on the calling user's timezone — broken for cross-region audit.
- **Environment-variable type code for `Decimal` corrected.** v1.x mapped `Decimal` to `100000001` (Number); environment variables have no native Decimal type, so v2.0.0 maps `Decimal` to `100000003` (JSON) and documents that flows must JSON-parse the value.

### Removed

- **Azure Backup / Backup Operator role from prereqs.** Power Platform environment backups are managed by Microsoft via PPAC; Azure Backup never applied.
- **Control 2.13 (Documentation) from Related Controls.** Catalog mapping is `2.4, 2.1, 1.9` only — the README was drifting.
- **OCC Bulletin 2011-12 references.** OCC 2011-12 governs model risk; replaced with the correct combination of FFIEC BCP, OCC Heightened Standards, FINRA Rule 4370, and SEC Rule 17a-4(f).
- **Two unused environment variables (`fsi_DRT_TargetRTOMinutes` and `fsi_DRT_TargetRPOMinutes`)** retired. They were defined in minutes but the script hard-coded targets in hours and never read them. Replaced with `fsi_DRT_ProbeBudgetMinutes` and `fsi_DRT_MaxMinutesSinceLastResult` reserved for a future wiring.

### Migration

1. Re-deploy environment variables: `python scripts/create_drt_environment_variables.py --interactive`. The two old variables are not removed automatically — delete them manually from PPAC if no other process consumes them.
2. Re-deploy the Dataverse schema: `python scripts/create_drt_dataverse_schema.py --interactive`. The DateTimeBehavior change requires recreating the column or asking Microsoft Support to flip the behavior in-place; existing rows retain their stored values.
3. Update any callers of `Invoke-DRTest.ps1` that pass the legacy `TestType` values — the alias map preserves behaviour but emits warnings; clean up over the next minor release.
4. Update dashboards / downstream consumers that read `fsi_actualrto`, `fsi_targetrto`, `fsi_rtomet` to relabel their semantics — values now reflect probe duration, not recovery time.
5. Confirm that any automation calling `Invoke-DRTest.ps1` either passes service-principal credentials or explicitly opts in with `-AllowConnectivityOnly`. Silent-PASS-on-auth-failure runs no longer happen.

---

## [1.2.1] - 2026-04-15

### Fixed

- Critical: Save-TestResult now includes required fsi_name primary attribute (was omitted, causing Dataverse writes to fail)

---

## [1.2.0] - 2026-04-10

### Added
- Environment variables deployment script (6 variables: RTO/RPO targets, notifications)
- Connection references script (Dataverse + Teams)
- Python requirements.txt

### Changed
- Replaced stub implementations in `Invoke-DRTest.ps1`:
  - Test-AgentRestore: real Dataverse bot queries, component verification, security validation
  - Test-EnvironmentFailover: HTTP health check, WhoAmI, data sync verification
  - Test-DataRecovery: restore point queries, SHA-256 integrity, RPO measurement
- Replaced stub in `Export-DREvidence.ps1`: real Dataverse queries, metric aggregation, gap analysis, SHA-256 evidence hash
- ActualRPO/RPOMet now computed from real data recovery measurements

---

## [1.1.0] - 2026-04-10

### Added

- **Dataverse schema script** (`create_drt_dataverse_schema.py`) — automated table and column creation for `fsi_drtestresult` with `--output-docs`, `--dry-run`, and `--interactive` flags
- **Documentation suite:**
  - `docs/prerequisites.md` — licensing, roles, network requirements, sovereign cloud endpoints
  - `docs/dataverse-schema.md` — auto-generated table and column reference
  - `docs/evidence-export.md` — evidence packaging guide with output format and regulatory alignment
  - `docs/troubleshooting.md` — auth, Dataverse, test execution, and Pester issue resolution
- **Templates:**
  - `templates/dr-test-config.sample.json` — sample test configuration with RTO/RPO targets
  - `templates/dr-evidence-metadata.sample.json` — sample evidence export output structure
- README updated with documentation links and automated schema deployment instructions

---

## [1.0.2] - 2026-03-15

### Fixed

- `Get-AccessToken` now resolves the correct Entra ID authority for sovereign clouds via new `Get-AuthEndpoint` helper — China (`.dynamics.cn` → `login.chinacloudapi.cn`), GCC High (`.microsoftdynamics.us` / `.appsplatform.us` → `login.microsoftonline.us`)
- `ClientId` parameter now validates GUID format with `[ValidatePattern]`, matching existing `TenantId` validation
- Script now exits with code 2 when Dataverse persistence fails (auth error or save error), preventing silent masking in CI pipelines

### Added

- `Get-AuthEndpoint` function for sovereign cloud auth endpoint resolution
- `Export-DREvidence.ps1` includes guidance comment for sovereign cloud auth when Dataverse integration is added
- Exit codes documentation in README (0 = pass, 1 = test fail, 2 = persistence fail)
- Pester tests for `Get-AuthEndpoint` sovereign cloud mapping
- Pester tests for `ClientId` GUID validation

---

## [1.0.1] - 2026-03-15

### Fixed

- `Write-AuditLog` changed from `Write-Output` to `Write-Information` to prevent success-stream contamination of function return values (e.g., `Get-AccessToken` retry path)
- `Get-AccessToken` and `Save-TestResult` no longer treat explicit `throw` (RuntimeException) as transient — prevents unnecessary retries on malformed token responses
- `Save-TestResult` serializes `ValidationChecks` via `-InputObject` instead of pipeline to preserve JSON array wrapper for single-item collections
- `Get-AccessToken` and `Save-TestResult` now inspect `Retry-After` header on HTTP 429 responses
- `Export-DREvidence.ps1` now validates `$Environment` parameter against Dataverse URL regex (SSRF prevention)

### Added

- `Write-Verbose` diagnostic statements at key decision points (token acquisition, retry attempts, Dataverse save)
- DryRun path tests for all three test functions
- `Write-AuditLog` stream isolation regression test
- RPO measurement caveats in FFIEC BCP and SEC 17a-4 regulatory alignment sections
- Solution package roadmap note in Deployment section

---

## [1.0.0] - 2026-02-15

### Added

- Initial release of DR Testing Framework
- **Test Scenarios:**
  - Agent Restore (RTO: 4 hours)
  - Environment Failover (RTO: 2 hours)
  - Data Recovery (RTO: 4 hours)
  - Full DR (RTO: 8 hours)
- **Validation Checks:**
  - Agent responsiveness
  - Connector functionality
  - Data integrity
  - Security policy application
- **PowerShell Scripts:**
  - `Invoke-DRTest.ps1` - Execute DR tests
  - `Export-DREvidence.ps1` - Export compliance evidence (stub)
- **Metrics:**
  - RTO measurement and comparison
  - RPO tracking (targets defined; actual measurement requires backup timestamp comparison — not yet implemented)
  - Success rate calculation
- **Gap Management** (planned):
  - Gap identification
  - Remediation tracking
- **Evidence Export** (stub):
  - Audit log file collection and packaging
  - JSON evidence metadata generation
- **Documentation:**
  - Prerequisites and licensing
  - Test scenario details
  - Validation check guide

### Regulatory Alignment

- OCC Heightened Standards - Operational Resilience
- FFIEC BCP - Business Continuity Planning
- SEC Rule 17a-4 - Record Recovery
- FINRA Rule 4370 - Business Continuity Plans

---

*DR Testing Framework - FSI Agent Governance Framework*
