# Changelog

All notable changes to the Pipeline Governance Cleanup solution are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to semantic versioning.

---

## [Unreleased]

### Fixed

- **Wave 6 P4b:** Empty catch blocks now log via `Write-Verbose` instead of silently swallowing errors. Output is unchanged unless caller passes `-Verbose`.
- `Send-OwnerNotifications.ps1` nested `Main` function now declares `SupportsShouldProcess`, preserving `-WhatIf` handling for live email sends.

## [1.2.1] - 2026-05-17

### Changed
- Bumped solution manifest version to 1.2.1 for the 2026-Q2 Microsoft Learn refresh.
- Refreshed Power Platform Pipelines guidance for custom host prerequisites, pipeline table references, trigger configuration, PAC CLI authentication, and solution checker integration.

### Fixed
- Corrected custom host Managed Environment guidance: target environments must be Managed Environments, while the custom host should be a dedicated Dataverse environment and does not have to be managed.
- Corrected Deployment Pipeline Default role guidance for custom hosts and documented the Deployment Pipeline Makers team option.
- Corrected Dataverse pipeline trigger settings to use the current Microsoft Dataverse Common / Power Platform Pipelines trigger metadata.

---

## [1.2.0] - 2026-04-17

### Council Review — Technical Accuracy Fixes

This release addresses findings from a 2-member AI Council review (Opus 4.7 + Goldeneye) targeting technical accuracy and customer-readiness.

### Fixed
- **Critical (Send-OwnerNotifications.ps1):** Delegated email send used `Send-MgUserMail -UserId "me"`, which Microsoft Graph rejects (the literal `me` alias works only on `/me/*` endpoints, not `/users/{id}/sendMail`). Every delegated send would fail in production while `-TestMode` previews succeeded. Now resolves the signed-in account from `Get-MgContext().Account` when no explicit `-SenderEmail` is supplied, with a clear error if neither is available.
- **High (Send-OwnerNotifications.ps1):** Transient-error retry detection regex-matched `$_.Exception.Message` for `429|503|504|timeout`. Microsoft Graph throttling responses surface the status on `$_.Exception.Response.StatusCode` and the wait time on the `Retry-After` header — both were ignored. Retry now inspects HTTP status codes (408/429/500/502/503/504), honors `Retry-After` (seconds), and falls back to exponential backoff.
- **High (Get-PipelineInventory.ps1):** Script invoked `pac admin list` without first verifying that an active PAC authentication profile existed. Missing or wrong-scope profiles produced misleading "Failed to list environments" errors or partial inventories. Added a `Test-PacAuth` check that runs `pac auth who` and exits with explicit remediation guidance if no profile is active.
- **High (Get-PipelineInventory.ps1):** Pipeline probe fail-open: when `pac pipeline list` succeeded but the output did not match any documented pattern, the function returned `HasPipelines = "No"` (silently classifying parse failures as compliant). Now returns `Unknown` with a "verify manually" note unless pac explicitly reports zero pipelines.
- **High (README.md schema table):** Pipeline-stage `previousstageid` lookup column renamed to the actual logical name `previousdeploymentstageid` (the Dataverse `deploymentpipelinestage` table uses the `DeploymentPipelineStage`-prefixed schema).
- **Medium (notification-templates.md):** Two flow-template expressions referenced `scheduledremovaldate`, a column that the custom tracking-table guide does not create. Aligned to the actual logical name `enforcementdate` (display name `EnforcementDate`).
- **Medium (Get-PipelineInventory.ps1):** Clarified inline that `ComplianceStatus = "Requires Manual Verification"` is an operator hint, not an evaluated verdict — the public PAC CLI / BAP API do not expose deployment-pipeline host linkage.
- **Medium (Send-OwnerNotifications.ps1):** Added `Microsoft.Graph.Authentication` to `#Requires -Modules` so constrained runspaces (Azure Automation sandboxes, JEA endpoints) load the dependency explicitly.
- **Low:** Regulatory citations normalized to canonical forms — `GLBA Section 501(b)`, `SOX Section 404`, `FINRA Rule 3110(a) / Rule 4511(a)` — across `README.md`, `docs/audit-checklist.md`, and `Send-OwnerNotifications.ps1`.

