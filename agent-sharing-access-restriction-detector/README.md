# Agent Sharing Access Restriction Detector

> **Version:** v1.0.1
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
| `fsi_agentsharingcompliances` | Detected sharing policy violations with agent identity, zone, and remediation status |
| `fsi_approvedsecuritygrouppolicies` | Approved security group whitelist per zone |
| `fsi_agentsharingcompliances.fsi_exception_*` | Time-bound exception records with approval audit trail (columns on compliance table) |
| `fsi_agentsharingcompliances.fsi_remediation_*` | Immutable remediation action history (columns on compliance table) |

## Prerequisites

- Microsoft Entra ID app registration with BAP Admin API and Microsoft Graph permissions
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

## FSI Governance Compliance Checklist

| Control | Description | Implementation Evidence |
|---------|-------------|------------------------|
| [1.18](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.18-application-level-authorization-and-role-based-access-control-rbac/) | Application-Level Authorization and RBAC | `asard-remediation-approval-workflow.json` — Zone-based approved security group enforcement via `fsi_approvedsecuritygrouppolicies` table; BAP Admin API PATCH to replace non-compliant sharing principals |
| [2.8](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.8-access-control-and-segregation-of-duties/) | Access Control and Segregation of Duties | `asard-remediation-approval-workflow.json` — Governance lead approval required before remediation; zone classification determines allowed security groups; `asard-exception-review-workflow.json` — Time-bound exceptions with audit trail preservation |

## Known Limitations

- **30-day runtime limit**: The sequential approval loop (concurrency=1) with 7-day timeouts means >4 agents will exceed Power Automate's 30-day maximum runtime limit, silently dropping later agents. For environments with >4 non-compliant agents, consider batch approval or a child flow pattern.
- **Sovereign cloud deployment**: The BAP Admin API base URL is configurable via the `fsi_ASARD_BAPAdminAPIBaseUrl` environment variable. Override for GCC, GCC-High, or DoD deployments.
- **Rejection cooldown**: After remediation rejection, agents are excluded from re-query for 7 days (matching the default approval timeout) to prevent repeated approval requests to the same approver. Override by manually resetting `fsi_approval_status` in Dataverse.
- **Adaptive card templates (remediation)**: `adaptive-card-asard-remediation-approval.json` and `adaptive-card-asard-remediation-result.json` are reference templates for external integrations (e.g., custom Power Apps, third-party dashboards). The remediation approval workflow uses inline Markdown for approval and notification messages — these templates are not loaded by the workflow at runtime.
- **Template URL integrity (exception review)**: The exception review workflow loads adaptive card templates via HTTP GET from a configurable URL (`fsi_ASARD_AdaptiveCardTemplateUrl`). No content hash or signature validation is performed. Ensure the URL points to a trusted, immutable source (e.g., GitHub release tag, Azure Blob Storage with SAS token).
- **Exception query pagination**: The exception review workflow retrieves up to 5,000 records per query (Dataverse maximum per request). Environments with >5,000 active exceptions should use Dataverse views or custom reporting for complete visibility.
- **Per-agent approved groups query (N+1 pattern)**: The remediation workflow queries approved security groups per-agent inside the sequential loop. Agents in the same zone redundantly fetch the same approved groups. Pre-fetching approved groups for all 3 zones before the loop would eliminate redundant Dataverse API calls. This is a performance optimization — correctness is unaffected.
- **Dataverse pagination (remediation)**: The remediation workflow uses `$skip`-based pagination with `@odata.nextLink` absence detection. For deployments with >5,000 non-compliant agents, `$skip` offsets may produce inconsistent results due to server-side cursor resets. Consider reducing the query window or using Dataverse views for large-scale environments.

## License

MIT License — see [LICENSE](../LICENSE)
