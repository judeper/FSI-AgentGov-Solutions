# Changelog

All notable changes to the Audit Logging Compliance Automation solution will be documented in this file.

## [1.0.0] - 2026-02-13

### Added

- `AuditComplianceHelpers.psm1` — Shared PowerShell module with 6 functions
  - `Invoke-WithRetry` — Exponential backoff with jitter for 429/503/504
  - `Get-ManagedIdentityToken` — Azure Automation Managed Identity token acquisition
  - `Get-DataverseToken` — Dataverse-specific token with URL normalization
  - `Invoke-DataverseRequest` — Web API wrapper with OData headers and retry logic
  - `Write-DataverseComplianceRecord` — Upsert by environment ID with option set mapping
  - `Send-ComplianceNotification` — Graph sendMail via shared mailbox with attachments
- `AuditComplianceHelpers.psd1` — Module manifest with version 1.0.0
- `AuditComplianceHelpers.Tests.ps1` — Pester 5 unit tests for helper module
