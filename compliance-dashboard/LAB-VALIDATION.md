# Compliance Dashboard — Lab Validation Report

> **Scope:** Static (no live tenant) lab-readiness validation of the `compliance-dashboard`
> solution (v1.0.5). Validation = parse-validity + authoritative-source verification +
> documentation completeness. Runtime behaviors that require a Dataverse environment,
> Exchange Online tenant, or Power BI capacity are flagged as runtime-only caveats.

## Purpose & Controls

Aggregated compliance reporting across the 78-control FSI Agent Governance Framework
baseline, surfaced through a Power BI dashboard over Dataverse, with optional Exchange
Online evidence collection. Primary framework controls: **3.3, 3.1, 3.2, 3.4**
(monitoring / reporting pillar). Supports internal reporting referenced for **SOX §404**
ICFR monitoring, **FINRA Rule 3120(a)(1)** supervisory control reporting, and
**OCC Bulletin 2011-12 / FRB SR 11-7** model-risk governance where applicable.

## What Was Checked

| Area | Method | Result |
|------|--------|--------|
| Python scripts (`create_cd_dataverse_schema.py`, `load_sample_data.py`) | `python -m py_compile` | Pass (exit 0) |
| PowerShell collector (`Get-ExchangeComplianceData.ps1`) | `Parser::ParseFile` | Pass (0 errors) |
| Schema doc drift | `create_cd_dataverse_schema.py --output-docs` + `git status` | No drift |
| Language rules | grep for the four prohibited compliance-overclaim phrases (excl. CHANGELOG) | 0 hits |
| Dataverse column logical names | Cross-checked OData/DAX/flow refs against `create_cd_dataverse_schema.py` | Consistent |
| Option-set values (1-6 vs 100000000+) | Cross-checked schema, DAX, sample data, loader, deployment checklist | Consistent + explicitly caveated |
| CLI flags in docs (`--export`, `--force`, `--controls-only`, `--assessments-only`) | Cross-checked against argparse | All exist |
| Exchange/Graph API endpoints & permissions | Microsoft Learn (authoritative) | Verified; 1 correction made |
| Power BI DAX functions | Reviewed against standard DAX surface | Valid |

## Authoritative Sources Cited

1. **mailboxSettings `userPurpose`** — confirms `userPurpose` is a real property with
   value `shared` (also `user`, `linked`, `room`, `equipment`, `others`).
   https://learn.microsoft.com/graph/api/resources/mailboxsettings?view=graph-rest-1.0
2. **Security alerts (alerts_v2)** — confirms `GET https://graph.microsoft.com/v1.0/security/alerts_v2`
   is the GA v1.0 List alerts endpoint, and `SecurityAlert.Read.All` is the current
   (non-legacy) read permission.
   https://learn.microsoft.com/graph/api/security-list-alerts_v2?view=graph-rest-1.0
   https://learn.microsoft.com/graph/api/resources/security-api-overview?view=graph-rest-1.0
3. **Microsoft 365 Copilot usage report** — confirms `getMicrosoft365CopilotUserCountSummary`
   is **beta-only** (`graph-rest-beta`); HTTP request is
   `GET https://graph.microsoft.com/beta/copilot/reports/getMicrosoft365CopilotUserCountSummary`.
   No v1.0 variant exists as of 2026-Q2. `/beta` APIs are documented as "subject to change…
   not supported" for production.
   https://learn.microsoft.com/graph/api/reportroot-getmicrosoft365copilotusercountsummary?view=graph-rest-beta
4. **Office 365 active user detail report** — `getOffice365ActiveUserDetail` is GA on v1.0
   `/reports/` with `Reports.Read.All`.
   https://learn.microsoft.com/graph/api/reportroot-getoffice365activeuserdetail?view=graph-rest-1.0

## Gaps Found & Fixes Applied

