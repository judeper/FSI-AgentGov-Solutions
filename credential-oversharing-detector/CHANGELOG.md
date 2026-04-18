# Credential Oversharing Detector — Changelog

All notable changes to this solution are documented here.

## [2.0.0] — 2026-04-17 — BREAKING

This release applies the AI Council technical-accuracy review (Opus 4.7 + Goldeneye + GPT-5.4). It tightens detection correctness, hardens unattended execution, fixes API-shape bugs that would 400 against Dataverse, and replaces several misapplied regulatory citations.

### BREAKING

- `Invoke-CredentialScan.ps1` and `Test-CredentialCompliance.ps1`: `-ExcludeSandbox` changed from `[switch]$ExcludeSandbox = $true` (PowerShell anti-pattern that callers could not consistently disable) to `[bool]$ExcludeSandbox = $true`. Update any caller using `-ExcludeSandbox` (no value) to `-ExcludeSandbox $true`, or `-ExcludeSandbox $false` to include sandboxes.
- `OutputFormat 'JSON'` now returns ONLY the JSON string. Previously the scripts emitted JSON and *also* fell through to a `return [PSCustomObject]…`, polluting machine-readable output. Pipelines that depended on the duplicate object emission must switch to `-OutputFormat Object`.
- `Test-CredentialCompliance.ps1 -PersistResults` no longer POSTs a duplicate `fsi_credentialscans` row. It PATCHes the row already created by `Invoke-CredentialScan.ps1` (same `fsi_scanrunid`) with `fsi_overallstatus`, `fsi_compliantagents`, and `fsi_zonesummary`. Downstream consumers expecting two scan rows per run must adapt.
- Connection reference renamed: `fsi_cr_powerplatformadmin_credentialoversharing` (legacy `shared_powerappsforadmins`) → `fsi_cr_powerplatformadminv2_credentialoversharing` (`shared_powerplatformforadmins`). Copilot Studio bot/environment control-plane actions live in V2; the legacy connector cannot enumerate them.

### Critical

- Fixed `fsi_violationid` duplicate primary-key collisions. Previously `"COD-{type}-{first8charsofagentid}"` produced duplicates whenever an agent had multiple violations of the same type — every record after the first failed insert. Now appends a `[guid]::NewGuid().ToString('N').Substring(0,8)` suffix.
- Fixed double-write of `fsi_credentialscans` when both `Invoke-CredentialScan.ps1 -DataverseUrl` and `Test-CredentialCompliance.ps1 -PersistResults -DataverseUrl` were used together; orchestrator now PATCHes the existing row.
- Removed `accesscontrolpolicy` from `$select` on `bots` queries. That column does not exist on the bot entity; access control is modeled via related `botcomponent` / sharing entities. Strict Dataverse environments would 400 the query.
- Fixed OData GUID quoting in `Get-AgentConnectorScope.ps1 -AgentId` — was `botid eq 'guid'`, must be unquoted `botid eq guid`. Single-agent mode would have returned 400 for any valid input.

### High

- `Invoke-CredentialScan.ps1` and `Get-AgentConnectorScope.ps1` now call `Add-PowerAppsAccount -Endpoint <cloud> -ApplicationId -ClientSecret` before invoking `Get-AdminPowerAppEnvironment`, so unattended (service-principal) execution actually authenticates the Power Apps Admin module rather than relying on a cached interactive session.
- Sovereign-cloud support: new `-Cloud` parameter (`Public`/`USGov`/`USGovHigh`/`USGovDoD`/`China`/`Germany`) routes OAuth authority and the Power Platform Admin endpoint accordingly. Previously hard-coded to `login.microsoftonline.com` and `api.powerplatform.com`.
- Sandbox detection now filters on `EnvironmentType -ne "Sandbox"` (the documented surface) rather than the inconsistently-populated `Internal.properties.environmentSku` — Trial, Developer, and Teams environments were silently treated as non-sandbox.
- Multi-connector agents are now fully evaluated. Previously `$credentialId` was overwritten inside the connector loop, so cross-environment and shared-credential rules only saw the *last* connection ID per agent. Both rules now iterate over all connection IDs.
- `SharedCredentialMisuse` no longer regex-matches against the raw configuration JSON of every other agent (which produced false positives whenever a connection-ID substring appeared anywhere). It now uses a pre-built per-agent connection-id index.
- JSON return-mode bug fix in `Invoke-CredentialScan.ps1`, `Test-CredentialCompliance.ps1`, and `Get-AgentConnectorScope.ps1`.
- `Test-CredentialCompliance.ps1` requires `Az.Accounts >= 2.17.0` (formal `#Requires` pin) — that minimum is needed for `Get-AzAccessToken -AsSecureString`.

