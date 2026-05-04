# Cost Tuning Guide

Sampling configuration and cost management for Agent Observability Foundation telemetry infrastructure.

## Overview

Copilot Studio agents can generate high-cardinality telemetry events, especially with frequent user interactions. Without proper cost management, Azure Monitor costs can grow rapidly. This guide provides recommendations for configuring sampling rates, cost alert thresholds, and retention optimization.

## Cost Components

| Component | Pricing Model | Key Cost Driver |
|-----------|---------------|-----------------|
| **Application Insights ingestion** | Per GB ingested | Event volume and event payload size |
| **Log Analytics retention** | Per GB/month after free tier (31 days) | Retention period beyond free tier |
| **Azure Blob Storage (StorageV2)** | Per GB stored + operations | Retention duration and geo-replication |

### Current Pricing Reference (February 2026)

| Service | Tier | Approximate Cost |
|---------|------|------------------|
| Application Insights | Pay-as-you-go | ~$2.30/GB ingested |
| Log Analytics | PerGB2018 | ~$2.76/GB/month retained |
| Azure Blob Storage (StorageV2) | Hot tier, LRS | ~$0.018/GB/month |
| Azure Blob Storage (StorageV2) | Hot tier, GRS | ~$0.036/GB/month |

> **Note:** Prices vary by region and may change. Check [Azure pricing calculator](https://azure.microsoft.com/pricing/calculator/) for current rates.

---

## Sampling Configuration

### Understanding Sampling

Sampling reduces telemetry volume by capturing only a percentage of events. This decreases costs while preserving statistical validity for analytics.

**Key Limitation:** Adaptive sampling is NOT available for Copilot Studio telemetry. Copilot Studio sends telemetry server-side using internal instrumentation, not the client SDK. Therefore:

- SDK-level adaptive sampling does not apply
- Ingestion sampling at the Application Insights resource/workspace level is the primary cost control
- Fixed sampling rates are used (not adaptive based on volume)

### Recommended Sampling Rates

| Environment | Sampling Rate | Rationale |
|-------------|---------------|-----------|
| **Development/Test** | 25-50% | Reduced costs; statistical validity still sufficient for testing |
| **Production** | 100% | Capture all events for compliance and operational visibility |
| **Production (high volume)** | 50-75% | Balance cost with visibility; document sampling in compliance procedures |

> **Compliance Note:** If you reduce sampling below 100% in production, document this in your compliance procedures. Sampling may affect audit completeness for some regulatory requirements.

### Configuring Ingestion Sampling

**Azure Portal Steps:**

1. Navigate to your Application Insights resource
2. Click **Usage and estimated costs** in the left menu
3. Click **Data sampling**
4. Select the desired sampling percentage
5. Click **Apply**

**Impact:**
- Takes effect immediately for new data
- Does not affect already-ingested data
- Applies to all telemetry types uniformly

### Sampling Trade-offs

| Sampling Rate | Cost Impact | Analytics Impact |
|---------------|-------------|------------------|
| 100% | Full cost | Complete data for all queries |
| 75% | ~25% cost reduction | Statistical validity preserved for aggregates |
| 50% | ~50% cost reduction | Good for high-volume; individual event loss possible |
| 25% | ~75% cost reduction | Only for testing; not recommended for production |

---

## Cost Alert Thresholds

Configure Azure Monitor cost alerts to prevent unexpected charges.

### Recommended Thresholds

| Threshold | Alert Level | Action |
|-----------|-------------|--------|
| **50%** of monthly budget | Informational | Review current usage trends |
| **75%** of monthly budget | Warning | Investigate cause; consider sampling adjustment |
| **90%** of monthly budget | Critical | Immediate action required; may need to reduce retention or sampling |

### Configuring Cost Alerts

**Azure Portal Steps:**

1. Navigate to **Cost Management + Billing**
2. Select your subscription
3. Click **Cost alerts** > **+ Add**
4. Configure alert:
   - **Scope:** Resource group containing telemetry resources
   - **Alert condition:** Actual cost > threshold
   - **Budget amount:** Your monthly telemetry budget
   - **Threshold %:** 50, 75, or 90 as above
5. Configure action group for email notifications
6. Save the alert

### Budget Estimation

Use this table to estimate monthly telemetry costs based on agent volume:

| Agents | Events/Day (est.) | Monthly GB (est.) | App Insights Cost | Log Analytics Cost |
|--------|-------------------|-------------------|-------------------|-------------------|
| 1-5 | 1,000-5,000 | < 1 GB | ~$2-3 | ~$3-5 |
| 5-20 | 5,000-50,000 | 1-5 GB | ~$12-15 | ~$15-25 |
| 20-100 | 50,000-500,000 | 5-50 GB | ~$12-70 | ~$15-125 |
| 100+ | 500,000+ | 50+ GB | ~$115+ | ~$140+ |

> **Note:** Estimates only. Actual costs depend on event payload size, custom properties, and sampling configuration.

---

## Data Retention Cost Optimization

### Retention Tier Strategy

| Tier | Storage | Retention | Query Access | Cost Profile | Use Case |
|------|---------|-----------|--------------|--------------|----------|
| **Hot (Interactive)** | Log Analytics | 730 days | Real-time KQL | Higher cost/GB | Daily operations, incident response |
| **Archive** | Azure Blob Storage (StorageV2) | 6+ years | Blob access / Search jobs | Lower cost/GB | SEC 17a-4 long-term retention |

### Basic Logs Option

For high-volume tables with infrequent queries, consider Basic Logs:

**Benefits:**
- ~80% lower ingestion cost
- Same retention capabilities

**Limitations:**
- Reduced query capabilities (simple queries only)
- 8-day interactive query window
- Not suitable for real-time alerting

**When to Use:**
- Verbose trace logs
- Debug telemetry
- High-volume system events

**When NOT to Use:**
- Primary agent interaction telemetry (`AppEvents` / legacy `customEvents`)
- Any data needed for real-time monitoring or alerting

### Archive Tier for Azure Blob Storage (StorageV2)

For data beyond Log Analytics retention:

1. Configure Diagnostic Settings export to Azure Blob Storage (StorageV2)
2. Set blob lifecycle management policy:
   - Hot tier: First 30-90 days
   - Cool tier: 90 days to 1 year
   - Archive tier: 1+ years

---

## Cost Monitoring Queries

Use these KQL queries to monitor telemetry costs:

### Daily Ingestion Volume

```kusto
let startTime = ago(30d);
let endTime = now();
union withsource=Table *
| where timestamp between (startTime .. endTime)
| summarize
    EventCount = count(),
    EstimatedGB = sum(estimate_data_size(*)) / 1024 / 1024 / 1024
    by bin(timestamp, 1d), Table
| order by timestamp desc
```

### Top Tables by Volume

```kusto
union withsource=Table *
| where timestamp > ago(7d)
| summarize
    EventCount = count(),
    EstimatedGB = sum(estimate_data_size(*)) / 1024 / 1024 / 1024
    by Table
| order by EstimatedGB desc
| take 10
```

### AppEvents/customEvents Volume Trend

```kusto
let AgentEvents = materialize(
    union isfuzzy=true
        (AppEvents | project timestamp = TimeGenerated, name = tostring(Name)),
        (customEvents | project timestamp = todatetime(column_ifexists("timestamp", datetime(null))), name = tostring(column_ifexists("name", "")))
);
AgentEvents
| where timestamp > ago(30d)
| summarize EventCount = count() by bin(timestamp, 1d)
| render timechart
```

---

## Optimization Checklist

- [ ] **Sampling configured:** Set appropriate sampling rate for environment
- [ ] **Cost alerts enabled:** 50%, 75%, 90% thresholds configured
- [ ] **Retention optimized:** Hot tier for operational data, archive for compliance
- [ ] **Basic Logs evaluated:** Consider for high-volume, low-query tables
- [ ] **Budget established:** Monthly telemetry budget documented
- [ ] **Monitoring in place:** Regular review of cost trends

---

## Adaptive Sampling Limitation

> **Important:** Adaptive sampling is NOT available for Copilot Studio telemetry.

Adaptive sampling (which automatically adjusts sampling rate based on volume) applies to supported SDK-instrumented workloads, not the managed Copilot Studio telemetry stream configured by this solution.

Copilot Studio sends telemetry server-side through Microsoft's internal instrumentation. This means:
- You cannot configure adaptive sampling at the agent level
- Ingestion sampling at the Application Insights resource/workspace level is your primary cost control
- Fixed sampling rates apply uniformly to all events

If you need volume-based sampling, implement custom logic via Logic Apps or Azure Functions to pre-process events before ingestion.

---

*Cost Tuning Guide version: 1.2.1*
*Last updated: 2026-Q2*
