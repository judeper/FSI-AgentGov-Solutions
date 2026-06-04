# Changelog

All notable changes to this solution are documented in this file.

## [Unreleased]

### Fixed

- **Critical — Dataverse column names did not match the official `msdyn_botsession` schema.** The sync `$select`/`$filter`/`$orderby` and all session reads used `msdyn_sessioncreatedon`, `msdyn_sessionclosedon`, `msdyn_sessionoutcome`, and `msdyn_sessionoutcomereason`. Per the official entity reference (https://learn.microsoft.com/en-us/dynamics365/developer/reference/entities/msdyn_botsession) the attribute logical names are `msdyn_startedon`, `msdyn_endedon`, `msdyn_outcome`, and `msdyn_outcomereason` (the `msdyn_sessionoutcome*` strings are the *global choice* names, not column logical names). The prior names would cause Dataverse Web API `$select` to reject the query (HTTP 400). Corrected in `sync_dataverse_sessions.py`, `architecture.md`, `docs/dataverse-data-sources.md`, `docs/agent-assisted-hours-methodology.md`, `docs/viva-insights-parity-matrix.md`, and `tests/test_sync_dataverse_sessions.py`. The v1.1.1 change that aligned docs *to the script* propagated the script's incorrect names; this corrects both to the authoritative schema.
- **Critical — Session-outcome option-set integers were wrong.** `SESSION_OUTCOMES`/`SESSION_OUTCOME_REASONS` used the `192350001..192350004` / `192350100..192350106` series, which appears in no Microsoft entity reference. The documented values are `419550000` (none) / `419550001` (resolved) / `419550002` (escalated) / `419550003` (abandoned) for `msdyn_outcome`, and `419560000..419560008` for `msdyn_outcomereason`. With the old integers every outcome mapped to "Unknown" against real data. Maps and the `dataverse-data-sources.md` option-set tables corrected; the downstream KQL friendly-label contract (`Resolved`/`Escalated`/`Abandoned`/`Success`/`Failure`) is unchanged.
- **`msdyn_channelid` / `msdyn_conversationid` are not columns on `msdyn_botsession`.** Both were referenced in the `$select` and docs. `msdyn_botsession` exposes no channel column in its documented schema, so channel-derived `usageType` (Internal/External) is not derivable in Tier 1; the invalid columns were removed from the query, `usageType` now emits `"Unknown"`, and `classify_usage_type()` / docs note this Tier 2 limitation honestly.

### Notes

- This is a corrections-only change validated by static + authoritative-source review (no live tenant). Hard-coded option-set integers remain Microsoft-managed; operators should still verify against their environment's metadata. See `LAB-VALIDATION.md` for the full evidence report and cited sources.
- Maintainers cutting the next release should bump to **v2.0.3** across the root catalog files (`README.md`, `AGENTS.md`, `CLAUDE.md`, `.github/copilot-instructions.md`) and `manifest.yaml`.

## [2.0.2] - 2026-05-22

### Fixed

- **Major**: CSAT Trend Over Time visualisation in `workbooks/quality-metrics/workbook-template.json` projected `Date = timestamp` after `summarize ... by bin(SessionTime, 1d)`. The `timestamp` column does not survive the `summarize` operator, so the visualisation produced a runtime error or an empty Date column depending on the KQL engine version. Now projects `Date = SessionTime`. (council review M-1)
- **Major**: `config/config.schema.json` `environment_url` pattern only matched `*.dynamics.com`, rejecting US Gov, Germany, and China sovereign-cloud Dataverse URLs that `sync_dataverse_sessions.py` already validates and accepts. Pattern now mirrors the Python regex (`dynamics.com|dynamics.us|crm.dynamics.us|microsoftdynamics.de|crm.dynamics.cn`); examples updated. (council review M-2)
- **Minor**: Topic Trend (daily) and Completion Time Trend (P50/P95) visualisations in `workbooks/behavior-analysis/workbook-template.json` had the same `Date = timestamp` projection bug after `summarize ... by bin(SessionTime, 1d)`. Both now project `Date = SessionTime`. (council review m-2)
- **Minor**: AAH/Cost Savings weekly trend in `workbooks/business-impact/workbook-template.json` projected `Week = timestamp` after `summarize ... by bin(SessionTime, 7d)` — same root cause as M-1 / m-2; not in the council report but found while fixing the others. Now projects `Week = SessionTime`.

### Notes

- m-1 (workbook AAH formula simplification vs standalone KQL weighting) deferred — recommendation is a doc-note add; the discrepancy is intentional and already documented in the standalone KQL files. Will land with a workbook README refresh in a future minor.
- m-3 (`applicationinsights` Python SDK in maintenance mode) is informational; migration to `azure-monitor-opentelemetry` is already tracked in Known Limitations.
- m-4 (`prerequisites.md` GenerativeAnswers checklist wording) deferred — standalone doc rewording, not co-located with the workbook/schema fixes.
- m-5 (expand test coverage for watermark upsert, lock handling, classification) deferred — net-new test coverage is out of scope for this patch bump.

## [2.0.1] - 2026-05-04

### Fixed
- Updated KQL and workbook queries to support both classic Application Insights (`customEvents`/`timestamp`/`customDimensions`) and workspace-based Log Analytics (`AppEvents`/`TimeGenerated`/`Properties`) event schemas.
- Re-binned session analytics on `sessionClosedOn`/`sessionCreatedOn` with telemetry ingestion time as a fallback, and de-duplicated `CopilotSessionOutcome` rows by session ID to account for lookback-window re-emission.
- Refreshed validation and setup guidance for connection strings, managed identity-first authentication, Microsoft Copilot Dashboard in Viva Insights, and Microsoft 365 admin center Copilot usage reports.

## [2.0.0] - 2026-04-17

> **Breaking release.** Multiple math, code, and documentation corrections affect the values of every business-impact KQL query. Re-baseline dashboards before promoting; do not compare numbers across the v1.x → v2.0 boundary. See "Migration notes" below.

### Fixed (Critical)

- **AAH double-count math bug** — `queries/business-impact/autonomous-assisted-hours.kql`, `agent-assisted-cost.kql`, and `roi-trend.kql` previously summed `SuccessfulSessions × GenericActionMinutes` (all successful sessions) **plus** `SuccessfulWithoutActions × GenericTimeSavingMinutes`, double-counting every "Success without KS" session. Renamed and partitioned to `SuccessfulWithActions = countif(Outcome=="Success" and HasKS==true)` so the two buckets are disjoint, matching the methodology document.
- **Watermark table grew unboundedly** — `update_watermark()` always called `client.create_record()`, inserting a fresh row on every `InProgress` claim, every success, and every failure. Now performs a find-by-(`fsi_environmenturl`, `fsi_synctier`)-and-PATCH using a new `dataverse_client.update_record()` helper; only the very first sync per (env, tier) inserts.
- **`validate_telemetry.py` failed against ARM-resource-ID workspaces** — `LogsQueryClient.query_workspace()` requires a workspace GUID, but `config.schema.json` documented and accepted ARM resource IDs. Detection now routes ARM-format inputs through `LogsQueryClient.query_resource()` and GUID inputs through `query_workspace()`. `config.schema.json` accepts both formats explicitly.
- **`validate_telemetry.py` retried non-retryable HTTP errors** — Exponential backoff now triggers only on 429/500/502/503/504. 4xx auth/config errors surface immediately.

### Fixed (High)

- **Missing connection-string support** — `sync_dataverse_sessions.py` now accepts `APPLICATIONINSIGHTS_CONNECTION_STRING` (Microsoft's current recommendation) in addition to the legacy `APPINSIGHTS_INSTRUMENTATIONKEY`. ARM-API fallback prefers `component.connection_string` when available. Old env var still works but emits a deprecation warning. `config.example.yml` now documents both env vars.
- **Sovereign-cloud regex too narrow** — Environment-URL validation in `get_watermark()` only accepted `*.dynamics.com`. Now accepts US Gov (`*.dynamics.us`, `*.crm.dynamics.us`), Germany (`*.microsoftdynamics.de`), and China (`*.crm.dynamics.cn`) hosts.
- **Wrong column name in agent-classification docs and example queries** — `architecture.md`, `dataverse-data-sources.md`, and `README.md` said the autonomous filter should be `componenttypename eq 17`; that's the human-readable string. The actual filter (and what the code uses) is the integer `componenttype eq 17`. Docs now match the code; an explicit warning is included.
- **Wrong session-outcome integer values in docs** — `dataverse-data-sources.md` listed outcome values as `1/2/3/4`. The real Dataverse optionset values (and what the code reads) are `192350001..192350004` for `msdyn_sessionoutcome` and `192350100..192350106` for `msdyn_sessionoutcomereason`. Tables corrected.
- **Session-time-vs-send-time confusion in trends** — The Python `applicationinsights.TelemetryClient.track_event()` SDK ignores per-event timestamps and stamps `timestamp` at send time, so KQL trends were silently binning on sync-execution time, not session time. Sync now also emits `customDimensions['sessionCreatedOn']` and `customDimensions['sessionClosedOn']` so KQL/workbooks can re-bin via `extend SessionTime = todatetime(customDimensions['sessionClosedOn'])`. Architecture.md documents this and the SDK migration plan (azure-monitor-opentelemetry).
- **Knowledge-source detection over-claimed** — Previous docs and code comments described KS detection as a join with App Insights `GenerativeAnswers` events. The actual implementation is a `msdyn_topicname` substring heuristic (`generativeanswers`/`knowledge`). Code comments, methodology doc, architecture, README, and prerequisites now describe the heuristic honestly with under-/over-count caveats.
- **Tier 2 per-action multipliers presented as live** — `agent-assisted-hours-methodology.md` showed the per-action autonomous formula and a "$2,960 minutes" example as if implemented. The active KQL only uses the session-level Tier 1 form. Methodology now clearly separates the active Tier 1 formula from the planned Tier 2 formula and labels the example as illustrative.
- **Workbook period-over-period join** — `workbooks/business-impact/workbook-template.json` joined Current and Previous subqueries on `$left.CurrentSessions == $right.PreviousSessions` (joining by count value — wrong whenever the two periods have different counts). Replaced with a constant-key join (`extend JoinKey = 1`).
- **`sessions-per-action.kql` consumed an event the sync pipeline does not emit** — Added a prominent "Tier 2 — planned, not yet emitted" banner so operators don't expect rows.

### Fixed (Medium)

- **Viva Insights "equivalent" overclaim** — README and `viva-insights-parity-matrix.md` now describe CSA as a customizable, partial alternative, not a drop-in replacement, and remove the "Viva combines both types" autonomous-agent claim.
- **Tier 2 references in architecture.md** — `componenttypename` swapped for `componenttype` in classification logic and the AOF integration table; KS row reframed as planned correlation; AAH custom-dimensions table now documents `sessionCreatedOn`/`sessionClosedOn` and the `timestamp` caveat.
- **`InfoRetrievalTimeSaving` mismatch** — Methodology doc had 6 minutes in the parameter table but used 5 in the Tier 2 example. Example now uses 6 (totals updated).
- **Cost-tuning narrative outdated** — Cross-references the connection-string config and the dimension-based binning workaround.
- **Schema script missing `EntitySetName`** — `create_csa_dataverse_schema.py` now sets `EntitySetName: "fsi_csasyncwatermarks"` explicitly so generated docs and OData callers don't have to guess Dataverse's pluralization.

### Fixed (Low / Docs)

- Rewrote KS heuristic comment in `correlate_knowledge_sources()` with explicit limitations.
- Tightened ROI/SOX 404/FINRA 3110 mapping in `governance-queries.md` — added a global preamble noting that AAH/ROI/cost-savings queries are **management-reporting metrics** and supporting context only, not standalone regulator-grade evidence for SOX 404 automated-control effectiveness or FINRA 3110 supervision adequacy.
- Prerequisites checklist no longer claims a `GenerativeAnswers` event is required for Tier 1 KS detection.

### Added

- **`scripts/shared/dataverse_client.py.update_record(entity_set, record_id, data)`** — Cross-cutting PATCH helper that uses `If-Match: *` so missing rows raise 404 instead of accidentally upserting. Available to every solution that uses the shared client.

### Known Limitations

- **Sync lock race window** — `check_sync_lock()` is a read-then-write pattern. Two sync invocations starting within milliseconds can both pass the check before either claims the `InProgress` watermark. Operators should avoid co-scheduling sync runs to the same (env, tier); a future release will add ETag-based optimistic concurrency on the watermark row.
- **Trend bin times use send time, not session time, in KQL queries that have not yet been re-pointed at `customDimensions['sessionClosedOn']`.** This v2.0 release ships the dimension; updating each KQL/workbook tile to bin on it is staged for v2.0.x.
- **Non-idempotent sync** — Re-running sync within the lookback window can re-emit the same session. Workbooks should prefer `dcount(tostring(customDimensions['sessionId']))` over `count()` for accuracy. v2.x will add an emitted-session de-dupe table.
- **`applicationinsights` Python SDK is in maintenance** — Custom timestamps and several modern Application Insights features require migrating to `azure-monitor-opentelemetry`. Planned for v2.x.

### Migration notes

1. Set `APPLICATIONINSIGHTS_CONNECTION_STRING` (or keep the legacy `APPINSIGHTS_INSTRUMENTATIONKEY` to suppress nothing more than a deprecation warning).
2. Re-baseline any AAH / ROI / cost dashboards — autonomous-side numbers will drop because the double-counted bucket is removed.
3. Re-deploy the business-impact workbook ARM template to pick up the period-over-period join fix.
4. If you query the watermark table directly, expect a single row per (env, tier) going forward; old rows can be archived or deleted.

## [1.1.1] - 2026-04-15

### Fixed
- Updated dataverse-data-sources.md to v1.1.0 and aligned session column names (msdyn_startedon/msdyn_endedon → msdyn_sessioncreatedon/msdyn_sessionclosedon to match sync script)

## [1.1.0] - 2026-04-01

### Fixed
- **Data contract mismatch**: Workbook embedded KQL now uses `sessionOutcomeReason` (was `outcomeReason`) to match sync script output
- **Event timestamp**: Events now use session end time (`msdyn_sessionclosedon`) with fallback to start time, matching documented behavior
- **Watermark advancement**: Watermark now advances to the last session's timestamp instead of sync-start time
- **Instrumentation key exposure**: Verbose validation output now redacts the key
- **Stale documentation**: Prerequisites.md now references correct config keys and actual CLI flags

### Added
- **Concurrency protection**: Advisory lock via InProgress watermark status prevents parallel sync runs (30-min stale lock timeout)
- **Usage type classification**: Sync script now emits `usageType` (Internal/External) derived from channel ID, enabling workbook UsageType filters
- `classify_usage_type()` helper function for channel-based Internal/External classification
- `check_sync_lock()` function with stale-lock detection

### Changed
- Architecture.md updated to reflect actual sync flow (filter field, watermark semantics, failure handling)
- Tier 2 references across all documentation now clearly labeled as "planned for future release"
- Prerequisites validation commands updated to match actual `validate_telemetry.py` CLI flags
- Config key documentation aligned with actual config schema (`dataverse.environment_url`, not `dataverse_url`)

## [1.0.0] - 2026-02-24

### Added
- Dataverse session sync script (`sync_dataverse_sessions.py`) with Tier 1 support
- Dataverse watermark table schema script (`create_csa_dataverse_schema.py`) with --output-docs
- Telemetry validation script (`validate_telemetry.py`)
- KQL query library with 15 queries across 4 categories:
  - Agent Overview (3 queries): inventory, active trend, top agents
  - Session Outcomes (5 queries): conversational/autonomous outcomes, CSAT, resolution matrix
  - Business Impact (4 queries): conversational/autonomous AAH, cost, ROI trend
  - Behavior Metrics (3 queries): topics, actions (Tier 2 — planned), triggers/completion
- Azure Monitor Workbooks (4 workbooks, 14 tabs):
  - Agent Overview (3 tabs)
  - Quality Metrics (4 tabs)
  - Business Impact (3 tabs)
  - Behavior Analysis (4 tabs)
- Configuration with YAML config and JSON schema validation
- Governance mapping to Control 3.2 (Usage Analytics)
- Viva Insights parity matrix with honest assessment
- Agent Assisted Hours methodology documentation (conversational + autonomous formulas)
- Prerequisites documentation including transcript retention guidance
