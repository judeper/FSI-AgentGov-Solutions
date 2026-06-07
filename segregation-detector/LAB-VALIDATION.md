# Lab Validation Report — Segregation of Duties Detector

> **Solution version:** v1.2.1 (with `[Unreleased]` BAP audience fix)
> **Validation date:** 2026-06-04
> **Validation type:** Static (no live tenant) — parse-validity + authoritative-source verification + documentation completeness
> **Validator:** Autonomous engineering pass (owl-mode)

---

## 1. Purpose and controls

The Segregation of Duties (SoD) Detector identifies users who hold incompatible role
combinations across three sources — Microsoft Entra ID directory roles, Power Platform
environment roles, and Dataverse security roles — and records Maker/Checker conflicts as
`fsi_sodviolation` rows. It supports compliance with:

- **Control 2.8** — Access Control and Segregation of Duties (primary)
- **Control 2.1** — Managed Environments (environment role context)
- **Control 2.3** — Change Management and Release Planning (pipeline gate)

Regulatory alignment documented by the solution: SOX Section 404 (IT General Controls),
COSO control activities, and OCC heightened standards. The shipped capability is
**detection + CI-gate exit code**; runtime pipeline blocking and real-time alerts are
documented roadmap items.

## 2. What was checked

| Area | Method | Result |
|------|--------|--------|
| PowerShell parse validity (`Invoke-SoDScan.ps1`, `Import-ConflictRules.ps1`, `SoDShared.ps1`) | `[Parser]::ParseFile` | 0 errors |
| Python compile (`create_sd_dataverse_schema.py`) | `python -m py_compile` | Pass |
| Dataverse column / entity-set names | Cross-checked scripts against `create_sd_dataverse_schema.py` and Microsoft Learn | Consistent |
| Microsoft Graph role-assignment query + permissions | Authoritative Graph v1.0 reference | Verified |
| Power Platform BAP role-assignment API host + token audience | Authoritative Power Platform admin docs | Host verified; **audience corrected** |
| Dataverse `systemuser` query columns | Authoritative SystemUser entity reference | Verified |
| Choice/option-set values (100000000+) | `SoDShared.ps1` vs `docs/conflict-rules.md` vs schema | Consistent (no 0/1/2 drift) |
| Regulatory language rules | grep for the FSI-prohibited compliance-absolute phrases (per `fsi-language-rules.instructions.md`, excl. CHANGELOG) | 0 hits |
| Managed-identity-first auth | Reviewed `Get-AccessToken` flow ordering | Compliant |

## 3. Authoritative sources cited

1. **List roleAssignmentScheduleInstances** — Microsoft Graph v1.0 —
   <https://learn.microsoft.com/en-us/graph/api/rbacapplication-list-roleassignmentscheduleinstances?view=graph-rest-1.0>
   Confirms: endpoint path; `principalId` / `roleDefinitionId` response properties;
   `$expand` / `$filter` / `$select` support; least-privileged application permission
   `RoleAssignmentSchedule.Read.Directory`; that active assignments include both PIM-activation and direct
   assignments.
2. **Power Platform programmability authentication (legacy)** —
   <https://learn.microsoft.com/en-us/power-platform/admin/programmability-authentication>
   Confirms: the BAP / Power Platform admin REST token audience is the **Power Apps Service**
   resource `https://service.powerapps.com/` (App ID `475226c6-020e-4fb2-8a90-7a972cbfc1d4`);
   documented scope string `https://service.powerapps.com//.default` (double slash is correct).
3. **Power Platform programmability authentication v2** —
   <https://learn.microsoft.com/en-us/power-platform/admin/programmability-authentication-v2>
   Confirms: the BAP admin host `https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/...`
   is the real request host; the newer Power Platform API uses audience `https://api.powerplatform.com/`.
4. **User (SystemUser) table/entity reference (Dataverse)** — Microsoft Learn
   Confirms columns `azureactivedirectoryobjectid`, `applicationid`, `isdisabled`,
   `domainname`, and the `systemuserroles_association` N:N relationship to `role`.

## 4. Gaps found and fixes applied

### 4.1 (Substantive) Power Platform BAP token audience — corrected

- **Gap:** `Invoke-SoDScan.ps1` acquired the BAP token with audience
  `https://api.bap.microsoft.com/.default`. `api.bap.microsoft.com` is the request **host**,
  not a documented Microsoft Entra resource identifier URI, so token acquisition can fail with
  `AADSTS500011` (resource principal not found). The v1.2.1 CHANGELOG marked this an "M2 false
  positive," asserting "the BAP API resource ID equals the API base URL" — that claim is **not
  supported** by authoritative documentation.