### Medium

- Zone option set now resolves `100000000` to `"Unclassified"` (was silently collapsed into `"Unknown"`). `"Unknown"` is reserved for environments with no entry in `fsi_environments`.
- `Test-CredentialCompliance.ps1` derives the zone list from the policy file (`templates/zone-credential-policy.json`) plus the scan results, rather than the previous hard-coded `('Zone1','Zone2','Zone3','Unknown')`. New zones added to the policy are automatically rolled up.
- `fsi_credentialscans` now includes `fsi_scancompletedat` on every persisted scan record (was previously never set; `Failed`/`InProgress` option-set values were dead code).
- `Export-CredentialEvidence.ps1`: informational findings are now counted in the summary and produce overall status `"Informational"` instead of being silently labeled `"Compliant"`.
- Regulatory citations corrected. `Get-ExpectedCredentialPolicy.ps1` and `templates/zone-credential-policy.json` previously cited "SEC 17a-4 access controls" — SEC 17a-4 is a records-retention rule, not an access-control rule. Critical zone now references GLBA 501(b) safeguards rule, SEC Reg S-P, and FINRA Rule 3110 supervisory controls (with SEC 17a-4 retained only for evidence retention of resulting records).
- README control-mapping titles corrected to match the framework: 1.14 = "Data Minimization and Agent Scope Control" (was "Content & Data Loss Prevention"); 1.4 = "Advanced Connector Policies (ACP)" (was "Approved Connector Governance"); 1.18 = "Application-Level Authorization and RBAC" (was "Agent Sharing Controls").
- `docs/flow-configuration.md` now documents the required columns when inserting `fsi_credentialscans`, `fsi_credentialviolations`, and `fsi_credentialexceptions` — flow builders previously got 400s on insert.
- `docs/troubleshooting.md` retry-and-backoff claim corrected — the scripts do **not** implement automatic 429 retry/backoff in this release.
- `docs/prerequisites.md` Microsoft Entra ID permissions section reworked: scanners do not currently call Microsoft Graph, so the previously-required `Application.Read.All` and `Directory.Read.All` are now documented as optional/future and reduced to least-privilege (`Application.Read.All` + `ServicePrincipal.Read.All`).
- `docs/prerequisites.md` zone-fallback-to-naming-heuristic claim removed (not implemented).

### Low

- `Export-CredentialEvidence.ps1` examples: `contoso.onmicrosoft.com` → `example.onmicrosoft.com`.
- `templates/adaptive-card-credential-alert.json` `_metadata.flowIntegration` updated: removed Teams Incoming Webhook recommendation (retired by Microsoft 31 Mar 2026); explicit guidance that `Action.Submit` requires a bot/Workflow endpoint to capture acknowledgement.
- `docs/dataverse-schema.md` regenerated from `create_cod_dataverse_schema.py` — previously omitted `fsi_scanrunid`, `fsi_totalenvironments`, `fsi_overallstatus`, `fsi_compliantagents`, `fsi_zonesummary` on the scan table.
- `.ralph-config.json` refreshed to reflect resolved drift and add new domain facts (Power Platform connector V2 vs legacy, OData GUID quoting, `accesscontrolpolicy` non-existence).

