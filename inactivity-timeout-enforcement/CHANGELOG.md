# Changelog

All notable changes to Inactivity Timeout Enforcement are documented here.

## [Unreleased]

### Fixed
- **Major (lab-validation):** Inactivity timeout is now read from its authoritative source — the Dataverse `organization` table (`inactivitytimeoutenabled` Boolean / `inactivitytimeoutinmins` **Integer minutes**) — in `Invoke-TimeoutComplianceScan.ps1`. The previous source (BAP Admin API `governanceConfiguration` returning an ISO 8601 `inactivityTimeoutDuration`) is undocumented by Microsoft and is retained only as a clearly-labelled, `try/catch`-guarded fallback. Enumeration now captures each environment's Dataverse instance URL; new `Get-DataverseResourceToken` (per-resource token cache) and `Get-OrganizationInactivityTimeout` helpers perform the read. Result objects gain a `DataSource` field. Source: [Organization table/entity reference](https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/organization). See `LAB-VALIDATION.md`.

### Changed
- **Doc:** `docs/flow-configuration.md` and `README.md` now document the Dataverse `organization` table as the authoritative inactivity timeout source (integer minutes, no ISO 8601 parsing) and reframe the BAP `governanceConfiguration` shape as an unverified fallback, including the single-Dataverse-connection constraint for a centralized flow.

### Added
- `LAB-VALIDATION.md` — static lab-readiness validation report with authoritative source citations, the central BAP-vs-organization-table finding, fixes, and runtime-only caveats.

## [1.1.2] - 2026-05-23

### Fixed
- **Major**: Promoted the previously `[Unreleased]` v1.1.1 CHANGELOG content to a dated release section and bumped patch version so `manifest.yaml`, `README.md`, `docs/`, and governance script `.NOTES Version` strings stay synchronized. (council review MAJ-1)
- **Minor**: Added `errorType = $_.fsi_errortype` to `$errorsReadable` projection in `Export-TimeoutComplianceEvidence.ps1` so evidence packages retain the error classification (MissingPolicy/Unauthorized/Forbidden/NotFound/Throttled/ParseError/DataverseError). `scripts/governance/Export-TimeoutComplianceEvidence.ps1:431-442`. (council review MIN-3)
- **Minor**: Corrected `FINRA Rule 4511` -> `FINRA Rule 4511(a)` in `Get-ExpectedTimeoutPolicy.ps1` (Zone2, Zone3, Unknown regulatory context arrays) to match the established prose-citation convention in flow docs and CHANGELOG v1.1.0. `scripts/governance/Get-ExpectedTimeoutPolicy.ps1:87,99,113`. (council review MIN-2)

### Changed
- **Minor**: Removed vestigial `fsi_ITE_DataverseUrl` from `create_ite_environment_variables.py` (the flow has read the Dataverse URL from the connection reference since v1.0.1). A comment was retained in place of the entry to prevent re-introduction. `scripts/create_ite_environment_variables.py:39-48`. (council review MIN-1)
- **Minor**: Documented the intentional ISO 8601 duration parser scope (PT-prefixed H/M only, no D/S/W) in `ConvertFrom-Iso8601Duration` so future readers do not assume forward-compatibility was overlooked. `scripts/governance/Invoke-TimeoutComplianceScan.ps1:161-205`. (council review MIN-4)
- **Hardening**: Pinned `Az.Accounts` module requirement to `>= 2.17.0` via `#Requires -Modules` in `Invoke-TimeoutComplianceScan.ps1` and `Export-TimeoutComplianceEvidence.ps1` to prevent silent token-API regressions on older runners.
- **Hardening**: Replaced non-ASCII em dashes (U+2014) with ASCII `--` in governance script comments and verbose messages to keep PS 5.1 + PS 7 console rendering predictable.

### Deferred
- **Minor (MIN-5)**: Duplicate `ConvertTo-PlainAccessToken` / `Get-IteManagedIdentityToken` helpers in `Invoke-TimeoutComplianceScan.ps1` and `Export-TimeoutComplianceEvidence.ps1` -- extraction to a shared `.ps1` is a doc/structure reorg; tracked separately.
- **Minor (MIN-6)**: `Get-EnvironmentZone` naming-convention sandbox overlap warning is a cosmetic clarification; deferred.
- **Minor (MIN-7)**: Adding a script-version-alignment step to `delivery-checklist.md` is net-new test coverage; deferred.

## [1.1.1] - 2026-05-04

### Changed
- Refreshed Microsoft Learn 2026-Q2 platform guidance for Power Platform inactivity/session timeout boundaries, Microsoft 365 idle timeout, Conditional Access session controls, and Continuous Access Evaluation.
- Updated authentication guidance and setup scripts to prefer managed identity, workload identity federation, certificate, or externally acquired tokens before legacy client-secret development fallback.

