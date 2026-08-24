---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P4, P5, P6]
applicable_drivers:
  - technology_data
  - ai_governance
coe_function: optimize
---
# Agent Observability Foundation

> **Version:** v1.2.5
> **Status:** Live
> **Validated against framework version:** v1.6.0

FSI-compliant telemetry infrastructure for Microsoft Copilot Studio agents with long-term audit retention, operational workbooks, and proactive alerting.

## Architecture Overview

The Agent Observability Foundation deploys a production-ready telemetry pipeline that captures Copilot Studio agent interactions and stores them with retention periods that help support SEC Rule 17a-4 compliance requirements. The solution establishes a clear separation between operational monitoring (real-time queries via Log Analytics) and compliance audit paths (Azure Blob Storage export via StorageV2 with hierarchical namespace disabled — required for Diagnostic Settings compatibility), supporting Control 2.8 (Access Control and Segregation of Duties).

This architecture addresses the unique challenges of AI agent observability in regulated financial services: capturing conversation telemetry without exposing PII, maintaining audit trails that help satisfy FINRA Rule 4511 books and records requirements, and providing cost-effective storage tiers that balance operational needs with long-term retention mandates. The solution supports Control 1.7 (Comprehensive Audit Logging), Control 3.2 (Usage Analytics and Activity Monitoring), and Control 2.9 (Agent Performance Monitoring).

All Azure resources are provisioned via Python scripts using the Azure SDK for Python, enabling repeatable lab deployments and teardown cycles. WORM (Write Once Read Many) policy configuration for SEC 17a-4(f) compliance is deliberately excluded from automation to prevent accidental immutable lockdown in production environments.

## What This Solution Does

### Telemetry Infrastructure
- **Deploys workspace-based Application Insights** with 730-day retention for Copilot Studio telemetry capture using connection-string configuration and normalized `AppEvents`/`customEvents` query support
- **Creates Log Analytics workspace** with 2-year interactive query capability using PerGB2018 pricing tier
- **Configures Azure Blob Storage (StorageV2) export** via Diagnostic Settings for SEC 17a-4 long-term retention (7+ years with WORM). StorageV2 is provisioned with hierarchical namespace disabled (required for Diagnostic Settings export).
- **Establishes RBAC separation** between operational monitoring (Monitoring Reader) and compliance audit paths (Storage Blob Data Reader)
- **Provides PII sanitization guidance** for conversation data in current `Properties` fields and legacy `customDimensions` fields (`text`, `speak`, `fromName`, `recipientName`)
- **Includes cost management configuration** with sampling defaults and cost alert thresholds

### Azure Monitor Workbooks
- **Operational Health Workbook** with 4 tabs: Overview metrics, Availability grid, Error Rates by category, Latency percentiles (P50/P95/P99)
- **Error Diagnostics Workbook** with 5 tabs: Error Summary, Error Drill-Down by agent, Root Cause Analysis (flow failures, RAI events), Event Detail payload view
- **Usage Overview Workbook** with 5 tabs: Adoption Overview, Engagement metrics, Channel Distribution, Generative AI Quality monitoring

### Alert Rules & Action Groups
- **High Failure Rate Alert (ALRT-01)** with dynamic threshold monitoring on BotMessageSend error rates across 3 zones
- **Latency Regression Alert (ALRT-02)** with P95 latency monitoring and zone-specific sensitivity tuning
- **Abnormal Usage Alert (ALRT-03)** with bidirectional detection (spikes and drops) on session volume
- **Zone-based notification routing** via Teams (real-time) and email (audit trail) through zone-specific action groups

## Who Should Use This

| Audience | Use Case |
|----------|----------|
| M365 Administrator | Deploy and configure telemetry infrastructure for Copilot Studio agents |
| Compliance Officer | Verify audit trail meets SEC 17a-4 and FINRA 4511 retention requirements |
| SOC Analyst | Query agent interactions for security monitoring and incident response |
| Platform Operations | Manage telemetry costs, configure sampling, monitor storage growth |

## Prerequisites

Before deploying this solution, ensure you have:

1. **Azure subscription** with Owner or Contributor + User Access Admin permissions
2. **Resource group** for telemetry resources (or permissions to create one)
3. **Entra ID authentication** configured (managed identity/workload identity for hosted automation or interactive login for admin workstations)
4. **Python 3.9+** installed with pip
5. **Azure SDK packages** installed via `pip install -r scripts/requirements.txt`

See [prerequisites.md](prerequisites.md) for detailed requirements including role assignments and license tiers.

## Quick Start

```bash
# 1. Clone the repository
git clone https://github.com/judeper/FSI-AgentGov-Solutions.git
cd FSI-AgentGov-Solutions/agent-observability-foundation

# 2. Install Python dependencies
pip install -r scripts/requirements.txt

# 3. Copy and edit configuration
cp config/config.example.yml config/config.yml
# Edit config.yml with your subscription ID, resource group, location

# 4. Preview changes (dry run)
python scripts/provision.py --dry-run

# 5. Deploy telemetry infrastructure
python scripts/provision.py

# 6. Verify deployment
python scripts/verify_telemetry.py
```

## Deployment

After provisioning the telemetry infrastructure (Phase 1), deploy workbooks and alert rules using PowerShell deployment scripts.

### Workbook Deployment

Deploy all 3 Azure Monitor Workbooks (Operational Health, Error Diagnostics, Usage Overview) to your resource group:

```powershell
# Preview deployment without making changes
pwsh scripts/deploy-workbooks.ps1 `
  -ResourceGroup "rg-agent-observability-dev" `
  -ApplicationInsightsId "/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Insights/components/{ai-name}" `
  -Environment dev `
  -DryRun

# Deploy workbooks to development environment
pwsh scripts/deploy-workbooks.ps1 `
  -ResourceGroup "rg-agent-observability-dev" `
  -ApplicationInsightsId "/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Insights/components/{ai-name}" `
  -Environment dev

# Deploy workbooks to production environment
pwsh scripts/deploy-workbooks.ps1 `
  -ResourceGroup "rg-agent-observability-prod" `
  -ApplicationInsightsId "/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Insights/components/{ai-name}" `
  -Environment prod
```

**Idempotent Deployment:**
Re-running the deployment script updates existing workbooks without creating duplicates, enabling safe CI/CD integration.

### Alert Deployment

Deploy alert infrastructure in dependency order: Logic App → Action Groups → Alert Rules.

```powershell
# Preview deployment without making changes
pwsh scripts/deploy-alerts.ps1 `
  -ResourceGroup "rg-agent-observability-dev" `
  -ApplicationInsightsId "/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Insights/components/{ai-name}" `
  -Environment dev `
  -DryRun

# Deploy alerts to development environment (with confirmation prompt)
pwsh scripts/deploy-alerts.ps1 `
  -ResourceGroup "rg-agent-observability-dev" `
  -ApplicationInsightsId "/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Insights/components/{ai-name}" `
  -Environment dev

# Deploy alerts to production environment (skip confirmation)
pwsh scripts/deploy-alerts.ps1 `
  -ResourceGroup "rg-agent-observability-prod" `
  -ApplicationInsightsId "/subscriptions/{sub-id}/resourceGroups/{rg}/providers/Microsoft.Insights/components/{ai-name}" `
  -Environment prod `
  -Force