---

## [1.1.0] - 2026-04-10

### Security Hardening & Compliance Improvements

This release addresses findings from an AI Council review (4 reviewers: Security, Customer Experience, Architecture, Compliance) to prepare the solution for customer testing.

| Category | Change | Severity |
|----------|--------|----------|
| Security | Hard-block placeholder defaults in production sends (requires `-Force` to override) | HIGH |
| Security | URL scheme validation — `MigrationUrl` and `ExemptionUrl` must use `https://` | HIGH |
| Security | Notification audit log CSV written after each run for FINRA evidence trail | HIGH |
| Security | GUID validation on `DesignatedHostId` parameter and `EnvironmentId` before shell interpolation | MEDIUM |
| Security | Graph session wrapped in `try/finally` to guarantee `Disconnect-MgGraph` | MEDIUM |
| Script | `#Requires` directives moved to top of file (before `param()`) in both scripts | HIGH |
| Script | Output directory auto-creation for `Get-PipelineInventory.ps1` `-OutputPath` | MEDIUM |
| Script | Script console references updated from `PORTAL_WALKTHROUGH.md` to `docs/portal-walkthrough.md` | MEDIUM |
| Compliance | Prohibited language fix: "ensures all future deployments" → "helps ensure" in migration guide | HIGH |
| Compliance | Added Data Handling and PII section to README (GLBA 501(b) guidance) | HIGH |
| Compliance | Added legal disclaimer note to notification templates | MEDIUM |
| Compliance | Regulatory citations upgraded to section-level (FINRA 4511(a), 3110(a), SOX §404(a)) | MEDIUM |
| Structure | Renamed `samples/` → `templates/` (per repo convention) | MEDIUM |
| Links | Fixed 5 broken `./README.md` links in docs/ → `../README.md` | HIGH |

#### Added

- `-Force` switch on `Send-OwnerNotifications.ps1` to override placeholder default blocking
- `-ValidateScript` on `MigrationUrl` and `ExemptionUrl` requiring `https://` scheme
- `-ValidateScript` on `DesignatedHostId` requiring valid GUID format
- GUID validation in `Test-EnvironmentPipelines` before `pac pipeline list` execution
- Notification audit log: `NotificationLog_<timestamp>.csv` written to input file directory
- `try/finally` around Graph send loop ensuring `Disconnect-MgGraph` always runs
- Data Handling and PII section in README with storage, retention, and GLBA guidance
- Legal disclaimer guidance note in `docs/notification-templates.md`
- Output directory auto-creation in `Get-PipelineInventory.ps1`

#### Changed

- Version bumped from 1.0.9 to 1.1.0 (structural + security changes warrant minor bump)
- `#Requires` directives moved to line 1 in both PowerShell scripts
- Regulatory citations use section-level references (FINRA Rule 4511(a), Rule 3110(a), SOX §404(a), OCC 2011-12 subtitle)
- `samples/` renamed to `templates/`
- Script banner references updated to new doc paths

#### Fixed

- 5 broken `./README.md` links in docs/ files (resolved to nonexistent `docs/README.md`)
- Prohibited language in `docs/migration-guide.md`: "ensures all" → "helps ensure"
- `PORTAL_WALKTHROUGH.md` references in Get-PipelineInventory.ps1 console output

#### Path Migration Note

File paths changed in v1.0.9 and v1.1.0. For audit trail continuity:
- `src/Get-PipelineInventory.ps1` → `scripts/Get-PipelineInventory.ps1`
- `src/Send-OwnerNotifications.ps1` → `scripts/Send-OwnerNotifications.ps1`
- Root docs (e.g., `AUTOMATION_GUIDE.md`) → `docs/` (e.g., `docs/automation-guide.md`)
- `samples/` → `templates/`

