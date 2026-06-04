# Lab Validation Report — Agent Access Governance Monitor

> **Scope:** Static lab-readiness validation (no live tenant). Validation method =
> parse-validity + authoritative-source verification + documentation completeness.
> **Date:** 2026-06-04 · **Solution version:** v1.1.2 · **Branch:** `validation/agent-access-monitor`

## Purpose and controls

The Agent Access Governance Monitor (AAM) detects Power Platform environments whose
Managed Environment agent-sharing settings deviate from zone-specific governance
requirements. It supports compliance with:

- **Control 3.8** — Copilot Hub and Governance Dashboard (primary)
- Related: 2.5 (agent sharing scope), 2.6 (restrict team-created agent sharing), 1.1
  (restrict publishing), 2.1 (Managed Environments)
- Regulatory context surfaced in output: FINRA Rule 4511, SOX 404, GLBA 501(b)

The solution evaluates three Managed Environment `extendedSettings` keys —
`bot-limitSharingMode`, `bot-authoringSharingDisabled`,
`bot-publishedBotLimitSharingMode` — against per-zone baselines, persists results to
three Dataverse tables, and exports tamper-evident JSON evidence with SHA-256 hashes.

## What was checked

| Area | Method | Result |
|------|--------|--------|
| PowerShell parse validity (11 `.ps1`) | `Parser::ParseFile` | 0 errors |
| Python compile (5 `.py`) | `python -m py_compile` | 0 errors |
| `templates/*.json` well-formedness | `json.load` | OK |
| Managed Environment setting keys/values | Microsoft Learn (authoritative) | Confirmed |
| Settings object path (`Get-EnvironmentAccessSettings.ps1`) | Microsoft Learn + internal consistency | **Bug found + fixed** |
| Zone baseline semantics (`zone-settings-baseline.json`) | Microsoft Learn | **Reversed description fixed** |
| Dataverse column logical names | `create_dataverse_schema.py` (source of truth) vs scripts/docs | Consistent |
| Option-set values (zone/severity) | schema script vs `dataverse-schema.md` | Consistent |
| Authentication model | repo standard (managed-identity-first) | Compliant; legacy paths marked |
| `Get-AdminPowerAppEnvironmentGroup` cmdlet | Microsoft Learn module reference | **Not found — flagged** |
| Regulatory language rules | grep prohibited phrases | Clean |

## Authoritative sources cited

1. **Limit sharing (Managed Environments)** —
   <https://learn.microsoft.com/power-platform/admin/managed-environment-sharing-limits>
   Confirms: setting keys `bot-limitSharingMode` (values `ExcludeSharingToSecurityGroups`,
   `noLimit`) and `bot-authoringSharingDisabled` (`True`/`False`); the settings object path
   `$environment.Internal.properties.governanceConfiguration.settings.extendedSettings`;
   `Get-AdminPowerAppEnvironment` / `Set-AdminPowerAppEnvironmentGovernanceConfiguration`
   cmdlets; that "Exclude sharing with security groups" means sharing is limited to
   individuals (security-group sharing is excluded); that rules "may take up to an hour"
   to enforce and "don't impact any existing users who already have access."
2. **Get-AdminPowerAppEnvironment** —
   <https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/get-adminpowerappenvironment>
3. **Set-AdminPowerAppEnvironmentGovernanceConfiguration** —
   <https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/set-adminpowerappenvironmentgovernanceconfiguration>
4. **Microsoft.PowerApps.Administration.PowerShell module reference** —
   <https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/>

## Gaps and fixes

### Fixed — settings extraction object path (Major)

`Get-EnvironmentAccessSettings.ps1` read the sharing settings from
`$env.Internal.governanceConfiguration.settings.extendedSettings` (two sites). The
authoritative Microsoft sample reads
`$environment.Internal.properties.governanceConfiguration.settings.extendedSettings`,
and the same script already uses `$env.Internal.properties.environmentGroup` and
`$env.Internal.properties.linkedEnvironmentMetadata` for sibling fields — so the missing
`.properties.` segment was internally inconsistent. With the wrong path, all three bot
settings resolved to `null`; `Compare-ZoneCompliance.ps1` then substitutes platform
defaults (`noLimit` / `false`), which violate Zone 2/3 expectations and would emit
systematic false Critical/High violations and corrupt captured baselines. Corrected both
extraction sites and the helper synopsis.

