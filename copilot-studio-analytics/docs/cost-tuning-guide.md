# Cost Tuning Guide

Guidance for optimizing Copilot Studio Analytics costs, including sync frequency tuning, data volume estimation, and Application Insights ingestion management.

## Overview

CSA adds incremental cost to your existing AOF infrastructure by syncing Dataverse session records into Application Insights as CopilotSessionOutcome custom events. The primary cost drivers are sync frequency, the number of agents and sessions, and the data tier selected (Tier 1 implemented; Tier 2 planned).

This guide helps balance analytics freshness against ingestion costs.

## Cost Components

| Component | Cost Driver | Who Pays |
|-----------|-----------|----------|
| Application Insights ingestion | CopilotSessionOutcome events per sync cycle | CSA (incremental to AOF) |
| Dataverse API calls | OData queries per sync cycle | CSA (minimal -- covered by Power Platform license) |
| Log Analytics retention | Storage of CopilotSessionOutcome events | Shared with AOF (same workspace) |
| Workbook queries | KQL compute per dashboard load | Shared with AOF (same workspace) |

> **Note:** CSA does not deploy additional Azure resources. All costs are incremental to the existing AOF Application Insights and Log Analytics workspace.

---

## Sync Frequency Tuning

The sync script (`sync_dataverse_sessions.py`) can run at different frequencies. Each run queries Dataverse for new sessions since the last watermark and emits events to Application Insights.

### Frequency Options

| Frequency | Use Case | App Insights Events/Day | Freshness |
|-----------|----------|------------------------|-----------|
| **Daily (1x)** | Standard analytics, cost-optimized | 1 batch per day | Up to 24 hours stale |
| **Twice daily (2x)** | Balanced freshness and cost | 2 batches per day | Up to 12 hours stale |
| **Every 6 hours (4x)** | Near-real-time dashboards | 4 batches per day | Up to 6 hours stale |
| **Every 4 hours (6x)** | High-priority agents | 6 batches per day | Up to 4 hours stale |

### Impact on Ingestion Cost

The number of CopilotSessionOutcome events ingested depends on session volume, not sync frequency. Running the sync more often does **not** increase event count (watermark prevents duplicates). However, more frequent syncs incur:

- **API overhead:** Each sync cycle includes Dataverse API calls and App Insights Track API calls
- **Batch metadata:** Small overhead per batch (watermark reads/writes)
- **Compute cost:** Python runtime (minimal if running on existing infrastructure)

**Bottom line:** Sync frequency primarily affects data freshness, not ingestion cost. The number of events is determined by session volume.

### Recommended Frequency by Scenario

| Scenario | Recommended Frequency | Rationale |
|----------|----------------------|-----------|
| Initial deployment / pilot | Daily | Minimize cost during validation |
| Production with weekly reporting | Daily | Sufficient freshness for weekly dashboards |
| Production with daily standups | Twice daily | Morning sync captures previous day |
| Executive-facing dashboards | Every 6 hours | Near-real-time for leadership visibility |
| Regulatory reporting | Daily | Compliance reports typically run on batch cycles |

---

## Data Volume Estimation

Use this formula to estimate monthly Application Insights ingestion from CSA:

```
Monthly GB = (SessionsPerDay x EventSizeKB x 30) / (1024 x 1024)
```

### Event Size Reference

| Event Type | Approximate Size | Notes |
|-----------|-----------------|-------|
| CopilotSessionOutcome (Tier 1) | ~1.5 KB | Session outcome, CSAT, agent metadata |
| CopilotSessionOutcome (Tier 2 enriched) *(planned)* | ~3.0 KB | Adds topic counts, action counts, KS count |

### Volume Estimation Table

| Agents | Sessions/Day | Monthly Events | Monthly GB (Tier 1) | Monthly GB (Tier 2) *(planned)* | Est. Monthly Cost |
|--------|-------------|----------------|--------------------|--------------------|-------------------|
| 1-5 | 50-200 | 1,500-6,000 | < 0.01 GB | < 0.02 GB | < $1 |
| 5-20 | 200-2,000 | 6,000-60,000 | 0.01-0.09 GB | 0.02-0.18 GB | $1-5 |
| 20-50 | 2,000-10,000 | 60,000-300,000 | 0.09-0.45 GB | 0.18-0.90 GB | $5-15 |
| 50-100 | 10,000-50,000 | 300,000-1,500,000 | 0.45-2.25 GB | 0.90-4.50 GB | $15-50 |
| 100+ | 50,000+ | 1,500,000+ | 2.25+ GB | 4.50+ GB | $50+ |

> **Note:** These are CSA-specific costs. Total Application Insights costs include AOF native telemetry events (BotMessageSend, GenerativeAnswers, etc.) which are typically 5-10x the CSA event volume.

### Monitoring Actual Ingestion

Use this KQL query to measure CSA-specific ingestion volume:

```kusto
customEvents
| where name == "CopilotSessionOutcome"
| where timestamp > ago(30d)
| summarize
    EventCount = count(),
    EstimatedGB = sum(estimate_data_size(*)) / 1024 / 1024 / 1024
    by bin(timestamp, 1d)
| order by timestamp desc
```

---

## Application Insights Sampling Considerations

### CSA Events vs Native Events

Application Insights ingestion sampling applies uniformly to all events in the workspace. If you enable sampling to manage AOF costs, CSA events are also affected.

