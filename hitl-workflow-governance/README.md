# HITL Workflow Governance

> **Version:** v1.0.0
> **Status:** Completed

Validates that Copilot Studio agent flows include required human-in-the-loop (HITL) checkpoints per zone governance policy, using Microsoft's **Request for Information** and **Run a Multistage Approval** actions from the `advancedapprovals` connector.

## Overview

The HITL Workflow Governance solution (HWG) scans Power Platform environments for Copilot Studio agents and validates that their flows include required human review checkpoints. In regulated financial services environments, agent actions that modify data, initiate external communication, or process customer financial information may require human approval before execution. HWG identifies agents missing required HITL steps, classifies violations by severity based on zone and action type, tracks evidence of human review, and exports compliance evidence for regulatory examination.

Microsoft introduced the **Request for Information** (RFI) action for Copilot Studio agent flows in public preview in July 2025. The `advancedapprovals` connector also provides **Run a Multistage Approval** for structured approval workflows. Both actions remain labeled as preview in the connector reference. Organizations should review the [Power Platform preview terms](https://www.microsoft.com/business-applications/legal/supp-powerplatform-preview/) before using these actions with regulated data.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [2.12 - Supervision and Oversight](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-lifecycle/2.12-supervision-and-oversight/) | Primary — Human review checkpoint validation for supervision evidence |
| [2.17 - Multi-Agent Orchestration Limits](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-lifecycle/2.17-multi-agent-orchestration-limits/) | Primary — HITL checkpoints within multi-step and multi-agent workflow patterns |
| [1.10 - Communication Compliance](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.10-communication-compliance-monitoring/) | Supporting — Reviewer identity, decision context, and timestamp retention for output review |
| [2.1 - Managed Environments](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-lifecycle/2.1-managed-environments/) | Dependency — Zone classification source |
| [3.8 - Copilot Hub](https://judeper.github.io/FSI-AgentGov/controls/pillar-3-reporting/3.8-copilot-hub-and-governance-dashboard/) | Downstream — Evidence export for governance dashboard |

## Regulatory Context

| Regulation | Relevance |
|------------|-----------|
| **FINRA Rule 3110** | Supervisory procedures requiring human review of AI agent outputs before client-facing actions |
| **FINRA 4511(a)** | Books and records requirements for supervision evidence, including documentation that human review checkpoints were invoked |
| **SEC 17a-3/4** | Supervisory review documentation and record preservation for human-in-the-loop decision records |
| **SOX 302/404** | Internal control documentation demonstrating that material financial workflows include human review steps |
| **GLBA 501(b)** | Safeguards for customer financial information requiring human oversight of agent actions that access or transmit protected data |

HWG supports compliance with these regulations by providing auditable evidence that agent flows include appropriate human review checkpoints. Implementation of this solution alone does not satisfy regulatory obligations — organizations should verify that HITL configurations meet their specific supervisory requirements.

## Zone Requirements

HITL checkpoint requirements vary by governance zone:

| Zone | HITL Scope | Review Model | SLA | Enforcement |
|------|-----------|--------------|-----|-------------|
| Zone 3 (Enterprise) | All write, financial, external, and customer-facing actions require HITL checkpoint | Pre-approval mandatory; 100% review | 4 hours | Mandatory — violations are Critical/High |
| Zone 2 (Team) | Financial, external, and PII-handling actions require HITL checkpoint | Sampled review (10%) | 24 hours | Required — violations are High/Medium |
| Zone 1 (Personal) | HITL recommended but not required | Periodic spot-check | Advisory | Advisory — findings are Warning severity |

## Violation Severity Matrix

When a required HITL checkpoint is missing, severity is classified as:

| Missing HITL Checkpoint | Zone 1 | Zone 2 | Zone 3 |
|------------------------|--------|--------|--------|
| Write/financial action | Warning | High | Critical |
| External/customer-facing action | Warning | High | Critical |
| PII-handling action | Warning | Medium | Critical |
| Multi-agent handoff without HITL | Warning | Medium | High |
| Other action (read, internal) | Warning | Warning | Medium |

## Features

- **HITL Checkpoint Detection** — Scans agent flow definitions for Request for Information and Run a Multistage Approval actions from the `advancedapprovals` connector
- **Zone-Based Policy Evaluation** — Enforces zone-specific HITL requirements using ELM zone classification
- **Reviewer Assignment Validation** — Verifies that HITL steps include designated reviewer configuration
- **Input Configuration Verification** — Validates that RFI actions include required input parameters (question text, response options)
- **Dataverse Evidence Persistence** — Stores scan results, exceptions, and run history in three Dataverse tables
- **SHA-256 Evidence Export** — Integrity-hashed evidence packages for regulatory examination
- **Azure Automation Runbook** — Scheduled scan execution with drift detection
- **Teams Adaptive Card Notifications** — Alert notifications with violation details and regulatory context
- **Exception Management** — Approval workflow for legitimate HITL checkpoint bypasses with expiration tracking

## Solution Components

```
hitl-workflow-governance/
├── README.md
├── CHANGELOG.md
├── docs/
│   ├── prerequisites.md                    # Licensing, roles, dependencies
│   ├── dataverse-schema.md                 # Auto-generated schema reference
│   ├── flow-configuration.md               # Manual build instructions for Power Automate flows
│   └── troubleshooting.md                  # Error recovery procedures
└── scripts/
    ├── create_hwg_dataverse_schema.py      # Dataverse table/column deployment
    ├── create_hwg_environment_variables.py  # Environment variable deployment
    ├── create_hwg_connection_references.py  # Connection reference deployment
    ├── deploy_hwg.py                       # Orchestrator (schema + env vars + connections)
    ├── requirements.txt                    # Python dependencies
    ├── Test-HitlWorkflowCompliance.ps1         # Scan orchestrator
    ├── Export-HitlGovernanceEvidence.ps1        # SHA-256 evidence export
    ├── Test-EvidenceIntegrity.ps1               # Evidence hash verification
    ├── Start-HitlValidationRunbook.ps1          # Azure Automation wrapper
    ├── Get-AgentHitlSettings.ps1                # Agent HITL settings query
    ├── governance/
    │   └── Test-HitlCheckpointConfiguration.ps1 # HITL checkpoint configuration
    ├── private/
    │   ├── HWGClient.psm1                  # Dataverse client module
    │   ├── Get-HitlCheckpointResults.ps1   # Evidence query helper
    │   ├── Get-ZoneClassification.ps1      # Zone lookup helper
    │   ├── Get-ExpectedHitlPolicy.ps1      # HITL policy reference
    │   ├── Test-ParameterValidation.ps1    # Parameter validators
    │   └── Connect-EnvironmentDataverse.ps1 # Per-env Dataverse auth
    └── templates/
        ├── zone-hitl-policy.json               # Zone policy configuration
        └── adaptive-card-hitl-alert.json       # Teams alert template
```

Power Automate flows are built manually using the instructions in [docs/flow-configuration.md](docs/flow-configuration.md).

## Prerequisites

- Microsoft 365 E5 or E5 Compliance
- Power Platform environment with Dataverse
- Power Automate Premium license (for cloud flows)
- Power Platform Admin or Entra Global Admin permissions
- Python 3.9+ and PowerShell 7+ for setup and governance scripts
- The Python setup scripts depend on a shared `DataverseClient` module located at `../scripts/shared/dataverse_client.py` (relative to the repository root). Ensure the [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions) repository structure is intact, or install the `dataverse_client` module on `PYTHONPATH`.

See [docs/prerequisites.md](docs/prerequisites.md) for detailed requirements.

## Quick Start

### 1. Register Entra ID Application

Register an app in Microsoft Entra ID with the following API permissions:
- `Dynamics CRM > user_impersonation` (Dataverse access)
- `PowerApps Service > User` (Power Platform admin queries)

### 2. Install Dependencies

```bash
# Python dependencies
pip install -r scripts/requirements.txt

# PowerShell modules
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Force
```

### 3. Deploy Dataverse Schema

```bash
# Dry run first
python scripts/deploy_hwg.py \
  --dataverse-url https://yourorg.crm.dynamics.com \
  --tenant-id <tenant-id> \
  --interactive \
  --dry-run

# Full deployment
python scripts/deploy_hwg.py \
  --dataverse-url https://yourorg.crm.dynamics.com \
  --tenant-id <tenant-id> \
  --interactive
```

### 4. Run Initial Scan

```powershell
# Preview scan results without writing to Dataverse
./scripts/Test-HitlWorkflowCompliance.ps1 `
  -DataverseUrl "https://yourorg.crm.dynamics.com" `
  -WhatIf
```

### 5. Review Results

```powershell
# Run compliance posture test
./scripts/Test-HitlWorkflowCompliance.ps1 `
  -DataverseUrl "https://yourorg.crm.dynamics.com" `
  -TenantId "<tenant-id>" `
  -Interactive
```

### 6. Configure Scheduled Monitoring

Deploy the Azure Automation runbook for recurring scans:

```powershell
./scripts/Start-HitlValidationRunbook.ps1 `
  -DataverseUrl "https://yourorg.crm.dynamics.com" `
  -AutomationAccountName "fsi-governance-automation" `
  -RunbookName "HitlCheckpointScan" `
  -ScheduleFrequencyHours 24
```

## Configuration

| Environment Variable | Purpose | Default |
|---------------------|---------|---------|
| `fsi_HWG_DataverseUrl` | Target Dataverse organization URL | — |
| `fsi_HWG_TenantId` | Microsoft Entra ID tenant identifier | — |
| `fsi_HWG_ClientId` | App registration client ID | — |
| `fsi_HWG_ScanFrequencyHours` | Hours between scheduled scans | 24 |
| `fsi_HWG_TeamsGroupId` | Teams group for alert notifications | — |
| `fsi_HWG_TeamsChannelId` | Teams channel for alert notifications | — |
| `fsi_HWG_AlertSeverityThreshold` | Minimum severity for Teams alerts | Medium |
| `fsi_HWG_DryRunMode` | Enable dry-run mode (true/false) | true |

Zone policy thresholds are configured in `templates/zone-hitl-policy.json`. See [docs/flow-configuration.md](docs/flow-configuration.md) for Azure Automation setup details.

## Boundary with Existing Solutions

| Solution | Its Role | HWG Boundary |
|----------|----------|--------------|
| [FINRA Supervision Workflow](../finra-supervision-workflow/) | Routes flagged items to supervisory principals and tracks queue activity (post-execution review). | HWG validates that HITL checkpoints exist **within agent flows** before actions execute — it governs in-flow human review presence, not the supervision queue. |
| [Hallucination Tracker](../hallucination-tracker/) | Aggregates feedback and override patterns for quality analytics after execution. | HWG is not a quality analytics solution — it validates checkpoint presence and produces governance evidence for HITL compliance. |
| [Action Confirmation Auditor](../action-confirmation-auditor/) | Validates that agents prompt users for confirmation before executing actions (step-up confirmation dialogs). | HWG validates human **reviewer** checkpoints (RFI / multistage approval) that pause flows for designated reviewers — distinct from end-user confirmation prompts. |
| [Cross-Solution Integration](../cross-solution-integration/) | Normalizes evidence from Tier 2 solutions into the Compliance Dashboard. | HWG contributes HITL checkpoint evidence that Cross-Solution Integration can aggregate into unified compliance reporting. |

## Documentation

| Guide | Description |
|-------|-------------|
| [docs/prerequisites.md](docs/prerequisites.md) | Licensing, roles, and dependency requirements |
| [docs/dataverse-schema.md](docs/dataverse-schema.md) | Table and column reference (auto-generated from schema script) |
| [docs/flow-configuration.md](docs/flow-configuration.md) | Manual build instructions for Power Automate flows |
| [docs/troubleshooting.md](docs/troubleshooting.md) | Common issues and error recovery procedures |

## Microsoft References

- [Request information from humans in the loop](https://learn.microsoft.com/en-us/microsoft-copilot-studio/flows-request-for-information)
- [Human in the loop connector reference](https://learn.microsoft.com/en-us/connectors/advancedapprovals/)
- [Power Platform and Dynamics 365 preview terms](https://www.microsoft.com/business-applications/legal/supp-powerplatform-preview/)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| v1.0.0 | April 2026 | Initial release — HITL checkpoint detection, zone-based policy evaluation, evidence export |

See [CHANGELOG.md](./CHANGELOG.md) for detailed version history.

## License

MIT License — see [LICENSE](../LICENSE)
