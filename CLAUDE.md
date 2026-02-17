# FSI-AgentGov-Solutions

## Purpose

Reference implementations for the [FSI Agent Governance Framework](https://judeper.github.io/FSI-AgentGov/).
These solutions help Financial Services organizations implement operational controls and monitoring for AI agents (Copilot Studio, Agent Builder).

## Companion Repository

**FSI-AgentGov** (`/Users/admin/dev/FSI-AgentGov`) contains the governance framework documentation:
- `docs/framework/` - Governance principles
- `docs/controls/` - 71 control specifications
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
| [environment-lifecycle-management](./environment-lifecycle-management/) | Power Platform environment provisioning with zone-based governance | Python/Docs | v1.0.1 |
| [message-center-monitor](./message-center-monitor/) | M365 Message Center monitoring for platform changes | Docs/Dataverse | v2.0.0 |
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
│   ├── hooks/                  # Claude Code hooks (root-level)
│   └── shared/                 # Shared utilities
│       ├── dataverse_client.py     # Shared Dataverse Web API client (MSAL, retry, dry-run)
│       └── Get-ZoneClassification.ps1
├── {solution-name}/
│   ├── docs/
│   │   ├── dataverse-schema.md     # Auto-generated (python create_*_schema.py --output-docs)
│   │   └── flow-configuration.md   # Manual build instructions
│   └── scripts/                # Python setup + PowerShell governance
└── ...
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