| Sampling Rate | Impact on CSA | Impact on AOF | Recommendation |
|---------------|-------------|-------------|----------------|
| 100% | Full precision for all metrics | Full cost | Recommended for compliance environments |
| 75% | Minor AAH variance (< 5%) | 25% cost reduction | Acceptable for most scenarios |
| 50% | Moderate AAH variance (5-15%) | 50% cost reduction | Document in compliance procedures |
| 25% | Significant AAH variance (15-30%) | 75% cost reduction | Not recommended for production analytics |

> **Compliance note:** If ingestion sampling reduces CSA event count, document this in your Control 3.2 evidence procedures. Sampled analytics provide directional accuracy but may not satisfy precise audit requirements.

### Selective Sampling Alternative

If CSA events are a small fraction of total ingestion (typical), consider:

1. Keep ingestion sampling at 100% for the workspace
2. Manage AOF costs through other means (Basic Logs for verbose traces, shorter retention for debug data)
3. CSA events remain at full precision with minimal cost impact

---

## Workbook Query Optimization

Azure Monitor Workbooks execute KQL queries each time a user opens or refreshes a dashboard. Poorly optimized queries increase Log Analytics compute costs.

### Optimization Tips

| Technique | Impact | Example |
|-----------|--------|---------|
| **Use time range parameters** | Reduces scanned data | `where timestamp > {TimeRange:start}` instead of `ago(90d)` |
| **Filter early** | Reduces rows processed | Put `where name == "CopilotSessionOutcome"` before joins |
| **Avoid `*` in summarize** | Reduces computation | Use `summarize count()` not `summarize count(*)` |
| **Use materialized views** | Pre-aggregates common queries | Consider for high-frequency dashboards |
| **Limit cardinality** | Reduces rendering cost | `take 50` or `top 20 by count_ desc` for agent lists |
| **Cache workbook results** | Reduces repeated queries | Set workbook auto-refresh interval to 30+ minutes |

### Query Performance Baseline

| Query Category | Expected Execution Time | Data Scanned (30-day) |
|----------------|------------------------|----------------------|
| Agent Overview | < 5 seconds | CopilotSessionOutcome events only |
| Session Outcomes | < 10 seconds | CopilotSessionOutcome + native events |
| Business Impact | < 15 seconds | CopilotSessionOutcome + GenerativeAnswers |
| Behavior Metrics (Tier 2) *(planned)* | < 20 seconds | CopilotSessionOutcome + topic/action data |

---

## Retention Period Impact

CopilotSessionOutcome events inherit the Log Analytics workspace retention configured by AOF (typically 730 days). There is no separate retention setting for CSA data.

### Retention Cost Impact

| Retention Period | Log Analytics Cost Factor | CSA Impact |
|------------------|--------------------------|-----------|
| 90 days | Baseline | Sufficient for operational analytics |
| 365 days | ~4x baseline | Full year for annual reporting |
| 730 days | ~8x baseline | Matches AOF retention; recommended for compliance |

> **Recommendation:** Match CSA data retention to AOF retention (730 days) for consistent analytics coverage. The incremental cost of retaining CSA events is small relative to AOF native telemetry.

---

## Tier 1 vs Tier 2 Cost Comparison

> **Note:** Tier 2 data processing (transcript parsing, per-action tracking) is planned for a future release. The cost estimates below describe the intended design. Current deployments operate on Tier 1 only.

| Aspect | Tier 1 | Tier 2 *(planned)* | Difference |
|--------|--------|--------|-----------|
| Dataverse API calls per sync | Low (3 queries: sessions, bots, components) | Higher (5+ queries: adds topic sessions, transcripts) | 2-3x more API calls |
| Event size | ~1.5 KB per event | ~3.0 KB per event | 2x larger events |
| App Insights ingestion | Lower | Higher | ~2x ingestion volume |
| Transcript JSON parsing | None | CPU-intensive content parsing | Additional compute cost |
| Dataverse storage | Standard | Higher (transcript retention extended) | Significant if transcripts retained > 90 days |
| Analytics precision | Approximate (KS proxy, session-level AAH) | Precise (exact KS count, per-action AAH) *(planned)* | Tier 2 precision planned for future release |

### Cost Recommendation by Organization Size

| Organization | Recommended Tier | Rationale |
|-------------|-----------------|-----------|
| Pilot (1-5 agents) | Tier 1 only | Low cost, sufficient for initial metrics |
| Mid-size (5-50 agents) | Tier 1 (Tier 2 when available) | Tier 2 planned for high-value agent analysis |
| Enterprise (50+ agents) | Tier 1 (Tier 2 when available) | Full precision planned for executive reporting |

---

## Cost Optimization Checklist

- [ ] **Sync frequency set** -- Daily for most scenarios; increase only when fresher data is needed
- [ ] **Volume estimated** -- Use the estimation table to project monthly costs
- [ ] **Sampling reviewed** -- Confirm ingestion sampling rate is appropriate for analytics precision needs
- [ ] **Workbook queries optimized** -- Apply time range filters and early filtering in all queries
- [ ] **Tier selection made** -- Tier 1 is currently implemented; Tier 2 is planned for a future release
- [ ] **Retention aligned** -- CSA retention matches AOF retention (no separate configuration needed)
- [ ] **Cost alerts configured** -- AOF cost alerts cover CSA events (same workspace)
- [ ] **Monitoring query saved** -- CopilotSessionOutcome ingestion monitoring query bookmarked

---

*Cost Tuning Guide version: 2.0.0*
*Last updated: February 2026*
