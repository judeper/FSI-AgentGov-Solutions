# FSI-AgentGov-Solutions

## Purpose

Reference implementations for the [FSI Agent Governance Framework](https://judeper.github.io/FSI-AgentGov/).
These solutions help Financial Services organizations implement operational controls and monitoring for AI agents (Copilot Studio, Agent Builder).

## Companion Repository

**FSI-AgentGov** (`/Users/admin/dev/FSI-AgentGov`) contains the governance framework documentation:
- `docs/framework/` - Governance principles
- `docs/controls/` - 62 control specifications
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

## Solutions

| Solution | Description | Type | Version |
|----------|-------------|------|---------|
| [environment-lifecycle-management](./environment-lifecycle-management/) | Automated Power Platform environment provisioning with zone-based governance | Python/Power Automate | v1.0.1 |
| [message-center-monitor](./message-center-monitor/) | M365 Message Center monitoring for platform changes | Power Automate/Dataverse | v2.0.0 |
| [pipeline-governance-cleanup](./pipeline-governance-cleanup/) | Discover, notify, clean up personal pipelines | PowerShell/Manual | v1.0.7 |
| [deny-event-correlation-report](./deny-event-correlation-report/) | Daily deny event correlation across Purview, DLP, App Insights | PowerShell/KQL | v1.0.0 |

## Control Implementations

| Solution | Primary Controls | Description |
|----------|-----------------|-------------|
| environment-lifecycle-management | 2.1, 2.2, 2.3, 2.8, 1.7 | Environment provisioning with zone-based governance |
| message-center-monitor | 2.3, 2.10 | M365 Message Center platform change monitoring |
| pipeline-governance-cleanup | 2.3, 2.1 | Personal pipeline cleanup and ALM governance |
| deny-event-correlation-report | 1.5, 1.7, 3.4 | Deny event correlation across Purview and App Insights |

When updating solution READMEs, ensure Related Controls sections match these mappings.

## Directory Structure

```
FSI-AgentGov-Solutions/
├── .claude/
│   ├── settings.json          # Team-shared settings
│   └── settings.local.json    # Local overrides (not committed)
├── scripts/
│   └── hooks/                  # Claude Code hooks (root-level)
├── environment-lifecycle-management/
│   ├── docs/                   # Setup and configuration guides
│   ├── scripts/                # Python automation (SP registration, evidence export)
│   └── templates/              # JSON samples, Copilot output schema
├── message-center-monitor/
├── pipeline-governance-cleanup/
│   └── scripts/hooks/          # Standalone pass-through hooks (intentionally different)
└── deny-event-correlation-report/
```

## Hooks

| Hook | Location | Purpose |
|------|----------|---------|
| `scripts/hooks/boundary-check.py` | Root | Full boundary checking with cross-repo access |
| `scripts/hooks/researcher-package-reminder.py` | Root | Reminder for FSI-AgentGov package regeneration |
| `pipeline-governance-cleanup/scripts/hooks/*` | Nested | Simple pass-throughs for standalone use |

**Note:** The nested hooks in `pipeline-governance-cleanup/scripts/hooks/` are intentionally different from root hooks. They allow all commands when that solution is used standalone.

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
