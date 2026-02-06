# Azure Monitor Workbooks

**Version:** 1.0.0

## Overview

Azure Monitor Workbooks provide interactive dashboards for operational visibility into Copilot Studio agent performance, errors, and usage patterns. These workbooks are deployed as ARM templates with environment-specific parameter files, enabling consistent visualization across development and production environments.

This solution includes 3 modular workbooks designed for different operational roles: daily health monitoring (Operational Health), incident investigation (Error Diagnostics), and adoption tracking (Usage Overview). Each workbook supports zone-based filtering aligned with the FSI-AgentGov governance framework (Zone 1 - Personal Productivity, Zone 2 - Team Collaboration, Zone 3 - Enterprise Managed).

All workbooks use KQL queries from the Phase 2 query library, providing consistent metrics across visualizations and alert rules. Global parameters (TimeRange and Zone) filter all tabs within each workbook, enabling focused analysis without repetitive parameter selection.

## Workbook Catalog

| Name | Purpose | Primary Audience | Key Tabs |
|------|---------|------------------|----------|
| **Operational Health** | Daily agent health monitoring and performance tracking | Operations teams, SOC analysts | Overview, Availability, Error Rates, Latency |
| **Error Diagnostics** | Error triage and root cause analysis for incident investigation | Incident responders, platform engineers | Error Summary, Error Drill-Down, Root Cause Analysis, Event Detail |
| **Usage Overview** | Adoption metrics and user engagement analytics | Product managers, compliance officers | Adoption Overview, Engagement, Channel Distribution, Generative AI Quality |

## Global Parameters

All three workbooks share consistent global parameter structure:

**TimeRange Parameter:**
- Type: Time range picker
- Default: 24 hours (86400000ms)
- Options: 1h, 4h, 24h, 48h, 3d, 7d
- Usage: Scopes all visualizations to selected time window

**Zone Parameter:**
- Type: Dropdown selector
- Default: All Zones
- Options: All Zones, Zone 1 - Personal Productivity, Zone 2 - Team Collaboration, Zone 3 - Enterprise Managed
- Usage: Filters telemetry by governance zone for compliance alignment

**Why these parameters:**
The 24-hour default time range supports daily operations monitoring (most common use case), while zone filtering enables governance-aligned access control and RBAC scoping per the FSI-AgentGov framework zones-and-tiers model.

## Deployment

Each workbook deploys via Azure CLI using ARM templates and environment-specific parameter files:

**Development Environment:**
```bash
cd /path/to/FSI-AgentGov-Solutions

# Operational Health
az deployment group create \
  --resource-group rg-agent-observability-dev \
  --template-file agent-observability-foundation/workbooks/operational-health/workbook-template.json \
  --parameters @agent-observability-foundation/workbooks/operational-health/workbook-parameters.dev.json

# Error Diagnostics
az deployment group create \
  --resource-group rg-agent-observability-dev \
  --template-file agent-observability-foundation/workbooks/error-diagnostics/workbook-template.json \
  --parameters @agent-observability-foundation/workbooks/error-diagnostics/workbook-parameters.dev.json

# Usage Overview
az deployment group create \
  --resource-group rg-agent-observability-dev \
  --template-file agent-observability-foundation/workbooks/usage-overview/workbook-template.json \
  --parameters @agent-observability-foundation/workbooks/usage-overview/workbook-parameters.dev.json
```

**Production Environment:**
Replace `workbook-parameters.dev.json` with `workbook-parameters.prod.json` and use production resource group name.

**Idempotent Deployment:**
Re-running deployment commands updates existing workbooks (does not create duplicates) because templates use fixed workbookId GUIDs in parameter files. This pattern supports safe CI/CD pipeline integration.

## Directory Structure

