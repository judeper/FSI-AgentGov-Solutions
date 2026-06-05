# Lab Validation Report — Conditional Access Automation

> **Solution version:** v2.0.2
> **Validation date:** 2026-06-04
> **Validation type:** Static (no live tenant) — parse-validity, authoritative-source verification, and documentation-completeness review.
> **Verdict:** **Lab-ready.** No code or documentation defects required repair. See "Final Assessment" for runtime-only caveats.

## Purpose and Controls

This solution automates deployment, compliance monitoring, and configuration-drift
detection of Microsoft Entra Conditional Access (CA) policies for Microsoft 365 AI
workloads (Copilot Studio, Agent Builder, M365 Copilot). It supports compliance with:

- **Control 1.11** — risk-based / Zero Trust access enforcement for AI applications
- **Control 1.23** — session controls (sign-in frequency, persistent browser)
- **Control 1.18** — access scope governance across governance zones (Zone 1/2/3)

It contributes to FINRA, SEC 17a-4, SOX 404 IT general controls, and GLBA 501(b) /
FTC Safeguards Rule (16 CFR Part 314) record-keeping objectives. No single control
satisfies any regulation in isolation; organizations should verify that their full
control set meets their specific obligations.

## What Was Checked

| Area | Method | Result |
|------|--------|--------|
| PowerShell parse-validity (all `.ps1` / `.psm1`) | `[Parser]::ParseFile` | 0 errors across all files |
| Python compile (all `.py`) | `python -m py_compile` | All 3 schema/config scripts compile |
| Graph CA API endpoint + version | Microsoft Learn | Matches v1.0; SDK cmdlets current |
| Required Graph permissions | Microsoft Learn | Match authoritative source |
| Required Entra roles | Microsoft Learn | Match authoritative source |
| Drift-detection property coverage | Code review vs. v1.0 schema | Covers current `conditionalAccessPolicy` shape |
| MFA compliance logic (auth-strength aware) | Code review | Correctly treats `authenticationStrength` as MFA-satisfying |
| Azure token acquisition pattern | Microsoft Learn | `Get-AzAccessToken -AsSecureString` — current/forward-compatible |
| Dataverse column logical-name usage | grep vs. schema script | Consistent; option-set values documented as `100000000+` |
| Regulatory language rules | grep (excl. CHANGELOG) | 0 prohibited phrases |
| Legacy product branding | grep | 0 (only the `AzureADMyOrg` API literal, which is required) |
| Module / package dependency declarations | review of `#Requires`, `.psd1`, `requirements.txt`, `prerequisites.md` | Complete and version-pinned |

## Authoritative Sources Cited

All assertions below were verified against official Microsoft documentation:

1. **Create conditionalAccessPolicy** (v1.0, `POST /identity/conditionalAccess/policies`) —
   <https://learn.microsoft.com/graph/api/conditionalaccessroot-post-policies?view=graph-rest-1.0>
2. **conditionalAccessPolicy resource** (request-body schema: `conditions`, `grantControls`, `sessionControls`) —
   <https://learn.microsoft.com/graph/api/resources/conditionalaccesspolicy?view=graph-rest-1.0>
3. **Update / Get / Delete conditionalAccessPolicy** (v1.0) —
   <https://learn.microsoft.com/graph/api/conditionalaccesspolicy-update?view=graph-rest-1.0>
4. **Conditional Access What-If `evaluate` API** (confirmed **preview / beta**, `POST /identity/conditionalAccess/evaluate`) —
   <https://learn.microsoft.com/en-us/graph/api/conditionalaccessroot-evaluate>
5. **Entra role permissions reference** (Conditional Access Administrator, Security Administrator) —
   <https://learn.microsoft.com/en-us/entra/identity/role-based-access-control/permissions-reference>
6. **Conditional Access grant controls** (`builtInControls`, `authenticationStrength`) —
   <https://learn.microsoft.com/entra/identity/conditional-access/concept-conditional-access-grant>
7. **Conditional Access session controls** (sign-in frequency, persistent browser) —
   <https://learn.microsoft.com/entra/identity/conditional-access/concept-conditional-access-session>
8. **Protect secrets in Azure PowerShell** (`Get-AzAccessToken` SecureString handling) —
   <https://learn.microsoft.com/en-us/powershell/azure/faq#how-can-i-convert-a-securestring-to-plain-text-in-powershell->

### Verified facts

- **Endpoint / version:** Policy create, read, update, and delete operate against the
  **v1.0** `/identity/conditionalAccess/policies` resource. The scripts use the current
  SDK cmdlets `Get-/New-/Update-/Remove-MgIdentityConditionalAccessPolicy`
  (module `Microsoft.Graph.Identity.SignIns`, pinned `>= 2.0.0`).
- **Permissions:** `Policy.Read.All` and `Policy.ReadWrite.ConditionalAccess` are the
  correct scopes for read and write respectively; `Application.Read.All` is correctly
  used for app-registration lookups. These match `prerequisites.md`, `troubleshooting.md`,
  and `Connect-GraphSession.ps1` defaults.
