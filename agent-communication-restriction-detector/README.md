---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P6]
applicable_drivers:
  - ai_governance
  - technology_data
coe_function: govern
---
# Agent Communication Restriction Detector

> **Version:** v1.2.1
> **Status:** Live
> **Validated against framework version:** v1.6.0
> **Last Verified:** 2026-05-25

Detects unauthorized agent-to-agent communication patterns, zone boundary violations, cross-tenant communication, and maker/checker violations in Copilot Studio multi-agent orchestration.

## Overview

The Agent Communication Restriction Detector (ACRD) validates that Copilot Studio multi-agent orchestration complies with organization-specific communication policies. It detects unauthorized agent-to-agent communication patterns, zone boundary violations, cross-environment communication, cross-tenant communication, and maker/checker violations across Power Platform environments.

Unlike solutions that monitor individual agent configurations, ACRD audits the communication topology itself -- which agents are permitted to invoke other agents, whether those invocations cross zone or environment boundaries, and whether maker/checker separation requirements are met for skill registrations.

## Zone Requirements

Each governance zone defines which agent-to-agent communication patterns are permitted and under what conditions:

| Pattern | Zone 3 | Zone 2 | Zone 1 |
|---------|--------|--------|--------|
| Same-zone, same-env | Route required | Route required | Advisory |
| Cross-zone (higher to lower) | Blocked unless approved | Warning + approval | Advisory |
| Cross-zone (lower to higher) | Blocked | Blocked unless approved | Warning |
| Cross-environment | Blocked unless explicit | Requires approval | Advisory |
| Cross-tenant | Blocked (Critical) | Blocked (Critical) | Blocked (High) |

### Violation Severity Matrix

| Violation | Zone 1 | Zone 2 | Zone 3 |
|-----------|--------|--------|--------|
| Zone Boundary Violation | Warning | High | Critical |
| Cross-Tenant Communication | High | Critical | Critical |
| Cross-Environment Unapproved | Warning | High | Critical |
| Maker/Checker Violation | Warning | High | Critical |

## Features

| Feature | Description |
|---------|-------------|
| **Per-Agent Skill Scanning** | Scans each Copilot Studio agent's registered skills and connected-agent schema references individually |
| **Zone-to-Zone Route Validation** | Validates agent communication routes against zone-specific governance policies |
| **Cross-Environment Detection** | Detects agent-to-agent communication that crosses Power Platform environment boundaries |
| **Maker/Checker Enforcement** | Validates that skill registrations follow maker/checker separation requirements |
| **Multiple Output Formats** | Table (human-readable), JSON (archival), Object (pipeline) |
| **Dry-Run Mode** | Preview violations without persisting results |
| **Severity Classification** | Critical/High/Medium/Warning per zone and violation type |
| **Regulatory Context** | FINRA 3110, SOX 404, GLBA 501(b) context for each violation |
| **Environment Filtering** | Exclude sandbox, trial, default, or newly provisioned environments |
| **Teams/Email Alerting** | Adaptive card alerts with severity classification and regulatory context |
| **Evidence Export** | SHA-256 integrity-hashed JSON evidence for regulatory examinations |
| **Approved Route Import** | CSV-based governance import for approved communication routes |
| **Cross-Tenant Entra Correlation** | Correlates cross-tenant violations with Entra cross-tenant access policies and B2B direct connect settings |
| **Child-Agent Payload Size Checks** | Validates child-agent input/output declarations against the documented 1 MB Copilot Studio limit |

## Solution Components

