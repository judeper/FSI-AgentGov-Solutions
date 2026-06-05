# Changelog

All notable changes to the Agent Communication Restriction Detector are documented in this file.

## [Unreleased]

### Fixed

- **`docs/prerequisites.md` listed a non-existent Microsoft Graph permission for environment enumeration.** The API Permissions table claimed `Microsoft Graph` `Environment.Read.All` (Application) was required for "Power Platform environment enumeration." No such Microsoft Graph permission exists, and environment enumeration is actually performed by `Get-AdminPowerAppEnvironment` (`Microsoft.PowerApps.Administration.PowerShell`, BAP admin API) under the Power Platform Admin role — no Graph app permission is needed. Replaced the row with the permission that is genuinely required: Microsoft Graph [`Policy.Read.All`](https://learn.microsoft.com/graph/api/crosstenantaccesspolicy-get) (Delegated or Application), which `Get-CrossTenantAccessCorrelation.ps1` needs to read the [cross-tenant access policy](https://learn.microsoft.com/graph/api/resources/crosstenantaccesspolicyconfigurationpartner). Added a note clarifying how environment enumeration is authorized. `Get-AgentSkillRegistrations.ps1` filtered skill components with `componenttype eq 2 or componenttype eq 10`, but per the Dataverse [botcomponent table reference](https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/botcomponent) (`botcomponent_componenttype` option set) `2` = *Bot variable* and `10` = *Bot translations (V2)* — skills are `1` (*Skill*) and `13` (*Skill (V2)*). The same script and `Test-ChildAgentPayloadSize.ps1` also referenced a `_botid_value` column that does not exist on `botcomponent`; the owning bot is the `parentbotid` lookup (`botcomponent_parent_bot` relationship), exposed in OData as `_parentbotid_value`. Both queries would have returned the wrong records or HTTP 400 in a live environment. Corrected the option-set integers to `1`/`13`, switched the lookup to `_parentbotid_value`, and removed the quotes around the GUID (Dataverse lookup `_value eq` filters take an unquoted `Edm.Guid`).
- **`Get-CrossTenantAccessCorrelation.ps1` read `isServiceProvider` off the wrong Graph object.** The script accessed `$partner.B2BCollaborationInbound.IsServiceProvider` and `$partner.B2BDirectConnectInbound.IsServiceProvider`, but per the Microsoft Graph [`crossTenantAccessPolicyConfigurationPartner`](https://learn.microsoft.com/graph/api/resources/crosstenantaccesspolicyconfigurationpartner) resource, `isServiceProvider` is a property of the partner object itself — `b2bCollaborationInbound`/`b2bDirectConnectInbound` are `crossTenantAccessPolicyB2BSetting` objects that expose `usersAndGroups`/`applications`, not `isServiceProvider`. The previous expressions always evaluated to `$null`. Now reads `IsServiceProvider` from the partner and records inbound B2B collaboration / direct-connect configuration as presence checks.

### Changed

- **`Test-ChildAgentPayloadSize.ps1` advisory threshold made configurable and reference corrected.** The script claimed a "documented 1 MB Copilot Studio limit" and cited `microsoft-copilot-studio/advanced-flow-input-output`, which no longer documents a child-agent input/output byte limit (the page now redirects to general agent-flow guidance). Current published [Copilot Studio limits](https://learn.microsoft.com/microsoft-copilot-studio/requirements-quotas#copilot-studio-web-app-limits) document a 5 MB connector payload limit (450 KB GCC) and a 28 KB Omnichannel channel-data limit, but no explicit child-agent payload byte limit. Reframed the 1 MB value as a configurable advisory heuristic via a new `-PayloadLimitKB` parameter (default 1024), widened threshold validation ranges accordingly, updated finding text and the `PlatformReference` URL, and corrected the README feature description.
- **`docs/prerequisites.md` corrected MSAL.PS / Az.Accounts roles.** MSAL.PS was mislabeled as "Evidence export authentication"; `Export-CommViolationEvidence.ps1` migrated to Az.Accounts in v1.2.1. MSAL.PS is now documented as a runbook-only certificate-auth dependency (and flagged as archived), and the Az.Accounts minimum was raised to 2.17+ to match the Export script's `#Requires`.
- `Get-CrossTenantAccessCorrelation.ps1` and `Test-ChildAgentPayloadSize.ps1` now honor `-WhatIf` by returning before Graph or Dataverse scan work when `ShouldProcess` declines the operation.
- Documented the previously undocumented `-IncludeCompliant` parameter in `Get-CrossTenantAccessCorrelation.ps1` comment-based help.

## [1.2.1] - 2026-05-23

### Fixed

- **CRITICAL (C-1) — Wrong audience for Dataverse Web API call.** `Get-CrossTenantAccessCorrelation.ps1` was sending a Microsoft Graph access token (`(Get-MgContext).AccessToken`) as the `Authorization` header to Dataverse. Graph-audience tokens are rejected with `401 Unauthorized` by Dataverse. The script now acquires a Dataverse-audience bearer via the existing `scripts\private\Connect-EnvironmentDataverse.ps1` helper (which already handles managed-identity, service-principal, and interactive paths plus Az.Accounts SecureString unwrap) before issuing the OData query. (council review C-1)
- **CRITICAL (C-2) — `Get-Date -AsUTC` is PowerShell 7.1+ only.** Three call sites in `Import-ApprovedCommRoutes.ps1` and `Start-CommRestrictionValidationRunbook.ps1` used the `-AsUTC` switch, which throws `A parameter cannot be found that matches parameter name 'AsUTC'` on Windows PowerShell 5.1 — the runtime declared by `#requires` for the runbook and admin scripts. Replaced all three with `(Get-Date).ToUniversalTime().ToString('o')`. (council review C-2)
- **CRITICAL (C-3) — Property access on the wrong return type.** `Test-ChildAgentPayloadSize.ps1` invoked `Connect-EnvironmentDataverse` as if it were a function and dereferenced `.AccessToken` on its return value. `Connect-EnvironmentDataverse.ps1` is a parameterized **script** that returns the bearer token as a plain `[string]`, not an object. Rewrote the invocation to use the call operator (`& <path> -DataverseUrl $url`), matching the established pattern in `Get-AgentSkillRegistrations.ps1`. (council review C-3)

### Changed

- **Major (M-1) — Migrated Python deployment scripts off the solution-local `acrd_client.py` onto the shared `scripts/shared/dataverse_client.py`.** `create_dataverse_schema.py`, `create_environment_variables.py`, `create_connection_references.py`, and `deploy.py` now import the shared client and use its dict-based metadata API (`create_option_set(metadata)`, `create_entity(metadata)`, `create_column(entity_logical_name, metadata)`). Added internal `_build_optionset_metadata()`, `_build_table_metadata()`, and `_build_column_metadata()` helpers in `create_dataverse_schema.py` modelled on the `cross-tenant-external-sharing-governance` pattern, so the metadata shape stays declarative and reviewable. **Breaking change for direct importers only**: `acrd_client.py` is now a deprecation stub that emits a `DeprecationWarning` and raises `ImportError` (modelled on `unrestricted-agent-sharing-detector/scripts/uasd_client.py`). External callers that imported `ACRDClient` directly must switch to `from dataverse_client import DataverseClient`. CLI entry points are backward-compatible: existing `--tenant-id` / `--client-id` / `--client-secret` / `--interactive` invocations work unchanged. (council review M-1)
- **Major (M-2) — Synchronised stale version strings to 1.2.1.** Bumped header `Version:` comments, banner strings, and footer markers in `Test-CommRestrictionCompliance.ps1`, `Export-CommViolationEvidence.ps1` (`solutionVersion` and `exportVersion`), `Start-CommRestrictionValidationRunbook.ps1`, `Import-ApprovedCommRoutes.ps1`, `Connect-EnvironmentDataverse.ps1`, and `docs/flow-configuration.md`. Files not modified in v1.2.0 (e.g. `Test-EvidenceIntegrity.ps1`) retain their existing version strings per the convention "only bump on files we change". (council review M-2)
- **Major (M-3) — Removed phantom `CommunicationPattern` reference from `docs/flow-configuration.md`.** This field was dropped from the runbook output schema in v1.1.0 (see CHANGELOG [1.1.0] Breaking notes) but a stray narrative reference survived in the flow-configuration doc, misleading administrators wiring up Parse JSON actions. Replaced with a pointer to the `SkillSnapshot` field that now carries per-skill detail in `fsi_summaryjson`. (council review M-3)
- **Major (M-4) — Broadened Dataverse URL `ValidatePattern` regexes to cover sovereign clouds.** `Connect-EnvironmentDataverse.ps1`, `Get-CrossTenantAccessCorrelation.ps1`, and `Test-ChildAgentPayloadSize.ps1` previously hard-coded `*.dynamics.com`, silently rejecting US Government (`*.crm.microsoftdynamics.us`) and German (`*.crm.microsoftdynamics.de`) tenants. Widened all three patterns to the council-recommended form that accepts commercial and sovereign clouds plus optional trailing slashes. (council review M-4)
- **Major (M-5) — Migrated `Export-CommViolationEvidence.ps1` from MSAL.PS to Az.Accounts.** MSAL.PS was archived by its maintainer in 2024 and is no longer receiving security updates. Replaced both the interactive and service-principal auth blocks with `Get-AzAccessToken` (after `Connect-AzAccount` / `Connect-AzAccount -ServicePrincipal`) and added the `Unprotect-AzAccessToken` helper that handles the SecureString return type introduced in Az.Accounts 2.17 (concatenating a SecureString into an `Authorization` header otherwise produces `'Bearer System.Security.SecureString'` and HTTP 401). Bumped `#Requires -Modules` to `Az.Accounts >= 2.17.0`. (council review M-5)
- **Major (M-6) — Documented the shared option-set integer-value deviation.** Added an inline block comment in `create_dataverse_schema.py` SHARED_OPTIONSETS section explaining why `fsi_acv_zone` (values 0-3) and `fsi_acv_severity` (values 1-5) keep low-integer option values rather than the 100000000+ convention used elsewhere in the solution. These two option sets are shared cross-solution allowlisted exceptions per the style-decisions guide; migrating them would break consumers of every solution that already references the low integers. (council review M-6)

### Minor improvements

- Added `azure-identity>=1.15.0` to `scripts/requirements.txt`. It is loaded lazily by the shared `DataverseClient` only when `--auth-mode managed-identity`, `workload-identity`, or `certificate` is requested, but declaring it explicitly removes the runtime surprise for operators preparing production deployments. (council review m-5)
- Widened the Python CLI surface of `create_dataverse_schema.py`, `create_environment_variables.py`, `create_connection_references.py`, and `deploy.py` to expose the shared client's full auth ladder: `--auth-mode {interactive,managed-identity,workload-identity,certificate,client-secret}`, `--certificate-path`, `--certificate-password`, and `--access-token` (for parent-process token passthrough). Existing `--client-id` / `--client-secret` flags remain and are marked dev-only in their help text per the repo's managed-identity-first authentication standard.

## [1.2.0] - 2026-05-12

### Added

- **Cross-tenant Entra correlation** (`Get-CrossTenantAccessCorrelation.ps1`): Pulls cross-tenant access policy from Microsoft Graph (`crossTenantAccessPolicy` and partner configurations), cross-references with ACRD CROSS_TENANT_VIOLATION records in Dataverse, and flags agents communicating with tenants outside the allowed cross-tenant access policy. Emits risk-level classification (Critical/High/Low) with B2B direct connect and inbound trust context.
- **Child-agent payload size validation** (`Test-ChildAgentPayloadSize.ps1`): Scans Copilot Studio `InvokeConnectedAgentTaskAction` topic nodes and estimates child-agent input/output payload sizes against the documented 1 MB limit. Emits Warning (≥768 KB), High (≥960 KB), and Critical (≥1 MB) findings with optimization recommendations. Reference: [Copilot Studio flow input/output](https://learn.microsoft.com/microsoft-copilot-studio/advanced-flow-input-output).

## [1.1.1] - 2026-05-04

### Fixed
- Aligned scan and runbook PowerShell requirements with Microsoft Learn guidance that `Microsoft.PowerApps.Administration.PowerShell` uses Windows PowerShell 5.x rather than PowerShell 7.x.
- Added connected-agent schema-name extraction for current Copilot Studio `InvokeConnectedAgentTaskAction` and `ConnectedAgentDefinition` YAML patterns.
- Updated flow prerequisites to include `Az.Accounts` and to document Windows PowerShell 5.1 runbook deployment for the Power Platform admin module.

## [1.1.0] - 2026-04-17

### Breaking

- Runbook output schema augmented with `SkillSnapshot` (array) and top-level `ViolationCount`. Power Automate "Parse JSON" action must be regenerated from a fresh sample (drop phantom `CommunicationPattern`, `ExpectedPolicy`, `ActualConfig`; add `RunType`, `RunId`, `TotalSkills`, `EnvironmentNames`, `Reason`, `Control`, `ZoneSummary`, `Drift`, `AlertRequired`, `AlertSeverity`, `SkillSnapshot`, `ViolationCount`; per-violation `IsCrossEnvironment`, `IsCrossTenant`, `RegulatoryContext`).
- Flow Step 7 column mapping for `fsi_environmentsscanned` changed from `string(TotalEnvironments)` (count) to `EnvironmentNames` (comma-separated environment list, the actual schema intent).
- Flow Step 6 (exception approval) `fsi_exceptionstatus` mapping changed from text label `"Approved"`/`"Denied"` to integer option set values `100000001`/`100000002`. Existing flows using the text labels will silently fail to update the column.
- `Import-ApprovedCommRoutes.ps1`: `ApprovedBy` is now mandatory per row (rows with empty `ApprovedBy` are skipped with warning); `fsi_approvedby` and `fsi_approvedat` are now always set on every CREATE and UPDATE.
- `ACRDClient.psm1` now declares `#requires -Modules @{ ModuleName='Az.Accounts'; ModuleVersion='2.0.0' }`. Importing the module without `Az.Accounts` installed will fail at parse time.

### Fixed

- **CRITICAL — drift detection restored.** `Start-CommRestrictionValidationRunbook.ps1` and `Test-CommRestrictionCompliance.ps1` now persist the `SkillSnapshot` array (id, name, environmentId, manifestUrl) into the runbook output and `scanSummary`. Without this snapshot, the next run's `Compare-Snapshot` had nothing to diff against and drift detection was a no-op.
- **Goldeneye HIGH** — `Start-CommRestrictionValidationRunbook.ps1` now calls `Add-PowerAppsAccount` with the same certificate/tenant/clientId after acquiring the Dataverse token. Without this, `Get-AdminPowerAppEnvironment` (used to enumerate environments) silently fails or prompts in non-interactive runbook context.
- `ACRDClient.psm1` `Get-AgentBots` `$select` clause: replaced invalid `schemaname` with `_ownerid_value` (the bot table has no `schemaname` column; query was returning 400).
- `ACRDClient.psm1` `Get-ACRDSkillRegistration`: `TargetZone` no longer masquerades `SourceZone`'s value — it is now `$null` since `fsi_AgentSkillRegistration` has only one zone column (`fsi_zone`). Comparison logic must treat `TargetZone` as unknown for skill-registration records.
- `ACRDClient.psm1` `Write-ACRDViolation`: violation `fsi_name` truncated to 200 chars (80+80 cap on calling/called agent names) to fit the schema column; `fsi_calledenvironmentid` always set with `'unknown-tenant'` fallback + warning when missing (column is required); `fsi_violationtype` now throws if unmappable rather than silently dropping the column (column is required).
- `Connect-EnvironmentDataverse.ps1`: SecureString token is now properly unwrapped (PS7 `ConvertFrom-SecureString -AsPlainText`, PS5.1 `Marshal.SecureStringToBSTR` fallback) before being placed in the `Authorization` header. Previous code passed the SecureString directly, producing 401 errors.
- `Import-ApprovedCommRoutes.ps1`: Dataverse URL regex broadened to accept sovereign clouds (`.crm.microsoftdynamics.us`, `.crm.microsoftdynamics.de`) and trailing slashes.
- `Export-CommViolationEvidence.ps1`: deterministic JSON canonicalization (recursive key sort, stable record ordering) and LF-only UTF-8 no-BOM file write so re-runs of the same data produce byte-identical hashes (sha256sum-compatible companion file).
- `ACRDClient.psm1` POSTs now use `ConvertTo-Json -Depth 10` to prevent nested object truncation.
- README "Violation Severity Matrix" Maker/Checker row corrected from `Warning | Medium | High` to `Warning | High | Critical` to match `Get-ExpectedCommPolicy.ps1`.
- CHANGELOG: corrected inverted dates (1.0.2 was dated after 1.0.1).
- All embedded `Version:` headers and banner strings synced to `1.1.0` across 11 .ps1 + 1 .psm1.

### Changed

- `prerequisites.md`: clarified that runbook needs `MSAL.PS` (cert auth), `Microsoft.PowerApps.Administration.PowerShell` (env enumeration), and `Az.Accounts` (transitively required by `ACRDClient.psm1`).

## [1.0.2] - 2026-03-08

### Fixed

- ACRDClient.psm1 `Get-ACRDSkillRegistration`: removed non-existent `fsi_isactive` filter and `fsi_ownerid` output mapping; changed `fsi_sourcezone`/`fsi_targetzone` to `fsi_zone` (actual AgentSkillRegistration column)
- Start-CommRestrictionValidationRunbook.ps1: fixed property name mismatch — Compare-CommRestrictionCompliance outputs `AgentId`/`AgentName`, not `CallingAgentId`/`CallingAgentName`
- flow-configuration.md exception approval flow: replaced phantom columns (`fsi_sourceagentid`, `fsi_targetagentid`, `fsi_sourceagentname`, `fsi_targetagentname`, `fsi_communicationpattern`, `fsi_requestedby`, `fsi_requestedon`) with correct schema columns (`fsi_callingagentid`, `fsi_calledagentid`, `fsi_justification`)
- flow-configuration.md scanner flow: added missing `fsi_totalskills` to scan run Dataverse write mapping
- Entity set name in comments: `fsi_commscanruns` → `fsi_commscanrun` in Test-CommRestrictionCompliance.ps1 and Start-CommRestrictionValidationRunbook.ps1

### Changed

- Bumped embedded version strings from 1.0.0 to 1.0.1 across all scripts
- Added `#Requires -Version 7.0` and comment-based help to `scripts/private/Get-ZoneClassification.ps1`

## [1.0.1] - 2026-03-01

### Fixed

- Entity set `fsi_commscanruns` → `fsi_commscanrun` in ACRDClient.psm1 and Export script (matches schema EntitySetName)
- Exception column `fsi_targetagentid` → `fsi_calledagentid` in ACRDClient.psm1 (matches schema)
- README status updated from "In Development" to "Released"

## [1.0.0] - 2026-02-24

### Added

- Initial release of Agent Communication Restriction Detector
- Dataverse schema: 5 tables, 4 ACRD-specific option sets, 2 shared option sets
- Python deployment scripts for Dataverse infrastructure (schema, environment variables, connection references)
- PowerShell governance scripts for agent communication compliance scanning
- Zone-to-zone communication policy enforcement (Zone 1/2/3)
- Cross-environment and cross-tenant violation detection
- Maker/checker enforcement for agent skill registrations
- Approved communication route management via CSV import
- SHA-256 integrity-hashed evidence export for regulatory examinations
- Azure Automation runbook for scheduled validation
- Teams and email alerting via Power Automate flows
- Regulatory context mapping (FINRA 3110, SOX 404, GLBA 501(b))
