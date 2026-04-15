# Changelog

All notable changes to the Compliance Dashboard solution.

---

## [1.0.2] - 2026-04-15

### Fixed

- Removed stale ZIP import instructions from README and dataverse-schema.md (package was removed in v1.0.1)
- Updated Get-ExchangeComplianceData.ps1 version strings to v1.0.2

---

## [1.0.1] - 2026-07-15

### Removed

- **Exported Dataverse solution package** (`src/ComplianceDashboard/`) removed per repository content policy — solutions must not contain Power Platform runtime artifacts (flow JSON, connection references, environment variable exports)
- Updated `templates/README.md` to reference manual build instructions instead of `src/` import

### Note

All flow logic remains fully documented in [Flow Configuration](docs/flow-configuration.md). Administrators should build flows manually in Power Automate designer following that guide.

---

## [1.0.0] - 2026-02-04

### Added

- **Deployment Documentation:**
  - Comprehensive deployment checklist with manual validation steps
  - Power BI template creation specification (.pbit manual creation guide)
  - Known limitations section documenting what is not supported
  - Rollback and uninstall procedures
- **Power Platform Solution Package:**
  - Unmanaged solution package (ComplianceDashboard_1_0_0.zip)
  - Contains Dataverse schema and Power Automate flows
  - Connection reference configuration for Dataverse, Outlook, Teams
  - Environment variables for notification email and Teams webhook
- **Enhanced Sample Data:**
  - Full 62-control coverage with zone applicability
  - 90-day historical compliance score data for trend analysis
  - Realistic distributions (not uniform scores)
  - Sample exceptions with varied SLA statuses and severities
  - Export flag for sample data extraction

### Changed

- **Status:** Updated from beta (v1.0.0-beta) to production-ready (v1.0.0)
- **README:** Restructured with Known Limitations and Rollback sections
- **Quick Start:** Updated to reference actual solution package and deployment checklist
- **Documentation:** Added deployment-checklist.md and power-bi-template-spec.md to documentation table

### Fixed

- Sample data loader now generates realistic compliance score variations
- Clarified that RLS is not pre-configured (customer must implement)
- Documented manual .pbit creation requirement

---

## [1.0.0-beta] - February 2026

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
  - CD-EvidenceCollector - Design documented in flow-configuration.md (planned — no flow definition exists in the solution package yet)
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
