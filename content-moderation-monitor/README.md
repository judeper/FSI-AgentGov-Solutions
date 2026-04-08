# Content Moderation Monitor

Automated validation of Copilot Studio agent content moderation levels against zone-specific governance requirements.

> **Status:** Completed

## Overview

The Content Moderation Monitor detects when Copilot Studio agents have insufficient content moderation settings for their governance zone. Unlike environment-level solutions, this monitor performs **per-agent validation** — examining each bot deployed across your Power Platform environments.

It supports Controls 1.8 (Runtime Protection) and 1.14 (Content Moderation Enforcement) by automating compliance validation against the FSI Agent Governance Framework's zone-based moderation requirements.

**Version:** 1.0.2

## Quick Start

```powershell
# 1. Install required modules
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Force

# 2. Connect to Power Platform
Add-PowerAppsAccount

# 3. Run validation (dry-run mode)
./scripts/Test-ContentModerationCompliance.ps1 -ExcludeSandbox -WhatIf

# 4. Run full validation
./scripts/Test-ContentModerationCompliance.ps1 -ExcludeSandbox

# 5. Export compliance evidence
./scripts/Export-ContentModerationEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId "your-tenant-id" `
    -OutputDirectory ".\exports" `
    -Interactive

# 6. Verify evidence integrity
./scripts/Test-EvidenceIntegrity.ps1 `
    -EvidenceFilePath ".\exports\cmm-evidence-All-*.json"
```

## Zone Requirements

Each governance zone has a minimum required content moderation level:

| Zone | Description | Minimum Moderation | Rationale |
|------|-------------|-------------------|-----------|
| Zone 1 | Personal Productivity | Medium | Baseline content protection for individual use |
| Zone 2 | Team Collaboration | High | Shared agents require stronger content controls |
| Zone 3 | Enterprise Managed | High | Customer-facing agents require maximum protection |

### Violation Severity Matrix

| Zone | Actual Level | Severity | Regulatory Context |
|------|-------------|----------|-------------------|
| Zone 3 | Low | Critical | FINRA 3110 — Unmoderated customer-facing AI agent |
| Zone 3 | Medium | High | GLBA 501(b) — Insufficient content protection for enterprise agent |
| Zone 2 | Low | High | SOX 404 — Inadequate content controls for shared agent |
| Zone 2 | Medium | Medium | Best practice uplift recommended for team agents |
| Zone 1 | Low | High | Governance gap — Below minimum content moderation threshold |
| Unknown | Low | High | Governance gap — Unclassified environment with minimal content moderation |
| Unknown | Medium | Warning | Governance gap — Environment not assigned to zone |

## Features

| Feature | Description |
|---------|-------------|
| **Per-Agent Validation** | Validates each Copilot Studio agent's moderation level individually |
| **Zone Compliance** | Compares actual moderation levels against zone-specific minimums |
| **Multiple Output Formats** | Table (human-readable), JSON (archival), Object (pipeline) |
| **Dry-Run Mode** | Preview violations without persisting results |
| **Severity Classification** | Critical/High/Medium/Warning per zone and moderation level |
| **Regulatory Context** | FINRA 3110, SOX 404, GLBA 501(b) context for each violation |
| **Environment Filtering** | Exclude sandbox, trial, default, or newly provisioned environments |
| **Drift Detection** | Daily baseline comparison detects configuration changes |
| **Teams Alerting** | Adaptive card alerts with severity classification and regulatory context |
| **Evidence Export** | SHA-256 integrity-hashed JSON evidence for regulatory examinations |
| **Evidence Verification** | Tamper detection via companion hash file verification |

## Solution Components

```
content-moderation-monitor/
├── scripts/
│   ├── Get-AgentModerationSettings.ps1    # Query agent moderation levels
│   ├── Compare-ModerationCompliance.ps1   # Compare levels vs requirements
│   ├── Test-ContentModerationCompliance.ps1 # Validation orchestrator
│   ├── Start-ModerationValidationRunbook.ps1 # Azure Automation runbook wrapper
│   ├── Invoke-ModerationBaselineCapture.ps1  # Baseline capture utility
│   ├── Export-ContentModerationEvidence.ps1   # SHA-256 evidence export
│   ├── Test-EvidenceIntegrity.ps1             # Evidence hash verification
│   └── private/
│       ├── CMMClient.psm1                 # Dataverse client module
│       ├── Get-CMMValidationResults.ps1   # Evidence query helper
│       ├── Get-ZoneClassification.ps1     # Zone lookup helper
│       ├── Get-ExpectedModerationLevel.ps1 # Moderation level reference
│       ├── Test-ParameterValidation.ps1   # Parameter validators
│       └── Connect-EnvironmentDataverse.ps1 # Per-env Dataverse auth
├── templates/
│   ├── moderation-baseline.json           # Zone requirements reference
│   └── adaptive-card-moderation-alert.json # Teams alert template
└── docs/
    ├── PREREQUISITES.md                   # Module and permission requirements
    ├── SCHEMA.md                          # Dataverse schema reference
    ├── EVIDENCE_EXPORT.md                 # Evidence export guide
    ├── FLOW_SETUP.md                      # Power Automate setup guide
    └── TROUBLESHOOTING.md                 # Troubleshooting guide
