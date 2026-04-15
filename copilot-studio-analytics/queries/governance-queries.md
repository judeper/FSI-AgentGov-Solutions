# KQL Query Governance Mapping

This document maps Copilot Studio Analytics KQL queries to FSI-AgentGov framework controls with tiered evidence indicators and regulatory citations.

## Overview

The governance mapping uses an **artifact-first approach**: each query is documented with the framework controls it supports. Evidence contributions are classified using a three-tier model to clarify the strength of each query's role in satisfying compliance requirements.

This document complements the solution-level governance mapping by providing granular query-to-control traceability for audit preparation.

### Evidence Tier Definitions

| Tier | Indicator | Meaning |
|------|-----------|---------|
| **Primary evidence** | The query directly satisfies the control's evidence requirement |
| **Supporting evidence** | The query provides supplementary evidence alongside other controls |
| **Partial coverage** | The query provides some evidence but additional artifacts are needed |

> **Regulatory Language Note:** This document uses hedging language ("helps support", "aids in meeting") per FSI-AgentGov CONTRIBUTING.md guidelines. No control or query, on its own, supports compliance. Implementation, validation, and ongoing maintenance are required for compliance.

---

## Query-to-Control Mapping

### Agent Overview Queries

#### agent-inventory.kql

**Location:** `agent-overview/agent-inventory.kql`

