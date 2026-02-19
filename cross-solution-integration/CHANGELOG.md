# Changelog — Cross-Solution Integration

All notable changes to this solution will be documented in this file.

## [1.0.0] — 2026-02-10

### Added

- **IntegrationConfig.psm1** — Shared constants module with solution-to-control mappings, status translation, and table configuration
- **Sync-SolutionAssessments.ps1** — PowerShell script to pull Tier 2 validation results into Compliance Dashboard assessments
- **Export-UnifiedComplianceEvidence.ps1** — Master evidence aggregation from all Tier 2 solutions with SHA-256 chain
- **Test-UnifiedEvidenceIntegrity.ps1** — Integrity verification for unified evidence packages
- **CD-SolutionFeedCollector** — Power Automate flow definition for daily automated dashboard feeds
- **ELM-SolutionInitializer** — Power Automate child flow for post-provisioning ACV auto-registration
- **SCHEMA_CONTRACT.md** — Canonical option set contract for cross-solution standardization
- **STATUS_MAPPING.md** — Per-solution status-to-dashboard translation reference
- Documentation suite: README, PREREQUISITES, CONFIGURATION, TROUBLESHOOTING, ELM_INTEGRATION, EVIDENCE_EXPORT, SCORE_CALCULATOR_UPDATE

### Integration Points

- 6 Tier 2 solutions feeding 9 controls into Compliance Dashboard
- ELM provisioning completion cascading to ACV environment registration
- Unified evidence export with per-solution SHA-256 hash chain
