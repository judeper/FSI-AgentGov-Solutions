# Lab Validation Report — Action Confirmation Auditor (ACA)

> **Validation type:** Static (no live tenant). Parse-validity + authoritative
> Microsoft source verification + documentation completeness.
> **Date:** 2026-06-04
> **Solution version:** v1.2.1 (fixes recorded under CHANGELOG `[Unreleased]`)

## Solution Purpose & Target Controls

ACA scans Power Platform environments for Copilot Studio agent topics that invoke
actions (connector calls, cloud flows, plugins, HTTP requests) without a
human-in-the-loop (HITL) confirmation step, classifies violations by zone and
action type, and supports exception management with Maker/Checker gating.

- **Primary control:** 2.12 — Supervision and Oversight / HITL checkpoints (FINRA Rule 3110)
- **Supporting control:** 1.10 — Communication Compliance Monitoring
- **Regulatory context:** FINRA Rule 3110, GLBA Section 501(b), SOX Section 404

## What Was Checked

- **PowerShell (14 files):** parse-validity via `[Parser]::ParseFile` — all pass.
- **Python (5 files):** `python -m py_compile` — all pass.
- **Dataverse column references:** cross-checked every `$select`/`$filter`/record
  write against `scripts/create_dataverse_schema.py` and `docs/dataverse-schema.md`
  (the source of truth) and `.ralph-config.json` domain facts.
- **Authentication patterns:** verified managed-identity-first standard; client
  secret path in `Connect-EnvironmentDataverse.ps1` carries the `# legacy: dev-only`
  marker.
- **API usage:** Microsoft Graph audit log query API, `Invoke-MgGraphRequest`,
  `Get-AzAccessToken` SecureString behavior, Power Platform admin token audience,
  Dataverse Web API `v9.2` endpoints.
- **Language rules:** grep for the FSI-prohibited compliance-absolute phrases
  (per `fsi-language-rules.instructions.md`) outside CHANGELOG — zero hits.

## Authoritative Sources Cited

| Topic | Source |
|-------|--------|
| Graph audit log query API on **v1.0**, `recordTypeFilters`, `auditLogRecordType` enum (`aipDiscover`, `aipSensitivityLabelAction`) | `https://learn.microsoft.com/graph/api/resources/security-auditlogquery` and `https://learn.microsoft.com/graph/api/security-auditlogquery-list-records` |
| `Get-MgContext` exposes ClientId/TenantId/Scopes/AuthType — **not** an access token | `https://learn.microsoft.com/powershell/microsoftgraph/authentication-commands` |
| `Invoke-MgGraphRequest` for authenticated Graph REST calls in PowerShell | `https://learn.microsoft.com/powershell/module/microsoft.graph.authentication/invoke-mggraphrequest` |
| `Get-AzAccessToken` default output changed to SecureString; `-ResourceUrl` usage | `https://learn.microsoft.com/powershell/module/az.accounts/get-azaccesstoken` |
| Power Platform admin token audience `https://service.powerapps.com/` | `https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/get-jwttoken` |
| `Microsoft.PowerApps.Administration.PowerShell` is a Windows PowerShell 5.x (.NET Framework) module | Repo `.ralph-config.json` domain fact + prerequisites.md |
| Azure Automation managed identity (RunAs deprecation) | `https://learn.microsoft.com/azure/automation/learn/powershell-runbook-managed-identity` |
| Purview AI Hub / DSPM for AI | `https://learn.microsoft.com/purview/ai-microsoft-purview` |

## Gaps Found and Fixes Applied

### Scripts

1. **`Get-PurviewAIHubEvidence.ps1` — broken Graph authentication (functional bug).**
   Built bearer headers from `(Get-MgContext).AccessToken`, which is always
   `$null` (the context object has no token property). Both the Graph audit query
   and the Dataverse query sent empty tokens. **Fix:** Graph calls now use
   `Invoke-MgGraphRequest` (reuses the `Connect-MgGraph` session, correct
   audience). Added a begin-block guard that errors clearly if no Graph session
   exists.

2. **`Get-PurviewAIHubEvidence.ps1` — wrong token audience for Dataverse.**
   The Dataverse query reused the (empty) Graph token; even when populated, a
   Graph-audience token is rejected by Dataverse. **Fix:** added
   `-DataverseAccessToken` (SecureString) parameter plus an `Az.Accounts`
   fallback (`Get-AzAccessToken -ResourceUrl <DataverseUrl>`), managed-identity-first.

