# Lab Validation Report — Inactivity Timeout Enforcement (ITE)

> **Solution version:** v1.1.2 (changes staged under CHANGELOG `[Unreleased]`)
> **Validation date:** 2026-06-04
> **Validation type:** Static (no live tenant) — parse-validity + authoritative-source verification + documentation completeness
> **Primary controls:** 2.22 (Inactivity Timeout), 1.23 (Step-Up / Session Security), 3.7 (PPAC Security Posture), 3.8 (Copilot Hub / Governance Dashboard)

## 1. Purpose and scope

ITE detects whether Power Platform environments have an inactivity timeout
configured within zone-specific maximum durations (Zone 1 optional ≤120 min;
Zone 2 required ≤120 min; Zone 3 / Unknown required ≤60 min). It ships:

- A documented daily cloud-flow compliance scanner (`docs/flow-configuration.md`).
- Standalone PowerShell governance scripts under `scripts/governance/`.
- A Dataverse schema (`scripts/create_ite_dataverse_schema.py`) with compliance
  and error-log tables.

## 2. What was checked

| Area | Method |
|------|--------|
| Inactivity / session timeout feature + storage location | Microsoft Learn (Power Platform admin + Dataverse `organization` table reference) |
| Data type of the inactivity timeout value | Dataverse `organization` entity reference |
| Conditional Access session-control property names | Microsoft Graph v1.0 conditional access docs (cross-check of existing scope notes) |
| PowerShell parse-validity (5 `.ps1`) | `[Parser]::ParseFile` — 0 errors |
| Python compile-validity (3 `.py`) | `python -m py_compile` — 0 errors |
| Prohibited compliance language | grep across `*.md/*.ps1/*.py` (excl. CHANGELOG) — 0 hits |
| Dataverse logical-name / option-set integer usage | reviewed against `create_ite_dataverse_schema.py` and `.ralph-config.json` |
| Token audiences / Az.Accounts 5.x SecureString | reviewed scanner + evidence-export auth helpers |

## 3. Authoritative sources cited

1. **Security enhancements for user sessions and access management** (inactivity
   timeout is a per-environment customer-engagement System Setting; client-side;
   excludes Power Apps canvas apps) —
   <https://learn.microsoft.com/power-platform/admin/user-session-management>
2. **Manage privacy and security settings** (admin-center Privacy + Security:
   custom session timeout, inactivity timeout) —
   <https://learn.microsoft.com/power-platform/admin/settings-privacy-security>
3. **Organization table/entity reference (Microsoft Dataverse)** — the
   authoritative storage and **data types**: `inactivitytimeoutenabled`
   (Boolean), `inactivitytimeoutinmins` (**Integer minutes**),
   `inactivitytimeoutreminderinmins` (Integer); plus `sessiontimeoutenabled`,
   `sessiontimeoutinmins` —
   <https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/organization>
4. **Conditional Access session controls / sign-in frequency** (cross-check of
   the existing `signInFrequency`, `persistentBrowser`, `cloudAppSecurity`,
   `applicationEnforcedRestrictions`, `disableResilienceDefaults` references) —
   Microsoft Graph v1.0 `/identity/conditionalAccess/policies`.

## 4. Central finding (most significant gap)

**The inactivity timeout value is stored as an integer number of minutes on the
Dataverse `organization` table, not as an ISO 8601 duration returned by the BAP
Admin API `governanceConfiguration` endpoint.**

Before this validation, both the scanner and the flow docs read inactivity
timeout from:

```
GET https://api.bap.microsoft.com/.../environments/{env}/governanceConfiguration?api-version=2021-04-01
→ properties.settings.inactivityTimeoutEnabled (bool)
→ properties.settings.inactivityTimeoutDuration (ISO 8601, e.g. PT60M)
```

Adversarial assessment:

- The BAP `governanceConfiguration` resource is documented for **Managed
  Environment governance** settings (maker onboarding, sharing limits, solution
  checker, usage insights). I found **no authoritative Microsoft documentation**
  that inactivity timeout fields exist on this endpoint or that the value is
  exposed as an ISO 8601 duration anywhere in the platform.
- The **only** authoritative source for the inactivity timeout value is the
  Dataverse `organization` table, where it is an **Integer (`inactivitytimeoutinmins`)**
  in whole minutes — confirming the ISO 8601 parsing assumption was misplaced
  for the authoritative path.
- Consequence if unaddressed: in a real tenant the `governanceConfiguration`
  call would most likely omit these fields (or 404), so **every** environment
  would be classified `Unknown`, silently defeating the solution's purpose.

I cannot *disprove* the BAP shape without a live tenant, so it is retained as a
clearly-labelled fallback rather than deleted.

## 5. Fixes applied

