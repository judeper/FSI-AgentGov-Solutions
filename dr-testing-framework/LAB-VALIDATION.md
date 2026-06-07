# Lab Validation Report — DR Testing Framework

> **Solution:** dr-testing-framework · **Version:** v2.0.2
> **Validation date:** 2026-06-04 · **Mode:** Static validation (no live tenant)
> **Primary controls:** 2.4 (Business Continuity & Disaster Recovery), 2.1 (Managed Environments), 1.9 (Data Retention)

## Purpose and scope

This solution provides **post-recovery validation and evidence packaging** for AI agent
environments in Microsoft Power Platform — not recovery execution. It runs read-only checks
(agent component count, statecode, connection references, `WhoAmI`, Dataverse-row hash
snapshot) against an already-restored environment and persists each check as an
`fsi_drtestresult` row for FFIEC BCP / FINRA Rule 4370 / OCC Heightened Standards /
SEC Rule 17a-4(f) supervisory review.

The validation focused on parse-validity, authoritative-source verification of every
Power Platform / Dataverse API and capability claim, and documentation completeness.

## What was checked

| Area | Method | Result |
|------|--------|--------|
| Python scripts (3) | `python -m py_compile` | ✅ all compile |
| PowerShell scripts (4, incl. tests) | `Parser::ParseFile` zero-error parse | ✅ all parse |
| Pester unit tests | `Invoke-Pester scripts` (Pester 5.7.1) | ✅ 57 passed, 0 failed |
| Dataverse schema docs | `create_drt_dataverse_schema.py --output-docs` regen | ✅ no drift |
| Dataverse column references | grep script `$select`/`$filter` vs `create_drt_dataverse_schema.py` | ✅ logical names consistent |
| Option-set values | `fsi_drt_teststatus` (1=Pass, 2=Fail) | ✅ matches script + `.ralph-config.json` note |
| Language rules | grep for prohibited overclaim phrases in `.md` (excl. CHANGELOG) | ✅ no violations |
| Templates | JSON parse | ✅ both valid |

## Authoritative sources cited

