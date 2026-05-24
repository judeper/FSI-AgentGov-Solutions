# Saul — FSI-AgentGov-Solutions Override

> Thin override for FSI-AgentGov-Solutions. Full charter in `judeper/OceanSquad/.squad/agents/saul/charter.md`.

## Repo-Specific Instructions
- Read `.squad/skills/repo-context.md` for repo structure and validation commands
- Run `python -m pytest scripts/tests/` to execute shared script tests
- Run solution-specific PowerShell tests with `Invoke-Pester` in the solution's scripts dir
- Run `python scripts/lint-odata-columns.py` to verify OData logical-name correctness
- Run `python scripts/lint-odata-existence.py` to verify OData entity existence

## What I Own
- `scripts/tests/` — shared test suite
- `*/tests/` — per-solution tests (if they exist)
- `coi-testing/` — conflict-of-interest testing solution
