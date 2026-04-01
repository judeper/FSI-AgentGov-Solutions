# Agent Assisted Hours Methodology

This document describes the Agent Assisted Hours (AAH) calculation methodology used by Copilot Studio Analytics, covering both conversational and autonomous agent formulas.

## Overview

Agent Assisted Hours (AAH) estimates the human labor hours saved by Copilot Studio agents. This is the primary metric for quantifying business impact and calculating return on investment. CSA provides two separate AAH formulas because conversational and autonomous agents have fundamentally different interaction models.

### Why Two Formulas

| Agent Type | Interaction Model | Value Driver |
|-----------|-------------------|-------------|
| **Conversational** | User asks questions, agent provides answers | Time saved answering questions, providing information |
| **Autonomous** | Agent executes tasks triggered by events | Time saved automating workflows, retrieving information |

A single formula cannot accurately capture the different ways these agent types deliver value. Conversational agents save time by handling inquiries; autonomous agents save time by automating multi-step processes.

---

## Conversational Agent Formula

### Formula

```
AAH = (KnowledgeSourceReferences + WeightedSessionsWithoutKS) x TimeSavingsMultiplier
```

### Components

**KnowledgeSourceReferences** -- Sessions where the agent cited at least one knowledge source.

| Tier | Measurement Method | Precision |
|------|-------------------|-----------|
| Tier 1 | Proxy via GenerativeAnswers events in App Insights where Result = "Success" | Approximate -- counts events, not distinct citations |
| Tier 2 *(planned)* | Parse conversationtranscript content JSON for Citation entities | Precise -- exact count of knowledge source citations per session *(not yet implemented)* |

**WeightedSessionsWithoutKS** -- Sessions that did not involve knowledge source citations, weighted by outcome quality.

| Session Outcome | Has Knowledge Source | Weight | Rationale |
|----------------|---------------------|--------|-----------|
| Resolved | No | 1.0 | Successfully resolved without KS -- full time savings |
| Escalated | No | 0.7 | Partial assistance before handoff -- partial time savings |
| Abandoned | No | 0.7 | Some assistance provided before user departed -- partial time savings |
| Unengaged | No | 0.0 (excluded) | No meaningful interaction -- no time savings |

**TimeSavingsMultiplier** -- Estimated minutes saved per assisted session.

| Parameter | Default | Configurable | Notes |
|-----------|---------|-------------|-------|
| TimeSavingsMultiplier | 6 minutes | Yes (config.yml) | Based on industry benchmarks for knowledge worker inquiry handling |

### Calculation Example

Given 1,000 conversational sessions in a period:

| Component | Count | Calculation |
|-----------|-------|-------------|
| Sessions with KS citations | 400 | 400 |
| Resolved without KS | 200 | 200 x 1.0 = 200 |
| Escalated without KS | 150 | 150 x 0.7 = 105 |
| Abandoned without KS | 100 | 100 x 0.7 = 70 |
| Unengaged | 150 | Excluded |
| **Total assisted interactions** | | 400 + 200 + 105 + 70 = **775** |
| **AAH** | | 775 x 6 min / 60 = **77.5 hours** |

### Cost Avoidance

```
AgentAssistedCost = AAH x HourlyRate
```

| Parameter | Default | Configurable | Notes |
|-----------|---------|-------------|-------|
| HourlyRate | $72/hr | Yes (config.yml) | Approximate fully-loaded cost for knowledge worker |

For the example above: 77.5 hours x $72/hr = **$5,580** in estimated cost avoidance.

---

## Autonomous Agent Formula

### Formula

```
AAH = (
    KS_References x InfoRetrievalTimeSaving
  + TotalTimeSavedAutomatingActions
  + SuccessfulSessionsWithoutIndependentActions x GenericTimeSaving
) / 60
```

### Components

**KS_References** -- Information retrieval actions where the agent fetched knowledge source content.

| Parameter | Default | Configurable | Notes |
|-----------|---------|-------------|-------|
| InfoRetrievalTimeSaving | 6 minutes | Yes (config.yml) | Time saved per information retrieval vs manual lookup |

**TotalTimeSavedAutomatingActions** -- Sum of time savings from executed automation actions.

Each action type has a configurable time saving value:

| Action Category | Default Time Saving | Example Actions |
|----------------|-------------------|-----------------|
| Data entry / form submission | 10 minutes | Create record, update record |
| Information retrieval | 5 minutes | Query database, search documents |
| Notification / routing | 3 minutes | Send email, post message, assign task |
| Approval workflow | 15 minutes | Submit approval, process approval |
| Custom connector action | 8 minutes | API call to external system |

> **Note:** Action time savings are configurable per action name in config.yml. The defaults above are starting points -- organizations should adjust based on their measured manual process times.

**SuccessfulSessionsWithoutIndependentActions** -- Autonomous sessions that completed successfully but did not execute any independently measurable actions (e.g., simple routing or triage).

| Parameter | Default | Configurable | Notes |
|-----------|---------|-------------|-------|
| GenericTimeSaving | 3 minutes | Yes (config.yml) | Minimum time saving for successful autonomous task completion |