```
agent-communication-restriction-detector/
├── README.md
├── CHANGELOG.md
├── docs/
│   ├── dataverse-schema.md
│   ├── flow-configuration.md
│   └── prerequisites.md
├── scripts/
│   ├── acrd_client.py
│   ├── create_dataverse_schema.py
│   ├── create_environment_variables.py
│   ├── create_connection_references.py
│   ├── deploy.py
│   ├── requirements.txt
│   ├── Test-CommRestrictionCompliance.ps1
│   ├── Export-CommViolationEvidence.ps1
│   ├── Test-EvidenceIntegrity.ps1
│   ├── Start-CommRestrictionValidationRunbook.ps1
│   ├── Get-AgentSkillRegistrations.ps1
│   ├── Get-CrossTenantAccessCorrelation.ps1
│   ├── Test-ChildAgentPayloadSize.ps1
│   ├── private/
│   │   ├── ACRDClient.psm1
│   │   ├── Connect-EnvironmentDataverse.ps1
│   │   ├── Get-ExpectedCommPolicy.ps1
│   │   ├── Get-ZoneClassification.ps1
│   │   └── Test-ParameterValidation.ps1
│   └── governance/
│       └── Import-ApprovedCommRoutes.ps1
```

## Quick Start

```powershell
# 1. Install Python dependencies
pip install -r scripts/requirements.txt

# 2. Deploy Dataverse schema (dry-run first)
#    Requires ACRD_TENANT_ID and ACRD_ENVIRONMENT_URL env vars, or pass explicitly:
python scripts/deploy.py --interactive --dry-run \
    --tenant-id <your-tenant-id> \
    --environment-url <your-dataverse-url>

# 3. Import approved communication routes
.\scripts\governance\Import-ApprovedCommRoutes.ps1 `
    -CsvPath ".\approved-routes.csv" `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -Interactive

# 4. Run compliance scan (dry-run first; use Windows PowerShell 5.1 for the Power Platform admin module)
. .\scripts\Test-CommRestrictionCompliance.ps1
Test-CommRestrictionCompliance -ExcludeSandbox -WhatIf

# 5. Export and verify evidence
.\scripts\Export-CommViolationEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -OutputDirectory ".\evidence" `
    -Interactive

.\scripts\Test-EvidenceIntegrity.ps1 `
    -EvidenceFilePath ".\evidence\acrd-evidence-All-20260210-143022.json"
```

## Configuration Placeholders

The following placeholder values in solution files must be replaced with your organization's values before deployment:

| Placeholder | Replace With |
|------------|-------------|
| `{{TENANT_DOMAIN}}` | Your tenant domain (e.g., `contoso.onmicrosoft.com`) |
| `{{COMPLIANCE_EMAIL}}` | Compliance team distribution list |
| `{{CLIENT_ID}}` | Microsoft Entra ID app registration client ID |
| `{{CERTIFICATE_THUMBPRINT}}` | Service principal certificate thumbprint |
| `{{AZURE_SUBSCRIPTION}}` | Azure subscription ID for Automation |
| `{{RESOURCE_GROUP}}` | Resource group for Azure Automation account |
| `{{AUTOMATION_ACCOUNT}}` | Azure Automation account name |
| `{{TEAMS_GROUP_ID}}` | Microsoft Teams group (team) GUID |
| `{{TEAMS_CHANNEL_ID}}` | Microsoft Teams channel GUID |

## Related Controls

| Control | Relationship |
|---------|-------------|
| [2.17 -- Multi-Agent Orchestration Limits](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.17-multi-agent-orchestration-limits/) | Primary -- validates agent-to-agent communication restrictions |
| [1.8 -- Runtime Protection](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.8-runtime-security-monitoring/) | Supporting -- runtime communication validation |
| [2.1 -- Managed Environments](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.1-managed-environments/) | Dependency -- zone classification source |
| [3.8 -- Copilot Hub](https://judeper.github.io/FSI-AgentGov/controls/pillar-3-reporting/3.8-copilot-hub-and-governance-dashboard/) | Downstream -- evidence export for governance dashboard |

## Documentation

- [Prerequisites](docs/prerequisites.md) -- Module and permission requirements
- [Dataverse Schema](docs/dataverse-schema.md) -- Table, column, and option set reference
- [Flow Setup](docs/flow-configuration.md) -- Power Automate deployment guide

See [CHANGELOG](./CHANGELOG.md) for version history.

## License

MIT License -- See [LICENSE](../LICENSE)
