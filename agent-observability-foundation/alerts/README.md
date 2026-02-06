# Alert Rules & Action Groups

**Version:** 1.0.0

## Overview

This solution provides proactive alerting for Copilot Studio agent operations using Azure Monitor scheduled query rules with dynamic thresholds. Dynamic thresholds use machine learning to establish baseline behavior patterns and detect anomalies, reducing false positives compared to static threshold alerting.

Alert rules are organized by FSI governance zones (Zone 1 - Personal Productivity, Zone 2 - Team Collaboration, Zone 3 - Enterprise Managed) with zone-specific sensitivity tuning. Each alert includes runbook links for automated remediation guidance and custom properties for incident context enrichment.

Notifications route through zone-specific action groups to appropriate Teams channels and email distribution lists. Teams integration requires a Logic App intermediary for schema transformation (direct webhooks produce malformed messages). Both email (audit trail) and Teams (real-time collaboration) notification channels are configured per alert.

## Alert Catalog

| Requirement ID | Alert Name | Detection Method | Zone 1 Sensitivity | Zone 2 Sensitivity | Zone 3 Sensitivity |
|----------------|------------|------------------|--------------------|--------------------|-------------------|
| **ALRT-01** | High Failure Rate | Dynamic threshold on BotMessageSend error rate percentage | Low (higher tolerance) | Medium (balanced) | High (strict SLA) |
| **ALRT-02** | Latency Regression | Dynamic threshold on P95 latency (ms) | Low (higher tolerance) | Medium (balanced) | High (strict SLA) |
| **ALRT-03** | Abnormal Usage | Dynamic threshold (bidirectional) on session volume | Low (higher tolerance) | Medium (balanced) | High (strict SLA) |

**Dynamic Threshold Sensitivity Levels:**
- **Low:** Higher tolerance for normal variance, fewer alerts (suitable for Zone 1 personal productivity agents)
- **Medium:** Balanced sensitivity for typical operational patterns (suitable for Zone 2 team collaboration agents)
- **High:** Strict threshold enforcement for enterprise SLA requirements (suitable for Zone 3 enterprise managed agents)

**Bidirectional Detection (ALRT-03):**
Abnormal Usage alert uses `GreaterOrLessThan` operator to detect both usage spikes (potential abuse, bot attacks) and drops (service degradation, agent unavailability). This differs from ALRT-01 and ALRT-02 which use unidirectional `GreaterThan` operator.

## Zone Routing Architecture

Each alert deploys 3 separate scheduled query rules (one per zone) with zone-filtered KQL queries. This pattern enables zone-specific action group routing and avoids alert rule sprawl.

| Zone | Action Group | Teams Channel | Email Recipient | Severity Range |
|------|--------------|---------------|-----------------|----------------|
| Zone 1 - Personal | action-group-zone1 | #general-ops | ops-team@example.com | 2-3 (Warning, Informational) |
| Zone 2 - Team | action-group-zone2 | #team-ops | team-ops@example.com | 1-2 (Error, Warning) |
| Zone 3 - Enterprise | action-group-zone3 | #enterprise-ops | enterprise-ops@example.com | 0-1 (Critical, Error) |

**Severity Progression:**
Zone 3 alerts use higher severity levels (0=Critical, 1=Error) than Zone 1 (2=Warning, 3=Informational) to reflect enterprise SLA enforcement requirements. This aligns with FSI-AgentGov framework risk-based governance tiers.

## Deployment Order

Alert deployment requires specific sequencing due to dependencies:

**1. Deploy Logic App (first)**
The Teams notification Logic App must be deployed first to obtain the callback URL:

```bash
cd /path/to/FSI-AgentGov-Solutions

az deployment group create \
  --resource-group rg-agent-observability-dev \
  --template-file agent-observability-foundation/alerts/action-groups/logic-app-teams-notification.json \
  --parameters logicAppName=fsi-agent-alert-teams-dev
```

Capture the Logic App callback URL from outputs:
```bash
az deployment group show \
  --resource-group rg-agent-observability-dev \
  --name logic-app-teams-notification \
  --query properties.outputs.logicAppCallbackUrl.value
```

**2. Update shared parameter files**
Edit `alerts/shared-parameters.dev.json` (or prod) with the actual callback URL:
```json
{
  "parameters": {
    "teamsLogicAppCallbackUrl": {
      "value": "https://prod-XX.region.logic.azure.com:443/workflows/.../triggers/manual/paths/invoke?..."
    }
  }
}
```

**3. Deploy Action Groups (second)**
Action groups reference the Logic App callback URL:

```bash
# Deploy all 3 zone-specific action groups
az deployment group create \
  --resource-group rg-agent-observability-dev \
  --template-file agent-observability-foundation/alerts/action-groups/action-group-zone1.json \
  --parameters @agent-observability-foundation/alerts/shared-parameters.dev.json

az deployment group create \
  --resource-group rg-agent-observability-dev \
  --template-file agent-observability-foundation/alerts/action-groups/action-group-zone2.json \
  --parameters @agent-observability-foundation/alerts/shared-parameters.dev.json

az deployment group create \
  --resource-group rg-agent-observability-dev \
  --template-file agent-observability-foundation/alerts/action-groups/action-group-zone3.json \
  --parameters @agent-observability-foundation/alerts/shared-parameters.dev.json
```

**4. Deploy Alert Rules (third)**
Alert rules reference action group resource IDs:

```bash
# Deploy all 3 alert rule templates
az deployment group create \
  --resource-group rg-agent-observability-dev \
  --template-file agent-observability-foundation/alerts/ALRT-01-high-failure-rate.json \
  --parameters @agent-observability-foundation/alerts/shared-parameters.dev.json

az deployment group create \
  --resource-group rg-agent-observability-dev \
  --template-file agent-observability-foundation/alerts/ALRT-02-latency-regression.json \
  --parameters @agent-observability-foundation/alerts/shared-parameters.dev.json

az deployment group create \
  --resource-group rg-agent-observability-dev \
  --template-file agent-observability-foundation/alerts/ALRT-03-abnormal-usage.json \
  --parameters @agent-observability-foundation/alerts/shared-parameters.dev.json
```

## Dynamic Threshold Baseline Period

Dynamic thresholds require historical data to establish normal behavior patterns. Azure Monitor uses machine learning to analyze past metric values and detect anomalies.

**Minimum Baseline Requirements:**
- **3 days (minimum):** 30+ data points for hourly aggregation (PT1H evaluation frequency)
- **10 days (standard):** Recommended for stable baselines with daily operational patterns
- **3 weeks (full):** Required for weekly patterns (weekend vs weekday variance)

**Recommendation for FSI-AgentGov:**
Use **~14 days (2 weeks)** as standard baseline period. This captures weekly patterns while enabling faster deployment than 3-week baseline. For agents with known weekly cycles (e.g., trading desk agents active Mon-Fri only), extend to 3 weeks.

**Initial Deployment Strategy:**
Dynamic thresholds show "Learning" state during baseline period. For production deployments requiring immediate alerting:

1. Deploy alert rules with dynamic thresholds on Day 1
2. Alerts enter "Learning" state (no notifications sent)
3. After 10-14 days, thresholds activate based on learned baseline
4. Use `ignoreDataBefore` property to exclude anomalous historical data from baseline calculation

**Example: Excluding Historical Anomalies**
If a known incident occurred before alert deployment, exclude that period from baseline:
```json
{
  "criterionType": "DynamicThresholdCriterion",
  "ignoreDataBefore": "2026-01-15T00:00:00Z",
  "alertSensitivity": "Medium"
}
```

## Severity Mapping

Alert severity levels map to Azure Monitor's 5-level system:

| Severity | Label | Zone 1 Use Case | Zone 2 Use Case | Zone 3 Use Case |
|----------|-------|-----------------|-----------------|-----------------|
| **0** | Critical | (Not used) | (Not used) | ALRT-01, ALRT-02 High Failure/Latency |
| **1** | Error | (Not used) | ALRT-01, ALRT-02 High Failure/Latency | ALRT-03 Abnormal Usage |
| **2** | Warning | ALRT-01, ALRT-02 High Failure/Latency | ALRT-03 Abnormal Usage | (Not used) |
| **3** | Informational | ALRT-03 Abnormal Usage | (Not used) | (Not used) |
| **4** | Verbose | (Not used) | (Not used) | (Not used) |

**Severity Progression Rationale:**
Zone 3 enterprise agents require immediate action (severity 0-1) for operational issues. Zone 1 personal productivity agents tolerate higher latency and error rates (severity 2-3). This aligns with FSI governance framework risk tiers.

## Runbook Links

Each alert includes a `RunbookUrl` custom property pointing to control-specific troubleshooting playbooks:

