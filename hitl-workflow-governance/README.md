---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P4, P5, P6]
applicable_drivers:
  - ai_governance
  - organization_culture
coe_function: govern
---
# HITL Workflow Governance

> **Version:** v1.1.2
> **Status:** Live
> **Validated against framework version:** v1.6.0
> **Upstream Microsoft dependency:** Mixed — The Request for Information action reached general availability on Jan 30, 2026 (Power Platform release plan), though the Human in the Loop connector reference still labels it preview; Run a Multistage Approval remains preview in Microsoft Learn. Review the Power Platform preview terms before using any preview action with regulated data.

Validates that Copilot Studio agent flows include required human-in-the-loop (HITL) checkpoints per zone governance policy, using Microsoft's **Request for Information** and **Run a Multistage Approval** actions from the `shared_advancedapprovals` connector.

## Overview

The HITL Workflow Governance solution (HWG) scans Power Platform environments for Copilot Studio agents and validates that their flows include required human review checkpoints. In regulated financial services environments, agent actions that modify data, initiate external communication, or process customer financial information may require human approval before execution. HWG identifies agents missing required HITL steps, classifies violations by severity based on zone and action type, tracks evidence of human review, and exports compliance evidence for regulatory examination.

Microsoft introduced the **Request for Information** (RFI) action for Copilot Studio agent flows in public preview on July 31, 2025; per the Power Platform release plan it reached general availability on January 30, 2026, although the Human in the Loop connector reference page still labels the action preview. The `shared_advancedapprovals` Human in the Loop connector also provides **Run a Multistage Approval** (`StartAndWaitForAnApprovalProcess`) for structured approval workflows, which remains labeled preview in Microsoft Learn. Organizations should review the [Power Platform preview terms](https://www.microsoft.com/business-applications/legal/supp-powerplatform-preview/) before using any preview action with regulated data.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [2.12 - Supervision and Oversight (FINRA Rule 3110)](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.12-supervision-and-oversight-finra-rule-3110/) | Primary — Human review checkpoint validation for supervision evidence |
| [2.17 - Multi-Agent Orchestration Limits](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.17-multi-agent-orchestration-limits/) | Primary — HITL checkpoints within multi-step and multi-agent workflow patterns |
| [1.10 - Communication Compliance](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.10-communication-compliance-monitoring/) | Supporting — Reviewer identity, decision context, and timestamp retention for output review |
| [2.1 - Managed Environments](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.1-managed-environments/) | Dependency — Zone classification source |
| [3.8 - Copilot Hub](https://judeper.github.io/FSI-AgentGov/controls/pillar-3-reporting/3.8-copilot-hub-and-governance-dashboard/) | Downstream — Evidence export for governance dashboard |

## Regulatory Context

| Regulation | Relevance |
|------------|-----------|
| **FINRA Rule 3110** | Supervisory procedures requiring human review of AI agent outputs before client-facing actions |
| **FINRA Rule 4511(a)** | Books and records requirements for supervision evidence, including documentation that human review checkpoints were invoked |
| **SEC Rule 17a-3/4** | Supervisory review documentation and record preservation for human-in-the-loop decision records |
| **SOX Section 302/404** | Internal control documentation demonstrating that material financial workflows include human review steps |
| **GLBA Section 501(b)** | Safeguards for customer financial information requiring human oversight of agent actions that access or transmit protected data |

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

- **HITL Checkpoint Detection** — Scans agent flow definitions for Request for Information and Run a Multistage Approval actions from the `shared_advancedapprovals` connector
- **Zone-Based Policy Evaluation** — Applies zone-specific HITL requirements using ELM zone classification
- **Reviewer Assignment Validation** — Verifies that HITL steps include designated reviewer configuration
- **Input Configuration Verification** — Validates that RFI actions include required parameters (`title`, Outlook `message`, `assignedTo`) and supported input definitions
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
    ├── deploy.py                           # Orchestrator (schema + env vars + connections)
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
    │   ├── Get-HWGValidationResults.ps1    # Evidence query helper
    │   ├── Get-ZoneClassification.ps1      # Zone lookup helper
    │   ├── Get-ExpectedHitlPolicy.ps1      # HITL policy reference
    │   ├── Test-ParameterValidation.ps1    # Parameter validators
    │   └── Connect-EnvironmentDataverse.ps1 # Per-env Dataverse auth

templates/
├── adaptive-card-hitl-alert.json       # Teams alert template (runbook summary)
└── hitl-zone-policy.json               # Reference zone-policy JSON (runtime policy is in Get-ExpectedHitlPolicy.ps1)
```

Power Automate flows are built manually using the instructions in [docs/flow-configuration.md](docs/flow-configuration.md).

## Prerequisites

- Microsoft 365 E5 or E5 Compliance
- Power Platform environment with Dataverse
- Power Automate licensing appropriate for Dataverse/Azure Automation connectors; Approvals, Human in the Loop, Teams, and Office 365 Outlook are documented as Standard connectors
- Power Platform Admin or Entra Global Admin permissions
- Python 3.9+ and PowerShell 7+ for setup and governance scripts
- The Python setup scripts depend on a shared `DataverseClient` module located at `../scripts/shared/dataverse_client.py` (relative to the repository root). Ensure the [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions) repository structure is intact, or install the `dataverse_client` module on `PYTHONPATH`.

See [docs/prerequisites.md](docs/prerequisites.md) for detailed requirements.

## Quick Start

### 1. Configure Authentication

For production automation, prefer managed identity, workload identity federation, or certificate-based authentication. Register an app in Microsoft Entra ID only when a service principal is required, then grant:
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
python scripts/deploy.py \
  --dataverse-url https://yourorg.crm.dynamics.com \
  --tenant-id <tenant-id> \
  --interactive \
  --dry-run

# Full deployment
python scripts/deploy.py \
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

Import `Start-HitlValidationRunbook.ps1` as the Azure Automation runbook entrypoint and schedule it with certificate-based authentication parameters:

```powershell
./scripts/Start-HitlValidationRunbook.ps1 `
  -TenantId "<tenant-id>" `
  -ClientId "<app-id>" `
  -CertificateThumbprint "<certificate-thumbprint>" `
  -DataverseUrl "https://yourorg.crm.dynamics.com"
```

## Configuration

The deploy script (`scripts/create_hwg_environment_variables.py`) provisions these Dataverse-backed environment variables (read by `Start-HitlValidationRunbook.ps1` and Power Automate flows):

| Environment Variable | Purpose | Default |
|---------------------|---------|---------|
| `fsi_HWG_GracePeriodHours` | Hours before new agents must have HITL checkpoints | 72 |
| `fsi_HWG_EnableDataversePersistence` | Persist scan results to Dataverse (`true`/`false`) | true |
| `fsi_HWG_DefaultReviewSlaHours` | Default reviewer response SLA in hours | 24 |
| `fsi_HWG_Zone3SampleRate` | Percent of Zone 3 actions requiring HITL | 100 |
| `fsi_HWG_Zone2SampleRate` | Percent of Zone 2 actions sampled for HITL | 10 |
| `fsi_HWG_NotificationWebhookUrl` | Microsoft Teams webhook URL for alerts | — |
| `fsi_HWG_IncludeSandbox` | Include Sandbox environments in scans (`true`/`false`) | false |
| `fsi_HWG_IncludeDrafts` | Include unpublished draft flows in scans (`true`/`false`) | false |

> Connection details (Dataverse URL, tenant, client, certificate or managed identity) are supplied through the runbook parameters and Automation account configuration, not as Dataverse environment variables. For dry runs, execute `Test-HitlWorkflowCompliance.ps1 -WhatIf` outside the scheduled runbook.

Zone policy thresholds are configured in `scripts/private/Get-ExpectedHitlPolicy.ps1`. See [docs/flow-configuration.md](docs/flow-configuration.md) for Azure Automation setup details.

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
- [Use multistage approvals in agent flows](https://learn.microsoft.com/en-us/microsoft-copilot-studio/flows-advanced-approvals)
- [Power Automate approvals connector](https://learn.microsoft.com/en-us/connectors/approvals/)
- [Copilot Studio audit logging in Microsoft Purview](https://learn.microsoft.com/en-us/microsoft-copilot-studio/admin-logging-copilot-studio)
- [Universal Actions for Adaptive Cards in Teams](https://learn.microsoft.com/en-us/microsoftteams/platform/task-modules-and-cards/cards/Universal-actions-for-adaptive-cards/Work-with-Universal-Actions-for-Adaptive-Cards)
- [Secretless authentication for Azure resources](https://learn.microsoft.com/en-us/azure/developer/intro/passwordless-overview)
- [Power Platform and Dynamics 365 preview terms](https://www.microsoft.com/business-applications/legal/supp-powerplatform-preview/)

## Version History

| Version | Date | Changes |
|---------|------|---------|
| v1.1.2 | May 2026 | Council-review remediation — C-1/C-2 phantom-column fixes, M-1 zone policy alignment, M-2 migration to shared DataverseClient, M-3 ActionCategory cleanup, M-4 flow-level config doc clarification, M-5 botcomponents lookup alignment, m-6 MSAL.PS → Az.Accounts |
| v1.1.1 | May 2026 | Microsoft Learn 2026-Q2 refresh — current HITL connector operation IDs, secretless auth guidance, Teams card version, exception approval schema/docs |
| v1.1.0 | April 2026 | Runtime reliability and Dataverse schema alignment fixes |
| v1.0.0 | April 2026 | Initial release — HITL checkpoint detection, zone-based policy evaluation, evidence export |

See [CHANGELOG.md](./CHANGELOG.md) for detailed version history.

## License

MIT License — see [LICENSE](../LICENSE)
