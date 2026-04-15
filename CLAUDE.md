# FSI-AgentGov-Solutions

## Purpose

Reference implementations for the [FSI Agent Governance Framework](https://judeper.github.io/FSI-AgentGov/).
These solutions help Financial Services organizations implement operational controls and monitoring for AI agents (Copilot Studio, Agent Builder).

## Companion Repository

**FSI-AgentGov** (`/Users/admin/dev/FSI-AgentGov`) contains the governance framework documentation:
- `docs/framework/` - Governance principles
- `docs/controls/` - 78 control specifications
- `docs/playbooks/` - Implementation guides including references to solutions here

### Cross-Repository Workflow

**Primary Working Directory:** FSI-AgentGov (documentation repo)
- Boundary hooks in both repos allow cross-access

**Hook Scope:**
- `boundary-check.py` only intercepts Bash commands
- Read/Write/Edit/Glob/Grep tools work cross-repo without restriction

**Git Operations:**
Each repo has separate git history. Always verify your working directory before git commands:
```bash
git rev-parse --show-toplevel
```

## Solution Content Policy (CRITICAL)

**Solutions must NOT contain Power Platform runtime artifacts** — no exported flow JSON, Canvas app packages, connection references, or environment variable exports. Solutions provide only documentation (manual step-by-step instructions for building flows in Power Automate designer), scripts (PowerShell, Python, KQL), and templates (schemas, sample payloads). If a `src/` directory exists with flow JSON files, replace it with documentation in `docs/`.

## Solutions

| Solution | Description | Type | Version |
|----------|-------------|------|---------|
| [action-confirmation-auditor](./action-confirmation-auditor/) | Step-up confirmation validation for agent action invocations | PowerShell/Python | v1.0.1 |
| [agent-365-lifecycle-governance](./agent-365-lifecycle-governance/) | Automated lifecycle governance for AI agents using Agent 365 and Entra ID Governance | PowerShell/Python | v1.1.1 |
| [agent-access-monitor](./agent-access-monitor/) | Automated detection of overly permissive agent access configurations | PowerShell/Python | v1.0.2 |
| [agent-communication-restriction-detector](./agent-communication-restriction-detector/) | Inter-agent communication restriction validation per zone routing policy | PowerShell/Python | v1.0.1 |
| [agent-knowledge-source-scanner](./agent-knowledge-source-scanner/) | Item-level permission scanning for agent knowledge source SharePoint libraries | PowerShell | v1.0.3 |
| [agent-observability-foundation](./agent-observability-foundation/) | Foundational observability infrastructure for agent monitoring and diagnostics | KQL/Docs | v1.1.1 |
| [agent-registry-automation](./agent-registry-automation/) | Automated discovery, registration, approval, and lifecycle governance of AI agents | PowerShell/Python | v1.0.1 |
| [agent-sharing-access-restriction-detector](./agent-sharing-access-restriction-detector/) | Zone-based agent sharing policy enforcement with approval workflows | PowerShell/Python | v1.0.4 |
| [audit-compliance-manager](./audit-compliance-manager/) | Unified audit compliance — validates configs, detects gaps, remediates | PowerShell/Python | v1.0.2 |
| [coi-testing](./coi-testing/) | Conflict of interest testing for agent recommendations | Python/Docs | v1.0.2 |
| [compliance-dashboard](./compliance-dashboard/) | Aggregated compliance reporting across 78 controls with Exchange coverage | Docs/Dataverse | v1.0.1 |
| [conditional-access-automation](./conditional-access-automation/) | CA policy deployment, compliance monitoring, and drift detection | PowerShell/Python | v1.2.0 |
| [content-moderation-monitor](./content-moderation-monitor/) | Per-agent content moderation validation against zone requirements | PowerShell/Python | v1.0.2 |
| [copilot-studio-analytics](./copilot-studio-analytics/) | Business impact analytics for Copilot Studio agents (Viva Insights alternative) | Python/KQL | v1.1.0 |
| [credential-oversharing-detector](./credential-oversharing-detector/) | Configuration-time credential scope governance for agent connectors | PowerShell/Python | v1.0.0 |
| [cross-solution-integration](./cross-solution-integration/) | Wires Tier 2 solutions into Compliance Dashboard with unified evidence export | Python/Docs | v1.0.1 |
| [cross-tenant-external-sharing-governance](./cross-tenant-external-sharing-governance/) | Three-layer cross-tenant access governance (tenant isolation, Entra CTA, agent shares) | PowerShell/Python | v1.0.0 |
| [deny-event-correlation-report](./deny-event-correlation-report/) | Daily deny event correlation across Purview, DLP, App Insights | PowerShell/KQL | v2.0.0 |
| [dr-testing-framework](./dr-testing-framework/) | Automated disaster recovery testing for AI agent infrastructure | PowerShell/Python | v1.2.0 |
| [environment-lifecycle-management](./environment-lifecycle-management/) | Power Platform environment provisioning with zone-based governance | Python/Docs | v1.1.2 |
| [file-upload-security](./file-upload-security/) | Per-agent file upload validation against zone governance policies | PowerShell/Python | v1.0.1 |
| [finra-supervision-workflow](./finra-supervision-workflow/) | Automated supervision queue for AI agent outputs (FINRA 3110) | PowerShell/Docs | v1.0.0 |
| [generative-ai-config-auditor](./generative-ai-config-auditor/) | GenAI feature configuration validation per zone governance policy | PowerShell/Python | v1.0.0 |
| [hallucination-tracker](./hallucination-tracker/) | Feedback aggregation for hallucination pattern analysis | Python/Docs | v1.0.0 |
| [hitl-workflow-governance](./hitl-workflow-governance/) | Zone-based governance for Human in the Loop checkpoints in Copilot Studio agent flows | PowerShell/Python | v1.0.0 |
| [inactivity-timeout-enforcement](./inactivity-timeout-enforcement/) | Policy-driven inactivity timeout validation with zone-based durations | PowerShell/Python | v1.0.4 |
| [message-center-monitor](./message-center-monitor/) | M365 Message Center monitoring for platform changes | Docs/Dataverse | v2.2.0 |
| [mime-type-restrictions](./mime-type-restrictions/) | Zone-based MIME type configuration with server-side validation | PowerShell/Python | v1.0.2 |
| [model-risk-management-automation](./model-risk-management-automation/) | OCC 2011-12 / SR 11-7 model risk management with inventory, risk scoring, validation workflows, and Agent Card generation | PowerShell/Python | v1.0.0 |
| [pipeline-governance-cleanup](./pipeline-governance-cleanup/) | Discover, notify, clean up personal pipelines | PowerShell/Manual | v1.1.0 |
| [rag-source-validator](./rag-source-validator/) | Integrity validation for RAG knowledge sources with change detection | Python/Docs | v1.1.0 |
| [scope-drift-monitor](./scope-drift-monitor/) | Detect agent data access beyond declared operational scope | PowerShell/Python | v1.1.1 |
| [segregation-detector](./segregation-detector/) | Role conflict detection for Maker/Checker enforcement in agent pipelines | PowerShell/Python | v1.0.0 |
| [session-security-configurator](./session-security-configurator/) | Session security validation per governance zone with drift detection | PowerShell/Python | v1.0.1 |
| [unrestricted-agent-sharing-detector](./unrestricted-agent-sharing-detector/) | Continuous detection of overly permissive agent sharing with automated remediation | PowerShell/Python | v1.0.2 |

## Control Implementations

| Solution | Primary Controls | Description |
|----------|-----------------|-------------|
| action-confirmation-auditor | 1.23 | Step-up confirmation for agent operations |
| agent-365-lifecycle-governance | 2.3, 1.2, 1.11, 2.1, 2.8, 2.12, 3.1 | Agent lifecycle governance with sponsor enforcement and access reviews |
| agent-access-monitor | 3.8 | Overly permissive agent access detection per governance zone |
| agent-communication-restriction-detector | 2.17 | Multi-agent orchestration limits per zone routing policy |
| agent-knowledge-source-scanner | 4.3, 1.4, 1.5 | Item-level permission scanning for agent knowledge source libraries |
| agent-observability-foundation | 1.7, 2.8, 2.9, 3.2 | Foundational observability infrastructure |
| agent-registry-automation | 1.2, 1.7, 2.1, 2.13 | Automated discovery, registration, approval, and lifecycle governance |
| agent-sharing-access-restriction-detector | 1.18, 2.8 | Zone-based sharing policy enforcement |
| audit-compliance-manager | 1.7 | Audit configuration validation and gap remediation |
| coi-testing | 2.18, 2.11, 2.5 | Conflict of interest testing for agent recommendations |
| compliance-dashboard | 3.3, 3.1, 3.2 | Aggregated compliance reporting with Exchange coverage |
| conditional-access-automation | 1.11, 1.23, 1.18 | CA policy deployment and drift detection |
| content-moderation-monitor | 1.8, 1.14 | Content moderation validation against zone requirements |
| copilot-studio-analytics | 3.2 | Business impact analytics and session outcome monitoring |
| credential-oversharing-detector | 1.14, 1.4, 1.18 | Configuration-time credential scope governance for agent connectors |
| cross-solution-integration | 1.7, 1.23, 1.11, 3.8, 1.8, 1.14 | Compliance Dashboard integration and evidence export |
| cross-tenant-external-sharing-governance | 1.1, 1.18, 2.1, 2.8, 3.1, 1.11 | Three-layer cross-tenant access governance |
| deny-event-correlation-report | 1.5, 1.7, 1.8, 3.4 | Deny event correlation across Purview and App Insights |
| dr-testing-framework | 2.4, 2.1, 1.9 | Automated disaster recovery testing |
| environment-lifecycle-management | 2.1, 2.2, 2.3, 2.8, 1.7 | Environment provisioning with zone-based governance |
| file-upload-security | 1.14, 1.8, 1.4 | File upload validation against zone governance policies |
| finra-supervision-workflow | 2.12, 1.10, 1.7 | Supervision queue for AI agent outputs (FINRA 3110) |
| generative-ai-config-auditor | 2.24 | GenAI feature enablement governance per zone |
| hallucination-tracker | 3.10, 2.9, 2.12 | Hallucination pattern analysis and feedback aggregation |
| hitl-workflow-governance | 2.12, 2.17, 1.10 | Zone-based HITL checkpoint governance for agent flows |
| inactivity-timeout-enforcement | 2.22, 1.23, 3.7, 3.8 | Inactivity timeout validation with zone-based durations |
| message-center-monitor | 2.3, 2.10 | M365 Message Center platform change monitoring |
| mime-type-restrictions | 1.5, 1.10, 1.11, 1.13, 1.14, 1.25, 3.3, 3.7, 4.3 | MIME type configuration with server-side validation |
| model-risk-management-automation | 2.6, 2.5, 2.9, 2.11, 2.13, 3.1, 1.2 | OCC 2011-12 / SR 11-7 model risk management |
| pipeline-governance-cleanup | 2.3, 2.1 | Personal pipeline cleanup and ALM governance |
| rag-source-validator | 2.16, 1.7, 2.13 | RAG knowledge source integrity validation |
| scope-drift-monitor | 1.14, 1.4, 1.5 | Agent data access scope drift detection |
| segregation-detector | 2.8, 2.1, 2.3 | Role conflict detection for Maker/Checker enforcement |
| session-security-configurator | 1.23, 1.11 | Session security validation with drift detection |
| unrestricted-agent-sharing-detector | 1.1, 3.8 | Overly permissive agent sharing detection and remediation |

When updating solution READMEs, ensure Related Controls sections match these mappings.

## Directory Structure

```
FSI-AgentGov-Solutions/
├── .claude/
│   ├── settings.json          # Team-shared settings
│   └── settings.local.json    # Local overrides (not committed)
├── .codex/
│   └── config.toml            # Codex CLI configuration
├── .github/
│   ├── copilot-instructions.md    # GitHub Copilot context
│   └── instructions/              # Auto-included rules
├── scripts/
│   ├── hooks/                  # Claude Code hooks (root-level)
│   └── shared/                 # Shared utilities
│       ├── dataverse_client.py     # Shared Dataverse Web API client (MSAL, retry, dry-run)
│       └── Get-ZoneClassification.ps1
├── {solution-name}/
│   ├── README.md              # Solution overview and setup
│   ├── CHANGELOG.md           # Version history
│   ├── docs/
│   │   ├── dataverse-schema.md     # Auto-generated (python create_*_schema.py --output-docs)
│   │   └── flow-configuration.md   # Manual build instructions
│   ├── scripts/               # Python setup + PowerShell governance
│   └── templates/             # JSON schemas and sample payloads
└── CHANGELOG.md
```

## Hooks

| Hook | Location | Purpose |
|------|----------|---------|
| `scripts/hooks/boundary-check.py` | Root | Full boundary checking with cross-repo access |
| `scripts/hooks/researcher-package-reminder.py` | Root | Reminder for FSI-AgentGov package regeneration |
| `pipeline-governance-cleanup/scripts/hooks/*` | Nested | Simple pass-throughs for standalone use |

**Note:** The nested hooks in `pipeline-governance-cleanup/scripts/hooks/` are intentionally different from root hooks. They allow all commands when that solution is used standalone.

## Dataverse Column Naming (CRITICAL)

Dataverse uses two names for every column:
- **SchemaName** (PascalCase with prefix): `fsi_AgentId`, `fsi_EnvironmentName`
- **Logical name** (all-lowercase, NO underscores between words): `fsi_agentid`, `fsi_environmentname`

The logical name is the SchemaName lowercased. Dataverse NEVER inserts underscores between words.

**CORRECT:** `fsi_agentid`, `fsi_violationtype` | **WRONG:** `fsi_agent_id`, `fsi_violation_type`

Source of truth: each solution's `create_*_dataverse_schema.py`.

## Language Guidelines (CRITICAL)

When writing documentation in this repository, follow the language guidelines from FSI-AgentGov:

**NEVER use these phrases (legal risk):**
- "ensures compliance" - implies guarantee
- "guarantees" - legal liability
- "will prevent" - overclaim

**ALWAYS use alternatives:** "supports compliance with", "helps meet", "recommended to"

**Full guidelines:** See FSI-AgentGov `CONTRIBUTING.md`

## Validation Commands

```bash
# Validate Python scripts
python -m py_compile scripts/hooks/*.py

# Validate PowerShell scripts (requires PowerShell)
pwsh -Command "Get-ChildItem -Recurse -Filter *.ps1 | ForEach-Object { [System.Management.Automation.Language.Parser]::ParseFile(\$_.FullName, [ref]\$null, [ref]\$null) }"
```

## Site Design System

The documentation site (`site-docs/`) uses a unified FSI design system shared across all FSI-AgentGov and FSI-CopilotGov repositories.

- **Theme:** MkDocs Material with `primary: custom` / `accent: custom`
- **Colors:** Microsoft Blue (`#0078D4`) primary, WCAG AA teal (`#007A7E`) accent — defined in `site-docs/stylesheets/extra.css`
- **Logo:** Shield + circuit motif SVG in `site-docs/assets/`
- **Homepage:** Hero → metrics strip → role cards → architecture diagram (uses `hide: navigation, toc`, `md_in_html`, `attr_list`)
- **Navigation:** `navigation.sections` intentionally removed (sidebar collapses by default)
- **Font:** `font: false` (avoids Google Fonts CDN blocked in FSI environments)
- **Extensions:** `pymdownx.emoji`, `md_in_html`, `pymdownx.highlight`

Do not change `primary`/`accent` in `mkdocs.yml` — they must stay `custom`. Modify colors in `extra.css`.
