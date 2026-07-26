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
> **Last Verified:** 2026-07-26

Validates generative AI feature configurations (Azure OpenAI integration, generative orchestration, generative answers nodes, knowledge sources, Allow ungrounded responses / AI general knowledge, and Tenant graph grounding with semantic search) for Copilot Studio agents against zone-specific governance policies.

## Overview

The Generative AI Config Auditor (GAC) validates that Copilot Studio agents comply with organization-specific generative AI governance policies. It detects unauthorized Azure OpenAI integrations, unapproved generative orchestration modes, unvetted knowledge sources, unauthorized Allow ungrounded responses (AI general knowledge) usage, and unapproved Tenant graph grounding with semantic search enablement across Power Platform environments.

Unlike the Content Moderation Monitor which validates moderation levels, GAC audits the generative AI feature configuration itself -- which AI capabilities are enabled, how they are configured, and whether connections to Azure OpenAI are on the approved whitelist.

## Zone Requirements

Each governance zone defines which generative AI features are permitted and under what conditions. On the lab validation tenant the shared `fsi_acv_zone` semantics are canonical: **Zone 1 (Enterprise) = most restrictive / highest-risk** (`100000001`), **Zone 2 (Team) = middle** (`100000002`), **Zone 3 (Personal) = least restrictive / lowest-risk** (`100000003`).

| Feature | Zone 1 | Zone 2 | Zone 3 |
|---------|--------|--------|--------|
| Azure OpenAI Integration | Explicit allowlist only | Approved connections only | Allowed |
| Generative Orchestration | Restricted (classic unless exception) | Allowed with approval | Allowed |
| Generative Answers Nodes | Explicit allowlist per topic | Allowed | Allowed |
| AOAI Connection Whitelist | Enforced (critical) | Enforced (high) | Advisory (warning) |
| Allow ungrounded responses (AI general knowledge) | Disabled (only approved knowledge sources) | Requires approval | Allowed |
| Tenant graph grounding with semantic search | Requires explicit approval | Allowed with logging | Allowed |

> **Product naming note (verified 2026-07-26).** Microsoft documents the agent-level semantic search toggle as **Tenant graph grounding with semantic search**, on the Copilot Studio **Generative AI** settings page ([Knowledge sources summary](https://learn.microsoft.com/microsoft-copilot-studio/knowledge-copilot-studio#tenant-graph-grounding-with-semantic-search)). Earlier releases of this solution labeled it *Work IQ*; the Dataverse column (`fsi_semanticsearchenabled`) and the detector key (`aISettings.isSemanticSearchEnabled`) are unchanged. It is a distinct capability from the separately documented [Work IQ MCP tools](https://learn.microsoft.com/microsoft-copilot-studio/use-work-iq) (preview), which are covered by the `work-iq-usage-detection` solution.

> **Orchestration and authentication dependency (verified 2026-07-26).** Microsoft documents that both **Allow ungrounded responses** and **Tenant graph grounding with semantic search** require the agent to have [generative orchestration](https://learn.microsoft.com/microsoft-copilot-studio/advanced-generative-actions) turned on, and that tenant graph grounding additionally requires the agent's user authentication to be set to **Authenticate with Microsoft**. Zone reviews are recommended to read these two toggles together with the agent's orchestration mode and authentication setting rather than in isolation.

### Violation Severity Matrix

| Violation | Zone 1 | Zone 2 | Zone 3 |
|-----------|--------|--------|--------|
| Unapproved AOAI Connection | Critical | High | Warning |
| Generative Orchestration (unauthorized) | Critical | Medium | Warning |
| Generative Answers (unauthorized) | High | Medium | Warning |
| Allow ungrounded responses (unauthorized) | Critical | Medium | Warning |
| Tenant graph grounding with semantic search (unauthorized) | High | Medium | Warning |
| Unknown Configuration | High | Medium | Warning |

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

### Admin Path Change (April 2026, re-verified 2026-07-26)

Power Platform admin center now exposes a centralized [**Copilot > Settings**](https://learn.microsoft.com/power-platform/admin/copilot/copilot-hub#settings) area for Power Platform Copilot and agent settings. Copilot Studio also retains the environment-level [**Generative AI features**](https://learn.microsoft.com/power-platform/admin/geographical-availability-copilot#turn-on-data-movement-bing-search-microsoft-365-services-and-flex-routing) pane and the tenant-level [**Publish Copilots with AI features**](https://learn.microsoft.com/power-platform/admin/tenant-settings) setting, while [Microsoft 365 admin center controls](https://learn.microsoft.com/microsoft-copilot-studio/copilot-plugins-enable-admin) govern agents and AI actions surfaced in Microsoft 365 Copilot.

**Impact on this solution:** Manual verification should distinguish Power Platform admin center `Copilot > Settings`, environment **Generative AI features**, and Microsoft 365 admin center agent/action controls. Automated validation via Dataverse bot records and Power Platform cmdlets is unaffected.

### Voice Feature Enablement (April 2026, re-verified 2026-07-26)

Copilot Studio supports [interactive voice response (IVR)](https://learn.microsoft.com/microsoft-copilot-studio/voice-overview) through two types of voice-enabled agent: [basic voice agents](https://learn.microsoft.com/microsoft-copilot-studio/voice-basic-overview), which use classic orchestration and natural language understanding models, and [real-time voice agents](https://learn.microsoft.com/microsoft-copilot-studio/voice-realtime-voice-agents), which are used in generative orchestration scenarios and run on a speech-to-speech model. Both types support [barge-in](https://learn.microsoft.com/microsoft-copilot-studio/voice-configuration#turn-on-barge-in) and [DTMF](https://learn.microsoft.com/microsoft-copilot-studio/voice-dtmf) input. Voice enablement introduces additional governance considerations:

- Voice track selection is coupled to the orchestration mode this solution already audits: Microsoft documents basic voice agents as using classic orchestration and real-time voice agents as a generative orchestration scenario, so an agent held to classic orchestration in Zone 1 falls into the basic voice track
- **Zone 1 (Enterprise) agents** with voice capabilities may require explicit approval before enabling real-time voice, due to telephony channel exposure
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
