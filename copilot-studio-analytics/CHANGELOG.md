# Changelog

All notable changes to this solution are documented in this file.

## [1.0.0] - 2026-02-24

### Added
- Dataverse session sync script (`sync_dataverse_sessions.py`) with Tier 1 support
- Dataverse watermark table schema script (`create_csa_dataverse_schema.py`) with --output-docs
- Telemetry validation script (`validate_telemetry.py`)
- KQL query library with 15 queries across 4 categories:
  - Agent Overview (3 queries): inventory, active trend, top agents
  - Session Outcomes (5 queries): conversational/autonomous outcomes, CSAT, resolution matrix
  - Business Impact (4 queries): conversational/autonomous AAH, cost, ROI trend
  - Behavior Metrics (3 queries): topics, actions (Tier 2), triggers/completion
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
