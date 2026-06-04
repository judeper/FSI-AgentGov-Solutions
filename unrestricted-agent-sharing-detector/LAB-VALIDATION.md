# Lab Validation — Unrestricted Agent Sharing Detector (UASD)

> Static validation report. No live tenant was used. Validation = parse-validity +
> authoritative-source verification (Microsoft Learn) + script/doc coherence.
> Date: 2026-06-04 · Solution version: v2.0.1 (+ Unreleased fixes)

## Purpose & controls

UASD provides **detective and corrective** controls for overly permissive Copilot
Studio agent sharing. It reads each agent's sharing posture from the Dataverse
`bot` table, classifies violations against zone policy, optionally remediates by
restricting to approved security groups, and retains rollback evidence.

- **Control 1.1** — Restrict Agent Publishing by Authorization (primary)
- **Control 3.8** — Copilot Hub & Governance Dashboard (sharing visibility)
- Regulatory context referenced: FINRA Rule 4511(a), SEC Rule 17a-4, SOX
  Section 302/404, GLBA Section 501(b). Per repo language rules, the solution
  *supports compliance with* / *helps meet* these obligations; it does not
  guarantee them.

## What was checked

- All PowerShell scripts parse with zero errors
  (`[Parser]::ParseFile`), and `Invoke-ScriptAnalyzer` shows only pre-existing
  `PSAvoidUsingWriteHost` style warnings (consistent with the rest of the repo).
- All Python setup scripts compile (`python -m py_compile`, exit 0).
- The sharing-read path (`bot` table columns and option-set integers) was
  verified column-by-column against the Microsoft Learn `bot` entity reference.
- Auto-remediation and rollback (`Restore-AgentSharingFromEvidence.ps1`) were
  checked against the documented evidence contract in `docs/flow-configuration.md`.
- Token audiences and Az.Accounts behavior verified against Microsoft Learn.
- Dataverse logical column names and option-set values cross-checked against
  `create_uasd_dataverse_schema.py` / `docs/dataverse-schema.md`.
- Markdown scanned for prohibited compliance-language (zero hits outside
  CHANGELOG history).

## Authoritative sources cited

1. **Copilot (bot) table/entity reference (Microsoft Dataverse)** —
   <https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/bot>
   - `accesscontrolpolicy` (GlobalChoiceName `bot_accesscontrolpolicy`):
     `0 = Any`, `1 = Copilot readers`, `2 = Group membership`,
     `3 = Any (multi-tenant)`. **Matches** the detector's map and policy logic.
   - `authenticationmode` (`bot_authenticationmode`): `0 = Unspecified`,
     `1 = None`, `2 = Integrated`, `3 = Custom Azure Active Directory`,
     `4 = Generic OAuth2`. Detector treats `1 = None` as unauthenticated/public —
     **correct**.
   - `authenticationtrigger`: `0 = As Needed`, `1 = Always`. **Matches.**
   - `authorizedsecuritygroupids`: String, "comma-delimited list of **up to 20**
     Microsoft Entra ID group IDs … ignored if Access Control Policy is not Group
     membership", `MaxLength 739`. Remediation caps to the first 20 groups —
     **correct**.
2. **Protect secrets in Azure PowerShell** —
   <https://learn.microsoft.com/powershell/azure/protect-secrets>
   - "the default output type of `Get-AzAccessToken` changed from a plain text
     `String` to a `SecureString`, starting with **Az.Accounts 5.0.0** and
     **Az 14.0.0**." Basis for the SecureString fix below.
3. **`Get-AzAccessToken` reference** —
   <https://learn.microsoft.com/powershell/module/az.accounts/get-azaccesstoken>
   - Confirms `-ResourceUrl` and `-AsSecureString` are current parameters.
4. **Managed environment sharing limits / agent sharing rules** —
   <https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-sharing-limits#agent-sharing-rules>
   - Confirms native preventive sharing controls described in the README; UASD is
     positioned as the complementary detective/corrective layer.

## Gaps found & fixes applied

