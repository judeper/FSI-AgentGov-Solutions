# Agent Sharing Access Restriction Detector

> **Version:** v1.0.0

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
    ├── adaptive-card-asard-alert.json                  # Violation alert card
    ├── adaptive-card-asard-remediation-approval.json   # Remediation approval card
    ├── adaptive-card-asard-remediation-result.json     # Remediation result card
    ├── adaptive-card-asard-exception-expiring.json     # Exception expiring warning card
    └── adaptive-card-asard-exception-expired.json      # Exception expired notification card
```

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
| `gov_asardsharingviolation` | Detected sharing policy violations with agent identity, zone, and remediation status |
| `gov_asardsecuritygrouppolicy` | Approved security group whitelist per zone |
| `gov_asardexception` | Time-bound exception records with approval audit trail |
| `gov_asardremediationlog` | Immutable remediation action history |

## Prerequisites

- Azure AD app registration with BAP Admin API and Microsoft Graph permissions
- Power Platform admin role (or Global Admin)
- Power Platform environment with Dataverse
- Python 3.9+ with `msal`, `requests`, `azure-identity`
- Power Automate Premium license (for approval workflows)

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
