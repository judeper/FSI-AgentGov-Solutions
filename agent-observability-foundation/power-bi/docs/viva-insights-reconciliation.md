# Viva Insights Reconciliation Workflow

## Purpose

When organizations use both Viva Insights and Application Insights for agent monitoring, metric discrepancies are expected and normal. This workflow provides a systematic process for reconciling numbers across systems, identifying the source of discrepancies, and communicating findings to stakeholders.

> **Key Principle:** Discrepancies between Viva Insights and Application Insights are
> expected — they track different agent populations. This workflow helps classify
> discrepancies as expected vs. unexpected.

## Prerequisites
- Access to Viva Insights Agent Dashboard (Insights Analyst role)
- Access to Application Insights / Log Analytics (Reader role)
- Familiarity with KQL queries (agent-usage-analytics.kql)
- Power BI Desktop for side-by-side comparison (optional)

## Reconciliation Workflow

### Step 1: Export Viva Insights Metrics
1. Open Viva Insights → Copilot Studio Agents dashboard
2. Set date range to match reconciliation period (e.g., last 7 days)
3. Record key metrics:
   - Total active agents
   - Total sessions
   - Total active users
   - Average session duration
4. Export to Excel if available

### Step 2: Query Application Insights for Matching Period
Run the following KQL query (or use agent-usage-analytics.kql with matching date range):

```kql
// Application Insights agent count — ALL agent types
let AgentEvents = materialize(
    union isfuzzy=true
        (AppEvents | project timestamp = TimeGenerated, name = tostring(Name), customDimensions = todynamic(Properties), session_Id = tostring(column_ifexists("SessionId", ""))),
        (customEvents | project timestamp = todatetime(column_ifexists("timestamp", datetime(null))), name = tostring(column_ifexists("name", "")), customDimensions = todynamic(column_ifexists("customDimensions", dynamic({}))), session_Id = tostring(column_ifexists("session_Id", "")))
);
AgentEvents
| where timestamp between (datetime(YYYY-MM-DD) .. datetime(YYYY-MM-DD))
| where name in ("BotMessageReceived", "BotMessageSend")
| where coalesce(tostring(customDimensions['DesignMode']), tostring(customDimensions['designMode'])) == "False"
| extend AgentId = tostring(customDimensions["recipientId"])
| summarize
    TotalAgents = dcount(AgentId),
    TotalSessions = dcount(session_Id),
    TotalMessages = count()
```

Record totals for comparison.

### Step 3: Identify Agent Type Breakdown
Classify agents in Application Insights by type:

```kql
// Agent breakdown by type
let AgentEvents = materialize(
    union isfuzzy=true
        (AppEvents | project timestamp = TimeGenerated, name = tostring(Name), customDimensions = todynamic(Properties), session_Id = tostring(column_ifexists("SessionId", ""))),
        (customEvents | project timestamp = todatetime(column_ifexists("timestamp", datetime(null))), name = tostring(column_ifexists("name", "")), customDimensions = todynamic(column_ifexists("customDimensions", dynamic({}))), session_Id = tostring(column_ifexists("session_Id", "")))
);
AgentEvents
| where timestamp between (datetime(YYYY-MM-DD) .. datetime(YYYY-MM-DD))
| where name in ("BotMessageReceived", "BotMessageSend")
| where coalesce(tostring(customDimensions['DesignMode']), tostring(customDimensions['designMode'])) == "False"
| extend
    AgentId = tostring(customDimensions["recipientId"]),
    AgentType = case(
        isnotempty(tostring(customDimensions["copilotStudioAgent"])), "CopilotStudio",
        isnotempty(tostring(customDimensions["agent365Sdk"])), "Agent365SDK",
        "AgentBuilder"
    ),
    IsProduction = tostring(customDimensions["environment"]) == "Production"
| summarize
    Sessions = dcount(session_Id),
    Messages = count()
    by AgentId, AgentType, IsProduction
| summarize
    Agents = dcount(AgentId),
    TotalSessions = sum(Sessions)
    by AgentType, IsProduction
```

This query categorizes agents and flags Production vs. development/test environments.

### Step 4: Calculate Expected Discrepancy
The expected discrepancy equals agents NOT covered by Viva Insights:

| Source | Agents | Sessions | Expected in Viva? |
|--------|--------|----------|:--:|
| Copilot Studio (Production) | X | Y | YES |
| Copilot Studio (Dev/Test) | X | Y | NO |
| Agent Builder | X | Y | NO |
| Agent 365 SDK | X | Y | NO |
| **Viva Expected Total** | **Sum of YES** | **Sum of YES** | — |
| **App Insights Total** | **Sum of ALL** | **Sum of ALL** | — |
| **Expected Discrepancy** | **App - Viva** | **App - Viva** | — |

### Step 5: Compare Actual vs Expected
| Metric | Viva Insights (Actual) | App Insights | Expected Viva | Variance |
|--------|----------------------|--------------|---------------|----------|
| Agent count | A | B | C | A - C |
| Session count | D | E | F | D - F |

