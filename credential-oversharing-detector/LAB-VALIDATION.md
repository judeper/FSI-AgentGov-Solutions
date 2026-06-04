# Lab Validation Report — Credential Oversharing Detector

> **Validation type:** Static (no live tenant). Parse-validity + authoritative-source verification + documentation completeness + column cross-check.
> **Validated:** 2026-06-04
> **Solution version:** v2.1.1 (schema addition staged under CHANGELOG `[Unreleased]`)
> **Branch:** `validation/credential-oversharing-detector`

## 1. Purpose and controls

Configuration-time credential scope governance for Copilot Studio agent connectors. Detects overprivileged connectors, excessive OAuth scopes, unauthorized service accounts, cross-environment credential sharing, shared-credential misuse, and stale credentials against zone-based policy; persists scan/violation evidence to Dataverse.

Primary framework controls: **1.14** (Data Minimization and Agent Scope Control), **1.4** (Advanced Connector Policies), **1.18** (Application-Level Authorization and RBAC). Supports compliance with FINRA Rule 4511(a) record-keeping, FINRA Rule 3110 supervision, GLBA Section 501(b) safeguards, SOX Sections 302/404, and OCC 2011-12 operational-risk guidance. No single control satisfies any regulation in isolation.

## 2. What was checked

| Check | Result |
|-------|--------|
| PowerShell parse (`Parser::ParseFile`) on all 9 `.ps1` | 0 errors |
| Python compile (`py_compile`) on all 3 `.py` | OK |
| Language-rule scan (prohibited compliance-overclaim phrases, excl. CHANGELOG) | 0 hits |
| Column references in every script cross-checked vs `create_cod_dataverse_schema.py` | 1 mismatch found and fixed (see §4) |
| Option-set values in docs/templates vs schema | Consistent (100000000+ ranges) |
| Token audiences per service | Correct (Dataverse `/.default`, PP admin endpoint, Graph for SP queries) |
| Auth pattern vs managed-identity-first standard | Conformant; client-secret path marked dev-only legacy |
| `.ralph-config.json` / manifest JSON validity | Valid |
| Regulatory citations | Accurate (SEC 17a-4 scoped to retention only, not access control) |

## 3. Authoritative sources cited

- Get-AzAccessToken (`-ResourceUrl`, secure-string default output) — https://learn.microsoft.com/powershell/module/az.accounts/get-azaccesstoken
- Conditional Access for workload identities (service-principal targeting, `servicePrincipalRiskLevels`) — https://learn.microsoft.com/entra/identity/conditional-access/workload-identity
- Power Platform programmability authentication (service-principal / management app) — https://learn.microsoft.com/power-platform/admin/programmability-authentication
- List federatedIdentityCredentials (Graph; keyed on Application object ID) — https://learn.microsoft.com/graph/api/application-list-federatedidentitycredentials
- Microsoft 365 connectors / Teams incoming webhook retirement — https://learn.microsoft.com/microsoftteams/platform/concepts/cards/cards-reference
- "Enforce safe sharing by detecting credential oversharing" (upstream preview dependency) — https://learn.microsoft.com/power-platform/release-plan/2026wave1/microsoft-copilot-studio/enforce-safe-sharing-detecting-credential-oversharing

Verified API/auth assertions: `Get-AzAccessToken -ResourceUrl ... -AsSecureString` is current (default output type is now `SecureString`, so the `ConvertFrom-SecureString -AsPlainText` unwrap is required) — matches usage in `Test-AgentAuthMethod.ps1`, `Compare-OAuthScopeBaseline.ps1`, and `Test-CredentialCompliance.ps1`. Workload-identity CA conditions (`clientApplications.includeServicePrincipals`, `servicePrincipalRiskLevels`) used by `Get-WorkloadIdentityCAPolicy.ps1` are valid CA policy surfaces.

## 4. Gaps found and fixes

### Fixed — column mismatch on the scope-baseline table (functional bug)

`Compare-OAuthScopeBaseline.ps1` issues `$select=...,fsi_approvedscopes,fsi_actualscopes,...` against the `fsi_agentconnectorscopes` entity set, but `fsi_ApprovedScopes` / `fsi_ActualScopes` were defined only on `fsi_credentialviolation` and `fsi_credentialexception`. A strict Dataverse environment returns **HTTP 400 ("Could not find a property named 'fsi_approvedscopes'")**, so the v2.1.0 name-level scope baseline comparison was non-functional. This was the deferred limitation tracked in the v2.1.1 CHANGELOG ("requires a schema column addition... tracked for the next minor bump").

**Fix:** Added `fsi_ApprovedScopes` and `fsi_ActualScopes` memo columns to the `fsi_AgentConnectorScope` table in `scripts/create_cod_dataverse_schema.py` (mirroring the existing `fsi_OAuthScopes` memo column), regenerated `docs/dataverse-schema.md` via `--output-docs`, and recorded the change under CHANGELOG `[Unreleased]` plus `.ralph-config.json`. The script now targets columns that exist on the queried entity. **Migration:** existing tenants must re-run `python scripts/create_cod_dataverse_schema.py` to add the two columns (additive, non-destructive).

### Verified — no action needed

- **All other column references** (scan, violation, exception, ELM `fsi_environments`/`fsi_zoneclassification`, primary keys `fsi_credentialscanid` / `fsi_agentconnectorscopeid`) match the schema source of truth.
- **Token audiences** are Dataverse-scoped for persistence (the v2.1.1 Graph-audience 401 fix is in place) and PP-admin-scoped for environment enumeration.
- **Option-set integer maps** in `Invoke-CredentialScan.ps1` and `docs/flow-configuration.md` use 100000000-based values consistent with the schema.
- **Language rules and regulatory citations** are clean across README and `docs/`.
- **Prerequisites** correctly scope Graph permissions as optional/future and document Power Platform admin + Dataverse System Administrator requirements, module versions, and network endpoints.

## 5. Runtime-only caveats (cannot be verified statically)

1. **Upstream preview dependency.** Connector OAuth-scope signal depends on Microsoft's "Enforce safe sharing by detecting credential oversharing" capability, listed for public preview (July 2026) / GA (September 2026). Availability and shape may change; validate in a non-production tenant. Without it, scans may report zero connectors (documented in troubleshooting).
2. **`bot.configuration` JSON is not a supported contract surface.** Detection parses agent configuration JSON; Microsoft schema changes can silently degrade detection (Tier 2 plans to move to supported `connectionreferences` + PP Admin V2 metadata).
3. **Scope baseline data must be populated.** The new `fsi_approvedscopes` / `fsi_actualscopes` columns are empty until a baseline capture process writes them; `Compare-OAuthScopeBaseline.ps1` will run cleanly but report nothing until rows carry scope data.
4. **No automatic 429/5xx retry/backoff** in the PowerShell scripts (documented); implement retry at the Power Automate / wrapper layer.
5. **Live auth paths** (service-principal client-credentials, `Add-PowerAppsAccount`, `Connect-AzAccount`, Graph SP enumeration) and Dataverse read/write round-trips require a tenant and were not exercised.

## 6. Lab-readiness assessment

**Lab-ready** for static deployment and dry-run review. The solution is mature (multiple prior council reviews) with clean parse/compile, consistent column naming, correct token audiences, compliant language, and accurate regulatory citations. The one functional defect found — the scope-baseline column mismatch that left `Compare-OAuthScopeBaseline.ps1` returning HTTP 400 — is now fixed at the schema level.

Before regulated production use, validate the upstream Microsoft preview feature in a non-production tenant and exercise the live auth and Dataverse round-trip paths listed in §5.
