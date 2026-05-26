---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P1, P2]
applicable_drivers:
  - ai_governance
  - technology_data
coe_function: govern
---
# Agent Sharing Access Restriction Detector

> **Version:** v2.0.2
> **Status:** Live
> **Validated against framework version:** v1.6.0
> **Last Verified:** 2026-05-25

See [CHANGELOG](./CHANGELOG.md) for version history.

Continuous detection and restriction of agent sharing configurations exceeding zone-based access policies with approval workflows and exception management.

## Overview

The Agent Sharing Access Restriction Detector (ASARD) monitors Power Platform environments for Copilot Studio agents shared with unauthorized security groups or users that violate zone-based governance policies. Where UASD detects broad sharing violations (org-wide, public links, cross-tenant), ASARD validates granular zone-based restrictions by checking that each agent's sharing configuration aligns with approved security group policies for its environment tier.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [1.18 - Application-Level Authorization and RBAC](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.18-application-level-authorization-and-role-based-access-control-rbac/) | Primary — Role-based access control enforcement |
| [2.8 - Access Control and Segregation of Duties](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.8-access-control-and-segregation-of-duties/) | Zone-based sharing policy enforcement |

## Companion Solution

| Solution | Scope | How They Differ |
|----------|-------|-----------------|
| [Unrestricted Agent Sharing Detector (UASD)](../unrestricted-agent-sharing-detector/README.md) | Org-wide sharing, public links, cross-tenant access | UASD detects broad unrestricted sharing; ASARD validates granular zone-based group policies |

## Components

```
agent-sharing-access-restriction-detector/
├── README.md
├── CHANGELOG.md
├── docs/
│   ├── flow-configuration.md                              # Flow build instructions and overview
│   └── prerequisites.md                                   # Licenses, roles, connections, network
└── templates/
    ├── adaptive-card-asard-alert.json                     # Violation alert card
    ├── adaptive-card-asard-remediation-approval.json      # Remediation approval card
    ├── adaptive-card-asard-remediation-result.json        # Remediation result card
    ├── adaptive-card-asard-exception-expiring.json        # Exception expiring warning card
    └── adaptive-card-asard-exception-expired.json         # Exception expired notification card
```

## Scripts

| Script | Purpose |
|--------|---------|
| `scripts/asard_zone_rules.py` | Zone classification rules for environment governance tiers |
| `scripts/create_asard_dataverse_schema.py` | Creates required Dataverse tables and columns |
| `scripts/create_asard_environment_variables.py` | Creates solution environment variables |
| `scripts/create_asard_connection_references.py` | Creates solution connection references |
| `scripts/requirements.txt` | Python dependencies |
| `scripts/governance/Invoke-SharingComplianceScan.ps1` | Main sharing compliance scan engine |
| `scripts/governance/Test-AgentSharingCompliance.ps1` | Compliance assessment orchestrator with summary reporting |
| `scripts/governance/Get-ExpectedSharingPolicy.ps1` | Zone-based sharing policy definitions |
| `scripts/governance/Export-SharingComplianceEvidence.ps1` | Evidence export with SHA-256 integrity hashing |
| `scripts/governance/Test-EvidenceIntegrity.ps1` | Evidence file integrity verification |

## Platform Update Notes

### Managed Environment Agent Sharing Limits (2026-Q2)

