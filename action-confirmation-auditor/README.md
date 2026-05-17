---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P4, P5, P6]
applicable_drivers:
  - ai_governance
  - technology_data
coe_function: govern
---
# Action Confirmation Auditor

> **Version:** v1.1.1
> **Status:** Completed

Validates that Copilot Studio agent topics include user confirmation steps before executing actions (connector calls, cloud flows, plugins, HTTP requests), with zone-based policy enforcement for financial services governance.

## Overview

The Action Confirmation Auditor (ACA) scans Power Platform environments for Copilot Studio agents that invoke actions without requiring user confirmation. In regulated financial services environments, unconfirmed agent actions -- particularly write, delete, and external transfer operations -- represent operational and compliance risk. ACA identifies missing confirmation steps, classifies violations by severity based on zone and action type, and supports exception management for approved bypasses (with Maker/Checker approval gating).

## Related Controls

| Control | Relationship |
|---------|--------------|
| [2.12 - Supervision and Oversight (FINRA Rule 3110)](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.12-supervision-and-oversight-finra-rule-3110/) | Primary -- HITL confirmation node validation in agent topics |
| [1.10 - Communication Compliance Monitoring](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.10-communication-compliance-monitoring/) | Supporting -- Aids FINRA 3110 supervisory review evidence |
| [2.1 - Managed Environments](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.1-managed-environments/) | Dependency -- Zone classification source |
| [3.8 - Copilot Hub](https://judeper.github.io/FSI-AgentGov/controls/pillar-3-reporting/3.8-copilot-hub-and-governance-dashboard/) | Downstream -- Evidence export for governance dashboard |

> **Note on Control 1.23:** Earlier versions claimed Control 1.23 (Step-Up Authentication for Agent Operations). Control 1.23 is implemented through Entra Authentication Contexts, Conditional Access policies, and phishing-resistant MFA -- see the *Conditional Access Automation* and *Session Security Configurator* solutions. ACA validates HITL/approval prompts in agent topics, which is governed by Control 2.12. ACA does not by itself satisfy AAL2/AAL3 step-up authentication requirements.

## Regulatory Context

| Regulation | Relevance |
|------------|-----------|
| **FINRA Rule 3110** | Supervisory system requirements for automated trading and client-facing operations |
| **GLBA Section 501(b)** | Safeguards for customer information accessed by automated agents |
| **SOX Section 404** | Internal control over financial reporting workflows executed by agents |

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
- **User-Defined Action Messages** -- Validates that agents have user-defined action messages configured per zone policy (Zone 3 required, Zone 2 recommended, Zone 1 optional)
- **Zone Compliance** -- Applies zone-specific confirmation requirements using ELM zone classification
- **Exception Management** -- Approval workflow for legitimate confirmation bypasses
- **Multiple Output Formats** -- Console and JSON evidence export
- **Dry-Run Mode** -- Preview scan results without writing to Dataverse
- **Severity Classification** -- Zone-aware severity assignment for each violation
- **Regulatory Context** -- Maps violations to FINRA 3110, GLBA 501(b), SOX 404 requirements
- **Environment Filtering** -- Scan specific environments or all environments
- **Teams/Email Alerting** -- Automated notifications via Power Automate flows
- **Evidence Export** -- SHA-256 hashed evidence packages for regulatory examination
- **v1.1 Risk Classification Import** -- Stub for custom risk rules per connector/action (deferred)
- **Managed Identity Runbook** -- Sample Azure Automation runbook using system-assigned or user-assigned MI authentication (replaces deprecated RunAs accounts)
- **Purview AI Hub / DSPM Integration** -- Cross-references action confirmation events with Purview AI Hub activities for dual-confirmation evidence

## Components

```
action-confirmation-auditor/
├── README.md
├── CHANGELOG.md
├── docs/
│   ├── dataverse-schema.md
│   ├── flow-configuration.md
│   └── prerequisites.md
├── scripts/
│   ├── aca_client.py
│   ├── create_connection_references.py
│   ├── create_dataverse_schema.py
│   ├── create_environment_variables.py
│   ├── deploy.py
│   ├── requirements.txt
│   ├── Export-ActionAuditEvidence.ps1
│   ├── Get-AgentActionSettings.ps1
│   ├── Start-ActionConfirmationValidationRunbook.ps1
│   ├── Start-ActionConfirmationRunbook-MI.ps1
│   ├── Test-ActionConfirmationCompliance.ps1
│   ├── Test-EvidenceIntegrity.ps1
│   ├── governance/
│   │   ├── Import-ActionRiskClassifications.ps1
│   │   └── Test-UserDefinedActionMessages.ps1
│   ├── Get-PurviewAIHubEvidence.ps1
│   └── private/
│       ├── ACAClient.psm1
│       ├── Connect-EnvironmentDataverse.ps1
│       ├── Get-ExpectedConfirmationPolicy.ps1
│       ├── Get-ZoneClassification.ps1
│       └── Test-ParameterValidation.ps1
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
  --environment-url https://yourorg.crm.dynamics.com \
  --tenant-id <tenant-id> \
  --interactive
```

### 2. Run Compliance Scan (Dry-Run)

```powershell
# Preview scan results without writing to Dataverse
. ./scripts/Test-ActionConfirmationCompliance.ps1
Test-ActionConfirmationCompliance -WhatIf
```

### 3. Export Evidence

```powershell
# Export SHA-256 hashed evidence for regulatory examination
./scripts/Export-ActionAuditEvidence.ps1 `
  -DataverseUrl "https://yourorg.crm.dynamics.com" `
  -TenantId "contoso.onmicrosoft.com" `
  -OutputDirectory ".\evidence" `
  -Interactive
```

## Configuration

| Environment Variable | Purpose | Default |
|---------------------|---------|---------|
| `fsi_ACA_GracePeriodHours` | Hours to exclude newly provisioned environments | 48 |
| `fsi_ACA_ScanFrequencyHours` | Hours between scheduled scans | 24 |
| `fsi_ACA_IncludeSandbox` | Include sandbox environments in scans | false |
| `fsi_ACA_IncludeDrafts` | Include draft/unpublished agents in scans | false |
| `fsi_ACA_ConfirmationPatternMode` | Detection mode: standard, strict, permissive | standard |
| `fsi_ACA_TeamsGroupId` | Teams group for alert notifications | -- |
| `fsi_ACA_TeamsChannelId` | Teams channel for alert notifications | -- |

## Documentation

- [Prerequisites](docs/prerequisites.md) -- Licensing, permissions, and setup requirements
- [Dataverse Schema](docs/dataverse-schema.md) -- Table and column reference (auto-generated)
- [Flow Configuration](docs/flow-configuration.md) -- Manual build instructions for Power Automate flows
- See [CHANGELOG](./CHANGELOG.md) for version history.

## License

MIT License -- see [LICENSE](../LICENSE)
