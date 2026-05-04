# Viva Insights Parity Matrix

Honest assessment of Copilot Studio Analytics (CSA) feature coverage relative to Microsoft Viva Insights for Copilot Studio agent analytics.

## Overview

Microsoft Viva Insights provides built-in analytics for Copilot Studio agents as part of the Viva Insights license. CSA provides a **partial alternative** for organizations that do not have Viva Insights licenses or that need customizable metrics, zone-based governance, or regulatory reporting integration. CSA is **not a drop-in replacement** for Viva Insights — see the parity matrix below for items that have only "near", "substantial", or "limited" parity, and the "Viva-only" rows for capabilities CSA does not currently match.

This matrix documents what CSA covers, what it partially covers, and what remains Viva-only.

---

## Parity Matrix

| Viva Insights Feature | CSA Equivalent | Parity Status | Notes |
|-----------------------|---------------|---------------|-------|
| Agent inventory | KQL: Agent Inventory query + Agent Overview workbook | Near parity | CSA adds agent type classification (conversational/autonomous) |
| Active agent trend | KQL: Active Agent Trend query | Near parity | Same data source (msdyn_botsession), same calculation |
| Session volume | KQL: Top Agents by Volume query | Near parity | CSA correlates with native BotMessageSend events |
| Session outcomes (conversational) | KQL: Conversational Outcomes query | Near parity | Same msdyn_sessionoutcome data |
| Session outcomes (autonomous) | KQL: Autonomous Outcomes query | Near parity | CSA separates autonomous from conversational outcomes |
| CSAT distribution | KQL: CSAT Distribution query | Near parity | Same msdyn_csatscore source |
| Resolution rate | KQL: Resolution Matrix query | Near parity | CSA adds outcome weighting by agent type |
| Agent Assisted Hours (conversational) | KQL: Conversational AAH query | Substantial parity | CSA uses configurable multipliers vs Viva fixed calculation; Tier 1 KS proxy slightly less precise |
| Agent Assisted Hours (autonomous) | KQL: Autonomous AAH query | Substantial parity | CSA currently uses session-level estimates; per-action granularity planned for Tier 2 |
| Cost avoidance | KQL: Cost Avoidance query | Near parity | Same formula; CSA hourly rate is configurable |
| ROI trend | KQL: ROI Trend query | Substantial parity | CSA provides period-over-period; Viva shows running total |
| Topic performance | KQL: Topic Performance query | Partial parity | Tier 1 provides topic name from session data; full per-topic detail requires Tier 2 data *(planned)* |
| Action execution metrics | KQL: Action Execution query | Partial parity | Requires Tier 2 data *(planned — not yet implemented in sync pipeline)*; Viva has direct access |
| Trigger analysis | KQL: Trigger Analysis query | Partial parity | CSA derives from session patterns; full trigger telemetry requires Tier 2 *(planned)* |
| Maker-led time savings inputs | config.yml defaults | No parity | Viva allows per-topic/action maker estimates; CSA uses configurable defaults |
| Business outcome data upload | Not available | Viva-only | Custom business outcome correlation (e.g., case closure, sales) |
| Organizational hierarchy analytics | Not available | Viva-only | Department/team-level rollups based on org hierarchy |
| Manager dashboard | Not available | Viva-only | Pre-built manager view of team agent adoption |
| Copilot Studio embedded analytics | Not applicable | Viva-only | In-product analytics within Copilot Studio portal |

---

## Parity Status Definitions

| Status | Definition |
|--------|-----------|
| **Near parity** | CSA provides functionally equivalent analytics with minor differences in data source or presentation |
| **Substantial parity** | CSA provides the same core metric with meaningful differences in calculation method or precision |
| **Partial parity** | CSA provides the metric but with reduced precision or additional prerequisites (e.g., Tier 2 data planned but not yet implemented) |
| **No parity** | CSA provides a workaround but cannot match the Viva feature |
| **Viva-only** | Feature depends on Viva Insights infrastructure with no CSA equivalent available |

---

## When to Use Viva Insights

Viva Insights is the better choice when:

- **Quick adoption checks** -- Pre-built dashboards available immediately without deployment
- **Maker-led time savings inputs** -- Agent builders need to specify per-topic time savings estimates
- **Business outcome correlation** -- Organization wants to upload custom business outcomes (case closure rates, sales conversion) and correlate with agent usage
- **Organizational hierarchy** -- Analytics needed at department/team level based on org hierarchy
- **Manager self-service** -- Managers need pre-built views of their team's agent adoption
- **Embedded Copilot Studio analytics** -- Analytics needed directly within the Copilot Studio portal

## When to Use CSA

CSA is the better choice when:

- **No Viva Insights license** -- Organization does not have or cannot justify Viva Insights licensing costs
- **Regulatory reporting** -- Analytics need to be integrated with FSI-AgentGov compliance evidence (Control 3.2)
- **Zone-based governance** -- Analytics need to respect zone boundaries established by AOF infrastructure
- **Custom calculations** -- Organization needs full control over AAH multipliers, outcome weights, and cost parameters
- **Historical recalculation** -- Need to recalculate metrics with adjusted parameters retroactively
- **Unified telemetry platform** -- Want all agent analytics (operational + business impact) in a single Application Insights workspace
- **Autonomous agent analytics** -- Need a separate breakdown of autonomous-agent activity. Viva Insights does report on autonomous agents, but CSA's separate AAH formula and dedicated workbook section make the autonomous metrics easier to isolate and tune.
- **Custom workbooks** -- Need to extend or customize analytics dashboards beyond what Viva provides

## When to Use Both

Organizations with Viva Insights licenses may still benefit from CSA for:

- **Compliance evidence** -- CSA governance mapping ties analytics to Control 3.2 with documented evidence tiers
- **Custom KQL queries** -- CSA query library provides reusable queries for ad hoc analysis beyond Viva dashboards
- **Long-term trend analysis** -- CSA stores data in Application Insights with 730-day retention (AOF infrastructure)
- **Cross-solution correlation** -- CSA data in Application Insights can be correlated with AOF operational data

---

## Features That Are Viva-Only

These features depend on Viva Insights infrastructure and cannot be replicated by CSA.

### Maker-Led Inputs

Viva Insights allows agent makers (the people who build agents in Copilot Studio) to specify estimated time savings per topic or action. These estimates feed into the AAH calculation.

**Why CSA cannot replicate:** Maker-led inputs are stored in Viva Insights backend services. There is no public API to read or write these estimates, and the data is not exposed in Dataverse or Application Insights.

**CSA workaround:** Configurable defaults in config.yml. Organizations can survey makers and update defaults accordingly.

### Business Outcome Data Upload

Viva Insights supports uploading custom business outcome data (e.g., case closure rates, customer retention, sales figures) and correlating it with agent usage patterns.

**Why CSA cannot replicate:** Business outcome correlation requires Viva's data processing pipeline and organizational data integration.

**CSA workaround:** None -- organizations needing business outcome correlation should use Viva Insights or build custom Power BI reports joining agent data with business systems.

### Organizational Hierarchy Analytics

Viva Insights provides analytics rolled up by organizational hierarchy (department, team, manager) using data from Entra ID / Microsoft 365.

**Why CSA cannot replicate:** Organizational hierarchy data is processed by Viva's internal services and is not available via Dataverse or Application Insights.

**CSA workaround:** None -- organizations needing org-level rollups should use Viva Insights or build custom groupings based on agent ownership metadata.

---

*Viva Insights Parity Matrix version: 2.0.1*
*Last updated: 2026-Q2*