```

**Deployment Phases:**
1. **Phase 1:** Logic App (Teams notification schema transformer)
2. **Phase 2:** Action Groups (3 zone-specific groups referencing Logic App callback URL)
3. **Phase 3:** Alert Rules (ALRT-01, ALRT-02, ALRT-03 with dynamic thresholds)

The script enforces this dependency order automatically. Dynamic threshold baselines require 10-14 days of telemetry data before alerts become active.

### Validation

For comprehensive pre-deployment prerequisites and post-deployment verification steps, see:

**[scripts/validation-checklist.md](scripts/validation-checklist.md)**

The validation checklist covers:
- Azure infrastructure verification (Application Insights, Log Analytics, Storage)
- Software requirements (PowerShell 7.0+, Azure CLI 2.60+)
- ARM template file verification
- Workbook deployment validation with idempotency testing
- Alert deployment validation with 3-phase dependency checks
- Dynamic threshold baseline expectations
- Troubleshooting quick reference

## Solution Structure

```
agent-observability-foundation/
├── README.md                          # This file - solution overview
├── CHANGELOG.md                       # Version history and release notes
├── architecture.md                    # Data flow diagram and component details
├── prerequisites.md                   # Checklist table with roles and licenses
├── governance-mapping.md              # Artifact → Controls with tiered evidence
├── config/
│   ├── config.schema.json             # JSON schema for validation
│   └── config.example.yml             # Example configuration template
├── scripts/
│   ├── provision.py                   # Main provisioning script
│   ├── teardown.py                    # Cleanup script for lab cycling
│   ├── verify_telemetry.py            # Post-deployment validation
│   ├── verify_worm.py                 # WORM policy verification (read-only)
│   ├── deploy-workbooks.ps1           # Workbook deployment automation (PowerShell 7.0+)
│   ├── deploy-alerts.ps1              # Alert infrastructure deployment (PowerShell 7.0+)
│   ├── validation-checklist.md        # Pre/post-deployment verification checklist
│   └── requirements.txt               # Python dependencies
├── queries/
│   ├── README.md                      # KQL query library overview
│   ├── performance/                   # Core operational queries (2 queries)
│   ├── compliance/                    # Regulatory audit queries (5 queries)
│   ├── usage-analytics/               # Adoption and engagement queries (2 queries)
│   ├── error-categorization/          # Error analysis queries (2 queries)
│   ├── sr11-7-model-risk/             # SR 11-7 model governance (3 queries)
│   └── governance-queries.md          # Query-to-control mapping
├── workbooks/
│   ├── README.md                      # Workbooks overview and deployment
│   ├── operational-health/            # Daily ops monitoring (4 tabs)
│   ├── error-diagnostics/             # Incident investigation (5 tabs)
│   └── usage-overview/                # Adoption and engagement (5 tabs)
├── alerts/
│   ├── README.md                      # Alert rules and action groups overview
│   ├── action-groups/                 # Zone-specific notification routing
│   ├── ALRT-01-high-failure-rate.json # Dynamic threshold error rate alerts
│   ├── ALRT-02-latency-regression.json # Dynamic threshold latency alerts
│   ├── ALRT-03-abnormal-usage.json    # Bidirectional usage anomaly alerts
│   └── shared-parameters.*.json       # Environment-specific parameters
├── power-bi/
│   ├── README.md                      # Power BI integration overview
│   ├── docs/                          # Connector decisions and reconciliation
│   ├── kql-views/                     # KQL views for DirectQuery
│   └── semantic-model/                # TMDL semantic model (delivered Phase 3.5)
├── docs/
│   ├── pii-sanitization-guide.md      # Decision framework for PII handling
│   ├── cost-tuning-guide.md           # Sampling and cost management
│   ├── alert-tuning-guide.md          # Dynamic threshold tuning guidance
│   └── worm-configuration.md          # Manual WORM setup steps (not automated)
└── templates/
    └── diagnostic-settings.json       # ARM template for export config
