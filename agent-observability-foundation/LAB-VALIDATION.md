# Lab-Readiness Validation — Agent Observability Foundation

> **Validation date:** 2026-06-04
> **Solution version at validation:** v1.2.3 (bumped from v1.2.2 as part of this pass)
> **Method:** Static validation — parse-validity, authoritative-source verification (Microsoft Learn), and documentation-completeness review. No live Azure tenant was used; runtime-only items are flagged explicitly.

## Purpose and controls

The Agent Observability Foundation (AOF) provisions an FSI-oriented telemetry pipeline for Microsoft Copilot Studio agents: workspace-based Application Insights + Log Analytics for operational queries, Azure Blob Storage (StorageV2, hierarchical namespace disabled) diagnostic-settings export for long-term audit retention, Azure Monitor workbooks, and scheduled-query alerts.

Mapped framework controls: **1.7** (Comprehensive Audit Logging), **2.8** (Access Control / Segregation of Duties), **2.9** (Agent Performance Monitoring), **3.2** (Usage Analytics). Target regulations referenced: SEC 17a-4, FINRA 4511/3110, SOX 302/404, OCC 2011-12 / SR 11-7, GLBA 501(b).

## What was checked

| Area | Result |
|------|--------|
| Python parse (`py_compile`) — `provision.py`, `teardown.py`, `verify_telemetry.py`, `verify_worm.py` | PASS (all compile) |
| PowerShell parse (`Parser::ParseFile`) — `deploy-alerts.ps1`, `deploy-workbooks.ps1` | PASS (0 errors) |
| JSON validity — alerts, action groups, workbooks, templates, config schema | PASS (all parse) |
| KQL schema correctness — 14 query files + 4 Power BI KQL views | PASS (see below) |
| Deployment ARM API versions | PASS (current/valid, see below) |
| RBAC built-in role definition IDs (`provision.py`) | PASS (well-known stable GUIDs) |
| Language rules (prohibited overclaim phrases per fsi-language-rules) | PASS (0 hits outside CHANGELOG) |
| Manifest/catalog drift (`build-manifest.py --check`) | PASS after regeneration |
| MkDocs `--strict` build | PASS (exit 0; no AOF-related link warnings) |

## Authoritative sources cited

1. **Copilot Studio → Application Insights telemetry schema** (event names, custom dimensions):
   - https://learn.microsoft.com/dynamics365/guidance/resources/copilot-studio-appinsights
   - Confirms event names `BotMessageSend`, `BotMessageReceived`, `GenerativeAnswers`, `TopicStart`/`TopicEnd`, `Action`, `Custom Telemetry`, and custom dimensions `recipientId`, `recipientName`, `fromName`, `fromId`, `channelId`, `designMode`/`DesignMode`, `conversationId`, `TopicName`, `text`, `Kind`, `type`, `Result`, `Message`, `Summary`, `session_Id`, `user_Id`.
2. **Application Insights table mapping (classic → workspace-based)**:
   - https://learn.microsoft.com/azure/azure-monitor/app/data-model-complete
   - https://learn.microsoft.com/azure/azure-monitor/reference/tables/appevents
   - Confirms `customEvents` → `AppEvents`, field `name` → `Name`, `customDimensions` → `Properties`, with `TimeGenerated`. This is exactly the normalization the query library performs via `union isfuzzy=true`.
3. **Azure Monitor diagnostic export — storage container naming**:
   - https://learn.microsoft.com/azure/azure-monitor/essentials/resource-logs#azure-storage
   - Confirms one container per enabled log category, named `insights-logs-{log category name}`.
4. **Deployment ARM API versions**:
   - Workbooks `Microsoft.Insights/workbooks@2023-06-01` — https://learn.microsoft.com/azure/templates/microsoft.insights/2023-06-01/workbooks
   - Scheduled query rules `Microsoft.Insights/scheduledQueryRules@2023-12-01` — https://learn.microsoft.com/azure/templates/microsoft.insights/2023-12-01/scheduledqueryrules
   - Action groups `Microsoft.Insights/actionGroups@2023-01-01` — https://learn.microsoft.com/azure/templates/microsoft.insights/2023-01-01/actiongroups
   - All present in the Learn template version index and current.
5. **Azure built-in roles** (RBAC GUIDs in `provision.py`):
   - https://learn.microsoft.com/azure/role-based-access-control/built-in-roles
   - Monitoring Reader, Storage Blob Data Reader, Log Analytics Reader/Contributor GUIDs match.

## Gaps found and fixes applied

### 1. WORM audit coverage targeted the wrong container (Critical — fixed)

