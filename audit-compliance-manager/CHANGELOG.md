# Changelog

All notable changes to the Audit Compliance Manager solution will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [1.0.4] - 2026-05-17

### Changed

- Bumped solution version to v1.0.4 for the Microsoft Learn 2026-Q2 technical refresh.
- Updated Microsoft Purview Audit retention guidance to the current 180-day Audit Standard baseline for records generated on or after 2023-10-17, with Audit Premium/E5 and 10-year add-on licensing caveats.
- Clarified that Unified Audit Log enablement is verified in Exchange Online PowerShell, while Purview retention policies use Security & Compliance PowerShell.
- Refreshed authentication guidance to be managed-identity-first with certificate-based app-only fallback; client secrets are documented as legacy development-only.
- Clarified Power Platform tenant audit logging, Dataverse org/table/column audit settings, and optional audit-event search evidence.

## [1.0.3] - 2026-04-16

### Fixed

#### Code bugs
- **Set-SecurityRoles.ps1: separator output bug** — `Write-Host "=" * 70 -ForegroundColor Cyan` was printing the literal string `= * 70` because PowerShell parses the operands as positional arguments. Wrapped in parentheses: `Write-Host ("=" * 70)`.
- **Set-SecurityRoles.ps1: privilege grant/remove API** — Replaced unsupported `roleprivileges_association/$ref` POST/DELETE pattern with documented Dataverse bound action `Microsoft.Dynamics.CRM.AddPrivilegesRole` (with explicit `Depth = Global`) and unbound `RemovePrivilegeRole` action.
- **Connect-AuditServices.ps1: invalid Connect-IPPSSession parameter** — EXO V3 `Connect-IPPSSession` does not accept `-CertificateFilePath`. Switched to loading the X509Certificate2 from file and passing via `-Certificate`.
- **AuditComplianceHelpers.Tests.ps1: BeforeEach scoping** — `$originalEndpoint` / `$originalHeader` captured without `$script:` prefix in BeforeEach, so AfterEach restored `$null`. Added `$script:` prefix.

#### Detection vs remediation alignment
- **Enable-AuditLogging.ps1: tenant audit setting clarification** — Added comment block clarifying that `powerPlatform.governance.disableAuditLogging` is a Power Platform-specific tenant setting, not the M365 Unified Audit Log. UAL must be enabled separately by an Exchange Online Admin via `Set-AdminAuditLogConfig -UnifiedAuditLogIngestionEnabled $true`.

#### Authentication / connections
- **AUTHENTICATION.md: public-client contradiction** — Documented that the `--interactive` quick-start path requires "Allow public client flows = Yes" and a `http://localhost` redirect URI (scripts use `msal.PublicClientApplication`); recommended a separate confidential-client / managed-identity app for production.
- **AUTHENTICATION.md: missing Purview/IPPS permission** — Added section documenting required `Compliance.ManageAsApp` Office 365 Exchange Online permission and Compliance Administrator Entra role for `Connect-IPPSSession`.
- **FLOW_SETUP.md: un-authenticated HTTP GET** — Approval flow Step 1 told customers to do a raw HTTP GET against the Dataverse Web API with no auth. Replaced with the supported Microsoft Dataverse "List rows" connector and documented HTTP fallback configuration.
- **FLOW_SETUP.md: missing connection references** — Added explicit table listing Approvals, Teams, and Azure Automation as connections that must be created manually before flows can be built (the included `create_connection_references.py` covers only Dataverse + Office 365).

#### Regulatory accuracy
- **README.md: UAL retention reality check** — Added prominent caveat to Zone Requirements table explaining that the 730-day Zone 3 target is FSI Framework guidance; actual retention is bounded by license (E3 90/180d, E5 1y default, up to 10y with the audit log retention add-on).
- **README.md: SEC 17a-3/4 retention** — Replaced bare "Record preservation" with explicit class-by-class retention (3y comms, 6y books-and-records).
- **SOLUTION-DOCUMENTATION.md: 7-year SEC 17a-4 misclaim** — Split retention by record class: 3y SEC 17a-4(b)(4) communications, 6y SEC 17a-4(a) / FINRA 4511(b) books and records, 7y SOX/PCAOB AS 1215 audit work papers, GLBA 501(b) per firm policy.
- **SOLUTION-DOCUMENTATION.md: "captures all M365 and Power Platform activities"** — Softened to "captures supported audited events" with workload/license caveats.
- **evidence-export-guide.md: 730-day claim** — Softened "Unified Audit Log meets Zone 3 retention (730 days)" with license caveat.

