# Power BI: Agent Compliance Dashboard

Executive-facing compliance dashboards and agent observability analytics for the FSI Agent Governance Framework.

## What's Included

This Power BI solution provides business intelligence and compliance reporting capabilities built on top of the Agent Observability Foundation telemetry infrastructure.

| Component | Description |
|-----------|-------------|
| **`semantic-model/`** | TMDL-based star schema with dual-grain facts (session + event), 8 dimensions, zone-based RLS |
| **`measures/`** | DAX measures for sessions, latency, error rates, compliance score, and trend calculations |
| **`kql-views/`** | Pre-aggregated KQL functions for efficient Power BI data consumption |
| **`templates/`** | Reserved for `.pbit` template (planned — use TMDL path for now) |
| **`docs/`** | Integration guide, connector decision matrix, Viva Insights documentation |

## Quick Start

Choose your deployment path based on your experience level and customization needs.

### Option 1: TMDL Import (Recommended)

**Best for:** Organizations requiring customization or integration with existing Power BI infrastructure

1. Deploy KQL functions from `kql-views/` to your Log Analytics workspace
2. Import TMDL semantic model from `semantic-model/` into Power BI Desktop or Fabric
3. Configure data source connection to your workspace
4. Import DAX measures from `measures/` directory
5. Customize dashboard pages and visuals as needed
6. Publish to Power BI Service

**Time to deploy:** 1-2 hours

> **Note:** A `.pbit` template for quick-start deployment is planned for a future release. Until then, the TMDL import path above provides full functionality including all 19 DAX measures, zone-based RLS, and 5 dashboard page designs.

**See:** [Power BI Integration Guide](docs/power-bi-integration.md) for detailed custom build instructions

## Prerequisites

**Infrastructure:**
- Agent Observability Foundation deployed ([see main README](../README.md))
- Log Analytics workspace with 730-day retention
- Application Insights with CopilotInteraction telemetry

**Access:**
- Read access to Log Analytics workspace (Monitoring Reader role)
- Power BI Desktop (June 2022 or later)

**Licensing:**
- **Import mode:** Power BI Pro license ($10/user/month)
- **DirectQuery mode:** Power BI Premium, Premium Per User (PPU), or Fabric F-SKU

**Not sure which to choose?** See [Connector Decision Matrix](docs/connector-decision-matrix.md)

## Choosing Your Connector

Two paths to connect Power BI to Application Insights / Log Analytics telemetry:

| Approach | License | Data Freshness | Best For |
|----------|---------|----------------|----------|
| **ADX Connector (Import)** | Pro ($10/user/month) | Scheduled refresh (1-8x/day) | Daily/weekly executive review, compliance reporting |
| **DirectQuery** | Premium/PPU/Fabric | Real-time (live queries) | Operations monitoring, incident investigation |

**Decision criteria:**
- **Real-time needed?** → DirectQuery (requires Premium)
- **Budget constrained?** → Import mode (Pro license)
- **Large deployment (>100 agents)?** → DirectQuery (no dataset size limit)
- **Executive reporting only?** → Import mode (better offline access)

**Full comparison:** [Connector Decision Matrix](docs/connector-decision-matrix.md)

## Dashboard Pages

The solution includes 5 pre-built dashboard pages aligned with FSI governance requirements:

### 1. Compliance Posture

**Audience:** CIO, Chief Compliance Officer, Board

Top-level compliance metrics and zone health overview:
- Overall compliance score (weighted by pillar)
- Control coverage by regulation (FINRA 3110, SEC 17a-4, SR 11-7)
- Zone distribution (Zone 1/2/3) and governance status
- Telemetry completeness indicator

**Supports:** Control 3.1 (Agent Inventory), Control 3.2 (Usage Analytics)

### 2. Regulation Drill-Down

**Audience:** Compliance team preparing for examinations

Select a regulation to view detailed evidence status:
- FINRA 3110 supervision requirements
- SEC 17a-4 record retention compliance
- SR 11-7 model risk management evidence
- Gap analysis with remediation recommendations

**Supports:** Control 2.6 (Model Risk Management), Control 1.7 (Audit Logging)

**Use case:** "We have a FINRA exam next month — show me our 3110 evidence readiness"

### 3. Operational Health

**Audience:** Operations team, M365 administrators

Real-time monitoring of agent performance and availability:
- Session success rate (completion rate)
- Error rates by category (connector, knowledge, orchestration)
- P95/P99 latency trends
- Agent availability by zone

**Supports:** Control 2.9 (Performance Monitoring), Control 3.4 (Incident Reporting)

### 4. Adoption Trends

**Audience:** Business stakeholders, project sponsors

Agent adoption and usage patterns:
- Session volume trends (daily/weekly/monthly)
- User engagement metrics (distinct users, repeat sessions)
- Zone distribution (Personal vs Team vs Enterprise)
- Agent comparison (top performers vs underutilized)

**Supports:** Control 3.2 (Usage Analytics)

**Integration:** Can correlate with Viva Insights Copilot Dashboard for Copilot Studio agents ([see Viva documentation](docs/viva-insights-scope.md))

### 5. Agent Detail (Drill-Through)

**Audience:** Agent owners, troubleshooting

Agent-specific metrics and audit trail:
- Session history for selected agent
- Error patterns and latency distribution
- User activity (hashed for privacy)
- Control evidence collection status