### 1. Copilot usage report endpoint mislabeled as v1.0 (doc accuracy) — FIXED
`README.md` ("Microsoft Learn 2026-Q2 integration notes") and `docs/flow-configuration.md`
(CD-EvidenceCollector → "Microsoft 365 usage reports (Graph)") asserted that
`getMicrosoft365CopilotUserCountSummary` is served from a v1.0 `/copilot/reports/...`
path and that beta endpoints "should not be used." Authoritative Microsoft Learn shows the
opposite: the Copilot usage report APIs exist **only under `/beta`** today. The inline
`GET` sample and surrounding guidance were corrected to use the beta path and to label
Copilot usage signals as preview (subject to change, unsupported for production), while
keeping `getOffice365ActiveUserDetail` on its correct v1.0 path. This source is in the
**planned, not-yet-implemented** `CD-EvidenceCollector` flow design, so the fix is
documentation-only with no script impact.

### 2. Notification env-var naming inconsistency (doc consistency) — FIXED
`docs/deployment-checklist.md` referenced `CD_NotificationEmail`; `docs/flow-configuration.md`
uses the publisher-prefixed schema name `fsi_CD_NotificationEmail`. Aligned the checklist to
`fsi_CD_NotificationEmail`.

### Items Verified as Already Correct (no change needed)
- **`Get-ExchangeComplianceData.ps1`** uses `Invoke-MgGraphRequest` (not a raw token),
  honors `Retry-After` on 429/503, paginates `@odata.nextLink`, supports sovereign-cloud
  base URLs, and disconnects in `finally`. Auth is certificate-based app-only or
  interactive — no client secret. Required scopes match `docs/prerequisites.md`.
- **`mailboxSettings/userPurpose eq 'shared'` $filter** on `/users` is best-effort: the
  property is real, but server-side filtering of mailboxSettings across the `/users`
  collection is not guaranteed. The script already wraps it in try/catch with a
  documented disabled-account fallback (consistent with `.ralph-config.json`).
- **Option-set integer values (1-6)** are used consistently across schema, DAX, sample
  data, and loader, with prominent deployment warnings that the maker-portal default of
  100000000+ must be overridden. `fsi_cd_evidencetype = 5` (Test Result) is intentionally
  coupled to `cross-solution-integration`.
- **DAX measures** use only standard functions (`CALCULATE`, `DATESINPERIOD`, `EOMONTH`,
  `DATEADD`, `DATESYTD`, `SUMMARIZE`, `ADDCOLUMNS`, `ALLEXCEPT`, `DATATABLE`). Lookup
  columns correctly referenced via `_<schemaname>_value`; `PillarDimension` counts
  (29/26/14/9 = 78) match the shipped sample.
- **`load_sample_data.py`** uses `DefaultAzureCredential` first with a clearly marked
  legacy client-secret fallback; documents the unimplemented lookup-binding limitation.

## Runtime-Only Caveats (cannot be validated statically)

- Server-side support for the `mailboxSettings/userPurpose` and `assignedLicenses/$count`
  advanced-query filters depends on tenant/directory state; exercise the fallback paths.
- `category eq 'DataLossPrevention'` filtering on `alerts_v2` depends on the connected
  Defender/Purview detection sources; the script already degrades gracefully on failure.
- Power BI requires the option sets to be created with explicit integer values (1-6) — an
  authoring step that cannot be verified without a live environment.
- The `CD-EvidenceCollector` flow remains **planned / not shipped**; Exchange and other
  evidence must be imported manually until it exists.
- `load_sample_data.py` `--assessments-only`/`--export` POST path for assessments and
  exceptions requires lookup-binding work (documented in-script) before it will be
  accepted by Dataverse.

## Lab-Readiness Assessment

**Lab-ready.** Scripts parse cleanly, documentation is complete and internally consistent,
and the data-source/API guidance now matches authoritative Microsoft Learn references after
the one substantive correction (Copilot usage report API version). Remaining limitations are
clearly documented, intentional, or runtime-only. A deploying admin can follow the
deployment checklist to a working dashboard, with the noted manual steps (option-set integer
values, manual evidence import, lookup-binding for assessment loads).

---

*Validated against framework version v1.6.0 · Solution v1.0.5*
