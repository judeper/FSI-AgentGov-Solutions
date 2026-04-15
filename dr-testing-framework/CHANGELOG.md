# Changelog

All notable changes to the DR Testing Framework.

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
