# Session Security Configurator - Changelog

All notable changes to the Session Security Configurator solution are documented here.

## [1.1.1] - 2026-05-04

### Fixed (Microsoft Learn refresh — 2026-Q2)

- Resolved authentication strength validation by looking up Microsoft Graph authentication strength policies by ID when Conditional Access policy payloads omit nested display names.
- Updated runbook and flow setup guidance to use current least-privilege Microsoft Graph permissions (`GroupMember.Read.All` and `RoleManagement.Read.Directory`) instead of broad directory read guidance.
- Corrected flow troubleshooting guidance to reference active baselines in `fsi_sessionbaselines` for drift comparison and aligned visible documentation status with this patch release.

## [1.1.0] - 2026-04-22

### Fixed (AI Council technical-accuracy review — Opus 4.7 + Goldeneye + GPT-5.4)

- **CRITICAL — Drift detection unwired from baseline:** `Start-SessionValidationRunbook.ps1` previously queried `fsi_validationhistories` (point-in-time runs) instead of `fsi_sessionbaselines` (active known-good). Drift comparison now reads the active SessionBaseline for the zone (`fsi_isactive eq true`) and treats any non-Passed current status as drift. Adds `Status='OK'`/`Status='Error'` discriminator so flows can distinguish infrastructure errors from real drift. (Opus #3 + Goldeneye #1 + GPT-5.4 #1)
- **CRITICAL — Baseline capture ignored zone:** `Invoke-BaselineCapture.ps1` selected the first CA policy with session controls across the entire tenant, so a Zone 3 baseline could be populated from an unrelated Zone 1 policy. Added `-PolicyPrefix` parameter (default `SSC`) and now filters policies by `"$PolicyPrefix-$Zone-*"` display-name pattern; throws if no matching policy exists. (Opus #3 + Goldeneye #1 + GPT-5.4 #2)
- **CRITICAL — Banner output corrupted:** Every `Write-Host "=" * 80 -ForegroundColor X` and `Write-Host "`n" + "=" * 80 -ForegroundColor X` line in `Deploy-AuthContexts.ps1` and `Deploy-StepUpPolicies.ps1` (22 instances) parsed as positional args and printed `= * 80` literal text. Wrapped expressions in parentheses. (Opus #1)
- **CRITICAL — Zone 2 step-up policy POST rejected by Graph:** `templates/step-up/zone2-step-up-policy.json` carried a non-schema property `_builtInControls_comment` inside `grantControls`; Microsoft Graph rejects unknown properties with HTTP 400 (`UnknownPropertyName`). Removed the comment property. (Opus #2)
- **HIGH — Missing Graph scopes caused silent fail-closed on PIM and break-glass checks:** `private/Connect-GraphSession.ps1` requested only `Policy.ReadWrite.ConditionalAccess, Policy.Read.All`; `Get-MgGroupMember` and PIM `roleManagement/*` calls returned 403 and surfaced as ambiguous "Error" status. Added `GroupMember.Read.All` and `RoleManagement.Read.Directory` to default scopes. Documented `Microsoft.Graph.Groups` and `Microsoft.Graph.Identity.Governance` module requirements in `docs/PREREQUISITES.md`. (Opus #4 + Goldeneye #3 + GPT-5.4 #5)
- **HIGH — Zone 1 MFA never validated:** Zone 1 step-up policy requires `builtInControls: ["mfa"]` but `Compare-SessionBaseline.ps1` never checked it; a tampered Zone 1 policy with MFA removed would still pass validation. Added Check 5 (`requireMfa`) and added `"requireMfa": true` to `templates/session-baselines/zone1-baseline.json`. (GPT-5.4 #4)
- **HIGH — Beta risky-user policy malformed:** `Deploy-StepUpPolicies.ps1` Beta API path set `frequencyInterval = "everyTime"` together with `value = 1, type = "hours"`; Microsoft Graph beta `signInFrequencySessionControl` rejects this combination. Removed `value`/`type` when `frequencyInterval = "everyTime"`. (Opus #7)
- **HIGH — Zone 1 Dataverse override caused false-fail:** `Test-SessionCompliance.ps1` overwrote `$baseline.authenticationStrength` with the literal string `"standard"` from the env-var default, then `Compare-SessionBaseline` reported `authenticationStrength Expected=standard Actual=not configured` because Zone 1 policies use `builtInControls=mfa`, not a custom authentication strength. The orchestrator now treats the sentinel `"standard"` as `$null`. (Opus #5)
- **HIGH — AuthenticationStrength comparison failed silently:** `Compare-SessionBaseline.ps1` compared against `$Policy.GrantControls.AuthenticationStrength.DisplayName`, which is not populated by `Get-MgIdentityConditionalAccessPolicy` by default — the validator returned a false `Failed` even when the policy was correct. Validator now resolves the strength policy by ID via `Get-MgIdentityConditionalAccessAuthenticationStrengthPolicy` when DisplayName is absent. (Opus #9)
- **HIGH — Get-DataverseThreshold expand used non-canonical navigation property:** Helper queried `$expand=environmentvariablevalues(...)`, which is not the Dataverse navigation property. Replaced with `environmentvariabledefinition_environmentvariablevalue($select=value)` and updated downstream property reads. (Goldeneye #2)
- **HIGH — UTC datetimes written to UserLocal columns:** `create_dataverse_schema.py` defined `fsi_capturedon`, `fsi_timestamp`, `fsi_detectedon`, `fsi_acknowledgedon` with `DateTimeBehavior=UserLocal` while writers (`Invoke-BaselineCapture.ps1` etc.) emit `Get-Date -AsUTC -Format "o"`. Changed all four columns to `TimeZoneIndependent` so values round-trip without timezone conversion. (Goldeneye #4)
- **MEDIUM — exportVersion stamp drift:** `Export-SessionSecurityEvidence.ps1` emitted `exportVersion=1.0.0` while documentation declared `1.0.1`. Both now updated to `1.0.2`. (Opus #8)
- **MEDIUM — StrictMode-unsafe `Get-MgContext.AccessToken` access:** `private/Get-DataverseThreshold.ps1` and `Export-SessionSecurityEvidence.ps1` touched `.AccessToken` on Graph SDK v2 contexts where the property does not exist; under `Set-StrictMode -Version Latest` this throws `PropertyNotFoundException` instead of falling through to MSAL.PS guidance. Added `PSObject.Properties.Name -contains 'AccessToken'` guard. (Opus #11)
- **MEDIUM — Decimal vs. Number env-var type confusion:** `create_environment_variables.py` declared `fsi_SSC_*SignInFrequencyMinutes` as `"Decimal"` and mapped to type code `100000001`, which Dataverse interprets as **Number** (integer), not Decimal. Renamed type marker to `"Number"` in script and `docs/DATAVERSE-SCHEMA.md`; integer storage was the intended behavior all along. (Opus #13)
- **LOW — Doc terminology "fails open":** `docs/FLOW_SETUP.md` described drift fail-safe path as "fails open", which inverts the security convention. Reworded to "fail-safe alerting / fail-closed for alerting". (Opus #15)

### Notes

- **Auth-context bindings are deployed but not yet validated by `Compare-SessionBaseline` (GPT-5.4 #3 — deferred).** Authentication context definitions c1-c5 are provisioned by `Deploy-AuthContexts.ps1` for downstream use (Information Protection labels, SharePoint per-site policies). Wiring `includeAuthenticationContextClassReferences` into both step-up policy templates and the validator is tracked as a roadmap item.
- **Conflict rule lookup column rename (Opus #10) deferred** — would break existing customer deployments; documented as a future v2 schema change.
- **Sovereign cloud authority handling (Goldeneye #5) deferred** — `ssc_client.py` hardcodes `login.microsoftonline.com`; tracked as a future enhancement for US Gov / 21Vianet customers.

## [1.0.1] - 2026-07-15

### Changed
- Moved adaptive card template from `src/` to `templates/` (repository content policy alignment)
- Removed `src/session-validation-flow.json` flow export (see `docs/FLOW_SETUP.md` for manual build instructions)
- Removed `src/` directory — solutions provide documentation and scripts, not Power Platform runtime artifacts

## [1.0.0] - 2026-02-09

### Added

- Phase 1: PowerShell Core - Authentication context lifecycle, step-up policy deployment, zone validation
  - Private helper scripts: Connect-GraphSession, Test-BreakGlassExclusion, Compare-SessionBaseline
  - Authentication context definitions (c1-c5) for FSI-AgentGov zones
  - Step-up policy templates for Zone 1 (8h), Zone 2 (4h + passwordless), Zone 3 (1h + phishing-resistant)
  - Session baseline templates for zone compliance validation

- Phase 2: Dataverse Infrastructure - Schema deployment, validation history storage
  - Python deployment scripts: deploy.py, create_dataverse_schema.py, create_environment_variables.py
  - fsi_SessionBaseline table (user-owned configuration storage)
  - fsi_ValidationHistory table (organization-owned immutable audit log)
  - fsi_DriftViolation table (user-owned alert management)
  - Global option sets: fsi_acv_zone, fsi_acv_severity
  - Global option set: fsi_ssc_validationtype
  - Environment variables for zone thresholds

- Phase 3: Power Automate Integration - Daily validation flow, Teams alerting
  - session-validation-flow.json (Power Automate flow definition)
  - Start-SessionValidationRunbook.ps1 (Azure Automation runbook)
  - Teams adaptive card templates for drift alerts
  - Email distribution for compliance notifications
  - FLOW_SETUP.md documentation

- Phase 4: Evidence Export and Framework Integration
  - Export-SessionSecurityEvidence.ps1 — compliance evidence export with SHA-256 integrity hashing
  - Get-SSCValidationResults.ps1 — Dataverse validation history query helper
  - Test-EvidenceIntegrity.ps1 — SHA-256 hash verification utility
  - PREREQUISITES.md — comprehensive prerequisites documentation
  - DATAVERSE-SCHEMA.md — Dataverse table and option set reference
  - EVIDENCE-EXPORT-GUIDE.md — step-by-step export instructions
  - TROUBLESHOOTING.md — common issues and resolutions
  - Control 1.23 framework integration (tip admonition)
  - solutions-index.md catalog entry

### Status

Solution complete with all 4 phases delivered:
- 11 scripts + 5 private helpers (~5,559 lines of code)
- 3 Dataverse tables with immutable audit logging
- Power Automate flow for daily validation
- Comprehensive documentation suite
- Validated against FSI-AgentGov governance framework