`templates/diagnostic-settings.json` enables four Application Insights log categories: `AppTraces`, **`AppEvents`**, `AppRequests`, `AppExceptions`. Per the Microsoft Learn container-naming convention, diagnostic export creates one container per category (`insights-logs-{category}`), and immutability (WORM) policies in Azure Blob Storage are scoped **per container**.

The primary Copilot Studio audit-of-record telemetry — `BotMessageSend`, `BotMessageReceived`, `GenerativeAnswers` and the topic/action events that the entire KQL query library consumes — is the **AppEvents** category, which exports to **`insights-logs-appevents`**. However, `docs/worm-configuration.md` and `scripts/verify_worm.py` treated `insights-logs-apptraces` as the sole/primary container. An administrator following the guide verbatim would lock WORM on `insights-logs-apptraces` while leaving the audit-of-record `insights-logs-appevents` container unprotected — a books-and-records gap relative to SEC 17a-4(f) / FINRA 4511.

**Fix:**
- `docs/worm-configuration.md` — added a "Which containers must be protected" section enumerating all four export containers, identifying `insights-logs-appevents` as the primary audit-of-record container, and directing the admin to apply the time-based immutability policy (with `allowProtectedAppendWrites` enabled) and run `verify_worm.py` **once per container**, starting with `insights-logs-appevents`. Updated the Prerequisites and Verification sections accordingly, with a Microsoft Learn citation for the container-naming convention.
- `scripts/verify_worm.py` — docstring updated to use `insights-logs-appevents` as the primary worked example and to document the per-container scope. The config default container value was intentionally left as `insights-logs-apptraces` for backward compatibility; the documentation now makes the per-container requirement explicit.
- `.ralph-config.json` — added a domain fact recording the per-category container model and that `insights-logs-appevents` is primary.

### 2. Version + changelog provenance

Bumped solution to **v1.2.3**, added a CHANGELOG entry, updated the solution README version section/footer, and updated catalog tables (`AGENTS.md`, `.github/copilot-instructions.md`). Regenerated manifest-driven artifacts (`solutions.json`, root `README.md`, `DEPLOYMENT-GUIDE.md`, `site-docs/solutions/index.md`, `agent-observability-foundation/controls-covered.json`) via `scripts/build-manifest.py`; `--check` is clean. `manifest.yaml` was edited only for the version bump.

## KQL validation detail

All 14 query files and the Power BI KQL views use a single consistent normalization block (`let AgentEvents = materialize(union isfuzzy=true (AppEvents …)(customEvents …))`) with defensive `column_ifexists(...)` and `todynamic(...)` projection. Event names and custom-dimension keys consumed by the queries (`recipientId`, `session_Id`, `designMode`/`DesignMode`, `conversationId`, `fromName`, `TopicName`, `text`, etc.) all match the authoritative Copilot Studio telemetry schema. The DesignMode test-canvas exclusion correctly coalesces both `DesignMode` and `designMode` casings, matching the inconsistent casing in Microsoft's own documentation examples.

## Runtime-only caveats (cannot be confirmed without a live tenant)

- **`duration` custom dimension** (`queries/performance/latency-distribution.kql`, `slow-query-detection.kql`): not enumerated in the published Copilot Studio custom-dimension table. The query is defensively coded (`todouble(...)` + `where isnotnull(DurationMs)`), so absence yields empty results rather than an error. Confirm the field is emitted in your tenant before relying on latency percentiles.
- **RAI / content-safety dimensions** (`XPIADetected`, `JailbreakDetected`, `ContentFilterResult` in `rai-content-filtering-detection.kql`; `FeedbackScore`/`FeedbackText` in `generative-answers-telemetry.kql`): not part of the documented Copilot Studio telemetry schema. These are Microsoft Purview / RAI adjacencies surfaced "if available"; the query header already labels Control 1.6 as an informational adjacency (Purview delivers DSPM for AI, not AOF). Queries are defensively filtered and will not error if the fields are absent.
- **Application Insights / Log Analytics retention of 730 days, diagnostic-export landing, workbook resource binding** (`.ralph-config.json` notes the `applicationInsightsId`/`sourceId` post-deployment binding step): require a live deployment to confirm.
- **Dynamic-threshold alert baselines** require 10–14 days of telemetry before activation (documented in README/alert guide).
- **WORM immutability is irreversible once locked** — must be applied manually per `docs/worm-configuration.md`; not automated by design.

## Lab-readiness assessment

**Lab-ready.** All scripts, templates, and KQL parse cleanly and align with authoritative Microsoft Learn schemas and current ARM API versions. Deployment guidance is complete (provision → verify → deploy workbooks/alerts → WORM). The one material correctness gap found — WORM coverage of the primary audit-of-record container — has been fixed in documentation and verifier guidance. Remaining open items are runtime-only confirmations that require a live tenant and are listed above as caveats.
