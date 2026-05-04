# Inactivity Timeout Enforcement

> **Version:** v1.1.1
> **Status:** Completed

Cloud Flow template for daily compliance detection of inactivity timeout settings across Power Platform environments.

## Overview

This solution provides a Power Automate cloud flow that performs daily scans of Power Platform environments to detect non-compliant inactivity timeout configurations. The flow identifies environments where timeout settings do not meet governance zone requirements and generates compliance reports.

> **Note:** PowerShell remediation scripts are maintained separately in the FSI-AgentGov repository and are not included in this solution package. The primary remediation script is [`Set-InactivityTimeout.ps1`](https://github.com/judeper/FSI-AgentGov/blob/main/scripts/governance/Set-InactivityTimeout.ps1) located at `scripts/governance/` in FSI-AgentGov.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [2.22 - Inactivity Timeout Enforcement](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.22-inactivity-timeout-enforcement/) | Primary — Timeout policy compliance detection |
| [1.23 - Session Security](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.23-session-security/) | Session timeout configuration validation |
| [3.7 - Monitoring](https://judeper.github.io/FSI-AgentGov/controls/pillar-3-monitoring/3.7-monitoring/) | Continuous compliance monitoring and alerting |
| [3.8 - Access Monitoring](https://judeper.github.io/FSI-AgentGov/controls/pillar-3-monitoring/3.8-access-monitoring/) | Overly permissive access detection via timeout gaps |

## Components

```
inactivity-timeout-enforcement/
├── README.md
├── CHANGELOG.md
├── docs/
│   ├── dataverse-schema.md       # Auto-generated schema reference
│   ├── delivery-checklist.md     # Pre-deployment verification checklist
│   └── flow-configuration.md    # Step-by-step flow build guide
└── scripts/
    ├── create_ite_dataverse_schema.py
    ├── create_ite_connection_references.py
    ├── create_ite_environment_variables.py
    ├── requirements.txt
    └── governance/
        ├── Invoke-TimeoutComplianceScan.ps1
        ├── Test-TimeoutCompliance.ps1
        ├── Get-ExpectedTimeoutPolicy.ps1
        ├── Export-TimeoutComplianceEvidence.ps1
        └── Test-EvidenceIntegrity.ps1
```

## Documentation

| Document | Description |
|----------|-------------|
| [Flow Configuration](docs/flow-configuration.md) | Step-by-step guide to build the inactivity timeout detection flow |
| [Delivery Checklist](docs/delivery-checklist.md) | Pre-deployment verification checklist |

## Prerequisites

- Power Platform environment with Dataverse
- Power Automate Premium license (for cloud flow)
- Power Platform Admin permissions

## Deployment

1. Follow the step-by-step build instructions in [docs/flow-configuration.md](docs/flow-configuration.md) to create the detection flow in Power Automate designer
2. Configure connection references (see prerequisites)
3. Activate cloud flows
4. Verify deployment using the [Delivery Checklist](docs/delivery-checklist.md) and the control implementation playbooks for [Control 2.22](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.22-inactivity-timeout-enforcement/) in FSI-AgentGov

## Microsoft Learn 2026-Q2 scope notes

- This solution monitors Power Platform environment **Privacy + Security** inactivity timeout settings surfaced through the Business Application Platform (BAP) admin API and Dataverse evidence tables.
- Power Platform **session timeout** is a server-side maximum session length; **inactivity timeout** is a client-side sign-out decision after inactivity. Microsoft Learn notes that Power Apps canvas apps are excluded from the customer engagement app inactivity timeout setting.
- Microsoft Entra Conditional Access sign-in frequency, persistent browser, app-enforced restrictions, Defender for Cloud Apps session controls, and Continuous Access Evaluation (CAE) are complementary identity/session controls. They are not substitutes for the Power Platform environment inactivity timeout setting scanned here.
- Copilot Studio agent inactivity handling should be implemented with agent/topic lifecycle patterns such as the Teams channel inactivity trigger; those agent conversation resets are outside this environment-level scanner.

## Known Limitations

- **Single-page flow environment enumeration:** The documented cloud-flow `List_Environments` action retrieves the first page of results from the BAP Admin API without following `nextLink` pagination. Tenants with environments exceeding the default API page size (~500) should extend the flow with a Do Until loop to accumulate all pages before processing. The standalone PowerShell scanner follows BAP pagination.

## License

MIT License — see [LICENSE](../LICENSE)
