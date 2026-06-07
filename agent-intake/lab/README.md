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
pac auth create --name <ProfileName> --deviceCode

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

## Lab authentication readiness

For unattended lab deployments (e.g., on a CI runner, or a headless shell with no interactive prompts), perform a bootstrap → preflight → deploy cycle:

### 1. One-time bootstrap (delegated auth)

On each new machine targeting the lab tenant, set up delegated authentication:

```pwsh
# Authenticate as the admin account
az login --tenant <your-tenant-id>

# Create a named PAC profile using device-code flow (non-interactive)
pac auth create --name <profile-name> --environment <env-url> --deviceCode
```

### 2. Run the readiness preflight

Before deploying, validate that your authentication environment supports unattended runs:

```pwsh
cd agent-intake\lab
.\Test-LabAuthReadiness.ps1 -EnvironmentUrl <env-url>
```

This script performs 5 checks:

| Check | What it validates | Notes |
|-------|------------------|-------|
| **Conditional Access policies** | No CA policies block device-code flow or require re-auth every <2 hours | ⚠️ Warns if policies are too restrictive; exits 0 (non-fatal) |
| **Token acquisition** | Dataverse + Microsoft Graph tokens can be acquired and verified | ❌ Exits non-zero on hard failure; required for proceeding |
| **PAC fresh-shell test** | `pac org who` works without cached state (detects pac-1.30+ WAM trap) | ⚠️ Warns if PAC requires interactive browser auth on Windows |
| **Environment SKU report** | Detects Trial/Developer/Teams environment types | ⚠️ Warns that pay-as-you-go billing policies cannot attach to these types |
| **ExchangeOnlineManagement module** | Checks for presence + version ≥ 3.2.0 (required for Purview label creation) | ⚠️ Skipped if `-SkipPurviewLabel` is set (see below) |

If all checks pass (exit 0), the environment is ready for unattended deployment. If only warnings appear (not errors), you can proceed with manual review of the flagged items.

### 3. Configure for unattended deployment

Edit `config.local.json` with these key settings for unattended runs:

```json
{
  "deploy": {
    "skipPurviewLabel": true
  },
  "billing": {
    "allowedEnvironmentType": "Any"
  },
  "entraAgentId": {
    "featureFlagEnabled": false
  }
}
```

**Why each setting:**

- **`deploy.skipPurviewLabel=true`:** Skips Stage 3 Purview retention-label creation (the `Connect-IPPSSession` interactive path). Use this for lab runs where the two retention labels already exist on the tenant. Blueprint, consent, and Purview verification probe still run. **Important:** This setting assumes the labels are pre-provisioned; on a greenfield tenant, labels must be created first.
- **`billing.allowedEnvironmentType="Any"`:** Allows the deployment to proceed even on Trial/Developer environment types (which cannot use pay-as-you-go billing). For production deployments, use `"Sandbox,Production"` (the default) to fail fast on SKU mismatches.
- **`entraAgentId.featureFlagEnabled=false`:** Disables Microsoft Entra Agent ID minting during lab cycles. Lab validation uses the agent-registry flow but does not require the Entra ID integration.

### 4. Dry-run, then live

```pwsh
# Validate the deployment plan without making changes
.\Invoke-Deploy.ps1 -DryRun

# Deploy for real
.\Invoke-Deploy.ps1

# Tear down when done
.\Invoke-Deploy.ps1 -Teardown
```

### Example: Full unattended cycle

```pwsh
cd c:\dev\FSI-AgentGov-Solutions\agent-intake\lab

# Bootstrap (one-time)
az login --tenant 12345678-1234-1234-1234-123456789012
pac auth create --name FSI-Lab --environment https://contoso-dev.crm.dynamics.com --deviceCode

# Preflight
.\Test-LabAuthReadiness.ps1 -EnvironmentUrl https://contoso-dev.crm.dynamics.com

# Configure
Copy-Item config.example.json config.local.json
# Edit config.local.json: set environment.url, environment.environmentId, tenant.tenantId

# Deploy
.\Invoke-Deploy.ps1 -DryRun     # plan first
.\Invoke-Deploy.ps1             # deploy
.\Invoke-Deploy.ps1 -Teardown   # clean up
```