**Interpretation:**
- **Variance near zero:** Systems are consistent — discrepancy explained by agent type coverage
- **Variance > 10% of expected:** Investigate — possible telemetry gap, configuration issue, or agent miscategorization
- **Viva > Expected:** Possible: Viva counting agents not in App Insights (check telemetry configuration)
- **Viva < Expected:** Possible: Some Copilot Studio agents not publishing to Production environment

### Step 6: Investigate Unexpected Variance

If variance exceeds 10% threshold:

1. **Check agent publishing status:**
   Are all expected Copilot Studio agents published to Production? Agents in "published to test" won't appear in Viva.

2. **Check telemetry configuration:**
   Is Application Insights configured for all Copilot Studio environments? Missing configuration = missing data in App Insights.

3. **Check date alignment:**
   Viva uses weekly refresh. Ensure App Insights query covers the same complete weeks.

4. **Check anonymization thresholds:**
   Viva applies anonymization (minimum 10 users per aggregate). Low-usage agents may be suppressed.

5. **Check sampling configuration:**
   Application Insights sampling may drop events. Review sampling settings if App Insights shows fewer events than expected.

### Step 7: Document and Communicate

Create reconciliation report for stakeholders:

```markdown
## Reconciliation Report — [Date Range]

**Status:** [Consistent / Under Investigation]

| Metric | Viva Insights | App Insights | Discrepancy | Explained? |
|--------|:---:|:---:|:---:|:---:|
| Active agents | X | Y | Z | [Yes/No] |
| Total sessions | X | Y | Z | [Yes/No] |

**Explanation:** [Summary of why numbers differ]
**Action items:** [Any follow-up needed]
```

Share with operations, compliance, and executive teams as needed.

## Recommended Reconciliation Schedule

| Audience | Frequency | Focus |
|----------|-----------|-------|
| Operations team | Weekly | Verify agent counts, catch configuration drift |
| Compliance team | Monthly | Confirm all agent types accounted for, evidence completeness |
| Executive review | Quarterly | High-level adoption metrics, regulatory posture |

## Common Discrepancy Patterns

### Pattern 1: Viva Shows Fewer Agents Than Expected
**Cause:** Agent Builder agents visible in App Insights but not Viva.
**Resolution:** Expected behavior. Document Agent Builder count separately.

### Pattern 2: Viva Shows More Sessions Than App Insights
**Cause:** Application Insights sampling dropping events.
**Resolution:** Check sampling configuration. Consider fixed-rate sampling or increasing sample rate.

### Pattern 3: Historical Data Doesn't Match
**Cause:** Viva Insights started later than App Insights, or Viva's 28-day initial window hasn't accumulated full history yet.
**Resolution:** Use App Insights for historical trend analysis. Viva data accumulates over time (12-month history takes 12 months to build).

### Pattern 4: Sudden Drop in Viva Metrics
**Cause:** Agent republished to test environment, or Copilot license removed.
**Resolution:** Check agent publishing status and license assignments.

### Pattern 5: Zero Agents in Viva But Agents in App Insights
**Cause:** No Copilot Studio agents in Production, or anonymization threshold not met (fewer than 10 users).
**Resolution:** Verify Production environment has published agents. Check if organization has sufficient active users to meet anonymization threshold.

## Example Reconciliation

**Scenario:** February 1-7, 2026

**Step 1 — Viva Insights metrics:**
- Active agents: 15
- Sessions: 450
- Active users: 120

**Step 2 — App Insights query (all agent types):**
- Total agents: 28
- Total sessions: 890
- Total messages: 3,200

**Step 3 — Agent type breakdown:**
| Agent Type | Production | Sessions |
|-----------|:---:|:---:|
| Copilot Studio | YES (15 agents) | 450 |
| Copilot Studio | NO (3 agents) | 60 |
| Agent Builder | YES (8 agents) | 280 |
| Agent 365 SDK | YES (2 agents) | 100 |

**Step 4 — Expected discrepancy:**
- Viva expected: 15 agents (Copilot Studio Production only)
- App Insights total: 28 agents (all types)
- Expected discrepancy: 13 agents (3 dev/test + 8 Agent Builder + 2 Agent 365 SDK)

**Step 5 — Compare actual vs expected:**
- Viva actual: 15 agents
- Viva expected: 15 agents
- Variance: 0 agents ✓

**Step 6 — Investigation:** Not needed — variance is zero.

**Step 7 — Report:**
> Viva Insights and App Insights are consistent for Copilot Studio Production agents. Discrepancy of 13 agents explained by Agent Builder (8), Agent 365 SDK (2), and dev/test environments (3). No action required.

## Related Documentation
- [Viva Insights Scope and Limitations](viva-insights-scope.md)
- [Power BI Integration Guide](power-bi-integration.md)
- [Agent Usage Analytics Query](../../queries/usage-analytics/agent-usage-analytics.kql)
