# Lab-Readiness Validation — message-center-monitor

> **Scope:** Static, no-live-tenant validation pass — parse-validity, authoritative
> Microsoft-source verification of the Microsoft Graph Message Center integration,
> unit-test execution, and documentation completeness. No customer or lab tenant was
> contacted during this validation.
>
> **Date:** 2026-06-04 · **Solution version:** v2.5.1 (`[Unreleased]` carries the POC
> + dry-run work) · **Validator:** automated lab-readiness pass.

---

## 1. Purpose and controls

`message-center-monitor` polls the Microsoft 365 Message Center through Microsoft Graph,
persists each post into the Dataverse table `fsi_messagecenterlog`, and (Phase 1) posts an
Adaptive Card to a Teams Workflows incoming webhook. It produces change-management evidence
for platform updates that could affect AI-agent deployments (Copilot Studio, Agent Builder).

- **Primary control (authoritative — `manifest.yaml`):** **2.3** (change-management evidence).
- **Regulatory framing (supports compliance with, not a guarantee):** FINRA Rule 4511 /
  3110, SEC Rule 17a-4, GLBA 501(b).
- **Note:** Control 2.10 was intentionally removed from the manifest in v2.4.0 as aspirational
  (this solution monitors changes; it does not patch). `manifest.yaml` (control `2.3` only) is
  authoritative; historical catalog tables may still list 2.10. See `.ralph-config.json` fact.

---

## 2. What was checked

| Area | Method | Result |
|---|---|---|
| PowerShell parse validity | `Parser::ParseFile` over every `*.ps1` in `scripts/` + `lab/` + `tests/` | 0 files with parse errors |
| Python compile | `python -m py_compile` on all `scripts/*.py` | 3/3 OK |
| Unit tests (PowerShell) | Pester 5.7.1 over `tests/` | **109 passed, 0 failed, 0 skipped** |
| Unit tests (Python) | pytest 9.0.3 over `tests/` | **13 passed** |
| Graph endpoint + permission | Microsoft Learn (see §3) | Verified |
| `$select` property names | Microsoft Learn `serviceUpdateMessage` resource | All 13 verified |
| Category / severity enum mappings | Microsoft Learn enums | Verified |
| Auth model | Source review of `Get-McmAccessToken` | Managed-identity-first; ClientSecret marked `# legacy: dev-only` |
| Dataverse column / option-set names | `.ralph-config.json` + `create_mcm_dataverse_schema.py` cross-check | Consistent |
| FSI language rules | grep for `ensures/guarantees/will prevent/eliminates risk` (excl. CHANGELOG) | 0 violations |
| Deprecated-API references | grep for `shared_http`, `/beta/`, retired O365 connectors | None misused; all are correct retirement callouts |

---

## 3. Authoritative sources cited

All API/permission/schema assertions below were verified against official Microsoft Learn
documentation (graph-rest-1.0):

1. **List serviceAnnouncement messages** —
   https://learn.microsoft.com/graph/api/serviceannouncement-list-messages?view=graph-rest-1.0
   - HTTP request: `GET /admin/serviceAnnouncement/messages` (**v1.0** — beta not required).
   - **Application** permission: **`ServiceMessage.Read.All`** (least-privileged; no higher
     option). Delegated also `ServiceMessage.Read.All`.
   - Supports OData query parameters (`$select`, `$filter` valid).
   - `Prefer: odata.maxpagesize={x}` — **max 1000**, default 100.

2. **serviceUpdateMessage resource type** —
   https://learn.microsoft.com/graph/api/resources/serviceupdatemessage?view=graph-rest-1.0
   - Confirmed every property used in the script's `$select`:
     `id, title, category, severity, services, startDateTime, endDateTime,
     lastModifiedDateTime, isMajorChange, actionRequiredByDateTime, body, tags, hasAttachments`.
   - `category` (`serviceUpdateCategory`): `preventOrFixIssue, planForChange, stayInformed,
     unknownFutureValue`.
   - `severity` (`serviceUpdateSeverity`): `normal, high, critical, unknownFutureValue`.

3. **Microsoft Graph permissions reference** (`ServiceMessage.Read.All`) — confirms the
   permission name and applicability used in `README.md` and `docs/setup-checklist.md`.

### Cross-check against the running script (`scripts/governance/Invoke-MessageCenterSync.ps1`)

