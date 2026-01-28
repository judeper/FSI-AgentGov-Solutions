# Changelog

All notable changes to the Pipeline Governance Cleanup solution are documented here.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/), and this project adheres to semantic versioning.

---

## [1.0.4] - January 2026

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

## [1.0.3] - January 2026

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

## [1.0.2] - January 2026

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

## [1.0.1] - January 2026

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
3. Use the new PowerShell scripts in `src/` for inventory and notifications
4. Follow [PORTAL_WALKTHROUGH.md](./PORTAL_WALKTHROUGH.md) for manual force-link procedures
5. Review [LIMITATIONS.md](./LIMITATIONS.md) to set correct expectations

---

## [1.0.0] - January 2026

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
