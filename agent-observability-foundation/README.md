# Agent Observability Foundation

> **Status:** Work In Progress

FSI-compliant telemetry infrastructure for Microsoft Copilot Studio agents with long-term audit retention.

## Architecture Overview

The Agent Observability Foundation deploys a production-ready telemetry pipeline that captures Copilot Studio agent interactions and stores them with retention periods that help support SEC 17a-4 compliance requirements. The solution establishes a clear separation between operational monitoring (real-time queries via Log Analytics) and compliance audit paths (immutable ADLS Gen2 export), supporting Control 2.8 (Access Control and Segregation of Duties).

This architecture addresses the unique challenges of AI agent observability in regulated financial services: capturing conversation telemetry without exposing PII, maintaining audit trails that satisfy FINRA 4511 books and records requirements, and providing cost-effective storage tiers that balance operational needs with long-term retention mandates. The solution supports Control 1.7 (Comprehensive Audit Logging), Control 3.2 (Usage Analytics and Activity Monitoring), and Control 2.9 (Agent Performance Monitoring).

All Azure resources are provisioned via Python scripts using the Azure SDK for Python, enabling repeatable lab deployments and teardown cycles. WORM (Write Once Read Many) policy configuration for SEC 17a-4(f) compliance is deliberately excluded from automation to prevent accidental immutable lockdown in production environments.

## What This Solution Does

- **Deploys Application Insights** with 730-day retention for Copilot Studio telemetry capture (customEvents with CopilotInteraction schema)
- **Creates Log Analytics workspace** with 2-year interactive query capability using PerGB2018 pricing tier
- **Configures ADLS Gen2 export** via Diagnostic Settings for SEC 17a-4 long-term retention (7+ years with WORM)
- **Establishes RBAC separation** between operational monitoring (Monitoring Reader) and compliance audit paths (Storage Blob Data Reader)
- **Provides PII sanitization guidance** for conversation data in customDimensions fields (text, speak, fromName, recipientName)
- **Includes cost management configuration** with sampling defaults and cost alert thresholds

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
3. **Entra ID authentication** configured (interactive login, Service Principal, or Managed Identity)
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

## Solution Structure

```
agent-observability-foundation/
├── README.md                          # This file - solution overview
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
│   └── requirements.txt               # Python dependencies
├── docs/
│   ├── pii-sanitization-guide.md      # Decision framework for PII handling
│   ├── cost-tuning-guide.md           # Sampling and cost management
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
| [docs/pii-sanitization-guide.md](docs/pii-sanitization-guide.md) | Decision framework for handling PII in customDimensions |
| [docs/cost-tuning-guide.md](docs/cost-tuning-guide.md) | Sampling configuration and cost alert thresholds |
| [docs/worm-configuration.md](docs/worm-configuration.md) | Manual WORM policy setup for SEC 17a-4(f) compliance |

## Troubleshooting

| Issue | Cause | Solution |
|-------|-------|----------|
| Diagnostic settings export shows no data | ADLS Gen2 hierarchical namespace enabled | Create StorageV2 account WITHOUT hierarchical namespace (limitation of diagnostic settings) |
| Queries return "no data" after 90 days | Only `retentionInDays` set, not `totalRetentionInDays` | Set BOTH `retentionInDays=730` AND `totalRetentionInDays=730` for full interactive access |
| WORM policy locked production data permanently | WORM applied via automation script | Never automate WORM - use manual `worm-configuration.md` steps with explicit confirmation |
| Adaptive sampling not reducing costs | Python SDK does not support adaptive sampling | Configure ingestion sampling at workspace level, not SDK level; see `cost-tuning-guide.md` |
| PII found in customDimensions during audit | Sensitive properties logging enabled in Copilot Studio | Disable sensitive logging or implement sanitization per `pii-sanitization-guide.md` |
| Authentication failed | DefaultAzureCredential cannot find valid credential | Run `az login` for interactive auth or configure Service Principal environment variables |
| Resource creation fails with 403 | Insufficient RBAC permissions | Verify Owner or Contributor + User Access Admin on subscription/resource group |

## Related Controls

This solution supports the following FSI-AgentGov framework controls:

- [Control 1.7: Comprehensive Audit Logging and Compliance](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.7-comprehensive-audit-logging-and-compliance.md) - Primary evidence via Application Insights customEvents
- [Control 3.2: Usage Analytics and Activity Monitoring](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.2-usage-analytics-and-activity-monitoring.md) - Session metrics and interaction analytics
- [Control 2.9: Agent Performance Monitoring and Optimization](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.9-agent-performance-monitoring-and-optimization.md) - Latency telemetry foundation
- [Control 1.6: Microsoft Purview DSPM for AI](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.6-microsoft-purview-dspm-for-ai.md) - RBAC separation for content access
- [Control 2.8: Access Control and Segregation of Duties](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.8-access-control-and-segregation-of-duties.md) - Operational vs compliance access paths

## Version

v0.1.0 - February 2026

See [CHANGELOG.md](CHANGELOG.md) for version history.

## License

MIT - See LICENSE in repository root
