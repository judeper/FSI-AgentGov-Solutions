# Changelog

All notable changes to Inactivity Timeout Enforcement are documented here.

## [1.0.1] — February 2026

### Fixed
- **CRITICAL:** Wire `NotificationRecipients` and `ConcurrencyLimit` to read from Power Platform environment variables via `@environmentVariables()` — previously initialized as empty/hardcoded and never populated
- **CRITICAL:** Add recipient guard on both `Send_Alert_Email` and `Send_Flow_Error_Email` to prevent SendEmailV2 failure when `fsi_ITE_NotificationRecipients` is not configured
- Add exponential retry policy (3 retries, 30s interval, 5m max) to `List_Environments` and `Get_Privacy_Settings` HTTP actions for transient BAP Admin API failures
- Map zone integers to friendly names (1→Personal, 2→Team, 3→Enterprise) in compliance alert email table
- Remove vestigial `Initialize_DataverseUrl` variable — Dataverse operations use the connection reference
- **DELIVERY-CHECKLIST:** Fix inverted zone timeout recommendations (was Zone 1=60min/Zone 3=120min; corrected to Zone 1=optional ≤120min/Zone 3=≤60min)
- **SOLUTION-DOCUMENTATION:** Remove DataverseUrl references, document `@environmentVariables()` mechanism, add email guard explanation

## [1.0.0] — February 2026

### Added
- Daily compliance detection flow (`detect-inactivity-timeout-noncompliance.json`) for inactivity timeout settings
- Flow template migrated from FSI-AgentGov `src/` to FSI-AgentGov-Solutions
