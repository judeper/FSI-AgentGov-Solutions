# Viva Insights: Scope and Limitations for Agent Observability

> **IMPORTANT: Limited Agent Coverage**
>
> Viva Insights Agent Dashboard **only covers Copilot Studio agents** published to
> Production environments. It does **NOT** include:
>
> - Agent Builder agents
> - Agent 365 SDK agents
> - Agents in development/test environments
> - Agents using generative orchestration or autonomous capabilities
>
> **Application Insights is the authoritative data source for all agent types.**
> See [Power BI Integration Guide](power-bi-integration.md) for comprehensive dashboards.

## Availability

> **Status:** The Microsoft Copilot Dashboard in Viva Insights and the Copilot
> Studio agents report are generally available. Microsoft Learn documents both as
> standard features with eligibility prerequisites (for example, a minimum of 50
> Copilot or Viva Insights licenses) and no preview labeling. Microsoft does not
> publish an explicit GA date in these articles; verify current eligibility and
> metric availability against the linked Microsoft Learn documentation for your
> tenant. See [Microsoft Copilot Dashboard](https://learn.microsoft.com/en-us/viva/insights/org-team-insights/copilot-dashboard)
> and [Copilot Studio agents report](https://learn.microsoft.com/en-us/viva/insights/advanced/analyst/templates/copilot-studio-agents).

## What Viva Insights Covers

### Agent Dashboard Metrics
| Metric | Description | Availability |
|--------|-------------|--------------|
| Active users | Unique users who interacted with agents | Available |
| Sessions | Total conversation sessions | Available |
| Messages sent/received | Message counts per agent | Available |
| User satisfaction | Thumbs up/down feedback | Available (if enabled) |
| Agent engagement | Repeat usage patterns | Available |
| Average session duration | Time per conversation | Available |

### Prerequisites
- At least 50 Copilot licenses in the tenant (report eligibility requirement) plus at least one Microsoft Copilot Studio license (standalone, pay-as-you-go, or bundled with Copilot)
- Insights Analyst role in Viva Insights
- At least one Copilot Studio agent published to a Production (default) environment with usage
- Power BI Desktop June 2022 or newer (for report access)

> **Source:** [Copilot Studio agents report — Prerequisites (Microsoft Viva Insights)](https://learn.microsoft.com/viva/insights/advanced/analyst/templates/copilot-studio-agents#prerequisites)

### Data Characteristics
- Initial query: Last 28 days of data
- Data accumulates over time (12-month history for YoY analysis takes 12 months to build)
- Anonymization thresholds: 10-person minimum for aggregated views (50+ licenses recommended for full anonymization)
- Data refresh: Weekly cadence

## What Viva Insights Does NOT Cover

### Excluded Agent Types
| Agent Type | Viva Insights | Application Insights | Notes |
|-----------|:---:|:---:|-------|
| Copilot Studio (Production) | YES | YES | Both systems track these agents |
| Copilot Studio (Dev/Test) | NO | YES | Only Production environment in Viva |
| Agent Builder | NO | YES | Not integrated with Viva Insights |
| Agent 365 SDK | NO | YES | Not integrated with Viva Insights |
| Autonomous agents | NO | YES | Generative orchestration excluded |
| Custom connectors | NO | YES | Custom telemetry only in App Insights |

### Excluded Metrics
| Metric | Viva Insights | Application Insights | Notes |
|--------|:---:|:---:|-------|
| Response latency (P50/P95/P99) | NO | YES | Performance metrics only in App Insights |
| Error categorization | NO | YES | Connector/Knowledge/Orchestration buckets |
| Knowledge source quality | NO | YES | RAG source validation metrics |
| Compliance evidence | NO | YES | FINRA 3110, SEC 17a-4 audit trails |
| Model drift detection | NO | YES | SR 11-7 risk monitoring |
| Zone-based filtering | NO | YES | Governance zone metadata |
| Cost/consumption data | NO | YES | Azure cost management integration |
| Custom dimensions | NO | YES | Organization-specific telemetry |

## Gap Analysis Matrix

### Comprehensive Coverage Comparison

| Capability | Viva Insights | Application Insights | Coverage Gap | Recommendation |
|-----------|:---:|:---:|-------------|----------------|
| **Agent Inventory** | Partial (Copilot Studio only) | Complete (all types) | Agent Builder, Agent 365 SDK missing | Use App Insights for authoritative agent count |
| **Adoption Metrics** | Good (active users, sessions) | Complete | Dev/test agents excluded | Supplement with App Insights for full picture |
| **Performance Monitoring** | None | Complete (latency, errors) | No performance data in Viva | App Insights is sole source |
| **Compliance Evidence** | None | Complete (audit trails) | No regulatory reporting | App Insights + KQL queries required |
| **User Satisfaction** | Good (thumbs up/down) | Partial (custom events) | Different collection mechanisms | Viva for built-in feedback, App Insights for custom |
| **Executive Reporting** | Pre-built dashboards | Custom (Power BI required) | Different presentation layers | Viva for quick adoption view, Power BI for comprehensive |
| **Historical Depth** | Limited (28-day initial) | Complete (730-day retention) | Short initial window | App Insights for trend analysis until Viva accumulates data |
| **Real-Time Monitoring** | No (weekly refresh) | Yes (near real-time) | Not suitable for incident response | App Insights for operations, Viva for periodic review |
| **Zone Governance** | None | Complete (via custom dims) | No zone-aware filtering | App Insights + Power BI for zone-based reporting |

### Summary
- **Viva Insights strengths:** Built-in adoption metrics for Copilot Studio, easy access without Power BI expertise, user satisfaction tracking
- **Viva Insights gaps:** No Agent Builder/Agent 365 SDK coverage, no performance metrics, no compliance evidence, no zone filtering, limited history
- **Recommendation:** Use Viva Insights as a supplementary adoption view. Application Insights with Power BI dashboards is the primary observability platform for FSI governance.

## When to Use Viva Insights

### Appropriate Use Cases
1. Quick adoption check: "How many users are using our Copilot Studio agents?"
2. User satisfaction trend: "Are agent interactions improving over time?"
3. Executive briefing: Pre-built dashboard for non-technical audience
4. Licensing justification: Usage data for Copilot license renewal decisions

### Inappropriate Use Cases (Use Application Insights Instead)
1. Regulatory reporting: FINRA 3110 audit trails, SEC 17a-4 evidence
2. Performance monitoring: Latency SLA compliance, error rate alerting
3. Complete agent inventory: Must include Agent Builder and Agent 365 SDK
4. Incident response: Real-time error diagnosis and root cause analysis
5. Zone governance: Filtering by Zone 1/2/3 governance classification

## Related Documentation
- [Viva Insights Reconciliation Workflow](viva-insights-reconciliation.md)
- [Power BI Integration Guide](power-bi-integration.md)
- [Connector Decision Matrix](connector-decision-matrix.md)
