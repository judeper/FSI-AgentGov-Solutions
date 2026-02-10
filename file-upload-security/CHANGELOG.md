# Changelog

All notable changes to the File Upload Security Configurator will be documented in this file.

## [1.0.0] — 2026-02-10

### Added

- Initial release of File Upload Security Configurator
- `Get-AgentFileUploadSettings.ps1` — Per-agent file upload enumeration across environments
- `Compare-FileUploadCompliance.ps1` — Zone-based compliance comparison with severity classification
- `Test-FileUploadCompliance.ps1` — End-to-end orchestrator with dry-run mode and multi-format output
- `FUSClient.psm1` — Dataverse client module for file upload metadata queries
- Content moderation cross-check for file-upload-enabled agents
- Zone policy model: Zone 1 (Allowed), Zone 2 (Restricted), Zone 3 (Disabled)
- Dataverse schema: fsi_fileupload_baseline, fsi_fileupload_validation, fsi_fileupload_violation tables
- Power Automate daily validation flow with Teams adaptive card alerts
- Azure Automation runbook wrapper for unattended execution
- SHA-256 integrity-hashed evidence export for SEC 17a-4(f) support
- Baseline capture and drift detection
- Control 1.14 framework integration
- Complete documentation suite (PREREQUISITES, SCHEMA, EVIDENCE_EXPORT, FLOW_SETUP, TROUBLESHOOTING)
