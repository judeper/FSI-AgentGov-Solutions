# Lab Validation Report — Environment Lifecycle Management

> **Solution:** environment-lifecycle-management · **Version:** v1.2.2 · **Status:** live
> **Validated:** 2026-06-04 · **Mode:** static (no live tenant)
> **Primary controls:** 2.1 (Environment provisioning governance), 2.2 (Environment configuration baseline), 2.8 (Access/sharing governance), 1.7 (Audit logging / evidence)

## Purpose

Automated Power Platform environment provisioning with zone-based governance
classification. Maker intake (Copilot Studio) → zone classification → approval
routing (segregation of duties) → Service Principal provisioning →
Managed Environment enablement → environment-group assignment → security-group
binding → baseline hardening → immutable provisioning audit trail (Dataverse)
with quarterly SHA-256-hashed evidence export. Supports compliance with
FINRA Rule 4511(a), SEC Rules 17a-3 / 17a-4(f), and SOX 404 recordkeeping.

## What was checked

| Area | Method | Result |
|------|--------|--------|
| Python parse-validity (12 scripts) | `python -m py_compile` on every `.py` in `scripts/` | PASS — zero errors |
| PowerShell scripts | Inventory | None in this solution (shared `Get-ZoneClassification.ps1` lives at repo-root `scripts/shared/`, out of scope here) |
| Language rules (no "ensures/guarantees/will prevent/eliminates risk") | grep across `*.md`, `*.py`, `*.json` excluding CHANGELOG | PASS — zero violations |
| Dataverse column / entity-set naming | Cross-checked scripts ↔ `create_dataverse_schema.py` SchemaNames | PASS — logical names consistent (`fsi_environmentrequest`(s), `fsi_provisioninglog`(s), `fsi_zone`, `fsi_state`, etc.) |
| Option-set values (canonical 100000001+) | Reviewed `create_dataverse_schema.py` OPTIONSETS + `.ralph-config.json` domain facts | PASS — all 8 global option sets use `100000001+`; docs aligned (legacy `1..N` already remediated in v1.2.0/1.2.1) |
| Auth pattern (managed-identity-first) | Reviewed `elm_client.py`, `register_service_principal.py`, all CLI scripts | PASS — `DefaultAzureCredential` first; client-secret paths carry `# legacy: dev-only` markers and dev-only help text |
| Token audiences | Reviewed token acquisition | PASS — Dataverse uses `{environment_url}/.default`; Graph uses `https://graph.microsoft.com/.default`; flow HTTP actions use resource URI `https://api.powerplatform.com` |
| Power Platform / Graph API + cmdlet references | Authoritative Microsoft Learn verification (below) | PASS — all referenced APIs/commands confirmed to exist |

## Authoritative sources cited

1. **Power Platform Management API — `environmentmanagement/environmentGroups` route + `addEnvironment` action** (used in `docs/flow-configuration.md` Steps 9–10, `docs/prerequisites.md`).
   - `https://learn.microsoft.com/dotnet/api/microsoft.powerplatform.management.environmentmanagement.environmentgroups.item.withgroupitemrequestbuilder.addenvironment?view=power-platform-latest`
   - `https://learn.microsoft.com/dotnet/api/microsoft.powerplatform.management.environmentmanagement.environmentgroups.item?view=power-platform-latest`
   - Confirms the route shape `environmentmanagement/environmentGroups/{id}/addEnvironment/{environmentName}` and the `environmentGroups` collection under the `environmentmanagement` provider.
2. **`pac admin create-service-principal`** (used in README Service Principal warning).
   - `https://learn.microsoft.com/power-platform/developer/cli/reference/admin` — confirms `admin create-service-principal` adds an Entra app (SPN) + application user to a Dataverse environment.
   - Service-principal-via-API/PAC CLI doc (preview) corroborates.
3. **`pac admin set-governance-config`** (used in `docs/flow-configuration.md` Step "baseline hardening").
   - `https://learn.microsoft.com/power-platform/developer/cli/reference/admin` — confirmed in the admin command group reference.
4. **`Set-AdminPowerAppEnvironmentGovernanceConfiguration`** PowerShell cmdlet (same flow step alternative).
   - Microsoft Learn "Enable Managed Environments" admin documentation references the `*GovernanceConfiguration` cmdlet for editing Managed Environment settings via PowerShell.
5. **Environment Groups capability constraints** (Managed-Environments-only, one group per environment, published group rules lock per-environment settings).
   - `https://learn.microsoft.com/en-us/power-platform/admin/environment-groups` (Environment groups admin guidance) — matches the constraints documented in `docs/prerequisites.md`.

## Gaps & fixes

**No code or documentation defects were found that require correction.** The
solution received a thorough Council Review remediation across v1.2.0 → v1.2.2
(April–May 2026) that already closed the classes of defects this validation
targets: legacy `1..N` option-set drift, deprecated relationship-creation
endpoints, false-PASS audit FetchXML, ImportError in `deploy.py` Phase 3,
managed-identity-first auth markers, and the invalid Power Automate `filter()`
signature. This static pass independently re-verified those areas and confirms
they remain correct.

- **Scripts:** all 12 compile; `elm_client.py` retry policy correctly excludes
  `DELETE` (immutability model) and `register_service_principal.py` correctly
  excludes `POST` from retries (non-idempotent Graph creates). Token audiences
  and the Graph `Group.Read.All` app-role ID (`5b567255-7703-4780-807c-7be8301ae99b`)
  and Graph resource app ID (`00000003-0000-0000-c000-000000000000`) are correct.
- **README / docs:** Purpose, Prerequisites, step-by-step Quick Start, expected
  outcomes, and validation scripts are all present and internally consistent.
- **Dependencies:** `requirements.txt` pins are security-current
  (`requests>=2.32.0` for CVE-2024-35195, `msal>=1.30.0`, `azure-identity>=1.18.0`).
  Required roles (Power Platform Admin, Entra Application Administrator,
  System Administrator, Key Vault Secrets Officer) and `pac` CLI usage are documented.

## Runtime-only caveats (cannot be verified statically; verify at deploy time)

1. **`api-version=2022-03-01-preview`** for the Environment Groups API is a
   **preview** version and is subject to change by Microsoft. The route and
   `addEnvironment` action are confirmed against the current Management SDK
   surface, but confirm the exact `api-version` string against the live
   `api.powerplatform.com` tenant response before relying on it in production.
2. **Live provisioning behavior** (async environment-creation polling, group
   rule lock interaction, DLP precedence) requires a tenant with Managed
   Environments licensing to exercise end-to-end.
3. **`docs/troubleshooting.md`** suggests `Connect-CrmOnline`
   (Microsoft.Xrm.Data.PowerShell) as a diagnostic aid. This community module
   still functions but is not the strategic PAC CLI path; it is a troubleshooting
   convenience only and does not affect the deployment scripts.
4. **GUID validation for `fsi_securitygroupid`** is intake-side only (Copilot
   agent), with no server-side business rule — already disclosed in the README
   "Known Limitations" table as a production hardening item.

## Lab-readiness assessment

**LAB-READY.** Static validation (parse-validity + authoritative-source
verification + documentation completeness) passes cleanly with no required
corrections. Every referenced Power Platform/Graph API endpoint, `pac` CLI
command, and PowerShell cmdlet was confirmed against Microsoft Learn. Auth is
managed-identity-first, Dataverse naming is canonical, option-set values are
canonical, and language rules are satisfied. The only outstanding items are
runtime-only behaviors that inherently require a licensed tenant, plus the
documented (and clearly labeled) preview `api-version` on the Environment
Groups API.
