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
    └── governance/
        ├── Invoke-SharingAudit.ps1
        ├── Test-AgentSharingCompliance.ps1
        ├── Get-ExpectedSharingPolicy.ps1
        ├── Export-ViolationReport.ps1
        ├── Import-ApprovedSecurityGroups.ps1
        ├── Deploy-DetectionFlow.ps1
        └── Deploy-RemediationFlow.ps1
```

Power Automate flows and Canvas apps are built manually using the instructions in `docs/flow-configuration.md`.

## Prerequisites

- Microsoft 365 E5 or E5 Compliance
- Power Platform environment with Dataverse
- Power Automate Premium license (for cloud flows)
- Power Platform Admin or Entra Global Admin permissions
- The Python setup scripts (`scripts/create_uasd_*.py`) depend on a shared `DataverseClient` module located at `../scripts/shared/dataverse_client.py` (relative to the repository root containing this solution). Ensure the [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions) repository structure is intact, or install the `dataverse_client` module on `PYTHONPATH`.

## Deployment

1. Create Dataverse schema: `python scripts/create_uasd_dataverse_schema.py`
2. Create environment variables: `python scripts/create_uasd_environment_variables.py`
3. Create connection references: `python scripts/create_uasd_connection_references.py`
4. Build flows manually following `docs/flow-configuration.md`
5. Verify deployment using the [deployment guide](https://judeper.github.io/FSI-AgentGov/playbooks/advanced-implementations/unrestricted-agent-sharing-detector/) in FSI-AgentGov

## License

MIT License — see [LICENSE](../LICENSE)
