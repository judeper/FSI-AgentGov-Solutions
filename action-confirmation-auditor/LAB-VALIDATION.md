# Lab Validation Report — Action Confirmation Auditor (ACA)

> **Validation type:** Static verification (2026-06-04), a bounded live tenant leg
> using a synthetic YAML fixture (2026-06-13), and offline Topic V2 regressions for
> the maintainer backport (2026-09-08). The June fixture did not prove authentic
> Copilot Studio Topic V2 retrieval; that provenance is corrected below.
> **Original static validation date:** 2026-06-04
> **Live tenant validation date:** 2026-06-13 (see "Live tenant validation outcome — 2026-06-13" below)
> **Offline backport validation date:** 2026-09-08
> **HTTP action-shape correction date:** 2026-09-11
> **Solution version:** v1.2.3

## Authentic Topic V2 action-shape correction - 2026-09-11

Owner-attended authoring through the supported Copilot Studio web editor in Autonomous Demo
created two enabled, unpublished Topic V2 topics. Copilot Studio serialized the HTTP action
as `kind: HttpRequestAction`, not the legacy `kind: HttpRequest`. The authentic fixture
therefore exposed a narrow recognition gap: the main detector and the user-defined
action-message helper both missed the action signature, while the existing private
`ACAClient.psm1` path already recognized it.

Version 1.2.3 adds `HttpRequestAction` recognition to the main canonical kind map and the
helper action signature while retaining legacy `HttpRequest`. Offline regressions now
exercise confirmed and unconfirmed GET actions plus recognized and missing action-message
cases with YAML parsing unavailable. This is offline discrimination only; owner-attended
live discrimination through the tenant retrieval path remains pending. Controls 2.12 and
1.10 remain **PARTIAL**.

## Maintainer backport outcome — 2026-09-08

The ACA-only backport corrects all three approved call sites:

- `Get-AgentActionSettings.ps1` and `governance/Test-UserDefinedActionMessages.ps1`
  query `componenttype` 9/0 topic rows, select `data` and `content`, and prefer
  nonblank `data`.
- Both canonical paths fail closed before page-one classification when
  `@odata.nextLink` is present.
- Empty or otherwise unassessable topics make the result inconclusive even when
  another topic was assessed successfully.
- `private/ACAClient.psm1` uses the same payload precedence while preserving its
  existing all-component pagination loop.

`tests/TopicV2Detection.Tests.ps1` provides offline behavioral coverage with mocked
Dataverse/network boundaries. The suite covers authentic-shape type-9 `data` payloads,
legacy type-0 fallback, precedence and whitespace cases, Present/Missing discrimination,
mixed unassessable content, unavailable YAML parsing, canonical incomplete pages,
401/403/timeout/429/5xx failures, stable result properties, downstream policy treatment,
and the exported client's existing page-two aggregation.

No tenant, credential, persistence, or agent-configuration access was used for this
backport. Controls 2.12 and 1.10 remain **PARTIAL**. A separately approved owner-attended
live proof against authentic in-product Topic V2 components is still required for full
detector acceptance.

## Live tenant validation outcome — 2026-06-13

On 2026-06-13 selected detection and persistence behavior was exercised against the lab
validation tenant using a **synthetic, hand-written YAML fixture**. The fixture was stored
in the same variable-type/legacy-content shape selected by the then-current defective
query, so this leg did not validate authentic Copilot Studio Topic V2 retrieval. The
static report is retained as a historical record, with the corrected boundary below.

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
recorded both the wrong `_botid_value` foreign key and variable component types `12`/`2`
as healthy. The June leg proved the `_parentbotid_value` re-path, but its synthetic
fixture exercised the still-defective type/content selection against itself. The type
`0`/`9` and Topic V2 `data` fixes were implemented in the September maintainer backport
and validated offline; no live proof was performed for this repository release.

**Synthetic-YAML boundary (why ACA stays PARTIAL).** The disposable fixture was not an
authentic in-product Copilot Studio-authored topic. The reported **0 of 18** result on the
two real agents was later identified as evidence of the wrong type/content query, not
evidence that authentic topics were absent. This live leg supports the FK, parser
heuristic, confirmation-policy, persistence, integrity, and teardown claims only within
that synthetic boundary. `controls-covered.json` stays `coverage: "partial"` on both
2.12 and 1.10; closing the gap requires a separately approved live leg against authentic
Topic V2 components with comparable confirmed and unconfirmed actions.

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

- Core scanner authentication and Dataverse Web API version remain unchanged.
  Topic retrieval now uses `_parentbotid_value`, component types 9/0, and
  Topic V2 `data` with legacy `content` fallback; this selection is covered by
  the September offline regression suite.
- `Export-ActionAuditEvidence.ps1`, `ACAClient.psm1`,
  `Test-UserDefinedActionMessages.ps1`, `Start-ActionConfirmationValidationRunbook.ps1`,
  `docs/flow-configuration.md`: all Dataverse column references and option-set
  integers (100000000+) match the schema.
- Auth standard: client-secret path is marked `# legacy: dev-only`; interactive
  and managed-identity paths are present.

## Runtime-Only Verification Items (cannot confirm statically)

- **Topic-content parsing fidelity.** `Get-AgentActionSettings.ps1` detects
  action nodes and confirmation patterns with regular expressions over the
  selected `botcomponent.data` or legacy `content` payload. The exact `kind` values (`InvokeFlowAction`,
  `InvokeConnectorAction`, `InvokeSkillAction`, etc.) and the confirmation
  heuristics were exercised live on 2026-06-13 against a **synthetic** YAML
  topic fixture; parsing fidelity against **authentic in-product** Copilot
  Studio-authored Topic V2 content is still unproven and remains the PARTIAL gap.
  The fallback regex can recognize signatures in some malformed payloads and is
  not universal semantic YAML validation. Node schemas can change and are not
  publicly versioned.
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

**Lab-ready, offline-regression-validated PARTIAL.** All scripts parse/compile; the two functional
authentication defects (Purview evidence script and the MI runbook) and the schema column
mismatch are fixed and verified against authoritative Microsoft sources. The core scan path
and evidence export were aligned to the schema. The June 13 tenant leg supports the bounded
synthetic-fixture claims above, while the September 8 offline suite covers the corrected
Topic V2 query/payload behavior and fail-closed regressions without tenant access.
Coverage stays **PARTIAL**: authentic in-product Copilot Studio Topic V2 detection is not
yet proven. The remaining items are runtime-verification concerns (authentic-content parsing
fidelity and service availability), documented above rather than assumed.