---

## [1.0.9] - 2026-04-10

### Changed

- Restructured solution to follow standard layout
- Moved documentation from root to `docs/` folder
- Moved PowerShell scripts from `src/` to `scripts/`
- Removed `src/` directory (per solution content policy)

---

## [1.0.8] - 2026-01-15

### Documentation Accuracy Fixes

This release addresses three documentation inaccuracies that could cause confusion or set false expectations for makers.

| Issue | Severity | File | Fix |
|-------|----------|------|-----|
| 4.1 | CRITICAL | NOTIFICATION_TEMPLATES.md, Send-OwnerNotifications.ps1 | Changed "deployment configurations will be preserved" to clarify that pipelines must be recreated |
| 4.2 | MEDIUM | README.md, Get-PipelineInventory.ps1 | Added directional-only warning for `-ProbePipelines` text parsing |
| 4.3 | MEDIUM | README.md | Added manual verification requirement for greenfield state detection |

#### Fixed

**Notification Language (Issue 4.1 - CRITICAL)**
- Changed misleading "Your deployment configurations will be preserved" to:
  - "Your deployed solutions will remain in place"
  - "Pipeline definitions must be recreated in the central host"
- This aligns with what MIGRATION_GUIDE.md and LIMITATIONS.md already correctly state
- Affects: NOTIFICATION_TEMPLATES.md (email template) and Send-OwnerNotifications.ps1 (HTML email body)

**-ProbePipelines Output Warning (Issue 4.2 - MEDIUM)**
- Added warning in README.md: "The `-ProbePipelines` output is **directional only**"
- Text parsing of `pac pipeline list` may produce false negatives if output formatting changes
- Added output message in Get-PipelineInventory.ps1 summary when `-ProbePipelines` is used

**Greenfield Verification Guidance (Issue 4.3 - MEDIUM)**
- Clarified that `pac pipeline list` returning no pipelines is only *indicative* of greenfield state
- Added requirement for manual verification in Deployment Pipeline Configuration app
- CLI cannot detect all host configurations

#### Changed

- Version bumped to 1.0.8 across all affected files
- README.md Quick Start Step 1 now includes manual verification requirement
- Get-PipelineInventory.ps1 now displays directional warning after probe summary

---

## [1.0.7] - 2026-01-15

### Second Review Corrections (2026-01-15)

Minor documentation clarifications addressing 6 findings from external review:

| ID | Severity | File | Correction |
|----|----------|------|------------|
| 1 | MEDIUM | MIGRATION_GUIDE.md | Added in-flight deployment warning in Phase 2 |
| 2 | LOW | README.md | Clarified "development environments" → "development source environments" |
| 3 | LOW | README.md | Added verification checkpoint after setting default host |
| 4 | LOW | MIGRATION_GUIDE.md | Clarified Deployment Pipeline Configuration app location |
| 5 | LOW | PORTAL_WALKTHROUGH.md | Clarified Force Link button appears after error is triggered |
| 6 | LOW | README.md | Standardized "Force Link" capitalization (removed hyphens in headings) |

### Added

- **MIGRATION_GUIDE.md** - Comprehensive brownfield migration and coexistence guidance
  - Phase-based migration approach (Assessment → Coexistence → Transition → Validation)
  - Pipeline recreation steps for affected makers
  - Coexistence failure scenarios and resolutions
  - Self-service vs admin-assisted migration guidance
- **Greenfield Quick Start** section in README.md for new implementations
  - Pre-flight checklist for clean-slate deployments
  - Step-by-step quick start for organizations without existing pipelines
- **Decision tree** for platform host vs custom host scenarios in PORTAL_WALKTHROUGH.md
  - Symptom-based scenario identification
  - FSI recommendation for custom host requirement