#### Documentation drift
- **SOLUTION-DOCUMENTATION.md: wrong script for ALCA table** — Listed `create_dataverse_schema.py` as the ALCA table creator; that script creates the ACV tables. `create_audit_compliance_schema.py` creates the ALCA `fsi_auditenvironmentcompliance` table. Added separate row for each.
- **SOLUTION-DOCUMENTATION.md: version history** — Reflected actual v1.0.0 (initial), v1.0.1, v1.0.2 (token-cache fix), v1.0.3 (this council pass).
- **SOLUTION-DOCUMENTATION.md: runbook names** — Standardized `ALCA-Test-AuditLoggingCompliance` / `ALCA-Enable-AuditLogging` → `Test-AuditLoggingCompliance` / `Enable-AuditLogging` (matches script filenames and deployment-guide.md).
- **README.md: tenant-validation filename case** — Example referenced lowercase `tenant-validation-...json` but the script emits `Tenant-validation-...json` (PascalCase from `-Scope` parameter).
- **README.md: "Import Power Automate flow templates"** — Per content policy, the solution does not ship exported flow JSON. Replaced with manual-build instructions referencing FLOW_SETUP.md.
- **README.md: connection references coverage** — Added note that `create_connection_references.py` covers only Dataverse + Office 365.
- **README.md: documentation table** — Added missing entries for `docs/acv-CHANGELOG.md` and `docs/alca-CHANGELOG.md`.
- **DELIVERY-CHECKLIST.md: stale version + counts** — Email body said v1.0.1 (now v1.0.3); script counts corrected to actual (~22 PowerShell scripts + 6 helpers + module, 7 Python scripts, 2 adaptive cards); `AuditComplianceHelpers (1.0.0)` → `(1.0.2)`.
- **deployment-guide.md: missing ALCA schema step** — Added Phase 5.0 prerequisite step pointing to `create_audit_compliance_schema.py` and Phase 5.0.1 explaining that `scripts/private/` helpers must be packaged with the runbook (Azure Automation has no working dir).
- **deployment-guide.md: PowerApps module version** — `2.0.0` → `2.0.180+` to match `#Requires` statements.
- **evidence-export-guide.md: manifest schema drift** — Documented manifest fields did not match what `Export-AuditValidationEvidence.ps1` emits. Updated to actual fields (`exportedAt`, `fromDate`, `toDate`, `exportVersion`, `organizationUrl`).

#### Naming / placeholders
- **Canonical role names** across README, AUTHENTICATION.md, deployment-guide.md: "Exchange Administrator" → "Exchange Online Admin", "Compliance Administrator" → "Purview Compliance Admin", "Power Platform Administrator" prose → "Power Platform Admin" (Entra display names preserved where they identify the actual Entra role).
- **`contoso.com` → `example.com`** — Replaced placeholder email domain `@contoso.com` (real Microsoft demo domain) with RFC 2606 reserved `@example.com` across SOLUTION-DOCUMENTATION.md, testing-scenarios.md, AuditComplianceHelpers.psm1, AuditComplianceHelpers.Tests.ps1, and New-CanaryEvent.ps1.
- **AuditComplianceHelpers.psd1: stale ReleaseNotes** — Said "Initial release" while ModuleVersion was 1.0.2; updated to reference v1.0.2 token-cache fix.

### Notes

- AI Council technical-accuracy pass with 4 council members (Opus 4.7 code/schema, Goldeneye integration/deployability, GPT-5.4 regulatory accuracy, Opus 4.7 doc/code drift detective).
- Several lower-priority findings deferred for future minor releases: `deploy.py` dead validation branches, `AuditComplianceHelpers.psm1` URL-encoding of resource URIs, `Validators.Tests.ps1` `$matches` shadowing, `Test-AuditLoggingCompliance.ps1` `-TenantID` parameter accepting domain instead of GUID.

---

## [1.0.2] - 2026-04-15

### Fixed

- Critical: Dataverse token cache bug — $script:dvToken now initialized at first acquisition, preventing null-token writes for first 50 minutes
- Standardized role naming to "Exchange Administrator" across README and deployment guide (was inconsistently "Exchange Online Admin")
- Updated deployment-guide.md footer version to v1.0.2

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