```

## Key Difference from Agent Access Monitor

The **Agent Access Monitor (v6)** validates **per-environment** settings (sharing modes, authoring restrictions). The **Content Moderation Monitor (v7)** validates **per-agent** settings — each Copilot Studio bot is individually assessed for content moderation compliance.

This means:
- A single environment may contain both compliant and non-compliant agents
- Violations are reported at the agent level, not the environment level
- Remediation targets specific bots rather than environment-wide configuration

## Platform Update Notes

### Voice Agent Moderation Considerations (April 2026)

Copilot Studio now supports [real-time voice agents](https://learn.microsoft.com/en-us/microsoft-copilot-studio/voice-configuration) with Basic and Realtime voice modes, barge-in support, and DTMF navigation. Voice-enabled agents introduce additional content moderation considerations:

- **Speech-to-text transcription** may not be subject to the same content moderation filters as text input — organizations should verify that moderation applies equally to both modalities
- **Barge-in behavior** (user interrupting agent speech) may bypass moderation checkpoints if the interrupted content is not fully evaluated
- **DTMF input** is numeric-only and lower risk, but agents that combine DTMF with natural language voice require full moderation coverage
- **Zone 3 agents** with telephony channels are customer-facing by definition and should maintain High moderation regardless of voice mode

> **Note:** This solution currently validates content moderation levels for text-based agent interactions only. Voice-specific moderation validation is not yet automated. Organizations deploying voice-enabled agents should include voice moderation coverage in their manual governance reviews.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [1.8 - Runtime Protection](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.8-runtime-security-monitoring/) | Primary — Runtime security monitoring and content moderation |
| [1.14 - Content Moderation Enforcement](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.14-content-moderation-enforcement/) | Primary — Agent content moderation levels |
| [2.1 - Managed Environments](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.1-managed-environments/) | Zone classification source |
| [3.8 - Copilot Hub](https://judeper.github.io/FSI-AgentGov/controls/pillar-3-reporting/3.8-copilot-hub-and-governance-dashboard/) | Governance dashboard integration |

## Configuration Placeholders

Configuration values for the Power Automate flow (tenant domain, Dataverse URL, compliance email, Teams IDs, etc.) must be set during manual flow creation. See [Flow Setup Guide](docs/FLOW_SETUP.md#step-2-configure-variables) for the complete list with descriptions.

## Documentation

- [Prerequisites](docs/PREREQUISITES.md)— Module and permission requirements
- [Dataverse Schema](docs/SCHEMA.md) — Table, column, and option set reference
- [Evidence Export](docs/EVIDENCE_EXPORT.md) — Compliance evidence export guide
- [Flow Setup](docs/FLOW_SETUP.md) — Power Automate deployment guide
- [Troubleshooting](docs/TROUBLESHOOTING.md) — Common issues and resolutions

## Prerequisites

See [docs/PREREQUISITES.md](docs/PREREQUISITES.md) for detailed requirements.

## License

MIT License — See [LICENSE](../LICENSE)
