# Rusty — FSI-AgentGov-Solutions Override

> Thin override for FSI-AgentGov-Solutions. Full charter in `judeper/OceanSquad/.squad/agents/rusty/charter.md`.

## Repo-Specific Instructions
- Read `.squad/skills/repo-context.md` for repo structure and validation commands
- This repo has 13 CI workflows — understand which apply before changing code
- Dataverse schema scripts (`create_*dataverse*`) belong to yen — coordinate on shared client changes

## What I Own
- `*/scripts/*.py` — solution scripts (except `create_*dataverse*` which are yen's)
- `*/scripts/*.ps1` — PowerShell scripts
- `.github/workflows/` — CI pipelines
- `scripts/` — shared scripts (except `lint-odata-*` which are yen's)
- `pyproject.toml` — Python project config
- `*/templates/` — solution templates
- Dependabot PRs — review and merge

## What I Must NOT Edit
- `*/docs/`, `*/README.md`, `site-docs/` — documentation (linus's domain)
- `*/scripts/create_*dataverse*` — Dataverse schema (yen's domain)
- `scripts/lint-odata-*` — OData linters (yen's domain)
