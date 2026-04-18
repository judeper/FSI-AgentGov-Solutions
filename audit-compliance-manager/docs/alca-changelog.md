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
- `Test-AuditLoggingCompliance.ps1` — Detection runbook (MI auth, environment scanning, compliance determination, CSV export, HTML email)
- `Enable-AuditLogging.ps1` — Remediation runbook (org-level + entity-level audit enablement, WhatIf, validation)
- `create_audit_compliance_schema.py` — Dataverse schema creation script
- `docs/deployment-guide.md` — Azure Automation deployment (phases 1–5, MI permissions, shared mailbox)
- `docs/scheduling-guide.md` — Runbook scheduling (weekly detection, optional daily, parameter reference)
- `docs/testing-scenarios.md` — 15 test scenarios + 10 troubleshooting issues
