# Action Confirmation Auditor

> **Version:** v1.0.0
> **Status:** Completed

Validates that Copilot Studio agent topics include user confirmation steps before executing actions (connector calls, cloud flows, plugins, HTTP requests), with zone-based policy enforcement for financial services governance.

## Overview

The Action Confirmation Auditor (ACA) scans Power Platform environments for Copilot Studio agents that invoke actions without requiring user confirmation. In regulated financial services environments, unconfirmed agent actions -- particularly write, delete, and external transfer operations -- represent operational and compliance risk. ACA identifies missing confirmation steps, classifies violations by severity based on zone and action type, and supports exception management for approved bypasses.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [1.23 - Step-Up Authentication for Agent Operations](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.23-step-up-authentication-for-agent-operations/) | Primary -- Step-up authentication enforcement |
| [1.8 - Runtime Protection](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.8-runtime-protection/) | Supporting -- Runtime action monitoring |
| [2.1 - Managed Environments](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-lifecycle/2.1-managed-environments/) | Dependency -- Zone classification source |
| [3.8 - Copilot Hub](https://judeper.github.io/FSI-AgentGov/controls/pillar-3-reporting/3.8-copilot-hub-and-governance-dashboard/) | Downstream -- Evidence export for governance dashboard |

## Regulatory Context

| Regulation | Relevance |
|------------|-----------|
| **FINRA 3110** | Supervisory system requirements for automated trading and client-facing operations |
| **GLBA 501(b)** | Safeguards for customer information accessed by automated agents |
| **SOX 404** | Internal control over financial reporting workflows executed by agents |

ACA supports compliance with these regulations by providing auditable evidence that agent actions include appropriate human-in-the-loop confirmation steps.

## Zone Requirements

Action confirmation requirements vary by governance zone:

| Action Category | Zone 1 | Zone 2 | Zone 3 |
|----------------|--------|--------|--------|
| Write/Delete Actions | Advisory | Confirmation required (High) | Confirmation required (Critical) |
| Read Actions | Advisory | Advisory | Confirmation required (High) |
| External Transfer | Advisory | Confirmation required (Medium) | Confirmation required (Critical) |
| All Other Actions | Advisory | Advisory | Confirmation required (High) |

## Violation Severity Matrix

When a required confirmation is missing, severity is classified as:

| Missing Confirmation | Zone 1 | Zone 2 | Zone 3 |
|---------------------|--------|--------|--------|
| Write/Delete action | Low | High | Critical |
| Read action | Low | Low | High |
| External transfer | Low | Medium | Critical |
| Other action | Low | Low | High |

## Features

- **Per-Action Validation** -- Inspects each action node in agent topics for confirmation steps
- **Zone Compliance** -- Enforces zone-specific confirmation requirements using ELM zone classification
- **Exception Management** -- Approval workflow for legitimate confirmation bypasses
- **Multiple Output Formats** -- Console, JSON, CSV evidence export
- **Dry-Run Mode** -- Preview scan results without writing to Dataverse
- **Severity Classification** -- Zone-aware severity assignment for each violation
- **Regulatory Context** -- Maps violations to FINRA 3110, GLBA 501(b), SOX 404 requirements
- **Environment Filtering** -- Scan specific environments or all environments
- **Teams/Email Alerting** -- Automated notifications via Power Automate flows
- **Evidence Export** -- SHA-256 hashed evidence packages for regulatory examination
- **v1.1 Risk Classification Import** -- Stub for custom risk rules per connector/action (deferred)

## Components

```
action-confirmation-auditor/
├── README.md
├── CHANGELOG.md
├── docs/
│   ├── dataverse-schema.md              # Auto-generated schema reference
│   ├── flow-configuration.md            # Manual build instructions for flows
│   └── prerequisites.md                 # Deployment prerequisites
└── scripts/
    ├── aca_client.py                    # ACA-specific Dataverse client wrapper
    ├── create_dataverse_schema.py       # Dataverse table/column deployment
    ├── requirements.txt                 # Python dependencies
    ├── governance/
    │   ├── Connect-EnvironmentDataverse.ps1
    │   ├── Get-ExpectedConfirmationPolicy.ps1
    │   ├── Get-ZoneClassification.ps1
    │   ├── Test-ParameterValidation.ps1
    │   └── Import-ActionRiskClassifications.ps1  # v1.1 stub
    └── private/
        ├── Connect-EnvironmentDataverse.ps1
        ├── Get-ExpectedConfirmationPolicy.ps1
        ├── Get-ZoneClassification.ps1
        └── Test-ParameterValidation.ps1
```

Power Automate flows are built manually using the instructions in `docs/flow-configuration.md`.

## Prerequisites

- Microsoft 365 E5 or E5 Compliance
- Power Platform environment with Dataverse
- Power Automate Premium license (for cloud flows)
- Power Platform Admin or Entra Global Admin permissions
- The Python setup scripts (`scripts/create_dataverse_schema.py`) depend on a shared `DataverseClient` module located at `../scripts/shared/dataverse_client.py` (relative to the repository root containing this solution). Ensure the [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions) repository structure is intact, or install the `dataverse_client` module on `PYTHONPATH`.

See [docs/prerequisites.md](docs/prerequisites.md) for detailed requirements.

## Quick Start

### 1. Deploy Dataverse Schema

```bash
python scripts/create_dataverse_schema.py \
  --dataverse-url https://yourorg.crm.dynamics.com \
  --client-id <app-id> \
  --client-secret <secret> \
  --tenant-id <tenant-id>
```

### 2. Run Compliance Scan (Dry-Run)

```powershell
# Preview scan results without writing to Dataverse
./scripts/governance/Get-ExpectedConfirmationPolicy.ps1 `
  -DataverseUrl "https://yourorg.crm.dynamics.com" `
  -WhatIf
```

### 3. Export Evidence

```powershell
# Export SHA-256 hashed evidence for regulatory examination
# (Evidence export is performed through the ACA-Scanner flow output)
```

## Configuration

| Environment Variable | Purpose | Default |
|---------------------|---------|---------|
| `fsi_ACA_DataverseUrl` | Target Dataverse organization URL | -- |
| `fsi_ACA_TenantId` | Azure AD tenant identifier | -- |
| `fsi_ACA_ClientId` | App registration client ID | -- |
| `fsi_ACA_ScanFrequencyHours` | Hours between scheduled scans | 24 |
| `fsi_ACA_TeamsGroupId` | Teams group for alert notifications | -- |
| `fsi_ACA_TeamsChannelId` | Teams channel for alert notifications | -- |
| `fsi_ACA_AlertSeverityThreshold` | Minimum severity for Teams alerts | Medium |
| `fsi_ACA_DryRunMode` | Enable dry-run mode (true/false) | true |

## Documentation

- [Prerequisites](docs/prerequisites.md) -- Licensing, permissions, and setup requirements
- [Dataverse Schema](docs/dataverse-schema.md) -- Table and column reference (auto-generated)
- [Flow Configuration](docs/flow-configuration.md) -- Manual build instructions for Power Automate flows

## License

MIT License -- see [LICENSE](../LICENSE)
