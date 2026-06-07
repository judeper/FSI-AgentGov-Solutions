---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P1, P2, P4]
applicable_drivers:
  - ai_governance
coe_function: govern
---
# Generative AI Config Auditor

> **Version:** v1.2.1
> **Status:** Live
> **Validated against framework version:** v1.6.0
> **Last Verified:** 2026-05-25

Validates generative AI feature configurations (Azure OpenAI integration, generative orchestration, generative answers nodes, knowledge sources, Allow ungrounded responses / AI general knowledge, and Work IQ / semantic search) for Copilot Studio agents against zone-specific governance policies.

## Overview

The Generative AI Config Auditor (GAC) validates that Copilot Studio agents comply with organization-specific generative AI governance policies. It detects unauthorized Azure OpenAI integrations, unapproved generative orchestration modes, unvetted knowledge sources, unauthorized Allow ungrounded responses (AI general knowledge) usage, and unapproved Work IQ (semantic search) enablement across Power Platform environments.

Unlike the Content Moderation Monitor which validates moderation levels, GAC audits the generative AI feature configuration itself -- which AI capabilities are enabled, how they are configured, and whether connections to Azure OpenAI are on the approved whitelist.

## Zone Requirements

Each governance zone defines which generative AI features are permitted and under what conditions:

| Feature | Zone 1 | Zone 2 | Zone 3 |
|---------|--------|--------|--------|
| Azure OpenAI Integration | Allowed | Approved connections only | Explicit allowlist only |
| Generative Orchestration | Allowed | Allowed with approval | Restricted (classic unless exception) |
| Generative Answers Nodes | Allowed | Allowed | Explicit allowlist per topic |
| AOAI Connection Whitelist | Advisory (warning) | Enforced (high) | Enforced (critical) |
| Allow ungrounded responses (AI general knowledge) | Allowed | Requires approval | Disabled (only approved knowledge sources) |
| Work IQ (semantic search) | Allowed | Allowed with logging | Requires explicit approval |

### Violation Severity Matrix

| Violation | Zone 1 | Zone 2 | Zone 3 |
|-----------|--------|--------|--------|
| Unapproved AOAI Connection | Warning | High | Critical |
| Generative Orchestration (unauthorized) | Warning | Medium | Critical |
| Generative Answers (unauthorized) | Warning | Medium | High |
| Allow ungrounded responses (unauthorized) | Warning | Medium | Critical |
| Work IQ / semantic search (unauthorized) | Warning | Medium | High |
| Unknown Configuration | Warning | Medium | High |

## Features

| Feature | Description |
|---------|-------------|
| **Per-Agent Validation** | Validates each Copilot Studio agent's generative AI configuration individually |
| **Zone Compliance** | Compares actual generative AI settings against zone-specific governance policies |
| **AOAI Connection Whitelist** | Manages approved Azure OpenAI connections per zone |
| **Multiple Output Formats** | Table (human-readable), JSON (archival), Object (pipeline) |
| **Dry-Run Mode** | Preview violations without persisting results |
| **Severity Classification** | Critical/High/Medium/Warning per zone and violation type |
| **Regulatory Context** | FINRA Rule 3110, SOX Section 404, GLBA Section 501(b) context for each violation |
| **Environment Filtering** | Exclude sandbox, trial, default, or newly provisioned environments |
| **Baseline Drift Detection** | Daily baseline comparison detects generative AI configuration changes |
| **Teams/Email Alerting** | Adaptive card alerts with severity classification and regulatory context |
| **Evidence Export** | SHA-256 integrity-hashed JSON evidence for regulatory examinations |
| **Approved Connection Import** | CSV-based governance import for approved AOAI connections |
| **Purview DLP Evidence** | Collects DLP policies covering Microsoft 365 Copilot location and sensitivity labels applied to AI knowledge sources |

## Solution Components