### Scripts (`scripts/governance/Invoke-TimeoutComplianceScan.ps1`)

- **Authoritative primary read added.** Environment enumeration now captures each
  environment's Dataverse instance URL (`properties.linkedEnvironmentMetadata.instanceUrl`
  / `instanceApiUrl`). New helpers `Get-DataverseResourceToken` (per-resource
  token cache) and `Get-OrganizationInactivityTimeout` read
  `organizations?$select=inactivitytimeoutenabled,inactivitytimeoutinmins` and
  use the **integer minutes** directly (no ISO 8601 parsing).
- **BAP path demoted to fallback.** The `governanceConfiguration` call now runs
  only when the organization-table read is unavailable/fails, and is annotated
  in-code as unverified. Existing error-classification and Dataverse persistence
  behavior is unchanged. The change is additive and fully `try/catch`-guarded, so
  a failed organization read cleanly reverts to prior behavior.
- **Transparency.** Result objects now carry a `DataSource`
  (`DataverseOrganization` | `BapGovernanceConfiguration` | `None`) field.
- Header `.DESCRIPTION` updated to reflect the authoritative-source-first flow.

### Documentation

- `docs/flow-configuration.md` — documents the Dataverse `organization` table as
  the authoritative source (integer minutes), reframes the BAP shape as an
  unverified fallback, and notes the single-Dataverse-connection architectural
  constraint for a centralized flow. ISO 8601 appendix scoped to the fallback.
- `README.md` — Microsoft Learn scope note updated with the authoritative source
  and a pointer to this report.

### Dependencies

- No new dependencies required. `scripts/requirements.txt`
  (`msal`, `requests`, `azure-identity`) and `#Requires -Modules Az.Accounts >= 2.17.0`
  remain valid. The auth helpers tolerate Az.Accounts 5.x (where
  `Get-AzAccessToken` returns a `SecureString`) via `ConvertTo-PlainAccessToken`.

## 6. Items verified as already correct

- Dataverse logical-name usage and option-set **integer** values (zone
  100000001–100000003 / Unknown 100000000; status 100000000–100000002; error
  type 100000000–100000006) match `create_ite_dataverse_schema.py` and
  `.ralph-config.json`.
- BAP environment **enumeration** (`api-version=2016-11-01`) follows
  `@odata.nextLink` pagination.
- Managed-identity-first auth with a clearly-marked `# legacy: dev-only`
  client-secret fallback.
- Conditional Access session-control property names in the scope notes are
  current Microsoft Graph v1.0 names.
- Regulatory citations use name+section form (e.g., `FINRA Rule 4511(a)`,
  `SOX Section 404`, `GLBA Section 501(b)`).

## 7. Runtime-only caveats (require a live tenant to confirm)

1. **BAP token audience.** The scanner requests `https://service.powerapps.com/`
   for `api.bap.microsoft.com`. The BAP Admin API is not officially publicly
   documented; confirm the accepted audience in your tenant.
2. **`linkedEnvironmentMetadata.instanceUrl` field name** on the 2016-11-01
   enumeration response — the code reads `instanceUrl` then `instanceApiUrl`;
   confirm the property actually present for your environments.
3. **Per-environment Dataverse access.** The managed identity / service principal
   must be granted an application user with read access to the `organization`
   table in **each** environment it scans. Without this the scanner falls back to
   the unverified BAP path (likely `Unknown`).
4. **Centralized cloud flow** cannot read every environment's `organization`
   table through one Dataverse connection; the standalone scanner is the
   reference implementation for the authoritative read.

## 8. Lab-readiness assessment

**Conditionally lab-ready.** Static validation passes (all scripts parse/compile;
no language violations; schema/option-set names consistent). The core
data-acquisition correctness gap — reading inactivity timeout from an
undocumented BAP field instead of the authoritative Dataverse `organization`
integer-minutes column — has been corrected in the PowerShell scanner and
documented across the flow guide and README.

Before production use, a maintainer must validate items in §7 against a live
tenant (especially per-environment Dataverse application-user permissions and
the BAP token audience). The centralized cloud flow remains documentation-only
and should be reconciled to the authoritative source in a future release.

## Second-Pass Command-Existence Re-Verification (2026-06-05)

An independent second-pass audit re-derived every invoked command, cmdlet, CLI verb, REST endpoint and api-version, Dataverse entity set / logical column / option-set, and module against Microsoft Learn, with a sharpened focus on confirming each surface exists and will run in a live lab. The Organization inactivitytimeoutenabled / inactivitytimeoutinmins columns (the correct source), Conditional Access signInFrequency session controls, Az.Accounts authentication, and all fsi_ custom columns and option-sets were confirmed against Microsoft Learn; no corrections required. The BAP governanceConfiguration fallback is caveated.

