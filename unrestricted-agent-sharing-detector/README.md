---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P1, P5]
applicable_drivers:
  - ai_governance
  - technology_data
coe_function: optimize
---
# Unrestricted Agent Sharing Detector

> **Version:** v2.0.1
> **Status:** Live
> **Validated against framework version:** v1.6.0

Continuous detection of overly permissive agent sharing configurations with automated remediation and exception management.

## Overview

The Unrestricted Agent Sharing Detector (UASD) monitors Power Platform environments for agents published with unrestricted sharing settings that violate governance zone requirements. When violations are detected, the solution triggers automated remediation flows and supports exception approval workflows for legitimate business cases.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [1.1 - Restrict Agent Publishing](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.1-restrict-agent-publishing-by-authorization/) | Primary — Publishing authorization enforcement |
| [3.8 - Copilot Hub](https://judeper.github.io/FSI-AgentGov/controls/pillar-3-reporting/3.8-copilot-hub-and-governance-dashboard/) | Agent sharing visibility and governance dashboard |

## Components

```
unrestricted-agent-sharing-detector/
├── README.md
├── CHANGELOG.md
├── SOLUTION-DOCUMENTATION.md
├── docs/
│   ├── dataverse-schema.md          # Auto-generated schema reference
│   └── flow-configuration.md        # Manual build instructions for flows
└── scripts/
    ├── create_uasd_dataverse_schema.py
    ├── create_uasd_environment_variables.py
    ├── create_uasd_connection_references.py
    ├── requirements.txt
    ├── uasd_client.py               # Deprecated stub (v1.0.1) — raises ImportError, use shared DataverseClient
    └── governance/
        ├── Invoke-SharingAudit.ps1
        ├── Test-AgentSharingCompliance.ps1
        ├── Get-ExpectedSharingPolicy.ps1
        ├── Export-ViolationReport.ps1
        ├── Import-ApprovedSecurityGroups.ps1
        ├── Deploy-DetectionFlow.ps1
        ├── Deploy-RemediationFlow.ps1
        ├── Deploy-ExceptionApprovalFlow.ps1
        └── Deploy-ExpirationMonitorFlow.ps1
```

Power Automate flows and Canvas apps are built manually using the instructions in `docs/flow-configuration.md`.

## Prerequisites

- Microsoft 365 E5 or E5 Compliance
- Power Platform environment with Dataverse
- Power Automate Premium license (for cloud flows)
- Power Platform Admin or Entra Global Admin permissions
- Dataverse System Administrator role for schema deployment and agent-sharing remediation
- Microsoft Entra ID authentication configured for agents whose chat access must be scoped to users or groups
- The Python setup scripts (`scripts/create_uasd_*.py`) depend on a shared `DataverseClient` module located at `../scripts/shared/dataverse_client.py` (relative to the repository root containing this solution). Ensure the [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions) repository structure is intact, or install the `dataverse_client` module on `PYTHONPATH`.

## Microsoft Learn Alignment (2026-Q2)

- Copilot Studio chat sharing currently supports individual users, security groups, or **Everyone in the organization**. Scoped chat sharing requires Microsoft Entra ID authentication and **Require users to sign in**.
- The detector uses the Dataverse `bot` table as the implementation source of truth: `accesscontrolpolicy` (`0` = Any, `1` = Copilot readers, `2` = Group membership, `3` = Any multi-tenant), `authorizedsecuritygroupids`, `authenticationmode`, and `authenticationtrigger`.
- Automated remediation follows an audit-then-act pattern: capture the prior sharing configuration in evidence, require approved security groups, patch both `accesscontrolpolicy` and `authorizedsecuritygroupids`, and leave a rollback trail.
- For scheduled runbooks, use Azure Automation managed identity or workload identity first. Client-secret setup paths in Python scripts are retained only as legacy development fallbacks.
- Copilot Studio agent identities are Microsoft-managed Entra Agent IDs or legacy app registrations. Do not modify or reuse those credentials for this solution's automation.

## Platform Update Notes

### Native Agent Sharing Rules (GA May 2025)

Microsoft introduced native admin controls in the Power Platform admin center to [block and limit sharing for Copilot Studio agents](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-sharing-limits#agent-sharing-rules-preview). These controls allow administrators to:

- Allow or block makers from sharing agents with individuals as editors
- Allow or block makers from sharing agents with viewers (individuals and security groups)
- Set numerical limits on how many viewers an agent can be shared with
- Apply rules at the managed environment level or via environment groups

**Relationship to UASD:** The native sharing rules provide **preventive controls** — they block sharing at the platform level before it occurs. UASD provides **detective and corrective controls** — it audits existing sharing configurations, detects violations that predate native rule deployment, manages time-bound exceptions, and generates compliance evidence for regulatory examinations. FSI organizations should deploy the native sharing rules as the primary preventive layer and use UASD for ongoing audit, evidence collection, and exception management.

### Microsoft 365 Copilot Agent Store and Package Management API (2026-Q2)

Microsoft has launched the Microsoft 365 Copilot Agent Store and the [Agent and app Package Management API preview](https://learn.microsoft.com/en-us/microsoft-365/copilot/extensibility/api/admin-settings/package/overview), enabling tenant-wide inventory and management of Microsoft 365 apps and agents. Agent Store deployments may operate outside Power Platform environment sharing settings, creating additional governance considerations:

- **Prebuilt agents** deployed from the Agent Store are available to assigned users without going through environment-level sharing configuration
- **Admin controls** in the Microsoft 365 admin center (`Agents > All agents`) allow admins to assign, block, or restrict agent access — these controls operate independently of Power Platform environment sharing settings
- Organizations should verify that Agent Store deployment policies align with zone-based sharing restrictions monitored and remediated by this solution

> **Note:** UASD currently detects sharing violations within Power Platform environments. Agent Store and Package Management API inventory is a recommended future extension, especially for agents outside Copilot Studio environments.

## Deployment

1. Create Dataverse schema: `python scripts/create_uasd_dataverse_schema.py`
2. Create environment variables: `python scripts/create_uasd_environment_variables.py`
3. Create connection references: `python scripts/create_uasd_connection_references.py`
4. Build flows manually following `docs/flow-configuration.md`
5. Verify deployment using the [deployment guide](https://judeper.github.io/FSI-AgentGov/playbooks/advanced-implementations/unrestricted-agent-sharing-detector/) in FSI-AgentGov

## License

MIT License — see [LICENSE](../LICENSE)
