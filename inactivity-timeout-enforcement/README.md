# Inactivity Timeout Enforcement

> **Version:** v1.0.0
> **Status:** Completed

Cloud Flow templatefor daily compliance detection of inactivity timeout settings across Power Platform environments.

## Overview

This solution provides a Power Automate cloud flow that performs daily scans of Power Platform environments to detect non-compliant inactivity timeout configurations. The flow identifies environments where timeout settings do not meet governance zone requirements and generates compliance reports.

> **Note:** PowerShell remediation scripts remain in FSI-AgentGov under `scripts/governance/`.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [2.22 - Inactivity Timeout Enforcement](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.22-inactivity-timeout-enforcement/) | Primary — Timeout policy compliance detection |

## Components

```
inactivity-timeout-enforcement/
├── README.md
├── CHANGELOG.md
└── src/
    └── detect-inactivity-timeout-noncompliance.json  # Daily compliance detection flow
```

## Prerequisites

- Power Platform environment with Dataverse
- Power Automate Premium license (for cloud flow)
- Power Platform Admin permissions

## Deployment

1. Import the solution ZIP into your Power Platform environment
2. Configure connection references (see prerequisites)
3. Activate cloud flows
4. Verify deployment using the control implementation playbooks for [Control 2.22](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.22-inactivity-timeout-enforcement/) in FSI-AgentGov

## License

MIT License — see [LICENSE](../LICENSE)