> **Runtime caveat:** Verified against the authoritative source and internal code
> consistency only. The actual runtime shape of `Get-AdminPowerAppEnvironment().Internal`
> could not be exercised without a live Managed Environment tenant. Recommended lab check:
> run `Get-EnvironmentAccessSettings -Verbose` and confirm `BotLimitSharingMode` is
> populated (not null) for an environment known to have sharing limits configured.

### Fixed — reversed zone-baseline setting descriptions (Minor)

`templates/zone-settings-baseline.json` described `ExcludeSharingToSecurityGroups` as
"restricted to security groups only" — the opposite of the documented behavior (sharing
with security groups is *excluded*; sharing is limited to individuals). Corrected both the
`bot-limitSharingMode` and `bot-publishedBotLimitSharingMode` descriptions, which feed
violation/evidence output and operator-facing alerts.

### Flagged — environment-group cmdlet not found (no code change)

`Get-EnvironmentAccessSettings.ps1` enriches environment-group names via
`Get-AdminPowerAppEnvironmentGroup`. This cmdlet is **not present** in the published
`Microsoft.PowerApps.Administration.PowerShell` module reference on Microsoft Learn. The
call is best-effort and wrapped in `try/catch` with `-ErrorAction SilentlyContinue`, so a
missing cmdlet degrades gracefully: the environment-group GUID is still captured from
`$env.Internal.properties.environmentGroup.id`, only the friendly group name is omitted.
No change was made because (a) it does not block validation, and (b) module versions
evolve and a future/region-specific build may expose it. **Lab action:** confirm cmdlet
availability with `Get-Command Get-AdminPowerAppEnvironmentGroup` in your installed module
version; if absent, group-name enrichment will be empty (non-fatal).

## Items verified as already correct (no change)

- **Dataverse logical names** in all OData `$select`/`$filter` calls and docs match the
  SchemaNames lowercased in `create_dataverse_schema.py` (e.g. `fsi_environmentguid`,
  `fsi_isactive`, `fsi_validationtime`, `fsi_severitylabel`).
- **Option-set integers** (`fsi_acv_zone`, `fsi_acv_severity`) in `AAMClient.psm1`,
  evidence export, and `dataverse-schema.md` are consistent with the schema script,
  including the documented Critical/High → `100000003` (Failed) collapse disambiguated by
  `fsi_severitylabel`.
- **Authentication** is managed-identity-first: `aam_client.py`/`deploy.py` prefer
  `ManagedIdentityCredential` / `WorkloadIdentityCredential`, with client-secret paths
  carrying the `# legacy: dev-only` marker; `requirements.txt` pins `azure-identity` and
  `msal`. PowerShell runbook/evidence paths use MSAL certificate auth (documented as the
  current supported path) and the docs steer unattended automation toward managed identity.
- **Regulatory language** — no prohibited phrases ("ensures compliance", "guarantees",
  "will prevent", "eliminates risk") in solution Markdown.
- **Content policy** — no Power Platform runtime artifacts; the flow is documented as a
  manual build in `docs/flow-configuration.md`.

## Final lab-readiness assessment

**Lab-ready, with one runtime-verification step.** Parse/compile baselines are clean,
documentation is complete and accurate, naming/auth conventions are honored, and the two
authoritative-source discrepancies (settings object path; reversed baseline description)
are corrected. The single residual risk is that the settings-path fix and the
environment-group cmdlet availability cannot be exercised without a live Managed
Environment tenant. Before relying on results in a lab, run
`Get-EnvironmentAccessSettings -Verbose` against a configured Managed Environment and
confirm the three `Bot*` properties populate as expected.
