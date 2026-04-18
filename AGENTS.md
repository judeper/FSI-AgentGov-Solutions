# AGENTS.md - Instructions for AI Agents

This file provides guidance for autonomous AI agents working on this repository. It is tool-neutral and readable by Codex CLI, GitHub Copilot, and Claude Code.

## Project Overview

**FSI-AgentGov-Solutions** — Deployable Power Platform solutions for the [FSI Agent Governance Framework](https://github.com/judeper/FSI-AgentGov). These solutions help Financial Services organizations implement operational controls and monitoring for AI agents (Copilot Studio, Agent Builder).

- **35 live solution implementations** mapped to the 78-control framework across all 4 pillars
- **Target regulations:** FINRA 4511/3110/25-07, SEC 17a-3/4, SOX 302/404, GLBA 501(b), OCC 2011-12, Fed SR 11-7, CFTC 1.31
- **Technologies:** PowerShell, Python, KQL, Dataverse (documentation-only for Power Automate — no exported flow artifacts)

**Companion Repository:** `FSI-AgentGov` (`/Users/admin/dev/FSI-AgentGov`) contains the governance framework documentation (78 controls, 312 playbooks, MkDocs site).

## Solution Catalog

| Solution | Version | Primary Controls | Description |
|----------|---------|-----------------|-------------|
| action-confirmation-auditor | v1.1.0 | 2.12, 1.10 | HITL confirmation step validation in Copilot Studio agent topics |
| agent-365-lifecycle-governance | v1.1.3 | 2.3, 1.2, 1.11, 2.1, 2.8, 2.12, 3.1 | Automated lifecycle governance for AI agents using Agent 365 and Entra ID Governance |
| agent-access-monitor | v1.1.0 | 3.8 | Automated detection of overly permissive agent access configurations |
|  | 2.17 | Inter-agent communication restriction validation |
| agent-knowledge-source-scanner | v1.1.0 | 4.3, 1.4, 1.5 | Item-level permission scanning for agent knowledge source SharePoint libraries |
| agent-registry-automation | v2.0.0 | 1.2, 1.7, 2.1, 2.13 | Automated discovery, registration, approval, and lifecycle governance of AI agents |
| agent-observability-foundation | v1.2.0 | 1.7, 2.8, 2.9, 3.2 | Foundational observability infrastructure for agent monitoring |
| agent-sharing-access-restriction-detector | v2.0.0 | 1.18, 2.8 | Zone-based agent sharing policy enforcement with approval workflows |
| audit-compliance-manager | v1.0.3 | 1.7 | Unified audit compliance — validates configs, detects gaps, remediates |
| coi-testing | v1.1.0 | 2.18, 2.11, 2.5 | Conflict of interest testing for agent recommendations |
| compliance-dashboard | v1.0.3 | 3.3, 3.1, 3.2, 3.4 | Aggregated compliance reporting across 78 controls with Exchange coverage |
| conditional-access-automation | v1.2.2 | 1.11, 1.23, 1.18 | CA policy deployment, compliance monitoring, and drift detection |
| content-moderation-monitor | v1.1.0 | 1.27, 1.8 | Per-agent content moderation validation against zone requirements |
| copilot-studio-analytics | v2.0.0 | 3.2 | Business impact analytics for Copilot Studio agents |
| credential-oversharing-detector | v2.0.0 | 1.14, 1.4, 1.18 | Configuration-time credential scope governance for agent connectors |
| cross-solution-integration | v2.0.0 | 1.7, 1.23, 1.11, 3.8, 1.8, 1.14 | Wires Tier 2 solutions into Compliance Dashboard |
| cross-tenant-external-sharing-governance | v1.0.2 |  1.1, 1.18, 2.1, 2.8, 1.7, 1.11 | Three-layer cross-tenant access governance (tenant isolation, Entra CTA, agent shares) |
| deny-event-correlation-report | v2.0.2 | 1.5, 1.7, 1.8, 3.4 | Daily deny event correlation across Purview, DLP, and App Insights |
| dr-testing-framework | v2.0.0 | 2.4, 2.1, 1.9 | Automated disaster recovery testing for AI agents |
| environment-lifecycle-management | v1.2.0 | 2.1, 2.2, 2.8, 1.7 | Automated environment provisioning with zone-based governance |
| file-upload-security | v1.1.0 | 1.14, 1.8, 1.4 | Per-agent file upload validation against zone governance policies |
| finra-supervision-workflow | v1.0.1 | 2.12, 1.10, 1.7 | Automated supervision queue for AI agent outputs (FINRA 3110) |
| generative-ai-config-auditor | v1.1.0 | 2.24 | GenAI feature enablement governance per zone |
| hallucination-tracker | v1.1.0 | 3.10, 2.9, 2.12 | Feedback aggregation for hallucination pattern analysis |
| hitl-workflow-governance | v1.1.0 | 2.12, 2.17, 1.10 | Zone-based governance for Human in the Loop checkpoints in Copilot Studio agent flows |
| inactivity-timeout-enforcement | v1.1.0 | 2.22, 1.23, 3.7, 3.8 | Policy-driven inactivity timeout validation with zone-based durations |
| message-center-monitor | v2.3.0 | 2.3, 2.10 | M365 Message Center monitoring for platform changes |
| model-risk-management-automation | v1.0.2 | 2.6, 2.5, 2.9, 2.11, 2.13, 3.1, 1.2 | OCC 2011-12 / SR 11-7 model risk management with inventory, risk scoring, validation workflows, and Agent Card generation |
| mime-type-restrictions | v1.1.0 | 1.5, 1.13, 1.25, 3.3, 3.7 | Zone-based MIME type configuration with server-side validation |
| pipeline-governance-cleanup | v1.2.0 | 2.3, 2.1 | Personal pipeline discovery and ALM governance enforcement |
| rag-source-validator | v1.2.0 | 2.16, 1.7, 2.13 | Integrity validation for RAG knowledge sources |
| scope-drift-monitor | v1.2.0 | 1.14, 1.4, 1.5 | Detect agent data access beyond declared scope |
| segregation-detector | v1.0.0 | 2.8, 2.1, 2.3 | Role conflict detection for Maker/Checker enforcement |
| session-security-configurator | v1.0.1 | 1.23, 1.11 | Session security validation per governance zone with drift detection |
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
│   ├── scripts/
│   │   ├── create_{prefix}_dataverse_schema.py   # Schema definition + doc generation
│   │   ├── create_{prefix}_environment_variables.py
│   │   ├── create_{prefix}_connection_references.py
│   │   └── governance/            # Operational PowerShell scripts
│   └── templates/             # JSON schemas, sample payloads, adaptive cards
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

## Creating a New Solution

Follow this checklist when creating a new solution folder:

1. **Create the directory structure:**
   ```
   {solution-name}/
   ├── README.md
   ├── CHANGELOG.md
   ├── docs/
   │   └── (dataverse-schema.md, flow-configuration.md, prerequisites.md, etc.)
   ├── scripts/
   │   └── (PowerShell .ps1, Python .py, or KQL .kql files)
   └── templates/
       └── (JSON schemas, sample payloads, adaptive card JSON)
   ```

2. **README.md must include:** Solution title, description, prerequisites, architecture overview, deployment steps, related controls section, and a link to the solution's CHANGELOG.

3. **CHANGELOG.md:** Follow [Keep a Changelog](https://keepachangelog.com/en/1.0.0/) format. Initial entry should be the solution version with an "Added" section.

4. **If the solution uses Dataverse tables:** Create `scripts/create_{prefix}_dataverse_schema.py` using the shared `dataverse_client.py`. Support `--output-docs` to auto-generate `docs/dataverse-schema.md`.

5. **If the solution involves Power Automate flows:** Write step-by-step manual build instructions in `docs/flow-configuration.md`. Do NOT include exported flow JSON.

6. **Adaptive card JSON** goes in `templates/`, not `src/` or `docs/`.

7. **Update all catalog files** — add the new solution to the tables in:
   - `README.md` (root)
   - `AGENTS.md`
   - `CLAUDE.md` (both Solutions and Control Implementations tables)
   - `.github/copilot-instructions.md`

8. **Commit convention:** One solution per commit. Use format: `feat({solution-name}): initial implementation vX.Y.Z`

## Version Bumping Process

When a solution is updated:

1. **Update the solution's `CHANGELOG.md`** with a new version entry (source of truth).
2. **Update the version in all 4 catalog files:**
   - `README.md` (root Solutions table)
   - `AGENTS.md` (Solution Catalog table)
   - `CLAUDE.md` (Solutions table)
   - `.github/copilot-instructions.md` (Solution Catalog table)
3. **Commit convention:** `fix({solution-name}): description` or `feat({solution-name}): description`

Version numbers follow [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`. Use `-preview` suffix for early-stage solutions (e.g., `v0.1.0-preview`).

## File Placement Rules

| File Type | Location | NOT Here |
|-----------|----------|----------|
| PowerShell scripts (.ps1) | `scripts/` or `scripts/governance/` | `src/` |
| Python scripts (.py) | `scripts/` | `src/` |
| KQL queries (.kql) | `scripts/` or `kql-queries/` | `src/` |
| Adaptive card JSON | `templates/` | `src/` |
| JSON schemas and sample payloads | `templates/` | `src/` |
| Flow build instructions | `docs/flow-configuration.md` | `src/` (no exported flow JSON) |
| Dataverse schema docs | `docs/dataverse-schema.md` (auto-generated) | — |
| C# plugins or custom code | `src/` (allowed for actual source code) | — |
| Dataverse solution packages | Not allowed — replace with `docs/` instructions | `src/` |
| Root-level documentation | `docs/` subfolder | Solution root (except README, CHANGELOG) |

**Key rule:** `src/` is only acceptable for actual compilable source code (e.g., C# Dataverse plugins). Exported Power Platform artifacts, flow JSON, connection references, environment variable exports, and Dataverse solution packages must NOT be in `src/`.

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

## Council Review Lessons Learned (2026-04-16)

An autonomous multi-agent council review (GPT-5.4 + Claude Opus 4.6) audited all 34 solutions. Key patterns discovered:

### Common Issues Found Across Solutions

1. **Dataverse Column Name Mismatches** — The most common critical issue. Scripts and flow docs frequently reference column names that don't match the schema defined in `create_*_dataverse_schema.py`. Common patterns:
   - `fsi_scantime` vs `fsi_validationtime` (scan timestamp column name varies by solution)
   - Entity set name pluralization (`fsi_actionscanruns` vs `fsi_actionscanrun`)
   - Snake_case in docs (`fsi_compliance_status`) that should be logical name (`fsi_compliancestatus`)
   - **Rule:** Always verify column names against `create_*_dataverse_schema.py` before writing OData queries

2. **"Azure AD" Product Naming** — Found in ~60 files across ~20 solutions. Most common in Python `argparse` help text (`help="Azure AD tenant ID"`) and PowerShell `.PARAMETER` descriptions.

3. **Compliance Language Violations** — "ensures", "guarantees", "enforces" found in ~25 locations across ~15 solutions. Most common in SOLUTION-DOCUMENTATION.md files, flow-configuration.md, and README feature descriptions.

4. **Flow Documentation Column Drift** — Flow build instructions in `docs/flow-configuration.md` frequently reference columns that don't exist in the deployed schema. This appears to happen when flow docs are written from design specs rather than validated against the schema script.

5. **Option Set Value Confusion** — Documentation shows picklist values as 0/1/2/3 but actual Dataverse option sets use 100000000/100000001/etc. Flow builders following docs create broken OData filters.

### `.ralph-config.json` Pattern

The council review created `.ralph-config.json` files for 8 solutions to capture domain-specific facts that would be lost between sessions. These files contain a `domainFacts` array with free-text entries about:
- Correct column names and entity set names
- Known design decisions and intentional behaviors
- Platform compatibility constraints
- API versioning notes

**When creating or editing a solution**, always check for `.ralph-config.json` first and read its domain facts before making changes.

### Validation Priority for Future Reviews

1. Run `create_*_dataverse_schema.py --output-docs` to regenerate schema docs
2. Grep for "Azure AD" (should be zero hits outside CHANGELOG historical entries)
3. Grep for "ensures|guarantees|will prevent|eliminates risk" in *.md files
4. Compare script `$select`/`$filter` columns against schema definitions
5. Verify option set values in flow docs match `create_*_dataverse_schema.py`