**Description:** Agent inventory with conversational vs autonomous split and engagement rates for operational oversight.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [3.2 - Usage Analytics](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Agent inventory and usage metrics | FINRA 3110 supervision scope |

**Supporting evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [2.9 - Performance Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.9-agent-performance-monitoring-and-optimization.md) | Engagement baseline for optimization | OCC 2011-12 operational visibility |

**Sample Output:**

| AgentId | AgentType | TotalSessions | EngagedSessions | EngagementRate |
|---------|-----------|---------------|-----------------|----------------|
| agent-prod-001 | Conversational | 1245 | 987 | 79.3 |
| agent-prod-002 | Autonomous | 890 | 756 | 84.9 |

---

#### active-agents-trend.kql

**Location:** `agent-overview/active-agents-trend.kql`

**Description:** Daily active agent count by type for deployment growth monitoring.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [3.2 - Usage Analytics](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Agent population trend tracking | FINRA 3110 supervision population monitoring |

**Sample Output:**

| Timestamp | ActiveAgents | ConversationalCount | AutonomousCount |
|-----------|--------------|---------------------|-----------------|
| 2026-02-24 | 18 | 12 | 6 |
| 2026-02-23 | 17 | 11 | 6 |

---

#### top-agents-by-engagement.kql

**Location:** `agent-overview/top-agents-by-engagement.kql`

**Description:** Top N agents ranked by engaged sessions for supervisory focus.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [3.2 - Usage Analytics](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | High-activity agent identification | FINRA 3110 risk-based supervision |

**Sample Output:**

| AgentId | AgentType | EngagedSessions | TotalSessions | EngagementRate |
|---------|-----------|-----------------|---------------|----------------|
| agent-prod-001 | Conversational | 987 | 1245 | 79.3 |
| agent-prod-002 | Autonomous | 756 | 890 | 84.9 |

---

### Session Outcomes Queries

#### conversational-outcome-distribution.kql

**Location:** `session-outcomes/conversational-outcome-distribution.kql`

**Description:** Resolved/Abandoned/Escalated distribution for conversational agent effectiveness analysis.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [3.2 - Usage Analytics](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Session outcome tracking | FINRA 3110 resolution effectiveness monitoring |

**Supporting evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [2.9 - Performance Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.9-agent-performance-monitoring-and-optimization.md) | Outcome quality metrics | OCC 2011-12 ongoing monitoring |

**Sample Output:**

| Outcome | OutcomeReason | SessionCount | Percentage |
|---------|---------------|--------------|------------|
| Resolved | CustomerConfirmed | 523 | 52.8 |
| Escalated | AgentTransfer | 287 | 29.0 |

---

#### autonomous-outcome-distribution.kql

**Location:** `session-outcomes/autonomous-outcome-distribution.kql`

**Description:** Success/Failure distribution for autonomous agent reliability analysis.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [3.2 - Usage Analytics](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Autonomous process success rate tracking | SOX 404 automated control effectiveness |

**Sample Output:**

| Outcome | SessionCount | SuccessRate |
|---------|--------------|-------------|
| Success | 678 | 87.4 |
| Failure | 98 | 12.6 |

---

#### csat-score-trend.kql

**Location:** `session-outcomes/csat-score-trend.kql`

**Description:** CSAT score trend for conversational agent quality monitoring.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [3.2 - Usage Analytics](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Customer satisfaction metrics | OCC 2011-12 ongoing quality monitoring |

**Sample Output:**

| Timestamp | AgentId | AvgCSAT | ResponseCount |
|-----------|---------|---------|---------------|
| 2026-02-24 | agent-prod-001 | 4.2 | 87 |
| 2026-02-23 | agent-prod-001 | 3.9 | 92 |

---

#### resolution-satisfaction-matrix.kql

**Location:** `session-outcomes/resolution-satisfaction-matrix.kql`

**Description:** 2x2 quadrant analysis (resolution rate x CSAT) for agent prioritization.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [3.2 - Usage Analytics](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Multi-dimensional agent quality assessment | OCC 2011-12 ongoing monitoring and risk prioritization |

**Sample Output:**

| AgentId | ResolutionRate | AvgCSAT | Quadrant |
|---------|----------------|---------|----------|
| agent-prod-001 | 79.9 | 4.2 | High Resolution, High CSAT |
| agent-prod-002 | 59.9 | 4.1 | Low Resolution, High CSAT |

---

#### outcome-by-agent.kql

**Location:** `session-outcomes/outcome-by-agent.kql`

**Description:** Per-agent outcome breakdown supporting both conversational and autonomous types.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [3.2 - Usage Analytics](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Individual agent performance tracking | FINRA 3110 per-agent supervision |

**Sample Output:**

| AgentId | AgentType | EngagedSessions | ResolutionRate | AvgCSAT |
|---------|-----------|-----------------|----------------|---------|
| agent-prod-001 | Conversational | 987 | 79.9 | 4.2 |
| agent-auto-001 | Autonomous | 756 | 87.4 | |

---

### Business Impact Queries

#### conversational-assisted-hours.kql

**Location:** `business-impact/conversational-assisted-hours.kql`

**Description:** Agent Assisted Hours calculation for conversational agents using weighted session formula.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [3.2 - Usage Analytics](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Business value quantification | SOX 404 operational efficiency evidence |

**Sample Output:**

| AgentId | KSReferences | WeightedNonKS | TotalWeighted | AgentAssistedHours |
|---------|-------------|---------------|---------------|-------------------|
| agent-prod-001 | 523 | 312.4 | 835.4 | 83.5 |

---

#### autonomous-assisted-hours.kql

**Location:** `business-impact/autonomous-assisted-hours.kql`

**Description:** Agent Assisted Hours calculation for autonomous agents using 3-component formula.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [3.2 - Usage Analytics](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Autonomous process value quantification | SOX 404 automated control efficiency |

**Sample Output:**

| AgentId | KSSavings | ActionSavings | GenericSavings | AgentAssistedHours |
|---------|-----------|---------------|----------------|-------------------|
| agent-auto-001 | 12.4 | 8.7 | 15.2 | 36.3 |

---

#### agent-assisted-cost.kql

**Location:** `business-impact/agent-assisted-cost.kql`

**Description:** Cost savings by multiplying Agent Assisted Hours by configurable hourly rate.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [3.2 - Usage Analytics](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Financial impact reporting | OCC 2011-12 cost-benefit analysis for AI deployments |

**Sample Output:**

| AgentId | AgentType | AgentAssistedHours | CostSavings |
|---------|-----------|-------------------|-------------|
| agent-prod-001 | Conversational | 83.5 | 6012.0 |
| agent-auto-001 | Autonomous | 36.3 | 2613.6 |

---

#### roi-trend.kql

**Location:** `business-impact/roi-trend.kql`

**Description:** Weekly ROI trend with week-over-week change deltas for business impact tracking.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [3.2 - Usage Analytics](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Trend-based business impact reporting | SOX 404 ongoing efficiency monitoring |

**Sample Output:**

| WeekStart | TotalHours | TotalCost | WoWHoursChange | WoWCostChange |
|-----------|------------|-----------|----------------|---------------|
| 2026-02-17 | 245.6 | 17683.2 | 12.3 | 12.3 |
| 2026-02-10 | 218.7 | 15746.4 | -3.5 | -3.5 |

---

### Behavior Metrics Queries

#### sessions-per-topic.kql

**Location:** `behavior-metrics/sessions-per-topic.kql`

**Description:** Topic distribution analysis across agents for content coverage assessment.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [3.2 - Usage Analytics](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Topic-level activity monitoring | FINRA 3110 topic supervision coverage |

**Sample Output:**

| AgentId | AgentType | Topic | SessionCount | EngagedCount |
|---------|-----------|-------|--------------|--------------|
| agent-prod-001 | Conversational | AccountInquiry | 342 | 298 |
| agent-prod-001 | Conversational | LoanStatus | 187 | 165 |

---

#### sessions-per-action.kql

**Location:** `behavior-metrics/sessions-per-action.kql`

**Description:** Action invocation frequency for connector and plugin usage analysis.

> **Note:** This query requires Tier 2 sync (transcript parsing) for action data. Tier 2 is planned for a future release and is not yet implemented in the sync pipeline. Until then, this query will return no results.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [3.2 - Usage Analytics](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Action execution monitoring | SOX 404 automated action audit trail |

**Sample Output:**

| AgentId | ActionName | InvocationCount |
|---------|------------|-----------------|
| agent-auto-001 | CreateServiceTicket | 234 |
| agent-auto-001 | LookupAccount | 189 |

---

#### sessions-per-trigger.kql

**Location:** `behavior-metrics/sessions-per-trigger.kql`

**Description:** Autonomous trigger distribution with completion time analysis.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [3.2 - Usage Analytics](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Autonomous process execution monitoring | OCC 2011-12 autonomous process performance |

**Supporting evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [2.9 - Performance Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.9-agent-performance-monitoring-and-optimization.md) | Completion time SLA monitoring | SOX 404 process timing controls |

**Sample Output:**

| AgentId | TriggerType | SessionCount | AvgCompletionSeconds | P50CompletionSeconds | P95CompletionSeconds |
|---------|-------------|--------------|---------------------|---------------------|---------------------|
| agent-auto-001 | Scheduled | 456 | 23.4 | 18.0 | 67.0 |
| agent-auto-001 | EventDriven | 234 | 45.2 | 32.0 | 120.0 |

---

## Control-to-Query Cross-Reference

| Control | Primary Evidence | Supporting Evidence |
|---------|------------------|---------------------|
| **3.2 - Usage Analytics** | All 15 queries | - |
| **2.9 - Performance Monitoring** | - | agent-inventory.kql, conversational-outcome-distribution.kql, sessions-per-trigger.kql |

---

## Regulatory Cross-Reference

| Regulation | Requirement | Supporting Queries |
|------------|-------------|-------------------|
| **FINRA 3110** | Supervision metrics and scope | agent-inventory.kql, active-agents-trend.kql, top-agents-by-engagement.kql, conversational-outcome-distribution.kql, outcome-by-agent.kql, sessions-per-topic.kql |
| **SOX 404** | Operational control evidence | agent-inventory.kql, autonomous-outcome-distribution.kql, conversational-assisted-hours.kql, autonomous-assisted-hours.kql, agent-assisted-cost.kql, roi-trend.kql, sessions-per-action.kql, sessions-per-trigger.kql |
| **OCC 2011-12** | Operational risk and ongoing monitoring | active-agents-trend.kql, conversational-outcome-distribution.kql, csat-score-trend.kql, resolution-satisfaction-matrix.kql, agent-assisted-cost.kql, sessions-per-trigger.kql |

---

## Query Library Summary

| Folder | Query Count | Primary Control |
|--------|-------------|-----------------|
| agent-overview/ | 3 | 3.2 |
| session-outcomes/ | 5 | 3.2 |
| business-impact/ | 4 | 3.2 |
| behavior-metrics/ | 3 | 3.2 |
| **Total** | **15** | **1 primary control** |

---

*Governance Queries Mapping version: 1.0.0*
*Last updated: February 2026*
