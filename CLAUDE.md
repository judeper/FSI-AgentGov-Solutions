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
| [action-confirmation-auditor](./action-confirmation-auditor/) | HITL confirmation step validation in Copilot Studio agent topics | PowerShell/Python | v1.1.0 |
| [agent-intake](./agent-intake/) | Pre-build maker intake (Express + Standard + Full paths) with sponsor 1-click approval, parallel reviewer quorum, MRM handoff, and Entra Agent ID minting | PowerShell/Python/Docs | v1.0.0-preview |
| [agent-365-lifecycle-governance](./agent-365-lifecycle-governance/) | Automated lifecycle governance for AI agents using Agent 365 and Entra ID Governance | PowerShell/Python | v1.1.3 |
| [agent-access-monitor](./agent-access-monitor/) | Automated detection of overly permissive agent access configurations | PowerShell/Python | v1.1.0 |
| [agent-communication-restriction-detector](./agent-communication-restriction-detector/) | Detects unauthorized agent-to-agent communication patterns, zone boundary violations, cross-tenant communication, and maker/checker violations in Copilot Studio multi-agent orchestration | PowerShell/Python | v1.2.1 |
| [agent-knowledge-source-scanner](./agent-knowledge-source-scanner/) | Item-level permission scanning for agent knowledge source SharePoint libraries | PowerShell | v1.1.0 |
| [agent-observability-foundation](./agent-observability-foundation/) | Foundational observability infrastructure for agent monitoring and diagnostics | KQL/Docs | v1.2.2 |
| [agent-registry-automation](./agent-registry-automation/) | Automated discovery, registration, approval, and lifecycle governance of AI agents | PowerShell/Python | v2.0.0 |
| [agent-sharing-access-restriction-detector](./agent-sharing-access-restriction-detector/) | Zone-based agent sharing policy enforcement with approval workflows | PowerShell/Python | v2.0.0 |
| [audit-compliance-manager](./audit-compliance-manager/) | Unified audit compliance — validates configs, detects gaps, remediates | PowerShell/Python | v1.0.3 |
| [coi-testing](./coi-testing/) | Conflict of interest testing for agent recommendations | Python/Docs | v1.1.0 |
| [compliance-dashboard](./compliance-dashboard/) | Aggregated compliance reporting across 78 controls with Exchange coverage | Docs/Dataverse | v1.0.5 |
| [conditional-access-automation](./conditional-access-automation/) | CA policy deployment, compliance monitoring, and drift detection | PowerShell/Python | v1.2.2 |
| [content-moderation-monitor](./content-moderation-monitor/) | Per-agent content moderation validation against zone requirements | PowerShell/Python | v1.1.2 |
| [copilot-studio-analytics](./copilot-studio-analytics/) | Business impact analytics for Copilot Studio agents (Viva Insights alternative) | Python/KQL | v2.0.0 |
| [credential-oversharing-detector](./credential-oversharing-detector/) | Configuration-time credential scope governance for agent connectors | PowerShell/Python | v2.0.0 |
| [cross-solution-integration](./cross-solution-integration/) | Wires Tier 2 solutions into Compliance Dashboard with unified evidence export | Python/Docs | v2.0.0 |
| [cross-tenant-external-sharing-governance](./cross-tenant-external-sharing-governance/) | Three-layer cross-tenant access governance (tenant isolation, Entra CTA, agent shares) | PowerShell/Python | v1.1.0 |
| [deny-event-correlation-report](./deny-event-correlation-report/) | Daily deny event correlation across Purview, DLP, App Insights | PowerShell/KQL | v2.0.2 |
| [dr-testing-framework](./dr-testing-framework/) | Automated disaster recovery testing for AI agent infrastructure | PowerShell/Python | v2.0.0 |
| [environment-lifecycle-management](./environment-lifecycle-management/) | Power Platform environment provisioning with zone-based governance | Python/Docs | v1.2.2 |
| [file-upload-security](./file-upload-security/) | Per-agent file upload validation against zone governance policies | PowerShell/Python | v1.1.0 |
| [finra-supervision-workflow](./finra-supervision-workflow/) | Automated supervision queue for AI agent outputs (FINRA 3110) | PowerShell/Docs | v1.0.1 |
| [generative-ai-config-auditor](./generative-ai-config-auditor/) | GenAI feature configuration validation per zone governance policy | PowerShell/Python | v1.2.1 |
| [hallucination-tracker](./hallucination-tracker/) | Feedback aggregation for hallucination pattern analysis | Python/Docs | v1.1.0 |
| [hitl-workflow-governance](./hitl-workflow-governance/) | Zone-based governance for Human in the Loop checkpoints in Copilot Studio agent flows | PowerShell/Python | v1.1.2 |
| [inactivity-timeout-enforcement](./inactivity-timeout-enforcement/) | Policy-driven inactivity timeout validation with zone-based durations | PowerShell/Python | v1.1.0 |
| [message-center-monitor](./message-center-monitor/) | M365 Message Center monitoring for platform changes | Docs/Dataverse | v2.5.1 |
| [mime-type-restrictions](./mime-type-restrictions/) | Zone-based MIME type configuration with server-side validation | PowerShell/Python | v1.1.0 |
| [model-risk-management-automation](./model-risk-management-automation/) | OCC 2011-12 / SR 11-7 model risk management with inventory, risk scoring, validation workflows, and Agent Card generation | PowerShell/Python | v1.0.2 |
| [pipeline-governance-cleanup](./pipeline-governance-cleanup/) | Discover, notify, clean up personal pipelines | PowerShell/Manual | v1.2.0 |
| [rag-source-validator](./rag-source-validator/) | Integrity validation for RAG knowledge sources with change detection | Python/Docs | v1.2.0 |
| [scope-drift-monitor](./scope-drift-monitor/) | Detect agent data access beyond declared operational scope | PowerShell/Python | v1.2.0 |
| [segregation-detector](./segregation-detector/) | Role conflict detection for Maker/Checker enforcement in agent pipelines | PowerShell/Python | v1.1.0 |
| [session-security-configurator](./session-security-configurator/) | Session security validation per governance zone with drift detection | PowerShell/Python | v1.3.0 |
| [unrestricted-agent-sharing-detector](./unrestricted-agent-sharing-detector/) | Continuous detection of overly permissive agent sharing with automated remediation | PowerShell/Python | v2.0.0 |

