# Known Gaps and Live-Tenant Verification Items

This solution is **preview** because several data points still require verification against a live
tenant, and several upstream surfaces are themselves preview/beta. None of these block the
architecture; they affect specific collectors or mappings.

## Structural gaps (no current API closes these)

- **Per-agent end-to-end USD** is not attributable through supported public APIs. Azure Cost
  Management has no agent dimension; per-agent credit consumption is UI-export only. The report labels
  any per-agent figure as partial / heuristic / manual and never folds it into authoritative totals.
- **Identity correlation** between `copilot_package_id` ↔ `bot_id` ↔ `entra_agent_id` ↔ the PAYG CSV
  `Resource ID` ↔ the audit-log agent field is not exposed by any single supported API; cross-mapping
  is heuristic (display name / owner / environment).
- **Direct-tenant invoice line items** at credit/meter granularity are not available via Graph
  (`PartnerBilling.Read.All` is for CSP partner contexts).

## Items to verify on a live tenant

| Item | Affects | What resolves it |
|------|---------|------------------|
| Exact Azure meter names/IDs for Power Platform / Copilot Studio / Agent 365 | `normalize_cost_facts.py` meter filtering | Run a Cost Management query grouped by MeterId/Meter over a subscription with known usage |
| Whether `capacityAllocations` returns consumed vs allocated | preview PP collector | Live call with nonzero usage; inspect payload |
| Agent 365 `skuPartNumber` values ($15 standalone, E7 bundle) | license mapping | `GET /subscribedSkus` from a tenant with the SKUs assigned |
| Purview audit records-fetch endpoint + `CopilotInteraction` schema | beta audit collector | Run a query to completion; enumerate records and agent-identifying fields |
| Whether Agent 365 ACU consumption is a distinct Azure meter | cost coverage | Export Cost Management while generating known Agent 365 activity |
| Current GA api-version for PP licensing + Azure Cost Management | all collectors | Confirm against the published REST references at build time |

## Unit semantics

Copilot Studio "credits" and "messages" are different units depending on context and agent
complexity (a generative answer or agent action consumes more than one credit). The report documents
the unit and the configured unit price it used; it does not assume a fixed credit↔message ratio.
