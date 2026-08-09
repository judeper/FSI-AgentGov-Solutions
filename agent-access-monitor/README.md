---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P1, P4]
applicable_drivers:
  - ai_governance
  - technology_data
coe_function: optimize
---
# Agent Access Governance Monitor

> **Version:** v1.2.0
> **Status:** Live
> **Validated against framework version:** v1.6.0
> **Last Verified:** 2026-08-09

Automated validation of Power Platform environment agent access settings against zone-specific governance requirements.

See [CHANGELOG](./CHANGELOG.md) for version history.

## Verification Notes (Last Re-Verified: 2026-08-09)

**Technical claims verified against current Microsoft Learn documentation:**
- ✅ Managed Environment agent sharing settings documented in [Limit sharing](https://learn.microsoft.com/power-platform/admin/managed-environment-sharing-limits)
- ✅ Agent sharing rules configuration options ([Agent sharing rules section](https://learn.microsoft.com/power-platform/admin/managed-environment-sharing-limits#agent-sharing-rules))
- ✅ Setting names: `bot-limitSharingMode`, `bot-authoringSharingDisabled`, `bot-maxLimitUserSharing` confirmed in PowerShell examples
- ✅ Enforcement timing: "up to an hour" for sharing rules to begin enforcement (confirmed in official docs)
- ✅ Microsoft.PowerApps.Administration.PowerShell module for administration ([Get started using the Power Apps admin module](https://learn.microsoft.com/power-platform/admin/powerapps-powershell))
- ✅ Copilot Studio security and governance controls ([Key concepts - Copilot Studio security and governance](https://learn.microsoft.com/microsoft-copilot-studio/security-and-governance))

All technical product claims remain accurate as of the verification date above. No drift detected.

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

| Setting | Zone 1 (Enterprise) | Zone 2 (Team) | Zone 3 (Personal) |
|---------|---------------------|---------------|-------------------|
| `bot-limitSharingMode` | ExcludeSharingToSecurityGroups | ExcludeSharingToSecurityGroups | noLimit |
| `bot-authoringSharingDisabled` | true | false | false |
| `bot-maxLimitUserSharing` | Capped | Capped | Uncapped |

> `bot-maxLimitUserSharing` is the Managed-Environment per-maker user-sharing cap. AAM
> normalizes the raw value to **Capped** (a positive integer limit, e.g. `20`) or
> **Uncapped** (`-1`, `0`, blank, or unset). The more-restrictive zones (Zone 1 Enterprise,
> Zone 2 Team) require a Capped limit; Zone 3 personal environments may remain Uncapped.

## Scope and Microsoft Learn Alignment

AAM validates Managed Environment agent sharing settings documented in [Power Platform limit sharing](https://learn.microsoft.com/power-platform/admin/managed-environment-sharing-limits). It does not enumerate individual Copilot Studio shares or Microsoft 365 Copilot package assignments. Microsoft Learn does not restrict these sharing limits to agents that require authentication; consult the authoritative [agent sharing rules](https://learn.microsoft.com/power-platform/admin/managed-environment-sharing-limits#agent-sharing-rules) for scope. The documented sharing semantics note that limit changes can take up to an hour to enforce and do not immediately revoke existing access.

Broad-sharing values from adjacent APIs (`all`, `AllUsers`, `OrgWide`, and tenant-wide variants) are normalized to the Managed Environment `noLimit` value during severity evaluation. Future inventory expansion should treat Microsoft Graph package and Agent Registry APIs as preview sources until production support is confirmed.

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
