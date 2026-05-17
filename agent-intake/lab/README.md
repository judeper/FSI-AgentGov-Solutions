# Lab configuration

This folder holds **per-developer lab configuration** for the agent-intake solution. It enables `deploy.ps1` to be re-run repeatedly against the same lab tenant without re-typing the environment URL each time.

## What's in this folder

| File | Committed? | Purpose |
|------|-----------|---------|
| `README.md` | ✅ | This file |
| `config.example.json` | ✅ | Template showing the schema |
| `Invoke-Deploy.ps1` | ✅ | Thin wrapper around `../scripts/deploy.ps1` that reads `config.local.json` |
| `config.local.json` | ❌ (gitignored) | Your real tenant URL, env name, IDs |
| `.deploy-runtime/` | ❌ (gitignored) | Temporary runtime artifacts created by deploy.ps1 |
| `*.log` | ❌ (gitignored) | Local log files |

## Pattern

1. Copy `config.example.json` → `config.local.json`.
2. Fill in your lab tenant URL, environment name, tenant ID, environment ID.
3. Run `./Invoke-Deploy.ps1` (no args) to deploy using those values.
4. Run `./Invoke-Deploy.ps1 -Teardown` to destructively remove the footprint.
5. Run `./Invoke-Deploy.ps1 -SeedTestData` to deploy + seed 5 fixtures.

## Security model

| What | Where it lives | Why |
|------|---------------|-----|
| Tenant URL, environment ID | `config.local.json` (gitignored) | Non-secret but tenant-identifying; not safe to commit to a public repo |
| Az / PAC auth tokens | `az login` and `pac auth create` user-profile stores | Tokens never touch the repo or any file we manage |
| Service principal secrets | Environment variables `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` / `AZURE_TENANT_ID` (legacy fallback only) | Never in any file. Set in shell session only when needed. |

Root `.gitignore` enforces `**/lab/*.local.*` so accidental commits are caught.

## Why `lab/` is per-solution, not centralized

Each FSI solution may target a different Power Platform environment in your tenant (Express path vs Full path testing may want isolated envs). Per-solution `lab/` folders keep configs scoped to the solution being tested.

## Quickstart for a new lab tenant

```pwsh
# 1. Sign in to az and pac (one-time per machine)
az login
pac auth create --name <ProfileName>

# 2. Create dedicated env (or reuse existing)
pac admin create --name FSI-AgentIntake-Lab --type Trial --region unitedstates

# 3. Point pac at the new env
pac org select --environment <env-id-from-step-2>

# 4. Copy and edit config
Copy-Item config.example.json config.local.json
# Edit config.local.json with values from steps 2-3

# 5. Run
./Invoke-Deploy.ps1            # deploy + smoke
./Invoke-Deploy.ps1 -Teardown  # tear down
./Invoke-Deploy.ps1 -DryRun    # see what would happen
```