```
workbooks/
├── README.md                          # This file
├── operational-health/
│   ├── workbook-template.json         # ARM template (4 tabs)
│   ├── workbook-parameters.dev.json   # Dev environment parameters
│   └── workbook-parameters.prod.json  # Prod environment parameters
├── error-diagnostics/
│   ├── workbook-template.json         # ARM template (5 tabs)
│   ├── workbook-parameters.dev.json   # Dev environment parameters
│   └── workbook-parameters.prod.json  # Prod environment parameters
└── usage-overview/
    ├── workbook-template.json         # ARM template (5 tabs)
    ├── workbook-parameters.dev.json   # Dev environment parameters
    └── workbook-parameters.prod.json  # Prod environment parameters
```

## KQL Query Source

Workbooks embed KQL queries from the Phase 2 query library (agent-observability-foundation/queries/). This table maps workbook visualizations to source queries for cross-reference:

**Operational Health Workbook:**
| Tab | Visualization | Source Query |
|-----|---------------|--------------|
| Overview | Overall metrics tiles | agent-usage-analytics.kql |
| Overview | Error rate trend | error-trend-analysis.kql |
| Overview | Success rate by agent | agent-usage-analytics.kql (modified for bottom 20) |
| Availability | Agent availability grid | agent-usage-analytics.kql |
| Error Rates | Error categorization | error-categorization-by-type.kql |
| Latency | P50/P95/P99 line chart | latency-distribution.kql |

**Error Diagnostics Workbook:**
| Tab | Visualization | Source Query |
|-----|---------------|--------------|
| Error Summary | Total errors, error rate | error-trend-analysis.kql |
| Error Summary | Error distribution donut | error-categorization-by-type.kql |
| Error Drill-Down | Errors by agent | error-categorization-by-type.kql (aggregated by agent) |
| Root Cause Analysis | Flow failure correlation | flow-execution-failures.kql |
| Root Cause Analysis | RAI content filtering | rai-content-filter-detections.kql |

**Usage Overview Workbook:**
| Tab | Visualization | Source Query |
|-----|---------------|--------------|
| Adoption Overview | Total agents, sessions, users | agent-usage-analytics.kql |
| Adoption Overview | Daily sessions trend | agent-usage-analytics.kql (time chart) |
| Engagement | Unique users per day | agent-usage-analytics.kql (user count) |
| Engagement | Completion rates pie chart | agent-usage-analytics.kql (completion rate calculation) |
| Generative AI Quality | Generative answers quality | generative-answers-telemetry.kql |

**Query Parameter Syntax:**
Workbook queries use parameter reference syntax like `{TimeRange:default}` and `{Zone:all}` for seamless integration with global parameters. This differs slightly from standalone .kql files which use KQL `let` statements for parameters.

## Related Documentation

- **Phase 2 Summary:** [03-02-SUMMARY.md](../../.planning/phases/03-azure-monitor-workbooks-alert-rules/03-02-SUMMARY.md) - KQL query library development
- **Governance Mapping:** [governance-mapping.md](../governance-mapping.md) - Control alignment for telemetry artifacts
- **Architecture Overview:** [architecture.md](../architecture.md) - Data flow and component details
- **Framework Zones:** [FSI-AgentGov zones-and-tiers.md](https://github.com/judeper/FSI-AgentGov/blob/main/docs/framework/zones-and-tiers.md) - Governance zone definitions

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Workbook shows "No data available" | Application Insights has no telemetry | Configure Copilot Studio agents to send telemetry to Application Insights resource ID specified in parameter file |
| Zone parameter shows no results | customDimensions['Zone'] field missing | Verify Copilot Studio agents emit zone metadata or add enrichment via Application Insights custom processors |
| Drill-down links don't navigate | Workbook context blade missing | Verify parameter passing in link formatter configuration, check workbook serializedData syntax |
| Deployment fails with "Conflict" | Duplicate workbookId in same resource group | Check parameter files for unique workbookId GUIDs per environment (dev vs prod) |
| Queries timeout after 30 seconds | KQL query not optimized | Review query optimization guidance in Phase 2 queries/README.md, ensure TimeGenerated filters present |

---

*Version: 1.0.0*
*Last Updated: February 2026*
*Part of FSI-AgentGov-Solutions*
