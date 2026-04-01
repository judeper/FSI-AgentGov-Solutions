# Changelog

All notable changes to this solution are documented in this file.

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
