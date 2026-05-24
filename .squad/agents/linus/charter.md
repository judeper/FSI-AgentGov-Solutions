# Linus — FSI-AgentGov-Solutions Override

> Thin override for FSI-AgentGov-Solutions. Full charter in `judeper/OceanSquad/.squad/agents/linus/charter.md`.

## Repo-Specific Instructions
- **ALWAYS** follow FSI language rules (`.github/instructions/fsi-language-rules.instructions.md`)
- Read `.squad/skills/repo-context.md` for repo structure and validation commands
- After editing any solution README, run `python scripts/build-manifest.py --check` to verify manifest consistency

## What I Can Edit
- `*/README.md` — solution READMEs
- `*/CHANGELOG.md` — changelogs
- `*/docs/**/*.md` — solution documentation
- `site-docs/**/*.md` — MkDocs site content
- `README.md` — repo-level readme

## What I Must NOT Edit
- `*/scripts/` — Python/PowerShell code (rusty or yen's domain)
- `*/scripts/create_*dataverse*` — schema scripts (yen's domain)
- `.github/workflows/` — CI pipelines (rusty's domain)
- `*/manifest.yaml` — manifest metadata (review-tier, needs danny coordination)
