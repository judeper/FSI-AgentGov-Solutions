# Session Security Configurator - Changelog

All notable changes to the Session Security Configurator solution are documented here.

## [Unreleased]

### Fixed

- **Non-existent v1.0 cmdlet `Get-MgIdentityConditionalAccessAuthenticationStrengthPolicy`** (`scripts/Test-SessionCompliance.ps1`, `scripts/Invoke-BaselineCapture.ps1`, `scripts/private/Compare-SessionBaseline.ps1`): Four call sites invoked a cmdlet that exists only in the beta module (`Microsoft.Graph.Beta.Identity.SignIns`), not in the v1.0 `Microsoft.Graph.Identity.SignIns` module declared by each script's `#Requires`. The v1.0 [conditionalAccessRoot](https://learn.microsoft.com/graph/api/resources/conditionalaccessroot?view=graph-rest-1.0) exposes only `authenticationContextClassReferences`, `namedLocations`, `policies`, and `templates` (no `authenticationStrength` navigation), so a live run failed with a command-not-found error. Replaced with the correct v1.0 cmdlet [`Get-MgPolicyAuthenticationStrengthPolicy`](https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/get-mgpolicyauthenticationstrengthpolicy?view=graph-powershell-1.0) (same `-AuthenticationStrengthPolicyId` parameter; maps to `/policies/authenticationStrengthPolicies`).
- **Wave 6 P4b:** Empty catch blocks now log via `Write-Verbose` instead of silently swallowing errors. Output is unchanged unless caller passes `-Verbose`.
- **CAE detection read from beta endpoint** (`scripts/Get-CAEConfiguration.ps1`): Switched policy retrieval from `Get-MgIdentityConditionalAccessPolicy` (v1.0) to `Get-MgBetaIdentityConditionalAccessPolicy` (beta). The `continuousAccessEvaluation` session control is not part of the v1.0 `conditionalAccessSessionControls` resource type, so the v1.0 cmdlet never populated `SessionControls.ContinuousAccessEvaluation`; every policy was reported as CAE "default enabled" and `CAEExplicitlyDisabled` was always `$false`, defeating the script's purpose of identifying policies with CAE explicitly disabled. Updated `#Requires` to `Microsoft.Graph.Beta.Identity.SignIns` (already a solution dependency for the Zone 3 risky-user policy). Verified against the [continuousAccessEvaluationSessionControl (beta)](https://learn.microsoft.com/graph/api/resources/continuousaccessevaluationsessioncontrol?view=graph-rest-beta) and [conditionalAccessSessionControls (v1.0)](https://learn.microsoft.com/graph/api/resources/conditionalaccesssessioncontrols?view=graph-rest-1.0) resource types.

### Documentation

