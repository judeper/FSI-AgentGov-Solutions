# Lab Validation Report — Copilot Studio Analytics

> **Scope:** Static, authoritative-source validation of the `copilot-studio-analytics`
> solution for a lab-ready steady state. No live tenant was available, so this report
> covers parse-validity, authoritative-source verification of every external API/schema
> claim, documentation completeness, and corrections applied. Runtime-only behaviors are
> called out explicitly.
>
> **Date:** 2026-06-04 · **Solution version:** v2.0.2 (corrections staged under `[Unreleased]`)
> **Primary control:** 3.2 — Usage Analytics and Activity Monitoring

## 1. Purpose & Controls

Copilot Studio Analytics (CSA) syncs Copilot Studio session outcomes from Dataverse
(`msdyn_botsession`) into Application Insights as `CopilotSessionOutcome` custom events,
and ships a KQL query library plus Azure Monitor Workbooks for session-outcome, CSAT,
Agent Assisted Hours (AAH), and ROI analytics. It supports **Control 3.2** (business-impact
analytics) and contributes supporting context to FINRA 3110, SOX 404, and OCC 2011-12
management reporting (not standalone regulator-grade evidence — see `queries/governance-queries.md`).

## 2. What Was Checked

| Area | Method | Result |
|------|--------|--------|
| Python scripts parse | `python -m py_compile` on all 3 scripts | ✅ Pass |
| Unit tests | `pytest tests/` | ✅ 3 passed |
| Dataverse column names | Cross-checked every `$select`/`$filter`/read against the official `msdyn_botsession` entity reference | ❌ → ✅ Fixed (see §4) |
| Option-set integer values | Cross-checked `SESSION_OUTCOMES`/`SESSION_OUTCOME_REASONS` against entity reference | ❌ → ✅ Fixed (see §4) |
| KQL schema (classic + workspace) | Verified `customEvents`/`timestamp`/`customDimensions` and `AppEvents`/`TimeGenerated`/`Name`/`Properties` | ✅ Correct |
| KQL `summarize`/`bin` projection bug | Grepped all queries + workbook templates for `X = timestamp` after `summarize` | ✅ None remain (v2.0.2 fixed; trend queries correctly project `Timestamp = SessionTime`) |
| Agent classification (`componenttype = 17`) | Verified against `botcomponent` entity reference | ✅ Code correct; wording already honest |
| Auth / token audience | Reviewed managed-identity-first auth + Dataverse scope | ✅ Correct (scope = environment URL `/.default`) |
| SDK status | `applicationinsights` (maintenance) vs `azure-monitor-opentelemetry`; `LogsQueryClient.query_workspace`/`query_resource` | ✅ Consistent with docs |
| Language rules | Grepped for the FSI-prohibited compliance-absolute phrases (per `fsi-language-rules.instructions.md`, excluding CHANGELOG history) | ✅ Zero hits |
| PowerShell parse | N/A — solution contains no `.ps1` files | — |

## 3. Authoritative Sources Cited

1. `msdyn_botsession` table/entity reference (column logical names + option-set integers):
   https://learn.microsoft.com/en-us/dynamics365/developer/reference/entities/msdyn_botsession
2. `botcomponent` table/entity reference (`componenttype` choices; value 17 = "External Trigger"):
   https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/botcomponent
3. Azure Monitor Logs standard columns (`Timestamp` for classic vs `TimeGenerated` for workspace):
   https://learn.microsoft.com/en-us/azure/azure-monitor/logs/log-standard-columns
4. `AppEvents` table reference (`TimeGenerated`, `Name`, `Properties`):
   https://learn.microsoft.com/en-us/azure/azure-monitor/reference/tables/appevents
5. Kusto `summarize` operator (result keeps only `by` columns + aggregates):
   https://learn.microsoft.com/en-us/kusto/query/summarize-operator
6. Copilot Studio + Application Insights telemetry events (`BotMessageSend`/`BotMessageReceived`/`GenerativeAnswers`):
   https://learn.microsoft.com/en-us/dynamics365/guidance/resources/copilot-studio-appinsights
7. `LogsQueryClient` (`query_workspace` vs `query_resource`):
   https://learn.microsoft.com/en-us/python/api/azure-monitor-query/azure.monitor.query.logsqueryclient
8. Dataverse OAuth scope (`<environment-url>/.default`):
   https://learn.microsoft.com/en-us/power-apps/developer/data-platform/authenticate-oauth
9. App Insights classic SDK retirement / OpenTelemetry migration direction:
   https://learn.microsoft.com/en-us/previous-versions/azure/azure-monitor/app/classic-api
10. `Get-AzAccessToken` SecureString default (context for repo auth standard):
    https://learn.microsoft.com/en-us/powershell/module/az.accounts/get-azaccesstoken

## 4. Gaps Found & Fixes Applied

