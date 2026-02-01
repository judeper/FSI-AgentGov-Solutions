# Changelog

All notable changes to the Compliance Dashboard solution.

---

## [1.0.0] - February 2026

### Added

- Initial release of Compliance Dashboard
- **Dataverse Schema:**
  - `fsi_controlmaster` - 62 framework controls with zone applicability and weights
  - `fsi_controlassessment` - Assessment records with status and scores
  - `fsi_compliancescore` - Daily compliance score snapshots
  - `fsi_complianceexception` - Exception tracking with SLA management
  - `fsi_complianceevidence` - Evidence collection with integrity hashing
- **Security Roles:**
  - CD Viewer - Read-only dashboard access
  - CD Assessor - Assessment entry and exception management
  - CD Admin - Full administrative access
- **Power Automate Flows:**
  - CD-ScoreCalculator - Daily compliance score calculation
  - CD-ExceptionMonitor - Hourly SLA status monitoring
  - CD-EvidenceCollector - Scheduled evidence collection
- **Power BI Dashboard:**
  - Executive Summary page
  - Pillar Overview page
  - Control Details page with drill-through
  - Exception Tracker page
  - Trend Analysis page
- **Documentation:**
  - Prerequisites and licensing requirements
  - Dataverse schema definitions
  - Flow configuration guide
  - Power BI setup and customization
  - DAX measure library
  - Troubleshooting guide
- **Sample Data:**
  - Control master JSON (62 controls)
  - Python script for loading sample data

### Regulatory Alignment

- SOX 404 (ICFR documentation)
- FINRA 3120 (supervisory control testing)
- OCC 2011-12 (model risk reporting)

---

*Compliance Dashboard - FSI Agent Governance Framework*
