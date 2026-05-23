# Changelog

All notable changes to the Agent Observability Foundation are documented here.

## [1.2.2] - 2026-05-22

### Fixed

- **Critical**: Removed stale "ADLS Gen2" terminology from `power-bi/kql-views/vw_dim_regulation_control.kql:113`; replaced with `BLOB-STORAGEV2` / `Azure Blob Storage (StorageV2, HNS disabled)` to match the actual storage type and the v1.1.1 terminology cleanup. (council review C-01)
- **Critical**: Removed Control 1.6 (DSPM for AI) mappings from `power-bi/kql-views/vw_dim_regulation_control.kql` (previously on GLBA-501b, RBAC-SEP, and PII-SANIT rows). AOF maps formally to controls 1.7, 2.8, 2.9, 3.2 per `.ralph-config.json` and `governance-mapping.md`; DSPM for AI is delivered by Microsoft Purview. (council review C-02)
- **Major**: Added `operation_Id` to the `AgentEvents` materialized view projection in `queries/compliance/flow-failure-correlation.kql` so the CorrelationId fallback at line 86 and the ConversationContext join at line 96 resolve against a real column instead of silently producing nulls. (council review M-01, m-02)
- **Major**: Added `operation_Id` to the embedded copy of the same `AgentEvents` block inside `workbooks/error-diagnostics/workbook-template.json` (Root Cause Analysis group, query-flow-failures tile). Without this fix the workbook tile would fail with a Kusto semantic error (`'operation_Id' could not be resolved`) on render. The other 10 embedded `AgentEvents` blocks in the same workbook do not consume `operation_Id` downstream and are intentionally left unchanged. (code-review SHIP-BLOCKER follow-up to council M-01)
- **Major**: Removed stale `{"GLBA-501b", "1.6"}` bridge row from `power-bi/semantic-model/tables/ControlRegulation.tmdl:52`. The TMDL bridge is a hard-coded parallel copy of the regulation→control mapping consumed by the `Regulatory Gaps` DAX measure (`power-bi/semantic-model/measures/CoreMetrics.tmdl:122-139`). Without this fix the Power BI report would continue to claim AOF delivers evidence for Control 1.6 even after the matching KQL fix in C-02. (code-review SHIP-BLOCKER follow-up to council C-02)
- **Major**: Removed stale Control 1.6 reference from `architecture.md:126` RBAC Separation section; the section now references only Control 2.8 (Access Control and Segregation of Duties). (council review M-02)
- **Major**: Bumped version strings in `workbooks/README.md` and `alerts/README.md` from 1.0.0 to 1.2.2 to match the solution version. (council review M-03)

### Changed

- **Minor**: Relabeled Control 1.6 in `queries/compliance/rai-content-filtering-detection.kql` header and `queries/governance-queries.md` cross-reference as an "informational adjacency" rather than primary/supporting evidence, to match the governance-mapping.md convention and the .ralph-config.json scope. Also dropped `1.6` from the Query Library Summary table at `queries/governance-queries.md:499` (compliance/ row) to align with the relabel earlier in the file. (council review m-01, code-review follow-up)
- **Minor**: Reverted `RBAC-SEP` / Control 2.8 evidence-type from "Primary" back to "Supporting" in `power-bi/kql-views/vw_dim_regulation_control.kql:115`. The Supporting→Primary change was applied alongside the disclosed C-02 1.6-row removal but was not itself part of the council recommendation; preserving the prior evidence-strength claim avoids an undisclosed audit-sensitive semantic change. (code-review follow-up)
- **Minor**: Refined four internal code comments in `scripts/provision.py` and `scripts/verify_worm.py` that referenced "ADLS Gen2" to instead describe StorageV2 with hierarchical namespace enabled, per .ralph-config.json terminology guidance. (council review m-04)
- **Minor**: Bumped Power BI README version footer from 1.2.0 to 1.2.2 to match the parent solution version. (council review m-07)

## [1.2.1] — 2026-Q2 Microsoft Learn refresh

### Fixed

- Bumped solution metadata to v1.2.1 for the Microsoft Learn 2026-Q2 refresh.
- Added normalized `AppEvents` / legacy `customEvents` KQL compatibility across query library files, Azure Workbooks, scheduled-query alerts, and `verify_telemetry.py`.
- Updated workbook ARM templates to `Microsoft.Insights/workbooks@2023-06-01`.
- Documented the currently supported preview status of `Microsoft.Insights/diagnosticSettings@2021-05-01-preview` in the diagnostic settings template metadata.
- Refreshed Copilot Studio telemetry setup, PII/property-bag guidance, retention notes, and managed-identity-first authentication guidance against Microsoft Learn 2026-Q2 documentation.

## [1.2.0] — 2026-04-17

### Breaking

- **`verify_worm.py` now fails when `allowProtectedAppendWrites` is disabled.** Previously the flag was printed but did not affect the exit code. A locked time-based immutability policy without protected append writes blocks Azure Monitor diagnostic export from landing new telemetry — silently halting the export pipeline while the storage account remains "immutable." Runs that previously returned exit code 0 with this flag disabled will now return exit code 2 (PARTIALLY COMPLIANT). See `docs/worm-configuration.md` Step 3 for the new requirement.
- **Power BI semantic-model `ZoneId` is now normalized to `Zone1`/`Zone2`/`Zone3`.** `vw_session_fact.kql` and `vw_dim_agent.kql` now map raw telemetry values (e.g. `"Zone 1 - Personal Productivity"`) to the canonical zone keys used by `DimZone.tmdl`. Existing Power BI reports filtered on the long-form labels need to be updated to the short keys.
- **`vw_event_fact.kql` UserId source changed.** Now reads `customDimensions["fromName"]` first (falls back to `from_Id`). Hash output for the same end user will differ from prior runs; downstream cohort analyses keyed on the hash are not directly comparable across the change.

