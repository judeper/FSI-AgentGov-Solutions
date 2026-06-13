# Lab Validation Report — Agent Access Governance Monitor

> **Scope:** Static lab-readiness validation (no live tenant). Validation method =
> parse-validity + authoritative-source verification + documentation completeness.
> **Date:** 2026-06-09 · **Solution version:** v1.2.0 · **Branch:** `validation/agent-access-monitor`
>
> **v1.2.0 refresh:** This report was updated for the owl-mode remediation pass. See
> [§ v1.2.0 owl-mode remediation](#v120-owl-mode-remediation) for the changes that
> supersede the original v1.1.2 findings (fictitious-key purge, MSAL.PS removal,
> PowerShell 7.4 retarget, append-only role-design reframe, deferred Azure Automation).
>
> **2026-06-09 live run:** Stages 5–7 were subsequently executed against the live lab validation tenant
> tenant. See [§ Live lab validation: Stages 5-7 (the lab validation tenant)](#live-lab-validation-stages-5-7-the lab validation tenant)
> — this supersedes the "no live tenant" scope for the runbook / baseline / scan / evidence paths.

## Purpose and controls

The Agent Access Governance Monitor (AAM) detects Power Platform environments whose
Managed Environment agent-sharing settings deviate from zone-specific governance
requirements. It supports compliance with:

- **Control 3.8** — Copilot Hub and Governance Dashboard (primary)
- Related: 2.5 (agent sharing scope), 2.6 (restrict team-created agent sharing), 1.1
  (restrict publishing), 2.1 (Managed Environments)
- Regulatory context surfaced in output: FINRA Rule 4511, SOX 404, GLBA 501(b)

The solution evaluates three Managed Environment `extendedSettings` keys —
`bot-limitSharingMode`, `bot-authoringSharingDisabled`,
`bot-maxLimitUserSharing` — against per-zone baselines, persists results to
three Dataverse tables, and exports tamper-evident JSON evidence with SHA-256 hashes.

## What was checked

| Area | Method | Result |
|------|--------|--------|
| PowerShell parse validity (11 `.ps1`) | `Parser::ParseFile` | 0 errors |
| Python compile (5 `.py`) | `python -m py_compile` | 0 errors |
| `templates/*.json` well-formedness | `json.load` | OK |
| Managed Environment setting keys/values | Microsoft Learn (authoritative) | Confirmed |
| Settings object path (`Get-EnvironmentAccessSettings.ps1`) | Microsoft Learn + internal consistency | **Bug found + fixed** |
| Zone baseline semantics (`zone-settings-baseline.json`) | Microsoft Learn | **Reversed description fixed** |
| Dataverse column logical names | `create_dataverse_schema.py` (source of truth) vs scripts/docs | Consistent |
| Option-set values (zone/severity) | schema script vs `dataverse-schema.md` | Consistent |
| Authentication model | repo standard (managed-identity-first) | Compliant; legacy paths marked |
| `Get-AdminPowerAppEnvironmentGroup` cmdlet | Microsoft Learn module reference | **Not found — removed** |
| Regulatory language rules | grep prohibited phrases | Clean |

## Authoritative sources cited

1. **Limit sharing (Managed Environments)** —
   <https://learn.microsoft.com/power-platform/admin/managed-environment-sharing-limits>
   Confirms: setting keys `bot-limitSharingMode` (values `ExcludeSharingToSecurityGroups`,
   `noLimit`), `bot-authoringSharingDisabled` (`True`/`False`), and the maximum
   per-maker user-sharing cap surfaced as `bot-maxLimitUserSharing` (a positive integer
   limit, or `-1`/unset for no cap); the settings object path
   `$environment.Internal.properties.governanceConfiguration.settings.extendedSettings`;
   `Get-AdminPowerAppEnvironment` / `Set-AdminPowerAppEnvironmentGovernanceConfiguration`
   cmdlets; that "Exclude sharing with security groups" means sharing is limited to
   individuals (security-group sharing is excluded); that rules "may take up to an hour"
   to enforce and "don't impact any existing users who already have access."
2. **Get-AdminPowerAppEnvironment** —
   <https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/get-adminpowerappenvironment>
3. **Set-AdminPowerAppEnvironmentGovernanceConfiguration** —
   <https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/set-adminpowerappenvironmentgovernanceconfiguration>
4. **Microsoft.PowerApps.Administration.PowerShell module reference** —
   <https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/>

## Gaps and fixes

### Fixed — settings extraction object path (Major)

`Get-EnvironmentAccessSettings.ps1` read the sharing settings from
`$env.Internal.governanceConfiguration.settings.extendedSettings` (two sites). The
authoritative Microsoft sample reads
`$environment.Internal.properties.governanceConfiguration.settings.extendedSettings`,
and the same script already uses `$env.Internal.properties.environmentGroup` and
`$env.Internal.properties.linkedEnvironmentMetadata` for sibling fields — so the missing
`.properties.` segment was internally inconsistent. With the wrong path, all three bot
settings resolved to `null`; `Compare-ZoneCompliance.ps1` then substitutes platform
defaults (`noLimit` / `false`), which violate Zone 2/3 expectations and would emit
systematic false Critical/High violations and corrupt captured baselines. Corrected both
extraction sites and the helper synopsis.

> **Runtime caveat:** Verified against the authoritative source and internal code
> consistency only. The actual runtime shape of `Get-AdminPowerAppEnvironment().Internal`
> could not be exercised without a live Managed Environment tenant. Recommended lab check:
> run `Get-EnvironmentAccessSettings -Verbose` and confirm `BotLimitSharingMode` is
> populated (not null) for an environment known to have sharing limits configured.

### Fixed — reversed zone-baseline setting descriptions (Minor)

`templates/zone-settings-baseline.json` described `ExcludeSharingToSecurityGroups` as
"restricted to security groups only" — the opposite of the documented behavior (sharing
with security groups is *excluded*; sharing is limited to individuals). Corrected the
`bot-limitSharingMode` and `bot-maxLimitUserSharing` descriptions, which feed
violation/evidence output and operator-facing alerts.

### Fixed — environment-group cmdlet does not exist (second-pass, Major)

`Get-EnvironmentAccessSettings.ps1` enriched environment-group names via
`Get-AdminPowerAppEnvironmentGroup`. A second-pass command-existence check against the
published
[`Microsoft.PowerApps.Administration.PowerShell` module reference](https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/)
confirmed that **no environment-group cmdlet exists** in the module (the `Get-*` list goes
`Get-AdminPowerAppEnvironment` → `Get-AdminPowerAppEnvironmentLocations` →
`Get-AdminPowerAppEnvironmentRoleAssignment`). The call could never succeed; the surrounding
`try/catch` only kept it from crashing while emitting a warning on every run. The dead lookup
was removed. The environment-group GUID is still captured from
`$env.Internal.properties.environmentGroup.id`; the friendly group name stays `null`
(resolve from the Power Platform admin center if required). The result-object shape is
unchanged.

## Items verified as already correct (no change)

- **Dataverse logical names** in all OData `$select`/`$filter` calls and docs match the
  SchemaNames lowercased in `create_dataverse_schema.py` (e.g. `fsi_environmentguid`,
  `fsi_isactive`, `fsi_validationtime`, `fsi_severitylabel`).
- **Option-set integers** (`fsi_acv_zone`, `fsi_acv_severity`) in `AAMClient.psm1`,
  evidence export, and `dataverse-schema.md` are consistent with the schema script,
  including the documented Critical/High → `100000003` (Failed) collapse disambiguated by
  `fsi_severitylabel`.
- **Authentication** is managed-identity-first: `aam_client.py`/`deploy.py` prefer
  `ManagedIdentityCredential` / `WorkloadIdentityCredential`, with client-secret paths
  carrying the `# legacy: dev-only` marker; `requirements.txt` pins `azure-identity` and
  `msal`. PowerShell runbook/evidence paths acquire modern OAuth through
  `Get-AAMAccessToken` (device-code or client-secret); the archived MSAL.PS module and
  certificate-thumbprint auth were removed, and the docs steer unattended automation
  toward managed identity.
- **Regulatory language** — no FSI-prohibited compliance-absolute phrases
  (per `fsi-language-rules.instructions.md`) in solution Markdown.
- **Content policy** — no Power Platform runtime artifacts; the flow is documented as a
  manual build in `docs/flow-configuration.md`.

## v1.2.0 owl-mode remediation

An adversarial (owl-mode) review of the promoted solution surfaced findings that
supersede portions of the original v1.1.2 report above. All CRITICAL and HIGH items were
applied before lab deployment:

- **C1 — fictitious key purged.** The fictitious published-bot limit sharing-mode key
  (a `bot-…` name that does not exist in `extendedSettings`) is **not** a real
  Managed-Environment setting; the original report incorrectly listed it as
  authoritative-source "Confirmed". Every reference was removed (Dataverse column,
  baseline-JSON property, comparison/severity logic, evidence-export field, alert text). The
  solution now evaluates only the three real keys, with `bot-maxLimitUserSharing`
  normalized to Capped/Uncapped. Repo-wide grep for the purged key token in
  `agent-access-monitor/` returns zero hits.
- **C2 — MSAL.PS removed.** The archived MSAL.PS dependency was removed from the runbook,
  baseline-capture, and evidence-export scripts; modern OAuth is acquired through
  `Get-AAMAccessToken`. Certificate-thumbprint auth now throws.
- **C3 — PowerShell 7.4 retarget.** Runbook and module manifest target 7.4 (Azure
  Automation retired 7.1/7.2).
- **C4 — append-only by role design.** Claims of native Dataverse immutability were
  removed; the append-only audit trail is documented as a security-role design in
  `docs/role-design-append-only.md`.
- **H1 — non-Managed guard.** Environments without `extendedSettings` are reported as
  `NotManaged` (out-of-band scope), distinct from a settings-read bug.
- **H2 — case-insensitive comparisons** for sharing-mode values.
- **M1/M3 — deferred Azure Automation.** The runbook runs standalone locally; the daily
  flow is a Recurrence trigger + Dataverse read. No Azure subscription, Automation
  Account, premium connector, or always-on SPN is required for the lab.

A `lab/` harness (`Invoke-Deploy.ps1`, `Test-LabAuthReadiness.ps1`, config templates,
`slice-build-runbook.md`) was added for the standalone deployment model.

## Final lab-readiness assessment

**Lab-ready, with one runtime-verification step.** Parse/compile baselines are clean,
documentation is complete and accurate, naming/auth conventions are honored, and the two
authoritative-source discrepancies (settings object path; reversed baseline description)
are corrected. The single residual risk is that the settings-path fix and the
environment-group cmdlet availability cannot be exercised without a live Managed
Environment tenant. Before relying on results in a lab, run
`Get-EnvironmentAccessSettings -Verbose` against a configured Managed Environment and
confirm the three `Bot*` properties populate as expected.

## Live lab validation: Stages 5-7 (the lab validation tenant)

> **Date:** 2026-06-09 · **Runner:** Lab validation (Validation/QA) · **Target:** the live lab validation tenant
> tenant (Sandbox / NotManaged) · **Mode:** local validator runbook (Azure Automation
> **deferred**) · single live-writer. Supersedes the "no live tenant" scope above for the
> Stage 5-7 runbook / baseline / scan / evidence paths.

The Stage 5-7 validator chain was executed **locally** against the lab validation tenant
(`Invoke-AccessBaselineCapture` -> `Test-AgentAccessCompliance` ->
`Export-AgentAccessEvidence` + `Test-EvidenceIntegrity`). Authentication used the operator's
existing Microsoft Entra ID / Dataverse user token (acquired in-process via
`az account get-access-token`); **no service principal or client secret was provisioned** for
this run. Every persisted row was confirmed with an **independent Get-row** issued on a
**fresh token** (not the script's own log). All option-set filters used the **live
100000000-based** integers, never labels.

### Stage 5 - baseline capture (LIVE, verified)

`Invoke-AccessBaselineCapture` wrote **1** `fsi_accessbaseline` row for the lab validation tenant. An
independent Get-row (fresh token) confirmed:

| Field | Value |
|---|---|
| `fsi_accessbaselineid` | `b711d162-…` (independently read back) |
| `fsi_zone` | `100000000` -> "Unclassified" (FormattedValue) |
| bot sharing settings | **empty / null** (NotManaged - no `extendedSettings`) |
| `fsi_isactive` | `True` |
| captured-by | `lab-validation` |
| raw JSON | `EnvironmentType = Sandbox`, null sharing settings |

The NotManaged status was captured correctly: the lab validation tenant exposes no
`governanceConfiguration.settings.extendedSettings`, so the baseline records empty bot
settings rather than fabricating defaults.

> **Bug found + fixed (Major) - baseline capture crashed on a NotManaged environment.**
> `Save-AAMBaseline` declared `[Parameter(Mandatory)][string]$BotLimitSharingMode`, which
> **rejects the empty string** a NotManaged environment legitimately produces - the first
> live capture threw before writing. Fixed by adding `[AllowEmptyString()]` to the parameter
> (`scripts/private/AAMClient.psm1`). The re-run succeeded and persisted the row above. Carry
> into back-port.

### Stage 6 - compliance scan (LIVE, verified)

`Test-AgentAccessCompliance` (the runbook, run verbatim with persistence) wrote **1**
`fsi_accessvalidationhistory` row and **0** `fsi_accessviolation` rows. An independent Get-row
confirmed:

| Field | Value |
|---|---|
| `fsi_accessvalidationhistoryid` | `5e8df48f-…` |
| run id | `fbc2e51b-…` |
| TotalEnvironments / CompliantCount / ViolationCount | `1 / 1 / 0` |
| OverallStatus | `Passed` |
| `fsi_severity` | `100000000` -> "Passed" |

This confirms the **H1 NotManaged guard**: the lab validation tenant (null `extendedSettings`) evaluated to
**ScopeOutOfBand -> compliant (out-of-band)**, **not** a false Critical/High and **not** a
crash on null `extendedSettings`. The scan persisted **no** phantom violation, and the
case-insensitive sharing-mode comparison emitted no spurious drift.

> **Non-blocking finding:** `Get-AAMEnvironmentVariable` (grace-period / include-sandbox
> reads) returns HTTP 400 in this env; the runbook **gracefully falls back to defaults**
> (grace = 48 h, include-sandbox = false). No effect on the outcome - the run explicitly
> passes `-GracePeriodHours 48` and does not exclude the Sandbox, so the lab validation tenant is in scope.

### Stage 6b - Managed-key observability (READ-ONLY, full tenant, not persisted)

To exercise the three real `bot-` keys (which the lab validation tenant cannot expose), a **read-only** pass
enumerated **all 24 environments** in the tenant via the BAP admin REST API and ran the
in-memory comparison **without persisting**:

- **11 Managed** (populated `extendedSettings`) / **13 NotManaged**.
- The three real keys (`bot-limitSharingMode`, `bot-authoringSharingDisabled`,
  `bot-maxLimitUserSharing`) were **read live** on Managed environments (e.g. `noLimit` /
  authoring-sharing-disabled / `-1`).
- Comparison: **Evaluated = 11**, **ScopeOutOfBand = 13** - **zero** false non-compliant on
  any NotManaged environment.
- **8 real baseline-vs-current drifts** were detected on Managed environments (read-only,
  **deliberately not persisted** - these are real tenant environments, out of disposable
  scope).
- **Fictitious-key absence confirmed live:** the purged `bot-published…` key is **absent**
  from every environment's settings; only the three real keys appear.

### Disposable drift demonstration (write -> verify -> delete)

Because the lab validation tenant is NotManaged, a true sharing-limit violation cannot be induced on it without
changing a real environment. To prove the **detection -> persist -> surface** path end-to-end
**without** mutating any real environment, a **single disposable synthetic Managed
environment** (canonically **Zone 1 (Enterprise)** under Option A — `noLimit` is non-compliant for the most-restrictive zone) was injected into the enumeration
shadow only:

- Detection produced **2 Critical violations** in memory (sharing-mode + authoring-sharing).
- Both **persisted** to `fsi_accessviolation` (run id `7602c69a-…`), including the boolean
  setting (`fsi_expectedvalue = 'True'`, `fsi_actualvalue = 'False'`), `fsi_zone` ->
  canonical **"Zone 1 (Enterprise)" (`100000001`)**, severity **Failed / Critical** -
  independently Get-row-verified. *(At validation time the pre-canonical code persisted this as
  the inverted "Zone 3 (Personal)" / `100000003`; the stored integer/label was inverted, but the
  Failed/Critical outcome was correct — see [§ Canonical-zone reconciliation — known evidence
  inversion](#canonical-zone-reconciliation--known-evidence-inversion).)*
- The disposable rows were then **deleted**; an independent re-count returned the tables to
  their pre-demonstration state.

> **Bug found + fixed (Major) - boolean-setting violations failed to persist (audit gap).**
> `Compare-ZoneCompliance` emits `[Boolean]` Expected/Actual for boolean settings (e.g.
> `BotAuthoringSharingDisabled`); `Write-AAMViolation` posted those raw JSON booleans into the
> **String** columns `fsi_expectedvalue` / `fsi_actualvalue`, which Dataverse rejected with
> **HTTP 400** - surfaced only as a `Write-Warning`, so a real boolean-setting violation would
> **silently fail to be recorded**. Fixed with `[string]` coercion of `$Violation.Expected` /
> `$Violation.Actual` in `Write-AAMViolation` (`scripts/private/AAMClient.psm1`). After the fix
> the boolean violation persisted as shown. Carry into back-port.

### Stage 7 - evidence export + SHA-256 integrity (LIVE, verified)

`Export-AgentAccessEvidence -IncludeBaselines` produced
`aam-evidence-All-20260609-092720.json` (Validations = 1, Violations = 0, Baselines = 1,
OverallStatus = Passed). **SHA-256 integrity verified three independent ways:**

| Check | Result |
|---|---|
| `Test-EvidenceIntegrity` (verbatim script) | **VERIFIED / True** |
| Export-reported hash == `.sha256` companion (64 chars) | **match** |
| Independent `Get-FileHash -Algorithm SHA256` | **match** |

**SHA-256:** `32C81BB88A41133A8E57247DE3D215BD397D4F73E85CD0E825146FAA77C46C4E`

The evidence package + its `.sha256` companion are retained in the gitignored
`lab/.deploy-runtime/evidence/` as the durable proof for this run.

### What this live run proved

- The Stage 5-7 validator chain **runs locally** end-to-end against a live tenant and
  **supports compliance with** Control 3.8 (and the related record-keeping context: FINRA
  4511, SOX §404, GLBA §501(b)) by producing a baseline, an append-only validation-history
  record, and tamper-evident SHA-256 evidence.
- The **H1 NotManaged guard** behaves correctly on the live NotManaged target:
  **ScopeOutOfBand -> compliant**, no false Critical/High, no null-`extendedSettings` crash,
  no phantom case-sensitivity drift.
- The **detection -> persist -> surface** path is exercised end-to-end via a disposable
  synthetic Managed environment (write -> independent verify -> delete).
- The **fictitious `bot-published…` key is absent** from live settings.
- **Two genuine product defects** on documented-expected paths were found and fixed
  (`[AllowEmptyString()]` baseline capture; `[string]` violation-value coercion).

### Known lab-scope limitation

Positive observation of the three real `bot-` keys, and persistence of a **true** Managed
sharing-limit `Failed` row, require a **Managed environment with environment-level sharing
limits configured** (so `governanceConfiguration.settings.extendedSettings` is populated).
the lab validation tenant is NotManaged (Sandbox), so its in-scope run legitimately exercises the
**NotManaged -> ScopeOutOfBand** branch. Managed-key behaviour was therefore evidenced
**read-only** across the 11 Managed tenant environments (8 real drifts detected, **not**
persisted), and the persist path was proven on a **disposable synthetic** Managed environment
- analogous to the documented ASARD runtime-plane scope limits. Validating a persisted
true-`Failed` row against a **real** Managed environment with configured sharing limits
remains the one outstanding runtime step, deferred as out of lab scope.

### Cleanup posture (this run)

- All disposable artifacts were deleted; the lab-tenant baseline + validation-history rows
  created for this run were removed after evidencing, returning **all three tables to 0**
  (independently re-counted). The real environment is unchanged.
- **No service principal / client secret was provisioned** (the existing operator token was
  used), so none required deletion; `lab/config.local.json` is unchanged (`auth.clientId`
  remains empty). The SHA-256-sealed evidence JSON is retained as the durable proof.

## Canonical-zone reconciliation — known evidence inversion

> **Added 2026-06-13 — portfolio canonical-zone decision (Option A). Code-and-text-only
> remap; this solution was NOT re-validated against a live tenant in this change.**

Earlier releases of AAM keyed governance policy off the environment-**name** string
(enterprise → Zone 3, personal → Zone 1) and persisted the matching integer and label — so an
enterprise/Managed environment was recorded as `fsi_zone = 100000003`, labelled
"Zone 3 (Personal)". The canonical producing schema for the shared `fsi_acv_zone` option set
(the agent-intake schema) and the live `fsi_acv_zone` set on the lab validation tenant define the
**opposite, canonical** meaning, adopted portfolio-wide as Coordinator Decision "Option A"
(2026-06-13):

- **Zone 1 (Enterprise) = `100000001` = most restrictive**
- Zone 2 (Team) = `100000002`
- **Zone 3 (Personal) = `100000003` = least restrictive**
- Unclassified / fail-closed = `100000000`

This solution's naming classifiers, per-zone baseline (`templates/zone-settings-baseline.json`),
zone-integer write-back, console/README labels, and the evidence narrative above were remapped to
this canonical orientation. A canonical-zone unit assertion (`lab/Assert-CanonicalZonePolicy.ps1`,
"strictest policy ⇔ Zone 1 ⇔ `100000001`") is locked in this release and gated.

**Pass/fail outcomes of prior validation runs were correct.** The legacy code keyed policy off the
environment-name string, so an enterprise environment received enterprise-grade (most-restrictive)
policy regardless of which integer was persisted alongside it. **What was inverted was the stored
zone integer and its label**, not the compliance decision.

**Correctness of this remap — established without a live tenant — rests on three pillars:**

1. the **canonical-zone unit assertion** (deterministic, runs against the remapped code: strictest
   policy ⇔ Zone 1 ⇔ `100000001`, Zone 3 ⇔ `100000003`, Unknown ⇔ `100000000`);
2. **static gates** (PowerShell parse + PSScriptAnalyzer + valid JSON); and
3. **byte-for-byte alignment with the four lab-validated sibling solutions** (FUS, CMM, GAC, ACA)
   that received the identical flip and were live-validated on the lab validation tenant on 2026-06-13.

**Recommendation for downstream operators.** Any `fsi_zone` rows persisted by earlier releases carry
the pre-canonical integers and labels. They remain valid historical evidence of which environments
were scanned and whether they passed or failed (the pass/fail call was correct), and are retained
unaltered. To refresh persisted integers/labels to the canonical semantics, **re-run the validated
solution after upgrading**; this solution does **not** auto-migrate historical rows.

AAM **supports compliance with** Control 3.8 (Copilot Hub / Governance Dashboard agent-access
expectations). It does **not by itself ensure, guarantee, or eliminate** regulatory risk.
