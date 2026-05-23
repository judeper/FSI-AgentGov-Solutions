# KQL Query Governance Mapping

This document maps KQL queries to FSI-AgentGov framework controls with tiered evidence indicators and regulatory citations.

## Overview

The governance mapping uses an **artifact-first approach**: each query is documented with the framework controls it supports. Evidence contributions are classified using a three-tier model to clarify the strength of each query's role in satisfying compliance requirements.

This document complements the solution-level [governance-mapping.md](../governance-mapping.md) by providing granular query-to-control traceability for audit preparation.

### Evidence Tier Definitions

| Tier | Indicator | Meaning |
|------|-----------|---------|
| **Primary evidence** | The query directly satisfies the control's evidence requirement |
| **Supporting evidence** | The query provides supplementary evidence alongside other controls |
| **Partial coverage** | The query provides some evidence but additional artifacts are needed |

> **Regulatory Language Note:** This document uses hedging language ("helps support", "aids in meeting") per FSI-AgentGov CONTRIBUTING.md guidelines. No control or query should be described as independently satisfying a compliance obligation. Implementation, validation, and ongoing maintenance are required for compliance.

---

## Query-to-Control Mapping

### Usage Analytics Queries

#### agent-usage-analytics.kql

**Location:** `usage-analytics/agent-usage-analytics.kql`