3. **`Get-PurviewAIHubEvidence.ps1` — non-existent column `fsi_hasconfirmation`.**
   The schema has no such column. **Fix:** query `fsi_confirmationstatus`
   (option set, `Present = 100000000`) and derive `HasConfirmation` as a boolean.

4. **`Get-PurviewAIHubEvidence.ps1` — recordTypeFilters values.** The
   `recordTypeFilters` use documented camelCase members of the v1.0
   `auditLogRecordType` enum (`aipDiscover`, `aipSensitivityLabelAction`).
   `copilotInteraction` is **not** a member of that enum (it is a beta
   record subtype, `copilotInteractionAuditRecord`, not a filter value), so
   it was removed — an unknown evolvable-enum member returns HTTP 400 and
   fails the whole query. Copilot interaction activity is collected via the
   Activity Explorer fallback.

5. **`Start-ActionConfirmationRunbook-MI.ps1` — wrong token audience for Power
   Platform admin.** Acquired a Graph token and passed it to
   `Add-PowerAppsAccount`; the module needs a `https://service.powerapps.com/`
   token, so environment enumeration would fail. **Fix:** acquire the Power
   Apps-audience token via `Get-AzAccessToken -ResourceUrl 'https://service.powerapps.com/'`.

### Docs

6. **`docs/prerequisites.md`** — added an "Optional: Purview AI Hub / DSPM
   Integration" section documenting the previously-undocumented dependencies:
   the `AuditLogsQuery.Read.All` Graph scope and the separate Dataverse token.

7. **`CHANGELOG.md`** — recorded all fixes under the existing `[Unreleased]` entry.

### Dependencies

- No dependency files changed. `scripts/requirements.txt` (`msal`, `requests`)
  is sufficient for the Python setup path. The Purview script's
  `Az.Accounts`/`Microsoft.Graph.Authentication` needs are now documented.

## Verified Healthy (no change needed)

- Core scanner `Get-AgentActionSettings.ps1`: queries `botcomponents` with
  `_botid_value`, `componenttype` 12/2, Dataverse Web API `v9.2` — endpoint
  shape correct. Per-environment Dataverse tokens are acquired via
  `Connect-EnvironmentDataverse.ps1` (Az/MI, correct audience).
- `Export-ActionAuditEvidence.ps1`, `ACAClient.psm1`,
  `Test-UserDefinedActionMessages.ps1`, `Start-ActionConfirmationValidationRunbook.ps1`,
  `docs/flow-configuration.md`: all Dataverse column references and option-set
  integers (100000000+) match the schema.
- Auth standard: client-secret path is marked `# legacy: dev-only`; interactive
  and managed-identity paths are present.

## Runtime-Only Verification Items (cannot confirm statically)

- **Topic-content parsing fidelity.** `Get-AgentActionSettings.ps1` detects
  action nodes and confirmation patterns with regular expressions over
  `botcomponent.content`. The exact `kind` values (`InvokeFlowAction`,
  `InvokeConnectorAction`, `InvokeSkillAction`, etc.) and the confirmation
  heuristics should be validated against real published Copilot Studio agent
  topic JSON; node schemas can change and are not publicly versioned.
- **`Add-PowerAppsAccount -AccessToken` with a managed-identity token.** Microsoft
  documents service-principal auth as the supported automation path; passing an
  MI-issued Power Apps-audience token is a reasonable pattern but is not
  explicitly documented as supported. Confirm in a live Automation account.
- **Graph audit log query latency.** The script polls once after a 5-second
  delay; real audit queries may take longer to return records. Confirm and tune
  poll/retry against a live tenant.
- **DSPM for AI availability / Copilot audit record types.** Copilot
  interaction activity is collected via the Activity Explorer fallback;
  presence of those records depends on tenant licensing and audit
  configuration.

## Final Lab-Readiness Assessment

**Lab-ready.** All scripts parse/compile; the two functional authentication
defects (Purview evidence script and the MI runbook) and the schema column
mismatch are fixed and verified against authoritative Microsoft sources. The core
scan path and evidence export were already aligned to the schema. Remaining items
are inherently runtime-verification concerns (live-tenant parsing fidelity and
service availability), documented above rather than assumed.
