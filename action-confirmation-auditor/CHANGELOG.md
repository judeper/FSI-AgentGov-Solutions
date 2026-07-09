# Changelog

All notable changes to the Action Confirmation Auditor are documented in this file.

## [Unreleased]

### Changed

- **Script auth:** Migrated `scripts/Start-ActionConfirmationValidationRunbook.ps1` from the archived [`MSAL.PS`](https://github.com/AzureAD/MSAL.PS) module (last updated September 2023) to `Az.Accounts` certificate-based service-principal sign-in (`Connect-AzAccount -ServicePrincipal -CertificateThumbprint` + `Get-AzAccessToken -ResourceUrl`), matching the established `Start-HitlValidationRunbook.ps1` pattern and removing the `MSAL.PS` dependency. The handler converts the SecureString token returned by Az.Accounts 5.x back to a header string via `[System.Net.NetworkCredential]`.
- **Script auth:** Migrated `scripts/Export-ActionAuditEvidence.ps1` from the archived [`MSAL.PS`](https://github.com/AzureAD/MSAL.PS) module to `Az.Accounts` (`Get-AzContext` + `Get-AzAccessToken -ResourceUrl` for the interactive path; `Connect-AzAccount -ServicePrincipal -CertificateThumbprint` + `Get-AzAccessToken -ResourceUrl` for the certificate path), matching the `Connect-EnvironmentDataverse.ps1` helper pattern. The `ConvertTo-ACAPlainTextToken` helper unwraps the SecureString token returned by Az.Accounts 5.x.

### Validated

- **Live tenant validation — detection path on a synthetic YAML fixture (2026-06-13, the lab validation tenant); coverage stays PARTIAL.** The three `fsi_action*` Dataverse tables and the shared/ACA option sets were deployed, and the committed detection path was proven end-to-end against disposable-bot fixtures using a **synthetic hand-written YAML** topic: the `_parentbotid_value` foreign-key query succeeded (no more HTTP 400), a Zone 1 connector action with no confirmation node resolved to `Missing` / **Critical** with one row persisted, a compliant variant (a `Question` confirmation node) produced no row, the same-fixture flip flipped the result, unparseable content fell closed to `UnableToDetermine` (never a false Compliant), the SHA-256 evidence digest (prefix `DADDBA91`) recomputed to an integrity match, and all disposable fixtures were torn down (the three ACA tables verified back to zero — the deployed schema is the retained deliverable). **No committed-source fix was needed** for this leg (contrast GAC's Rule 7); `git diff` over `scripts` is empty. **PARTIAL is preserved on both 2.12 and 1.10:** the topic content was synthetic, NOT an authentic in-product Copilot Studio-authored topic (the two real agents exposed 0 of 18 topic components), so authentic in-product topic detection remains unproven and out of lab scope. This is lab evidence from disposable fixtures, not a production guarantee. Full record: `LAB-VALIDATION.md` → "Live tenant validation outcome — 2026-06-13".

### Fixed

- **`scripts/Start-ActionConfirmationRunbook-MI.ps1`**: Corrected an inaccurate version reference in the `ConvertFrom-AzAccessTokenValue` helper comment. It stated `Get-AzAccessToken` returns a `SecureString` "(Az.Accounts >= 2.17)"; Microsoft Learn documents that the default output type changed from plain-text `String` to `SecureString` starting with **Az.Accounts 5.0.0** (Az 14.0.0), not 2.17. No behavior change — the helper already type-checks and handles both shapes (and matches the already-correct note in `Get-PurviewAIHubEvidence.ps1`). (technical-accuracy review; verified against `https://learn.microsoft.com/powershell/azure/context-persistence` / Protect secrets in Azure PowerShell — "the default output type of the `Get-AzAccessToken` cmdlet changed ... starting with Az.Accounts version 5.0.0 and Az version 14.0.0")

- **`scripts/Get-PurviewAIHubEvidence.ps1`**: Removed the invalid `copilotInteraction` value from the Graph audit log query `recordTypeFilters`. `copilotInteraction` is not a member of the v1.0 `auditLogRecordType` enum (it is the beta `copilotInteractionAuditRecord` record subtype, not a filter value); sending an unknown evolvable-enum member returns HTTP 400 and fails the entire query. The filter now uses only the valid camelCase members `aipDiscover` and `aipSensitivityLabelAction`, and Copilot interaction activity is collected via the existing Activity Explorer fallback. (second-pass command-existence audit; verified against `https://learn.microsoft.com/graph/api/resources/security-auditlogrecordtype?view=graph-rest-1.0`)

- **`botcomponent` foreign-key lookup**: Re-pathed the detector's `botcomponent` query from the non-existent `_botid_value` to the real FK `_parentbotid_value` (filter form `$filter=_parentbotid_value eq <guid>`) in all three call sites (`Get-AgentActionSettings.ps1`, `private/ACAClient.psm1`, `governance/Test-UserDefinedActionMessages.ps1`). The prior value returned HTTP 400 on the live lab validation tenant and hard-failed the scan before scoring. This reverses the incorrect standardization recorded in the v1.2.0 entry below. (OPTION A reconciliation; Phase 0 probe 2026-06-13)

- **YAML-aware topic parsing (fail-closed)**: `Get-AgentActionSettings.ps1` (and the exported `ACAClient.psm1` parser) previously `ConvertFrom-Json`'d `botcomponent.content` and silently `continue`'d on parse failure — a false-Compliant trap, since Copilot Studio topics are authored as **YAML**. The parser now detects JSON vs YAML, parses YAML best-effort (`ConvertFrom-Yaml` when the module is present, plus portable structural regex that works without it), and emits an `UnableToDetermine` (Indeterminate) marker for unparseable/empty content instead of dropping it. Indeterminate surfaces as a violation in strict zones and a Warning in advisory zones — never silently Compliant. Full YAML *semantic* detection remains **PARTIAL** pending a genuine in-product fixture.

### Changed

- **Zone/severity reconciliation to OPTION A canonical**: Flipped the zone semantics so the strictest confirmation requirement attaches to **Zone 1 (Enterprise)** (was Zone 3) and the advisory policy to Zone 3 (Personal), across `private/Get-ExpectedConfirmationPolicy.ps1`, `governance/Test-UserDefinedActionMessages.ps1`, `Start-ActionConfirmationValidationRunbook.ps1`, `Export-ActionAuditEvidence.ps1`, `governance/Import-ActionRiskClassifications.ps1`, and the shared `scripts/shared/Get-ZoneClassification.ps1` naming map (`-prod-/-production-/-enterprise-`→Zone1; `-personal-/-dev-/-sandbox-`→Zone3). Reconciled the PowerShell zone→integer maps and `create_dataverse_schema.py` declarations to the live canonical set (Unclassified=100000000, Zone1=100000001, Zone2=100000002, Zone3=100000003). Retext zone-policy strings in `README.md`, `docs/*`, and `lab/README.md`. Confirmed ACA's `fsi_Severity` is a free String (no column-binding change needed). Added `lab/Assert-CanonicalZonePolicy.ps1` proving "strictest ⇔ Zone 1 ⇔ 100000001" (passes).

## [1.2.1] - 2026-05-23

### Fixed

- **Critical**: `scripts/governance/Test-UserDefinedActionMessages.ps1` zone string-to-integer switch labels were `'Zone 1'/'Zone 2'/'Zone 3'` (with spaces) but `Get-ZoneClassification.ps1` returns `'Zone1'/'Zone2'/'Zone3'` (no spaces); every UDAM violation persisted to Dataverse was being written with `fsi_zone = 0` (Unknown). (council review C-1)
- **Major**: `scripts/Start-ActionConfirmationRunbook-MI.ps1` was splatting `-Zone` and `-IncludeSandbox` parameters that do not exist on `Test-ActionConfirmationCompliance`. Removed the unknown `-Zone` splatting (added a post-scan filter on the `Zone` property in the result envelope instead) and inverted `-IncludeSandbox` into the correct `-ExcludeSandbox` switch. (council review M-1)
- **Major**: `scripts/Start-ActionConfirmationRunbook-MI.ps1` required `#Requires -Version 7.1` while depending on `Microsoft.PowerApps.Administration.PowerShell` (a Windows PowerShell 5.1 module). Downgraded the requirement to `#Requires -Version 5.1`, pinned `Az.Accounts` to `>= 2.17.0`, replaced `Get-Date -AsUTC -Format 'o'` with `(Get-Date).ToUniversalTime().ToString('o')`, and added a `ConvertFrom-AzAccessTokenValue` helper to unwrap the `SecureString` token that Az.Accounts 2.17+ returns. (council review M-2, m-2)
- **Major**: `docs/prerequisites.md` footer was `v1.1.1` while `manifest.yaml`, README, and CHANGELOG all said `v1.2.0`. Bumped to `v1.2.1`. (council review M-4)
- **Major**: Root `CLAUDE.md` Solutions table row for `action-confirmation-auditor` was pinned at `v1.1.0` (two releases behind). Bumped to `v1.2.1`. (council review M-5)
- **Major**: `scripts/create_connection_references.py` Office 365 connection description still used the legacy Control 1.23 phrase "step-up confirmation"; replaced with "HITL confirmation" to match the Control 2.12 mapping established in v1.1.0. (council review M-6)

### Changed

- **Minor**: Synchronised `Version:` headers in all production `.ps1` / `.psm1` files (`ACAClient.psm1`, `Export-ActionAuditEvidence.ps1`, `Get-AgentActionSettings.ps1`, `Get-ExpectedConfirmationPolicy.ps1`, `Get-PurviewAIHubEvidence.ps1`, `Start-ActionConfirmationRunbook-MI.ps1`, `Start-ActionConfirmationValidationRunbook.ps1`, `Test-ActionConfirmationCompliance.ps1`, `Test-EvidenceIntegrity.ps1`, `Test-ParameterValidation.ps1`, `Test-UserDefinedActionMessages.ps1`) from `1.1.0` / `1.2.0` to `1.2.1`; updated `solutionVersion` metadata in evidence package and the verbose banner in `Test-ActionConfirmationCompliance.ps1`. Per style-decisions §4 (version strings must be bumped with the release).

### Notes (false positives investigated, no change made)

- **m-3 (FALSE POSITIVE)**: Council report claimed `create_connection_references.py:97` calls `client.query(...)` with `filter=` while `ACAClient.query()` uses `filter_expr=`. Verified at `scripts/aca_client.py:166-173`: the local `ACAClient.query()` signature is `query(self, entity_set, select=None, filter=None, orderby=None, top=None)`. The call site `filter=...` matches the parameter name. The council report appears to have conflated the local `ACAClient` API with the shared `DataverseClient` API.

### Deferred (out of scope for patch bump)

- **M-3** (shared `DataverseClient` migration): Reconciling `scripts/aca_client.py` with `scripts/shared/dataverse_client.py` requires per-method API alignment (the shared client uses `query_records(filter_expr=...)`, not `query(filter=...)`), regression testing of `create_dataverse_schema.py` / `create_connection_references.py` / `create_environment_variables.py` / `deploy.py`, and adoption of managed-identity / certificate auth paths the local client does not currently expose. Out of scope for a patch bump; tracked for a future minor.
- **m-1** (`Import-ActionRiskClassifications.ps1` stub): The script is intentionally retained as a placeholder for the v1.1 risk-classification feature documented in CHANGELOG v1.0.0. Removing or gating it behind an experimental flag is a standalone change not co-located with any fix in this PR. Deferred.
- **m-4** (`.ralph-config.json` mention in `CLAUDE.md`): Standalone documentation gap. Deferred.

## [1.2.0] - 2026-05-12

### Added

- **Azure Automation managed identity runbook** (`Start-ActionConfirmationRunbook-MI.ps1`): Sample runbook demonstrating the migration from deprecated RunAs accounts to managed identity (system-assigned or user-assigned). Authenticates via `Connect-AzAccount -Identity`, acquires tokens for Graph and Dataverse, and runs the action confirmation compliance scan. Includes inline migration guide. Reference: [Azure Automation MI](https://learn.microsoft.com/azure/automation/learn/powershell-runbook-managed-identity).
- **Purview AI Hub / DSPM for AI integration** (`Get-PurviewAIHubEvidence.ps1`): Queries Purview AI Hub for confirmed actions on AI-classified data, cross-references with ACA action-confirmation events from Dataverse, and generates dual-confirmation evidence (action-level + DSPM-level). Evidence includes SHA-256 integrity hashing for regulatory submissions. Reference: [Purview AI Hub](https://learn.microsoft.com/purview/ai-microsoft-purview).

## [Unreleased] - 2026-Q2 — Microsoft Learn refresh

### Fixed

- **scripts/Get-PurviewAIHubEvidence.ps1**: Authentication was non-functional. The script built `Authorization: Bearer` headers from `(Get-MgContext).AccessToken`, but `Get-MgContext` does not expose an access token property (it returns ClientId, TenantId, Scopes, AuthType, etc. — never the raw token), so both the Graph audit-log query and the Dataverse query sent an empty bearer token. Graph calls now use `Invoke-MgGraphRequest`, which reuses the established `Connect-MgGraph` session token with the correct audience. ([Authentication module cmdlets in Microsoft Graph PowerShell](https://learn.microsoft.com/powershell/microsoftgraph/authentication-commands), [Invoke-MgGraphRequest](https://learn.microsoft.com/powershell/module/microsoft.graph.authentication/invoke-mggraphrequest))
- **scripts/Get-PurviewAIHubEvidence.ps1**: The Dataverse query reused the Graph token, which is scoped to the wrong audience and is rejected by Dataverse. Added a `-DataverseAccessToken` (SecureString) parameter and an `Az.Accounts` fallback (`Get-AzAccessToken -ResourceUrl <DataverseUrl>`) so a Dataverse-audience token is used; managed-identity-first in Azure Automation.
- **scripts/Get-PurviewAIHubEvidence.ps1**: `$select`/property mapping referenced a non-existent `fsi_hasconfirmation` column. The schema confirmation column is `fsi_confirmationstatus` (option set `fsi_ACA_confirmationstatus`, Present = 100000000). `HasConfirmation` is now derived from `fsi_confirmationstatus -eq 100000000`. Source of truth: `scripts/create_dataverse_schema.py`.
- **scripts/Get-PurviewAIHubEvidence.ps1**: `recordTypeFilters` enum values normalized to the documented camelCase members (`copilotInteraction`, `aipDiscover`, `aipSensitivityLabelAction`) per the Microsoft Graph `auditLogRecordType` enum.
- **scripts/Start-ActionConfirmationRunbook-MI.ps1**: The managed-identity runbook acquired a Microsoft Graph token and passed it to `Add-PowerAppsAccount`, but the Power Platform admin module expects a token scoped to the Power Apps service audience (`https://service.powerapps.com/`), so `Get-AdminPowerAppEnvironment` enumeration would fail. The runbook now acquires the Power Apps-audience token via `Get-AzAccessToken -ResourceUrl 'https://service.powerapps.com/'`. ([Get-JwtToken](https://learn.microsoft.com/powershell/module/microsoft.powerapps.administration.powershell/get-jwttoken) documents the `https://service.powerapps.com/` audience.)
- **docs/prerequisites.md**: Documented the optional Purview AI Hub integration dependencies (the `AuditLogsQuery.Read.All` Graph scope and the separate Dataverse token).

- Aligned Power Platform admin PowerShell scripts and runbook guidance with Microsoft Learn's Windows PowerShell 5.x compatibility requirement for `Microsoft.PowerApps.Administration.PowerShell`.
- Replaced stale Control 1.23 output metadata with Control 2.12 / 1.10 mappings for HITL confirmation evidence.
- Regenerated Dataverse schema documentation so `fsi_IsActive` shows the schema default `false` and confirmation wording matches the current HITL control mapping.
- Updated setup examples to prefer interactive authentication for workstation deployment and label client-secret flows as legacy dev-only.

## [1.1.0] - 2026-04-17 - BREAKING

### Changed (BREAKING)

- **Control mapping re-aligned.** Primary control changed from **1.23 (Step-Up Authentication for Agent Operations)** to **2.12 (Human-in-the-Loop Checkpoints)**, with **1.10 (Communication Compliance)** as supporting (FINRA 3110 supervisory review evidence). Control 1.23 is implemented through Entra Authentication Contexts and Conditional Access (see *Conditional Access Automation* and *Session Security Configurator* solutions); ACA validates HITL/approval prompts in agent topics and does not by itself satisfy AAL2/AAL3 step-up authentication. AI Council convergent finding (Opus 4.7 + Goldeneye).
- **Schema: `fsi_IsActive` default flipped to `false`** on `fsi_ActionConfirmationException`. Previously defaulted to `true`, creating a control-bypass window where any newly created exception immediately suppressed violations until the approver acted (up to 14 days). Now exceptions are inactive by default and only the approval branch in the exception-approval flow sets `fsi_IsActive = true`. Existing tenants must republish the schema (`python scripts/create_dataverse_schema.py`) and update the exception-approval flow trigger filter (remove `fsi_isactive eq true`).
- **Runbook output schema additions.** `Start-ActionConfirmationValidationRunbook.ps1` now emits `ActionsMissingConfirmation` and `ActionsWithConfirmation` at the top level of the JSON output (previously only present inside `ZoneSummary[*]`). The Power Automate Parse JSON schema in `docs/flow-configuration.md` already referenced these top-level fields, so prior to this fix the corresponding Dataverse `fsi_actionsmissingconfirmation` / `fsi_actionswithconfirmation` `ApplicationRequired` columns were always written as null (record creation failed).

### Fixed

- **scripts/Start-ActionConfirmationValidationRunbook.ps1**: Replaced remaining `OverallStatus = 'Review'` emission (lines 248, 431, .OUTPUTS doc) with `'Warning'`. CHANGELOG v1.0.3 fixed this in `Test-ActionConfirmationCompliance.ps1` but missed the runbook, which is the primary production path. Removed dead `'Review'` branches from `Export-ActionAuditEvidence.ps1` and `Test-ActionConfirmationCompliance.ps1` switch tables.
- **scripts/private/ACAClient.psm1 `Write-ACAViolation`**: Now persists `fsi_violationtype` from the supplied `Violation.ViolationType`. Previously omitted, breaking cross-solution-integration / dashboard filtering by violation type. (Same gap was fixed in `Test-UserDefinedActionMessages.ps1` per v1.0.3 but the central PSM1 path was missed.)
- **scripts/private/ACAClient.psm1 `Write-ACAValidationHistory`**: `fsi_name` timestamp now correctly converted to UTC before formatting (was emitting local time labelled `Z`, causing drift vs `fsi_validationtime`).
- **scripts/Export-ActionAuditEvidence.ps1**: Evidence JSON is now **deterministic** — recursive key sort + LF-only + UTF-8 no-BOM write — so two exports of identical Dataverse data produce identical SHA-256 hashes. Required for FINRA 4511 / SEC 17a-4 chain-of-custody verification through `Test-EvidenceIntegrity.ps1`.
- **scripts/Export-ActionAuditEvidence.ps1**: Hash companion file now written via `[System.IO.File]::WriteAllText` with explicit `\n` line ending and UTF-8 no BOM, matching GNU `sha256sum` format exactly.
- **scripts/Export-ActionAuditEvidence.ps1**: All three Dataverse queries (`fsi_actionscanrun`, `fsi_actionauditresults`, `fsi_actionconfirmationexceptions`) now follow `@odata.nextLink` via a shared `Invoke-DataversePagedQuery` helper. Previously single-page only — large tenants received truncated evidence packages with hashes computed over partial data.
- **scripts/Export-ActionAuditEvidence.ps1**: Added GUID format validation for `-RunId` parameter before insertion into OData filter (mirrors validation already present in `ACAClient.psm1`).
- **scripts/Export-ActionAuditEvidence.ps1**: Replaced "Azure AD" with "Microsoft Entra ID" in `.PARAMETER TenantId` and `.PARAMETER ClientId` help text (per repo language policy).
- **All script `.NOTES`**: Bumped `Version` from `1.0.2` → `1.1.0` and `Control` references from `1.23` → `2.12 (HITL); supports 1.10 (Communication Compliance / FINRA 3110)` across `Get-AgentActionSettings.ps1`, `ACAClient.psm1`, `Start-ActionConfirmationValidationRunbook.ps1`, `Test-UserDefinedActionMessages.ps1`, `Test-ActionConfirmationCompliance.ps1`, `Get-ExpectedConfirmationPolicy.ps1`, `Test-EvidenceIntegrity.ps1`, `Test-ParameterValidation.ps1`, `Export-ActionAuditEvidence.ps1`. Verbose banner in `Test-ActionConfirmationCompliance.ps1` and `solutionVersion` in evidence package metadata also bumped.
- **README.md**: Updated Related Controls table to reflect 2.12 / 1.10 mapping, added explanatory note about why 1.23 was removed.

### Council Review

This release applies fixes from a 2-member AI Council technical review (Opus 4.7 + Goldeneye). Both council members independently identified the control mis-mapping, the runbook `'Review'` regression, the version-string drift, and "Azure AD" naming issues. Opus additionally surfaced the non-deterministic evidence JSON, the `Write-ACAViolation` `fsi_violationtype` omission, the `IsActive` default-true control-bypass vector, and the missing `ActionsMissingConfirmation` / `ActionsWithConfirmation` runbook output fields. Goldeneye additionally surfaced the missing OData pagination in `Export-ActionAuditEvidence.ps1`.

## [1.0.3] - 2026-04-16

### Fixed

- **scripts/private/ACAClient.psm1**: Added missing required fields `fsi_totalagents` and `fsi_violationcount` to `Write-ACAValidationHistory` scan run record
- **scripts/private/ACAClient.psm1**: Added missing `fsi_risklevel` field to `Write-ACAViolation` violation record
- **scripts/Test-ActionConfirmationCompliance.ps1**: Fixed `$validationSummary` to pass `ActionsWithConfirmation`, `ActionsMissingConfirmation`, and `ViolationCount` keys matching `Write-ACAValidationHistory` expectations
- **scripts/Test-ActionConfirmationCompliance.ps1**: Changed `OverallStatus` from non-schema value `Review` to `Warning` to match schema documentation
- **scripts/Test-ActionConfirmationCompliance.ps1**: Exception matching now validates `IsActive`, `ExpiresAt`, and `Zone` fields instead of matching on AgentId|ActionName alone
- **scripts/Get-AgentActionSettings.ps1**: Fixed confirmation status string `Unable to Determine` → `UnableToDetermine` to match schema option set
- **scripts/Get-AgentActionSettings.ps1**: Fixed `ActionsMissingConfirmation` count to include Partial and UnableToDetermine statuses (was only counting Missing)
- **scripts/Export-ActionAuditEvidence.ps1**: Fixed zone filter to use integer picklist value instead of string `'Zone1'` for OData query
- **scripts/governance/Test-UserDefinedActionMessages.ps1**: Added missing required Dataverse fields (`fsi_zone`, `fsi_actionname`, `fsi_actiontype`, `fsi_risklevel`, `fsi_confirmationstatus`, `fsi_violationstatus`) when persisting violations
- **docs/flow-configuration.md**: Added missing violation properties (`EnvironmentId`, `EnvironmentName`, `Zone`, `AgentId`, `AgentName`, `ActionCategory`) to Parse JSON schema
- **scripts/private/Get-ZoneClassification.ps1**: Added missing `#requires -Version 7.0` statement
- **scripts/governance/Import-ActionRiskClassifications.ps1**: Added missing `.EXAMPLE` section to comment-based help
- Updated all script `.NOTES` version references from `1.0.0` to `1.0.2`
- **scripts/Export-ActionAuditEvidence.ps1**: Updated evidence metadata `solutionVersion` from `1.0.0` to `1.0.2`

## [1.0.2] - 2026-04-15

### Fixed

- **README.md**: Corrected Quick Start CLI flag `--dataverse-url` → `--environment-url` to match actual `create_dataverse_schema.py` argument
- **README.md**: Fixed dry-run example to dot-source script before calling `Test-ActionConfirmationCompliance` function
- **README.md**: Added mandatory auth parameters (`-TenantId`, `-Interactive`) to evidence export example
- **README.md**: Formalized regulation references (FINRA Rule 3110, GLBA Section 501(b), SOX Section 404)
- **docs/prerequisites.md**: Corrected deployment command `--dataverse-url` → `--environment-url`
- **docs/prerequisites.md**: Fixed Dataverse table names from SchemaName format to logical names
- **docs/prerequisites.md**: Updated footer version v1.0.0 → v1.0.2
- **docs/dataverse-schema.md**: Regenerated from schema script to include missing `fsi_ViolationType` column
- **docs/flow-configuration.md**: Added missing required fields to Action Scan Run record creation (`fsi_actionswithconfirmation`)
- **docs/flow-configuration.md**: Added all required fields and option set value mappings to Action Audit Result creation (`fsi_environmentguid`, `fsi_environmentname`, `fsi_zone`, `fsi_agentid`, `fsi_agentname`, `fsi_risklevel`, `fsi_violationstatus`)
- **docs/flow-configuration.md**: Removed undocumented `fsi_cr_approvals_actionconfirmationauditor` connection reference not created by deployment scripts
- **docs/flow-configuration.md**: Aligned troubleshooting guidance with certificate-based service principal authentication
- **scripts/private/ACAClient.psm1**: Fixed `Connect-ACADataverse` to reset `$script:DataverseUrl` on token acquisition failure instead of leaving partial connected state
- **scripts/private/ACAClient.psm1**: Fixed help example to reference `Get-ACALastValidation` (was non-existent `Get-ACAScanRunHistory`)
- **scripts/Export-ActionAuditEvidence.ps1**: Added `#Requires -Modules MSAL.PS` declaration
- **scripts/Test-ActionConfirmationCompliance.ps1**: Fixed help text entity set name `fsi_actionscanruns` → `fsi_actionscanrun`

## [1.0.1] - 2026-04-15

### Fixed

- Aligned all PowerShell scripts with Dataverse schema source of truth:
  - Entity set `fsi_actionscanruns` → `fsi_actionscanrun` (ACAClient.psm1, Export-ActionAuditEvidence.ps1, Start-ActionConfirmationValidationRunbook.ps1)
  - Column `fsi_scantime` → `fsi_validationtime` across all scan run queries
  - Column `fsi_reason` → `fsi_justification` for exception records
  - Removed references to non-existent `fsi_connectorid` column (use `fsi_connectorname`)
  - Removed references to non-existent `fsi_agentname` on exception table
  - Fixed `fsi_compliantcount` → `fsi_actionswithconfirmation` in evidence export
  - Removed non-existent `fsi_actioncategory` from evidence export
- Fixed `Get-ACAExceptions` → `Get-ActionConfirmationExceptions` function call in Test-ActionConfirmationCompliance.ps1
- Fixed exception property access to use PSCustomObject property names (`AgentId`, `ActionName`) instead of raw Dataverse column names
- Standardized bot component lookup field to `_botid_value` (was inconsistently `_parentbotid_value` in ACAClient.psm1)
- Updated README: corrected Quick Start dry-run command, environment variables table, removed false CSV export claim
- Updated flow-configuration.md: corrected environment variables, runbook parameters, Dataverse column names, removed non-existent exception columns
- Updated prerequisites.md: corrected authentication guidance to certificate-based auth
- Added missing `.EXAMPLE` sections to PowerShell comment-based help (ACAClient.psm1, Connect-EnvironmentDataverse.ps1, Get-ExpectedConfirmationPolicy.ps1, Get-ZoneClassification.ps1)

## [1.0.0] - 2026-02-24

### Added

- Initial release of Action Confirmation Auditor
- Dataverse schema: 3 tables, 3 solution-specific option sets, 2 shared option sets
- Python deployment scripts: schema, environment variables, connection references, orchestrator
- PowerShell governance scripts: compliance scan, evidence export
- Zone-based policy enforcement for action confirmation requirements
- Hardcoded zone policies (v1.0): Zone 3 all actions, Zone 2 write/delete/external, Zone 1 advisory
- Exception management for approved confirmation bypasses
- SHA-256 evidence export for regulatory examination
- Azure Automation runbook wrapper for scheduled execution
- Teams/email alerting via Power Automate flow documentation
- Regulatory context mapping (FINRA 3110, GLBA 501(b), SOX 404)
- v1.1 stub for risk classification CSV import
