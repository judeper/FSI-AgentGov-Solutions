# Credential Oversharing Detector - Changelog

All notable changes to this solution are documented here.

## [Unreleased]

### Added

- **Schema:** Added `fsi_ApprovedScopes` and `fsi_ActualScopes` memo columns to the `fsi_AgentConnectorScope` table in `create_cod_dataverse_schema.py`. This resolves the deferred limitation carried since v2.1.1: `Compare-OAuthScopeBaseline.ps1` queries `fsi_approvedscopes` / `fsi_actualscopes` on the baseline table, but those columns previously existed only on `fsi_credentialviolation` and `fsi_credentialexception`. The name-level OAuth scope baseline comparison now targets columns that exist on the queried entity instead of returning HTTP 400. Regenerated `docs/dataverse-schema.md` via `--output-docs`. Existing tenants must re-run `python scripts/create_cod_dataverse_schema.py` to add the two columns (additive, non-destructive migration).

### Fixed

- **Accuracy (Microsoft Learn re-verification):** Corrected the Microsoft 365 / O365 connectors ("Teams incoming webhooks") retirement date from the stale "March 31, 2026" to the authoritative schedule: connectors stop functioning after **May 22, 2026** (full deprecation rollout May 18-22, 2026). "March 31, 2026" was only an interim extended-support date, not the final retirement. Updated `docs/troubleshooting.md` and `.ralph-config.json`. Source: [Retirement of Office 365 connectors within Microsoft Teams](https://devblogs.microsoft.com/microsoft365dev/retirement-of-office-365-connectors-within-microsoft-teams/) and message center MC1181996.
- **Second-pass command-existence audit:** Migrated `Export-CredentialEvidence.ps1` off the deprecated/archived `MSAL.PS` module (`Get-MsalToken`) to `Az.Accounts` (`Connect-AzAccount` + `Get-AzAccessToken -ResourceUrl <DataverseUrl> -AsSecureString`), matching the Dataverse token-acquisition pattern already used by the other COD governance scripts. `MSAL.PS` is no longer maintained by Microsoft; removing it eliminates a future-break dependency and aligns the evidence-export auth path with the managed-identity-first standard. `-Interactive` and service-principal certificate (`-ClientId`/`-CertificateThumbprint`) flows are preserved. Updated `docs/prerequisites.md` to drop the `MSAL.PS` row.
- **Wave 6 P4b:** Empty catch blocks now log via `Write-Verbose` instead of silently swallowing errors. Output is unchanged unless caller passes `-Verbose`.

### Validation

- Lab-readiness static validation pass (no live tenant). All 9 PowerShell scripts parse cleanly; all 3 Python scripts compile; column references cross-checked against `create_cod_dataverse_schema.py`; auth token audiences and current Microsoft APIs verified against Microsoft Learn. See `LAB-VALIDATION.md`.

## [2.1.1] - 2026-05-22

### Fixed

- **Major**: Removed duplicate `[Parameter()]` attribute on `$ExcludeSandbox` in `scripts/governance/Test-CredentialCompliance.ps1:96-97`. (council review M-1)
- **Major**: Corrected `fsi_details` -> `fsi_description` column name in v2.1.0 violation writes (matches `fsi_credentialviolation` schema). `scripts/governance/Test-AgentAuthMethod.ps1:225` and `scripts/governance/Compare-OAuthScopeBaseline.ps1:188`. Previously the recommendation text was silently dropped on insert. (council review M-2)
- **Minor**: Replaced Microsoft Graph access token (`(Get-MgContext).AccessToken`) with Dataverse-audience token acquired via `Get-AzAccessToken -ResourceUrl $DataverseUrl` in `Test-AgentAuthMethod.ps1` and `Compare-OAuthScopeBaseline.ps1`. Graph-audience tokens produce HTTP 401 against `/api/data/v9.2`; v2.1.0 persistence was entirely non-functional. Both scripts now accept an optional `-DataverseToken` parameter for pre-acquired tokens. (council review m-5)
- **Minor**: `Get-MgApplicationFederatedIdentityCredential -ApplicationId` now receives the Application *object* ID resolved via `Get-MgApplication -Filter "appId eq '...'"` instead of the service principal's `AppId` (client ID). Previous code returned 404 for every service principal that had federated credentials. `scripts/governance/Test-AgentAuthMethod.ps1:128-141`. (council review m-8)
- **Minor**: Added GUID suffix to violation IDs in v2.1.0 scripts to prevent primary-key collisions when an agent has multiple deviations on the same day. `Test-AgentAuthMethod.ps1:219`, `Compare-OAuthScopeBaseline.ps1:177`. Follows the v2.0.0 pattern from `Invoke-CredentialScan.ps1`. (council review m-4)
- **Minor**: Added `Unclassified` to `Get-ExpectedCredentialPolicy.ps1` ValidateSet, defaults, and `zone-credential-policy.json`. `Invoke-CredentialScan.ps1` produces the literal `"Unclassified"` when an environment is missing zone metadata; the policy lookup previously threw a parameter-validation error and the `$zoneMap` returned `$null` to Dataverse. Also added `"Unclassified" = 100000000` to the `$zoneMap` in `Invoke-CredentialScan.ps1:651-660`. (council review m-2, m-3)
- **Minor**: Standardized severity label `Info` -> `Informational` in `scripts/governance/Export-CredentialEvidence.ps1:306` to match the rest of the solution (schema docs, policy file, scan script). (council review m-6)
- **Minor**: Added v2.1.0 and v2.1.1 entries to README Version History table. (council review m-7)
- **Minor**: Replaced `Get-Date -AsUTC` (PS 7.0+) with `(Get-Date).ToUniversalTime()` in `scripts/governance/Invoke-CredentialScan.ps1:201` for PS 5.1 lex/parse safety. The script's `Get-Date -Format ... -AsUTC` combination silently fails on Windows PowerShell runners.
- **Minor**: Replaced em-dashes (U+2014) with ASCII hyphens across all `.ps1` files (Wave 3 ACA precedent: PS 5.1 lexer chokes on em-dashes in non-BOM scripts).

### Known limitations (carried forward)

- `Compare-OAuthScopeBaseline.ps1` queries `fsi_approvedscopes` and `fsi_actualscopes` on `fsi_agentconnectorscope`, but the schema currently defines those memo columns only on `fsi_credentialviolation` and `fsi_credentialexception`. Adding them to the baseline table requires a schema column addition and tenant-side migration; tracked for the next minor bump. Until then, callers should treat the baseline comparison as a placeholder. (council review m-1, deferred)

## [2.1.0] - 2026-05-12

### Added

- **Workload identity CA policy detection** (`Get-WorkloadIdentityCAPolicy.ps1`): Enumerates Conditional Access policies targeting workload identities (managed identities, service principals) and cross-references with agent service principals to identify those without location-based restrictions or risk-based blocking. Reference: [Conditional Access for workload identities](https://learn.microsoft.com/entra/identity/conditional-access/workload-identity).
- **Certificate/MI auth detection** (`Test-AgentAuthMethod.ps1`): Inspects agent service principals to classify authentication methods as ManagedIdentity, Certificate, FederatedCredential, or ClientSecret. Flags client-secret usage as legacy/risky and recommends migration to managed identity. Records evidence to Dataverse for audit trail. Reference: [Power Platform authentication](https://learn.microsoft.com/power-platform/admin/programmability-authentication).
- **Name-level OAuth scope baseline** (`Compare-OAuthScopeBaseline.ps1`): Compares actual OAuth scopes against approved baseline at the individual scope name level (e.g., `Mail.Read`, `Files.ReadWrite.All`) using the `fsi_approvedscopes` / `fsi_actualscopes` columns in `fsi_agentconnectorscopes`. Detects excess scopes, sensitive scopes requiring elevated approval, and scope drift from the documented baseline. Replaces the prior count-only heuristic.

## [2.0.1] — 2026-05-04

### Fixed

- Refreshed Microsoft release-plan references for credential oversharing detection: current Microsoft Learn guidance lists public preview for July 2026 and general availability for September 2026, with standard release-plan caveats.
- Updated prerequisite module guidance for Microsoft.PowerApps.Administration.PowerShell 2.0.217+, Az.Accounts 2.17.0+ (5.3.4 validated), Microsoft.Graph 2.36.1+ for optional enrichment, and MSAL.PS 4.37.0.0+ for evidence export.
- Corrected service-principal setup instructions to include Power Platform management application registration via `New-PowerAppManagementApp`, and clarified that Graph application permissions are only needed for optional enrichment.
- Corrected `fsi_violationstatus` option-set values in the flow guide to match the Dataverse schema: Open, Remediated, ExceptionApproved, FalsePositive, UnderReview.
- Reworded Teams alert template metadata to use the Power Automate Teams connector rather than webhook terminology, consistent with Microsoft 365 connector retirement guidance.
- Bumped solution metadata and script note versions to 2.0.1.

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
- This solution tracks the Microsoft "Enforce safe sharing by detecting credential oversharing" feature; current release-plan timing was refreshed in 2.0.1.
- Organizations should verify feature availability in their tenant before production deployment.
- See [Microsoft release plan](https://learn.microsoft.com/en-us/power-platform/release-plan/2026wave1/microsoft-copilot-studio/enforce-safe-sharing-detecting-credential-oversharing) for current status.

## [0.1.0-preview] — 2026-03-01

### Added
- Initial documentation-only placeholder
- Namespace reservation for credential oversharing governance
- Boundary documentation with existing solutions
- Microsoft feature status tracking
