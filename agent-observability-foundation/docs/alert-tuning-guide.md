# Alert Tuning Guide

## Overview

Dynamic threshold alerts use machine learning to establish baseline behavior patterns and detect anomalies. This guide provides recommendations for tuning alert sensitivity, baseline periods, and failing period thresholds to reduce false positives while maintaining effective incident detection.

Tuning is an iterative process requiring operational observation and adjustment. Zone-specific tuning enables higher tolerance for Zone 1 (Personal Productivity) agents while maintaining strict SLA enforcement for Zone 3 (Enterprise Managed) agents, aligning with the FSI-AgentGov governance framework risk-based approach.

## Baseline Period

Dynamic thresholds require historical data to learn normal behavior patterns. Azure Monitor analyzes past metric values using machine learning to establish upper and lower bounds for anomaly detection.

**Minimum Requirements:**
- **3 days (minimum):** 30+ data points for hourly aggregation
- **10 days (standard):** Recommended for stable baselines with daily operational patterns
- **3 weeks (full):** Required for weekly patterns (weekend vs weekday variance)

**Recommended Baseline Period:**
Use **~14 days (2 weeks)** as the standard baseline period for FSI-AgentGov deployments. This duration captures weekly operational patterns while enabling faster deployment than a 3-week baseline. For agents with known weekly cycles (e.g., trading desk agents active Monday-Friday only, customer service agents with weekend staffing differences), extend the baseline period to 3 weeks.

**Initial Deployment:**
Dynamic thresholds show "Learning" state during the baseline period. No alerts fire while the ML model establishes normal ranges. After the baseline period completes, thresholds activate and alerts begin firing when anomalies are detected.

**Production Deployment Strategy:**
For production environments requiring immediate alerting, consider a phased approach:

1. Deploy alert rules with dynamic thresholds on Day 1 (alerts enter "Learning" state)
2. Optionally deploy temporary static threshold alerts for critical scenarios (e.g., error rate > 10%)
3. After 10-14 days, dynamic thresholds activate based on learned baseline
4. Remove temporary static threshold alerts once dynamic thresholds are operational

## Sensitivity Levels

Azure Monitor provides three sensitivity levels for dynamic threshold alerts:

| Sensitivity | Description | Typical Use Case | Zone Recommendation |
|-------------|-------------|------------------|---------------------|
| **Low** | Higher tolerance for variance, fewer alerts | Exploratory/personal agents with variable usage | Zone 1 - Personal Productivity |
| **Medium** | Balanced sensitivity for typical operations | Team collaboration agents with predictable patterns | Zone 2 - Team Collaboration |
| **High** | Strict threshold enforcement, more alerts | Enterprise agents with strict SLA requirements | Zone 3 - Enterprise Managed |

**Default Zone Sensitivity Mapping:**
- **Zone 1:** Low (higher false positive tolerance for personal productivity agents)
- **Zone 2:** Medium (balanced approach for team collaboration)
- **Zone 3:** High (strict SLA enforcement for enterprise managed agents)

**When to Adjust:**
- **Increase sensitivity (Low → Medium → High):** If critical incidents are missed, or SLA requirements demand stricter monitoring
- **Decrease sensitivity (High → Medium → Low):** If alert volume creates fatigue, or operational patterns have high natural variance

## Tuning Process

Alert tuning is an iterative cycle of observation, analysis, and adjustment:

**Week 1-2: Observe**
- Monitor alert volume and false positive rate
- Document alert patterns (time of day, day of week, specific agents)
- Track incident detection effectiveness (true positives vs missed incidents)

**Week 3: Adjust**
Based on Week 1-2 observations:
- Adjust sensitivity levels (Low/Medium/High) for zones with excessive or insufficient alerts
- Modify failingPeriods settings to reduce noise (e.g., 4/3 → 4/4 for stricter enforcement)
- Use `ignoreDataBefore` to exclude known anomalous historical periods from baseline

**Month 2: Fine-tune**
After 30+ days of operational data:
- Review runbook effectiveness (are runbook links helping resolution?)
- Validate zone assignments (are agents in correct governance zones?)
- Consider agent-specific thresholds for high-value or high-risk agents

**Ongoing:**
- Quarterly review of alert effectiveness and tuning adjustments
- Re-establish baselines after major platform changes (new Copilot Studio features, agent redesigns)

## Common Issues

### Issue: No Alerts Firing

**Symptoms:** Dynamic threshold alerts remain in "Learning" state indefinitely, or show "Healthy" status despite visible anomalies in workbooks.

**Possible Causes:**
1. Insufficient baseline data (fewer than 30 data points)
2. Metric not being emitted by Application Insights (KQL query returns no results)
3. Zone filter in KQL query excludes all data (customDimensions['Zone'] field missing)

