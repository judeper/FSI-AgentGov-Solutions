# AGENTS.md - Instructions for AI Agents

This file provides guidance for autonomous AI agents working on this repository. It is tool-neutral and readable by Codex CLI, GitHub Copilot, and Claude Code.

## Project Overview

**FSI-AgentGov-Solutions** — Deployable Power Platform solutions for the [FSI Agent Governance Framework](https://github.com/judeper/FSI-AgentGov). These solutions help Financial Services organizations implement operational controls and monitoring for AI agents (Copilot Studio, Agent Builder).

- **16 solutions** covering 28+ controls across all 4 pillars
- **Target regulations:** FINRA 4511/3110/25-07, SEC 17a-3/4, SOX 302/404, GLBA 501(b), OCC 2011-12, Fed SR 11-7, CFTC 1.31
- **Technologies:** PowerShell, Python, Power Automate, KQL, Dataverse

**Companion Repository:** `FSI-AgentGov` (`/Users/admin/dev/FSI-AgentGov`) contains the governance framework documentation (71 controls, 284 playbooks, MkDocs site).

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
├── .claude/
│   ├── settings.json          # Team-shared settings
│   └── settings.local.json    # Local overrides (not committed)
├── .codex/
│   └── config.toml            # Codex CLI configuration
├── .github/
│   ├── copilot-instructions.md    # GitHub Copilot context
│   └── instructions/              # Auto-included instruction files
├── scripts/
│   └── hooks/                 # Claude Code hooks
├── {solution-name}/
│   ├── README.md              # Solution overview and setup
│   ├── docs/                  # Setup and configuration guides
│   ├── scripts/               # Automation scripts
│   └── templates/             # JSON samples, schemas
└── CHANGELOG.md
```

## Before Making Changes

1. **Read the solution's README** for prerequisites and architecture
2. **Check Related Controls** — ensure control mappings match the catalog above
3. **Check session ownership** — see Multi-Agent Coordination below

## Multi-Agent Coordination

Three tools operate on this repository:

| Tool | Primary Role | Config Location |
|------|-------------|-----------------|
| **Codex CLI** | Script generation | `.codex/config.toml` |
| **GitHub Copilot** | Code assistance | `.github/copilot-instructions.md` |
| **Claude Code** | Verification, cross-repo work | `.claude/settings.json` |

### Session Ownership Protocol

Only one tool writes to shared state files at a time.

**Rules:**
- Whichever tool starts a session owns writes for that session
- Both tools can always **read** all files
- Handoff requires the current owner to document the state before the other tool begins

**Handoff format:**
```markdown
**Active Tool:** copilot | claude-code | codex
**Session Started:** YYYY-MM-DD HH:MM
**Handoff Summary:** [What was done, what's next]
```

## Cross-Repository Workflow

**Primary Working Directory:** FSI-AgentGov (documentation repo)
- Has MkDocs, comprehensive context, and skills
- Boundary hooks allow access to this Solutions repo

**Git Operations:**
Each repo has separate git history. Always verify your working directory before git commands:
```bash
git rev-parse --show-toplevel
```

**When working from FSI-AgentGov on Solutions files:**
```bash
cd /Users/admin/dev/FSI-AgentGov-Solutions
git add <specific-files>
git commit -m "message"
cd -  # return to previous directory
```

**Commit order for cross-repo changes:**
1. Commit FSI-AgentGov-Solutions changes first (scripts/implementations)
2. Commit FSI-AgentGov changes second (documentation)
3. Use cross-references in commit messages when related

## Language Guidelines

When writing documentation in this repository:
- **NEVER use:** "ensures compliance", "guarantees", "will prevent", "eliminates risk"
- **ALWAYS use:** "supports compliance with", "helps meet", "required for", "recommended to", "aids in"
- Include caveats about implementation requirements
- Reference specific regulations by name and section (e.g., "FINRA Rule 4511(a)")

**Full guidelines:** See FSI-AgentGov `CONTRIBUTING.md` and `.github/instructions/fsi-language-rules.instructions.md`

## Validation Commands

```bash
# Validate Python scripts
python -m py_compile scripts/hooks/*.py

# Validate PowerShell scripts (requires PowerShell)
pwsh -Command "Get-ChildItem -Recurse -Filter *.ps1 | ForEach-Object { [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$null, [ref]$null) }"
```

## Files to Never Modify Without Permission

- `LICENSE` — Legal file

## Tool-Specific Configuration

| Tool | Config | Details |
|------|--------|---------|
| **Claude Code** | `CLAUDE.md` | Project context, cross-repo workflow |
| **Codex CLI** | `.codex/config.toml` | Model, sandbox, approval policy |
| **Copilot** | `.github/copilot-instructions.md` | Repository context for Copilot |
| **Copilot Instructions** | `.github/instructions/` | Auto-included rules by file path |

### Copilot Tool Alias Notes

GitHub Copilot's recognized built-in aliases are: `read`, `edit`, `search`, `execute`, `agent`, `web`, `todo`. Unrecognized names are silently ignored (falling back to unrestricted access).

**Platform differences:** The `web` and `todo` aliases are supported in VS Code Copilot Chat but are currently not applicable to the GitHub.com Copilot coding agent. This repo does not define custom Copilot agents or prompts — agent workflows are orchestrated from FSI-AgentGov using cross-repo edits.
