# Deny Event Correlation Report

Daily operational reporting solution for correlating "deny/no content returned" events across Microsoft Copilot and Copilot Studio agents.

> ⚠️ **Deprecation Warning: x-api-key Authentication**
>
> Application Insights x-api-key authentication is deprecated and will be removed **March 31, 2026**. After this date, `Export-RaiTelemetry.ps1` will fail unless migrated to Entra ID authentication. See [prerequisites.md](docs/prerequisites.md#authentication-migration) for migration guidance.

## Overview

This solution provides automated extraction, correlation, and visualization of deny events from three Microsoft data sources:

| Source | Event Types | Purpose |
|--------|-------------|---------|
| **Microsoft Purview Audit** | CopilotInteraction deny, XPIA, Jailbreak | Agent-level access blocks |
| **Microsoft Purview DLP** | DlpRuleMatch for Copilot location | Sensitivity-based blocks |
| **Application Insights** | ContentFiltered RAI events | Model-layer content filtering |
| **Defender CloudAppEvents** (optional) | UPIA/XPIA detections | Prompt injection detection (advanced) |

## Regulatory Alignment

This solution supports compliance evidence for:

- **FINRA 25-07** - AI governance evidence
- **FINRA 4511** - Records retention
- **SEC 17a-3/4** - Supervision evidence
- **GLBA 501(b)** - Safeguards evidence
- **OCC 2011-12** - Model risk controls

## Contents

```
deny-event-correlation-report/
├── README.md                          # This file
├── scripts/
│   ├── Export-CopilotDenyEvents.ps1   # Purview CopilotInteraction extraction
│   ├── Export-DlpCopilotEvents.ps1    # Purview DLP extraction
│   ├── Export-RaiTelemetry.ps1        # Application Insights extraction
│   └── Invoke-DailyDenyReport.ps1     # Orchestration script
├── kql-queries/
│   ├── copilot-deny-events.kql        # Log Analytics queries
│   ├── dlp-copilot-matches.kql        # DLP correlation queries
│   ├── content-filtered-events.kql    # App Insights RAI queries
│   └── correlation-analysis.kql       # Cross-source correlation
└── docs/
    ├── architecture.md                # Solution architecture
    ├── prerequisites.md               # Requirements and permissions
    └── troubleshooting.md             # Common issues
```

## Quick Start

### 1. Prerequisites

- Microsoft 365 E5 or E5 Compliance
- Power BI Pro or Premium
- Azure subscription (for storage and automation)
- Required permissions:
  - Purview Audit Reader
  - Application Insights Reader
  - Storage Blob Data Contributor (optional, for blob upload)

### 2. Basic Usage

```powershell
# Install required modules
Install-Module ExchangeOnlineManagement -Force
Install-Module Az.Storage -Force
Install-Module Az.KeyVault -Force

# Connect to Exchange Online
Connect-ExchangeOnline

# Run individual extractions
.\scripts\Export-CopilotDenyEvents.ps1 -OutputPath ".\CopilotDeny.csv"
.\scripts\Export-DlpCopilotEvents.ps1 -OutputPath ".\DlpEvents.csv"

# Or run the orchestration script
.\scripts\Invoke-DailyDenyReport.ps1 -OutputDirectory ".\reports"
```

### 3. Application Insights RAI Telemetry

For RAI telemetry, you need:

1. Application Insights resource in Azure
2. API key with read permissions
3. Copilot Studio agents configured with App Insights connection string

```powershell
# Export RAI telemetry
.\scripts\Export-RaiTelemetry.ps1 `
    -AppInsightsAppId "your-app-id" `
    -ApiKey "your-api-key" `
    -OutputPath ".\RaiTelemetry.csv"
```

### 4. Scheduled Automation

For daily automated extraction, deploy to Azure Automation:

1. Create Azure Automation Account
2. Import required modules (ExchangeOnlineManagement, Az.*)
3. Create Runbook with `Invoke-DailyDenyReport.ps1`
4. Configure schedule (daily at 6 AM recommended)
5. Configure Azure Key Vault for credentials

See [docs/architecture.md](docs/architecture.md) for detailed deployment instructions.

## Documentation

- **[Architecture](docs/architecture.md)** - Solution design and data flow
- **[Prerequisites](docs/prerequisites.md)** - Detailed requirements
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions

## Related Framework Documentation

This solution implements the [Deny Event Correlation Report](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/advanced-implementations/deny-event-correlation-report/index.md) playbook from the FSI Agent Governance Framework.

## Related Controls

- [Control 1.5: DLP and Sensitivity Labels](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.5-data-loss-prevention-dlp-and-sensitivity-labels.md)
- [Control 1.7: Comprehensive Audit Logging](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.7-comprehensive-audit-logging-and-compliance.md)
- [Control 3.4: Incident Reporting](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.4-incident-reporting-and-root-cause-analysis.md)

## Support

For issues or questions:
- [FSI-AgentGov Issues](https://github.com/judeper/FSI-AgentGov/issues)
- [FSI-AgentGov-Solutions Issues](https://github.com/judeper/FSI-AgentGov-Solutions/issues)

## License

MIT License - See [LICENSE](../LICENSE) for details.

---

*FSI Agent Governance Framework v1.2 - January 2026*
