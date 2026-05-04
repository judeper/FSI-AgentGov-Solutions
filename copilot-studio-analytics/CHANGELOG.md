# Changelog

All notable changes to this solution are documented in this file.

## [Unreleased]

### Fixed

- Target version v2.0.1 for the Microsoft Learn 2026-Q2 refresh.
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