### Critical Fixes

- **WORM container name corrected across docs and verifier docstrings.** `worm-configuration.md` and `verify_worm.py` examples referenced a `telemetry-export` container that does not exist. The actual telemetry-export container created by Azure Diagnostic Settings is `insights-logs-apptraces`, which is also the verifier's default. Following the prior steps with the wrong container would have left the real telemetry container unprotected.
- **WORM runbook now requires `allowProtectedAppendWrites`** (see breaking change above). Without this flag, locking the policy halts diagnostic export.

### Fixed

- **Stop logging the Application Insights InstrumentationKey** in `provision.py`. Previously partial-masked output (first-8 + last-4) was written to stdout, exposing enough entropy to be useful in a logs-leak scenario. Connection-string verbose output is also no longer written.
- **Provider-registration preflight added** to `provision.py`. On a net-new subscription with `Microsoft.Insights`, `Microsoft.OperationalInsights`, `Microsoft.Storage`, or `Microsoft.Authorization` unregistered, provisioning previously failed deep into the run with `NoRegisteredProviderFound`. Preflight now checks and auto-registers each required provider.
- **Governance mapping accuracy:** removed Control 1.6 (DSPM for AI) cross-references from primary/supporting tables. Per the catalog and `.ralph-config.json`, AOF maps formally to controls **1.7, 2.8, 2.9, 3.2** only. DSPM for AI is delivered by Microsoft Purview, not by AOF telemetry. Controls 1.3, 1.4, 2.6, 3.1 are now labeled as "informational adjacencies" rather than primary evidence.
- **WORM compliance-states table** in `worm-configuration.md` now includes the protected-append-writes condition and the retention-adequacy condition (previously implied any "Locked" state was SEC 17a-4(f) compliant).
- **Power BI documentation** corrected to reflect the **18 DAX measures** that actually ship in `CoreMetrics.tmdl` (previously claimed 19). Power BI README clarified that the 5-page dashboard is a *design blueprint* and not a shipped `.pbix`.
- **`ALRT-03-abnormal-usage.json`** KQL replaced `summarize SessionCount = dcount(session_Id) by AgentId | summarize TotalSessions = sum(SessionCount)` with a single `summarize TotalSessions = dcount(session_Id)`, removing per-agent double-counting and the unstable sum-of-HyperLogLog approximation.
- **README troubleshooting** entry for "no data after 90 days" rewritten to match actual `provision.py` behavior (Log Analytics workspace is created with `retention_in_days=730`; total retention defaults to match) instead of telling admins to also set `totalRetentionInDays=730`.
- **`@contoso.com`** placeholders replaced with `@example.com` (RFC 2606) across the alert shared-parameters and Power BI integration doc.

## [1.1.1] — 2026-04-15

### Fixed

- Security: removed instrumentation key logging from verify_telemetry.py (logged resource ID instead)
- architecture.md: replaced all "ADLS Gen2" references with "Azure Blob Storage (StorageV2, HNS disabled)" to match actual script requirements
- README: corrected Azure CLI minimum version from 2.50+ to 2.60+ (required by alert deployment)

## [1.1.0] — 2026-02-15

### Added
- Azure Monitor Workbooks: Operational Health (4 tabs), Error Diagnostics (5 tabs), Usage Overview (5 tabs)
- Dynamic threshold alert rules: ALRT-01 (High Failure Rate), ALRT-02 (Latency Regression), ALRT-03 (Abnormal Usage)
- Zone-based notification routing via Teams and email through zone-specific action groups
- Alert deployment script (`deploy-alerts.ps1`) with 3-phase dependency ordering
- Workbook deployment script (`deploy-workbooks.ps1`) with idempotent re-deployment
- Alert tuning guide for dynamic threshold sensitivity and baseline period optimization
- Validation checklist for pre/post-deployment verification

## [1.0.1] — 2026-02-10

### Added
- Agent usage workbook (`agent-usage-workbook.json`) migrated from FSI-AgentGov `src/`

## [1.0.0] — 2026-01-15

### Added
- Application Insights provisioning with 730-day retention for Copilot Studio telemetry
- Log Analytics workspace with 2-year interactive query capability (PerGB2018 pricing)
- Azure Blob Storage (StorageV2) diagnostic settings export for SEC 17a-4 long-term retention
- RBAC separation between operational monitoring and compliance audit paths
- KQL query library: 6 foundation queries, 5 compliance queries, 3 SR 11-7 model governance queries
- KQL governance views for query-to-control mapping
- Power BI semantic model for cross-workspace analytics
- Python deployment scripts: `provision.py`, `teardown.py`, `verify_telemetry.py`, `verify_worm.py`
- Configuration schema (`config.schema.json`) and example template (`config.example.yml`)
- PII sanitization guide, cost tuning guide, WORM configuration guide
- Architecture documentation with data flow diagrams and SoD boundaries
- Governance mapping of artifacts to FSI-AgentGov framework controls
