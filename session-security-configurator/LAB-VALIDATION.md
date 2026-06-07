# Lab Validation Report — Session Security Configurator

**Solution:** session-security-configurator
**Version:** v1.3.0 (manifest unchanged; fixes recorded under CHANGELOG `[Unreleased]`)
**Primary controls:** 1.23 (Session Security and Step-Up Authentication), 1.11 (Conditional Access and MFA)
**Validation type:** Static — parse-validity, authoritative-source verification, and documentation completeness. No live tenant was used.
**Date:** 2026-06-04

## Purpose

The Session Security Configurator (SSC) validates Microsoft 365 / Entra ID session security configuration
against per-zone governance baselines (Zone 1 = 8 h, Zone 2 = 4 h, Zone 3 = 1 h sign-in frequency), deploys
zone step-up Conditional Access (CA) policies and authentication contexts in report-only mode, captures
baselines for drift detection, tracks Continuous Access Evaluation (CAE) posture, and exports SHA-256-hashed
compliance evidence to Dataverse. It supports compliance with FINRA 4511/3110, SEC 17a-3/4, GLBA 501(b),
and SOX 302/404 — it does not by itself satisfy any regulation.

## What was checked

- PowerShell parse-validity for all 14 `.ps1` scripts (`Parser::ParseFile`, zero errors).
- `py_compile` for all 5 Python scripts (all OK).
- Microsoft Graph Conditional Access **session control** schema: `signInFrequency`, `persistentBrowser`,
  `continuousAccessEvaluation`, and `grantControls.authenticationStrength` / `builtInControls`.
- Graph PowerShell cmdlet currency (`Get-/New-/Update-MgIdentityConditionalAccessPolicy`,
  `Get-MgPolicyAuthenticationStrengthPolicy`,
  `*-MgIdentityConditionalAccessAuthenticationContextClassReference`, beta `*-MgBetaIdentityConditionalAccessPolicy`).
- Required Graph permission scopes and the v1.0-vs-beta endpoint boundary for each property read.
- `Az.Accounts` `Get-AzAccessToken` output-type change and `MSAL.PS` deprecation status.
- Dataverse logical column names and option-set values against `scripts/create_dataverse_schema.py`.
- Zone→setting mapping and drift-detection comparison logic (`Compare-SessionBaseline.ps1`).
- FSI language rules across all Markdown (excluding CHANGELOG history).

## Authoritative sources cited

| Topic | Source URL |
|-------|-----------|
| `signInFrequencySessionControl` (`type` = days/hours; `frequencyInterval` = timeBased/everyTime) | https://learn.microsoft.com/graph/api/resources/signinfrequencysessioncontrol?view=graph-rest-1.0 |
| `persistentBrowserSessionControl` (`mode` = always/never) | https://learn.microsoft.com/graph/api/resources/persistentbrowsersessioncontrol?view=graph-rest-1.0 |
| `conditionalAccessSessionControls` (v1.0 — no `continuousAccessEvaluation`) | https://learn.microsoft.com/graph/api/resources/conditionalaccesssessioncontrols?view=graph-rest-1.0 |
| `continuousAccessEvaluationSessionControl` (beta-only; `mode` = strictEnforcement/disabled/…) | https://learn.microsoft.com/graph/api/resources/continuousaccessevaluationsessioncontrol?view=graph-rest-beta |
| Require reauthentication every time (sign-in frequency `everyTime`) | https://learn.microsoft.com/entra/identity/conditional-access/concept-session-lifetime#require-reauthentication-every-time |
| `Get-AzAccessToken` SecureString change (Az.Accounts 5.0.0 / Az 14.0.0) | https://learn.microsoft.com/powershell/azure/protect-secrets |

## Gaps found and fixes applied

### 1. (Bug) CAE detection read from the wrong Graph endpoint — fixed

`scripts/Get-CAEConfiguration.ps1` retrieved policies with `Get-MgIdentityConditionalAccessPolicy`
(**v1.0**) and then read `$sessionControls.ContinuousAccessEvaluation.Mode`. The `continuousAccessEvaluation`
session control is **not part of the v1.0 `conditionalAccessSessionControls` resource type** — it is exposed
only on the **beta** endpoint. As a result the property was always `$null`, so the script reported every
policy as CAE "default enabled" and `CAEExplicitlyDisabled` could never become `$true` — defeating the
script's stated purpose (identify policies with CAE explicitly disabled).

**Fix:** switched retrieval to `Get-MgBetaIdentityConditionalAccessPolicy -All` and updated `#Requires` to
`Microsoft.Graph.Beta.Identity.SignIns` (already a solution dependency, used by the Zone 3 risky-user policy
in `Deploy-StepUpPolicies.ps1`). Added inline + `.DESCRIPTION` notes explaining the v1.0/beta boundary, and
bumped the script-level version note to 1.2.1.

### 2. (Docs) Invalid `persistentBrowser` mode in help text — fixed

`scripts/private/Compare-SessionBaseline.ps1` `.PARAMETER Baseline` listed modes as
`("never", "always", "persistent")`. The Graph `persistentBrowserSessionControl.mode` enum is only
`always` / `never`; `"persistent"` does not exist. Removed it. (Runtime comparison is plain string equality,
so this was a documentation-only defect.)

### 3. (Docs) `Get-AzAccessToken` SecureString caveat added — fixed

