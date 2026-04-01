# Azure Monitor Workbooks

**Version:** 1.0.0

## Overview

Azure Monitor Workbooks provide interactive dashboards for Copilot Studio analytics, covering agent inventory, quality metrics, business impact, and behavioral analysis. These workbooks are deployed as ARM templates with environment-specific parameter files, enabling consistent visualization across development and production environments.

This solution includes 4 modular workbooks designed for different analytical perspectives: agent inventory and adoption (Agent Overview), session quality and satisfaction (Quality Metrics), ROI and cost savings (Business Impact), and topic and channel analysis (Behavior Analysis). Each workbook supports zone-based filtering aligned with the FSI-AgentGov governance framework (Zone 1 - Personal Productivity, Zone 2 - Team Collaboration, Zone 3 - Enterprise Managed), plus agent type and usage type filtering specific to Copilot Studio Analytics.

All workbooks query `CopilotSessionOutcome` custom events from Application Insights. Global parameters (TimeRange, Zone, AgentType, UsageType) filter all tabs within each workbook, enabling focused analysis without repetitive parameter selection.

## Workbook Catalog

| Name | Purpose | Primary Audience | Key Tabs |
|------|---------|------------------|----------|
| **Agent Overview** | Agent inventory, adoption tracking, and engagement metrics | Product managers, platform admins | Overview Dashboard, Agent Inventory, Adoption Trends |
| **Quality Metrics** | Session outcomes, CSAT analysis, and agent ranking | Operations teams, quality analysts | Session Outcomes, Customer Satisfaction, Top Agents Ranking, Interpretation Matrix |
| **Business Impact** | Agent assisted hours, cost analysis, and ROI calculation | Executive stakeholders, finance | Agent Assisted Hours, Cost Analysis, ROI Breakdown |
| **Behavior Analysis** | Topic trends, action usage, autonomous agent behavior, and channel distribution | Product managers, conversation designers | Topics, Actions, Autonomous Agents, Channel Distribution |

## Global Parameters

All four workbooks share consistent global parameter structure:

**TimeRange Parameter:**
- Type: Time range picker
- Default: 7 days (604800000ms)
- Options: 1d, 3d, 7d, 14d, 30d
- Usage: Scopes all visualizations to selected time window

**Zone Parameter:**
- Type: Dropdown selector
- Default: All Zones
- Options: All Zones, Zone 1 - Personal Productivity, Zone 2 - Team Collaboration, Zone 3 - Enterprise Managed
- Usage: Filters telemetry by governance zone for compliance alignment

**AgentType Parameter:**
- Type: Dropdown selector
- Default: All Types
- Options: All Types, Conversational, Autonomous
- Usage: Filters by agent mode to compare conversational and autonomous agent performance

**UsageType Parameter:**
- Type: Dropdown selector
- Default: All Types
- Options: All Types, Internal, External
- Usage: Filters by internal vs external usage patterns

**Business Impact Additional Parameters:**
- **TimeSavingsMinutes**: Text input (default: 6) - estimated minutes saved per engaged session
- **HourlyRate**: Text input (default: 72) - hourly rate in USD for cost savings calculation

## Deployment

Each workbook deploys via Azure CLI using ARM templates and environment-specific parameter files:

**Development Environment:**
```bash
cd /path/to/FSI-AgentGov-Solutions

# Agent Overview
az deployment group create \
  --resource-group rg-copilot-analytics-dev \
  --template-file copilot-studio-analytics/workbooks/agent-overview/workbook-template.json \
  --parameters @copilot-studio-analytics/workbooks/agent-overview/workbook-parameters.dev.json

# Quality Metrics
az deployment group create \
  --resource-group rg-copilot-analytics-dev \
  --template-file copilot-studio-analytics/workbooks/quality-metrics/workbook-template.json \
  --parameters @copilot-studio-analytics/workbooks/quality-metrics/workbook-parameters.dev.json

# Business Impact
az deployment group create \
  --resource-group rg-copilot-analytics-dev \
  --template-file copilot-studio-analytics/workbooks/business-impact/workbook-template.json \
  --parameters @copilot-studio-analytics/workbooks/business-impact/workbook-parameters.dev.json

# Behavior Analysis
az deployment group create \
  --resource-group rg-copilot-analytics-dev \
  --template-file copilot-studio-analytics/workbooks/behavior-analysis/workbook-template.json \
  --parameters @copilot-studio-analytics/workbooks/behavior-analysis/workbook-parameters.dev.json
```

**Production Environment:**
Replace `workbook-parameters.dev.json` with `workbook-parameters.prod.json` and use production resource group name.

**Idempotent Deployment:**
Re-running deployment commands updates existing workbooks (does not create duplicates) because templates use fixed workbookId GUIDs in parameter files. This pattern supports safe CI/CD pipeline integration.

## Directory Structure

```
workbooks/
├── README.md                          # This file
├── agent-overview/
│   ├── workbook-template.json         # ARM template (3 tabs)
│   ├── workbook-parameters.dev.json   # Dev environment parameters
│   └── workbook-parameters.prod.json  # Prod environment parameters
├── quality-metrics/
│   ├── workbook-template.json         # ARM template (4 tabs)
│   ├── workbook-parameters.dev.json   # Dev environment parameters
│   └── workbook-parameters.prod.json  # Prod environment parameters
├── business-impact/
│   ├── workbook-template.json         # ARM template (3 tabs)
│   ├── workbook-parameters.dev.json   # Dev environment parameters
│   └── workbook-parameters.prod.json  # Prod environment parameters
└── behavior-analysis/
    ├── workbook-template.json         # ARM template (4 tabs)
    ├── workbook-parameters.dev.json   # Dev environment parameters
    └── workbook-parameters.prod.json  # Prod environment parameters
```