- **persistentBrowser mode values corrected** (`scripts/private/Compare-SessionBaseline.ps1`): The `.PARAMETER Baseline` help listed `persistentBrowser` modes as `("never", "always", "persistent")`. Per the [persistentBrowserSessionControl](https://learn.microsoft.com/graph/api/resources/persistentbrowsersessioncontrol?view=graph-rest-1.0) resource type, only `always` and `never` are valid; removed the non-existent `"persistent"` value.
- **`Get-AzAccessToken` SecureString caveat added** (`docs/prerequisites.md`): Documented that `Az.Accounts` 5.0.0+ returns the token as a `SecureString` by default, so a manual conversion is required before passing it to the SSC scripts' plain-text token parameters. Verified against [Protect secrets in Azure PowerShell](https://learn.microsoft.com/powershell/azure/security-features#transition-from-strings-to-securestrings).
- **Accuracy/language fix** (`docs/prerequisites.md`): Changed "SSC enforces zone-specific session security controls" to "SSC validates …" — SSC validates configuration and detects drift; Conditional Access policies perform enforcement.

## [1.3.0] - 2026-05-22

### Fixed

- **Critical — StrictMode-unsafe AccessToken access** (`scripts/private/Get-SSCValidationResults.ps1:160`): Added `PSObject.Properties.Name -contains 'AccessToken'` guard before reading `$context.AccessToken`. The v1.1.0 fix pass applied this guard to `Get-DataverseThreshold.ps1` and `Export-SessionSecurityEvidence.ps1` but missed this third helper. Under `Set-StrictMode -Version Latest` with Graph SDK v2 (where the `AccessToken` property is removed from the context object), the previous code threw `PropertyNotFoundException` instead of falling through gracefully. (council review C-01)

### Changed

- **Major — Auth-mode parity with shared Dataverse client** (`scripts/ssc_client.py`): Extended `SSCClient` to support `access_token` passthrough plus `managed-identity`, `workload-identity`, and `certificate` auth modes alongside the existing `interactive` and `client-secret` modes. Mirrors the constructor shape of `scripts/shared/dataverse_client.py`. Backward-compatible: existing callers using `interactive=True` or `client_id` + `client_secret` keep working unchanged. The CLI now exposes `--auth-mode`, `--access-token`, `--certificate-path`, and `--certificate-password` (also via `SSC_AUTH_MODE`, `SSC_ACCESS_TOKEN`, `SSC_CERTIFICATE_PATH`, `SSC_CERTIFICATE_PASSWORD` env vars). `azure-identity` is now an additional dependency required only for the new auth modes. (council review M-02)
- **Major — `fsi_ssc_validationtype` option-set migrated to 100000000+ range** (`scripts/create_dataverse_schema.py`, `scripts/Export-SessionSecurityEvidence.ps1`, `docs/dataverse-schema.md`, `scripts/private/Get-SSCValidationResults.ps1`): Migrated SessionControls/AuthStrength/PIMSettings/BreakGlass/ConflictAudit/Orchestrator values from `1-6` to `100000001-100000006` to align with the repository-wide Dataverse option-set convention (CLAUDE.md §8). The `$validationTypeMap` read-side map in `Export-SessionSecurityEvidence.ps1`, the documentation table in `docs/dataverse-schema.md`, and the `.NOTES` section in `Get-SSCValidationResults.ps1` were updated in lockstep. (council review M-01 — `fsi_ssc_validationtype` portion only)

### Minor

- **Minor — Validation-type option-set documentation refreshed** (`scripts/private/Get-SSCValidationResults.ps1:78-95`): Lockstep update of the `.NOTES` option-set table to reflect the new 100000000+ values for `fsi_ssc_validationtype`, and an inline note explaining why `fsi_acv_severity` remains 1-based (shared cross-solution option set; deferred for coordinated migration). (council review m-02)

### Migration notes (BREAKING DEPLOY)

The `fsi_ssc_validationtype` global option-set values changed. Tenants that already deployed v1.2.0 (or earlier) carry `fsi_validationtype` integers `1`-`6` in `fsi_ValidationHistory` rows. v1.3.0 schema scripts emit `100000001`-`100000006`. To migrate:

1. **Add the new option-set values without removing the old ones.** In the Power Platform maker portal, open the `fsi_ssc_validationtype` global option set and add six new options (`100000001` SessionControls, `100000002` AuthStrength, `100000003` PIMSettings, `100000004` BreakGlass, `100000005` ConflictAudit, `100000006` Orchestrator). Keep the existing `1`-`6` labels in place for now so historical rows remain readable.
2. **Re-key historical rows.** Run an XrmToolBox / FetchXML Builder bulk update (or a one-shot Python script using `SSCClient`) that maps `fsi_validationtype = 1` → `100000001`, `2` → `100000002`, …, `6` → `100000006` across every row in `fsi_validationhistories`. Validate with `SELECT fsi_validationtype, COUNT(*) FROM fsi_validationhistories GROUP BY fsi_validationtype` (or the OData equivalent) — only the new integers should be present after the migration.
3. **Update any external consumers** (custom Power BI reports, downstream flows, KQL queries) that filter or pivot on `fsi_validationtype` integers. The migration is silent for callers that go through `Export-SessionSecurityEvidence.ps1` — it already translates the integers to label strings.
4. **Remove the legacy `1`-`6` option-set values** after Step 2 succeeds on every environment. Optional but recommended to prevent new writers from re-introducing the old codes.

The `fsi_acv_severity` option set (`1`-`5`) is **not** migrated in this release. It is shared by 6+ solutions and is tracked for a coordinated cross-solution migration (Wave 5 / style-decisions §9).

## [1.2.0] - 2026-05-12

### Added

- **CAE configuration tracking** (`Get-CAEConfiguration.ps1`): Reads tenant Continuous Access Evaluation configuration from Microsoft Graph Conditional Access policies, tracks which policies have CAE enabled (default) vs. explicitly disabled, determines CAE eligibility for agent sessions per governance zone, and generates a CAE rollout posture report. Reference: [Continuous Access Evaluation](https://learn.microsoft.com/entra/identity/conditional-access/concept-continuous-access-evaluation).

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
