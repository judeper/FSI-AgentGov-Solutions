# KQL Query Library

**Version:** 1.1.0
**Part of:** Agent Observability Foundation Solution
**Purpose:** Reusable KQL queries for Copilot Studio governance monitoring

## Overview

This query library provides production-ready KQL queries for extracting governance-relevant metrics from Copilot Studio Application Insights telemetry. The queries serve as the data extraction layer for:

- **Phase 3:** Azure Monitor Workbooks (interactive dashboards)
- **Phase 4:** Power BI dashboards (executive reporting)
- **Ad-hoc analysis:** Direct Log Analytics queries for incident investigation

All queries align with the [FSI-AgentGov framework](https://github.com/judeper/FSI-AgentGov) 78-control governance model and include inline control references for audit traceability.

## Query Organization

Queries are organized by **function** (not regulation) to maximize reusability:

```
queries/
├── README.md                     # This file
├── governance-queries.md         # Query-to-control mapping for audits
├── usage-analytics/              # Session and user engagement metrics
│   ├── agent-usage-analytics.kql     # Session/message volume trends
│   └── user-engagement-metrics.kql   # Distinct users, repeat sessions
├── error-categorization/         # Error classification and trends
│   ├── error-categorization-by-type.kql  # Connector/knowledge/orchestration buckets
│   └── error-trend-analysis.kql          # Error rate over time
├── performance/                  # Latency and response time metrics
│   ├── latency-distribution.kql      # P50/P95/P99 percentiles
│   └── slow-query-detection.kql      # Responses exceeding threshold
├── compliance/                   # Audit trail and regulatory evidence
│   ├── agent-decision-audit-trail.kql    # FINRA 3110 decision chain
│   ├── completeness-assessment.kql       # Telemetry gap detection
│   ├── rai-content-filtering-detection.kql  # RAI/XPIA/Jailbreak events
│   ├── generative-answers-telemetry.kql  # GenAI response quality
│   └── flow-failure-correlation.kql      # Power Automate failures
└── sr11-7-model-risk/           # SR 11-7 model risk monitoring
    ├── output-monitoring.kql         # Outcome analysis
    ├── drift-detection-baseline.kql  # Response pattern drift (20%)
    └── validation-test-results.kql   # Pass rate threshold (95%)
```

**Why function-based?** A single query often supports multiple regulations. For example, `agent-usage-analytics.kql` provides evidence for both FINRA 3110 (supervision metrics) and SOX 404 (operational monitoring). Organizing by function avoids query duplication.

## Query Header Format

Every `.kql` file includes a standardized header block for self-contained documentation:

```kql
// query-name.kql
// Purpose: Brief description of what the query extracts
//
// Parameters:
//   {TimeRange} - Time window (default: 7d) - workbook parameter syntax
//   {AgentId} - Optional agent filter (default: all agents)
//
// Output Schema:
//   ColumnName (type) - Description
//   Timestamp (datetime) - When the event occurred
//   AgentId (string) - Agent identifier
//
// Supports:
//   Control X.X (Primary) - Control name
//   Control Y.Y (Supporting) - Control name
//
// Sample Output:
// | Timestamp | AgentId | MetricValue |
// | 2026-02-04 | agent-001 | 342 |
```

This header format enables:
- Quick understanding without running the query
- Control traceability for audit preparation
- Workbook integration guidance

## Usage Instructions

### Azure Monitor Workbooks (Primary Use Case)

Queries use workbook parameter syntax `{Param:default}` for seamless dashboard integration:

```kql
let TimeRange = {TimeRange:7d};
let AgentId = "{AgentId}";
```

When adding queries to workbooks:
1. Create a time range parameter named `TimeRange` with default `7d`
2. Create a text parameter named `AgentId` with default `all`
3. Paste the query - parameters are automatically substituted

### Log Analytics Portal (Testing/Ad-hoc)

The `{Param:default}` syntax does NOT work in Log Analytics portal. Replace with literal values:

```kql
// Original (workbook syntax)
let TimeRange = {TimeRange:7d};

// For Log Analytics testing
let TimeRange = 7d;
```

**Quick test procedure:**
1. Copy the query from `.kql` file
2. Find/replace `{TimeRange:7d}` with `7d`
3. Find/replace `{AgentId}` with `"all"` or specific agent ID
4. Run in Log Analytics

### Power BI (Executive Dashboards)

For Power BI integration:
1. Use Log Analytics connector
2. Paste query with literal time ranges (Power BI has its own time filtering)
3. Map output columns to visuals

## PII Handling

### Default: Hash User Identities

All queries with user identity fields use `hash_sha256()` for persistent, PII-safe correlation:

```kql
| extend UserIdRaw = tostring(customDimensions["fromName"])
| extend UserId = hash_sha256(UserIdRaw)
```

**Why hash_sha256()?**
- **Persistent:** Same input always produces same hash (unlike `hash()` which may change)
- **Correlatable:** Can join user sessions across queries
- **PII-safe:** Original identity not exposed in query results

### Optional: Include PII (Authorized Users Only)

Some queries support an `IncludePII` parameter for authorized reviewers:

```kql
let IncludePII = {IncludePII:false};
| extend UserId = iff(IncludePII, UserIdRaw, hash_sha256(UserIdRaw))
```

**Use IncludePII=true only when:**
- User has explicit FINRA 3110 supervision role
- Query results are for active investigation
- Output is stored in access-controlled location

## Completeness Assessment

### The CompletenessPercent Field

Audit trail queries include a `CompletenessPercent` field indicating what percentage of required telemetry fields are present:

```kql
| extend CompletenessPercent =
    todouble(
        iff(isnotnull(customDimensions["text"]), 1, 0) +
        iff(isnotnull(customDimensions["speak"]), 1, 0) +
        iff(isnotnull(customDimensions["fromName"]), 1, 0) +
        iff(isnotnull(session_Id), 1, 0)
    ) / 4.0
```

**Why this matters:**
- Copilot Studio telemetry capture depends on "Log sensitive Activity properties" setting
- If disabled (default), Prompt/Response fields are NULL
- Queries run successfully but may return incomplete audit records
- `CompletenessPercent < 90%` indicates potential audit risk

### Recommended Thresholds

| CompletenessPercent | Risk Level | Action |
|---------------------|------------|--------|
| >= 95% | LOW | Audit-ready |
| 90-95% | MEDIUM | Document exceptions |
| < 90% | HIGH | Investigate telemetry config |

## Folder Descriptions

### usage-analytics/

**Purpose:** Session and user engagement metrics for operational visibility.

| Query | Description | Primary Control |
|-------|-------------|-----------------|
| `agent-usage-analytics.kql` | Session/message volume trends over time | 3.2 (Usage Analytics) |
| `user-engagement-metrics.kql` | Distinct users, repeat sessions | 3.2 (Usage Analytics) |

### error-categorization/

**Purpose:** Error classification for incident response and root cause analysis.

| Query | Description | Primary Control |
|-------|-------------|-----------------|
| `error-categorization-by-type.kql` | Connector/knowledge/orchestration error buckets | 3.4 (Incident Reporting) |
| `error-trend-analysis.kql` | Error rate trends for anomaly detection | 3.4 (Incident Reporting) |

### performance/

**Purpose:** Latency and response time metrics for SLA monitoring.

| Query | Description | Primary Control |
|-------|-------------|-----------------|
| `latency-distribution.kql` | P50/P95/P99 response time percentiles | 2.9 (Performance Monitoring) |
| `slow-query-detection.kql` | Responses exceeding latency threshold | 2.9 (Performance Monitoring) |

### compliance/

**Purpose:** Audit trail extraction for regulatory evidence (FINRA 3110, SEC 17a-4).

| Query | Description | Primary Control |
|-------|-------------|-----------------|
| `agent-decision-audit-trail.kql` | Complete decision chain for FINRA 3110 | 1.7 (Audit Logging), 2.12 (FINRA 3110) |
| `completeness-assessment.kql` | Telemetry gap detection for audit readiness | 1.7 (Supporting) |
| `rai-content-filtering-detection.kql` | RAI/XPIA/Jailbreak event detection | 1.6 (DSPM for AI) |
| `generative-answers-telemetry.kql` | Generative AI response quality metrics | 2.9 (Performance) |
| `flow-failure-correlation.kql` | Power Automate failure correlation | 3.4 (Incident Reporting) |

### sr11-7-model-risk/

**Purpose:** SR 11-7 model risk monitoring (outcome analysis, drift detection, validation).

| Query | Description | Primary Control |
|-------|-------------|-----------------|
| `output-monitoring.kql` | Topic distribution and recommendation trends | 2.6 (Model Risk) |
| `drift-detection-baseline.kql` | Response pattern drift detection (20% threshold) | 2.6 (Model Risk) |
| `validation-test-results.kql` | Validation test pass rates (95% threshold) | 2.6 (Model Risk) |

## Related Documentation

- [Query Governance Mapping](governance-queries.md) - Query-to-control mapping with regulatory cross-reference
- [Architecture](../architecture.md) - Solution architecture overview
- [Governance Mapping](../governance-mapping.md) - Artifact-to-control mapping
- [PII Sanitization Guide](../docs/pii-sanitization-guide.md) - PII handling guidance
- [FSI-AgentGov Controls](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/CONTROL-INDEX.md) - Complete control catalog

---

*Query Library Version: 1.2.0*
*Last Updated: 2026-02-05*