### 4.1 🔴 Critical — Wrong Dataverse column logical names
The sync read sessions via `msdyn_sessioncreatedon`, `msdyn_sessionclosedon`,
`msdyn_sessionoutcome`, `msdyn_sessionoutcomereason`. The official `msdyn_botsession`
entity reference shows the attribute **logical names** are `msdyn_startedon`,
`msdyn_endedon`, `msdyn_outcome`, `msdyn_outcomereason`. The `msdyn_sessionoutcome*`
strings are the **global choice (option set) names**, not column identifiers. A Dataverse
Web API `$select` on a non-existent property returns HTTP 400, so the pipeline would fail
on the first fetch in any real environment.

**Root cause:** the CHANGELOG `[1.1.1]` entry aligned the docs *to the sync script* rather
than to the schema, propagating the script's incorrect names. Two prior council reviews
validated script↔doc internal consistency but never compared against the external Microsoft
schema — exactly the gap this validation targeted.

**Fix:** corrected `scripts/sync_dataverse_sessions.py` (`fetch_sessions` select/filter/orderby,
`get_session_created_timestamp`, `get_session_effective_timestamp`, `transform_session`),
the test fixtures, and all four docs.

### 4.2 🔴 Critical — Wrong option-set integers
`SESSION_OUTCOMES` used `192350001..192350004` and `SESSION_OUTCOME_REASONS` used
`192350100..192350106`. Neither series exists in the Microsoft entity reference, which
documents `419550000..419550003` for `msdyn_outcome` and `419560000..419560008` for
`msdyn_outcomereason`. With the old integers, **every** outcome would map to `"Unknown"`
against live data, zeroing out all outcome-dependent analytics.

**Fix:** replaced both maps with the documented values; preserved the capitalized
friendly labels (`Resolved`/`Escalated`/`Abandoned`) that the KQL data contract depends on.
`419550000` ("none") maps to `Unengaged` to preserve existing downstream semantics.
Updated the option-set tables in `docs/dataverse-data-sources.md`.

### 4.3 🟡 Medium — Non-existent channel/conversation columns
The `$select` and docs referenced `msdyn_channelid` and `msdyn_conversationid`, which are
**not** columns on `msdyn_botsession` (no channel column exists in the documented schema).
Including them would also cause a 400. `usageType` (Internal/External) therefore cannot be
derived in Tier 1.

**Fix:** removed the invalid columns from the query; `classify_usage_type()` now returns
`"Unknown"` when no channel data is present (instead of silently labeling everything
`"Internal"`); the transform emits `usageType = "Unknown"`; code comments and docs note that
channel-based usage typing is planned for Tier 2 (transcript parsing).

### 4.4 ✅ Verified-correct (no change)
- KQL classic/workspace dual-schema union, `summarize`/`bin` projections, and the v2.0.2
  `Timestamp = SessionTime` fixes are all correct.
- `botcomponent.componenttype = 17` = "External Trigger"; the existing code/README wording
  ("External Trigger / Event-Driven … integer `componenttype`, not `componenttypename`") is
  accurate. Note this counts trigger-definition components as an autonomous-agent proxy.
- Managed-identity-first auth, Dataverse `/.default` scope, and `LogsQueryClient`
  workspace-vs-resource routing match Microsoft guidance.

## 5. Runtime-Only Caveats (cannot be verified statically)

- **Option-set integers are environment-dependent.** Microsoft manages these values and may
  renumber them across Copilot Studio releases. Operators should confirm via
  `GET …/EntityDefinitions(LogicalName='msdyn_botsession')/Attributes(LogicalName='msdyn_outcome')/Microsoft.Dynamics.CRM.PicklistAttributeMetadata?$expand=OptionSet`.
- **Standalone vs Customer Service schema.** The `msdyn_botsession` reference is documented in
  the Dynamics 365 developer reference (Customer Service / Omnichannel context). Standalone
  Copilot Studio provisions the same managed table, but a runtime metadata check is still the
  authoritative confirmation for a given tenant.
- **`TelemetryClient.track_event` send-time stamping** (the reason KQL re-bins on
  `customDimensions['sessionClosedOn']`) is an SDK behavior asserted by the code; not
  independently documented by Microsoft, but consistent with the maintenance status of the
  `applicationinsights` package. Migration to `azure-monitor-opentelemetry` remains the
  documented remediation.
- **Copilot Studio standalone App Insights event names** (`BotMessageSend`, etc.) are
  confirmed in the Dynamics 365 Customer Service guidance; a dedicated standalone Copilot
  Studio event-schema page was not locatable on Microsoft Learn at validation time.

## 6. Lab-Readiness Assessment

**Verdict: Lab-ready (corrected).** Before this validation the solution would have failed at
the first Dataverse fetch (HTTP 400 from invalid `$select` columns) and produced all-`Unknown`
outcomes even if the query had succeeded. With the column-name and option-set corrections, the
sync's documented data contract now matches the authoritative `msdyn_botsession` schema, and
the KQL/workbook layer (which consumes only the emitted `customDimensions`) is unaffected and
verified. Remaining items are runtime-only confirmations (§5), appropriate for a tenant smoke
test rather than static review.