### Fixed
- Corrected stale v1.0.5 version references in solution documentation and evidence metadata.
- Corrected flow documentation to use the deployed `fsi_acv_zone` global option set and Dataverse option-set integer values in validation and remediation examples.

## [1.1.0] — 2026-04-17

### Fixed
- **Critical:** `Invoke-TimeoutComplianceScan.ps1` was a function-only script — running it directly registered the function but never invoked it (silent green). Added a script-level `param()` block plus an explicit invocation guard so direct invocation now forwards arguments to the function. Dot-sourcing from `Test-TimeoutCompliance.ps1` continues to work unchanged.
- **Critical:** Error-log persistence omitted the required `fsi_errortype` column, causing every `fsi_inactivitytimeouterrorlogs` insert to fail with `0x80040217 ObjectDoesNotExist` once the schema was deployed. Errors are now classified (`Unauthorized`/`Forbidden`/`NotFound`/`Throttled`/`ParseError`/`DataverseError`) from the HTTP status code and mapped to the `fsi_ITE_errortype` global option set integer (100000000–100000006).
- **Critical:** BAP API field-name reconciliation — the scanner was reading `sessionTimeoutEnabled` / `sessionTimeoutInactivityDuration` while the documented contract uses `inactivityTimeoutEnabled` / `inactivityTimeoutDuration`. The scanner now accepts both shapes and the flow-configuration documentation now reflects the canonical `governanceConfiguration?api-version=2021-04-01` endpoint with the correct field names.
- **High:** Flow documentation Dataverse tables now use the deployed option-set integer values (`fsi_compliancestatus`: 100000000/100000001/100000002; `fsi_zone`: 100000001/100000002/100000003) instead of 0/1/2 and 1/2/3, which previously produced silent OData filter mismatches.
- **High:** `fsi_timeoutduration` documentation reconciled with the schema — split into `fsi_timeoutduration` (String(50), raw ISO 8601) and `fsi_timeoutdurationminutes` (Whole Number, parsed minutes). `fsi_errortype` is now correctly documented as a Choice / global option set, not String(50).
- **High:** Compliance and error-log table documentation now flags required columns (`fsi_compliancename`, `fsi_errorname`, `fsi_errortype`) and documents the auto-generated naming pattern `ITE-{env}-{runId}` used by the runbook.
- **High:** Bulk regulatory citation sweep across `flow-configuration.md`, `Get-ExpectedTimeoutPolicy.ps1`, `Export-TimeoutComplianceEvidence.ps1`, `Test-TimeoutCompliance.ps1`, and the `Invoke-TimeoutComplianceScan.ps1` `.NOTES` block — `FINRA 4511` → `FINRA Rule 4511(a)`, `SOX 404`/`302` → `SOX Section 404`/`302`, `GLBA 501(b)` → `GLBA Section 501(b)`, `SEC 17a-3`/`17a-4` → `SEC Rule 17a-3`/`17a-4`.
- **Medium:** `$ExcludeSandbox` no longer defaults to `$true` in `Invoke-TimeoutComplianceScan.ps1` and `Test-TimeoutCompliance.ps1` — sandbox environments were being silently dropped from compliance reporting. Default is now opt-in (`$false`).
- **Medium:** `Test-EvidenceIntegrity.ps1` now returns `$false` on missing-file / parse-failure paths instead of re-throwing, so callers can branch on integrity without wrapping the call in `try`/`catch`.
- **Medium:** Flow documentation now clarifies that `fsi_ITE_ConcurrencyLimit` is **not provisioned** by `create_ite_environment_variables.py` (consistent with prior CHANGELOG entries) and is not read by the flow.

### Changed
- Documented the implementation gap between the flow (which reads the `fsi_environmentpolicies` table) and the standalone PowerShell scanner (which derives zone from environment-name heuristics in `Get-ExpectedTimeoutPolicy.ps1`). A future release will reconcile the two paths.

## [1.0.5] — 2026-04-15

### Fixed

- Fixed zone filter to use option set integer values instead of string literals

## [1.0.4] — 2026-04-10

### Added
- Dataverse schema script with 3 tables, 2 option sets, and `--output-docs` support
- Environment variables script (4 variables for notifications, BAP API, scan frequency, Dataverse URL)
- Connection references script (Dataverse + Office 365 Outlook)
- PowerShell governance scripts: Invoke-TimeoutComplianceScan, Test-TimeoutCompliance, Get-ExpectedTimeoutPolicy, Export-TimeoutComplianceEvidence, Test-EvidenceIntegrity
- ISO 8601 duration parser (ConvertFrom-Iso8601Duration) for BAP API timeout values
- Auto-generated Dataverse schema documentation
- Python requirements.txt

