# Changelog

All notable changes to the COI Testing Framework.

---

## [1.0.2] - 2026-04-16

### Fixed

- Fixed prohibited compliance language: "ensure" → "help support" in README.md
- Fixed product name: "Azure AD" → "Microsoft Entra ID" in prerequisites.md
- Fixed version mismatch in README footer (v1.0.0 → v1.0.2)
- Removed unused imports (hashlib, Path) from run_coi_tests.py

---

## [1.0.1] - April 2026

### Added

- Documentation suite: docs/prerequisites.md, docs/test-scenarios.md, docs/troubleshooting.md

---

## [1.0.0] - February 2026

### Added

- Initial release of COI Testing Framework
- **Test Categories:**
  - Proprietary product bias detection (3 scenarios)
  - Suitability testing (3 scenarios)
  - Fee transparency verification (2 scenarios)
  - Cross-selling analysis (2 scenarios)
- **Python Test Runner:**
  - `run_coi_tests.py` - Execute tests against agents
  - Scheduled and on-demand execution
  - Text, JSON, HTML report formats
- **Dataverse Integration:**
  - Test result storage
  - Finding tracking
  - Supervision workflow integration
- **Documentation:**
  - Test scenario library
  - Custom test creation guide

### Regulatory Alignment

- FINRA Rule 2111 - Suitability
- FINRA Rule 2010 - Standards of Commercial Honor
- FINRA Rule 2210 - Communications
- SEC Regulation Best Interest

---

*COI Testing Framework - FSI Agent Governance Framework*
