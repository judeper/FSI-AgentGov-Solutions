# Changelog

All notable changes to the Agent Observability Foundation are documented here.

## [1.1.0] — February 2026

### Added
- Azure Monitor Workbooks: Operational Health (4 tabs), Error Diagnostics (5 tabs), Usage Overview (5 tabs)
- Dynamic threshold alert rules: ALRT-01 (High Failure Rate), ALRT-02 (Latency Regression), ALRT-03 (Abnormal Usage)
- Zone-based notification routing via Teams and email through zone-specific action groups
- Alert deployment script (`deploy-alerts.ps1`) with 3-phase dependency ordering
- Workbook deployment script (`deploy-workbooks.ps1`) with idempotent re-deployment
- Alert tuning guide for dynamic threshold sensitivity and baseline period optimization
- Validation checklist for pre/post-deployment verification

## [1.0.1] — February 2026

### Added
- Agent usage workbook (`agent-usage-workbook.json`) migrated from FSI-AgentGov `src/`

## [1.0.0] — January 2026

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