## [1.0.3] — 2026-04-10

### Changed

- Restructured solution to follow standard layout
- Moved documentation from root to `docs/` folder
- Renamed SOLUTION-DOCUMENTATION.md to docs/flow-configuration.md
- Removed exported Power Automate flow JSON from `src/` (per solution content policy — manual build instructions preserved in docs/flow-configuration.md)

## [1.0.2] — 2026-03-15

### Fixed
- **CRITICAL:** Fix false-compliant classification when `inactivityTimeoutEnabled=true` but `inactivityTimeoutDuration` is null (BAP API data inconsistency). Added `Check_Duration_Is_Null` guard action; `Evaluate_Compliance` now classifies this indeterminate state as `Unknown` (status=2) instead of `Compliant` (status=0). This aligns with the existing pattern where API errors and missing policies produce Unknown status.
- **CRITICAL:** `Map_Compliance_Status_Value` now maps `Unknown` → 2 in addition to `Non-Compliant` → 1 and `Compliant` → 0. Previously, Unknown from `Evaluate_Compliance` would have mapped to 0 (Compliant).
- Add `runtimeConfiguration.paginationPolicy` (minimumItemCount: 100000) to `Load_Environment_Policies` to handle tenants with >5000 policy rows. Without pagination, results were silently truncated at the Dataverse default page size.
- Add `runtimeConfiguration.paginationPolicy` to `Query_NonCompliant_Records`, `Query_Unknown_Records`, and `Query_Compliant_Count` as defensive measure against large scan result sets.
- `Set_Compliance_Notes` now generates descriptive note for the null-duration Unknown case: "Inactivity timeout is enabled but duration is null — indeterminate state classified as Unknown"

### Documentation
- **SOLUTION-DOCUMENTATION:** Add null-duration to Unknown criteria in compliance status tables, appendix, and remediation guidance
- **SOLUTION-DOCUMENTATION:** Add Known Limitations section documenting BAP API version (2016-11-01), Condition_Has_Issues run-after gap, and List_Environments pagination limitation

## [1.0.1] — 2026-02-15

### Fixed
- **CRITICAL:** Wire `NotificationRecipients` and `ConcurrencyLimit` to read from Power Platform environment variables via `@environmentVariables()` — previously initialized as empty/hardcoded and never populated
- **CRITICAL:** Add recipient guard on both `Send_Alert_Email` and `Send_Flow_Error_Email` to prevent SendEmailV2 failure when `fsi_ITE_NotificationRecipients` is not configured
- **CRITICAL:** Fix null `inactivityTimeoutEnabled` false-compliant classification — when BAP API returns null, `equals(null, false)` evaluated to false, causing environments with unknown timeout status to be classified as Compliant. Changed to `not(equals(..., true))` so null and false are both Non-Compliant.
- Add exponential retry policy (3 retries, 30s interval, 5m max) to `List_Environments` and `Get_Privacy_Settings` HTTP actions for transient BAP Admin API failures
- Map zone integers to friendly names (1→Personal, 2→Team, 3→Enterprise) in compliance alert email table
- Remove vestigial `Initialize_DataverseUrl` variable — Dataverse operations use the connection reference
- Remove unused `Initialize_ConcurrencyLimit` variable — concurrency is hardcoded to 5 in `Apply_to_Each_Environment` `runtimeConfiguration`; eliminates silent failure path when `fsi_ITE_ConcurrencyLimit` contains non-numeric data
- HTML-escape environment display names in compliance alert email to prevent HTML injection via malicious display names
- **DELIVERY-CHECKLIST:** Fix inverted zone timeout recommendations (was Zone 1=60min/Zone 3=120min; corrected to Zone 1=optional ≤120min/Zone 3=≤60min)
- **DELIVERY-CHECKLIST:** Remove informational-only environment variables from deployment validation checklist
- **SOLUTION-DOCUMENTATION:** Remove DataverseUrl references, document `@environmentVariables()` mechanism, add email guard explanation
- **SOLUTION-DOCUMENTATION:** Fix Zone 2 timeout inconsistency (was 90 minutes, corrected to ≤120 minutes to match DELIVERY-CHECKLIST)
- **SOLUTION-DOCUMENTATION:** Correct HTTP 429 troubleshooting to reference flow JSON `runtimeConfiguration` instead of unused env var
- **README.md:** Fix deployment step to reference JSON file import instead of solution ZIP

## [1.0.0] — 2026-02-15

### Added
- Daily compliance detection flow (`detect-inactivity-timeout-noncompliance.json`) for inactivity timeout settings
- Flow template migrated from FSI-AgentGov `src/` to FSI-AgentGov-Solutions
