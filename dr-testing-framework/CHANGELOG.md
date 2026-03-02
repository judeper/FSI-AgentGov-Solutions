# Changelog

All notable changes to the DR Testing Framework.

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
  - RPO tracking (targets defined; actual measurement requires backup timestamp comparison — not yet implemented)
  - Success rate calculation
- **Gap Management** (planned):
  - Gap identification
  - Remediation tracking
- **Evidence Export** (planned):
  - Compliance artifact generation
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
