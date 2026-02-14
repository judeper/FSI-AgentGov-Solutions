# Unrestricted Agent Sharing Detector

> **Version:** v1.0.0

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
└── src/
    ├── uasd-detector-scan-agents.json            # Detector scan flow
    ├── uasd-remediation-apply-sharing-policy.json # Automated remediation flow
    ├── uasd-exception-approval-workflow.json      # Exception approval workflow
    ├── uasd-exception-manager-app.json            # Exception manager app
    └── adaptive-card-uasd-alert.json              # Teams adaptive card alert
```

## Prerequisites

- Microsoft 365 E5 or E5 Compliance
- Power Platform environment with Dataverse
- Power Automate Premium license (for cloud flows)
- Power Platform Admin or Entra Global Admin permissions

## Deployment

1. Import the solution ZIP into your Power Platform environment
2. Configure connection references (see prerequisites)
3. Activate cloud flows
4. Verify deployment using the [deployment guide](https://judeper.github.io/FSI-AgentGov/playbooks/advanced-implementations/unrestricted-agent-sharing-detector/) in FSI-AgentGov

## License

MIT License — see [LICENSE](../LICENSE)