## Control Implementations

| Solution | Primary Controls | Description |
|----------|-----------------|-------------|
| action-confirmation-auditor | 2.12, 1.10 | HITL confirmation node validation in Copilot Studio agent topics; FINRA 3110 supervision evidence |
| agent-intake | 1.2, 1.7, 2.1, 2.13, 3.1 | Pre-build maker intake (Express + Standard + Full paths) with sponsor 1-click approval, parallel reviewer quorum, MRM handoff, and Entra Agent ID minting |
| agent-365-lifecycle-governance | 2.3, 1.2, 1.11, 2.1, 2.8, 2.12, 3.1 | Agent lifecycle governance with sponsor enforcement and access reviews |
| agent-access-monitor | 3.8 | Overly permissive agent access detection per governance zone |
| agent-communication-restriction-detector | 2.17 | Multi-agent orchestration limits per zone routing policy |
| agent-knowledge-source-scanner | 4.3, 1.4, 1.5 | Item-level permission scanning for agent knowledge source libraries |
| agent-observability-foundation | 1.7, 2.8, 2.9, 3.2 | Foundational observability infrastructure |
| agent-registry-automation | 1.2, 1.7, 2.1, 2.13 | Automated discovery, registration, approval, and lifecycle governance |
| agent-sharing-access-restriction-detector | 1.18, 2.8 | Zone-based sharing policy enforcement |
| audit-compliance-manager | 1.7 | Audit configuration validation and gap remediation |
| coi-testing | 2.18, 2.11, 2.5 | Conflict of interest testing for agent recommendations |
| compliance-dashboard | 3.3, 3.1, 3.2, 3.4 | Aggregated compliance reporting with Exchange coverage |
| conditional-access-automation | 1.11, 1.23, 1.18 | CA policy deployment and drift detection |
| content-moderation-monitor | 1.27, 1.8 | Content moderation validation against zone requirements |
| copilot-studio-analytics | 3.2 | Business impact analytics and session outcome monitoring |
| credential-oversharing-detector | 1.14, 1.4, 1.18 | Configuration-time credential scope governance for agent connectors |
| cross-solution-integration | 1.7, 1.23, 1.11, 3.8, 1.8, 1.14 | Compliance Dashboard integration and evidence export |
| cross-tenant-external-sharing-governance |  1.1, 1.18, 2.1, 2.8, 1.7, 1.11 | Three-layer cross-tenant access governance |
| deny-event-correlation-report | 1.5, 1.7, 1.8, 3.4 | Deny event correlation across Purview and App Insights |
| dr-testing-framework | 2.4, 2.1, 1.9 | Automated disaster recovery testing |
| environment-lifecycle-management | 2.1, 2.2, 2.8, 1.7 | Environment provisioning with zone-based governance |
| file-upload-security | 1.14, 1.8, 1.4 | File upload validation against zone governance policies |
| finra-supervision-workflow | 2.12, 1.10, 1.7 | Supervision queue for AI agent outputs (FINRA 3110) |
| generative-ai-config-auditor | 2.24 | GenAI feature enablement governance per zone |
| hallucination-tracker | 3.10, 2.9, 2.12 | Hallucination pattern analysis and feedback aggregation |
| hitl-workflow-governance | 2.12, 2.17, 1.10 | Zone-based HITL checkpoint governance for agent flows |
| inactivity-timeout-enforcement | 2.22, 1.23, 3.7, 3.8 | Inactivity timeout validation with zone-based durations |
| message-center-monitor | 2.3, 2.10 | M365 Message Center platform change monitoring |
| mime-type-restrictions | 1.5, 1.13, 1.25, 3.3, 3.7 | MIME type configuration with server-side validation |
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