### Known Limitations

- **Semantic scope-vs-baseline comparison is heuristic, not exact.** `OverprivilegedConnector` and `ExcessiveOAuthScope` compare scope *counts* against `MaxOAuthScopes`. They do not (yet) compare actual scope names against per-agent declared/approved baselines. A connector carrying `Sites.FullControl.All` could pass if the total scope count stays under the zone threshold. The schema includes `fsi_approvedscopes`, `fsi_actualscopes`, and `fsi_agentconnectorscope` for a future Tier 2 release that will perform name-level comparison.
- **Detection sources `bot.configuration` JSON.** This is not a publicly documented contract surface — schema changes by Microsoft can silently degrade detection. Tier 2 will move to supported `connectionreferences` + Power Platform Admin V2 metadata.
- **No automatic 429/5xx retry/backoff.** Implement at the Power Automate flow level (HTTP action retry policy) or wrap calls externally.
- **No naming-convention zone fallback.** Environments not registered in ELM `fsi_environments` resolve to the `Unknown` zone.

### Migration

1. Review any pipelines passing `-ExcludeSandbox` as a switch; convert to `-ExcludeSandbox $true|$false`.
2. Pipelines that consume `-OutputFormat JSON` and the prior duplicate object emission must switch to `-OutputFormat Object` for the object form.
3. If you previously created the `fsi_cr_powerplatformadmin_credentialoversharing` connection reference, create the new V2 reference and rebuild Flow 1 to use it.
4. Set `-Cloud` parameter on scan invocations in sovereign tenants (defaults to `Public`).
5. Re-run `python scripts/create_cod_dataverse_schema.py --output-docs` if you forked `docs/dataverse-schema.md`.

## [1.0.1] — 2026-04-15

### Fixed

- Critical: Scan persistence uses fsi_scanid instead of non-existent fsi_name
- Critical: Violation persistence uses fsi_violationid and adds required fsi_violationstatus
- Critical: Export uses correct column names (fsi_scanstartedat, fsi_agentsscanned, fsi_violationsfound)
- Zone filter in evidence export uses integer option set values instead of string literals

## [1.0.0] — 2026-04-01

### Added
- Dataverse schema with 5 tables: CredentialScan, CredentialViolation, CredentialPolicy, CredentialException, AgentConnectorScope
- 5 COD-specific option sets plus shared zone classification
- 11 environment variables for scan configuration, alerting, and exception management
- 4 connection references for Dataverse, Teams, Approvals, and Power Platform Admin
- `Invoke-CredentialScan.ps1` — main credential scope scanning script
- `Test-CredentialCompliance.ps1` — zone compliance validation orchestrator
- `Get-AgentConnectorScope.ps1` — per-agent connector scope extraction
- `Get-ExpectedCredentialPolicy.ps1` — zone-based policy lookup
- `Export-CredentialEvidence.ps1` — evidence export with SHA-256 integrity hash
- `Test-EvidenceIntegrity.ps1` — evidence hash verification
- Zone credential policy baseline template with Zone 1/2/3 thresholds
- Teams adaptive card template for scan alerts
- Prerequisites documentation
- Flow configuration guide with manual build instructions for 3 flows
- Troubleshooting guide
- Auto-generated Dataverse schema documentation

### Changed
- Upgraded from documentation-only placeholder (v0.1.0-preview) to full solution

### Notes
- This solution leverages the Microsoft "Enforce safe sharing by detecting credential oversharing" feature (public preview April 2026)
- Organizations should verify feature availability in their tenant before production deployment
- See [Microsoft release plan](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/microsoft-copilot-studio/enforce-safe-sharing-detecting-credential-oversharing) for current status

## [0.1.0-preview] — 2026-03-01

### Added
- Initial documentation-only placeholder
- Namespace reservation for credential oversharing governance
- Boundary documentation with existing solutions
- Microsoft feature status tracking
