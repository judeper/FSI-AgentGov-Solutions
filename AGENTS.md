# AGENTS.md - Instructions for AI Agents

This file provides guidance for autonomous AI agents working on this repository. It is tool-neutral and readable by Codex CLI, GitHub Copilot, and Claude Code.

## Project Overview

**FSI-AgentGov-Solutions** — Deployable Power Platform solutions for the [FSI Agent Governance Framework](https://github.com/judeper/FSI-AgentGov). These solutions help Financial Services organizations implement operational controls and monitoring for AI agents (Copilot Studio, Agent Builder).

- **31 solutions** covering 40+ controls across all 4 pillars
- **Target regulations:** FINRA 4511/3110/25-07, SEC 17a-3/4, SOX 302/404, GLBA 501(b), OCC 2011-12, Fed SR 11-7, CFTC 1.31
- **Technologies:** PowerShell, Python, KQL, Dataverse (documentation-only for Power Automate — no exported flow artifacts)

**Companion Repository:** `FSI-AgentGov` (`/Users/admin/dev/FSI-AgentGov`) contains the governance framework documentation (71 controls, 284 playbooks, MkDocs site).

## Solution Catalog

| Solution | Version | Primary Controls | Description |
|----------|---------|-----------------|-------------|
| action-confirmation-auditor | v1.0.0 | 1.23 | Step-up confirmation validation for agent actions |
| agent-access-monitor | v1.0.0 | 3.8 | Automated detection of overly permissive agent access configurations |
| agent-communication-restriction-detector | v1.0.0 | 2.17 | Inter-agent communication restriction validation |
| agent-knowledge-source-scanner | v1.0.0 | 4.3, 1.4, 1.5 | Item-level permission scanning for agent knowledge source SharePoint libraries |
| agent-registry-automation | v1.0.0 | 1.2, 1.7, 2.1, 2.13 | Automated discovery, registration, approval, and lifecycle governance of AI agents |
| agent-observability-foundation | v1.1.0 | — | Foundational observability infrastructure for agent monitoring |
| agent-sharing-access-restriction-detector | v1.0.0 | 1.18, 2.8 | Zone-based agent sharing policy enforcement with approval workflows |
| audit-compliance-manager | v1.0.0 | 1.7 | Unified audit compliance — validates configs, detects gaps, remediates |
| coi-testing | v1.0.0 | 2.18, 2.11, 2.5 | Conflict of interest testing for agent recommendations |
| compliance-dashboard | v1.0.0 | 3.3, 3.1, 3.2 | Aggregated compliance reporting across 71 controls with Exchange coverage |
| conditional-access-automation | v1.1.0 | 1.11, 1.23, 1.18 | CA policy deployment, compliance monitoring, and drift detection |
| content-moderation-monitor | v1.0.0 | 1.8, 1.14 | Per-agent content moderation validation against zone requirements |
| copilot-studio-analytics | v1.0.0 | 3.2 | Business impact analytics for Copilot Studio agents |
| cross-solution-integration | v1.0.0 | 1.7, 1.23, 1.11, 3.8, 1.8, 1.14 | Wires Tier 2 solutions into Compliance Dashboard |
| cross-tenant-external-sharing-governance | v1.0.0 | 1.1, 1.18, 2.1, 2.8, 3.1, 1.11 | Three-layer cross-tenant access governance (tenant isolation, Entra CTA, agent shares) |
| deny-event-correlation-report | v2.0.0 | 1.5, 1.7, 1.8, 3.4 | Daily deny event correlation across Purview, DLP, and App Insights |
| dr-testing-framework | v1.0.0 | 2.4, 2.1, 1.9 | Automated disaster recovery testing for AI agents |
| environment-lifecycle-management | v1.1.2 | 2.1, 2.2, 2.3, 2.8, 1.7 | Automated environment provisioning with zone-based governance |
| file-upload-security | v1.0.0 | 1.14, 1.8, 1.4 | Per-agent file upload validation against zone governance policies |
| finra-supervision-workflow | v1.0.0 | 2.12, 1.10, 1.7 | Automated supervision queue for AI agent outputs (FINRA 3110) |
| generative-ai-config-auditor | v1.0.0 | 2.24 | GenAI feature enablement governance per zone |
| hallucination-tracker | v1.0.0 | 3.10, 2.9, 2.12 | Feedback aggregation for hallucination pattern analysis |
| inactivity-timeout-enforcement | v1.0.0 | 2.22, 1.23, 3.7, 3.8 | Policy-driven inactivity timeout validation with zone-based durations |
| message-center-monitor | v2.1.1 | 2.3, 2.10 | M365 Message Center monitoring for platform changes |
| model-risk-management-automation | v1.0.0 | 2.6, 2.5, 2.9, 2.11, 2.13, 3.1, 1.2 | OCC 2011-12 / SR 11-7 model risk management with inventory, risk scoring, validation workflows, and Agent Card generation |
| mime-type-restrictions| v1.0.0 | 1.5, 1.10, 1.11, 1.13, 1.14, 1.25, 3.3, 3.7, 4.3 | Zone-based MIME type configuration with server-side validation |
| pipeline-governance-cleanup | v1.0.8 | 2.3, 2.1 | Personal pipeline discovery and ALM governance enforcement |
| rag-source-validator | v1.0.0 | 2.16, 1.7, 2.13 | Integrity validation for RAG knowledge sources |
| scope-drift-monitor | v1.1.0 | 1.14, 1.4, 1.5 | Detect agent data access beyond declared scope |
| segregation-detector | v1.0.0 | 2.8, 2.1, 2.3 | Role conflict detection for Maker/Checker enforcement |
| session-security-configurator | v1.0.0 | 1.23, 1.11 | Session security validation per governance zone with drift detection |
| unrestricted-agent-sharing-detector | v1.0.2 | 1.1, 3.8 | Continuous detection of overly permissive agent sharing |

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
│   ├── hooks/                 # Claude Code hooks
│   └── shared/                # Shared utilities (see below)
│       ├── dataverse_client.py    # Shared Dataverse Web API client
│       └── Get-ZoneClassification.ps1  # Zone classification utility
├── {solution-name}/
│   ├── README.md              # Solution overview and setup
│   ├── CHANGELOG.md           # Version history
│   ├── docs/
│   │   ├── dataverse-schema.md    # Auto-generated from schema script
│   │   └── flow-configuration.md  # Manual build instructions for flows
│   └── scripts/
│       ├── create_{prefix}_dataverse_schema.py   # Schema definition + doc generation
│       ├── create_{prefix}_environment_variables.py
│       ├── create_{prefix}_connection_references.py
│       └── governance/            # Operational PowerShell scripts
└── CHANGELOG.md
```

### Shared Infrastructure (`scripts/shared/`)

| File | Purpose | Used By |
|------|---------|---------|
| `dataverse_client.py` | Dataverse Web API client with MSAL auth, retry logic, dry-run mode | All solutions with Dataverse tables |
| `Get-ZoneClassification.ps1` | Zone classification utility | ELM, conditional-access-automation |

**Schema-generated docs:** Each solution's `create_*_dataverse_schema.py` supports `--output-docs` to generate `docs/dataverse-schema.md`. This is the single source of truth for column names and option sets. Always regenerate after schema changes:
```bash
python scripts/create_{prefix}_dataverse_schema.py --output-docs
```

## Solution Content Policy (CRITICAL)

**Solutions must NOT contain Power Platform runtime artifacts.** This includes:
- Power Automate flow JSON definitions (exported `.json` flow files)
- Canvas app packages or specifications
- Connection reference definitions
- Environment variable JSON exports
- Any other exported Power Platform components

**Solutions MUST contain only:**
- **Documentation** — Step-by-step instructions for administrators to manually build flows, apps, and configurations in the Power Platform designer
- **Scripts** — PowerShell, Python, and KQL automation for setup, governance, and monitoring
- **Templates** — JSON schemas, sample payloads, and configuration examples (not exported flows)
- **README and docs/** — Architecture diagrams, prerequisites, and deployment guides

**Why:** Exported flow JSON files create cross-file reference bugs (action names, connection IDs, environment variable schema mismatches) that are fragile and difficult to validate. Manual instructions with documentation ensure administrators understand what they are building and can adapt to their environment.

**If a `src/` directory exists with flow JSON files**, it must be replaced with documentation in `docs/` that describes how to create the flow manually in Power Automate designer.

## Dataverse Column Naming (CRITICAL)

Dataverse uses two names for every column:
- **SchemaName** (PascalCase with prefix): `fsi_AgentId`, `fsi_EnvironmentName`, `fsi_ViolationType`
- **Logical name** (all-lowercase, NO underscores between words): `fsi_agentid`, `fsi_environmentname`, `fsi_violationtype`

The logical name is the SchemaName lowercased. Dataverse NEVER inserts underscores between words.

**In PowerShell OData queries, scripts, and documentation, ALWAYS use the logical name:**
- CORRECT: `fsi_agentid`, `fsi_environmentname`, `fsi_violationtype`
- WRONG: `fsi_agent_id`, `fsi_environment_name`, `fsi_violation_type`

The single source of truth for column names is each solution's `create_*_dataverse_schema.py`. When in doubt, find the SchemaName there and lowercase it.

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

### Codex CLI Model Selection

Pick the cheapest model that can hold the relevant context in one pass and will not invent control IDs, file paths, or implementation steps. Three named profiles are defined in `.codex/config.toml`:

| Profile | Model | Reasoning | Use When |
|---------|-------|-----------|----------|
| `budget` | gpt-5.1-codex-mini | low | Script edits, README updates within one solution |
| *(default)* | gpt-5.1-codex | high | New solution folder following existing pattern |
| `quality` | gpt-5.3-codex | xhigh | Solution spanning multiple admin domains or controls |

Activate with `codex --profile budget` or `codex --profile quality`. The default (no flag) uses gpt-5.1-codex.

**Workflow:**
1. Run a "plan-only" prompt first — get the file list and diff outline before generating changes
2. Simple patches (1–2 files): `codex --profile budget`; multi-file: use the default
3. One solution per commit for reviewable diffs
4. Validate after each change set; escalate to `--profile quality` when failures need cross-file reasoning

> **Note:** Profiles control the LLM model and reasoning effort. GSD model profiles (`quality`/`balanced`/`budget`) control workflow behavior, not the underlying LLM. They are complementary.

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
