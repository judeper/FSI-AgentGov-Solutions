# Inactivity Timeout Enforcement

> **Version:** v1.0.2
> **Status:** Completed

Cloud Flow template for daily compliance detection of inactivity timeout settings across Power Platform environments.

## Overview

This solution provides a Power Automate cloud flow that performs daily scans of Power Platform environments to detect non-compliant inactivity timeout configurations. The flow identifies environments where timeout settings do not meet governance zone requirements and generates compliance reports.

> **Note:** PowerShell remediation scripts are maintained separately in the FSI-AgentGov repository and are not included in this solution package. The primary remediation script is [`Set-InactivityTimeout.ps1`](https://github.com/judeper/FSI-AgentGov/blob/main/scripts/governance/Set-InactivityTimeout.ps1) located at `scripts/governance/` in FSI-AgentGov.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [2.22 - Inactivity Timeout Enforcement](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.22-inactivity-timeout-enforcement/) | Primary — Timeout policy compliance detection |

## Components

```
inactivity-timeout-enforcement/
├── README.md
├── CHANGELOG.md
├── DELIVERY-CHECKLIST.md
├── SOLUTION-DOCUMENTATION.md
└── src/
    └── detect-inactivity-timeout-noncompliance.json  # Daily compliance detection flow
```

## Prerequisites

- Power Platform environment with Dataverse
- Power Automate Premium license (for cloud flow)
- Power Platform Admin permissions

## Deployment

1. Import the flow JSON file (`src/detect-inactivity-timeout-noncompliance.json`) into your Power Platform environment
2. Configure connection references (see prerequisites)
3. Activate cloud flows
4. Verify deployment using the control implementation playbooks for [Control 2.22](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.22-inactivity-timeout-enforcement/) in FSI-AgentGov

## Known Limitations

- **Single-page environment enumeration:** The `List_Environments` action retrieves the first page of results from the BAP Admin API without following `nextLink` pagination. Tenants with environments exceeding the default API page size (~500) should extend the flow with a Do Until loop to accumulate all pages before processing.

## License

MIT License — see [LICENSE](../LICENSE)
