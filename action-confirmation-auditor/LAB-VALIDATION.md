# Lab Validation Report — Action Confirmation Auditor (ACA)

> **Validation type:** Static (parse-validity + authoritative Microsoft source
> verification + documentation completeness, 2026-06-04) **followed by live tenant
> validation of the detection path on the lab validation tenant (2026-06-13) with a
> SYNTHETIC YAML topic fixture — coverage remains PARTIAL.** The static report below is
> retained as the historical record; the live outcome is in its own dated section.
> **Original static validation date:** 2026-06-04
> **Live tenant validation date:** 2026-06-13 (see "Live tenant validation outcome — 2026-06-13" below)
> **Solution version:** v1.2.1 (fixes recorded under CHANGELOG `[Unreleased]`)

## Live tenant validation outcome — 2026-06-13

On 2026-06-13 the detection path was validated live against the lab validation tenant
using a **synthetic, hand-written YAML topic fixture**. This supersedes the "no live
tenant" framing of the 2026-06-04 static report for the parts proven below; the static
report is retained as the historical record. **Coverage remains PARTIAL** — see the
synthetic-YAML boundary at the end of this section.

**What was deployed.** The three `fsi_action*` Dataverse tables (scan-run, audit-result,
confirmation-exception) with their columns, the two shared option sets (`fsi_acv_zone`,
`fsi_acv_severity`) bound to the canonical live `100000000`-based members, and the
ACA-specific option sets. The **deployed schema is the retained deliverable**; the
disposable test fixtures below were all removed afterward.

**What was proven against disposable-bot fixtures (committed detection path, real agents read-only):**

- **Foreign-key re-path is live.** The `botcomponent` query keyed on `_parentbotid_value`
  now succeeds against the lab validation tenant (no more HTTP 400), on a disposable bot and read-only on
  the two real agents. This confirms the FK fix that re-pathed the detector away from the
  non-existent `_botid_value`.
- **Violation.** A Zone 1 synthetic YAML topic with a connector action and no confirmation
  node resolved to `Missing` / non-compliant / **Critical**; one row persisted to Dataverse,
  and an independent read-back confirmed the canonical zone integer and the String severity.
- **Discrimination + same-fixture flip.** A compliant variant (a `Question` confirmation
  node preceding the action) resolved to `Present` / Compliant with no row; flipping the
  same fixture between shapes flipped the result accordingly.
- **Fail-closed Indeterminate.** Unparseable content resolved to `UnableToDetermine` /
  non-compliant — never a false Compliant.
- **Evidence integrity + teardown.** The **SHA-256 evidence digest (prefix `DADDBA91`)**
  recomputed to an integrity match; afterward the audit-result table returned from one row
  to zero, the exception and scan-run tables stayed at zero, and the disposable bots were
  deleted. **No disposable rows persist in the lab validation tenant**; the real agents were never mutated.

**Correction to the 2026-06-04 static "Verified Healthy" note.** The static report below
recorded the core scanner as healthy "queries `botcomponents` with `_botid_value`,
`componenttype` 12/2 … endpoint shape correct". That `_botid_value` lookup was in fact a
defect (it returned HTTP 400 live); the detector was subsequently **re-pathed to
`_parentbotid_value` with topic component types `0`/`9`** and that fix was proven live on
2026-06-13. The static note is left in place as the historical record, corrected here.

**Synthetic-YAML boundary (why ACA stays PARTIAL).** The topic content authored on the
disposable fixtures was **synthetic hand-written YAML**, NOT an authentic in-product
Copilot Studio-authored topic. The two real agents exposed **0 of 18 topic components**, so
there was no genuine in-product topic to scan. This live leg therefore proves the FK query,
the YAML parser, the confirmation-node policy, and Dataverse persistence are **real**, but it
does **NOT** prove end-to-end detection of authentic in-product topics. `controls-covered.json`
stays `coverage: "partial"` on **both 2.12 and 1.10**; closing the gap requires a future live
leg against a genuine Copilot Studio-authored fixture (a real confirmation-bearing topic plus a
second topic with no confirmation node).

**Honest framing.** This is **lab evidence** from disposable fixtures on the lab validation tenant — not a
production guarantee. A customer's tenant evidence is produced by running the solution against
the customer's own tenant. This solution **supports compliance with** its named controls; it
does not by itself ensure, guarantee, or eliminate regulatory risk.

## Solution Purpose & Target Controls

