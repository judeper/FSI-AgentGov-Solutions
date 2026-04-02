# Copilot Studio Analytics

> **Version:** v1.1.0
> **Status:** Active

Business impact analytics for Copilot Studio agents -- session outcomes, CSAT, Agent Assisted Hours, and ROI calculations. Provides Viva Insights-equivalent metrics for organizations without Viva Insights licenses.

## Architecture Overview

Copilot Studio Analytics (CSA) operates as a companion to the [Agent Observability Foundation](../agent-observability-foundation/) (AOF). Where AOF captures operational telemetry (session volumes, error rates, latency), CSA focuses on business impact: session outcomes, customer satisfaction, time savings, and return on investment.

CSA bridges two data sources into a unified analytics layer:

1. **Native telemetry** (managed by AOF): BotMessageSend, BotMessageReceived, GenerativeAnswers events already flowing into Application Insights
2. **Dataverse session data** (managed by CSA): msdyn_botsession outcome records synced into Application Insights as CopilotSessionOutcome custom events

See [architecture.md](architecture.md) for the full data flow diagram and tiered data strategy.

## What This Solution Does

### Dataverse Session Sync

- **Syncs msdyn_botsession records** from Dataverse to Application Insights as CopilotSessionOutcome custom events
- **Watermark-based incremental sync** using a Dataverse tracking table to avoid duplicate processing
- **Agent type classification** by joining bot and botcomponent tables (componenttypename = 17 identifies autonomous agents)
- **Configurable sync frequency** from daily batch to near-real-time (4-6 hour intervals)

### KQL Query Library

- **15 production queries** across 4 categories organized by business function
- **Agent Overview (3 queries):** Agent inventory, active agent trend, top agents by session volume
- **Session Outcomes (5 queries):** Conversational outcomes, autonomous outcomes, CSAT distribution, resolution matrix, outcome trends
- **Business Impact (4 queries):** Conversational AAH, autonomous AAH, cost avoidance, ROI trend analysis
- **Behavior Metrics (3 queries):** Topic performance, action execution (Tier 2 -- planned), trigger patterns and completion rates

### Azure Monitor Workbooks

- **4 workbooks with 14 tabs** deployed via ARM templates to Azure Monitor
- **Agent Overview (3 tabs):** Inventory, adoption trends, agent comparison
- **Quality Metrics (4 tabs):** Session outcomes, CSAT analysis, resolution rates, escalation patterns
- **Business Impact (3 tabs):** Agent Assisted Hours, cost avoidance, ROI calculator
- **Behavior Analysis (4 tabs):** Topic drill-down, action performance, trigger analysis, completion funnel

### Business Impact Calculations

- **Agent Assisted Hours (AAH):** Separate formulas for conversational and autonomous agents
- **Cost avoidance:** Configurable hourly rate (default $72/hr) applied to AAH
- **ROI trend analysis:** Period-over-period business impact tracking
- **Viva Insights parity:** Honest assessment of feature coverage vs Microsoft Viva Insights

## Relationship to AOF

| Aspect | AOF | CSA |
|--------|-----|-----|
| **Focus** | Operational telemetry | Business impact analytics |
| **Data source** | Native Copilot Studio events (BotMessage*, GenerativeAnswers) | Dataverse session outcomes (msdyn_botsession) |
| **Metrics** | Error rates, latency, availability | CSAT, AAH, ROI, adoption |
| **Control scope** | 1.7, 2.9, 3.2 (operational) | 3.2 (business impact) |
| **Prerequisite** | Standalone | Requires AOF deployed first |

> CSA depends on AOF infrastructure (Application Insights + Log Analytics). Deploy AOF before CSA.

## Who Should Use This

| Audience | Use Case |
|----------|----------|
| Product Manager | Track agent adoption, CSAT trends, business impact |
| Compliance Officer | Control 3.2 evidence -- usage analytics and activity monitoring |
| Business Analyst | ROI calculations and agent performance comparison |
| Platform Operations | Validate sync pipeline health, monitor data freshness |

## Prerequisites

Before deploying this solution, confirm:

1. **AOF deployed** -- Application Insights and Log Analytics workspace from [Agent Observability Foundation](../agent-observability-foundation/)
2. **Dataverse access** -- App registration with read permissions to msdyn_botsession, bot, botcomponent
3. **Python 3.9+** with dependencies installed
4. **Copilot Studio agents** connected to Application Insights (same as AOF prerequisite)
5. **Transcript retention extended** (recommended for future Tier 2 support) -- default 30-day bulk delete job should be modified if planning for Tier 2 data

See [prerequisites.md](prerequisites.md) for detailed requirements, role assignments, and transcript retention instructions.

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/judeper/FSI-AgentGov-Solutions.git
cd FSI-AgentGov-Solutions/copilot-studio-analytics

# 2. Install Python dependencies
pip install -r scripts/requirements.txt

# 3. Copy and edit configuration
cp config/config.example.yml config/config.yml
# Edit config.yml with your App Insights connection string, Dataverse URL, tenant ID

