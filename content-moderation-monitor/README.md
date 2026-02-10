# Content Moderation Monitor

Automated validation of Copilot Studio agent content moderation levels against zone-specific governance requirements.

## Overview

The Content Moderation Monitor detects when Copilot Studio agents have insufficient content moderation settings for their governance zone. Unlike environment-level solutions, this monitor performs **per-agent validation** — examining each bot deployed across your Power Platform environments.

It supports Control 1.14 (Content Moderation) and related controls by automating compliance validation against the FSI Agent Governance Framework's zone-based moderation requirements.

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
| Unknown | Any non-compliant | Warning | Governance gap — Environment not assigned to zone |

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

## Solution Components

```
content-moderation-monitor/
├── scripts/
│   ├── Get-AgentModerationSettings.ps1    # Query agent moderation levels
│   ├── Compare-ModerationCompliance.ps1   # Compare levels vs requirements
│   ├── Test-ContentModerationCompliance.ps1 # Validation orchestrator
│   └── private/
│       ├── CMMClient.psm1                 # Dataverse client
│       ├── Get-ZoneClassification.ps1     # Zone lookup helper
│       ├── Get-ExpectedModerationLevel.ps1 # Moderation level reference
│       ├── Test-ParameterValidation.ps1   # Parameter validators
│       └── Connect-EnvironmentDataverse.ps1 # Per-env Dataverse auth
├── src/dataverse/                         # Dataverse schema (Phase 2)
├── templates/
│   └── moderation-baseline.json           # Zone requirements reference
├── flows/                                 # Power Automate flows (Phase 3)
└── docs/
    ├── PREREQUISITES.md
    ├── SCHEMA.md
    ├── EVIDENCE_EXPORT.md
    └── TROUBLESHOOTING.md
```

## Key Difference from Agent Access Monitor

The **Agent Access Monitor (v6)** validates **per-environment** settings (sharing modes, authoring restrictions). The **Content Moderation Monitor (v7)** validates **per-agent** settings — each Copilot Studio bot is individually assessed for content moderation compliance.

This means:
- A single environment may contain both compliant and non-compliant agents
- Violations are reported at the agent level, not the environment level
- Remediation targets specific bots rather than environment-wide configuration

## Related Controls

| Control | Relationship |
|---------|--------------|
| [1.14 - Content Moderation](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.14-content-moderation-configuration/) | Primary — Agent content moderation levels |
| [2.1 - Managed Environments](https://judeper.github.io/FSI-AgentGov/controls/pillar-2-management/2.1-managed-environments/) | Zone classification source |
| [3.8 - Copilot Hub](https://judeper.github.io/FSI-AgentGov/controls/pillar-3-reporting/3.8-copilot-hub-and-governance-dashboard/) | Governance dashboard integration |

## Prerequisites

See [docs/PREREQUISITES.md](docs/PREREQUISITES.md) for detailed requirements.

## License

MIT License — See [LICENSE](../LICENSE)
