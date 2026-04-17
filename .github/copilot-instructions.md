# FSI-AgentGov-Solutions Repository Instructions

## Project Overview

Deployable Power Platform solutions for the [FSI Agent Governance Framework](https://github.com/judeper/FSI-AgentGov). These solutions help Financial Services organizations implement operational controls and monitoring for AI agents (Copilot Studio, Agent Builder).

- **35 live solution implementations** mapped to the 78-control framework across all 4 pillars
- **Target regulations:** FINRA 4511/3110/25-07, SEC 17a-3/4, SOX 302/404, GLBA 501(b), OCC 2011-12, Fed SR 11-7, CFTC 1.31
- **Technologies:** PowerShell, Python, KQL, Dataverse (documentation-only for Power Automate — no exported flow artifacts)
- **Audience:** M365 administrators and DevOps engineers in US financial services

## Solution Catalog

| Solution | Version | Primary Controls | Description |
|----------|---------|-----------------|-------------|
| action-confirmation-auditor | v1.0.3 | 1.23 | Step-up confirmation validation for agent actions |
| agent-365-lifecycle-governance | v1.1.2 | 2.3, 1.2, 1.11, 2.1, 2.8, 2.12, 3.1 | Automated lifecycle governance for AI agents using Agent 365 and Entra ID Governance |
| agent-access-monitor | v1.0.3 | 3.8 | Automated detection of overly permissive agent access configurations |
| agent-communication-restriction-detector | v1.0.2 | 2.17 | Inter-agent communication restriction validation |
| agent-knowledge-source-scanner | v1.0.3 | 4.3, 1.4, 1.5 | Item-level permission scanning for agent knowledge source SharePoint libraries |
| agent-registry-automation | v1.0.2 | 1.2, 1.7, 2.1, 2.13 | Automated discovery, registration, approval, and lifecycle governance of AI agents |
| agent-observability-foundation | v1.1.1 | 1.7, 2.8, 2.9, 3.2 | Foundational observability infrastructure for agent monitoring |
| agent-sharing-access-restriction-detector | v1.0.4 | 1.18, 2.8 | Zone-based agent sharing policy enforcement with approval workflows |
| audit-compliance-manager | v1.0.2 | 1.7 | Unified audit compliance — validates configs, detects gaps, remediates |
| coi-testing | v1.0.2 | 2.18, 2.11, 2.5 | Conflict of interest testing for agent recommendations |
| compliance-dashboard | v1.0.2 | 3.3, 3.1, 3.2 | Aggregated compliance reporting across 78 controls with Exchange coverage |
| conditional-access-automation | v1.2.1 | 1.11, 1.23, 1.18 | CA policy deployment, compliance monitoring, and drift detection |
| content-moderation-monitor | v1.0.3 | 1.8, 1.14 | Per-agent content moderation validation against zone requirements |
| copilot-studio-analytics | v1.1.1 | 3.2 | Business impact analytics for Copilot Studio agents |
| credential-oversharing-detector | v1.0.1 | 1.14, 1.4, 1.18 | Configuration-time credential scope governance for agent connectors |
| cross-solution-integration | v1.0.2 | 1.7, 1.23, 1.11, 3.8, 1.8, 1.14 | Wires Tier 2 solutions into Compliance Dashboard |
| cross-tenant-external-sharing-governance | v1.0.1 | 1.1, 1.18, 2.1, 2.8, 3.1, 1.11 | Three-layer cross-tenant access governance (tenant isolation, Entra CTA, agent shares) |
| deny-event-correlation-report | v2.0.1 | 1.5, 1.7, 1.8, 3.4 | Daily deny event correlation across Purview, DLP, and App Insights |
| dr-testing-framework | v1.2.1 | 2.4, 2.1, 1.9 | Automated disaster recovery testing for AI agents |
| environment-lifecycle-management | v1.1.3 | 2.1, 2.2, 2.3, 2.8, 1.7 | Automated environment provisioning with zone-based governance |
| file-upload-security | v1.0.2 | 1.14, 1.8, 1.4 | Per-agent file upload validation against zone governance policies |
| finra-supervision-workflow | v1.0.1 | 2.12, 1.10, 1.7 | Automated supervision queue for AI agent outputs (FINRA 3110) |
| generative-ai-config-auditor | v1.0.1 | 2.24 | GenAI feature enablement governance per zone |
| hallucination-tracker | v1.0.0 | 3.10, 2.9, 2.12 | Feedback aggregation for hallucination pattern analysis |
| hitl-workflow-governance | v1.0.1 | 2.12, 2.17, 1.10 | Zone-based governance for Human in the Loop checkpoints in Copilot Studio agent flows |
| inactivity-timeout-enforcement | v1.0.5 | 2.22, 1.23, 3.7, 3.8 | Policy-driven inactivity timeout validation with zone-based durations |
| message-center-monitor | v2.2.0 | 2.3, 2.10 | M365 Message Center monitoring for platform changes |
| model-risk-management-automation | v1.0.2 | 2.6, 2.5, 2.9, 2.11, 2.13, 3.1, 1.2 | OCC 2011-12 / SR 11-7 model risk management with inventory, risk scoring, validation workflows, and Agent Card generation |
| mime-type-restrictions | v1.0.2 | 1.5, 1.10, 1.11, 1.13, 1.14, 1.25, 3.3, 3.7, 4.3 | Zone-based MIME type configuration with server-side validation |
| pipeline-governance-cleanup | v1.1.0 | 2.3, 2.1 | Personal pipeline discovery and ALM governance enforcement |
| rag-source-validator | v1.1.1 | 2.16, 1.7, 2.13 | Integrity validation for RAG knowledge sources |
| scope-drift-monitor | v1.1.2 | 1.14, 1.4, 1.5 | Detect agent data access beyond declared scope |
| segregation-detector | v1.0.0 | 2.8, 2.1, 2.3 | Role conflict detection for Maker/Checker enforcement |
| session-security-configurator | v1.0.1 | 1.23, 1.11 | Session security validation per governance zone with drift detection |
| unrestricted-agent-sharing-detector | v1.0.2 | 1.1, 3.8 | Continuous detection of overly permissive agent sharing |

## Directory Structure

```
FSI-AgentGov-Solutions/
├── .claude/                   # Claude Code settings
├── .codex/                    # Codex CLI configuration
├── .github/
│   ├── copilot-instructions.md    # This file
│   └── instructions/              # Auto-included rules
├── scripts/
│   ├── hooks/                 # Claude Code hooks
│   └── shared/                # Shared utilities
│       ├── dataverse_client.py    # Shared Dataverse Web API client
│       └── Get-ZoneClassification.ps1  # Zone classification utility
├── {solution-name}/
│   ├── README.md              # Solution overview and setup
│   ├── CHANGELOG.md           # Version history
│   ├── docs/                  # Setup and configuration guides
│   ├── scripts/               # Automation scripts (PowerShell, Python, KQL)
│   └── templates/             # JSON samples, schemas
└── CHANGELOG.md
```

## Solution Content Policy (CRITICAL)

**Solutions must NOT contain Power Platform runtime artifacts** — no exported Power Automate flow JSON, Canvas app packages, connection references, or environment variable exports. Solutions provide only:
- **Documentation** — Step-by-step instructions for manually building flows/apps in Power Platform designer
- **Scripts** — PowerShell, Python, KQL for setup, governance, and monitoring
- **Templates** — JSON schemas and sample payloads (not exported flows)

If a `src/` directory exists with flow JSON files, replace it with documentation in `docs/`.

## Coding Patterns

### Dataverse Column Naming (CRITICAL)

Dataverse uses two names for every column:
- **SchemaName** (PascalCase with prefix): `fsi_AgentId`, `fsi_EnvironmentName`, `fsi_ViolationType`
- **Logical name** (all-lowercase, NO underscores between words): `fsi_agentid`, `fsi_environmentname`, `fsi_violationtype`

The logical name is the SchemaName lowercased. Dataverse NEVER inserts underscores between words.

**In PowerShell OData queries, scripts, and documentation, ALWAYS use the logical name:**
- CORRECT: `fsi_agentid`, `fsi_environmentname`, `fsi_violationtype`
- WRONG: `fsi_agent_id`, `fsi_environment_name`, `fsi_violation_type`

The single source of truth for column names is each solution's `create_*_dataverse_schema.py`. When in doubt, find the SchemaName there and lowercase it.

### PowerShell Scripts
- Use `#Requires -Modules` for dependencies
- Include `.SYNOPSIS`, `.DESCRIPTION`, `.PARAMETER`, `.EXAMPLE` in comment-based help
- Use `[CmdletBinding()]` with parameter validation
- Follow verb-noun naming: `Get-AgentComplianceStatus`, `Export-DenyEventReport`
- Use approved PowerShell verbs only

### Python Scripts
- Include docstrings for all public functions
- Use `argparse` for CLI interfaces
- Use `logging` module (not print) for operational output
- Type hints for function signatures

### KQL Queries
- Include comments explaining query logic
- Use `let` statements for reusable variables
- Parameterize time ranges

## Language Standards

**CRITICAL:** When writing documentation or comments:
- **NEVER use:** "ensures compliance", "guarantees", "will prevent", "eliminates risk"
- **ALWAYS use:** "supports compliance with", "helps meet", "required for", "recommended to"
- Include implementation caveats where appropriate
- Reference specific regulations by name and section

## Companion Repository

**FSI-AgentGov** (`/Users/admin/dev/FSI-AgentGov`) contains the governance framework:
- `docs/framework/` — Governance principles
- `docs/controls/` — 78 control specifications (10-section format)
- `docs/playbooks/` — Implementation guides referencing solutions here
- `docs/reference/solutions-index.md` — Complete solutions catalog
- `docs/framework/solutions-integration.md` — Framework-to-solutions mapping

When updating solution READMEs, ensure Related Controls sections match the control mappings in the catalog above.

## Validation

```bash
# Validate Python scripts
python -m py_compile scripts/hooks/*.py

# Validate PowerShell scripts (requires PowerShell)
pwsh -Command "Get-ChildItem -Recurse -Filter *.ps1 | ForEach-Object { [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$null) }"
```

## Site Design System

The documentation site uses a unified FSI design system shared across all FSI-AgentGov and FSI-CopilotGov repositories.

- **Theme:** MkDocs Material with `primary: custom` / `accent: custom` palette
- **Colors:** Microsoft Blue (`#0078D4`) primary, WCAG AA teal (`#007A7E`) accent, full dark mode tokens in `site-docs/stylesheets/extra.css`
- **Logo:** Shield + circuit motif SVG (`site-docs/assets/logo.svg`, `site-docs/assets/favicon.svg`)
- **Homepage pattern:** Hero section → metrics strip → role cards → architecture diagram (uses `hide: navigation, toc` frontmatter, `md_in_html` extension, `attr_list` for buttons)
- **Navigation:** `navigation.sections` is intentionally removed so sidebar sections collapse by default
- **Font:** `font: false` — avoids Google Fonts CDN (blocked in FSI network environments)
- **Extensions required:** `pymdownx.emoji` (icon shortcodes), `md_in_html` (hero/cards), `pymdownx.highlight` (code blocks)

When modifying the site theme, update `site-docs/stylesheets/extra.css` — do not change `primary`/`accent` in `mkdocs.yml` (they must stay `custom`).
