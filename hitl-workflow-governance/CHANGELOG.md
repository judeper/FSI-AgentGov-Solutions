# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/).

## [Unreleased]

### Fixed

- **botcomponent componenttype filter:** Corrected the Copilot Studio `botcomponents` `componenttype` filter in `Get-AgentHitlSettings.ps1` and `governance/Test-HitlCheckpointConfiguration.ps1`. The scripts filtered `componenttype eq 12 or componenttype eq 2` with a comment claiming "12 = Topic, 2 = Dialog/Skill". Per the authoritative [Microsoft Dataverse botcomponent reference](https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/botcomponent), those values are **Bot variable (V2) = 12** and **Bot variable = 2** — neither holds the topic/dialog action content the scan parses, so HITL checkpoints could be silently missed. The filter now targets `componenttype eq 0` (Topic), `9` (Topic V2), `4` (Dialog), and `1` (Skill).

### Changed

- **Runbook auth:** Migrated `Start-HitlValidationRunbook.ps1` from the archived [`MSAL.PS`](https://github.com/AzureAD/MSAL.PS) module (last updated September 2023) to `Az.Accounts` certificate-based service-principal sign-in (`Connect-AzAccount -ServicePrincipal -CertificateThumbprint` + `Get-AzAccessToken -ResourceUrl`), matching the rest of the solution and removing the last `MSAL.PS` dependency. The handler converts the SecureString token returned by Az.Accounts 5.x back to a header string. Updated `docs/prerequisites.md` and `docs/troubleshooting.md` module references accordingly.
- **Request for Information GA:** Updated `README.md`, `docs/prerequisites.md`, and `docs/troubleshooting.md` to reflect that the Request for Information action reached general availability on Jan 30, 2026 (Power Platform release plan), while noting the Human in the Loop connector reference page still labels the action preview and Run a Multistage Approval remains preview.

### Notes

- Added `LAB-VALIDATION.md` documenting authoritative-source verification (Microsoft Learn), gaps and fixes, and runtime-only caveats — including the documented-versus-deployed `botcomponents` lookup attribute discrepancy (`_botid_value` retained per council-review fix M-5; Microsoft documents only `parentbotid`/`_parentbotid_value`).

## [1.1.2] - 2026-05-23

### Fixed

- **C-1:** Removed phantom `fsi_agentname` reference from the exception evidence JSON in `Export-HitlGovernanceEvidence.ps1`. The `fsi_HitlCheckpointException` table does not define an `fsi_AgentName` column; exporting it produced `$null` in every record and could mislead reviewers comparing evidence across exports.
- **C-2:** Removed the "Update Violation Record" step from `docs/flow-configuration.md` that instructed administrators to set `fsi_alertsentat` on `fsi_HitlCheckpointResult`. No such column exists; flows following the instruction would fail at runtime. Replaced with documentation noting that alert-dispatch metadata is intentionally out-of-schema and lives in the maker's own audit sink.
- **M-1:** Aligned Zone 2 `minimumInputs` in `templates/hitl-zone-policy.json` (was `1`, now `0`) so the JSON template matches the PowerShell policy evaluation in `Get-AgentHitlSettings.ps1` / `Test-HitlCheckpointConfiguration.ps1`. The previous mismatch caused a Zone 2 agent with a single input to be flagged in PowerShell but pass when JSON-driven tooling consumed the template directly.
- **M-3:** Removed the orphaned `$script:ActionCategoryToInt` / `$script:IntToActionCategory` integer-mapping hashtables from `private/HWGClient.psm1`. `Get-ActionCategory` returns string labels and the integer maps were never read by any caller. The schema defines no `fsi_ActionCategory` picklist, so the hashtables had no production purpose and risked future contributors persisting non-existent columns.
- **M-4:** Rewrote the Teams notification and approver troubleshooting sections in `docs/troubleshooting.md` to clarify that Teams group/channel IDs and the compliance approver address are **flow-level configuration** (Azure Automation variable assets, secure flow configuration, or flow parameters), not Dataverse environment variables. `create_hwg_environment_variables.py` never deployed `fsi_HWG_TeamsGroupId`, `fsi_HWG_TeamsChannelId`, or `fsi_HWG_ComplianceApproverEmail`.
- **M-5:** Aligned the Copilot Studio `botcomponents` lookup attribute in `Get-BotHitlSettings` (`private/HWGClient.psm1`) from `_parentbotid_value` to `_botid_value` to match the production scanning scripts `Get-AgentHitlSettings.ps1` and `governance/Test-HitlCheckpointConfiguration.ps1`. Added a comment explaining the platform-version drift in this attribute name.
- **m-1, m-4, m-5:** Bumped version headers from `1.0.0` to `1.1.2` in `Test-HitlWorkflowCompliance.ps1`, `private/HWGClient.psm1`, and `Get-AgentHitlSettings.ps1` so on-disk version metadata matches the solution release.
- **m-2:** Updated module docstring in `create_hwg_environment_variables.py` from "six environment variables" to "eight" — the module already defined eight (`fsi_HWG_IncludeSandbox` and `fsi_HWG_IncludeDrafts` were added previously without updating the count).
- **m-6:** Migrated `Export-HitlGovernanceEvidence.ps1` authentication from MSAL.PS to Az.Accounts via `private/Connect-EnvironmentDataverse.ps1`, aligning with the rest of the solution and removing the last MSAL.PS dependency. Bumped the script `.NOTES` Version from `1.0.0` to `1.1.2` and replaced the MSAL.PS requirement with Az.Accounts >= 2.17.0.

### Changed

- **M-2:** Replaced the local 590-line `hwg_client.py` with a 27-line deprecation stub that raises `ImportError` on use, following the UASD migration pattern. All schema/deployment scripts (`create_hwg_dataverse_schema.py`, `create_hwg_environment_variables.py`, `create_hwg_connection_references.py`, `deploy.py`) now import the shared `DataverseClient` from `scripts/shared/dataverse_client.py`. Per the canonical pattern in `cross-tenant-external-sharing-governance/scripts/migrate_ctsg_optionsets_v1_1_0.py:238-267`, `dry_run` is **not** passed to the shared client constructor — writes are gated locally inside each `create_*` helper so that existence-check reads stay live and `--dry-run` previews remain meaningful. Fixed two latent shared-client API bugs uncovered during the migration: `client.query(...)` returns a list directly (callers had been treating it as `{"value": [...]}`) and the keyword is `filter_expr`, not `filter`. Regenerated `docs/dataverse-schema.md` from the refactored script.
- Bumped solution metadata to v1.1.2 to reflect the council-review remediation set above.

### Deferred

- **m-3 (cosmetic naming inconsistency):** Left in place pending a broader cross-solution naming convention pass; no functional impact.

## [1.1.1] - 2026-05-17

### Added

- Added optional exception-request audit columns (`fsi_RequestedBy`, `fsi_RequestedAt`, `fsi_ApprovalStatus`, `fsi_ApprovalNotes`) so the Power Automate approval flow can track pending, approved, rejected, and timed-out exception requests without relying on non-existent Dataverse fields.
- Added Python `DefaultAzureCredential` support for managed identity, workload identity federation, and local Azure developer credentials when no legacy client secret is provided.

### Changed

- Bumped solution metadata to v1.1.1 for the 2026-Q2 Microsoft Learn refresh.
- Updated Adaptive Card template version to 1.5 for current Teams host compatibility guidance.
- Updated production authentication guidance to prefer managed identity, workload identity federation, or certificate-based auth and to label client secrets as legacy development fallback.

### Fixed

- Aligned scanner detection with the current Human in the Loop connector (`shared_advancedapprovals`) and multistage approval operation ID `StartAndWaitForAnApprovalProcess`.
- Corrected flow instructions for `Start-HitlValidationRunbook.ps1` parameters, required Dataverse columns, deployed connection references, and Power Automate Approvals outputs.
- Regenerated Dataverse schema documentation to include v1.1.0 checkpoint option-set additions and the new exception approval audit columns.
- Updated evidence export metadata from v1.0.1 to v1.1.1.

## [1.1.0] - 2026-04-16

### Fixed

- Critical: `fsi_severity` is a String column in the deployed schema, but `docs/flow-configuration.md` and `docs/troubleshooting.md` instructed flow builders to filter it as a picklist (e.g., `eq 100000003`). Severity filters now use string comparisons (`eq 'Critical' or eq 'High'`).
- Critical: `fsi_actiontype` and `fsi_details` were referenced in flow build instructions and `Export-HitlGovernanceEvidence.ps1` but do not exist in the schema. Removed from docs and evidence projection.
- Critical: `fsi_CheckpointType` is `ApplicationRequired` but `Write-HitlCheckpointResult` and `Write-HitlViolation` could omit it (or set it to `$null`) for missing-HITL or generic detections, causing inserts to fail with `0x80040217`. Both code paths now default to a new `NotApplicable` (100000004) option-set value, and the schema option set was extended with `AdvancedApprovalsGeneric` (100000003) and `NotApplicable` (100000004).
- Critical: `Write-HitlViolation` hard-coded `fsi_checkpointstatus = 100000002` (Partial) for missing-checkpoint cases. Now defaults to `Missing` (100000001) and accepts an explicit `CheckpointStatus` override.
- Critical: `Get-AzAccessToken` calls used only `-ResourceUrl`. Added `-ResourceUri` first / `-ResourceUrl` fallback in `Connect-EnvironmentDataverse.ps1` and `HWGClient.psm1` for compatibility with Az.Accounts >= 5.x.
- Critical: `Connect-EnvironmentDataverse.ps1` returned the raw `$tokenResult.Token` even when it was a `SecureString`, sending unusable bearer tokens to Dataverse on newer Az.Accounts. Token is now unwrapped via `System.Net.NetworkCredential` before caching.
- Critical: `docs/prerequisites.md` instructed administrators to import `Test-HitlWorkflowCompliance.ps1` as the Automation runbook. Replaced with `Start-HitlValidationRunbook.ps1`, which is the actual orchestrator entrypoint.
- Critical: Six environment variables were deployed by `create_hwg_environment_variables.py`, but `README.md` and `docs/flow-configuration.md` documented eight different ones with zero overlap. Added `fsi_HWG_IncludeSandbox` and `fsi_HWG_IncludeDrafts` to the deployment script (the runbook reads both), and rewrote the README configuration section to match the actual deployed variables.
- High: `Get-HitlCheckpointExceptions -ActiveOnly` honored only `fsi_isactive` and ignored `fsi_expiresat`, leaving expired exceptions in effect. Filter now also requires `fsi_expiresat eq null or fsi_expiresat ge <now>`.
- High: Exception lookup in `Test-HitlWorkflowCompliance.ps1` keyed `"$AgentId|$ActionName"`, but `Get-HitlCheckpointExceptions` did not project `ActionName` (no such schema column either). Lookup now uses `FlowName` (added to the projection) and supports an agent-wide `"$AgentId|*"` fallback when no flow is specified.
- High: `Start-HitlValidationRunbook.ps1` failed open on previous-scan query failure (literally `# Failing open`). Failure is now treated as `AuditControlBypass` Critical with a supervisor-visible reason.
- High: Empty agent scan results returned a silent `Passed`. Empty scans are now reported as `Inconclusive` (both in the orchestrator's `OverallStatus` and in the `Test-HitlWorkflowCompliance` JSON metadata).
- High: `Test-HitlWorkflowCompliance.ps1` used `[switch]::new($true)` on lines 178/184 to coerce env-var overrides; replaced with conventional `$true` assignment for runbook reliability.
- Medium: Non-canonical regulatory citations (`FINRA 4511`, `SEC 17a-3/4`, `SOX 404`, `GLBA 501(b)`) standardized to `FINRA Rule 4511(a)`, `SEC Rule 17a-3`, `SEC Rule 17a-4`, `SOX Section 404`, `GLBA Section 501(b)` across 12 files.
- Medium: `README.md` directory tree referenced `Get-HitlCheckpointResults.ps1` (does not exist); corrected to `Get-HWGValidationResults.ps1`. Also moved `templates/` out of the `scripts/` subtree to match repo layout.

### Added

- `fsi_HWG_checkpointtype` option set extended with `AdvancedApprovalsGeneric` (100000003) and `NotApplicable` (100000004) so unclassified checkpoint types do not violate the required-column constraint.
- `fsi_HWG_IncludeSandbox` and `fsi_HWG_IncludeDrafts` Dataverse environment variables (matching what `Start-HitlValidationRunbook.ps1` already reads).



### Fixed

- Critical: Write-HWGValidationHistory -> Write-HitlScanRun, Write-HWGViolation -> Write-HitlViolation (function names now match module exports)
- Write-Output contamination in Object output mode changed to Write-Host

## [1.0.0] - 2026-04-01

### Added

- HITL checkpoint detection engine scanning agent flows for Request for Information and Run a Multistage Approval actions
- Zone-based HITL policy evaluation (Zone 1 advisory, Zone 2 conditional, Zone 3 mandatory)
- Dataverse schema with three tables: fsi_HitlCheckpointResult, fsi_HitlCheckpointException, fsi_HitlScanRun
- Python deployment scripts: schema, environment variables, connection references, orchestrator
- PowerShell governance scripts: scan, compliance test, evidence export, integrity verification
- Azure Automation runbook wrapper with drift detection
- SHA-256 evidence export with manifest for regulatory examination
- Teams adaptive card notification template
- Zone policy configuration template
- Private PowerShell helper modules for Dataverse operations and zone classification
- Documentation: prerequisites, flow configuration (manual build), Dataverse schema, troubleshooting

### Regulatory Alignment

- Supports FINRA Rule 3110 supervision requirements for human review of AI agent outputs
- Aids in FINRA 4511 record retention for supervision evidence
- Helps meet SEC 17a-3/4 documentation requirements for supervisory review
- Supports SOX 302/404 internal control documentation
- Aids in GLBA 501(b) safeguards for customer financial information processing

### Known Limitations

- Microsoft Human in the Loop connector actions (Request for Information, Run a Multistage Approval) are currently in public preview
- Scan detection relies on bot component definitions; flows without saved definitions may not be detected
- Reviewer response content is not captured by scan scripts (only checkpoint presence/absence)
- Zone classification requires Environment Lifecycle Management deployment or naming convention adherence
