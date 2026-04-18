# Deny Event Correlation Report

> **Status:** Validated

Daily operational reporting solution for correlating "deny/no content returned" events across Microsoft Copilot and Copilot Studio agents.

> ✅ **Authentication Migration Complete**: `Export-RaiTelemetry.ps1` was migrated to Entra ID authentication on February 4, 2026. No API key is required. See [prerequisites.md](docs/prerequisites.md#authentication-migration) for details.

## Overview

This solution provides automated extraction, correlation, and visualization of deny events from four Microsoft data sources:

| Source | Event Types | Purpose |
|--------|-------------|---------|
| **Microsoft Purview Audit** | CopilotInteraction deny (resource failure, policy block) | Agent-level access blocks |
| **Microsoft Purview DLP** | DlpRuleMatch for Copilot location | Sensitivity-based blocks |
| **Application Insights** | ContentFiltered RAI events | Model-layer content filtering |
| **Defender CloudAppEvents** (optional) | UPIA/XPIA, Jailbreak detections | Prompt injection & jailbreak detection (advanced) |

## Regulatory Alignment

This solution supports compliance evidence for:

- **FINRA 4511** - Books and records (enforceable rule); helps support
  retention of supervisory artifacts when paired with WORM storage and a
  retention schedule.
- **SEC 17a-3 / 17a-4** - Records to be made / records preservation
  (enforceable rules); the deny-event CSVs and KQL outputs can serve as
  ancillary supervisory records when stored on a 17a-4(f)-compliant
  electronic storage system. This solution does not by itself constitute a
  full 17a-4 compliance program — engage qualified counsel.
- **GLBA 501(b)** - Safeguards (enforceable rule); helps demonstrate
  monitoring of access denials on customer NPI.
- **FINRA Regulatory Notice 24-09** - Generative AI governance
  (supervisory guidance, not an enforceable rule)
- **OCC 2011-12 / Fed SR 11-7** - Model risk management (supervisory
  guidance, not enforceable rules)

## Contents

```
deny-event-correlation-report/
├── README.md                          # This file
├── CHANGELOG.md                       # Version history
├── scripts/
│   ├── Connect-ExchangeOnlineHelper.ps1  # Shared EXO connection helper
│   ├── Export-CopilotDenyEvents.ps1   # Purview CopilotInteraction extraction
│   ├── Export-DefenderCopilotEvents.ps1  # Defender CloudAppEvents extraction
│   ├── Export-DlpCopilotEvents.ps1    # Purview DLP extraction
│   ├── Export-RaiTelemetry.ps1        # Application Insights extraction
│   └── Invoke-DailyDenyReport.ps1     # Orchestration script
├── kql-queries/
│   ├── copilot-deny-events.kql        # Log Analytics queries
│   ├── dlp-copilot-matches.kql        # DLP correlation queries
│   ├── cloud-app-events.kql            # Defender XPIA/Jailbreak queries
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
  - Monitoring Reader (on Application Insights resource)
  - ThreatHunting.Read.All (optional, for Defender CloudAppEvents)
  - Storage Blob Data Contributor (optional, for blob upload)

### 2. Basic Usage

```powershell
# Install required modules
Install-Module ExchangeOnlineManagement -MinimumVersion 3.0.0 -Force
Install-Module Az.Accounts -MinimumVersion 2.17.0 -Force
Install-Module Az.Storage -Force
Install-Module Az.KeyVault -Force
# Optional — only required when extracting Defender CloudAppEvents:
# Install-Module Microsoft.Graph.Security -Force

# Connect to Exchange Online
Connect-ExchangeOnline

# Run individual extractions
.\scripts\Export-CopilotDenyEvents.ps1 -OutputPath ".\CopilotDeny.csv"
.\scripts\Export-DlpCopilotEvents.ps1 -OutputPath ".\DlpEvents.csv"

# Or run the orchestration script (Defender extraction is optional and
# requires Microsoft.Graph.Security + Connect-MgGraph -Scopes ThreatHunting.Read.All).
# Use -SkipDefenderEvents the first time you run end-to-end if Graph auth
# isn't configured yet:
.\scripts\Invoke-DailyDenyReport.ps1 -OutputDirectory ".\reports" -SkipDefenderEvents
```

### 3. Application Insights RAI Telemetry

For RAI telemetry, you need:

1. Application Insights resource in Azure
2. Entra ID authentication with Monitoring Reader role on the Application Insights resource
3. Copilot Studio agents configured with App Insights connection string

```powershell
# Authenticate with Entra ID
Connect-AzAccount

# Export RAI telemetry
.\scripts\Export-RaiTelemetry.ps1 `
    -AppInsightsAppId "your-app-id" `
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

> **Note:** No Power BI template (`.pbit`) is included. Build a report in Power BI Desktop by connecting to your CSV exports or Log Analytics workspace using the queries in `kql-queries/correlation-analysis.kql`.

## Documentation

- **[Architecture](docs/architecture.md)** - Solution design and data flow
- **[Prerequisites](docs/prerequisites.md)** - Detailed requirements
- **[Troubleshooting](docs/troubleshooting.md)** - Common issues and solutions

## Related Framework Documentation

This solution implements the [Deny Event Correlation Report](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/advanced-implementations/deny-event-correlation-report/index.md) playbook from the FSI Agent Governance Framework.

## Related Controls

- [Control 1.5: DLP and Sensitivity Labels](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.5-data-loss-prevention-dlp-and-sensitivity-labels.md)
- [Control 1.7: Comprehensive Audit Logging](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.7-comprehensive-audit-logging-and-compliance.md)
- [Control 1.8: Content Moderation](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.8-content-moderation-and-responsible-ai.md)
- [Control 3.4: Incident Reporting](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-3-reporting/3.4-incident-reporting-and-root-cause-analysis.md)

## Support

For issues or questions:
- [FSI-AgentGov Issues](https://github.com/judeper/FSI-AgentGov/issues)
- [FSI-AgentGov-Solutions Issues](https://github.com/judeper/FSI-AgentGov-Solutions/issues)

## License

MIT License - See [LICENSE](../LICENSE) for details.

---

*Deny Event Correlation Report v2.0.2 - 2026*