- **Backup/DR cascade effects** documentation in LIMITATIONS.md (Section 7)
  - What happens during force-link operations
  - What happens if host environment is deleted
  - Recovery options and FSI retention recommendations
- **Managed Environment licensing** implications note in LIMITATIONS.md (Section 8)
  - 2026-02-15 requirement documentation
  - Licensing considerations for FSI
- **Service principal setup guide** for unattended automation in AUTOMATION_GUIDE.md
  - App registration steps
  - Certificate vs secret authentication
  - FSI security considerations
- **DLP considerations** for pipeline deployments in AUTOMATION_GUIDE.md
  - Monitoring flow connector requirements
  - Pipeline deployment DLP impacts
- **Impact assessment template** in NOTIFICATION_TEMPLATES.md
  - Pre-enforcement assessment checklist
  - Risk assessment checklist
  - Operational approvals section
  - Post-enforcement verification
- **Part 7: Managing Pipeline Creator Access** in PORTAL_WALKTHROUGH.md
  - Security role configuration
  - Deployment pipeline default role management
- **Sample CSV files** in `samples/` directory
  - environment-inventory-sample.csv
  - non-compliant-sample.csv
  - samples/README.md with column descriptions
- **FINRA 3110** to FSI Regulatory Alignment section (supervision and oversight)

### Changed

- Expanded Part 0 decision tree in PORTAL_WALKTHROUGH.md
- Enhanced troubleshooting with owner lookup guidance
- Updated escalation timeline to use "Force-Link Execution" instead of "Deactivation"
- Version updated to 1.0.7 across all files

### Removed

- GCC/GCC High admin center URLs from PORTAL_WALKTHROUGH.md (out of scope for US FSI commercial)

### Fixed

- Documentation gaps for customers starting fresh (greenfield)
- Missing coexistence period guidance for brownfield migrations
- Unclear pipeline recreation steps for affected makers

---

## [1.0.6] - 2026-01-15

### Added
- Part 0 in PORTAL_WALKTHROUGH.md: Identify Your Pipelines Host Environment
- Platform host vs custom host distinction in README.md and LIMITATIONS.md
- New environment detection guidance in AUTOMATION_GUIDE.md
- Environment type priority table for Force Link decisions
- GCC/GCC High/DoD admin center URLs in PORTAL_WALKTHROUGH.md

### Changed
- Clarified that Force Link controls environment-host association (affects both to/from deployments)
- Documented "Deployment pipeline default" role for controlling personal pipeline creation
- Enhanced troubleshooting with PAC CLI diagnostic commands (must auth to HOST)
- Added Managed Environment prerequisite note (2026-02-15 requirement)

### Fixed
- Documentation gap for customers using platform host (infrastructure-managed default)

### References
- Platform host: https://learn.microsoft.com/en-us/power-platform/alm/platform-host-pipelines
- Custom host: https://learn.microsoft.com/en-us/power-platform/alm/custom-host-pipelines
- Set default host: https://learn.microsoft.com/en-us/power-platform/alm/set-a-default-pipelines-host

---

## [1.0.5] - 2026-01-15

### Critical Bug Fixes - Technical Review Remediation

This release fixes critical bugs identified during external technical review that would have caused script execution failures.

#### Fixed

**Get-PipelineInventory.ps1 - CLI Command Bug (CRITICAL)**
- Changed `pac env list --json` to `pac admin list --json`
- `pac env list` does not support `--json` parameter
- Reference: [Microsoft Learn - pac admin](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/admin)

**Get-PipelineInventory.ps1 - JSON Property Names (CRITICAL)**
- Fixed property accessors to match `pac admin list --json` output format
- Changed `$env.EnvironmentId` to `$env.'Environment Id'` (property has space)
- Changed `$env.DisplayName` to `$env.Environment`
- Changed `$env.EnvironmentType` to `$env.Type`
- Previous code would return null values for all critical columns

