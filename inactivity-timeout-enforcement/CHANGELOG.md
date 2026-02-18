# Changelog

All notable changes to Inactivity Timeout Enforcement are documented here.

## [1.0.3] — February 2026

### Fixed
- Fix post-loop reporting queries (`Query_NonCompliant_Records`, `Query_Unknown_Records`, `Query_Compliant_Count`) skipped when any ForEach iteration catch handler fails — added `"Failed"` to `runAfter` conditions for partial-result reporting
- Fix `Determine_Error_Type` misclassifying non-HTTP failures as `ParseError` — now returns `ActionError` when Get_Privacy_Settings has no status code or returned 200 (downstream action failed), `HttpError` for unknown HTTP errors
- Fix `Create_Unknown_APIErrorRecord` setting `fsi_inactivitytimeoutenabled` to `false` — changed to `null` for consistency with Unknown (2) compliance status and `Create_Unknown_NoPolicyRecord`
- Fix false-negative compliance when `inactivityTimeoutEnabled` is `true` but `inactivityTimeoutDuration` is `null` — `Parse_Duration_Minutes` now returns -1 sentinel, `Evaluate_Compliance` treats as Non-Compliant
- Mitigate BAP Admin API pagination gap — added `$top=5000` to `List_Environments` URI to request larger result set
- Add partial-results note to `Scope_Catch` error email body so recipients know compliance data may already be in Dataverse

## [1.0.2] — February 2026

### Fixed
- **CRITICAL:** Fix `Build_Issue_Rows` zone-mapping crash when `fsi_zone` is null — `string(null)` replaced with `'Unassigned'` fallback for Unknown records without a policy
- **CRITICAL:** Fix false Compliant status when BAP API returns null `inactivityTimeoutEnabled` — added null checks in `Parse_Duration_Minutes`, `Evaluate_Compliance`, and `Set_Compliance_Notes`
- **CRITICAL (SOLUTION-DOCUMENTATION):** Fix inverted zone timeout recommendations throughout — Zone 3 (Enterprise) corrected to 60min (most restrictive), Zone 1 (Personal) to 120min (most lenient), per NIST 800-53 AC-11 risk-based guidance
- Remove phantom `fsi_ITE_ScanFrequencyHours` environment variable from SOLUTION-DOCUMENTATION.md and DELIVERY-CHECKLIST.md — variable does not exist in the flow (uses fixed daily recurrence trigger)
- Revert `ConcurrencyLimit` to hardcoded value (5); environment variable `fsi_ITE_ConcurrencyLimit` is informational only
- Fix `Apply_to_Each_Environment` description to reflect hardcoded concurrency

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