1. **Power Platform backup retention / restore mechanics** — Microsoft Learn, *Back up and restore environments*: <https://learn.microsoft.com/en-us/power-platform/admin/backup-restore-environments>
   - System and manual backups retained **7 days** by default for all production and nonproduction environments.
   - Production **Managed Environments**: retention extendable to 7/14/21/**28 days** via PPAC or PowerShell.
   - Restore must be in the **same region** as the backup; **1 GB** free capacity required to restore; manual backups take ~10–15 min before they are available.
2. **`Backup-PowerAppEnvironment`** — Microsoft Learn (Microsoft.PowerApps.Administration.PowerShell): <https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/backup-powerappenvironment?view=pa-ps-latest> — cmdlet exists; backs up an environment.
3. **`Copy-PowerAppEnvironment`** — Microsoft Learn (same module): <https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/copy-powerappenvironment?view=pa-ps-latest> — copies source→target; `MinimalCopy`/`SkipAuditData` options confirmed.
4. **`botcomponent` table / `parentbotid` lookup** — Microsoft Learn, *Copilot component (botcomponent) table reference*: confirms `parentbotid` lookup to the `bot` table (script uses `_parentbotid_value`).
5. **`Get-AzAccessToken` SecureString change** — Microsoft Learn, *Protect secrets in Azure PowerShell*: <https://learn.microsoft.com/powershell/azure/protect-secrets> (and `Get-AzAccessToken` reference: <https://learn.microsoft.com/powershell/module/az.accounts/get-azaccesstoken>) — `Get-AzAccessToken` returns `SecureString` from **Az.Accounts 5.0.0 / Az 14.0.0**. `docs/prerequisites.md` already handles both `SecureString` and `String` defensively.
6. **Emergency access (break-glass) accounts** — Microsoft Learn, *Manage emergency access accounts*: <https://learn.microsoft.com/entra/identity/role-based-access-control/security-emergency-access> — referenced by `docs/emergency-access-drill.md` (≥2 cloud-only accounts, monitored sign-ins, regular validation drills).

## Gaps found and fixes applied

| # | Severity | File | Gap | Fix |
|---|----------|------|-----|-----|
| 1 | Minor (accuracy) | `README.md` (Power Platform backup notes) | Backup-retention claim used the **outdated** model ("production environments *with Dynamics 365 applications* have up to 28 days; others 7 days"). Microsoft's current model ties extended retention (7/14/21/28 days) to **production Managed Environments**, not Dynamics 365 app presence. | Rewrote to the current Managed Environments model with the correct admin roles, verified against source #1. |
| 2 | Cosmetic (doc accuracy) | `docs/evidence-export.md` (2 places) | Example audit-log filenames embedded the `TestType` (e.g. `dr-audit-AgentReadinessCheck-...`), but the real filename emitted by `Invoke-DRTest.ps1` is `dr-audit-<yyyyMMdd-HHmmss>-<correlationid>.log`. An operator following the doc would mis-predict filenames and the `-TestRunId` glob (`dr-audit-*-<id>.log`). | Replaced examples with the actual format. |
| 3 | Cosmetic (doc accuracy) | `templates/dr-evidence-metadata.sample.json` | Same outdated audit-log filename format in `AuditLogFiles`. | Aligned to actual format. |

No script logic, API call, auth flow, column name, or option-set value required correction —
the v2.0.0 reframe + council-review remediations (M-1/M-2/m-5/m-6) had already brought the
code to a high standard.

## Verified-correct items (no change needed)

- **API surface:** `bots`, `botcomponents` (`_parentbotid_value`), `connectionreferences`, `organizations`, `WhoAmI`, `fsi_drtestresults` Web API v9.2 paths are valid; `$count=true&$top=0` + `@odata.nextLink` pagination patterns are correct.
- **Honest scope framing:** README explicitly disclaims that the script initiates restores, fails over regions, or computes regulator-grade RTO/RPO — matching the platform reality verified in source #1 (customer scripts cannot back up / restore tenant-bound environment metadata).
- **Auth:** managed-identity-first guidance; client-secret paths marked `# legacy: dev-only` with `SuppressMessageAttribute` + justification; secret zeroized in `finally`.
- **Token audience:** `"$Environment/.default"` scope targets the Dataverse org — correct audience.

## Runtime-only caveats (cannot be verified statically)

- Live `bot`/`botcomponent`/`fsi_drtestresult` reads, `WhoAmI`, and PATCH writes require a real
  Dataverse environment with the application user provisioned and roles granted.
- Actual probe-duration and 429/`Retry-After` retry behavior depend on live service latency/throttling.
- `Backup-PowerAppEnvironment` / `Copy-PowerAppEnvironment` and PPAC restore are **operator-run,
  out-of-scope** prerequisites; this framework only validates the post-recovery state.
- KQL queries require Application Insights connected to Dataverse / Azure Monitor with the
  expected tables (`requests`, `dependencies`, `customEvents`, `AzureActivity`).

## Lab-readiness assessment

**Lab-ready.** All static checks pass (compile, parse, 57/57 Pester, no schema drift, no
language violations). Three documentation-accuracy gaps were corrected — the most material
being the outdated backup-retention model now realigned to the current Microsoft Managed
Environments model. Live-tenant execution paths remain unverified by design (no tenant in this
validation) and are clearly enumerated above as runtime-only caveats.

## Second-Pass Command-Existence Re-Verification (2026-06-05)

An independent second-pass audit re-derived every invoked command, cmdlet, CLI verb, REST endpoint and api-version, Dataverse entity set / logical column / option-set, and module against Microsoft Learn, with a sharpened focus on confirming each surface exists and will run in a live lab. Backup/Copy-PowerAppEnvironment cmdlets (documentation-only), Dataverse entity sets including botcomponent _parentbotid_value (correct in this context), the OAuth token endpoint, and the KQL AzureActivity / requests tables were confirmed against Microsoft Learn; no corrections required. One SecureString-token item is handled defensively and caveated.

