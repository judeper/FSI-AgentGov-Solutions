# Copilot Studio Analytics - KQL Query Library

KQL query library for Copilot Studio agent analytics, providing operational visibility into agent performance, session outcomes, business impact, and behavior patterns.

## Overview

This library contains 15 KQL queries organized into 4 categories. All queries operate on `CopilotSessionOutcome` custom events synced to Application Insights from the Copilot Studio Analytics pipeline.

## Query Catalog

| # | Query | Category | Purpose | Default TimeRange | Tier |
|---|-------|----------|---------|-------------------|------|
| 1 | [agent-inventory.kql](agent-overview/agent-inventory.kql) | Agent Overview | Agent count with conversational vs autonomous split | 30d | 1 |
| 2 | [active-agents-trend.kql](agent-overview/active-agents-trend.kql) | Agent Overview | Daily active agent count by type | 30d | 1 |
| 3 | [top-agents-by-engagement.kql](agent-overview/top-agents-by-engagement.kql) | Agent Overview | Top N agents by engaged sessions | 7d | 1 |
| 4 | [conversational-outcome-distribution.kql](session-outcomes/conversational-outcome-distribution.kql) | Session Outcomes | Resolved/Abandoned/Escalated split | 7d | 1 |
| 5 | [autonomous-outcome-distribution.kql](session-outcomes/autonomous-outcome-distribution.kql) | Session Outcomes | Success/Failure split for autonomous agents | 7d | 1 |
| 6 | [csat-score-trend.kql](session-outcomes/csat-score-trend.kql) | Session Outcomes | Average CSAT over time (conversational only) | 30d | 1 |
| 7 | [resolution-satisfaction-matrix.kql](session-outcomes/resolution-satisfaction-matrix.kql) | Session Outcomes | 2x2 quadrant (resolution x satisfaction) | 30d | 1 |
| 8 | [outcome-by-agent.kql](session-outcomes/outcome-by-agent.kql) | Session Outcomes | Per-agent outcome breakdown | 7d | 1 |
| 9 | [conversational-assisted-hours.kql](business-impact/conversational-assisted-hours.kql) | Business Impact | Conversational Agent Assisted Hours | 30d | 1 |
| 10 | [autonomous-assisted-hours.kql](business-impact/autonomous-assisted-hours.kql) | Business Impact | Autonomous Agent Assisted Hours | 30d | 1 |
| 11 | [agent-assisted-cost.kql](business-impact/agent-assisted-cost.kql) | Business Impact | Cost savings from AAH | 30d | 1 |
| 12 | [roi-trend.kql](business-impact/roi-trend.kql) | Business Impact | Weekly ROI trend with WoW deltas | 30d | 1 |
| 13 | [sessions-per-topic.kql](behavior-metrics/sessions-per-topic.kql) | Behavior Metrics | Topic distribution | 7d | 1 |
| 14 | [sessions-per-action.kql](behavior-metrics/sessions-per-action.kql) | Behavior Metrics | Action invocation frequency | 7d | 2 *(planned)* |
| 15 | [sessions-per-trigger.kql](behavior-metrics/sessions-per-trigger.kql) | Behavior Metrics | Autonomous triggers and completion time | 7d | 1 |

## Data Source

All queries target the `customEvents` table in Application Insights, filtering on:

```kql
| where name == "CopilotSessionOutcome"
```

These events are synced from Copilot Studio's built-in analytics via the CSA sync pipeline. Design mode sessions are already filtered during the sync process.

## Tier Definitions

| Tier | Description | Data Source |
|------|-------------|-------------|
| **Tier 1** | Session-level analytics from CopilotSessionOutcome events | Copilot Studio Analytics API |
| **Tier 2** *(planned)* | Action-level analytics from transcript parsing *(not yet implemented in sync pipeline)* | Conversation transcript API |

Most queries operate on Tier 1 data. `sessions-per-action.kql` requires Tier 2 sync for action-level detail, which is planned for a future release.

## Parameters

All queries support workbook parameter syntax using `{ParameterName:default}` notation.

### Common Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `{TimeRange}` | timespan | Varies | Time window for the query (7d or 30d) |
| `{Zone}` | string | `"all"` | Zone filter - "all" or specific zone name |
| `{AgentType}` | string | `"All"` | Agent type filter - "All", "Conversational", or "Autonomous" |

### Business Impact Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `{TimeSavingsMinutes}` | int | 6 | Minutes saved per conversational session |
| `{InfoRetrievalMinutes}` | int | 6 | Minutes saved per autonomous KS reference |
| `{GenericActionMinutes}` | int | 3 | Minutes saved per autonomous action session |
| `{GenericTimeSavingMinutes}` | int | 5 | Minutes saved per autonomous generic session |
| `{HourlyRate}` | int | 72 | Hourly rate in USD for cost calculations |

### Other Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `{TopN}` | int | 20 | Number of agents to return in top-N queries |
| `{ResolutionThreshold}` | int | 70 | Resolution rate threshold percentage |
| `{CSATThreshold}` | real | 3.5 | CSAT score threshold for matrix quadrants |

## Filter Syntax

All queries include Zone and AgentType filters using the following pattern:

```kql
| where "{Zone}" == "all" or tostring(customDimensions['Zone']) == "{Zone}"
| where "{AgentType}" == "All" or tostring(customDimensions['agentMode']) == "{AgentType}"
```

When the parameter is set to the default ("all" / "All"), no filtering occurs. Otherwise, the filter narrows results to the specified value.

## Testing in Log Analytics

To test queries directly in Log Analytics (outside a workbook context):

1. Replace workbook parameter syntax with literal values:
   - `{TimeRange:7d}` becomes `7d`
   - `"{Zone}"` becomes `"all"`
   - `"{AgentType}"` becomes `"All"`
   - `{TopN:20}` becomes `20`

2. Example transformation:
   ```kql
   // Workbook syntax
   let TimeRange = {TimeRange:7d};

   // Log Analytics testing
   let TimeRange = 7d;
   ```

## Directory Structure

```
queries/
├── README.md                    # This file
├── governance-queries.md        # Control mapping documentation
├── agent-overview/
│   ├── agent-inventory.kql
│   ├── active-agents-trend.kql
│   └── top-agents-by-engagement.kql
├── session-outcomes/
│   ├── conversational-outcome-distribution.kql
│   ├── autonomous-outcome-distribution.kql
│   ├── csat-score-trend.kql
│   ├── resolution-satisfaction-matrix.kql
│   └── outcome-by-agent.kql
├── business-impact/
│   ├── conversational-assisted-hours.kql
│   ├── autonomous-assisted-hours.kql
│   ├── agent-assisted-cost.kql
│   └── roi-trend.kql
└── behavior-metrics/
    ├── sessions-per-topic.kql
    ├── sessions-per-action.kql
    └── sessions-per-trigger.kql
```

## Related Documentation

- [Governance Query Mapping](governance-queries.md) - Maps queries to Control 3.2 with evidence descriptions
- [Agent Observability Foundation Queries](../../agent-observability-foundation/queries/) - Foundation-layer KQL queries

---

*Query Library version: 2.0.0*
*Last updated: February 2026*
