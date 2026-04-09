# Unrestricted Agent Sharing Detector

> **Version:** v1.0.2
> **Status:** Completed

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
- The Python setup scripts (`scripts/create_uasd_*.py`) depend on a shared `DataverseClient` module located at `../scripts/shared/dataverse_client.py` (relative to the repository root containing this solution). Ensure the [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions) repository structure is intact, or install the `dataverse_client` module on `PYTHONPATH`.

## Platform Update Notes

### Native Agent Sharing Rules (GA May 2025)

Microsoft introduced native admin controls in the Power Platform admin center to [block and limit sharing for Copilot Studio agents](https://learn.microsoft.com/en-us/power-platform/admin/managed-environment-sharing-limits#agent-sharing-rules-preview). These controls allow administrators to:

- Allow or block makers from sharing agents with individuals as editors
- Allow or block makers from sharing agents with viewers (individuals and security groups)
- Set numerical limits on how many viewers an agent can be shared with
- Apply rules at the managed environment level or via environment groups

**Relationship to UASD:** The native sharing rules provide **preventive controls** — they block sharing at the platform level before it occurs. UASD provides **detective and corrective controls** — it audits existing sharing configurations, detects violations that predate native rule deployment, manages time-bound exceptions, and generates compliance evidence for regulatory examinations. FSI organizations should deploy the native sharing rules as the primary enforcement layer and use UASD for ongoing audit, evidence collection, and exception management.

### M365 Copilot Agent Store (April 2026)

Microsoft has launched the [M365 Copilot Agent Store](https://learn.microsoft.com/en-us/microsoft-365/copilot/copilot-agent-store), enabling tenant-wide deployment of prebuilt, Copilot Studio, and external platform agents. Agent Store deployments may bypass environment-level sharing controls, creating additional governance considerations:

- **Prebuilt agents** deployed from the Agent Store are available to assigned users without going through environment-level sharing configuration
- **Admin controls** in the M365 Admin Center (`Agents > All agents`) allow admins to assign, block, or restrict agent access — these controls operate independently of Power Platform environment sharing settings
- Organizations should verify that Agent Store deployment policies align with zone-based sharing restrictions enforced by this solution

> **Note:** UASD currently detects sharing violations within Power Platform environments. Agent Store deployment visibility is not yet covered. Organizations should review Agent Store admin controls alongside environment-level sharing governance.

## Deployment

1. Create Dataverse schema: `python scripts/create_uasd_dataverse_schema.py`
2. Create environment variables: `python scripts/create_uasd_environment_variables.py`
3. Create connection references: `python scripts/create_uasd_connection_references.py`
4. Build flows manually following `docs/flow-configuration.md`
5. Verify deployment using the [deployment guide](https://judeper.github.io/FSI-AgentGov/playbooks/advanced-implementations/unrestricted-agent-sharing-detector/) in FSI-AgentGov

## License

MIT License — see [LICENSE](../LICENSE)
