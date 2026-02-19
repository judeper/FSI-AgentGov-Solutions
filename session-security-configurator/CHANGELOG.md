# Session Security Configurator - Changelog

All notable changes to the Session Security Configurator solution are documented here.

## [1.0.0] - 2026-02-09

### Added

- Phase 1: PowerShell Core - Authentication context lifecycle, step-up policy deployment, zone validation
  - Private helper scripts: Connect-GraphSession, Test-BreakGlassExclusion, Compare-SessionBaseline
  - Authentication context definitions (c1-c5) for FSI-AgentGov zones
  - Step-up policy templates for Zone 1 (8h), Zone 2 (4h + passwordless), Zone 3 (1h + phishing-resistant)
  - Session baseline templates for zone compliance validation

- Phase 2: Dataverse Infrastructure - Schema deployment, validation history storage
  - Python deployment scripts: deploy.py, create_dataverse_schema.py, create_environment_variables.py
  - fsi_SessionBaseline table (user-owned configuration storage)
  - fsi_ValidationHistory table (organization-owned immutable audit log)
  - fsi_DriftViolation table (user-owned alert management)
  - Global option sets: fsi_acv_zone, fsi_acv_severity
  - Local option set: fsi_ssc_validationtype
  - Environment variables for zone thresholds

- Phase 3: Power Automate Integration - Daily validation flow, Teams alerting
  - session-validation-flow.json (Power Automate flow definition)
  - Start-SessionValidationRunbook.ps1 (Azure Automation runbook)
  - Teams adaptive card templates for drift alerts
  - Email distribution for compliance notifications
  - FLOW_SETUP.md documentation

- Phase 4: Evidence Export and Framework Integration
  - Export-SessionSecurityEvidence.ps1 — compliance evidence export with SHA-256 integrity hashing
  - Get-SSCValidationResults.ps1 — Dataverse validation history query helper
  - Test-EvidenceIntegrity.ps1 — SHA-256 hash verification utility
  - PREREQUISITES.md — comprehensive prerequisites documentation
  - DATAVERSE-SCHEMA.md — Dataverse table and option set reference
  - EVIDENCE-EXPORT-GUIDE.md — step-by-step export instructions
  - TROUBLESHOOTING.md — common issues and resolutions
  - Control 1.23 framework integration (tip admonition)
  - solutions-index.md catalog entry

### Status

Solution complete with all 4 phases delivered:
- 11 scripts + 5 private helpers (~5,559 lines of code)
- 3 Dataverse tables with immutable audit logging
- Power Automate flow for daily validation
- Comprehensive documentation suite
- Validated against FSI-AgentGov governance framework