**Resolution:**
1. Verify baseline period has elapsed (check alert creation date, wait 10-14 days)
2. Run KQL query manually in Log Analytics to confirm metric values exist
3. Check telemetry for zone metadata: `customEvents | where name == 'BotMessageSend' | project customDimensions['Zone']`
4. If zone field is missing, remove zone filter from KQL query or add zone enrichment to Application Insights

### Issue: Too Many Alerts (Alert Fatigue)

**Symptoms:** Alert volume exceeds operations team capacity, alerts ignored, SLA degradation due to desensitization.

**Possible Causes:**
1. Sensitivity level too high for operational variance
2. failingPeriods threshold too lenient (e.g., 4/1 fires on single anomaly)
3. Baseline includes anomalous historical data (skews thresholds)

**Resolution:**
1. Decrease sensitivity: High → Medium or Medium → Low for affected zones
2. Increase failingPeriods threshold: 4/2 → 4/3 (requires 3 consecutive anomalies in 4 periods)
3. Use `ignoreDataBefore` to exclude historical incidents from baseline calculation
4. Consider zone reassignment: Move low-criticality agents from Zone 3 to Zone 2

### Issue: Alerts Only During Business Hours

**Symptoms:** Alerts fire Monday-Friday 9am-5pm but never on weekends or evenings, despite 24x7 agent availability.

**Possible Causes:**
1. Baseline period too short to capture weekly patterns (daily baseline only)
2. Agent usage genuinely has weekly patterns (business hours only)

**Resolution:**
1. If agents should have 24x7 usage: Extend baseline period to 3 weeks to capture weekly variance
2. If agents genuinely have business hours usage: This is expected behavior; ensure after-hours incidents are detected through static threshold backup alerts if needed
3. Validate agent deployment: Confirm agents are accessible outside business hours

## Zone-Specific Recommendations

### Zone 1 - Personal Productivity

**Characteristics:**
- Exploratory agents built by individual users
- Variable usage patterns (sporadic testing, one-off queries)
- Lower business impact if unavailable

**Recommended Tuning:**
- Sensitivity: Low (higher tolerance for usage variance)
- failingPeriods: 4/3 (stricter threshold to reduce noise)
- Baseline: 10 days (shorter baseline acceptable due to lower criticality)
- Severity: 2-3 (Warning/Informational, avoid critical/error severity)

**Rationale:** Zone 1 agents have high natural variance. Low sensitivity prevents alert fatigue while still detecting severe anomalies.

### Zone 2 - Team Collaboration

**Characteristics:**
- Department-level agents with predictable usage patterns
- Team-scoped access with moderate business impact
- Shared ownership and support

**Recommended Tuning:**
- Sensitivity: Medium (balanced approach for typical operations)
- failingPeriods: 4/3 (standard threshold)
- Baseline: 14 days (captures weekly patterns)
- Severity: 1-2 (Error/Warning)

**Rationale:** Zone 2 agents have predictable patterns. Medium sensitivity balances detection effectiveness with manageable alert volume.

### Zone 3 - Enterprise Managed

**Characteristics:**
- Organization-wide agents with strict SLA requirements
- High business impact if unavailable
- Formal change management and incident response

**Recommended Tuning:**
- Sensitivity: High (strict threshold enforcement)
- failingPeriods: 4/2 (more sensitive, fires faster on anomalies)
- Baseline: 21 days (full weekly pattern capture, including holidays)
- Severity: 0-1 (Critical/Error for immediate action)

**Rationale:** Zone 3 agents require strict monitoring. High sensitivity ensures SLA compliance even if it creates higher alert volume.

## Ignoring Historical Anomalies

The `ignoreDataBefore` property excludes historical data from baseline calculation. This is useful when known incidents or anomalous periods would skew thresholds.

**Example Scenario:**
An agent experienced a major outage on January 10-12, 2026 with 90% error rates. This anomaly would inflate the baseline error rate threshold, preventing future alerts.

**Solution:**
Set `ignoreDataBefore` to exclude the outage period:

```json
{
  "criterionType": "DynamicThresholdCriterion",
  "alertSensitivity": "Medium",
  "ignoreDataBefore": "2026-01-13T00:00:00Z",
  "failingPeriods": {
    "numberOfEvaluationPeriods": 4,
    "minFailingPeriodsToAlert": 3
  }
}
```

**When to Use:**
- After major incidents that would skew baseline calculations
- When changing agent architecture significantly (e.g., migrating from Copilot Studio classic to Agent 365 SDK)
- When initially deploying alerts to production with existing telemetry history containing known anomalies

**When NOT to Use:**
- For routine operational variance (use sensitivity adjustment instead)
- To artificially lower thresholds (creates false positives)
- As a permanent configuration (should be temporary exclusion of specific historical periods)

---

*Version: 1.0.0*
*Last Updated: February 2026*
*Part of FSI-AgentGov-Solutions*
