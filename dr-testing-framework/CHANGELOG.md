# Changelog

All notable changes to the DR Testing Framework.

---

## [1.0.2] - March 2026

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

## [1.0.1] - March 2026

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

## [1.0.0] - February 2026

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
