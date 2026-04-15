# Agent Access Governance Monitor

Automated validation of Power Platform environment agent access settings against zone-specific governance requirements.

> **Version:** v1.0.2
> **Status:** Completed

See [CHANGELOG](./CHANGELOG.md) for version history.

## Overview

The Agent Access Governance Monitor detects when Power Platform environments have overly permissive agent access configurations that violate governance zone requirements. It supports Control 3.8 (Copilot Hub and Governance Dashboard) by automating compliance validation.

## Quick Start

```powershell
# 1. Install required modules
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Force

# 2. Connect to Power Platform
Add-PowerAppsAccount

# 3. Run validation (dry-run mode)
./scripts/Test-AgentAccessCompliance.ps1 -ExcludeSandbox -WhatIf

# 4. Run full validation
./scripts/Test-AgentAccessCompliance.ps1 -ExcludeSandbox

# 5. Export compliance evidence
./scripts/Export-AgentAccessEvidence.ps1 -DataverseUrl https://org.crm.dynamics.com `
    -TenantId <your-tenant-id> -OutputDirectory ./exports -Interactive

# 6. Verify evidence integrity
./scripts/Test-EvidenceIntegrity.ps1 -EvidenceFilePath ./exports/aam-evidence-All-20260209-143022.json
```

## Features

| Feature | Description |
|---------|-------------|
| **Zone Compliance Validation** | Validates agent access settings against zone requirements (Zone 1/2/3) |
| **Multiple Output Formats** | Table (human-readable), JSON (archival), Object (pipeline) |
| **Dry-Run Mode** | Preview violations without persisting results |
| **Severity Classification** | Critical/High/Warning/Info per zone and violation type |
| **Regulatory Context** | FINRA 4511, SOX 404 context for each violation |
| **Environment Filtering** | Exclude sandbox, trial, default, or newly provisioned environments |
| **Evidence Export** | JSON evidence packages with SHA-256 integrity hashes for regulatory examinations |
| **Hash Verification** | Tamper-evident verification of exported evidence files (single, batch, cross-platform) |

## Zone Requirements

| Setting | Zone 1 (Personal) | Zone 2 (Team) | Zone 3 (Enterprise) |
|---------|-------------------|---------------|---------------------|
| `bot-limitSharingMode` | noLimit | ExcludeSharingToSecurityGroups | ExcludeSharingToSecurityGroups |
| `bot-authoringSharingDisabled` | false | false | true |
| `bot-publishedBotLimitSharingMode` | noLimit | ExcludeSharingToSecurityGroups | ExcludeSharingToSecurityGroups |

## Solution Components

```
agent-access-monitor/
├── scripts/
│   ├── Get-EnvironmentAccessSettings.ps1  # Query environments
│   ├── Compare-ZoneCompliance.ps1         # Compare settings vs requirements
│   ├── Test-AgentAccessCompliance.ps1     # Validation orchestrator
│   ├── Start-AccessValidationRunbook.ps1  # Azure Automation runbook wrapper
│   ├── Invoke-AccessBaselineCapture.ps1   # Baseline capture utility
│   ├── Export-AgentAccessEvidence.ps1     # Evidence export with SHA-256
│   ├── Test-EvidenceIntegrity.ps1         # Hash verification utility
│   ├── agent-access-monitor.psd1          # Module manifest
│   ├── deploy.py                          # Deployment orchestrator
│   ├── aam_client.py                      # Python Dataverse client
│   ├── create_dataverse_schema.py         # Schema deployment script
│   ├── create_environment_variables.py    # Environment variable setup
│   ├── create_connection_references.py    # Connection reference setup
│   ├── requirements.txt                   # Python dependencies
│   └── private/
│       ├── AAMClient.psm1                 # Dataverse client
│       ├── Get-ZoneClassification.ps1     # Zone lookup helper
│       ├── Get-ExpectedSettings.ps1       # Settings reference helper
│       ├── Get-AAMValidationResults.ps1   # Evidence query helper
│       └── Test-ParameterValidation.ps1   # Parameter validation helper
├── templates/
│   ├── zone-settings-baseline.json           # Zone requirements reference
│   ├── adaptive-card-access-alert.json       # Adaptive card template
│   └── adaptive-card-zone-access-alert.json  # Zone alert card template
└── docs/
    ├── prerequisites.md
    ├── flow-configuration.md
    ├── dataverse-schema.md
    ├── evidence-export.md
    └── troubleshooting.md
```

## Related Controls

| Control | Relationship |
|---------|--------------|
| [3.8 - Copilot Hub](https://judeper.github.io/FSI-AgentGov/controls/pillar-3-reporting/3.8-copilot-hub-and-governance-dashboard/) | Primary — Agent Access Control settings |
| [2.5 - Agent Sharing Scope](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.5-agent-sharing-scope/) | Agent sharing scope validation |
| [2.6 - Restrict Team-Created Agent Sharing](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.6-restrict-team-created-agent-sharing/) | Team-created agent sharing limits |
| [1.1 - Restrict Publishing](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.1-restrict-agent-publishing-by-authorization/) | Publishing authorization |
| [2.1 - Managed Environments](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.1-managed-environments/) | Sharing limits |

> **Evidence Export:** Use `Export-AgentAccessEvidence.ps1` to produce tamper-evident JSON evidence packages for regulatory examinations. See [docs/evidence-export.md](docs/evidence-export.md) for details.

## Prerequisites

See [docs/prerequisites.md](docs/prerequisites.md) for detailed requirements.

## Configuration Placeholders

The following placeholder values in template files must be replaced with your organization's values before use:

| Placeholder | Replace With | Files |
|------------|-------------|-------|
| `your-org.github.io` | Your GitHub Pages domain | `templates/adaptive-card-zone-access-alert.json` |

> **Note:** Flow-specific placeholders (Dataverse URL, tenant ID, certificate thumbprint, etc.) are configured when manually building the Power Automate flow. See [docs/flow-configuration.md](docs/flow-configuration.md) for step-by-step instructions.

## Deployment

1. Deploy Dataverse schema (see prerequisites)
2. Build the Power Automate flow manually using [docs/flow-configuration.md](docs/flow-configuration.md)
3. Configure connection references
4. Activate cloud flows
5. Verify deployment using the verification steps below

## License

MIT License - See [LICENSE](../LICENSE)
