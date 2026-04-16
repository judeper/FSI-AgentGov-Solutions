# Changelog

All notable changes to the Audit Compliance Manager solution will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.2] - 2026-04-16

### Fixed

- Fixed 4 prohibited compliance language violations: "ensures" → hedging language in SOLUTION-DOCUMENTATION.md

## [1.0.1] - 2026-03-12

### Fixed

#### PowerShell (Issues #11, #13, #14, #18)
- Remove non-existent `Remove-PowerAppsAccount` calls in cleanup blocks (#11)
- Fix `RecordType` from `PowerAppsApp` to `PowerPlatformAdminActivity` for `Search-UnifiedAuditLog` (#11)
- Fix `Interactive.IsPresent` boolean-to-switch bug in `Test-MailboxAudit` and `Test-PurviewRetention` (#13)
- Update `Test-EvidenceIntegrity.ps1` from `#Requires -Version 5.1` to 7.2 (#13)
- Fix WhatIf mode to query Dataverse and show what would be remediated (#14)
- Add missing `$envNoChanges` counter increment in "Already Enabled" path (#14)
- Suppress `-Verbose` on `Invoke-RestMethod` in `Invoke-DataverseRequest` to prevent bearer token leak (#18)
- Add concurrency guard via `Get-AzAutomationJob` to prevent parallel runbook corruption (#18)
- Add `HtmlEncode` on environment names in HTML email to prevent XSS (#18)
- Add token refresh for long-running scans (50+ environments) to prevent 401 after 60m expiry (#18)

#### Python (Issues #17, #20)
- Add `MSCRM.SolutionUniqueName` header to all schema creation scripts (#17)
- Raise `RuntimeError` when `create_record()` cannot parse entity ID (#17)
- Add `--include-alca` flag to `deploy.py` for unified deployment (#17)
- Remove unused `azure-identity` and `azure-keyvault-secrets` from `requirements.txt` (#17)
- Add tenant-id GUID format validation in `deploy.py` (#17)
- Fix `acquire_token_silent` → `acquire_token_for_client` for client-credentials flow (#20)
- Add `https://` URL scheme validation on `environment_url` (#20)
- Require `--client-id` for all auth modes in `deploy.py` (#20)
- Allow GET requests in dry-run mode for accurate existence checks (#20)
- Add cleanup for orphaned environment variable definitions on value creation failure (#20)

#### Power Automate Templates (Issues #15, #19)
- Fix job ID extraction path from `?['properties']?['jobId']` to `?['name']` (#15)
- Wrap workflow steps in `Scope_Try/Scope_Catch` for comprehensive error handling (#15, #19)
- Add `P5D` timeout on approval action to prevent indefinite waits (#15)
- Add null check on `fsi_lastchecked` in `formatDateTime` expression (#19)
- Pass `NonCompliantEnvironmentIds` to runbook to eliminate TOCTOU race (#19)

#### Documentation (Issues #16, #21)
- Fix `src/` → `scripts/`/`templates/` path references in `SOLUTION-DOCUMENTATION.md` (#16)
- Add missing `--client-id` to Python command examples in `README.md` (#16)
- Add "Transition to Azure Automation" section bridging interactive and automated phases (#16)
- Create `docs/AUTHENTICATION.md` — Entra ID app registration, certificates, Managed Identity setup (#21)
- Fix `Get-AdminConfig` → `Get-AdminAuditLogConfig` in `testing-scenarios.md`

## [1.0.0] - 2026-02-15

### Added

- Consolidated Audit Configuration Validator (ACV) and Audit Logging Compliance Automation (ALCA) into a single solution
- See [docs/acv-CHANGELOG.md](./docs/acv-CHANGELOG.md) for ACV v1.0.0 history
- See [docs/alca-CHANGELOG.md](./docs/alca-CHANGELOG.md) for ALCA v1.0.0 history

### Changed

- Unified directory structure: `scripts/`, `docs/`, `templates/`
- Merged Python dependencies into single `requirements.txt`
- Combined documentation from both solutions
