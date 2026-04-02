# Changelog

All notable changes to Inactivity Timeout Enforcement are documented here.

## [1.0.4] — April 2026

### Added
- Dataverse schema script with 3 tables, 2 option sets, and `--output-docs` support
- Environment variables script (4 variables for notifications, BAP API, scan frequency, Dataverse URL)
- Connection references script (Dataverse + Office 365 Outlook)
- PowerShell governance scripts: Invoke-TimeoutComplianceScan, Test-TimeoutCompliance, Get-ExpectedTimeoutPolicy, Export-TimeoutComplianceEvidence, Test-EvidenceIntegrity
- ISO 8601 duration parser (ConvertFrom-Iso8601Duration) for BAP API timeout values
- Auto-generated Dataverse schema documentation
- Python requirements.txt

## [1.0.3] — April 2026

### Changed

- Restructured solution to follow standard layout
- Moved documentation from root to `docs/` folder
- Renamed SOLUTION-DOCUMENTATION.md to docs/flow-configuration.md
- Removed exported Power Automate flow JSON from `src/` (per solution content policy — manual build instructions preserved in docs/flow-configuration.md)

## [1.0.2] — March 2026

### Fixed
- **CRITICAL:** Fix false-compliant classification when `inactivityTimeoutEnabled=true` but `inactivityTimeoutDuration` is null (BAP API data inconsistency). Added `Check_Duration_Is_Null` guard action; `Evaluate_Compliance` now classifies this indeterminate state as `Unknown` (status=2) instead of `Compliant` (status=0). This aligns with the existing pattern where API errors and missing policies produce Unknown status.
- **CRITICAL:** `Map_Compliance_Status_Value` now maps `Unknown` → 2 in addition to `Non-Compliant` → 1 and `Compliant` → 0. Previously, Unknown from `Evaluate_Compliance` would have mapped to 0 (Compliant).
- Add `runtimeConfiguration.paginationPolicy` (minimumItemCount: 100000) to `Load_Environment_Policies` to handle tenants with >5000 policy rows. Without pagination, results were silently truncated at the Dataverse default page size.
- Add `runtimeConfiguration.paginationPolicy` to `Query_NonCompliant_Records`, `Query_Unknown_Records`, and `Query_Compliant_Count` as defensive measure against large scan result sets.
- `Set_Compliance_Notes` now generates descriptive note for the null-duration Unknown case: "Inactivity timeout is enabled but duration is null — indeterminate state classified as Unknown"

### Documentation
- **SOLUTION-DOCUMENTATION:** Add null-duration to Unknown criteria in compliance status tables, appendix, and remediation guidance
- **SOLUTION-DOCUMENTATION:** Add Known Limitations section documenting BAP API version (2016-11-01), Condition_Has_Issues run-after gap, and List_Environments pagination limitation

## [1.0.1] — February 2026

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

## [1.0.0] — February 2026

### Added
- Daily compliance detection flow (`detect-inactivity-timeout-noncompliance.json`) for inactivity timeout settings
- Flow template migrated from FSI-AgentGov `src/` to FSI-AgentGov-Solutions