- **Authoritative basis:** Source 2 above shows the documented audience for the BAP admin REST
  surface is `https://service.powerapps.com/`, the same resource targeted by
  `New-PowerAppManagementApp` (already required in `docs/prerequisites.md`) and the
  `Microsoft.PowerApps.Administration.PowerShell` module.
- **Fix (surgical, low-regression):**
  - Added `Get-BapResource` to `SoDShared.ps1`. Commercial cloud now resolves the documented
    audience `https://service.powerapps.com/` (yielding the documented `…//.default` scope).
    The BAP **request host** is unchanged (`Get-BapApiBaseUrl`).
  - Added a `-BapResource` parameter and `FSI_BAP_RESOURCE` environment variable to override the
    audience if needed.
  - Documented in `docs/prerequisites.md`, `docs/troubleshooting.md` (new `AADSTS500011` row),
    README helper list, and CHANGELOG `[Unreleased]` (explicitly superseding the prior M2 note).

### 4.2 (Verified, no change) Items previously flagged or assumed

- **Graph PIM schedule-instance query** — verified correct against Source 1; permissions in
  `docs/prerequisites.md` (`RoleAssignmentSchedule.Read.Directory`, `RoleManagement.Read.Directory`,
  `Directory.Read.All`, `User.Read.All`) match the documented least-privileged + higher-privileged set.
- **Dataverse `systemusers` query** — `azureactivedirectoryobjectid`, `domainname`, `fullname`,
  `isdisabled`, `applicationid`, and `systemuserroles_association($select=name,roleid)` all verified.
- **Choice values** — `Category`, `RoleContext`, `Severity`, `ViolationStatus` etc. use
  `100000000+` consistently across `SoDShared.ps1`, `docs/conflict-rules.md`, and the schema
  generator. No 0/1/2-vs-100000000 drift. The README conflict-matrix "Context: 1/3/4" labels are
  human-readable context **codes** (explicitly defined in a README note), not Dataverse option-set
  values, so they are not a drift defect.
- **Disabled aspirational rules** — `DLP Policy Author/Approver` and `Environment Approver` remain
  `fsi_enabled = $false` because those names are not produced by the BAP role-assignment API; this
  is correct and documented.

## 5. Runtime-only caveats (cannot be verified statically without a tenant)

1. **BAP environment role-assignments endpoint** — `…/scopes/admin/environments/{id}/roleAssignments?api-version=2023-06-01`
   is the host/path the PowerApps Administration module uses, but the per-environment
   `roleAssignments` contract is not part of the publicly documented REST reference (which is the
   newer RBAC REST API). Response shape (`properties.principal.type`,
   `properties.roleDefinition.displayName`) is assumed from that module's behavior and must be
   confirmed against a live tenant.
2. **Corrected BAP audience** — the commercial fix to `https://service.powerapps.com/` is grounded
   in authoritative docs but must still be exercised end-to-end in a tenant.
3. **`New-PowerAppManagementApp` registration** — required for BAP queries to return data; cannot be
   exercised here.
4. **Token lifetime** — long scans in large tenants may exceed ~60 min; no in-script refresh
   (documented in README Known Limitations).
5. **Group-based / PIM-eligible / App-role assignments** — not evaluated (documented limitations).

## 6. Lab-readiness assessment

**Verdict: Lab-ready, with the BAP audience correction.**

The scripts parse cleanly, use authoritatively-verified Graph and Dataverse APIs with correct
property and column names, follow managed-identity-first auth, and carry accurate, language-rule-
compliant documentation. The one substantive defect found — an undocumented BAP token audience that
would likely fail token acquisition for the Power Platform role-enumeration branch — has been
corrected for commercial cloud and made overridable for all clouds, with zero change to the verified
Graph/Dataverse paths.

Before production (vs. lab) use, an operator should run an authenticated `-DryRun -Verbose` scan in a
real tenant to confirm: (a) the BAP audience succeeds and environment role data is returned, and (b)
`New-PowerAppManagementApp` registration is in place.

---

*Segregation of Duties Detector — Lab Validation Report*

## Second-Pass Command-Existence Re-Verification (2026-06-05)

An independent second-pass audit re-derived every invoked command, cmdlet, CLI verb, REST endpoint and api-version, Dataverse entity set / logical column / option-set, and module against Microsoft Learn, with a sharpened focus on confirming each surface exists and will run in a live lab. Microsoft Graph v1.0 roleManagement/directory roleAssignmentScheduleInstances (with $expand=principal) and roleDefinitions are GA; the Dataverse systemusers / systemuserroles_association N:N relationship and the fsi_conflictrules / sodviolations schema and option-sets, the BAP environments api-version 2023-06-01 with PowerApps Administration cmdlets, and the managed-identity / workload-identity token endpoints were all confirmed against Microsoft Learn. No corrections required; the BAP per-environment roleAssignments REST contract is caveated (runtime-confirmable, consistent with sibling calls).

