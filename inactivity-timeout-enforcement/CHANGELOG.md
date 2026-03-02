# Changelog

All notable changes to Inactivity Timeout Enforcement are documented here.

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