- Graph URL (line 226): `https://graph.microsoft.com/v1.0/admin/serviceAnnouncement/messages?$select=…&$filter=lastModifiedDateTime ge {cutoff}` — **matches the authoritative endpoint and v1.0 namespace.**
- `Prefer: odata.maxpagesize=500` (line 233) — within the documented 1000 ceiling.
- Token scope (line 188): `https://graph.microsoft.com/.default` — correct client-credentials
  scope for the application permission `ServiceMessage.Read.All`.
- `categoryMap` (lines 271-275) and `severityMap` (lines 277-281) map the Graph enum strings to
  Dataverse choice integers; the Graph-side enum labels exactly match the authoritative enums.
- Pagination follows `@odata.nextLink` via `PSObject.Properties` probe (StrictMode-safe).

> **Caveat (cannot be statically verified):** the *non-alphabetical* Dataverse option-set
> integers (`100000000=High, 100000001=Normal, 100000002=Critical`) are a deliberate local
> mapping stamped into live rows — they are **not** a Graph contract and must not be "corrected."
> See `.ralph-config.json` and `AGENTS.md` §5. The map direction (Graph label → integer) in
> `Invoke-MessageCenterSync.ps1` was confirmed consistent with the schema script.

---

## 4. Gaps and fixes

**No code or documentation defects were found in this pass.** The solution has already been
through multiple council-review rounds and a 7-of-17-phase live dry-run (see `AGENTS.md` §3 and
`CHANGELOG.md` `[Unreleased]`), and the static surface is clean:

- Scripts: all parse; auth is managed-identity-first with the required `# legacy: dev-only`
  marker on the ClientSecret path; all HTTP routed through `Invoke-McmRest`; token audiences
  correct for both Graph (`graph.microsoft.com/.default`) and Dataverse (`{env}/.default`).
- Dependencies: `scripts/requirements.txt` pins `msal` + `requests`; PowerShell module
  prerequisites (`MSAL.PS` ≥ 4.37 for managed identity, `Az.KeyVault`, Pester 5) are documented
  and enforced by `Test-McmPrerequisites.ps1` (11 preflight checks).
- README: Purpose, deployment-path fork, Prerequisites, step-by-step Quick Start, Expected
  outcomes, Troubleshooting, and a "Microsoft Learn validation notes (2026-Q2)" block whose
  claims were independently re-verified here and found accurate.
- Language rules: 0 prohibited-phrase hits outside `CHANGELOG.md` history.

**Items deliberately *not* changed (owl-mode discipline):**

- `Test-McmPrerequisites.ps1` "stray `.Count`" (`AGENTS.md` Known Issue #4): reviewed
  (lines 788-816). The tally `.Count` accesses operate on `Where-Object` output and are
  PowerShell-7 scalar-`.Count`-safe; the exit-code logic is correct and Pester passes. No
  functional defect exists, so no change was made to avoid regressing a documented invariant.
- Option-set integers and the `fsi_assessedby` String type — protected invariants; left intact.

---

## 5. Runtime-only caveats (cannot be closed by static validation)

These require a live non-prod tenant and are tracked in `AGENTS.md` §3 "Phases pending":

- **Teams Workflows incoming webhook creation** (Phase 1.4 notification path) — manual Teams
  UI step; URL supplied at runtime via `-TeamsWebhookUrl` / `$env:MCM_TEAMS_WEBHOOK_URL`.
- **`lab/06` lab smoke + `lab/07` POC smoke** — end-to-end runs against a provisioned env.
- **Phase 3 Power Automate flow** — manual build per `docs/flow-configuration.md`
  (documentation-only by policy; no exported flow JSON ships in the repo).
- **Live Graph authorization / consent, alternate-key index activation, real upsert counts** —
  exercised only against a tenant; the dry-run log records 315 upserts + idempotent re-sync.

---

## 6. Lab-readiness assessment

**Verdict: LAB-READY for Phase 1 / Phase 2 (PowerShell sync + assessment + evidence export).**

- Static validation is fully green: all scripts parse, all 122 unit tests pass (109 Pester +
  13 pytest), and every Microsoft Graph assertion (endpoint, version, permission, resource
  properties, enum values, paging ceiling) is confirmed against authoritative Microsoft Learn
  documentation.
- The managed-identity-first auth model, Dataverse logical-name/option-set discipline, C1
  admin-owned-column invariant, and bearer-credential URL redaction are all present and
  test-enforced.
- Remaining work is **runtime-only** (Teams webhook creation, live smoke tests, optional
  Phase 3 flow build) and inherently cannot be completed without a tenant. Those steps are
  fully documented with a cross-machine resume runbook in `AGENTS.md`.

No corrective code changes were required; this report is the committed evidence artifact for
the lab-readiness pass.
