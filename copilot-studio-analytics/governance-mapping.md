# Governance Mapping

This document maps Copilot Studio Analytics artifacts to the FSI-AgentGov framework control they support with evidence tier indicators.

## Overview

CSA focuses on a single governance control: **Control 3.2 -- Usage Analytics and Activity Monitoring**. Where AOF covers the operational scope of Control 3.2 (session volumes, error rates, latency), CSA covers the business impact scope (outcomes, CSAT, ROI, adoption).

> **AOF + CSA together** provide comprehensive Control 3.2 coverage. Neither solution alone addresses the full control scope.

### Evidence Tier Definitions

| Tier | Indicator | Meaning |
|------|-----------|---------|
| **Primary evidence** | The artifact directly satisfies the control's evidence requirement |
| **Supporting evidence** | The artifact provides supplementary evidence alongside other controls |

> **Regulatory Language Note:** This document uses hedging language ("helps support", "aids in meeting") per FSI-AgentGov CONTRIBUTING.md guidelines. No control or artifact alone is sufficient for compliance. Implementation, validation, and ongoing maintenance are required.

---

## CSA Artifacts

### Dataverse Session Sync Script

**Artifact:** `sync_dataverse_sessions.py`
**Description:** Syncs msdyn_botsession outcome records from Dataverse to Application Insights as CopilotSessionOutcome custom events with watermark-based incremental processing.

**Primary evidence for:**

| Control | Requirement | How This Artifact Supports |
|---------|-------------|---------------------------|
| [3.2 - Usage Analytics and Activity Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Session outcome data for business impact analytics | Bridges Dataverse session records into the centralized telemetry platform for unified querying |

**Evidence details:**
- Session outcomes (Resolved, Escalated, Abandoned, Unengaged) synced per agent
- CSAT scores captured when survey is enabled
- Agent type classification (conversational vs autonomous)
- Watermark tracking for incremental sync integrity

---

### KQL Query Library

**Artifact:** 15 queries across `queries/` directory in 4 categories
**Description:** Production-ready KQL queries for business impact analysis of Copilot Studio agents.

**Primary evidence for:**

| Control | Requirement | How This Artifact Supports |
|---------|-------------|---------------------------|
| [3.2 - Usage Analytics and Activity Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Structured analytics queries for usage reporting | 15 queries covering agent inventory, session outcomes, business impact (AAH, cost, ROI), and behavior metrics |

**Query categories and evidence contribution:**

| Category | Queries | Evidence Contribution |
|----------|---------|----------------------|
| Agent Overview | 3 | Agent inventory, adoption trends, top agents -- supports activity monitoring |
| Session Outcomes | 5 | Outcome distribution, CSAT, resolution matrix -- supports usage analytics |
| Business Impact | 4 | AAH, cost avoidance, ROI trend -- supports business impact reporting |
| Behavior Metrics | 3 | Topic performance, actions, triggers -- supports activity monitoring |

---

### Azure Monitor Workbooks

**Artifact:** 4 workbooks with 14 tabs across `workbooks/` directory
**Description:** Interactive dashboards deployed to Azure Monitor for visual analytics of Copilot Studio agent business impact.

**Primary evidence for:**

| Control | Requirement | How This Artifact Supports |
|---------|-------------|---------------------------|
| [3.2 - Usage Analytics and Activity Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Interactive dashboards for usage monitoring | 4 workbooks covering agent overview, quality metrics, business impact, and behavior analysis |

**Workbook evidence contribution:**

| Workbook | Tabs | Evidence Contribution |
|----------|------|----------------------|
| Agent Overview | 3 | Visual agent inventory and adoption trends |
| Quality Metrics | 4 | Session outcome analysis and CSAT visualization |
| Business Impact | 3 | AAH calculations, cost avoidance, ROI tracking |
| Behavior Analysis | 4 | Topic and action performance drill-down (Actions and trigger type tabs depend on Tier 2 data -- planned) |

---

### Viva Insights Parity Matrix

**Artifact:** `docs/viva-insights-parity-matrix.md`
**Description:** Documents CSA feature coverage relative to Microsoft Viva Insights with honest parity assessments.

**Supporting evidence for:**

| Control | Requirement | How This Artifact Supports |
|---------|-------------|---------------------------|
| [3.2 - Usage Analytics and Activity Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Documentation of analytics capability coverage | Demonstrates awareness of analytics gaps and provides guidance on when Viva Insights is needed |

---

## AOF Boundary

> CSA focuses on the **business impact scope** of Control 3.2 (outcomes, CSAT, ROI, adoption). AOF covers the **operational scope** (session volumes, error rates, latency). Together they provide comprehensive Control 3.2 coverage.

| Scope | Owner | Artifacts |
|-------|-------|-----------|
| Operational monitoring | AOF | Application Insights, KQL queries (performance), Operational Health Workbook |
| Business impact analytics | CSA | Dataverse sync, KQL queries (outcomes/impact), Business Impact Workbook |
| Adoption and engagement | Shared | AOF Usage Overview Workbook + CSA Agent Overview Workbook |

---

## Control Coverage Summary

| Control ID | Control Name | CSA Artifacts | Evidence Tier |
|------------|--------------|---------------|---------------|
| 3.2 | Usage Analytics and Activity Monitoring | Sync Script, KQL Library, Workbooks, Parity Matrix | Primary + Supporting |

---

*Governance Mapping version: 2.0.1*
*Last updated: 2026-Q2*
