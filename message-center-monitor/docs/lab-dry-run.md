# Lab dry-run runbook

This runbook walks an engineer through a one-evening end-to-end validation of
`message-center-monitor` v2.5.0 against a non-prod Microsoft Entra tenant +
Power Platform environment. After the smoke test passes, the engineer has
verified — against live wires — that the v2.4.0 fix for the C1 admin-field
clobber regression actually holds.

> **Status:** Internal lab tooling. NOT for production deployment.
> Production deployment uses `docs/setup-checklist.md`.

## Audience & prerequisites

You are an M365 administrator or DevOps engineer with:

- A non-prod Microsoft Entra tenant + Power Platform environment.
- **Application Administrator** + **Power Platform Administrator** roles in
  that tenant. (The prereq script can confirm via `-CheckRoles`.)
- Local workstation with PowerShell 7+, Python 3.10+, GitHub CLI.
- Azure subscription (for the lab Key Vault) where you have Contributor.
- An empty resource group OR permission to create one.

## Council finding traceability

This lab gates the following findings from the v2.4.0 verification council:

| Finding | Bug class                                  | Fix file                                                | Unit test                            | Smoke step (lab)                              |
|---------|--------------------------------------------|---------------------------------------------------------|--------------------------------------|-----------------------------------------------|
| **C1**  | Update clobbers admin assessments          | `_Common.ps1` `Invoke-McmDvUpsertMessage`               | `Upsert.Tests.ps1` (8 cases)         | Steps 5–6 (manual flip → all 7 admin cols)    |
| **H1**  | WorkloadIdentity token exchange            | `_Common.ps1` `Get-McmAccessToken`                      | `Common.Tests.ps1` auth-mode dispatch | n/a (lab uses ClientSecret per A3)            |
| **H2**  | Retry on 5xx                               | `_Common.ps1` `Invoke-McmRest`                          | `Common.Tests.ps1` retry suite       | implicit (live network during sync)           |
| **H3**  | `Retry-After` parsing on PS7               | `_Common.ps1` `Invoke-McmRest`                          | `Common.Tests.ps1` Retry-After       | implicit                                      |
| Schema  | Idempotent alt-key creation                | `create_mcm_dataverse_schema.py` `create_keys()`        | `test_schema.py`                     | Step 3 (deploy) + Steps 3-6 (uses alt-key URL)|

## One-time setup

```pwsh
cd message-center-monitor/lab
cp lab-config.example.json lab-config.json
# Fill in lab-config.json with your tenant/subscription/environment details.
```

Then install prereqs (will prompt for Microsoft.Graph + Az + PowerApps modules
if missing):

```pwsh
pwsh ./00_Install-Prereqs.ps1 -CheckRoles
```

If `-CheckRoles` warns that you lack a required directory role, fix that
**before** continuing — every step after this assumes you have it.

### Non-prod safety acknowledgement

Before any mutating script (`01`-`06`, `99`) will run, `lab-config.json` must
contain the literal string in `nonProd.acknowledgement`:

```json
"nonProd": {
  "acknowledgement": "I understand this lab must not target production"
}
```

The check is **case + punctuation sensitive**. A typo, a generic "yes", or an
empty value all fail the guard. To deliberately re-validate against a production
tenant (NOT recommended), pass `-AllowProduction` to each script — it is a loud
log line, not silence.

## Execution order

Run each script in order. Each is **idempotent** — safe to re-run on the same
state.

| # | Script                              | Time   | What it does                                                                 |
|---|-------------------------------------|--------|------------------------------------------------------------------------------|
| 0 | `00_Install-Prereqs.ps1`            | ~3 min | Installs PS modules + pip packages; verifies runtimes; (opt) checks roles    |
| 1 | `01_New-AppRegistration.ps1`        | ~30 s  | Creates app reg + SP + permissions; admin-consents; rotates secret if stale  |
| 2 | `02_New-KeyVault.ps1`               | ~1 min | Creates Key Vault + RBAC role; uploads the secret from step 1                |
| 3 | `03_Deploy-Schema.ps1`              | ~5 min | Runs the 3 Python setup scripts; **polls alt-key for Active up to 15 min**   |
| 4 | `04_New-AppUser.ps1`                | ~1 min | Creates Dataverse app user; assigns role; **probes effective access**         |
| 5 | `05_Set-EnvVarValues.ps1`           | ~30 s  | Populates the 6 `fsi_MCM_*` Dataverse environment variable values             |
| 6 | `06_Invoke-LabSmokeTest.ps1`        | ~3 min | **The dry-run.** 10-step orchestrator including manual cloud-flow gate.       |
| 99| `99_Remove-LabDeployment.ps1`       | ~3 min | State-driven teardown. Run when you're done with the lab.                     |

