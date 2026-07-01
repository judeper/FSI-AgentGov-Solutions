---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P1, P4]
applicable_drivers:
  - ai_governance
  - technology_data
coe_function: optimize
---
# Agent Cost Reporting

> **Version:** v0.1.0-preview
> **Status:** Preview
> **Validated against framework version:** v1.6.0
> **Upstream Microsoft dependency:** Mixed — Azure Cost Management and Microsoft Graph usage/license APIs are GA; the Power Platform API is GA but delegated-only (service principal + RBAC, no managed identity); Power Platform capacity-allocation endpoints, the Purview audit-log query API, and Agent 365 APIs are preview/beta. Per-agent end-to-end USD is not attributable through supported public APIs today.

Consolidated, on-demand, point-in-time **cost and consumption evidence report** for AI agents
across the Microsoft stack. The solution collects from each available billing/usage surface,
normalizes everything into a single **cost-fact dataset**, and renders a **self-contained HTML
evidence artifact** that can be regenerated any time and archived for recordkeeping.

This solution is **preview** because several upstream surfaces are themselves preview/beta and a
number of data points still require live-tenant verification (see
[docs/known-gaps.md](docs/known-gaps.md)). It aids in meeting cost-benefit and recordkeeping
expectations under OCC 2011-12 / Fed SR 11-7, SOX 404, and FINRA 4511 / SEC 17a-4; it does not by
itself satisfy any regulation. Organizations should verify that the report meets their specific
obligations.

## Why this exists

AI-agent cost and consumption data is spread across several admin portals with **no single pane of
glass and no single supported public API** that yields end-to-end per-agent dollars. This solution
assembles what *is* programmatically available, clearly labels what is not, and produces an
auditable artifact rather than a live dashboard.

## Architecture (decoupled, three layers)

```
collectors/ ──▶ raw extracts ──▶ normalize/ ──▶ cost_facts.jsonl ──▶ render/ ──▶ report.html
   (per surface)                  (+ correlate)   (+ manifest + hash)            (+ evidence pkg)
```

1. **Ingestion** — one collector per surface, each writing a raw extract plus a provenance row.
2. **Normalized cost-fact dataset** — the durable asset: one normalized record set
   (`cost_facts.jsonl` / `.csv`) with per-row **provenance, confidence, and attribution status**.
   File-first by design (the repo does not ship Power Platform runtime artifacts); an optional
   Dataverse `fsi_costfact` table can be added later for operational querying.
3. **Renderer** — a self-contained HTML evidence report (Python + Jinja2, inline SVG charts, **no
   CDN**). Power BI is intentionally **not** the primary renderer; a secondary Power BI overlay is
   optional.

See [docs/architecture.md](docs/architecture.md) for the full data flow and the per-surface API
matrix in [docs/api-surface-matrix.md](docs/api-surface-matrix.md).

## Data surfaces

| Surface | What it provides | API status | Auth |
|---------|------------------|-----------|------|
| **Azure Cost Management** | Authoritative pay-as-you-go cost ($) by subscription / meter | GA | App-only / managed identity |
| **Microsoft Graph (usage + license)** | Copilot usage activity; seat inventory (no cost) | GA | App-only / managed identity |
| **Power Platform API** | billing-policy to environment to subscription join | GA (capacity = preview) | Service principal + Power Platform RBAC (no managed identity) |
| **Purview audit logs** | Per-agent Copilot interaction counts (supplementary) | Beta | App-only / delegated |
| **Manual Copilot Credits CSV** | Per-agent credit consumption (the gap) | UI export only | Admin portal |

## Control limitations (read before use)

- **Per-agent end-to-end USD is not attributable through supported public APIs.** Any per-agent
  cost shown is partial, heuristic, or sourced from a manually exported CSV, and is labeled as such.
- **Credit and message units differ** across surfaces; the report documents the unit mapping it used.
- **Azure budgets are alerts, not hard spending limits** on Enterprise Agreements.
- **Purview audit-log enrichment is beta** and is **not available in every cloud environment**;
  it is feature-flagged and degrades gracefully.
- The HTML format alone is not an approved recordkeeping format. Defensibility comes from immutable
  (WORM) storage, dataset hashing, and retention of the raw extracts alongside the report.
  Organizations should consult records-management counsel.

## Related controls

| Control | Title | How this solution helps |
|---------|-------|-------------------------|
| 1.7 | Audit Logging & Evidence | Produces a hashed, point-in-time cost evidence package with retained raw extracts. |
| 3.1 | Compliance Reporting | Consolidates multi-surface cost/consumption data into one report. |
| 3.2 | Usage Analytics & Activity Monitoring | Surfaces agent usage and consumption signals for cost-benefit review. |

Mappings should match the catalog in the repository root; see the framework control specifications
for authoritative definitions.

## Getting started

1. Review [docs/prerequisites.md](docs/prerequisites.md) and register the required identities.
2. Copy `config/config.example.json` and fill in tenant, subscription, and scope values.
3. Run the collectors (see [docs/architecture.md](docs/architecture.md) run order).
4. Run the normalizer, then the renderer.

> **Status note:** This is a preview scaffold. Collector data-shaping logic is stubbed where the
> exact response schema or meter names still require live-tenant verification — see
> [docs/known-gaps.md](docs/known-gaps.md). See the [CHANGELOG](CHANGELOG.md) for version history.
