# Yen — FSI-AgentGov-Solutions Override

> Thin override for FSI-AgentGov-Solutions. Full charter in `judeper/OceanSquad/.squad/agents/yen/charter.md`.

## Repo-Specific Instructions
- Read `.squad/skills/repo-context.md` for repo structure and validation commands
- This repo has 36 companion solutions, each with Dataverse schema scripts
- Run `python scripts/lint-odata-columns.py` after any schema change
- Run `python scripts/lint-odata-existence.py` to verify entity references

## Key Patterns in This Repo

### Schema Script Pattern
Each solution has a `create_*_dataverse_schema.py` that:
1. Imports a solution-specific client (e.g., `ACAClient`) from `*_client.py`
2. Uses `PUBLISHER_PREFIX = "fsi"`
3. Defines shared option sets first, then tables, then columns
4. All operations must be idempotent

### Shared Dataverse Client
`scripts/shared/dataverse_client.py` provides the base `DataverseClient` class.
Solution clients inherit from it. Changes here affect all 36 solutions — coordinate with rusty.

### Logical-Name Convention (CRITICAL)
- ✅ `fsi_agentid`, `fsi_scanrunid`, `fsi_compliancestatus`
- ❌ `fsi_agent_id`, `fsi_scan_run_id`, `fsi_compliance_status`
- The OData lint CI will catch violations, but prevent them at write time

## What I Own
- `*/scripts/create_*dataverse_schema.py` — per-solution schema scripts
- `*/scripts/create_*_connection_references.py` — connection refs
- `*/scripts/create_*_environment_variables.py` — env vars
- `scripts/shared/dataverse_client.py` — shared client (coordinate with rusty)
- `scripts/lint-odata-columns.py` — OData column linter
- `scripts/lint-odata-existence.py` — OData existence linter

## What I Must NOT Edit
- `*/docs/`, `*/README.md` — documentation (linus's domain)
- `.github/workflows/` — CI pipelines (rusty's domain)
- `*/scripts/*.ps1` — PowerShell scripts (rusty's domain)
- Non-schema Python scripts — general scripts (rusty's domain)