Microsoft Learn documents [agent sharing limits](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-sharing-limits#agent-sharing-rules) as Managed Environment controls in the Power Platform admin center. Administrators can configure whether makers can grant **Editor** or **Viewer** assignments, restrict viewer sharing to individuals only, and set a maximum viewer count per agent. Microsoft Learn also notes that **Editor** permissions can only be granted to individual users; security groups are supported for **Viewer** assignments only.

Operational caveats from Microsoft Learn:

- Sharing limits are applied when users attempt new sharing changes; they do not remove users or groups that already had access before the rules were configured.
- Enforcement can take up to one hour after settings are saved.
- Sharing limits apply to agents that require authentication.
- Dataverse for Teams environments have a publish-to-Team exception; limits apply when sharing outside the team bound to the environment.

**Relationship to ASARD:** Managed Environment sharing limits provide the preventive control layer. ASARD provides zone-specific detective controls, validates `bot.accesscontrolpolicy` and `bot.authorizedsecuritygroupids` against approved group policy, manages time-bound exceptions with approval workflows, and generates evidence for review. FSI organizations should configure Managed Environment sharing limits as the primary preventive layer and use ASARD for granular zone-based compliance auditing and exception management.

### M365 Copilot Agent Store (April 2026)

Microsoft has launched the [M365 Copilot Agent Store](https://learn.microsoft.com/en-us/microsoft-365/copilot/copilot-agent-store), enabling tenant-wide deployment of prebuilt, Copilot Studio, and external platform agents. Agent Store deployments introduce a parallel sharing channel that operates outside environment-level controls:

- **Agent Store deployments** are managed via the M365 Admin Center (`Agents > All agents`), not through Power Platform environment sharing settings
- Agents deployed through the Agent Store may be accessible to users who would not have access through environment-level sharing policies
- Zone-based sharing restrictions validated by ASARD should be complemented by Agent Store admin policies to reduce policy bypass risk

> **Note:** ASARD currently validates sharing configurations within Power Platform environments. Agent Store deployment governance is not yet covered by this solution. Organizations should coordinate environment-level sharing policies with M365 Admin Center agent deployment controls.

## Dataverse Tables

| Table | Purpose |
|-------|---------|
| `fsi_agentsharingcompliances` | Detected sharing policy violations with agent identity, zone, and remediation status |
| `fsi_approvedsecuritygrouppolicies` | Approved security group whitelist per zone |
| `fsi_agentsharingcompliances.fsi_exception*` | Time-bound exception records with approval audit trail (columns on compliance table) |
| `fsi_agentsharingcompliances.fsi_remediation*` | Immutable remediation action history (columns on compliance table) |

## Prerequisites

- Microsoft Entra workload identity or app registration with Power Platform admin API, Dataverse Web API, and Microsoft Graph permissions
- Power Platform Admin (or Entra Global Admin)
- Power Platform environment with Dataverse
- Python 3.9+ with `msal`, `requests`, `azure-identity`
- Power Automate Premium license (for approval workflows)

## Documentation

| Document | Description |
|----------|-------------|
| [Flow Configuration Guide](docs/flow-configuration.md) | Overview of both flows, adaptive card templates, and environment variables |
| [Prerequisites](docs/prerequisites.md) | Required licenses, roles, connections, Dataverse tables, and network endpoints |
| [ASARD Deployment Guide](https://judeper.github.io/FSI-AgentGov/playbooks/asard-deployment-guide/) | End-to-end setup (FSI-AgentGov) |
| [Exception Management](https://judeper.github.io/FSI-AgentGov/playbooks/asard-exception-management/) | Exception lifecycle operations (FSI-AgentGov) |
| [Troubleshooting Guide](https://judeper.github.io/FSI-AgentGov/playbooks/asard-troubleshooting-guide/) | Diagnostics and resolution (FSI-AgentGov) |

## Deployment

1. Create Dataverse tables using the schema creation script (see [prerequisites](docs/prerequisites.md))
2. Build the two Power Automate cloud flows following the [flow configuration guide](docs/flow-configuration.md)
3. Configure connection references and environment variables
4. Activate cloud flows
5. Verify deployment using the guides below

See the [deployment guide](https://judeper.github.io/FSI-AgentGov/playbooks/asard-deployment-guide/) in FSI-AgentGov, which covers:

- [Deployment Guide](https://judeper.github.io/FSI-AgentGov/playbooks/asard-deployment-guide/) — End-to-end setup
- [Exception Management](https://judeper.github.io/FSI-AgentGov/playbooks/asard-exception-management/) — Exception lifecycle operations
- [Troubleshooting Guide](https://judeper.github.io/FSI-AgentGov/playbooks/asard-troubleshooting-guide/) — Diagnostics and resolution

## FSI Governance Compliance Checklist

| Control | Description | Implementation Evidence |
|---------|-------------|------------------------|
| [1.18](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.18-application-level-authorization-and-role-based-access-control-rbac/) | Application-Level Authorization and RBAC | Remediation approval workflow — Zone-based approved security group validation via `fsi_approvedsecuritygrouppolicies`; Dataverse bot-table PATCH updates `accesscontrolpolicy` and `authorizedsecuritygroupids` for approved remediation (see [flow configuration](docs/flow-configuration.md)) |
| [2.8](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.8-access-control-and-segregation-of-duties/) | Access Control and Segregation of Duties | Remediation approval workflow — Governance lead approval required before remediation; zone classification determines allowed security groups; Exception review workflow — Time-bound exceptions with audit trail preservation (see [flow configuration](docs/flow-configuration.md)) |

## Known Limitations

- **28-day approval wait limit**: Microsoft Learn notes that an approval flow can wait for 28 days before the flow fails. The sequential approval loop (concurrency=1) with 7-day timeouts means more than four agents can exceed this limit. For environments with more than four non-compliant agents, consider batch approval or a child flow pattern.
- **Sovereign cloud deployment**: The BAP Admin API base URL is configurable via the `fsi_ASARD_BAPAdminAPIBaseUrl` environment variable for administrative calls. Detection and approved remediation use the Dataverse Web API `bots` table in each environment; validate both endpoint families for GCC, GCC-High, or DoD deployments.
- **Rejection cooldown**: After remediation rejection, agents are excluded from re-query for 7 days (matching the default approval timeout) to prevent repeated approval requests to the same approver. Override by manually resetting `fsi_remediationstatus` in Dataverse.
- **Adaptive card templates (remediation)**: `adaptive-card-asard-remediation-approval.json` and `adaptive-card-asard-remediation-result.json` are reference templates for external integrations (e.g., custom Power Apps, third-party dashboards). The remediation approval workflow uses inline Markdown for approval and notification messages — these templates are not loaded by the workflow at runtime.
- **Template URL integrity (exception review)**: The exception review workflow loads adaptive card templates via HTTP GET from a configurable URL (`fsi_ASARD_AdaptiveCardTemplateUrl`). No content hash or signature validation is performed. Ensure the URL points to a trusted, immutable source (e.g., GitHub release tag, Azure Blob Storage with SAS token).
- **Exception query pagination**: The exception review workflow retrieves up to 5,000 records per query (Dataverse maximum per request). Environments with >5,000 active exceptions should use Dataverse views or custom reporting for complete visibility.
- **Per-agent approved groups query (N+1 pattern)**: The remediation workflow queries approved security groups per-agent inside the sequential loop. Agents in the same zone redundantly fetch the same approved groups. Pre-fetching approved groups for all 3 zones before the loop would eliminate redundant Dataverse API calls. This is a performance optimization — correctness is unaffected.
- **Dataverse pagination (remediation)**: The remediation workflow uses `$skip`-based pagination with `@odata.nextLink` absence detection. For deployments with >5,000 non-compliant agents, `$skip` offsets may produce inconsistent results due to server-side cursor resets. Consider reducing the query window or using Dataverse views for large-scale environments.

## License

MIT License — see [LICENSE](../LICENSE)