# 4. Run Dataverse session sync (dry run)
python scripts/sync_dataverse_sessions.py --dry-run

# 5. Run Dataverse session sync
python scripts/sync_dataverse_sessions.py

# 6. Validate telemetry
python scripts/validate_telemetry.py

# 7. Deploy workbooks (example: Agent Overview)
az deployment group create \
  --resource-group rg-agent-observability-dev \
  --template-file workbooks/agent-overview/workbook-template.json \
  --parameters @workbooks/agent-overview/workbook-parameters.dev.json
```

## Solution Structure

```
copilot-studio-analytics/
├── README.md                              # This file -- solution overview
├── CHANGELOG.md                           # Version history
├── architecture.md                        # Data flow diagram and tiered data strategy
├── prerequisites.md                       # Deployment requirements checklist
├── governance-mapping.md                  # Artifact-to-control mapping (Control 3.2)
├── config/
│   ├── config.schema.json                 # JSON schema for configuration validation
│   └── config.example.yml                 # Example configuration template
├── scripts/
│   ├── sync_dataverse_sessions.py         # Dataverse → App Insights session sync
│   ├── create_csa_dataverse_schema.py     # Watermark table schema (--output-docs)
│   ├── validate_telemetry.py              # Post-sync validation
│   └── requirements.txt                   # Python dependencies
├── queries/
│   ├── README.md                          # KQL query library overview
│   ├── governance-queries.md              # Governance-specific KQL queries
│   ├── agent-overview/                    # Agent inventory and trends (3 queries)
│   ├── session-outcomes/                  # Outcome analysis (5 queries)
│   ├── business-impact/                   # AAH, cost, ROI (4 queries)
│   └── behavior-metrics/                  # Topics, actions, triggers (3 queries)
├── workbooks/
│   ├── README.md                          # Workbook catalog and deployment
│   ├── agent-overview/                    # Agent inventory workbook (3 tabs)
│   ├── quality-metrics/                   # Quality analysis workbook (4 tabs)
│   ├── business-impact/                   # Business impact workbook (3 tabs)
│   └── behavior-analysis/                 # Behavior analysis workbook (4 tabs)
└── docs/
    ├── dataverse-schema.md                # Auto-generated Dataverse schema reference
    ├── dataverse-data-sources.md          # Dataverse table reference
    ├── agent-assisted-hours-methodology.md # AAH calculation methodology
    ├── viva-insights-parity-matrix.md     # Feature comparison with Viva Insights
    └── cost-tuning-guide.md               # Cost optimization guidance
```

## Documentation

| Guide | Description |
|-------|-------------|
| [architecture.md](architecture.md) | Mermaid data flow diagram, tiered data strategy, agent type classification |
| [prerequisites.md](prerequisites.md) | Deployment requirements with role assignments and transcript retention |
| [governance-mapping.md](governance-mapping.md) | Maps CSA artifacts to Control 3.2 with evidence tiers |
| [docs/dataverse-data-sources.md](docs/dataverse-data-sources.md) | Dataverse table reference for msdyn_botsession, bot, botcomponent |
| [docs/agent-assisted-hours-methodology.md](docs/agent-assisted-hours-methodology.md) | AAH calculation formulas for conversational and autonomous agents |
| [docs/viva-insights-parity-matrix.md](docs/viva-insights-parity-matrix.md) | Honest feature comparison with Microsoft Viva Insights |
| [docs/cost-tuning-guide.md](docs/cost-tuning-guide.md) | Sync frequency tuning, data volume estimation, cost optimization |

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Sync returns zero sessions | Dataverse app registration missing read permissions | Verify app has `msdyn_botsession` read access in Dataverse security role |
| CopilotSessionOutcome events not appearing | App Insights instrumentation key misconfigured | Verify `APPINSIGHTS_INSTRUMENTATIONKEY` env var or `application_insights.name` in config.yml matches AOF deployment |
| CSAT data missing from queries | CSAT survey not enabled on agents | Enable CSAT survey in Copilot Studio agent settings |
| Tier 2 queries return no data | Tier 2 sync not yet implemented | Tier 2 transcript parsing is planned for a future release; current sync provides Tier 1 data only |
| Autonomous agent AAH shows zero | Agent type classification failed | Verify botcomponent records exist with componenttypename for the agent |
| Workbook shows "No data" | Time range too narrow or sync not yet run | Expand time range; verify sync completed via `validate_telemetry.py` |
| Duplicate CopilotSessionOutcome events | Watermark table corrupted or reset | Check watermark table; re-sync with `--full-sync` flag to rebuild |

## Related Controls

This solution supports the following FSI-AgentGov framework control:

- [Control 3.2: Usage Analytics and Activity Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) -- Business impact analytics including session outcomes, CSAT, Agent Assisted Hours, and ROI calculations

## Version

**v1.1.0** -- April 2026

See [CHANGELOG.md](CHANGELOG.md) for version history.

## License

MIT -- See LICENSE in repository root
