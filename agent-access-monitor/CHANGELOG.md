# Changelog

All notable changes to the Agent Access Governance Monitor.

## [0.3.0] - 2025-07-17

### Added
- Start-AccessValidationRunbook.ps1 - Azure Automation runbook wrapper for non-interactive daily access validation with certificate-based auth and structured JSON output
- Invoke-AccessBaselineCapture.ps1 - Operator-initiated baseline capture writing environment access settings to Dataverse with active baseline management
- adaptive-card-access-alert.json - Teams adaptive card template for agent access violation and drift alerts with severity classification
- access-validation-flow.json - Power Automate cloud flow for daily scheduled validation, Dataverse persistence, and conditional Teams/email alerting
- FLOW_SETUP.md - Step-by-step guide for flow import, configuration, connection reference binding, and testing
- Save-AAMBaseline function in AAMClient.psm1 for writing access baseline records with active baseline rotation
- Get-AAMLastValidation function in AAMClient.psm1 for querying validation history (drift detection support)

### Changed
- AAMClient.psm1 now exports 8 functions (was 6): added Save-AAMBaseline and Get-AAMLastValidation
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
- Zone classification via ELM Dataverse lookup with naming convention fallback
- Severity classification (Critical/High/Warning/Info) per zone and violation type
- Regulatory context (FINRA 4511, SOX 404) in violation output
- Grace period filtering for newly provisioned environments
- Environment group support for group-level rule visibility

### Known Limitations
- Dataverse persistence not yet implemented (Phase 2)
- M365 Admin Center agent settings not queryable via API (portal-only)