## KQL Query Source

Workbooks embed self-contained KQL queries that operate on `CopilotSessionOutcome` custom events. This table maps workbook visualizations to the query patterns used:

**Agent Overview Workbook:**
| Tab | Visualization | Query Pattern |
|-----|---------------|---------------|
| Overview Dashboard | Metric tiles (Total, Conversational, Autonomous, Sessions, Engaged) | Aggregated dcount/count on CopilotSessionOutcome |
| Overview Dashboard | Active agents trend (stacked by type) | Daily bin dcount by agentMode |
| Overview Dashboard | Top 5 agents bar chart | Top N by engaged session count |
| Agent Inventory | Full agent table with engagement rate | Per-agent summarize with calculated EngagementRate |
| Adoption Trends | New agents deployed over time | First-seen date aggregation |
| Adoption Trends | Session volume stacked by agent type | Daily bin count by agentMode |
| Adoption Trends | Cumulative agent count | row_cumsum on first-seen dates |

**Quality Metrics Workbook:**
| Tab | Visualization | Query Pattern |
|-----|---------------|---------------|
| Session Outcomes | Conversational outcomes donut | Filter agentMode==Conversational, isEngaged==true, group by sessionOutcome |
| Session Outcomes | Autonomous outcomes donut | Filter agentMode==Autonomous, isEngaged==true, group by sessionOutcome |
| Session Outcomes | Outcome reason table | Group by agentMode, sessionOutcome, sessionOutcomeReason |
| Customer Satisfaction | CSAT trend line | Daily avg of csatScore for conversational agents |
| Customer Satisfaction | CSAT distribution (1-5) | Bar chart of csatScore counts |
| Customer Satisfaction | Per-agent CSAT table | Avg csatScore grouped by agentId |
| Top Agents Ranking | Ranked agent table | Resolution/Success rate calculation with CSAT |
| Interpretation Matrix | Resolution Rate vs CSAT scatter | Scatter plot of per-agent resolution rate and avg CSAT |

**Business Impact Workbook:**
| Tab | Visualization | Query Pattern |
|-----|---------------|---------------|
| Agent Assisted Hours | Total AAH tile | EngagedSessions * TimeSavingsMinutes / 60 |
| Agent Assisted Hours | Conversational AAH table | Per-agent AAH for conversational agents |
| Agent Assisted Hours | Autonomous AAH table | Per-agent AAH for autonomous agents |
| Agent Assisted Hours | Top 10 agents by AAH bar chart | Top N by calculated AAH |
| Cost Analysis | Total cost savings tile | AAH * HourlyRate |
| Cost Analysis | Per-agent cost breakdown table | Per-agent AAH and cost savings |
| ROI Breakdown | Weekly trend chart | Weekly bin of AAH and cost savings |
| ROI Breakdown | Period-over-period delta table | Current vs previous period comparison |

**Behavior Analysis Workbook:**
| Tab | Visualization | Query Pattern |
|-----|---------------|---------------|
| Topics | Top 20 topics bar chart | Top N by session count on topicName |
| Topics | Topic x Agent matrix | Group by agentId and topicName |
| Topics | Topic trend (daily) | Daily bin count by topicName |
| Actions | Action invocation table | Group by actionName with success rate (Tier 2 dependent -- planned, not yet implemented) |
| Autonomous Agents | Outcomes with duration | Group by sessionOutcome with percentile duration |
| Autonomous Agents | Completion time trend (P50/P95) | Daily bin percentiles of sessionDurationMs |
| Autonomous Agents | Sessions by trigger type | Group by triggerType (Tier 2 dependent -- planned, `triggerType` not yet emitted by sync pipeline) |
| Channel Distribution | Sessions by channel pie chart | Group by channel |
| Channel Distribution | Channel x Agent breakdown | Group by agentId and channel |

**Query Parameter Syntax:**
Workbook queries use parameter reference syntax like `{TimeRange:ms}`, `"{Zone}"`, `"{AgentType}"`, and `"{UsageType}"` for seamless integration with global parameters. The Business Impact workbook additionally uses `{TimeSavingsMinutes}` and `{HourlyRate}` as numeric parameters.

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Workbook shows "No data available" | Application Insights has no CopilotSessionOutcome events | Verify Copilot Studio telemetry sync is configured and emitting CopilotSessionOutcome custom events to Application Insights |
| Zone parameter shows no results | customDimensions['Zone'] field missing | Verify Copilot Studio agents emit zone metadata via environment configuration |
| AgentType filter has no effect | customDimensions['agentMode'] field missing | Confirm agents are configured with agentMode dimension (Conversational or Autonomous) |
| CSAT data missing in Quality Metrics | csatScore not present in telemetry | CSAT is only available for conversational agents with survey enabled |
| Actions tab shows no data | Tier 2 sync not yet implemented | Tier 2 transcript parsing is planned for a future release; the Actions tab requires `actionName` and `actionStatus` fields that are not yet emitted by the sync pipeline |
| Business Impact shows zero savings | No engaged sessions in selected period | Verify isEngaged dimension is populated and adjust time range |
| Deployment fails with "Conflict" | Duplicate workbookId in same resource group | Check parameter files for unique workbookId GUIDs per environment (dev vs prod) |
| Queries timeout after 30 seconds | KQL query not optimized for large datasets | Narrow the TimeRange parameter or add additional filters (Zone, AgentType) |

---

*Version: 1.0.0*
*Last Updated: February 2026*
*Part of FSI-AgentGov-Solutions*
