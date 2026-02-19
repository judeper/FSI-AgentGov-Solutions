# Changelog

All notable changes to the DR Testing Framework.

---

## [Unreleased]

### Fixed

- Tightened environment URL validation regex to use explicit TLD allowlist (`com`, `us`, `cn`, `de`) instead of permissive `\w+`
- Added GCC High Dataverse URL support (`microsoftdynamics.us`)
- Added warning message when `Save-TestResult` fails after retries (previously silent)

### Added

- Pester tests for URL validation, save failure handling, and script structure (`Invoke-DRTest.Tests.ps1`)
- Dataverse `fsi_drtestresults` table schema documentation in README (column types, option set values, field descriptions)

### Planned

- **Evidence Export:** Compliance artifact generation
- **Gap Management:** Gap identification and remediation tracking

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
- **Metrics:**
  - RTO measurement and comparison
  - RPO tracking (targets defined; measurement not yet implemented — RPO fields omitted from Dataverse until implemented)
  - Success rate calculation
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
