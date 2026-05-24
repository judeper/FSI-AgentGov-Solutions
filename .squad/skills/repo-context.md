# FSI-AgentGov-Solutions — Repo Context

> Shared facts for all OceanSquad agents working in this repo.

## What This Repo Is
Companion solutions repository for the FSI Agent Governance Framework (`judeper/FSI-AgentGov`). Contains 36 Power Platform / Dataverse solutions that implement the framework's controls. Each solution lives in its own directory with scripts, docs, templates, and a `manifest.yaml`.

## Architecture

### Solution Structure (per solution)
```
<solution-name>/
  manifest.yaml          # ID, name, version, status, domain, controls, zones
  README.md              # Solution documentation
  CHANGELOG.md           # Version history
  docs/                  # Detailed docs
  scripts/               # Python + PowerShell automation
    create_*_dataverse_schema.py   # Dataverse table/column definitions (yen)
    create_*_connection_references.py
    create_*_environment_variables.py
    *_client.py           # Solution-specific Dataverse client
    *.ps1                 # PowerShell collectors/validators
  templates/             # ARM/Bicep/Power Automate templates (some solutions)
```

### Shared Infrastructure
- `scripts/shared/dataverse_client.py` — Base `DataverseClient` class (all solutions inherit)
- `scripts/build-manifest.py` — Build consolidated manifest from per-solution `manifest.yaml`
- `scripts/lint-odata-columns.py` — OData logical-name linter (CI enforced)
- `scripts/lint-odata-existence.py` — OData entity existence checker
- `overrides/` — Solution-level CI config overrides
- `site-docs/` — MkDocs documentation site source
- `coi-testing/` — Conflict-of-interest testing solution

### 6 Domains
| Domain | Solutions |
|--------|-----------|
| `access-identity` | agent-access-monitor, conditional-access-automation, credential-oversharing-detector, segregation-detector |
| `agent-config` | action-confirmation-auditor, agent-communication-restriction-detector, agent-intake, agent-knowledge-source-scanner, agent-registry-automation, agent-sharing-access-restriction-detector, generative-ai-config-auditor, unrestricted-agent-sharing-detector |
| `compliance-audit` | audit-compliance-manager, finra-supervision-workflow, hitl-workflow-governance |
| `content-data` | content-moderation-monitor, file-upload-security, hallucination-tracker, mime-type-restrictions, rag-source-validator |
| `lifecycle-ops` | agent-365-lifecycle-governance, environment-lifecycle-management, pipeline-governance-cleanup, scope-drift-monitor |
| `monitoring-analytics` | agent-observability-foundation, compliance-dashboard, copilot-studio-analytics, cross-solution-integration, cross-tenant-external-sharing-governance, deny-event-correlation-report, dr-testing-framework, inactivity-timeout-enforcement, message-center-monitor, model-risk-management-automation, session-security-configurator |

## Validation Commands

### CI Checks (13 workflows)
```bash
# Python lint + tests
python -m ruff check .
python -m pytest scripts/tests/

# PowerShell lint
Invoke-ScriptAnalyzer -Path . -Recurse -Settings PSGallery

# OData lint (CRITICAL — catches Dataverse logical-name typos)
python scripts/lint-odata-columns.py
python scripts/lint-odata-existence.py

# Manifest consistency
python scripts/build-manifest.py --check

# Language rules
# (enforced by language-rules.yml workflow)

# CodeQL (Python + C#)
# (GitHub-managed, runs on PR)

# gitleaks (secret scanning)
# (runs on PR)
```

### Key Rule: Dataverse Logical Names
The #1 source of bugs in this repo. Dataverse logical names use SchemaName lowercased with NO underscores between words:
- ✅ `fsi_agentid`, `fsi_scanrunid`, `fsi_compliancestatus`
- ❌ `fsi_agent_id`, `fsi_scan_run_id`, `fsi_compliance_status`
- Exception: connection reference unique names (`fsi_cr_*`) may use underscores

## Sister Repo
- `judeper/FSI-AgentGov` — The governance framework (controls, assessment engine, docs site)
- Solutions in this repo implement controls defined in FSI-AgentGov