**Get-PipelineInventory.ps1 - Pipeline Probing (HIGH)**
- Removed `--json` flag from `pac pipeline list` command (unsupported)
- Implemented text output parsing to detect pipeline presence
- Reference: [Microsoft Learn - pac pipeline](https://learn.microsoft.com/en-us/power-platform/developer/cli/reference/pipeline)

**Get-PipelineInventory.ps1 - Output Column Updates**
- `IsManaged` and `CreatedTime` now show placeholder values
- These fields are not returned by `pac admin list --json`
- Added notes directing users to verify in admin portal

**Send-OwnerNotifications.ps1 - Application Permissions Support (MEDIUM)**
- Added `-SenderEmail` parameter to support application permissions
- When `-SenderEmail` is provided, uses explicit user ID instead of "me"
- Enables fully automated notification workflows with service principals
- Updated documentation to clarify both delegated and application permissions are supported

**PORTAL_WALKTHROUGH.md - Missing Prerequisite (LOW)**
- Added Managed Environment requirement for target environments
- Starting 2026-02-15, Microsoft requires all pipeline targets to be Managed Environments
- Added link to Microsoft Learn documentation

#### Changed

- Version bumped to 1.0.5 across all scripts
- src/README.md updated with corrected output columns and new parameter
- Clarified CLI command requirements in script comments

### Technical Review Summary

| Finding | Severity | Status |
|---------|----------|--------|
| `pac env list --json` invalid | CRITICAL | ✅ Fixed |
| JSON property names wrong | CRITICAL | ✅ Fixed |
| `pac pipeline list --json` unsupported | HIGH | ✅ Fixed |
| Application permissions not supported | MEDIUM | ✅ Fixed |
| Missing Managed Environment prereq | LOW | ✅ Fixed |

### Migration Notes

If you implemented v1.0.3 or v1.0.4:
1. Replace scripts with v1.0.5 versions - previous versions will not execute correctly
2. If using application permissions for notifications, add `-SenderEmail` parameter
3. Note that `IsManaged` and `CreatedTime` columns now require manual verification

---

## [1.0.4] - 2026-01-15

### Post-Review Enhancements

This release incorporates practical enhancements identified during technical assessment review. Focus areas: operational completeness and FSI compliance alignment.

#### Added

**PORTAL_WALKTHROUGH.md - Rollback Procedure**
- New Part 6: Reversing a Force-Link (Rollback)
- Documents how to move an environment to a different host after force-link
- Includes impact assessment and tracking requirements
- Clarifies there is no "unlink" - only "link to different host"

**README.md - Post-Migration Cleanup**
- New Step 7: Post-Migration Cleanup
- Covers verification, maker communication, documentation, and old host review
- Sample communication template for notifying affected makers

**README.md - Error Recovery Procedures**
- Expanded Troubleshooting section with recovery procedures
- Covers: notification script failures, environment protection errors, inventory unknowns, Graph API errors, propagation delays

**AUDIT_CHECKLIST.md - New File**
- Compliance evidence checklist for auditors
- Pre-enforcement, enforcement, and post-enforcement evidence sections
- Regulatory mapping to OCC 2011-12, FFIEC, SOX 404, FINRA 4511
- Retention requirements guidance
- Evidence collection tips for screenshots, emails, and CSV exports
- Audit interview preparation guide

#### Changed

- PORTAL_WALKTHROUGH.md: Added reference to AUDIT_CHECKLIST.md in See Also section
- README.md version updated to 1.0.4

### Review Assessment Summary

Technical review validated the solution as "production-ready" with zero critical defects. This release addresses optional enhancements that align with FSI-AgentGov framework vision:

| Enhancement | Priority | Rationale |
|-------------|----------|-----------|
| Rollback procedure | HIGH | Practical necessity for admins |
| Post-migration cleanup | HIGH | Completes operational story |
| Compliance audit checklist | MEDIUM | Direct FSI alignment |
| Error recovery procedures | MEDIUM | Operational robustness |

Excluded from scope: Azure Automation integration, Azure Monitor integration, video walkthroughs.

---

## [1.0.3] - 2026-01-15

### Executive Feedback Remediation

This release addresses material correctness gaps identified during executive assessment.

#### Fixed

**Get-PipelineInventory.ps1 - Overpromising Header**
- Updated script description to accurately reflect capabilities (environment inventory only)
- Removed claims about "pipeline configurations per environment" and "owner email resolution via Graph"
- Script header now honestly describes what the script does and its limitations

**Get-PipelineInventory.ps1 - Dead Code Removed**
- Removed unused `-IncludeUserDetails` parameter
- Removed unused `Get-UserEmailFromGraph` function
- Removed Graph connection logic that connected but never used the connection

**Send-OwnerNotifications.ps1 - Permission Claim**
- Fixed documentation: "Mail.Send permission (delegated or application)" → "Mail.Send permission (delegated only - interactive sign-in required)"
- Code uses `Send-MgUserMail -UserId "me"` which requires delegated auth

**NOTIFICATION_TEMPLATES.md - Enforcement Language Consistency**
- Changed all "deactivated" language to "force-link" to match actual enforcement action
- Updated escalation email template: "pipeline will be deactivated" → "environment will be force-linked"
- Updated confirmation email template: describes force-link outcome and impact

**LIMITATIONS.md - Overclaimed Constraint**
- Updated Section 3 to acknowledge `pac pipeline list --environment` CAN detect pipeline presence
- Clarified that host association (not pipeline existence) is what cannot be automated

#### Added

**Get-PipelineInventory.ps1 - Pipeline Probing**
- New `-ProbePipelines` switch that runs `pac pipeline list --environment` for each environment
- Populates `HasPipelinesEnabled` column with "Yes" (with count), "No", or "Unknown"
- Materially reduces manual triage by identifying which environments have pipelines
- Does NOT solve host-association (that still requires manual verification)

**Test-EnvironmentPipelines Function**
- New function that probes individual environments for pipeline configurations
- Handles "no pipelines" vs actual errors gracefully
- Returns structured result with `HasPipelines` and `Notes` fields

#### Changed

- Version bumped to 1.0.3 across all files
- AUTOMATION_GUIDE.md: Added `-ProbePipelines` documentation
- src/README.md: Updated parameters, removed Graph references, fixed permission claim
- README.md: Updated quick start to use `-ProbePipelines`, updated limitations table

### Migration Notes

If you implemented v1.0.2:
1. Update inventory scripts to use `-ProbePipelines` for automated pipeline detection
2. Remove any references to `-IncludeUserDetails` parameter (no longer exists)
3. Review notification templates if using "deactivated" language - update to "force-link"

---

## [1.0.2] - 2026-01-15

### Fixed

#### Critical PowerShell Bugs

- **Get-PipelineInventory.ps1** - Fixed invalid PAC CLI command (`pac admin list` → `pac env list`)
- **Get-PipelineInventory.ps1** - Fixed invalid PowerShell ternary syntax in `Get-UserEmailFromGraph` function
- **Send-OwnerNotifications.ps1** - Added empty CSV check to prevent error when accessing empty array

#### Documentation Consistency

- **AUTOMATION_GUIDE.md** - Added missing output columns (`HasPipelinesEnabled`, `Notes`) to inventory table
- **AUTOMATION_GUIDE.md** - Added complete pipeline trigger event list (`OnPreDeploymentCompleted`, `OnApprovalStarted`, `OnApprovalCompleted`, `OnDeploymentStarted`)
- **AUTOMATION_GUIDE.md** - Standardized output filename to `environment-inventory.csv`
- **README.md** - Added missing DeploymentEnvironment columns (`EnvironmentType`, `ValidationStatus`, `ErrorMessage`)
- **README.md** - Corrected `EnvironmentId` type from GUID to String
- **src/README.md** - Updated output columns list and standardized filename

### Verified Correct

The following were verified as accurate and unchanged:
- All Microsoft Learn URLs are valid
- Regulatory citations (OCC 2011-12, FFIEC, SOX 404, FINRA 4511) are appropriate
- Control references (2.1, 2.3) exist and are correctly linked
- All internal file references are valid

---

## [1.0.1] - 2026-01-15

### Critical Corrections

This release addresses critical technical inaccuracies discovered during solution review that would have caused customer deployment failures.

#### Removed Incorrect Content

- **Removed `pac pipeline link` command** - This command does not exist in the PAC CLI. Force-linking environments is UI-only.
- **Removed "List rows from DeploymentPipeline"** - The DeploymentPipeline table cannot be queried via Power Automate "List rows" action.
- **Removed automated force-link claims** - Force-linking cannot be automated via any API, CLI, or workflow.

#### Added

- **LIMITATIONS.md** - New file documenting technical constraints and what cannot be automated
- **PORTAL_WALKTHROUGH.md** - New file with step-by-step UI procedures for force-linking environments
- **Get-PipelineInventory.ps1** - PowerShell script for environment discovery via PAC CLI
- **Send-OwnerNotifications.ps1** - PowerShell script for sending notifications via Microsoft Graph
- **AUTOMATION_GUIDE.md** - Renamed from FLOW_SETUP.md with corrected content

#### Changed

- **README.md** - Major rewrite with honest limitations section, updated prerequisites, revised workflow showing manual steps
- **SETUP_CHECKLIST.md** - Added [MANUAL] markers to distinguish automated vs manual steps
- **NOTIFICATION_TEMPLATES.md** - Fixed expression references for owner email resolution

#### Documentation

- Expanded Data Model section to include DeploymentStage and DeploymentEnvironment tables
- Added prerequisite: Power Platform Pipelines app installation
- Documented that trigger-based monitoring is the only supported Power Automate approach
- Added Microsoft Learn URL references confirming limitations

### Migration Notes

If you implemented v1.0.0:

1. Remove any flows attempting to "List rows from DeploymentPipeline" - they will not work
2. Remove any PowerShell scripts using `pac pipeline link` - this command does not exist
3. Use the new PowerShell scripts in `scripts/` for inventory and notifications
4. Follow [Portal Walkthrough](docs/portal-walkthrough.md) for manual force-link procedures
5. Review [Limitations](docs/limitations.md) to set correct expectations

---

## [1.0.0] - 2026-01-15

### Added

- Initial release
- **Discovery workflow** - Inventory non-compliant pipelines via Dataverse views and Power Automate flows
- **Owner notification system** - Email and Teams adaptive card templates for communicating with pipeline owners
- **Cleanup flow** - Automated pipeline deactivation with audit logging
- **Custom host enforcement** - Force-link guidance for centralizing pipeline governance
- **Ongoing monitoring** - Validation flow for detecting new violations
- **FSI regulatory alignment** - Mapping to OCC 2011-12, FFIEC, SOX 404, FINRA 4511

### Documentation

- README.md - Solution overview, prerequisites, data model, quick start
- FLOW_SETUP.md - Complete Power Automate flow configuration
- NOTIFICATION_TEMPLATES.md - Email and Teams notification templates
- SETUP_CHECKLIST.md - Quick deployment checklist
- CHANGELOG.md - This file

### Related Framework Controls

- Control 2.3: Change Management and Release Planning
- Control 2.1: Managed Environments

### Known Issues (Addressed in v1.0.1)

- Documentation contained incorrect claims about automation capabilities
- `pac pipeline link` command does not exist
- DeploymentPipeline table cannot be queried via Power Automate
- Force-linking requires manual admin action

---

## Roadmap

### Under Consideration

- Power BI dashboard for compliance tracking
- ServiceNow integration for exemption workflow
- Azure Automation runbook for scheduled inventory
- Teams bot for self-service status queries