```

## Documentation

| Guide | Description |
|-------|-------------|
| [architecture.md](architecture.md) | Mermaid data flow diagram, component details, SoD boundaries, retention tiers |
| [prerequisites.md](prerequisites.md) | Checklist table with Resource, Required Role, and License Tier |
| [governance-mapping.md](governance-mapping.md) | Maps telemetry artifacts to FSI-AgentGov framework controls |
| [queries/README.md](queries/README.md) | KQL query library with 14 production queries for workbooks and alerts |
| [workbooks/README.md](workbooks/README.md) | Workbook catalog, deployment instructions, KQL query source mapping |
| [alerts/README.md](alerts/README.md) | Alert catalog, zone routing architecture, deployment order, runbook links |
| [docs/pii-sanitization-guide.md](docs/pii-sanitization-guide.md) | Decision framework for handling PII in customDimensions |
| [docs/cost-tuning-guide.md](docs/cost-tuning-guide.md) | Sampling configuration and cost alert thresholds |
| [docs/alert-tuning-guide.md](docs/alert-tuning-guide.md) | Dynamic threshold sensitivity tuning, baseline periods, zone recommendations |
| [docs/worm-configuration.md](docs/worm-configuration.md) | Manual WORM policy setup for SEC 17a-4(f) compliance |
| [scripts/validation-checklist.md](scripts/validation-checklist.md) | Pre-deployment prerequisites and post-deployment verification procedures |

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Diagnostic settings export shows no data | StorageV2 (with immutability policies) hierarchical namespace enabled | Create StorageV2 account WITHOUT hierarchical namespace (limitation of diagnostic settings) |
| Queries return "no data" after 90 days | Workspace was created with default 90-day retention (the foundation provisioning was modified or skipped) | `provision.py` sets `retention_in_days=730` on the Log Analytics workspace; when `total_retention_in_days` is left unset it defaults to match `retention_in_days`, so 730 interactive days is the expected behavior. If a manual override shortened retention, run `provision.py` again or set `retentionInDays=730` and `totalRetentionInDays=730` directly. |
| WORM policy locked production data permanently | WORM applied via automation script | Never automate WORM - use manual `worm-configuration.md` steps with explicit confirmation |
| Adaptive sampling not reducing costs | Copilot Studio emits telemetry through managed service instrumentation rather than this Python deployment script | Configure ingestion sampling at the Application Insights resource/workspace level, not SDK level; see `cost-tuning-guide.md` |
| PII found in telemetry property bags during audit | Sensitive properties logging enabled in Copilot Studio | Disable sensitive logging or implement sanitization per `pii-sanitization-guide.md` |
| Authentication failed | DefaultAzureCredential cannot find valid credential | Use managed identity/workload identity for hosted automation, or run `az login` for administrator workstation validation. Service principal secrets are legacy dev-only fallback. |
| Resource creation fails with 403 | Insufficient RBAC permissions | Verify Owner or Contributor + User Access Admin on subscription/resource group |

## Related Controls

This solution supports the following FSI-AgentGov framework controls:

- [Control 1.7: Comprehensive Audit Logging and Compliance](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.7-comprehensive-audit-logging-and-compliance.md) - Primary evidence via Application Insights `AppEvents` / legacy `customEvents`
- [Control 3.2: Usage Analytics and Activity Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) - Session metrics and interaction analytics
- [Control 2.9: Agent Performance Monitoring and Optimization](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.9-agent-performance-monitoring-and-optimization.md) - Latency telemetry foundation
- [Control 2.8: Access Control and Segregation of Duties](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.8-access-control-and-segregation-of-duties.md) - Operational vs compliance access paths

## Version

**v1.2.4** - Technical accuracy review vs Microsoft Learn (2026-06-05)

**What's New in v1.2.4:**
- Corrected Viva Insights prerequisites in `power-bi/docs/viva-insights-scope.md`: the Copilot Studio agents report still requires at least 50 Copilot licenses (the prior "50-license minimum removed" note was inaccurate), per Microsoft Learn

**v1.2.3** - Lab-readiness validation (2026-06-04)

**What's New in v1.2.3:**
- Corrected WORM container coverage: `docs/worm-configuration.md` and `scripts/verify_worm.py` now identify `insights-logs-appevents` as the primary audit-of-record container (Copilot Studio interaction events) and direct applying/verifying WORM across all four diagnostic-export containers, not just `insights-logs-apptraces`
- Added `LAB-VALIDATION.md` static validation evidence report

**What's New in v1.2.2:**
- Removed stale "ADLS Gen2" reference and Control 1.6 (DSPM for AI) mappings from `power-bi/kql-views/vw_dim_regulation_control.kql`
- Fixed `flow-failure-correlation.kql` to project `operation_Id` through the `AgentEvents` materialized view (correlation joins now resolve)
- Removed stale Control 1.6 reference from `architecture.md` RBAC Separation section
- Synced version headers in `workbooks/README.md`, `alerts/README.md`, and `power-bi/README.md` to the solution version

See [CHANGELOG.md](CHANGELOG.md) for version history.

## License

MIT - See LICENSE in repository root