## Per-Solution AGENTS.md (Context Cascade)

Some solutions carry a per-solution `AGENTS.md` at their root (e.g., `agent-intake/AGENTS.md`). When working on a solution that has one, **read it first** — it captures dev/AI-agent context: active development status, resume-on-new-machine workflow, auth quirks specific to that solution, pending polish items, and recent design decisions. Per-solution `AGENTS.md` files are **not** customer-facing (that's `README.md`); they exist so a new session or a new machine picks up exactly where the previous one left off.

Active per-solution `AGENTS.md` files:

- [`agent-intake/AGENTS.md`](agent-intake/AGENTS.md) — v1.0.0-preview · PR #142 open

When you add a per-solution `AGENTS.md`, list it here and link to it from the solution's README.

## Hooks

| Hook | Location | Purpose |
|------|----------|---------|
| `scripts/hooks/boundary-check.py` | Root | Full boundary checking with cross-repo access |
| `scripts/hooks/researcher-package-reminder.py` | Root | Reminder for FSI-AgentGov package regeneration |
| `pipeline-governance-cleanup/scripts/hooks/*` | Nested | Simple pass-throughs for standalone use |

**Note:** The nested hooks in `pipeline-governance-cleanup/scripts/hooks/` are intentionally different from root hooks. They allow all commands when that solution is used standalone.

## Per-solution AGENTS.md (opt-in convention)

Solutions with active in-flight work ship a `<solution>/AGENTS.md` that **adds
to this root file**. Loading order for any agent working in a solution folder:

1. This `CLAUDE.md` (and `AGENTS.md`, `.github/copilot-instructions.md`) — cross-cutting rules
2. `.github/instructions/*.md` — auto-included rules by file path
3. `<solution>/AGENTS.md` — solution-specific context + current operational state
4. `<solution>/.ralph-config.json` — machine-readable domain facts (column names, option-set values)

Solution-specific guidance wins only on solution-specific topics; cross-cutting
rules (FSI language, Dataverse naming, lab guards, commit conventions) always
apply. **Backfilling stable solutions with their own AGENTS.md is not
required** — the convention is opt-in when there's non-trivial state to hand off
across machines / sessions / agents.

Currently shipped: `message-center-monitor/AGENTS.md` (POC dry-run in progress).

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

## Docs Site Build Pipeline

The MkDocs site at https://judeper.github.io/FSI-AgentGov-Solutions/ is built in two steps by CI (`.github/workflows/publish_docs.yml`):

1. `python scripts/build-manifest.py` — reads each `<slug>/manifest.yaml` (canonical source of truth), validates against `scripts/manifest.schema.json` and the framework `controls.json` (pinned to `${{ vars.FRAMEWORK_REF || 'v1.4.0' }}` in CI), then emits `solutions.json` (repo root, schemaVersion **1.5.0**), the README solutions table (between `<!-- BEGIN:SOLUTIONS -->` markers), `site-docs/solutions/index.md`, every per-solution detail page at `site-docs/solutions/{slug}/index.md`, `site-docs/reference/control-mapping.md` (all 78 framework controls), the home-page hero metrics block, the deployment-guide `<!-- BEGIN:DEPLOY_LAYERS -->` and `<!-- BEGIN:ZONE_ROADMAP -->` blocks, and copies `{slug}/docs/*.md` with filename normalization (lowercase, hyphens).
2. `mkdocs build --strict` — renders the site from `site-docs/`.

A separate CI gate, `.github/workflows/manifest-check.yml`, runs `build-manifest.py --check` on every PR and fails when manifests reference unknown framework control IDs or generated artifacts drift.

### Continuous health monitoring

`.github/workflows/health-check.yml` runs every 30 minutes on a cron (and on demand via `gh workflow run health-check.yml`). It probes the published Pages URLs and the raw `solutions.json` at the **latest published GitHub release** (auto-derived via `gh api repos/{repo}/releases/latest --jq .tag_name`; see Issue #39), validates the lock file shape (count `>= MIN_SOLUTIONS` floor — currently 36, raise only when releasing intentional removals; non-empty `controls[]`; present `schemaVersion`), and **opens or comments on a GitHub issue titled "Health check failure: published artifacts not healthy" if anything fails**. No manual `LATEST_TAG` bump is required after a release.

**Critical:** `site-docs/solutions/*/` is **gitignored** and regenerated on every build. Manual edits to those files are discarded. Never edit under `site-docs/solutions/{slug}/` directly.

### To change overview pages

- **Description, version, domain, tier, controls, prerequisites, verification, status**: edit `<slug>/manifest.yaml` — this is the single source of truth. The schema is enforced by `scripts/manifest.schema.json`.
- **Layout / table structure**: edit `scripts/build-manifest.py`.

### To change detail-page sub-docs

Edit files under `{slug}/docs/`. `build-manifest.py` copies them into `site-docs/solutions/{slug}/` with filename normalization. Update `mkdocs.yml` nav when adding or removing detail pages.

### Schema evolution policy

`solutions.json` schema **1.5.0 (current)**. 1.5.0 made `zones` a **required** field on every solution entry — a breaking change from 1.4.x (which had introduced `zones` as optional in 1.4.2). The framework consumer in `judeper/fsi-agentgov` was widened ahead of this change to accept both 1.4.x and 1.5.x. Future field renames or new required fields require **1.6.0** with a coordinated `judeper/fsi-agentgov` update.

### Manifest fields

`<slug>/manifest.yaml` carries (schema in `scripts/manifest.schema.json`):

- **Required**: `id`, `name`, `description`, `version`, `domain`, `tier`, `controls[]`, `prerequisites[]`, `verification`, `status`.
- **Optional (1.4.2)**: `dataClassification` (`internal|confidential|restricted`), `dataResidency`, `retention`. Backfilled across all 36 solutions with sentinel comments pending product-team confirmation. (`zones` was optional in 1.4.2 and became **required** in 1.5.0.)

### Security and release CI

- **`gitleaks.yml`** — secret scanning on every push/PR.
- **`codeql.yml`** — Python CodeQL on push/PR/weekly cron (C# pending plugin `.csproj`).
- **`dependency-review.yml`** — GitHub-native dependency review on PRs.
- **`language-rules.yml`** — bans `ensures compliance` / `guarantees compliance` outside the rule-documenting files.
- **`odata-lint.yml` + `scripts/lint-odata-columns.py`** — narrow OData-context Dataverse-logical-name linter (soft-gate; flip to `--strict` after 5 known bugs in `conditional-access-automation` and `cross-solution-integration` are fixed).
- **`ci-python.yml`** — ruff + pytest (soft-gate).
- **`ci-powershell.yml`** — PSScriptAnalyzer + Pester (soft-gate).
- **`release.yml`** — on tag, builds source tarball + SPDX/CycloneDX SBOMs + SHA-256 manifest + GitHub build-provenance attestation, attaches to the GitHub Release.

See `SECURITY.md` for vulnerability disclosure and `THREAT-MODEL.md` for the STRIDE-by-asset model.

### To verify before committing

```bash
python scripts/build-manifest.py            # regenerate everything
python scripts/build-manifest.py --check    # exits non-zero if drift exists
python -m mkdocs build --strict             # fail on any broken link or missing nav file
```

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

## Council Review Notes (2026-04-16)

An autonomous dual-model council review (GPT-5.4 + Claude Opus 4.6) audited all 34 solutions and applied 189 fixes across 142 files. Key findings:

- **Dataverse column mismatches** are the #1 source of runtime bugs. Always verify OData column names against `create_*_dataverse_schema.py`.
- **`.ralph-config.json`** files now exist in 14 solutions (6 pre-existing + 8 new) containing domain facts about correct column names, entity set names, and platform constraints. Read these before editing any solution.
- **Option set values** in flow docs must use integer values (100000000+), not 0/1/2/3. Multiple solutions had this error.
- **"Azure AD"** branding was found in ~60 files. Always use "Microsoft Entra ID" — the only acceptable legacy reference is in CHANGELOG historical entries.
- **PnP.PowerShell** cmdlets were renamed: `Get-PnPAzureADGroupMember` → `Get-PnPEntraIDGroupMember` in PnP 3.x.
