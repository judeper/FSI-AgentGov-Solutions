# Lab Validation — Cross-Solution Integration

> **Solution:** cross-solution-integration · **Version:** v2.0.3
> **Validation date:** 2026-06-04 · **Mode:** Static (no live tenant)
> **Validator note:** Static validation only — parse-validity, authoritative-source
> verification, and cross-solution schema cross-referencing. Items that can only be
> confirmed against a live Dataverse environment are called out as runtime caveats.

## Purpose & controls

Integration/glue layer that wires the six Tier 2 governance solutions into the
Compliance Dashboard and the Environment Lifecycle Management (ELM) provisioning
workflow. Primary controls: **1.7, 1.23, 1.11, 3.8, 1.8, 1.14, 1.18**.

Because this is an integration solution, the dominant risk is **drift between this
solution's cross-references and the real Dataverse schemas of the six sibling
solutions it reads**. Validation focused there.

## What was checked

| Area | Method | Result |
|------|--------|--------|
| PowerShell parse-validity (5 `.ps1` + `.psd1`) | `[Parser]::ParseFile` | ✅ 0 errors |
| Python compile (`create_csi_alternate_keys.py`, tests) | `py_compile` | ✅ pass |
| Unit tests (`tests/`) | `pytest -q` | ✅ 8 passed |
| Tier 2 history entity-set names | cross-ref sibling `create_*_dataverse_schema.py` | ✅ verified |
| Tier 2 history column references (Sync + Export `$select`) | cross-ref schema scripts | ✅ verified |
| ACV `fsi_environmentregistry` references (Register script) | cross-ref ACV schema | ✅ verified |
| Compliance Dashboard tables + option-set values | cross-ref CD schema | ✅ verified |
| Auth model (managed-identity-first, token audience) | code read + MS Learn | ✅ verified |
| Language-rule compliance (live docs) | grep prohibited phrases | ✅ clean (only CHANGELOG history) |

### Cross-solution schema verification (authoritative = each sibling's schema script)

Entity-set names — confirmed each against the sibling `create_*_dataverse_schema.py`
(default Dataverse pluralization vs. explicit `EntitySetName`):

| Sol. | Entity set used | Schema source | Verdict |
|------|-----------------|---------------|---------|
| ACV | `fsi_auditvalidationhistories` (auto-plural) | `audit-compliance-manager/scripts/create_dataverse_schema.py` (`fsi_AuditValidationHistory`, no `EntitySetName`) | ✅ |
| SSC | `fsi_validationhistories` (auto-plural) | `session-security-configurator/.../create_dataverse_schema.py` (`fsi_ValidationHistory`) | ✅ |
| AAM | `fsi_accessvalidationhistory` (**explicit singular**) | `agent-access-monitor/.../create_dataverse_schema.py:143` (`EntitySetName`) | ✅ |
| CMM | `fsi_moderationvalidationhistory` (**explicit singular**) | `content-moderation-monitor/.../create_dataverse_schema.py:296` (`entity_set_name`) | ✅ |
| FUS | `fsi_fileuploadvalidationhistories` (auto-plural) | `file-upload-security/.../create_dataverse_schema.py:269` | ✅ |
| CAA | `fsi_capolicyvalidationhistories` (auto-plural) | `conditional-access-automation/.../create_caa_dataverse_schema.py:201` | ✅ |
| ACV registry | `fsi_environmentregistries` (consonant+y → ies) | `audit-compliance-manager/.../create_dataverse_schema.py:138` | ✅ |
| CD | `fsi_controlmasters` / `fsi_controlassessments` / `fsi_complianceevidences` | `compliance-dashboard/scripts/create_cd_dataverse_schema.py` | ✅ |

Every column in `Export-UnifiedComplianceEvidence.ps1` `$select` lists and in
`Sync-SolutionAssessments.ps1` status/timestamp/runid reads was matched to a
declared attribute on the corresponding history table. Notable confirmations:

- **`fsi_runid` exists on all six history tables.** On CAA it is the table's
  **primary name attribute**, declared inline in the entity definition
  (`create_caa_dataverse_schema.py:234`, `PrimaryNameAttribute` at line 256) rather
  than in the additional-columns array — so `$select=fsi_runid` against the CAA
  history table is valid. (This was adversarially re-checked after an initial
  false-positive reading that only inspected the column array.)
- **Compliance Dashboard option sets are intentionally 1-based**
  (`fsi_cd_status` 1–4, `fsi_cd_zone` 1–3, `fsi_cd_evidencetype` 1–6, Test Result = 5).
  The integration's `DashboardStatus`, `DashboardScores`, `EvidenceTypeTestResult = 5`,
  and `Get-CanonicalZoneValue` outputs all match. The CD schema explicitly documents
  this as a deliberate choice (`create_cd_dataverse_schema.py:240`, plus a migration
  note that renumbering to 100000000-based is deferred).
- **Severity is 100000000-based** (`fsi_acv_severity` global option set, bound by ACV,
  SSC, AAM-severity, CAA), and `ConvertTo-DashboardStatus` maps the five values
  correctly.