ACA scans Power Platform environments for Copilot Studio agent topics that invoke
actions (connector calls, cloud flows, plugins, HTTP requests) without a
human-in-the-loop (HITL) confirmation step, classifies violations by zone and
action type, and supports exception management with Maker/Checker gating.

- **Primary control:** 2.12 — Supervision and Oversight / HITL checkpoints (FINRA Rule 3110)
- **Supporting control:** 1.10 — Communication Compliance Monitoring
- **Regulatory context:** FINRA Rule 3110, GLBA Section 501(b), SOX Section 404

## What Was Checked

- **PowerShell (14 files):** parse-validity via `[Parser]::ParseFile` — all pass.
- **Python (5 files):** `python -m py_compile` — all pass.
- **Dataverse column references:** cross-checked every `$select`/`$filter`/record
  write against `scripts/create_dataverse_schema.py` and `docs/dataverse-schema.md`
  (the source of truth) and `.ralph-config.json` domain facts.
- **Authentication patterns:** verified managed-identity-first standard; client
  secret path in `Connect-EnvironmentDataverse.ps1` carries the `# legacy: dev-only`
  marker.
- **API usage:** Microsoft Graph audit log query API, `Invoke-MgGraphRequest`,
  `Get-AzAccessToken` SecureString behavior, Power Platform admin token audience,
  Dataverse Web API `v9.2` endpoints.
- **Language rules:** grep for the FSI-prohibited compliance-absolute phrases
  (per `fsi-language-rules.instructions.md`) outside CHANGELOG — zero hits.

## Authoritative Sources Cited

| Topic | Source |
|-------|--------|
| Graph audit log query API on **v1.0**, `recordTypeFilters`, `auditLogRecordType` enum (`aipDiscover`, `aipSensitivityLabelAction`) | `https://learn.microsoft.com/graph/api/resources/security-auditlogquery` and `https://learn.microsoft.com/graph/api/security-auditlogquery-list-records` |
| `Get-MgContext` exposes ClientId/TenantId/Scopes/AuthType — **not** an access token | `https://learn.microsoft.com/powershell/microsoftgraph/authentication-commands` |
| `Invoke-MgGraphRequest` for authenticated Graph REST calls in PowerShell | `https://learn.microsoft.com/powershell/module/microsoft.graph.authentication/invoke-mggraphrequest` |
| `Get-AzAccessToken` default output changed to SecureString; `-ResourceUrl` usage | `https://learn.microsoft.com/powershell/module/az.accounts/get-azaccesstoken` |
| Power Platform admin token audience `https://service.powerapps.com/` | `https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/get-jwttoken` |
| `Microsoft.PowerApps.Administration.PowerShell` is a Windows PowerShell 5.x (.NET Framework) module | Repo `.ralph-config.json` domain fact + prerequisites.md |
| Azure Automation managed identity (RunAs deprecation) | `https://learn.microsoft.com/azure/automation/learn/powershell-runbook-managed-identity` |
| Purview AI Hub / DSPM for AI | `https://learn.microsoft.com/purview/ai-microsoft-purview` |

## Gaps Found and Fixes Applied

### Scripts

1. **`Get-PurviewAIHubEvidence.ps1` — broken Graph authentication (functional bug).**
   Built bearer headers from `(Get-MgContext).AccessToken`, which is always
   `$null` (the context object has no token property). Both the Graph audit query
   and the Dataverse query sent empty tokens. **Fix:** Graph calls now use
   `Invoke-MgGraphRequest` (reuses the `Connect-MgGraph` session, correct
   audience). Added a begin-block guard that errors clearly if no Graph session
   exists.

2. **`Get-PurviewAIHubEvidence.ps1` — wrong token audience for Dataverse.**
   The Dataverse query reused the (empty) Graph token; even when populated, a
   Graph-audience token is rejected by Dataverse. **Fix:** added
   `-DataverseAccessToken` (SecureString) parameter plus an `Az.Accounts`
   fallback (`Get-AzAccessToken -ResourceUrl <DataverseUrl>`), managed-identity-first.

3. **`Get-PurviewAIHubEvidence.ps1` — non-existent column `fsi_hasconfirmation`.**
   The schema has no such column. **Fix:** query `fsi_confirmationstatus`
   (option set, `Present = 100000000`) and derive `HasConfirmation` as a boolean.