- **Roles:** Conditional Access Administrator and Security Administrator are the
  authoritative least-privilege roles for CA policy management; the README and
  `manifest.yaml` reflect this.
- **What-If `evaluate` endpoint:** correctly documented in `docs/deployment-guide.md`
  as a **preview / beta** API (`/beta/identity/conditionalAccess/evaluate`), consistent
  with `.ralph-config.json` domain fact #5 and the authoritative source.
- **Token handling:** `Export-CAAComplianceEvidence.ps1` uses
  `Get-AzAccessToken -ResourceUrl ... -AsSecureString` and extracts via
  `System.Net.NetworkCredential`, which is correct for Az.Accounts 3.x and forward-
  compatible with the 5.x line where SecureString output is the default.

## Gaps and Fixes

**No script, documentation, or dependency defects were identified that required repair.**
This solution has been through prior council reviews (v1.2.2, v2.0.0–v2.0.2) that already
corrected the issues commonly found across the repository. Specifically, the following were
verified as already-correct during this pass (no change applied):

- **Drift detection** (`Get-PolicyBaseline.ps1`) normalizes the full current v1.0
  `conditionalAccessPolicy` property surface — including `authenticationStrength`,
  `insiderRiskLevels`, `servicePrincipalRiskLevels`, `authenticationFlows`,
  device filters, named locations, and `disableResilienceDefaults` (CAE) — so it compares
  the right properties.
- **MFA compliance** (`Test-PolicyCompliance.ps1`) treats an MFA-satisfying
  `authenticationStrength` as equivalent to `builtInControls: ["mfa"]`, matching Microsoft's
  grant-control model, and does not raise a false violation when strength-based MFA is used.
- **Template hygiene** (`Deploy-CAPolicies.ps1`) strips the non-Graph `_metadata` block
  before any API call, validates that all `<placeholder>` tokens were substituted, and
  refuses to deploy when break-glass exclusions are missing.
- **Dataverse logical names** are used consistently in all OData consumers
  (`fsi_overallseverity`, `fsi_totalpolicies`, etc.), and option-set values are documented
  in the Dataverse-issued `100000000+` range rather than `0/1/2` placeholders.
- **Language and branding:** no prohibited regulatory-assurance phrases outside CHANGELOG
  history; no legacy directory-service branding except the required `AzureADMyOrg` API literal.

## Runtime-Only Caveats

The following cannot be validated statically and require a live tenant to confirm:

1. **Tenant app IDs.** `config.sample.json` placeholders for Copilot Studio / Agent Builder /
   M365 Copilot application IDs must be replaced with the IDs present in the target tenant.
   First-party app IDs drift over time; verify in the Entra portal before deployment.
2. **Licensing.** Risk-based templates (`signInRiskLevels` / `userRiskLevels`, and the
   optional `CA-RiskBased-Zone3-Block`) require **Entra ID P2**. Basic policies require P1.
3. **Authentication strength IDs.** If a tenant adopts phishing-resistant strength for Zone 3,
   the current strength ID must be retrieved from Graph at authoring time, and the policy must
   not combine `mfa` and `authenticationStrength` (per `docs/policy-templates.md`).
4. **What-If `evaluate` API.** Preview-only; behavior and request shape may change before GA.
   Treat any automation built on it as non-production until the API reaches v1.0.
5. **Managed identity.** Unattended runbook auth (`Start-CAAValidationRunbook.ps1`) requires a
   system- or user-assigned managed identity granted the application permissions above, or a
   certificate-based app registration where MI is unavailable.
6. **Report-only first.** All nine baseline templates ship as
   `enabledForReportingButNotEnforced`. Validate with the What-If tool and CA insights before
   enforcement to avoid lockout.

## Final Assessment

The Conditional Access Automation solution is **lab-ready** for static-validation purposes.
All PowerShell parses cleanly, all Python compiles, every Graph API endpoint / permission /
role assertion matches authoritative Microsoft documentation, the drift and compliance logic
reflect the current v1.0 CA schema, and dependency declarations are complete and version-pinned.
The remaining items are environment-specific runtime configuration (app IDs, licensing, managed
identity, strength IDs) that are inherent to any CA deployment and are appropriately documented
in the solution's prerequisites and deployment guides.

## Second-Pass Command-Existence Re-Verification (2026-06-05)

An independent second-pass audit re-derived every invoked command, cmdlet, CLI verb, REST endpoint and api-version, Dataverse entity set / logical column / option-set, and module against Microsoft Learn, with a sharpened focus on confirming each surface exists and will run in a live lab. Microsoft Graph Conditional Access cmdlets (New/Get/Update-MgIdentityConditionalAccessPolicy), the conditionalAccessPolicy JSON schema, the beta /identity/conditionalAccess/evaluate endpoint, Microsoft Graph Applications cmdlets, and Dataverse entity sets and columns were all confirmed against Microsoft Learn; no corrections required.