`docs/prerequisites.md` recommended `Get-AzAccessToken -ResourceUrl` as a modern alternative to the
deprecated `MSAL.PS`, but did not mention that **Az.Accounts 5.0.0+** returns a `SecureString` by default.
The SSC scripts accept a plain-text bearer token (`-DataverseToken` / `-AccessToken`), so a manual
`SecureString` → plain-text conversion is now documented (per Microsoft's "Protect secrets in Azure
PowerShell" guidance, which states the token must be converted manually; there is no plain-text switch in 5.x).

### 4. (Accuracy/language) "enforces" → "validates" — fixed

`docs/prerequisites.md` stated "SSC enforces zone-specific session security controls." SSC validates
configuration and detects drift; the deployed Conditional Access policies perform enforcement. Changed to
"SSC validates …".

### 5. (Bug) Non-existent v1.0 cmdlet `Get-MgIdentityConditionalAccessAuthenticationStrengthPolicy` — fixed (second pass)

Four call sites invoked `Get-MgIdentityConditionalAccessAuthenticationStrengthPolicy`
(`Test-SessionCompliance.ps1` lines 327 and 500, `Invoke-BaselineCapture.ps1` line 248, and
`private/Compare-SessionBaseline.ps1` line 184). That cmdlet exists **only in the beta module**
(`Microsoft.Graph.Beta.Identity.SignIns`). In the v1.0 `Microsoft.Graph.Identity.SignIns` module
declared by each script's `#Requires`, it does not exist — the v1.0 `conditionalAccessRoot` resource
exposes only `authenticationContextClassReferences`, `namedLocations`, `policies`, and `templates`
(no `authenticationStrength` navigation), so no v1.0 cmdlet is generated for that path. A live run would
fail with "The term '…' is not recognized." The correct v1.0 cmdlet, mapping to
`/policies/authenticationStrengthPolicies`, is `Get-MgPolicyAuthenticationStrengthPolicy`, which accepts
the same `-AuthenticationStrengthPolicyId` parameter.

**Fix:** replaced all four calls with `Get-MgPolicyAuthenticationStrengthPolicy`. Sources:
`https://learn.microsoft.com/graph/api/resources/conditionalaccessroot?view=graph-rest-1.0`,
`https://learn.microsoft.com/powershell/module/microsoft.graph.identity.signins/get-mgpolicyauthenticationstrengthpolicy?view=graph-powershell-1.0`.

## Verified as correct (no change needed)

- **Session-control comparison** (`Compare-SessionBaseline.ps1`) normalizes `signInFrequency` of type
  `hours`/`minutes`/`days` to minutes. Graph only emits `days`/`hours`, so the `minutes` branch is harmless
  defensive code; all three zone baselines (8 h / 4 h / 1 h) are expressible in hours.
- **Zone 3 risky-user beta policy** (`Deploy-StepUpPolicies.ps1`) sets `signInFrequency` with
  `frequencyInterval = "everyTime"` and omits `value`/`type` — consistent with the beta schema (per the
  resource doc, `everyTime` is for risky users / risky sign-ins / Intune enrollment).
- **Graph cmdlets and scopes** are current: `Policy.ReadWrite.ConditionalAccess`, `Policy.Read.All`,
  `GroupMember.Read.All`, `RoleManagement.Read.Directory`.
- **Dataverse column logical names** in OData queries match `create_dataverse_schema.py`
  (e.g., `fsi_signinfrequencyminutes`, `fsi_requirecompliantdevice`, `fsi_capturedon`).
- **Option-set values** are internally consistent: `fsi_acv_zone` = 100000001-3,
  `fsi_ssc_validationtype` = 100000001-6, and `fsi_acv_severity` = 1-5 (a shared cross-solution set
  intentionally kept 1-based; documented in CHANGELOG 1.3.0). Read-side maps in
  `Export-SessionSecurityEvidence.ps1` match the schema.
- **No FSI language-rule violations** remain in Markdown.

## Runtime-only caveats (cannot be verified without a tenant)

- The CAE fix was verified against the published Graph schema and parse-checked. End-to-end behavior
  (beta cmdlet returning populated `ContinuousAccessEvaluation` for a policy that has it explicitly set)
  requires a live tenant with `Microsoft.Graph.Beta.Identity.SignIns` installed.
- Graph beta APIs are subject to change and are not formally supported for production by Microsoft; the
  CAE read and the Zone 3 risky-user policy both depend on beta surfaces. This is an inherent platform
  constraint, not a defect.
- `signInFrequency` `everyTime` only takes effect for the scenarios Microsoft documents (risky users,
  risky sign-ins, Intune enrollment); deploying it via a group-targeted policy does not make every sign-in
  reauthenticate outside those conditions. Validate the intended behavior in a tenant before enforcing.
- `continuousAccessEvaluationMode` also defines `strictLocation` (evolvable enum); the script labels any
  non-`disabled`/non-`strictEnforcement` value as "DefaultEnabled". This is a display nuance only.
- All deployment paths create CA policies in `enabledForReportingButNotEnforced` (report-only) mode; an
  operator must promote them to enforced after review. No live MFA/session impact occurs from deployment alone.

## Lab-readiness assessment

**Ready for lab use** with the fixes above. Scripts parse cleanly, Python compiles, API/permission/option-set
references are verified against authoritative Microsoft sources, and the one functional defect (CAE endpoint)
is corrected. Remaining items are runtime-only behaviors that require a tenant to exercise and are documented
as caveats rather than blockers.