| Alert | Control Reference | Runbook URL |
|-------|-------------------|-------------|
| ALRT-01 High Failure Rate | Control 3.4 - Incident Reporting and Root Cause Analysis | https://judeper.github.io/FSI-AgentGov/playbooks/control-implementations/3.4/troubleshooting/ |
| ALRT-02 Latency Regression | Control 2.9 - Agent Performance Monitoring and Optimization | https://judeper.github.io/FSI-AgentGov/playbooks/control-implementations/2.9/troubleshooting/ |
| ALRT-03 Abnormal Usage | Control 3.2 - Usage Analytics and Activity Monitoring | https://judeper.github.io/FSI-AgentGov/playbooks/control-implementations/3.2/troubleshooting/ |

Runbook URLs appear in Teams notifications and email alert payloads, enabling operations teams to access remediation guidance directly from alert context.

**Customizing Runbook URLs:**
To point to internal documentation sites, edit the `customProperties.RunbookUrl` value in each alert rule ARM template before deployment.

## PagerDuty/ServiceNow Integration

For enterprise ITSM escalation workflows, configure action groups with webhook receivers pointing to PagerDuty or ServiceNow incident creation APIs.

**PagerDuty Integration:**
1. Create PagerDuty service integration for Azure Monitor alerts
2. Obtain Events API v2 endpoint (https://events.pagerduty.com/v2/enqueue)
3. Add webhook receiver to action group ARM template:

```json
{
  "webhookReceivers": [
    {
      "name": "PagerDuty Critical Incidents",
      "serviceUri": "https://events.pagerduty.com/v2/enqueue",
      "useCommonAlertSchema": true,
      "useAadAuth": false
    }
  ]
}
```

**ServiceNow Integration:**
1. Configure ServiceNow Azure Monitor event connector
2. Create webhook endpoint in ServiceNow instance
3. Add webhook receiver with authentication header:

```json
{
  "webhookReceivers": [
    {
      "name": "ServiceNow Incident Creation",
      "serviceUri": "https://your-instance.service-now.com/api/now/table/incident",
      "useCommonAlertSchema": true,
      "useAadAuth": false
    }
  ]
}
```

**Common Alert Schema:**
All receivers (email, Logic App, webhook) use `useCommonAlertSchema: true` for consistent payload structure. This enables downstream systems to parse alerts without version-specific logic.

## Directory Structure

```
alerts/
├── README.md                              # This file
├── action-groups/
│   ├── logic-app-teams-notification.json  # Teams schema transformation Logic App
│   ├── action-group-zone1.json            # Zone 1 (Personal) action group
│   ├── action-group-zone2.json            # Zone 2 (Team) action group
│   └── action-group-zone3.json            # Zone 3 (Enterprise) action group
├── ALRT-01-high-failure-rate.json         # High Failure Rate alert (3 zone resources)
├── ALRT-02-latency-regression.json        # Latency Regression alert (3 zone resources)
├── ALRT-03-abnormal-usage.json            # Abnormal Usage Pattern alert (3 zone resources)
├── shared-parameters.dev.json             # Dev environment shared parameters
└── shared-parameters.prod.json            # Prod environment shared parameters
```

## Related Documentation

- **Phase 3 Plan 02:** [03-02-SUMMARY.md](../../.planning/phases/03-azure-monitor-workbooks-alert-rules/03-02-SUMMARY.md) - Action groups and Teams integration
- **Phase 3 Plan 04:** [03-04-SUMMARY.md](../../.planning/phases/03-azure-monitor-workbooks-alert-rules/03-04-SUMMARY.md) - Alert rule templates
- **Governance Mapping:** [governance-mapping.md](../governance-mapping.md) - Control alignment for alerting infrastructure
- **Framework Controls:** [FSI-AgentGov controls catalog](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/CONTROL-INDEX.md)

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Alerts never fire despite visible anomalies | Dynamic threshold in "Learning" state | Wait 10-14 days for baseline establishment, or switch to static thresholds temporarily |
| Teams shows raw JSON instead of formatted message | Direct webhook to Teams (not Logic App) | Use Logic App intermediary for schema transformation, configure action group with logicAppReceiver |
| Alert fires on every evaluation period | failingPeriods set to 1/1 (too sensitive) | Increase to 4/3 (must fail 3 out of 4 periods) to reduce noise |
| Zone filtering returns no results | customDimensions['Zone'] field missing in telemetry | Verify Copilot Studio agents emit zone metadata or add enrichment via Application Insights custom processors |
| Email notifications not received | emailReceiver not configured or incorrect address | Verify emailReceivers section in action group ARM template, check spam filters |
| Logic App callback URL expired | Logic App redeployed with new callback URL | Update shared-parameters.json with new callback URL, redeploy action groups |

---

*Version: 1.0.0*
*Last Updated: February 2026*
*Part of FSI-AgentGov-Solutions*