- **ELM→ACV registration** writes only columns present on `fsi_EnvironmentRegistry`
  (`fsi_environmentid`, `fsi_zone`, `fsi_status` [integer 1=Active], `fsi_environmenttype`,
  `fsi_environmenturl`, `fsi_discoveredon`, `fsi_notes`), with zone/type translated to
  the `fsi_acv_zone` / `fsi_acv_environmenttype` option sets.

`.ralph-config.json` domain facts were re-verified against the schemas and hold,
with one clarification recorded below.

## Authoritative sources cited

- Dataverse application user requirement for non-interactive identities:
  <https://learn.microsoft.com/en-us/power-platform/admin/manage-application-users#create-an-application-user>
- Custom security role configuration:
  <https://learn.microsoft.com/en-us/power-platform/admin/database-security#create-or-configure-a-custom-security-role>
- Service-principal connection prerequisites (create application user in Dataverse):
  Microsoft Learn — *Manage connections for the Microsoft Dataverse connector*
  (Power Automate service-principal support).

## Gaps found & fixes applied

| # | Gap | Severity | Fix |
|---|-----|----------|-----|
| 1 | `PREREQUISITES.md` did not mention that managed-identity / service-principal auth requires a **Dataverse Application User + security role** — a valid token returns `403` on every call without it. This is the most likely lab-deploy blocker. | High (deployment) | Added an "Authentication" rewrite with a dedicated Application User section enumerating the required read/write security-role privileges per table, citing MS Learn. |
| 2 | `PREREQUISITES.md` described service-principal auth as using the delegated `user_impersonation` scope. That scope is for interactive sign-in; client-credentials uses `.default`. | Medium (accuracy) | Corrected the scope description. |
| 3 | `PREREQUISITES.md` and `README.md` listed `Microsoft.PowerApps.Administration.PowerShell` as required; no script uses it (all calls are `Invoke-RestMethod` to the Dataverse Web API). `MSAL.PS` was listed as unconditionally required. | Medium (script↔doc drift) | Removed the unused module; clarified `MSAL.PS` is needed only for interactive / legacy service-principal auth. |
| 4 | `CHANGELOG.md` had two duplicate `## [Unreleased]` headers. | Low (format) | Consolidated into a single `[Unreleased]` section. |

No PowerShell or Python **code** changes were required — every script reference was
verified accurate against the authoritative sibling schemas.

## Observations (no change made — by design / low value / risk)

- **`Get-SolutionTableConfig` declares `ZoneField = 'fsi_zone'` for CMM and FUS, whose
  *history* tables do not have an `fsi_zone` column** (zone lives on those solutions'
  *violation* tables). This is inert: no script ever reads `$config.ZoneField`. Zone is
  read in `Sync-SolutionAssessments.ps1` via a defensive
  `$ValidationRecord.PSObject.Properties['fsi_zone']` check (yields `null` for CMM/FUS),
  and `Export` uses explicit per-solution field lists that correctly omit `fsi_zone` for
  CMM/FUS/CAA. Left as-is to avoid churn on unused metadata; flagged for a future
  maintainer so the entry is not mistaken for a queryable column.
- **`.ralph-config.json` fact #4** ("All integrated solutions correlate run-level records
  through `fsi_runid`") is accurate, but note CAA carries `fsi_runid` as the history
  table's *primary name attribute*, not as an ordinary column — relevant if anyone
  scripts attribute metadata against that table.
- **Internal abbreviation:** ACV's `SolutionName` is "Audit Configuration Validator"
  while the repo catalog folder is `audit-compliance-manager` ("Audit Compliance
  Manager"). Consistent throughout this solution and its docs; cosmetic only.

## Runtime-only caveats (cannot be confirmed without a live tenant)

- Actual Web API success depends on the Application User existing with the listed
  security-role privileges (gap #1). Static analysis cannot verify role assignment.
- `fsi_zone` is **business-required** on `fsi_controlassessment`. Business-required
  attributes are not enforced by the Web API on create, so the Sync path that omits
  zone for CMM/FUS should succeed — but confirm in-tenant that no plug-in or
  alternate-key constraint rejects a null zone.
- The `fsi_AssessmentUpsertKey` alternate key (control + date + zone) is defined but
  not yet wired into the scripts; if adopted, all three key columns (including zone)
  must be populated, which interacts with the CMM/FUS null-zone behavior above.
- Power Automate flows are documentation-only (per the Solution Content Policy); their
  designer build steps were reviewed for column accuracy but not executed.

## Lab-readiness assessment

**Lab-ready (with the deployment prerequisite now documented).** The PowerShell and
Python assets parse/compile, tests pass, and all cross-solution Dataverse references
were verified accurate against the authoritative sibling schema scripts. The single
material risk to a first lab deployment — the missing Dataverse Application User /
security-role prerequisite for non-interactive auth — is now documented in
`PREREQUISITES.md`. Remaining items are runtime confirmations that require a live
tenant.
