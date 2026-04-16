# Changelog

All notable changes to the Agent Access Governance Monitor.

## [1.0.2] - 2026-04-16

### Fixed

- Fixed control mapping in Test-AgentAccessCompliance.ps1: added primary control 3.8 (Copilot Hub) to .NOTES
- Fixed hardcoded version strings in Export-AgentAccessEvidence.ps1 (1.0.0 → 1.0.1)

## [1.0.1] - 2026-07-15

### Changed
- Moved adaptive card templates from `src/` to `templates/` (repository content policy alignment)
- Removed `src/access-validation-flow.json` flow export (see `docs/FLOW_SETUP.md` for manual build instructions)
- Removed `src/` directory — solutions provide documentation and scripts, not Power Platform runtime artifacts

## [1.0.0] - 2026-02-19

### Added — Phase 4: Evidence Export & Framework Integration

#### Evidence Export
- **Export-AgentAccessEvidence.ps1** — Main evidence export script
  - Zone-based filtering (All/1/2/3)
  - Date range support with -FromDate and -ToDate
  - Optional baseline inclusion with -IncludeBaselines
  - JSON output with -Depth 10 (prevents nested object truncation)
  - SHA-256 companion hash files in standard checksum format
  - Interactive and certificate-based authentication modes

- **Get-AAMValidationResults.ps1** (private) — Dataverse query helper
  - Queries fsi_accessvalidationhistory and fsi_accessviolations
  - OData filtering with automatic pagination support

- **Test-EvidenceIntegrity.ps1** — SHA-256 hash verification utility
  - Single file and batch verification modes
  - Cross-platform hash format compatibility (shasum, certutil)

#### Documentation
- **SCHEMA.md** — Dataverse schema reference (3 tables, option sets, environment variables)
- **EVIDENCE_EXPORT.md** — Evidence export operations guide with verification procedures
- **TROUBLESHOOTING.md** — Common issues and resolutions (6 categories)

#### Framework Integration
- Control 3.8 tip admonition linking to Agent Access Governance Monitor solution
- solutions-index.md catalog entry with regulatory alignment (FINRA 4511, SOX 404)

## [0.3.0] - 2026-02-17

### Added
- Start-AccessValidationRunbook.ps1 - Azure Automation runbook wrapper for non-interactive daily access validation with certificate-based auth and structured JSON output
- Invoke-AccessBaselineCapture.ps1 - Operator-initiated baseline capture writing environment access settings to Dataverse with active baseline management
- adaptive-card-access-alert.json - Teams adaptive card template for agent access violation and drift alerts with severity classification
- access-validation-flow.json - Power Automate cloud flow for daily scheduled validation, Dataverse persistence, and conditional Teams/email alerting
- FLOW_SETUP.md - Step-by-step guide for flow import, configuration, connection reference binding, and testing
- Save-AAMBaseline function in AAMClient.psm1 for writing access baseline records with active baseline rotation
- Get-AAMLastValidation function in AAMClient.psm1 for querying validation history (drift detection support)

### Changed
- AAMClient.psm1 now exports 9 functions (was 6): added Save-AAMBaseline, Get-AAMLastValidation, and Get-ValidToken
- Start-AccessValidationRunbook.ps1 enriches ZoneSummary to per-zone objects with Total/Compliant/Violations for flow and adaptive card consumption

## [0.2.0] - 2026-02-09

### Added
- Dataverse integration: `aam_client.py` for Dataverse Web API operations
- Schema deployment: `create_dataverse_schema.py` for 3 tables + shared option sets
- Environment variables: `create_environment_variables.py` for 6 operational parameters
- Connection references: `create_connection_references.py` for Dataverse, O365, Teams
- Deployment orchestrator: `deploy.py` with full/selective/dry-run support
- Test-AgentAccessCompliance.ps1: `-DataverseToken`, `-PersistResults` parameters
- Dataverse environment variable reads for operational parameters (grace period, sandbox inclusion)
- Validation result persistence to `fsi_accessvalidationhistory`
- Violation persistence to `fsi_accessviolations`
- Graceful fallback when Dataverse is unavailable

### Changed
- Write-AAMValidationHistory: added `-RunId` parameter, sets `fsi_name` and `fsi_run_id`
- Write-AAMViolation: added `-RunId` parameter, sets `fsi_name`

## [0.1.0] - 2026-02-09

### Added
- Initial solution scaffold
- Get-EnvironmentAccessSettings.ps1 — Query Power Platform environments for agent access settings
- Compare-ZoneCompliance.ps1 — Compare settings against zone-specific requirements
- Test-AgentAccessCompliance.ps1 — Orchestrator with dry-run mode and multiple output formats
- Zone classification via Dataverse baseline lookup (`fsi_accessbaselines`) with naming convention fallback
- Severity classification (Critical/High/Warning/Info) per zone and violation type
- Regulatory context (FINRA 4511, SOX 404) in violation output
- Grace period filtering for newly provisioned environments
- Environment group support for group-level rule visibility

### Known Limitations
- Dataverse persistence not yet implemented (Phase 2)
- M365 Admin Center agent settings not queryable via API (portal-only)
