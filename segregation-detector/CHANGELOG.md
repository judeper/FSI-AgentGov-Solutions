# Changelog

All notable changes to the Segregation of Duties Detector.

---

## [1.0.0] - February 2026

### Added

- Initial release of Segregation of Duties Detector
- **Dataverse Schema:**
  - `fsi_conflictrule` - Conflict rule definitions
  - `fsi_sodviolation` - Detected violations
  - `fsi_sodexception` - Approved exceptions
  - `fsi_sodauditlog` - Audit trail
- **Security Roles:**
  - SoD Viewer - Read-only compliance access
  - SoD Analyst - Exception management
  - SoD Admin - Full administrative access
- **PowerShell Scripts:**
  - `Invoke-SoDScan.ps1` - Full directory scan for violations
  - `Import-ConflictRules.ps1` - Rule set import
- **Default Rule Sets:**
  - Maker/Checker rules (5 rules)
  - Segregation rules (5 rules)
  - Privileged Access rules (4 rules)
- **Documentation:**
  - Prerequisites and licensing
  - Dataverse schema definitions
  - Conflict rules configuration
  - Troubleshooting guide

### Regulatory Alignment

- SOX 404 (IT General Controls)
- COSO Framework (Control Activities)
- OCC Heightened Standards (Risk Management)

---

*Segregation of Duties Detector - FSI Agent Governance Framework*