**Description:** Agent session and message volume trends over time for operational visibility.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [3.2 - Usage Analytics](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | Session metrics, message volumes | Operational visibility requirement |

**Supporting evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [2.9 - Performance Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.9-agent-performance-monitoring-and-optimization.md) | Activity baseline for SLA | SR 11-7 ongoing monitoring |

**Sample Output:**

| Timestamp | AgentId | SessionCount | MessageCount | CompletionRate |
|-----------|---------|--------------|--------------|----------------|
| 2026-02-04 | agent-prod-001 | 342 | 1205 | 0.87 |
| 2026-02-03 | agent-prod-001 | 318 | 1089 | 0.91 |

---

#### user-engagement-metrics.kql

**Location:** `usage-analytics/user-engagement-metrics.kql`

**Description:** Distinct users and repeat session metrics with PII-safe hashing for user behavior analysis.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [3.2 - Usage Analytics](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) | User engagement tracking | FINRA 3110 supervision patterns |

**Sample Output:**

| Timestamp | AgentId | DistinctUsers | TotalSessions | SessionsPerUser |
|-----------|---------|---------------|---------------|-----------------|
| 2026-02-04 | agent-prod-001 | 128 | 342 | 2.67 |

---

### Error Categorization Queries

#### error-categorization-by-type.kql

**Location:** `error-categorization/error-categorization-by-type.kql`

**Description:** Categorize errors into connector/knowledge/orchestration buckets for incident triage.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [3.4 - Incident Reporting](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.4-incident-reporting-and-root-cause-analysis.md) | Error classification for root cause analysis | SOX 404 IT control monitoring |

**Sample Output:**

| ErrorCategory | ErrorCode | ErrorCount | Percentage |
|---------------|-----------|------------|------------|
| Connector | API_TIMEOUT | 45 | 32.1 |
| Knowledge | SEARCH_NO_RESULTS | 38 | 27.1 |

---

#### error-trend-analysis.kql

**Location:** `error-categorization/error-trend-analysis.kql`

**Description:** Error rate trend over time for anomaly detection and alerting.

**Supporting evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [3.4 - Incident Reporting](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.4-incident-reporting-and-root-cause-analysis.md) | Exception monitoring and escalation | SOX 404, OCC 2011-12 |

**Sample Output:**

| Timestamp | ErrorCount | TotalMessages | ErrorRate |
|-----------|------------|---------------|-----------|
| 2026-02-05T14:00:00Z | 12 | 245 | 4.9 |

---

### Performance Queries

#### latency-distribution.kql

**Location:** `performance/latency-distribution.kql`

**Description:** P50/P95/P99 response time distribution for SLA monitoring and performance analysis.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [2.9 - Performance Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.9-agent-performance-monitoring-and-optimization.md) | Latency percentile tracking | OCC 2011-12 operational risk |

**Sample Output:**

| Timestamp | AgentId | P50 | P95 | P99 | Count |
|-----------|---------|-----|-----|-----|-------|
| 2026-02-05T14:00:00Z | agent-prod-001 | 245 | 890 | 1523 | 312 |

---

#### slow-query-detection.kql

**Location:** `performance/slow-query-detection.kql`

**Description:** Identify responses exceeding latency threshold for performance investigation.

**Supporting evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [2.9 - Performance Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.9-agent-performance-monitoring-and-optimization.md) | Tail latency investigation | SOX 404 system performance |

**Sample Output:**

| Timestamp | AgentId | SessionId | DurationMs | Topic |
|-----------|---------|-----------|------------|-------|
| 2026-02-05T14:23:45Z | agent-prod-001 | sess-abc123 | 8945 | AccountInquiry |

---

### Compliance Queries

#### agent-decision-audit-trail.kql

**Location:** `compliance/agent-decision-audit-trail.kql`

**Description:** Complete decision chain extraction for FINRA 3110 supervision requirements.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [1.7 - Audit Logging](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.7-comprehensive-audit-logging-and-compliance.md) | Complete audit trail of agent interactions | SEC 17a-4(b)(4), FINRA 4511 |
| [2.12 - FINRA 3110 Supervision](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.12-ai-supervision-and-review-procedures-finra-3110-alignment.md) | Supervisory procedures documentation | FINRA 3110 |

**Supporting evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [2.6 - Model Risk Management](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.6-model-risk-management-alignment-with-occ-2011-12-sr-11-7.md) | Model decision audit trail | SR 11-7 |

**Sample Output:**

| Timestamp | AgentId | SessionId | UserId | Prompt | Response | CompletenessPercent |
|-----------|---------|-----------|--------|--------|----------|---------------------|
| 2026-02-04T10:15:23Z | agent-001 | sess-abc-123 | sha256:a3f2... | "What are my account options?" | "Based on your profile..." | 1.0 |

---

#### completeness-assessment.kql

**Location:** `compliance/completeness-assessment.kql`

**Description:** Identify telemetry gaps for audit readiness and proactive remediation.

**Supporting evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [1.7 - Audit Logging](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.7-comprehensive-audit-logging-and-compliance.md) | Audit trail quality monitoring | SEC 17a-4 record integrity |
| [2.12 - FINRA 3110 Supervision](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.12-ai-supervision-and-review-procedures-finra-3110-alignment.md) | Evidence completeness | FINRA 3110 |

**Sample Output:**

| Date | AvgCompleteness | RecordsBelow80Percent | TotalRecords | ComplianceRisk |
|------|-----------------|----------------------|--------------|----------------|
| 2026-02-04 | 0.72 | 1543 | 4250 | HIGH |
| 2026-02-03 | 0.91 | 287 | 3890 | LOW |

---

#### rai-content-filtering-detection.kql

**Location:** `compliance/rai-content-filtering-detection.kql`

**Description:** Detect RAI content filtering events from Microsoft Purview (XPIA, Jailbreak detection).

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [1.7 - Audit Logging](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.7-comprehensive-audit-logging-and-compliance.md) | Security event audit (RAI content filter telemetry capture) | GLBA 501(b) |

**Informational adjacency:**

| Control | Note |
|---------|------|
| [1.6 - DSPM for AI](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.6-microsoft-purview-dspm-for-ai.md) | DSPM for AI is delivered by Microsoft Purview, not by AOF. This query surfaces RAI events for visibility but is not primary or supporting evidence for Control 1.6. |

**Sample Output:**

| Timestamp | AgentId | SessionId | FilterType | FilterResult | UserIdHashed |
|-----------|---------|-----------|------------|--------------|--------------|
| 2026-02-04T14:23:45Z | agent-001 | sess-xyz-789 | XPIA | Blocked | sha256:c5d4... |

---

#### generative-answers-telemetry.kql

**Location:** `compliance/generative-answers-telemetry.kql`

**Description:** Extract generative answers telemetry (topic, result, feedback) for response quality monitoring.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [2.9 - Performance Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.9-agent-performance-monitoring-and-optimization.md) | Generative AI quality metrics | Operational visibility |

**Supporting evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [2.6 - Model Risk Management](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.6-model-risk-management-alignment-with-occ-2011-12-sr-11-7.md) | Model output quality | SR 11-7 outcome analysis |

**Sample Output:**

| Timestamp | ConversationId | AgentId | Topic | Result | HasFeedback |
|-----------|----------------|---------|-------|--------|-------------|
| 2026-02-04T15:30:12Z | conv-abc-123 | agent-001 | AccountInquiry | Success | true |

---

#### flow-failure-correlation.kql

**Location:** `compliance/flow-failure-correlation.kql`

**Description:** Correlate Power Automate flow failures with agent conversations.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [3.4 - Incident Reporting](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.4-incident-reporting-and-root-cause-analysis.md) | Cross-system incident correlation | SOX 302/404 IT control failure |

**Supporting evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [2.9 - Performance Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.9-agent-performance-monitoring-and-optimization.md) | Performance impact tracking | OCC 2011-12 |

**Sample Output:**

| Timestamp | AgentId | SessionId | FlowName | ErrorCode | CorrelationId |
|-----------|---------|-----------|----------|-----------|---------------|
| 2026-02-04T16:45:23Z | agent-001 | sess-abc-123 | CreateTicketFlow | ActionFailed | corr-xyz-789 |

---

### SR 11-7 Model Risk Queries

#### output-monitoring.kql

**Location:** `sr11-7-model-risk/output-monitoring.kql`

**Description:** SR 11-7 outcome analysis - track agent recommendation distribution and quality metrics over time.

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [2.6 - Model Risk Management](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.6-model-risk-management-alignment-with-occ-2011-12-sr-11-7.md) | Ongoing monitoring | SR 11-7 Section III |

**Sample Output:**

| Date | AgentId | Topic | TotalRecommendations | DistinctUsers |
|------|---------|-------|----------------------|---------------|
| 2026-02-04 | agent-prod-001 | AccountInquiry | 342 | 128 |
| 2026-02-04 | agent-prod-001 | LoanRecommendation | 156 | 89 |

---

#### drift-detection-baseline.kql

**Location:** `sr11-7-model-risk/drift-detection-baseline.kql`

**Description:** SR 11-7 drift detection - identify response pattern changes exceeding threshold (default 20%).

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [2.6 - Model Risk Management](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.6-model-risk-management-alignment-with-occ-2011-12-sr-11-7.md) | Model recalibration trigger | SR 11-7 Section III |

**Sample Output:**

| Topic | BaselineCount | CurrentCount | DriftPercent | DriftDirection | InvestigationRequired |
|-------|---------------|--------------|--------------|----------------|----------------------|
| LoanRecommendation | 1250 | 1875 | 50.0 | INCREASE | true |
| AccountInquiry | 3450 | 3105 | 10.0 | DECREASE | false |

---

#### validation-test-results.kql

**Location:** `sr11-7-model-risk/validation-test-results.kql`

**Description:** SR 11-7 process verification - confirm agent responses match validation test expectations (default 95% threshold).

**Primary evidence for:**

| Control | Requirement | Regulatory Alignment |
|---------|-------------|---------------------|
| [2.6 - Model Risk Management](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.6-model-risk-management-alignment-with-occ-2011-12-sr-11-7.md) | Validation evidence | SR 11-7 Section II |

**Sample Output:**

| Topic | TestCount | PassCount | FailCount | PassRate | MeetsThreshold |
|-------|-----------|-----------|-----------|----------|----------------|
| AccountInquiry | 150 | 147 | 3 | 98.0 | true |
| LoanRecommendation | 120 | 108 | 12 | 90.0 | false |

---

## Control-to-Query Cross-Reference

| Control | Primary Evidence | Supporting Evidence |
|---------|------------------|---------------------|
| **1.7 - Audit Logging** | agent-decision-audit-trail.kql, rai-content-filtering-detection.kql | completeness-assessment.kql |
| **2.6 - Model Risk** | output-monitoring.kql, drift-detection-baseline.kql, validation-test-results.kql | agent-decision-audit-trail.kql, generative-answers-telemetry.kql |
| **2.9 - Performance** | latency-distribution.kql, generative-answers-telemetry.kql | agent-usage-analytics.kql, slow-query-detection.kql, flow-failure-correlation.kql |
| **2.12 - FINRA 3110** | agent-decision-audit-trail.kql | completeness-assessment.kql |
| **3.2 - Usage Analytics** | agent-usage-analytics.kql, user-engagement-metrics.kql | - |
| **3.4 - Incident Reporting** | error-categorization-by-type.kql, flow-failure-correlation.kql | error-trend-analysis.kql |

---

## Regulatory Cross-Reference

| Regulation | Requirement | Supporting Queries |
|------------|-------------|-------------------|
| **SEC 17a-4** | Communications retention | agent-decision-audit-trail.kql, completeness-assessment.kql |
| **FINRA 3110** | Supervisory procedures | agent-decision-audit-trail.kql |
| **FINRA 4511** | Books and records | agent-decision-audit-trail.kql, completeness-assessment.kql |
| **SR 11-7** | Model risk monitoring | output-monitoring.kql, drift-detection-baseline.kql, validation-test-results.kql |
| **SOX 302/404** | Internal controls | error-categorization-by-type.kql, completeness-assessment.kql, flow-failure-correlation.kql |
| **OCC 2011-12** | Sound practices for model risk | drift-detection-baseline.kql, latency-distribution.kql |
| **GLBA 501(b)** | Protection against threats | rai-content-filtering-detection.kql |

---

## SR 11-7 Model Risk Compliance Guide

SR 11-7 (Guidance on Model Risk Management) requires three monitoring components for AI agents. This section documents the production-ready KQL patterns.

### 1. Outcome Analysis (output-monitoring.kql)

**What it does:** Tracks the distribution of agent recommendations by topic and user reach over time.

**When to run:** Weekly (minimum) for SR 11-7 compliance evidence.

**How to interpret:**
- Consistent topic distribution indicates stable model behavior
- Sudden shifts in topic volume may indicate data drift or model degradation
- Low DistinctUsers relative to TotalRecommendations may indicate repeat issues

**Key thresholds:**
- No hard threshold - establish baseline and monitor for deviation

### 2. Drift Detection (drift-detection-baseline.kql)

**What it does:** Compares recent response patterns (7 days) against a 90-day baseline to identify statistically significant changes.

**When to run:** Weekly for proactive monitoring.

**How to interpret:**
- `InvestigationRequired = true` indicates drift exceeding threshold
- `DriftDirection = INCREASE` with new topics suggests model expansion
- `DriftDirection = DECREASE` may indicate topic deprecation or data issues

**Key thresholds:**
| Threshold | Use Case |
|-----------|----------|
| 20% (default) | Standard agents |
| 10% | High-risk agents (financial advice, lending) |
| 5% | Critical agents (regulatory communications) |

**Investigation protocol when triggered:**
1. Review topic content for semantic changes
2. Check training data recency
3. Validate knowledge base updates
4. Document findings in model risk register

### 3. Validation Testing (validation-test-results.kql)

**What it does:** Measures pass rate of automated validation tests against expected responses.

**When to run:** After each model update or weekly minimum.

**How to interpret:**
- `MeetsThreshold = false` requires remediation before production use
- Low PassRate on specific topics indicates targeted training gaps
- Zero TestCount for topics indicates validation coverage gap

**Key thresholds:**
| Threshold | Use Case |
|-----------|----------|
| 95% (default) | Production readiness |
| 99% | Regulatory communications |
| 90% | Informational/FAQ topics |

**Remediation steps when below threshold:**
1. Identify failing test cases from detailed logs
2. Review expected vs actual responses
3. Update training data or knowledge base
4. Re-run validation suite
5. Document remediation in change log

### SR 11-7 Compliance Evidence Package

For regulatory examinations, produce the following evidence package:

| Component | Query | Frequency | Retention |
|-----------|-------|-----------|-----------|
| Outcome monitoring | output-monitoring.kql | Weekly | 730 days |
| Drift detection | drift-detection-baseline.kql | Weekly | 730 days |
| Validation results | validation-test-results.kql | After changes + weekly | 730 days |
| Audit trail | agent-decision-audit-trail.kql | Continuous | 730 days |

---

## SOX 302/404 Control Evidence Guide

SOX 302/404 compliance requires evidence of effective IT general controls. This section maps KQL queries to SOX control objectives.

### IT General Controls Supported

| Control Objective | Evidence Query | What it Demonstrates |
|-------------------|----------------|---------------------|
| **Change Management** | drift-detection-baseline.kql | Model behavior changes are detected and investigated |
| **Incident Management** | error-categorization-by-type.kql, flow-failure-correlation.kql | Errors are categorized and correlated for root cause analysis |
| **Access Controls** | agent-decision-audit-trail.kql (with IncludePII=false) | User interactions are logged with PII protection |
| **Data Integrity** | completeness-assessment.kql | Telemetry completeness is monitored and gaps flagged |

### SOX Evidence Collection Schedule

| Control | Query | Frequency | Reviewer |
|---------|-------|-----------|----------|
| Error monitoring | error-categorization-by-type.kql | Daily | IT Operations |
| Incident correlation | flow-failure-correlation.kql | Per incident | IT Operations |
| Audit trail integrity | completeness-assessment.kql | Weekly | Compliance |
| Model change detection | drift-detection-baseline.kql | Weekly | Model Risk |

### SOX Deficiency Indicators

| Query | Deficiency Threshold | Action |
|-------|---------------------|--------|
| completeness-assessment.kql | ComplianceRisk = HIGH for 3+ consecutive days | Escalate to IT controls owner |
| error-trend-analysis.kql | ErrorRate > 5% for 4+ hours | Initiate incident response |
| drift-detection-baseline.kql | InvestigationRequired = true not addressed within 5 days | Document as finding |

---

## Query Library Summary

| Folder | Query Count | Primary Controls |
|--------|-------------|------------------|
| usage-analytics/ | 2 | 3.2 |
| error-categorization/ | 2 | 3.4 |
| performance/ | 2 | 2.9 |
| compliance/ | 5 | 1.6, 1.7, 2.12, 3.4 |
| sr11-7-model-risk/ | 3 | 2.6 |
| **Total** | **14** | **7 controls** |

---

*Governance Queries Mapping version: 1.2.0*
*Last updated: February 2026*