## Step 6 explained: why all 7 admin columns?

The v2.4.0 fix (council finding C1) was that the inline upsert PATCH body
included `fsi_assessmentstatus` on every update — which **clobbered any value
an admin had set during their assessment workflow**. The fix re-routes update
PATCH bodies through `Invoke-McmDvUpsertMessage`, which excludes ALL admin-owned
columns from the update payload (admin-owned = anything a human sets after the
machine writes the row).

The 7 admin-owned columns are:

1. `fsi_assessmentstatus`
2. `fsi_assessment`
3. `fsi_assessedby`
4. `fsi_assesseddate`
5. `fsi_actionstaken`
6. `fsi_impactsagents`
7. `fsi_notifiedon`

`Upsert.Tests.ps1` asserts via JSON-body set intersection that none of these
appear in update payloads. Step 6 of the lab smoke test does the same
end-to-end against a real Dataverse row: set all 7, run the sync, then
read back the row and assert all 7 are unchanged.

## Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `00_Install-Prereqs.ps1` fails on `Install-Module`                        | TLS / proxy / no PSGallery trust | `Set-PSRepository PSGallery -InstallationPolicy Trusted; [Net.ServicePointManager]::SecurityProtocol = 'Tls12'`; retry |
| `01_New-AppRegistration.ps1` fails: "Insufficient privileges"             | Missing Application Administrator | Assign role in Microsoft Entra admin center > Roles & administrators        |
| `01` finishes but Step 6 of consent poll times out                         | Tenant-wide consent backlog       | Wait 5 min and re-run `01` (it is idempotent and re-checks consent)         |
| `03_Deploy-Schema.ps1` polls alt-key and reports `status=Failed`          | Alt-key index activation failed   | Power Apps maker portal > Tables > Message Center Log > Keys; delete + recreate, then re-run `03` |
| `03` polls alt-key and reports `status=Pending` past `schemaKeyActivationMaxSeconds` | Slow tenant; large existing data | Bump `thresholds.schemaKeyActivationMaxSeconds` in `lab-config.json` and re-run `03` |
| `04_New-AppUser.ps1` step "probe" fails after 6 attempts                  | Role association did not propagate| Power Apps maker portal > Users + permissions > Application users; verify role; re-run `04` |
| Step 3 of smoke test reports "No rows in fsi_messagecenterlogs"           | Tenant has no recent MC posts     | Bump `smoke.daysBack` to 90 in `lab-config.json` and re-run `06`            |
| Step 6 of smoke test FAILS with "ADMIN FIELDS CLOBBERED"                  | C1 regression has resurfaced      | **STOP**. Do NOT ship. Re-open PR #40 thread; investigate `Invoke-McmDvUpsertMessage` |

## Re-running the lab

All scripts are idempotent. To re-run from scratch without tearing down:

```pwsh
pwsh ./06_Invoke-LabSmokeTest.ps1
```

To start over:

```pwsh
pwsh ./99_Remove-LabDeployment.ps1
# Then run 01..06 again.
```

## Out of scope

- **Production deployment** — use `docs/setup-checklist.md`.
- **Government cloud** — endpoints in this lab are commercial-cloud defaults.
  A gov-cloud lab profile is future work.
- **Real Teams notification validation** — the lab runs headless (empty
  TeamId/Channel are accepted). Verify Teams manually after the lab if needed.
- **Logic Apps Standard alternative** — this lab uses the existing
  PowerShell-driven sync; a Logic App variant could be added in a future release.

## Files in this folder

```
lab/
├── 00_Install-Prereqs.ps1            # Step 0 — modules + pip + role check
├── 01_New-AppRegistration.ps1        # Step 1 — app reg + consent + secret rotation
├── 02_New-KeyVault.ps1               # Step 2 — Key Vault + secret upload + RBAC
├── 03_Deploy-Schema.ps1              # Step 3 — Python schema + alt-key polling
├── 04_New-AppUser.ps1                # Step 4 — Dataverse app user + role + probe
├── 05_Set-EnvVarValues.ps1           # Step 5 — Dataverse env-var values
├── 06_Invoke-LabSmokeTest.ps1        # Step 6 — 10-step end-to-end smoke test
├── 99_Remove-LabDeployment.ps1       # Step 99 — state-driven idempotent teardown
├── lab-config.example.json           # Template — copy to lab-config.json
├── lab-state.schema.json             # Schema for the ownership manifest
├── .gitignore                        # Excludes lab-config.json, lab-state.json, logs/
└── lib/
    └── Write-LabLog.ps1              # Shared logger with secret redaction
```