```
generative-ai-config-auditor/
├── README.md
├── CHANGELOG.md
├── docs/
│   ├── dataverse-schema.md
│   ├── flow-configuration.md
│   └── prerequisites.md
├── scripts/
│   ├── gac_client.py
│   ├── create_dataverse_schema.py
│   ├── create_environment_variables.py
│   ├── create_connection_references.py
│   ├── deploy.py
│   ├── requirements.txt
│   ├── Test-GenAIConfigCompliance.ps1
│   ├── Invoke-GenAIBaselineCapture.ps1
│   ├── Compare-GenAIConfigCompliance.ps1
│   ├── Get-AgentGenAISettings.ps1
│   ├── Get-PurviewDLPEvidence.ps1
│   ├── Export-GenAIConfigEvidence.ps1
│   ├── Test-EvidenceIntegrity.ps1
│   ├── Start-GenAIConfigValidationRunbook.ps1
│   ├── private/
│   │   ├── GACClient.psm1
│   │   ├── Connect-EnvironmentDataverse.ps1
│   │   ├── Get-ExpectedGenAIPolicy.ps1
│   │   ├── Get-GACValidationResults.ps1
│   │   ├── Get-ZoneClassification.ps1
│   │   └── Test-ParameterValidation.ps1
│   └── governance/
│       └── Import-ApprovedAoaiConnections.ps1
```

## Quick Start

```powershell
# 1. Install Python dependencies
pip install -r scripts/requirements.txt

# 2. Deploy Dataverse schema (dry-run first)
python scripts/deploy.py --interactive --dry-run

# 3. Import approved AOAI connections
.\scripts\governance\Import-ApprovedAoaiConnections.ps1 `
    -CsvPath ".\approved-connections.csv" `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -Interactive

# 4. Run compliance scan (dry-run first)
. .\scripts\Test-GenAIConfigCompliance.ps1
Test-GenAIConfigCompliance -ExcludeSandbox -WhatIf

# 5. Capture baseline
.\scripts\Invoke-GenAIBaselineCapture.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -Interactive

# 6. Export and verify evidence
.\scripts\Export-GenAIConfigEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -OutputDirectory ".\evidence" `
    -Interactive

.\scripts\Test-EvidenceIntegrity.ps1 `
    -EvidencePath ".\evidence\gac-evidence-All-*.json"
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

## Platform Update Notes

### Admin Path Change (April 2026)

Power Platform admin center now exposes a centralized **Copilot > Settings** area for Power Platform Copilot and agent settings. Copilot Studio also retains environment-level **Generative AI features** controls and the tenant-level **Publish Copilots with AI features** setting, while Microsoft 365 admin center controls govern agents and AI actions surfaced in Microsoft 365 Copilot.

**Impact on this solution:** Manual verification should distinguish Power Platform admin center `Copilot > Settings`, environment **Generative AI features**, and Microsoft 365 admin center agent/action controls. Automated validation via Dataverse bot records and Power Platform cmdlets is unaffected.

### Voice Feature Enablement (April 2026)

Copilot Studio now supports [real-time voice agents](https://learn.microsoft.com/en-us/microsoft-copilot-studio/voice-configuration) with Basic and Realtime voice modes, barge-in support, and DTMF navigation. Voice enablement introduces additional governance considerations:

- **Zone 3 agents** with voice capabilities may require explicit approval before enabling real-time voice mode, due to telephony channel exposure
- Voice-enabled agents generate speech transcripts that may fall under FINRA Rule 4511 and SEC Rule 17a-4 record-keeping requirements
- Organizations should evaluate whether voice feature toggles require the same zone-based governance as other GenAI features audited by this solution

> **Note:** Voice configuration governance is not yet automated in GAC scripts. Organizations should include voice enablement in their manual feature governance reviews until automated support is added.

## Related Controls

| Control | Relationship |
|---------|-------------|
| [2.24 -- Agent Feature Enablement Governance](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.24-agent-feature-enablement-and-restriction-governance/) | Primary -- validates generative AI feature configurations |
| [1.8 -- Runtime Protection](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.8-runtime-protection-and-external-threat-detection/) | Supporting -- runtime feature validation |
| [2.1 -- Managed Environments](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.1-managed-environments/) | Dependency -- zone classification source |
| [3.8 -- Copilot Hub](https://judeper.github.io/FSI-AgentGov/controls/pillar-3-reporting/3.8-copilot-hub-and-governance-dashboard/) | Downstream -- evidence export for governance dashboard |

## Documentation

- [Prerequisites](docs/prerequisites.md) -- Module and permission requirements
- [Dataverse Schema](docs/dataverse-schema.md) -- Table, column, and option set reference
- [Flow Setup](docs/flow-configuration.md) -- Power Automate deployment guide

## License

MIT License -- See [LICENSE](../LICENSE)