| # | Severity | Finding | Fix |
|---|----------|---------|-----|
| 1 | High (bug) | `Restore-AgentSharingFromEvidence.ps1` `Get-DataverseAccessToken` returned `$tokenResponse.Token` directly for the ManagedIdentity/Interactive paths. On Az.Accounts 5.0.0+ that is a `SecureString`, yielding a `Bearer System.Security.SecureString` header → 401. The detector, export, and import scripts already convert correctly; this script did not. | Request `-AsSecureString` explicitly and convert with `ConvertFrom-SecureString -AsPlainText` (handles both `SecureString` and legacy `String`). |
| 2 | High (script↔doc inconsistency) | The backout runbook only understood a legacy **principal-array** evidence shape applied via `GrantAccess`. The canonical UASD evidence (`fsi_evidencejson`) written by `Test-AgentSharingCompliance.ps1` and the detection flow (`docs/flow-configuration.md` step 8) records the prior **bot sharing columns** — so the runbook could not actually reverse a real remediation. | Added a canonical restore branch that PATCHes the `bot` record (`accesscontrolpolicy`, `authorizedsecuritygroupids`, and `authenticationmode`/`authenticationtrigger` when present) with `If-Match: *`. The legacy `GrantAccess` path is retained as a backward-compatible fallback. Docstring updated to document both shapes. |
| 3 | Low (prereq gap) | `Restore-AgentSharingFromEvidence.ps1` used `Get-AzAccessToken` without declaring the module dependency. | Added `#Requires -Modules Az.Accounts`, matching the other governance scripts. |

All three fixes are recorded in `CHANGELOG.md` under `[Unreleased]`.

### Verified-correct (no change needed)

- `accesscontrolpolicy` / `authenticationmode` / `authenticationtrigger` /
  `authorizedsecuritygroupids` usage and the 4-value access-policy map.
- Option-set integers (`fsi_UASD_violationtype` etc.) are 100000000-based and
  match `create_uasd_dataverse_schema.py`; the `fsi_acv_zone` vs
  `fsi_UASD_zoneclassification` divergence is documented and honored.
- Dataverse logical column names (lowercase, no inter-word underscores).
- Deprecated scripts (`Invoke-SharingAudit.ps1`, all `Deploy-*Flow.ps1`) fail
  closed with redirect messages — correct per the no-runtime-artifacts policy.
- Token audience uses the environment org URL as the Dataverse resource —
  correct for the Dataverse Web API.
- No prohibited compliance-language in docs.

## Runtime-only caveats (cannot be verified without a live tenant)

- **Bot PATCH for remediation/restore.** Whether `accesscontrolpolicy` /
  `authorizedsecuritygroupids` are updatable for a given published agent, and
  whether the service principal/managed identity holds the required Dataverse
  privileges, can only be confirmed against a real environment.
- **`authenticationmode = 0` (Unspecified).** The detector flags only `1 = None`
  as public. `0 = Unspecified` is not treated as a violation; confirm desired
  posture against tenant data before relying on this.
- **Per-environment restore target.** `Restore-AgentSharingFromEvidence.ps1`
  patches against the single `-DataverseUrl` provided; multi-environment evidence
  must be restored one environment at a time.
- **`GrantAccess` legacy fallback** operates on Dataverse record-level sharing
  (POA), a different concept from `accesscontrolpolicy` chat access. It exists
  only for legacy principal-array evidence and is not produced by current UASD.
- Managed-identity token acquisition, environment enumeration
  (`Get-AdminPowerAppEnvironment`), and Teams/Approvals flow wiring require a
  provisioned tenant.

## Lab-readiness assessment

**Lab-ready (static).** Scripts parse and compile, the authoritative sharing-read
and remediation model matches the current Microsoft Learn `bot` reference, and
the rollback runbook now consumes the evidence the solution actually produces and
authenticates correctly on Az.Accounts 5.x. Remaining items are inherently
runtime-only and require a provisioned Power Platform tenant to exercise.
