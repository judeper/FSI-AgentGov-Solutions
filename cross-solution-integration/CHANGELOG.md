# Changelog — Cross-Solution Integration

All notable changes to this solution will be documented in this file.

## [1.0.2] — 2026-04-16

### Fixed

- Fixed 19 snake_case Dataverse column/table names in docs (fsi_overall_status → fsi_overallstatus, fsi_fileupload_validationhistories → fsi_fileuploadvalidationhistories, etc.)
- Fixed ACV solution directory mapping in IntegrationConfig.psm1: 'audit-configuration-validator' → 'audit-compliance-manager'

## [1.0.1] — 2026-02-11

### Changed

- **Migrated flow definitions to documentation** — Removed exported Power Automate flow JSON files (`flows/cd-solution-feed-collector.json`, `flows/elm-solution-initializer.json`) and replaced with manual build instructions in `docs/flow-configuration.md`, per the Solution Content Policy
- Updated README Quick Start steps to reference flow build instructions instead of flow deployment

### Removed

- `flows/` directory containing exported Power Automate flow JSON artifacts

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

- 6 Tier 2 solutions feeding 7 controls into Compliance Dashboard
- ELM provisioning completion cascading to ACV environment registration
- Unified evidence export with per-solution SHA-256 hash chain