4. **`Get-PurviewAIHubEvidence.ps1` — recordTypeFilters values.** The
   `recordTypeFilters` use documented camelCase members of the v1.0
   `auditLogRecordType` enum (`aipDiscover`, `aipSensitivityLabelAction`).
   `copilotInteraction` is **not** a member of that enum (it is a beta
   record subtype, `copilotInteractionAuditRecord`, not a filter value), so
   it was removed — an unknown evolvable-enum member returns HTTP 400 and
   fails the whole query. Copilot interaction activity is collected via the
   Activity Explorer fallback.

5. **`Start-ActionConfirmationRunbook-MI.ps1` — wrong token audience for Power
   Platform admin.** Acquired a Graph token and passed it to
   `Add-PowerAppsAccount`; the module needs a `https://service.powerapps.com/`
   token, so environment enumeration would fail. **Fix:** acquire the Power
   Apps-audience token via `Get-AzAccessToken -ResourceUrl 'https://service.powerapps.com/'`.

### Docs

6. **`docs/prerequisites.md`** — added an "Optional: Purview AI Hub / DSPM
   Integration" section documenting the previously-undocumented dependencies:
   the `AuditLogsQuery.Read.All` Graph scope and the separate Dataverse token.

7. **`CHANGELOG.md`** — recorded all fixes under the existing `[Unreleased]` entry.

### Dependencies

- No dependency files changed. `scripts/requirements.txt` (`msal`, `requests`)
  is sufficient for the Python setup path. The Purview script's
  `Az.Accounts`/`Microsoft.Graph.Authentication` needs are now documented.

## Verified Healthy (no change needed)

- Core scanner `Get-AgentActionSettings.ps1`: queries `botcomponents` with
  `_botid_value`, `componenttype` 12/2, Dataverse Web API `v9.2` — endpoint
  shape correct. Per-environment Dataverse tokens are acquired via
  `Connect-EnvironmentDataverse.ps1` (Az/MI, correct audience).
- `Export-ActionAuditEvidence.ps1`, `ACAClient.psm1`,
  `Test-UserDefinedActionMessages.ps1`, `Start-ActionConfirmationValidationRunbook.ps1`,
  `docs/flow-configuration.md`: all Dataverse column references and option-set
  integers (100000000+) match the schema.
- Auth standard: client-secret path is marked `# legacy: dev-only`; interactive
  and managed-identity paths are present.

## Runtime-Only Verification Items (cannot confirm statically)

- **Topic-content parsing fidelity.** `Get-AgentActionSettings.ps1` detects
  action nodes and confirmation patterns with regular expressions over
  `botcomponent.content`. The exact `kind` values (`InvokeFlowAction`,
  `InvokeConnectorAction`, `InvokeSkillAction`, etc.) and the confirmation
  heuristics were exercised live on 2026-06-13 against a **synthetic** YAML
  topic fixture; parsing fidelity against **authentic in-product** Copilot
  Studio-authored topic content is still unproven (the real agents exposed 0/18
  topic components) and remains the PARTIAL gap. Node schemas can change and are
  not publicly versioned.
- **`Add-PowerAppsAccount -AccessToken` with a managed-identity token.** Microsoft
  documents service-principal auth as the supported automation path; passing an
  MI-issued Power Apps-audience token is a reasonable pattern but is not
  explicitly documented as supported. Confirm in a live Automation account.
- **Graph audit log query latency.** The script polls once after a 5-second
  delay; real audit queries may take longer to return records. Confirm and tune
  poll/retry against a live tenant.
- **DSPM for AI availability / Copilot audit record types.** Copilot
  interaction activity is collected via the Activity Explorer fallback;
  presence of those records depends on tenant licensing and audit
  configuration.

## Final Lab-Readiness Assessment

**Lab-ready, live-validated PARTIAL.** All scripts parse/compile; the two functional
authentication defects (Purview evidence script and the MI runbook) and the schema column
mismatch are fixed and verified against authoritative Microsoft sources. The core scan path
and evidence export were aligned to the schema, and the detection path was **live-validated
against the lab validation tenant on 2026-06-13** with a synthetic YAML fixture (FK re-path, YAML parser,
confirmation-node policy, fail-closed Indeterminate, Dataverse persistence, SHA-256 evidence
integrity, and teardown all proven — see "Live tenant validation outcome — 2026-06-13" above).
Coverage stays **PARTIAL**: authentic in-product Copilot Studio topic detection is not yet
proven (synthetic-YAML boundary; real topic content 0/18). The remaining items are inherently
runtime-verification concerns (authentic-content parsing fidelity and service availability),
documented above rather than assumed.
