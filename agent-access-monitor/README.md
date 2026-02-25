# Agent Access Governance Monitor

Automated validation of Power Platform environment agent access settings against zone-specific governance requirements.

> **Status:** Completed

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
│   ├── Invoke-AccessBaselineCapture.ps1   # Baseline capture operator script
│   ├── Export-AgentAccessEvidence.ps1     # Evidence export with SHA-256
│   ├── Test-EvidenceIntegrity.ps1         # Hash verification utility
│   ├── aam_client.py                      # Python Dataverse Web API client
│   ├── create_dataverse_schema.py         # Schema deployment script
│   ├── create_environment_variables.py    # Environment variable deployment
│   ├── create_connection_references.py    # Connection reference deployment
│   ├── deploy.py                          # Deployment orchestrator
│   ├── requirements.txt                   # Python dependencies
│   ├── agent-access-monitor.psd1          # PowerShell module manifest
│   └── private/
│       ├── AAMClient.psm1                 # Dataverse client
│       ├── Get-ZoneClassification.ps1     # Zone lookup helper (standalone — not currently called)
│       ├── Get-ExpectedSettings.ps1       # Settings reference helper (standalone — not currently called)
│       ├── Get-AAMValidationResults.ps1   # Evidence query helper
│       └── Test-ParameterValidation.ps1   # Parameter validation helper
├── src/
│   ├── access-validation-flow.json        # Power Automate cloud flow
│   ├── adaptive-card-access-alert.json    # Teams adaptive card template (reference only — see note below)
│   └── adaptive-card-zone-access-alert.json  # Zone-specific alert card (reference only — see note below)
├── templates/
│   └── zone-settings-baseline.json        # Zone requirements reference
└── docs/
    ├── PREREQUISITES.md
    ├── FLOW_SETUP.md
    ├── SCHEMA.md
    ├── EVIDENCE_EXPORT.md
    └── TROUBLESHOOTING.md
```

> **Adaptive Card Templates:** The template files (`adaptive-card-access-alert.json`, `adaptive-card-zone-access-alert.json`) are **design-time references only**. The flow (`access-validation-flow.json`) constructs its adaptive card inline via string replacement and does not reference these template files at runtime. The inline card shows **summary-level data only** (zone compliant/total counts), while the template files include additional per-violation and per-drift detail sections for reference when building custom integrations. If you modify the shared card sections (header, run summary, zone summary, actions), update both the template file and the inline card string in the flow definition.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [3.8 - Copilot Hub](https://judeper.github.io/FSI-AgentGov/controls/pillar-3-reporting/3.8-copilot-hub-and-governance-dashboard/) | Primary — Agent Access Control settings |
| [1.1 - Restrict Publishing](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.1-restrict-agent-publishing-by-authorization/) | Publishing authorization |
| [2.1 - Managed Environments](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.1-managed-environments/) | Sharing limits |
| [2.5 - Agent Sharing Scope](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.5-agent-sharing-scope/) | Agent sharing scope validation |
| [2.6 - Restrict Team-Created Agent Sharing](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.6-restrict-team-created-agent-sharing/) | Team-created agent sharing restrictions |

> **Evidence Export:** Use `Export-AgentAccessEvidence.ps1` to produce tamper-evident JSON evidence packages for regulatory examinations. See [docs/EVIDENCE_EXPORT.md](docs/EVIDENCE_EXPORT.md) for details.

## Prerequisites

See [docs/PREREQUISITES.md](docs/PREREQUISITES.md) for detailed requirements.

## Configuration Placeholders

The following placeholder values in solution files must be replaced with your organization's values before deployment:

| Placeholder | Replace With | Files |
|------------|-------------|-------|
| `contoso.onmicrosoft.com` | Your tenant domain | `src/access-validation-flow.json` |
| `your-client-id-here` | Your app registration client ID | `src/access-validation-flow.json` |
| `your-certificate-thumbprint-here` | Your certificate thumbprint | `src/access-validation-flow.json` |
| `your-subscription-id-here` | Your Azure subscription ID | `src/access-validation-flow.json` |
| `your-teams-group-id-here` | Your Teams group ID for alerts | `src/access-validation-flow.json` |
| `your-teams-channel-id-here` | Your Teams channel ID for alerts | `src/access-validation-flow.json` |
| `compliance-alerts@contoso.com` | Your compliance team email | `src/access-validation-flow.json` |
| `https://governance.crm.dynamics.com` | Your Dataverse organization URL | `src/access-validation-flow.json` |
| `https://your-org.github.io/FSI-AgentGov/...` | Your organization's FSI-AgentGov documentation URL | `src/access-validation-flow.json`, `src/adaptive-card-zone-access-alert.json` |
| `rg-agent-access-monitor` | Your Azure resource group name | `src/access-validation-flow.json` |
| `aa-agent-access-monitor` | Your Azure Automation Account name | `src/access-validation-flow.json` |

## Deployment

1. Run the Python deployment orchestrator to create Dataverse schema, environment variables, and connection references:
   ```bash
   python scripts/deploy.py
   ```
2. Import the flow definition from `src/access-validation-flow.json` via Power Automate
3. Bind connection references (see [Flow Setup](docs/FLOW_SETUP.md))
4. Update placeholder values (see Configuration Placeholders above)
5. Activate cloud flows
6. Verify deployment using the verification steps below

## License

MIT License - See [LICENSE](../LICENSE)
