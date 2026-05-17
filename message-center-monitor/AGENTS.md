# message-center-monitor — AGENTS.md

> **For AI agents and engineers working in this solution folder.** Read this file
> AFTER the root `AGENTS.md` / `CLAUDE.md` / `.github/copilot-instructions.md`.
> Cross-cutting rules (FSI language guidelines, Dataverse naming, lab/sandbox
> guards, commit conventions) live in those root files. **This file adds
> solution-specific context and the current operational state.** Both layers
> apply — solution-specific guidance wins only on solution-specific topics.

---

## 1. Solution snapshot

| Field | Value |
|---|---|
| **Solution** | `message-center-monitor` |
| **Version** | v2.5.1 (latest tag); `[Unreleased]` carries the POC-handoff + dry-run fixes |
| **Status** | POC dry-run in progress on `feature/message-center-monitor-poc-ready` (PR #141) |
| **Primary controls** | 2.3 (change-management evidence), 2.10 (platform-update awareness) |
| **Regulatory mapping** | FINRA 4511 / 3110, SEC 17a-4 (immutable evidence), GLBA 501(b) |
| **Tech stack** | PowerShell 7.2+ (governance scripts + lab), Python 3.10+ (schema setup), Dataverse Web API, Microsoft Graph (`ServiceMessage.Read.All`), Teams incoming webhook (Phase 1) / Power Automate (Phase 3) |
| **Deployment paths** | **Phase 1** (PowerShell + Teams webhook, the POC bar) · **Phase 2** (assessment + evidence export) · **Phase 3** (Power Automate flow — mutually exclusive with Phase 1) |

---

## 2. Where things are

```
message-center-monitor/
├── AGENTS.md                           ← this file
├── README.md                           customer-facing deployment guide
├── CHANGELOG.md                        Keep-a-Changelog format; [Unreleased] = uncommitted/pending
├── manifest.yaml                       canonical metadata for site catalog
├── .ralph-config.json                  domain facts (column names, option-set values) — machine-readable
├── docs/
│   ├── poc-quickstart.md               customer Phase 1 / 2 / 3 runbook
│   ├── flow-configuration.md           Phase 3 Power Automate build instructions
│   ├── dataverse-schema.md             auto-generated from create_mcm_dataverse_schema.py --output-docs
│   └── …
├── scripts/
│   ├── create_mcm_dataverse_schema.py  schema deploy (option sets + table + columns + alt-key)
│   ├── create_mcm_environment_variables.py     Phase 3 only
│   ├── create_mcm_connection_references.py     Phase 3 only
│   └── governance/
│       ├── _Common.ps1                 shared helpers (Invoke-McmRest, Invoke-McmDvUpsertMessage, Send-McmTeamsWebhook)
│       ├── Invoke-MessageCenterSync.ps1        the daily sync
│       ├── Test-McmPrerequisites.ps1           preflight (11 checks)
│       ├── Get-MessageCenterAssessmentStatus.ps1
│       └── Export-MessageCenterEvidence.ps1    audit-ready JSON + SHA-256
├── tests/                              Pester (PowerShell) + pytest (Python)
├── templates/
│   ├── teams-notification-card.json    adaptive card v1.5 — read by BOTH Phase 1 webhook AND Phase 3 flow
│   └── …
└── lab/                                cross-machine dry-run automation (gitignored runtime state)
    ├── 00_Install-Prereqs.ps1          PS7 / Python / module install
    ├── 00b_New-PaygEnvironment.ps1     auto-provision PAYG sandbox (single BAP API call)
    ├── 01_New-AppRegistration.ps1      Entra app reg + admin consent
    ├── 02_New-KeyVault.ps1             KV + RBAC + secret upload
    ├── 03_Deploy-Schema.ps1            wraps Python schema script + alt-key poll
    ├── 04_New-AppUser.ps1              Dataverse application user + role
    ├── 05_Set-EnvVarValues.ps1         Phase 3 env-var values
    ├── 06_Invoke-LabSmokeTest.ps1      lab end-to-end
    ├── 07_Invoke-PocSmokeTest.ps1      customer-flow smoke with local Teams listener
    ├── 99_Remove-LabDeployment.ps1     teardown (idempotent; -RemoveEnvironment for env)
    ├── Resume-LabState.ps1             rebuild lab-state.json on a fresh machine
    ├── lib/Write-LabLog.ps1            redaction-safe logging helpers (Get-LabConfig, Save-LabState, Assert-NonProdAcknowledgement, ConvertTo-RedactedString)
    ├── lab-config.example.json         starter (committed)
    ├── lab-config.json                 LOCAL ONLY, gitignored — tenant/env/KV identifiers
    └── lab-state.json                  LOCAL ONLY, gitignored — derived resource IDs from cloud
```

---

## 3. Current operational state (UPDATE THIS AT EVERY CHECKPOINT)

> **Last updated:** 2026-05-17 (post Phase 1.1-1.7 + 2.2 autonomous dry-run)
> **Last committed at SHA:** `6516c2d` (subject to change once this AGENTS.md commit lands — update on next checkpoint).

### Where the live IDs are (NEVER commit these)

All tenant / subscription / environment / app-registration / Key Vault / Dataverse
identifiers for the active dry-run live in **two gitignored files in `lab/`**:

| File | Contents | How to populate on a fresh machine |
|---|---|---|
| `lab/lab-config.json` | Inputs the engineer chooses: `tenant.tenantId`, `azure.subscriptionId`, `azure.resourceGroup`, `azure.region`, `powerPlatform.environmentUrl`, `powerPlatform.environmentId`, `powerPlatform.billingPolicyId`, `keyVault.name`, `keyVault.secretName`, `appRegistration.displayName`, `operator.runnerUpn`, `nonProd.acknowledgement`, optional Teams notification + smoke settings. | Either (a) copy your existing `lab-config.json` from the other workstation, **or** (b) start from `lab-config.example.json` and re-fill from your records. |
| `lab/lab-state.json` | Outputs the lab scripts discovered/created: `appRegistration.applicationId`, `appRegistration.objectId`, `appRegistration.servicePrincipalObjectId`, `appRegistration.secretKeyId`, `keyVault.resourceId`, `dataverse.environmentId`, `dataverse.applicationUserId`, `dataverse.assignedRole`, etc. | Either (a) copy your existing `lab-state.json` from the other workstation, **or** (b) run `lab/Resume-LabState.ps1` to rebuild it by querying the cloud resources named in `lab-config.json`. |

Both files are listed in `lab/.gitignore`. The example/template file
`lab-config.example.json` IS committed and contains only placeholder values plus
inline `_help` notes.

**If you are an AI agent reading this and you do not see `lab/lab-config.json`
on disk, do not invent values for it. Ask the user to copy it from their other
machine, or to recreate it from `lab-config.example.json`.**

### Phases done (7/17)

- [x] **0** Auto-provision PAYG env (≈30 s via `lab/00b_New-PaygEnvironment.ps1`)
- [x] **1.1** App registration + admin consent (`lab/01`)
- [x] **1.2** Key Vault + secret with RBAC retry (`lab/02`)
- [x] **1.3** Dataverse schema (3 option sets + table + 19 columns + alt-key `Active`)
- [x] **1.4** App user + role (`lab/04`)
- [x] **1.5** Preflight 9 PASS + 1 SKIP (Teams URL not yet supplied) + 1 WARN (no notification path active)
- [x] **1.6 / 1.7** Sync #1 (315 upserts) + Sync #2 (idempotent — row count stable)
- [x] **2.2** `Get-MessageCenterAssessmentStatus` (207 records in 30-day window) + `Export-MessageCenterEvidence` (150 KB JSON + SHA-256)

### Phases pending (10/17)

- [ ] **1.4 (notification path)** **USER:** Create Teams Workflows incoming webhook (Teams app UI; ~2 min). Paste URL into the next sync's `$env:MCM_TEAMS_WEBHOOK_URL` or `-TeamsWebhookUrl` parameter.
- [ ] **1.8 / 2.1** lab/07 POC smoke + lab/06 lab smoke (both automatable via local listener)
- [ ] **3.1** **USER:** Build Power Automate flow per `docs/flow-configuration.md` (≈30-60 min UI work)
- [ ] **3.2** Create + bind Phase 3 env-var VALUE
- [ ] **3.3** **USER:** Clear `$env:MCM_TEAMS_WEBHOOK_URL` (mutex with Phase 3 flow)
- [ ] **3.4 / 3.5 / 3.6** Phase 3 preflight + sync + mutex test
- [ ] **4** Teardown (`lab/99_Remove-LabDeployment.ps1 -RemoveEnvironment`)

---

## 4. Resume on a new machine

```powershell
# Step 1 — install prereqs (PS7, Python, Az / Mg / MSAL.PS modules)
pwsh ./message-center-monitor/lab/00_Install-Prereqs.ps1

# Step 2 — auth as the lab admin (one-time device-code flow)
#   Tenant ID is in your lab-config.json from your other machine.
az login --tenant <tenantId-from-lab-config.json>

# Step 3 — bring lab-config.json onto this machine
#   Option A (preferred): copy your existing file from your other workstation
#       to message-center-monitor/lab/lab-config.json
#   Option B: start fresh
#       cp message-center-monitor/lab/lab-config.example.json \
#          message-center-monitor/lab/lab-config.json
#       # then fill it in — the inline _help fields explain each value

# Step 4 — rebuild lab-state.json by querying the cloud resources we already
#   provisioned, OR copy lab-state.json from your other workstation.
pwsh ./message-center-monitor/lab/Resume-LabState.ps1

# Step 5 — re-run preflight to confirm everything still resolves on this machine.
#   The exact arguments are derivable from lab-config.json + lab-state.json;
#   the snippet below shows the shape. Pull the secret from Key Vault by
#   reading the KV name + secret name from lab-config.json (do not hardcode).
$cfg = Get-Content message-center-monitor/lab/lab-config.json | ConvertFrom-Json
$state = Get-Content message-center-monitor/lab/lab-state.json   | ConvertFrom-Json
$secret = az keyvault secret show `
    --vault-name $cfg.keyVault.name `
    --name       $cfg.keyVault.secretName `
    -o json | ConvertFrom-Json | Select-Object -ExpandProperty value
pwsh ./message-center-monitor/scripts/governance/Test-McmPrerequisites.ps1 `
    -TenantId            $cfg.tenant.tenantId `
    -ClientId            $state.appRegistration.applicationId `
    -ClientSecret        (ConvertTo-SecureString $secret -AsPlainText -Force) `
    -AuthMode            ClientSecret `
    -DataverseUrl        $cfg.powerPlatform.environmentUrl `
    -KeyVaultName        $cfg.keyVault.name `
    -KeyVaultSecretName  $cfg.keyVault.secretName `
    -AssumePhase1Only
```

Total wall-clock: ~5 min on a machine that already has WinGet / pwsh installed.

If `Resume-LabState.ps1` can't find one of the cloud resources (e.g. the env
got deleted while you were away), the script prints exactly which name it
couldn't resolve. From that point, decide whether to re-create it via
`lab/00b_New-PaygEnvironment.ps1` → `lab/01` → `lab/02` etc., or to update
`lab-config.json` to point at a different existing resource.

---

## 5. Solution-specific conventions (additive to root)

> The machine-readable source of truth for these facts is `.ralph-config.json`.
> Read it before editing any governance script. This section is the
> human-readable summary.

- **Dataverse table:** `fsi_messagecenterlog` (entity set `fsi_messagecenterlogs`). Alternate key `fsi_MessageCenterIdKey` on column `fsi_messagecenterid`.
- **Severity option-set values:** `100000000=High`, `100000001=Normal`, `100000002=Critical`.
  Mapping is intentionally NOT alphabetical — older `[Unreleased]` notes warn of an inverted mapping bug. Do not "fix" it.
- **Assessment-status option-set values:** `100000000=NotAssessed`, `100000001=Reviewed`, `100000002=ImpactsAgents`, `100000003=NoImpact`.
- **C1 (admin-owned columns invariant):** `Invoke-McmDvUpsertMessage` MUST NOT write `fsi_notifiedon`, `fsi_assessmentstatus` (except on initial create), `fsi_assessment`, `fsi_assessedby`, `fsi_assesseddate`, `fsi_impactsagents`, or `fsi_actionstaken` on the UPDATE branch. The post-notify write-back of `fsi_notifiedon` is the documented exception and uses a direct PATCH via `Invoke-McmRest` (NOT `Invoke-McmDvUpsertMessage`) with a single-key body. Enforced by `Sync.Tests.ps1` AST regression.
- **Phase 1 / Phase 3 mutex:** the Phase 1 PowerShell Teams webhook and the Phase 3 Power Automate flow are mutually exclusive notification paths. Preflight check 11 fails when both are configured (`$env:MCM_TEAMS_WEBHOOK_URL` set AND env-var definition `fsi_MCM_NotifySeverities` deployed). Stale Phase 3 scaffolding (definition without bound value) downgrades to WARN. The `-AssumePhase1Only` switch bypasses the Phase 3 probe and returns WARN.
- **AssessedBy is a String** (`StringAttributeMetadata`, MaxLength 200), NOT a Lookup. v2.4.0 mistakenly treated it as a Lookup at 4 sites + 2 comments; v2.5.1's `[Unreleased]` reverts that. Do not reintroduce `_fsi_assessedby_value` syntax.
- **Token redaction:** every log line that quotes a URL must go through `Format-McmSafeUri` (`_Common.ps1`). It rewrites Teams Workflows / Logic Apps SAS / `*.webhook.office.com` / `*.azure-apim.net` / URLs with `sig=` or `code=` to `<scheme>://<host>/<redacted>`. Dataverse and Graph URLs pass through unchanged.
- **Webhook URLs are bearer credentials.** They must never appear in `Write-LabLog` output, error messages, or test fixtures.

---

## 6. Things AI agents must NOT do in this solution

- **Do NOT push to PR #141** without explicit user ack. `git push` to `feature/message-center-monitor-poc-ready` requires authorization.
- **Do NOT change the severity / assessment-status option-set integer values** — they are stamped into 315+ live Dataverse rows on the test env (and presumably in customer envs).
- **Do NOT add admin-owned columns to the direct-PATCH allowlist** in `_Common.ps1` Invoke-McmDvUpsertMessage's post-notify write-back. `fsi_notifiedon` is the ONLY permitted member. Enforced by `Sync.Tests.ps1` AST invariant.
- **Do NOT remove the alt-key POST fallback** in `_Common.ps1`. Real Dataverse returns 404 on PATCH + If-None-Match against a missing row instead of the documented 201 — the fallback is empirical, not theoretical.
- **Do NOT run any script with the existing prod tenant ID** in `lab-config.json`. The non-prod guard is the only thing standing between the lab and a real customer tenant; preserve `Assert-NonProdAcknowledgement` calls in every mutating step.
- **Do NOT delete `lab-state.json`** without first archiving the IDs (or use `Resume-LabState.ps1` to rebuild from cloud). It is the only local record of `applicationUserId` and the current `secretKeyId`.
- **Do NOT add exported Power Automate flow JSON / connection references / environment variable JSON to the repo.** This solution is documentation-only for flows; see root `AGENTS.md` § "Solution Content Policy".

---

## 7. Known issues / open follow-ups

| # | Topic | Status | Notes |
|---|---|---|---|
| 1 | FSI role not deployed | Workaround in place | `lab/04` falls back to `System Customizer` when `FSI Message Center Sync` role is absent. Production deployments need the FSI role defined in a managed solution. |
| 2 | Az.KeyVault breaking-change warning | Cosmetic | The `Get-AzKeyVaultSecret` warning about Az 16.0.0 / Az.KeyVault 7.0.0 is acknowledged. Re-evaluate when those versions ship. |
| 3 | Lab/04 PowerApps Administration module warnings | Cosmetic | "unapproved verbs" warnings from `Microsoft.PowerApps.Administration.PowerShell` 2.0.217. Module is no longer used by `lab/04` (we now create app users via Dataverse Web API) but `Add-PowerAppsAccount` was still being loaded. Safe to ignore. |
| 4 | `Test-McmPrerequisites.ps1` final-line `Count` warning | Cosmetic | A stray `.Count` access after the results table prints. Doesn't affect the exit code or the per-check tallies. Fix at next pass through the file. |
| 5 | Phase 3 flow not exercised | Pending | The Power Automate flow path has unit tests but no live customer-flow validation. Phase 3.1 of the dry-run will do that. |

---

## 8. Recent checkpoints

| Date | SHA | Phase / event | Summary |
|---|---|---|---|
| 2026-05-17 | (this commit) | docs: per-solution AGENTS.md + Resume-LabState | Establishes the per-solution AGENTS.md convention and ships the cross-machine bootstrap script. |
| 2026-05-17 | `6516c2d` | dry-run: phase 2.2 fixes | StrictMode `.Count` + `@odata.nextLink` patches in Status + Evidence scripts. 109/109 Pester. |
| 2026-05-17 | `dd1ea25` | dry-run: 9 phase-1 blockers | Schema `@odata.type`, alt-key POST fallback, app-user Web API, KV defaults, RBAC retry, etc. End-to-end sync works. |
| 2026-05-17 | `6423052` | feat: PAYG env automation | `lab/00b_New-PaygEnvironment.ps1` — single BAP API call provisions env + Dataverse + billing policy in ~30 s. |
| 2026-05-16 | `bdb1761` | council round 3 | 5 fixes from rubber-duck + code-review on round-2 fix commits. |

---

## 9. Validation commands (quick)

```powershell
# Lint + parse + unit tests + Python compile
Invoke-ScriptAnalyzer -Path message-center-monitor/scripts/governance,message-center-monitor/lab -Severity Error,Warning
python -m py_compile message-center-monitor/scripts/*.py
$cfg = New-PesterConfiguration; $cfg.Run.Path = "message-center-monitor/tests"; $cfg.Output.Verbosity = 'Minimal'; Invoke-Pester -Configuration $cfg
python -m pytest message-center-monitor/tests -q

# Verify the live env is healthy (reads the env URL from lab-config.json so
# this is portable across machines)
$envUrl = (Get-Content message-center-monitor/lab/lab-config.json | ConvertFrom-Json).powerPlatform.environmentUrl.TrimEnd('/')
$tok    = az account get-access-token --resource $envUrl --query accessToken -o tsv
Invoke-RestMethod -Uri "$envUrl/api/data/v9.2/fsi_messagecenterlogs?`$select=fsi_messagecenterid&`$top=1" -Headers @{Authorization="Bearer $tok"}
```
