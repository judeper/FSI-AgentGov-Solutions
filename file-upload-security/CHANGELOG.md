# Changelog

All notable changes to the File Upload Security Configurator will be documented in this file.

## [1.1.0] — 2026-04-17

AI Council technical-accuracy review (Claude Opus 4.7 + Goldeneye). Bug fixes, regulatory-language corrections, and runtime hardening; existing column writes are preserved (non-breaking).

### Fixed

- **Schema:** `create_dataverse_schema.py` now declares the required `fsi_name` primary string attribute inline when creating each table. Without this, Dataverse rejects entity creation with error 0x80048408 — the schema would never deploy successfully on a fresh tenant despite all helper functions writing `fsi_name`.
- **Environment-variable type map:** `create_environment_variables.py` `TYPE_MAP` corrected — `JSON` is option-set value `100000003` (previously incorrectly mapped to `100000002`, which is `Boolean`). Added missing `Boolean`, `Number`, `DataSource`, and `Secret` entries.
- **Severity option-set drift:** `Compare-FileUploadCompliance.ps1` summary counters now include `Info` and `Low` severities (previously only counted `Critical`/`High`/`Medium`/`Warning`, silently dropping any `Info`/`Low` violations from severity rollups). Mirrored in `Test-FileUploadCompliance.ps1`.
- **Severity 'None':** `Get-ExpectedFileUploadPolicy.ps1` initial severity changed from `'None'` to `'Info'` so the option-set conversion succeeds. `ConvertTo-SeverityOptionValue` (FUSClient.psm1) also accepts `'None'` as a legacy alias for `'Info'` to avoid silent `$null` writes.
- **Fail-closed orchestration:** `Get-AgentFileUploadSettings.ps1` now tracks per-environment auth/connectivity skips and throws when ALL targeted environments are skipped — previously the script returned an empty array, causing `Test-FileUploadCompliance.ps1` to record a green PASS evidence row with zero coverage. `Test-FileUploadCompliance.ps1` also throws on empty result sets unless the new `-AllowEmptyResultSet` switch is supplied for explicit opt-in.
- **statecode/statuscode pair:** baseline deactivation `PATCH` (`FUSClient.psm1`) now sends `statecode = 1` AND `statuscode = 2` together — Dataverse rejects partial state transitions silently in some configurations.
- **Az.Accounts compatibility:** `Connect-EnvironmentDataverse.ps1` now tries the Az.Accounts 5.x `-ResourceUri` parameter first and falls back to the deprecated `-ResourceUrl` only when running on Az.Accounts 4.x.

### Changed

- All entry-point scripts (`Test-FileUploadCompliance.ps1`, `Get-AgentFileUploadSettings.ps1`, `Compare-FileUploadCompliance.ps1`, `Export-FileUploadEvidence.ps1`, `Invoke-FileUploadBaselineCapture.ps1`, `Test-EvidenceIntegrity.ps1`) now declare `#Requires -Version 7.4` since they all depend on PowerShell 7.4 features (`ConvertFrom-SecureString -AsPlainText`, `Get-Date -AsUTC`, etc.).
- Regulatory references standardised to full citation form: `FINRA Rule 4511`, `FINRA Regulatory Notice 25-07`, `SEC Rule 17a-3` (was bare `FINRA 4511` / `FINRA 25-07` / `SEC 17a-3`).

### Removed

- **OCC 2011-12 / SR 11-7 misclaim:** removed from README control table, `Get-ExpectedFileUploadPolicy.ps1`, `templates/fileupload-baseline.json`, and `create_environment_variables.py`. OCC 2011-12 is the model-risk-management bulletin (covered by `model-risk-management-automation`); file-upload data-minimisation is covered by FFIEC IT Booklet — Information Security and the Interagency Guidelines (12 CFR 30 App. B).

## [1.0.2] — 2026-04-15

### Fixed

- Critical: Entity set name corrected from fsi_fileuploadvalidationhistorys to fsi_fileuploadvalidationhistories (was malformed plural)

## [1.0.1] — 2026-03-01

### Changed
- Moved `src/adaptive-card-fileupload-alert.json` to `templates/` per solution content policy
- Updated README, `flows/README.md`, and `docs/FLOW_SETUP.md` to reflect new paths

### Removed
- `src/fileupload-validation-flow.json` — Replaced by manual build instructions in `docs/FLOW_SETUP.md`
- `src/dataverse/` scaffolding (empty placeholder directories and READMEs) — Schema deployed via `scripts/create_dataverse_schema.py`
- `src/` directory entirely

## [1.0.0] — 2026-02-10

### Added

- Initial release of File Upload Security Configurator
- `Get-AgentFileUploadSettings.ps1` — Per-agent file upload enumeration across environments
- `Compare-FileUploadCompliance.ps1` — Zone-based compliance comparison with severity classification
- `Test-FileUploadCompliance.ps1` — End-to-end orchestrator with dry-run mode and multi-format output
- `FUSClient.psm1` — Dataverse client module for file upload metadata queries
- Content moderation cross-check for file-upload-enabled agents
- Zone policy model: Zone 1 (Allowed), Zone 2 (Restricted), Zone 3 (Disabled)
- Dataverse schema: fsi_fileuploadbaseline, fsi_fileuploadvalidationhistory, fsi_fileuploadviolation tables
- Power Automate daily validation flow with Teams adaptive card alerts
- Azure Automation runbook wrapper for unattended execution
- SHA-256 integrity-hashed evidence export for SEC 17a-4(f) support
- Baseline capture and drift detection
- Control 1.14 framework integration
- Complete documentation suite (PREREQUISITES, SCHEMA, EVIDENCE_EXPORT, FLOW_SETUP, TROUBLESHOOTING)
