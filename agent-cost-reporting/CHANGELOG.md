# Changelog

All notable changes to this solution are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project
adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0-preview] - 2026-06-16

### Added

- Initial preview scaffold for consolidated AI-agent cost/consumption reporting.
- `manifest.yaml` mapping controls 1.7, 3.1, 3.2 (monitoring-analytics, tier 2, preview).
- Decoupled architecture: per-surface collectors, a normalized cost-fact dataset, and a
  self-contained HTML evidence renderer (file-first; no Power Platform runtime artifacts).
- JSON schemas: `cost_fact.schema.json`, `manual_credit_import.schema.json`,
  `report_manifest.schema.json`.
- Auth helper stubs: `auth_arm.py` (managed-identity-capable), `auth_graph.py` (app-only),
  `auth_powerplatform.py` (service principal + Power Platform RBAC; managed identity is not
  supported for the Power Platform API).
- Collector stubs for Azure Cost Management (query + cost details), Microsoft Graph (usage reports +
  license inventory), the Power Platform API (billing policies + environments, and a feature-flagged
  preview capacity-allocation collector), a feature-flagged beta Purview audit-log collector, and a
  manual Copilot Credits CSV importer.
- Normalization (`normalize_cost_facts.py`) and identity/scope correlation
  (`correlate_identity_and_scope.py`) stubs.
- Renderer (`render_report.py` + `templates/report.html.j2`) and evidence packaging
  (`package_evidence.py`) stubs.
- Documentation: architecture, prerequisites, the per-surface API matrix, and known gaps.

### Notes

- Preview status reflects upstream preview/beta dependencies (Power Platform capacity allocations,
  Purview audit-log query API, Agent 365 APIs) and several data points pending live-tenant
  verification (exact Azure meter names, Agent 365 SKU part numbers, the audit-log records-fetch
  endpoint and `CopilotInteraction` schema).
- Per-agent end-to-end USD attribution is not available via supported public APIs and is documented
  as a control limitation rather than implemented.