**Supports:** Control 1.7 (Audit Logging), Control 2.9 (Performance Monitoring)

**Access control:** Zone-based RLS restricts visibility to authorized users

## Documentation

### Getting Started
- **[Connector Decision Matrix](docs/connector-decision-matrix.md)** - ADX Connector vs DirectQuery comparison with decision criteria, setup steps, and troubleshooting
- **[Power BI Integration Guide](docs/power-bi-integration.md)** - Full deployment guide, customization instructions, and advanced scenarios

### Viva Insights Integration
- **[Viva Insights Scope](docs/viva-insights-scope.md)** - What Viva Insights covers (Copilot Studio Production agents only) and limitations
- **[Viva Insights Reconciliation](docs/viva-insights-reconciliation.md)** - Cross-system validation workflow for Application Insights vs Viva Insights metrics

### Technical Reference
- **[Semantic Model Design](semantic-model/README.md)** - Star schema documentation, relationship diagrams, RLS configuration
- **[DAX Measures Reference](measures/README.md)** - Complete measure documentation with calculation logic
- **[KQL Functions](kql-views/)** - Pre-aggregation functions for efficient data consumption

## Architecture Overview

The Power BI solution connects to Application Insights telemetry via Azure Data Explorer (ADX) connector:

```
┌─────────────────────────────────────────────────────────────────┐
│ Power BI Service (Premium/PPU/Fabric or Pro)                     │
│                                                                   │
│  ┌──────────────────┐      ┌──────────────────┐                 │
│  │ Compliance       │      │ Operational      │                 │
│  │ Posture          │      │ Health           │                 │
│  └──────────────────┘      └──────────────────┘                 │
│                                                                   │
│  ┌──────────────────┐      ┌──────────────────┐                 │
│  │ Regulation       │      │ Adoption         │                 │
│  │ Drill-Down       │      │ Trends           │                 │
│  └──────────────────┘      └──────────────────┘                 │
│                                                                   │
│  Semantic Model: Dual-grain star schema (session + event facts)  │
│  RLS: Zone-based access control (Zone1/Zone2/Zone3)              │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     │ ADX Connector (Import or DirectQuery)
                     │
┌────────────────────▼────────────────────────────────────────────┐
│ Azure Log Analytics Workspace (730-day retention)                │
│                                                                   │
│  KQL Pre-Aggregation Functions:                                  │
│    • vw_session_fact(startDate, endDate) → Session metrics       │
│    • vw_event_fact(startDate, endDate) → Event-level detail      │
│    • vw_dim_agent() → Agent dimension                            │
│    • vw_dim_regulation_control() → Regulation mapping            │
│                                                                   │
│  Data Source: customEvents table (CopilotInteraction)            │
└────────────────────┬────────────────────────────────────────────┘
                     │
                     │ Diagnostic Settings
                     │
┌────────────────────▼────────────────────────────────────────────┐
│ Application Insights (Workspace-based)                           │
│                                                                   │
│  Copilot Studio telemetry: BotMessageReceived, BotMessageSend    │
│  Agent Builder telemetry: (future roadmap)                       │
│  Agent 365 SDK telemetry: (future roadmap)                       │
└──────────────────────────────────────────────────────────────────┘
```

**Key design decisions:**
- **Dual-grain star schema:** Session-level for trends, event-level for drill-down
- **Zone-based RLS:** Users see only agents in their authorized zones
- **Pre-aggregation:** KQL functions reduce data transfer and improve performance
- **Parameterized date ranges:** Control dataset size for Pro license 1GB limit

## Related

### Agent Observability Foundation
- **[Main Solution README](../README.md)** - Parent solution overview and deployment
- **[KQL Query Library](../queries/README.md)** - Foundation queries for workbooks and ad-hoc analysis
- **[Governance Mapping](../docs/governance-mapping.md)** - Controls-to-observability artifact mapping

### FSI-AgentGov Framework
- **[Control Catalog](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/CONTROL-INDEX.md)** - Complete 78-control framework
- **[Framework Documentation](https://judeper.github.io/FSI-AgentGov/)** - Published documentation site
- **[Regulatory Mappings](https://github.com/judeper/FSI-AgentGov/blob/main/docs/reference/regulatory-mappings.md)** - Control-to-regulation cross-reference

### Microsoft Learn Resources
- **[Power BI DirectQuery](https://learn.microsoft.com/power-bi/connect-data/desktop-directquery-about)** - DirectQuery concepts and limitations
- **[Azure Data Explorer Connector](https://learn.microsoft.com/power-bi/connect-data/desktop-connect-azure-data-explorer)** - ADX connector documentation
- **[Log Analytics Workspace](https://learn.microsoft.com/azure/azure-monitor/logs/log-analytics-workspace-overview)** - Workspace concepts and query optimization

---

**Questions or issues?**
- Open an issue in [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues)
- See [Troubleshooting](docs/connector-decision-matrix.md#known-limitations-and-troubleshooting) for common problems

**Contributing:**
- See [CONTRIBUTING.md](../../CONTRIBUTING.md) for contribution guidelines
- Language rules: Use hedging language ("helps support", "aids in") — never "ensures compliance" or "guarantees"

---

*Power BI Solution Version: 1.0.0*
*Last Updated: February 2026*
*Part of Agent Observability Foundation v1.1.0*