### Calculation Example

Given 500 autonomous agent runs in a period:

| Component | Count | Time Saving | Total Minutes |
|-----------|-------|-------------|---------------|
| KS retrievals | 100 | 5 min each | 500 |
| Data entry actions | 80 | 10 min each | 800 |
| Notification actions | 120 | 3 min each | 360 |
| Approval actions | 30 | 15 min each | 450 |
| Sessions without actions | 170 | 3 min each | 510 |
| **Total minutes** | | | **2,620** |
| **AAH** | | | 2,620 / 60 = **43.7 hours** |

---

## Tier 1 vs Tier 2 Precision (Tier 2 Planned)

> **Note:** Tier 2 data processing (transcript parsing, per-action tracking) is planned for a future release and is not yet implemented in the sync pipeline. The precision comparisons below describe the intended design. Current deployments operate on Tier 1 data only.

The accuracy of AAH calculations depends on the data tier available.

| Metric | Tier 1 Source | Tier 2 Source *(planned)* | Precision Difference |
|--------|-------------|-------------|---------------------|
| Knowledge source citations | GenerativeAnswers (Result = "Success") | conversationtranscript Citation entities *(planned)* | Tier 1 may overcount (one event per generative call, not per citation) |
| Action execution count | Not available in Tier 1 | conversationtranscript invoke activities *(planned)* | Tier 1 autonomous AAH uses session-level estimates only |
| Session outcome | msdyn_botsession.msdyn_sessionoutcome | Same | No difference |
| CSAT score | msdyn_botsession.msdyn_csatscore | Same | No difference |

### Impact on AAH Accuracy

| Scenario | Tier 1 AAH | Tier 2 AAH *(planned)* | Variance |
|----------|-----------|-----------|----------|
| Conversational agents (KS-heavy) | May overcount by 10-20% | Precise | Moderate |
| Conversational agents (few KS) | Close to Tier 2 *(planned)* | Precise | Low |
| Autonomous agents | Session-level estimate only | Per-action granularity | Significant |

> **Recommendation:** Use Tier 1 for current deployments. Tier 2 (transcript parsing for precise per-action and per-citation data) is planned for a future release.

---

## Maker-Led Inputs (Viva-Only Limitation)

Microsoft Viva Insights includes a feature where agent makers can specify custom time savings values per topic or action directly in Copilot Studio. This "maker-led input" approach allows the person who built the agent to estimate how much time each topic or action saves.

**CSA does not replicate this feature** because:

1. Maker-led inputs are stored in Viva Insights backend, not in Dataverse or App Insights
2. There is no public API to read or write maker-led estimates
3. CSA uses configurable defaults in config.yml as an alternative

### Workaround

Organizations without Viva Insights can approximate maker-led inputs by:

1. Surveying agent makers for estimated time savings per topic/action
2. Updating the `action_time_savings` section in config.yml with these estimates
3. Periodically reviewing and adjusting estimates based on observed patterns

---

## Configuration Guidance

### When to Adjust Multipliers

| Scenario | Adjustment | Rationale |
|----------|-----------|-----------|
| High-complexity knowledge domain | Increase TimeSavingsMultiplier to 10-15 min | Complex inquiries save more time per interaction |
| Simple FAQ agent | Decrease TimeSavingsMultiplier to 2-3 min | Simple lookups save less time |
| Long manual processes being automated | Increase action-level time savings | Automation of complex workflows saves more time |
| Agent handles mostly routing | Decrease GenericTimeSaving to 1-2 min | Simple routing provides minimal time savings |

### Configuration Example

```yaml
business_impact:
  conversational:
    time_savings_minutes: 6
    resolved_no_ks_weight: 1.0
    escalated_abandoned_no_ks_weight: 0.7
  autonomous:
    info_retrieval_time_saving_minutes: 6
    generic_action_multiplier_minutes: 3
    generic_time_saving_minutes: 5
    action_multipliers:
      # Per-action-type overrides (Tier 2 — planned, not yet implemented)
      # data_entry: 10
      # notification: 3
      # approval: 15
  hourly_rate: 72
```

---

## CSA Calculation vs Viva Insights Calculation

| Aspect | CSA | Viva Insights |
|--------|-----|---------------|
| **Data source** | Dataverse msdyn_botsession + App Insights | Viva Insights backend telemetry |
| **KS citation method** | Tier 1 proxy (topic-name heuristic) | Direct platform integration |
| **Time savings input** | Configurable defaults in config.yml | Maker-led inputs per topic/action |
| **Outcome weighting** | Configurable weights per outcome type | Fixed weighting (not configurable) |
| **Autonomous agent support** | Separate formula with session-level estimates (per-action granularity planned for Tier 2) | Included in unified calculation |
| **Customization** | Full control over all parameters | Limited to maker-led inputs |
| **License requirement** | None (uses existing AOF infrastructure) | Viva Insights license required |
| **Historical recalculation** | Supported (change config, re-query) | Not supported (calculated at event time) |

---

*Agent Assisted Hours Methodology version: 1.0.0*
*Last updated: February 2026*
