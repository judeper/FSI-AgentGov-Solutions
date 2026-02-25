# Agent Sharing Access Restriction Detector

> **Version:** v1.0.0
> **Status:** Completed

Continuous detection and restriction of agent sharing configurations exceeding zone-based access policies with approval workflows and exception management.

## Overview

The Agent Sharing Access Restriction Detector (ASARD) monitors Power Platform environments for Copilot Studio agents shared with unauthorized security groups or users that violate zone-based governance policies. Where UASD detects broad sharing violations (org-wide, public links, cross-tenant), ASARD enforces granular zone-based restrictions — validating that each agent's sharing configuration aligns with approved security group policies for its environment tier.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [1.18 - Application-Level Authorization and RBAC](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.18-application-level-authorization-and-role-based-access-control-rbac/) | Primary — Role-based access control enforcement |
| [2.8 - Access Control and Segregation of Duties](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.8-access-control-and-segregation-of-duties/) | Zone-based sharing policy enforcement |

## Companion Solution

| Solution | Scope | How They Differ |
|----------|-------|-----------------|
| [Unrestricted Agent Sharing Detector (UASD)](../unrestricted-agent-sharing-detector/README.md) | Org-wide sharing, public links, cross-tenant access | UASD detects broad unrestricted sharing; ASARD enforces granular zone-based group policies |

## Components

```
agent-sharing-access-restriction-detector/
├── README.md
├── CHANGELOG.md
└── src/
    ├── asard-remediation-approval-workflow.json       # Remediation approval flow
    ├── asard-exception-review-workflow.json            # Exception review and expiration flow
    ├── adaptive-card-asard-alert.json                  # Violation alert card (standalone — not loaded by workflows)
    ├── adaptive-card-asard-remediation-approval.json   # Remediation approval card (standalone — not loaded by workflows)
    ├── adaptive-card-asard-remediation-result.json     # Remediation result card (standalone — not loaded by workflows)
    ├── adaptive-card-asard-exception-expiring.json     # Exception expiring warning card (loaded by exception review workflow)
    └── adaptive-card-asard-exception-expired.json      # Exception expired notification card (loaded by exception review workflow)
```

> **Note:** Three adaptive card templates (`alert`, `remediation-approval`, `remediation-result`) are standalone templates provided for external consumption or future workflow integration. They are not currently loaded by the solution workflows. The remediation workflow uses inline markdown via `PostMessageToConversation` rather than adaptive card templates. Only the exception expiring and expired cards are actively loaded and used by the exception review workflow.

> **Template Note:** `adaptive-card-asard-remediation-result.json` is a pre-parse template that contains unquoted `{{variable}}` boolean placeholders for Adaptive Cards `isVisible` conditional visibility. This is the correct and intentional template injection pattern, but the file will not pass JSON validation until variables are substituted at runtime.

## Supporting Scripts (FSI-AgentGov)

| Script | Location | Purpose |
|--------|----------|---------|
| Detection engine | `scripts/detect_agent_sharing_violations.py` | Enumerates agents and evaluates sharing against approved groups |
| Remediation engine | `scripts/remediate_agent_sharing.py` | Applies sharing policy corrections |
| Zone classification | `scripts/asard_zone_rules.py` | Classifies environments into governance zones |
| Dataverse schema | `scripts/create_asard_dataverse_schema.py` | Creates required Dataverse tables |
| BAP Admin client | `scripts/bap_admin_client.py` | Power Platform API client for agent enumeration |

## Dataverse Tables

| Table | Purpose |
|-------|---------|
| `fsi_agentsharingcompliances` | Agent sharing compliance records with violation details, exception fields, and remediation status |
| `fsi_approvedsecuritygrouppolicies` | Approved security group whitelist per zone |

## Prerequisites

- Microsoft Entra ID app registration with BAP Admin API and Microsoft Graph permissions
- Power Platform admin role (or Global Admin)
- Power Platform environment with Dataverse
- Python 3.9+ with `msal`, `requests`, `azure-identity`
- Power Automate Premium license (for approval workflows)
- Three connection references configured in the solution:
  - **Dataverse** (`shared_commondataserviceforapps` / `fsi_cr_dataverse_asard`)
  - **Microsoft Teams** (`shared_teams` / `fsi_cr_teams_asard`)
  - **Approvals** (`shared_approvals` / `fsi_cr_approvals_asard`)
- Six environment variables configured across the workflows:

  | Variable | Used By | Description |
  |----------|---------|-------------|
  | `fsi_ASARD_ApprovalEmail` | Remediation workflow | Email address for sending approval requests |
  | `fsi_ASARD_TeamsChannelId` | Both workflows | Teams channel ID for governance notifications |
  | `fsi_ASARD_ApprovalTimeoutDays` | Remediation workflow | Number of days before unanswered approvals auto-reject |
  | `fsi_ASARD_AdaptiveCardTemplateUrl` | Exception review workflow | URL for adaptive card templates used in notifications |
  | `fsi_ASARD_AdaptiveCardTemplateToken` | Exception review workflow | Optional bearer token for authenticated access to adaptive card template URLs (leave empty for public URLs) |
  | `fsi_ASARD_PlaybookUrl` | Exception review workflow | URL to the ASARD playbook/runbook for remediation guidance |

## Deployment

1. Import the solution ZIP into your Power Platform environment
2. Configure connection references (see prerequisites)
3. Activate cloud flows
4. Verify deployment using the guides below

See the [deployment guide](https://judeper.github.io/FSI-AgentGov/playbooks/asard-deployment-guide/) in FSI-AgentGov, which covers:

- [Deployment Guide](https://judeper.github.io/FSI-AgentGov/playbooks/asard-deployment-guide/) — End-to-end setup
- [Exception Management](https://judeper.github.io/FSI-AgentGov/playbooks/asard-exception-management/) — Exception lifecycle operations
- [Troubleshooting Guide](https://judeper.github.io/FSI-AgentGov/playbooks/asard-troubleshooting-guide/) — Diagnostics and resolution

## License

MIT License — see [LICENSE](../LICENSE)
