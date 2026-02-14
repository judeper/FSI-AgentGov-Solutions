# FSI-AgentGov-Solutions Repository Instructions

## Project Overview

Deployable Power Platform solutions for the [FSI Agent Governance Framework](https://github.com/judeper/FSI-AgentGov). These solutions help Financial Services organizations implement operational controls and monitoring for AI agents (Copilot Studio, Agent Builder).

- **25 solutions** covering 28+ controls across all 4 pillars
- **Target regulations:** FINRA 4511/3110/25-07, SEC 17a-3/4, SOX 302/404, GLBA 501(b), OCC 2011-12, Fed SR 11-7, CFTC 1.31
- **Technologies:** PowerShell, Python, Power Automate, KQL, Dataverse
- **Audience:** M365 administrators and DevOps engineers in US financial services

## Solution Catalog

| Solution | Version | Primary Controls | Description |
|----------|---------|-----------------|-------------|
| environment-lifecycle-management | v1.1.2 | 2.1, 2.2, 2.3, 2.8, 1.7 | Automated environment provisioning with zone-based governance |
| message-center-monitor | v2.1.1 | 2.3, 2.10 | M365 Message Center monitoring for platform changes |
| pipeline-governance-cleanup | v1.0.8 | 2.3, 2.1 | Personal pipeline discovery and ALM governance enforcement |
| deny-event-correlation-report | v1.1.0 | 1.5, 1.7, 3.4 | Daily deny event correlation across Purview and App Insights |
| finra-supervision-workflow | v1.0.0 | 2.12, 1.10, 1.7 | Automated supervision queue for AI agent outputs (FINRA 3110) |
| conditional-access-automation | v1.0.0 | 1.11, 1.23, 1.18 | CA policy deployment and compliance monitoring for AI workloads |
| compliance-dashboard | v1.0.0-beta | 3.3, 3.1, 3.2 | Aggregated compliance reporting across 71 controls |
| segregation-detector | v1.0.0 | 2.8, 2.1, 2.3 | Role conflict detection for Maker/Checker enforcement |
| scope-drift-monitor | v1.0.0 | 1.14, 1.4, 1.5 | Detect agent data access beyond declared scope |
| rag-source-validator | v1.0.0 | 2.16, 1.7, 2.13 | Integrity validation for RAG knowledge sources |
| coi-testing | v1.0.0 | 2.18, 2.11, 2.5 | Conflict of interest testing for agent recommendations |
| hallucination-tracker | v1.0.0 | 3.10, 2.9, 2.12 | Feedback aggregation for hallucination pattern analysis |
| dr-testing-framework | v1.0.0 | 2.4, 2.1, 1.9 | Automated disaster recovery testing for AI agents |

## Directory Structure

```
FSI-AgentGov-Solutions/
├── .claude/                   # Claude Code settings
├── .codex/                    # Codex CLI configuration
├── .github/
│   ├── copilot-instructions.md    # This file
│   └── instructions/              # Auto-included rules
├── scripts/
│   └── hooks/                 # Claude Code hooks
├── {solution-name}/
│   ├── README.md              # Solution overview and setup
│   ├── docs/                  # Setup and configuration guides
│   ├── scripts/               # Automation scripts (PowerShell, Python, KQL)
│   └── templates/             # JSON samples, schemas
└── CHANGELOG.md
```

## Coding Patterns

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
- `docs/controls/` — 71 control specifications (10-section format)
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
