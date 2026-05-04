# Changelog

All notable changes to the Unrestricted Agent Sharing Detector are documented here.


## [Unreleased]

- No unreleased changes.

## [2.0.1] — 2026-05-04

### Fixed
- Updated detector logic and flow guidance to align with current Microsoft Learn Copilot Studio sharing semantics: `accesscontrolpolicy`, `authorizedsecuritygroupids`, `authenticationmode`, and `authenticationtrigger` on the Dataverse `bot` table.
- Corrected auto-remediation to patch both `accesscontrolpolicy=2` and approved `authorizedsecuritygroupids`, skip remediation when no approved groups exist, and retain previous sharing configuration in `fsi_evidencejson` for rollback.
- Regenerated Dataverse schema docs so `fsi_UASD_violationstatus` consistently lists `100000004` = `Remediation Failed`.

### Changed
- Bumped solution manifest to v2.0.1 for the Microsoft Learn 2026-Q2 refresh.
- Marked client-secret setup paths as legacy development fallbacks and documented managed-identity-first automation for unattended scans.

## [2.0.0] — 2026-04-17

### BREAKING
- **`bot.sharingtype` renamed to `bot.accesscontrolpolicy`** in all Dataverse Web API queries, mappings, and PATCH bodies in `Test-AgentSharingCompliance.ps1`. The `sharingtype` column does NOT exist on the Dataverse `bot` table (verified against [Microsoft Learn bot table reference](https://learn.microsoft.com/en-us/power-apps/developer/data-platform/reference/entities/bot)). The actual sharing column is `accesscontrolpolicy` (Picklist: `0`=Any/open, `1`=Copilot readers, `2`=Group membership, `3`=Any multi-tenant), with associated `authorizedsecuritygroupids` (String, comma-separated Entra group IDs). All prior remediation `PATCH { sharingtype: 0 }` calls were silent no-ops; these now correctly emit `PATCH { accesscontrolpolicy: 2 }` (Group membership).
- **`Invoke-SharingAudit.ps1` is deprecated** and now exits non-zero with a redirect message. The script depended on `Get-AdminPowerAppChatBot`, which is NOT a published cmdlet in `Microsoft.PowerApps.Administration.PowerShell` (verified against [module reference](https://learn.microsoft.com/en-us/powershell/module/microsoft.powerapps.administration.powershell/)). Use `Test-AgentSharingCompliance.ps1` instead.
- **`Deploy-DetectionFlow.ps1`, `Deploy-RemediationFlow.ps1`, `Deploy-ExceptionApprovalFlow.ps1`, `Deploy-ExpirationMonitorFlow.ps1` are deprecated** and now exit non-zero. They attempted to provision cloud flows by POSTing raw JSON to the Dataverse `workflows` table — an unsupported pattern that produces non-functional flows (no triggers, connection refs, or solution metadata wired up). Build flows manually per `docs/flow-configuration.md`.

### Fixed
- **Critical:** `fsi_violationstatus` collision — `100000002` is "Exception Approved" in the schema, but flow doc instructed setting it to `100000002 (RemediationFailed)` on remediation failure, causing failed remediations to be silently treated as approved exceptions. Added new option `100000004` = **"Remediation Failed"** to `fsi_UASD_violationstatus`; flow doc updated.
- **High:** `Test-AgentSharingCompliance.ps1` now fails closed when `-DataverseToken` is missing — attempts `Get-AzAccessToken` (Power Platform resource) and throws on failure, instead of sending empty `Bearer` headers and silently skipping all environments with 401s.
- **High:** Coverage gaps surface as `SCAN_COVERAGE_GAP` violation records when an environment's bot query fails, instead of being silently swallowed and reported as "0 violations."
- **High:** `Import-ApprovedSecurityGroups.ps1` rejects invalid zone CSV values (was silently defaulting to Zone 2).
- **Medium:** Severity mapping no longer collapses `Informational` into `100000003` (Low). `Informational` now returns `$null` to suppress persistence (matches existing Compliant gate).
- **Medium:** Shared zone-classification helper path computation no longer adds an extra `..` (was resolving outside the repo, never finding the helper).
- **Medium:** OData filters in `docs/flow-configuration.md` for `fsi_agentid` (string column) are now properly quoted.
- **Low:** Regulatory citations standardized to section-level form across scripts and docs: `FINRA Rule 4511(a)`, `SEC Rule 17a-4`, `SOX Section 302/404`, `GLBA Section 501(b)`.
- **Low:** Removed "automatically enforces approved security policies" overclaim from `SOLUTION-DOCUMENTATION.md` Overview; reworded "enforced by this solution" → "monitored and remediated by this solution" in `README.md`.

### Added
- `Az.Accounts` added to `#Requires -Modules` in `Test-AgentSharingCompliance.ps1` (needed for the new fail-closed token acquisition).
- `accesscontrolpolicy` map (4 values) and cross-tenant detection via `accesscontrolpolicy=3` in `Test-AgentSharingCompliance.ps1`.

### Notes
- Customers using v1.x must re-run `python scripts/create_uasd_dataverse_schema.py` to apply the new `Remediation Failed` option set value before deploying v2.0.0 scripts.
- Existing flow definitions reading or writing `bot.sharingtype` will need to be re-pointed at `bot.accesscontrolpolicy` and `bot.authorizedsecuritygroupids`.

## [1.0.2] — 2026-02-15

### Added
- Flow 4 (`UASD-Exception-Expiration-Monitor`) build instructions in `docs/flow-configuration.md`
  - Daily scheduled flow for proactive exception expiration handling
  - Automated status transition from Approved to Expired
  - Teams adaptive card warnings for exceptions expiring within configurable threshold
  - New environment variable: `fsi_UASD_ExpirationWarningDays` (default: 7)
- Resolved Known Limitation #1 (exception expiration monitoring)

## [1.0.1] — 2026-02-15

### Changed
- Removed `src/` directory with exported flow JSON per Solution Content Policy — flows are now built manually using `docs/flow-configuration.md`
- Removed `DELIVERY-CHECKLIST.md` (no longer applicable without exported artifacts)
- Shared Dataverse client (`scripts/shared/dataverse_client.py`) replaces solution-specific `uasd_client.py`
- Schema script generates `docs/dataverse-schema.md` via `--output-docs` flag
- Trimmed SOLUTION-DOCUMENTATION.md to reference generated schema docs

## [1.0.0] — 2026-02-15

### Added
- Detector scan flow for continuous monitoring of agent sharing configurations
- Remediation flow for automated policy enforcement
- Exception approval workflow for business-justified exceptions
- Exception manager Canvas app for exception lifecycle management
- Teams adaptive card alert for real-time violation notifications
- Dataverse schema setup scripts, environment variables, connection references
- PowerShell governance scripts for sharing audit, violation export, and security group import
