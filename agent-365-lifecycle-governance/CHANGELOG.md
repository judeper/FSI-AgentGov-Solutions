# Changelog

All notable changes to the Agent 365 Lifecycle Governance solution.

## [1.1.1] - 2026-04-15

### Fixed

- Validate-LifecycleCompliance.ps1: compliance status now returns UNKNOWN when Dataverse queries fail instead of false COMPLIANT
- Validate-LifecycleCompliance.ps1: InactiveAgents count now included in compliance decision logic
- README: replaced "Immutable Audit Trail" overclaim with conditional language requiring security role configuration
- README: added `--client-id` to interactive deployment examples (required by DataverseClient)
- CHANGELOG: replaced "immutable" overclaim with conditional language
- canvas-app-guide.md: corrected `fsi_assignedat` → `fsi_assignmentdate` (matches schema)
- Updated version footers in canvas-app-guide.md, power-bi-dashboard.md, troubleshooting.md to v1.1.0
- Added missing `.PARAMETER DryRun` to comment-based help in both PowerShell scripts

## [1.1.0] - 2026-03-20

### Added

- **Dataverse schema:** 5 custom tables — AgentLifecycleRecord, SponsorAssignment, AccessReview, DeactivationRequest, LifecycleComplianceEvent
- **Schema automation:** `create_alg_dataverse_schema.py` with `--output-docs` and `--dry-run` support
- **Environment variables:** 14 solution-level variables including feature flag (`IsAgent365LifecycleEnabled`)
- **Connection references:** Dataverse, Teams, Approvals, HTTP with Azure AD, Power Platform Admin connectors
- **Flow documentation:** Step-by-step build instructions for 6 Power Automate cloud flows
  - Flow 1: Enforce-SponsorAssignment-OnOnboard (hourly)
  - Flow 2: Schedule-AccessReview-ZoneBased (daily)
  - Flow 3: Detect-InactiveAgents-Daily (daily)
  - Flow 4: Execute-DeactivationWorkflow (called)
  - Flow 5: Monitor-SponsorChanges-Weekly (weekly)
  - Flow 6: Check-DeletionHold-Daily (daily)
- **PowerShell scripts:** Deploy-LifecycleGovernance-Baseline.ps1, Validate-LifecycleCompliance.ps1
- **Templates:** Adaptive Card v1.2 for sponsor assignment notification, sample configuration JSON
- **Documentation:** Prerequisites, canvas app guide, Power BI dashboard guide, troubleshooting
- **Delivery checklist:** Phased pre-deployment and post-deployment validation tasks
- **Feature flag:** `IsAgent365LifecycleEnabled` gates all Agent 365 API calls until GA

### Notes

- Agent 365 GA target: May 1, 2026. Set feature flag to "false" until licensing is confirmed.
- Entra Lifecycle Workflow tasks for agents require Frontier-enabled tenant for pre-GA testing.
- Default access review decision is "Deny" — silence equals revocation in FSI regulatory contexts.
- `fsi_lifecyclecomplianceevent` table supports append-only operation when no-delete security roles are configured, with 7-year Dataverse LTR.
