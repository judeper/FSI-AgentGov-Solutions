# Changelog

All notable changes to the Agent 365 Lifecycle Governance solution.

## [1.1.1] - 2026-04-16

### Fixed

- Fixed 13 Dataverse column name mismatches in flow-configuration.md to match deployed schema (e.g., fsi_assigneddate → fsi_assignmentdate, fsi_requeststatus → fsi_approvalstatus, fsi_deletionholdexpiry → fsi_deletionholduntil)
- Fixed 3 event type label mismatches in flow-configuration.md (e.g., "Access Review Created" → "Access Review Started", "Agent Deactivated" → "Agent Disabled")
- Fixed Deploy-LifecycleGovernance-Baseline.ps1 error message to cite correct permission (AgentRegistry.ReadWrite.All)
- Fixed canvas-app-guide.md column reference: fsi_assignedat → fsi_assignmentdate
- Fixed DELIVERY-CHECKLIST.md version from v1.0.0 to v1.1.0

### Added

- Added 5 missing event types to fsi_ALG_eventtype option set: Feature Flag Skip, Activity Data Unavailable, Duplicate Request Skipped, Deletion Hold Extended, Access Review Denied
- Added TODO comment for Agent 365 GA API endpoint verification
- Created `.ralph-config.json` with domain facts from council review

### Updated

- Product name: "HTTP with Azure AD" → "HTTP with Microsoft Entra ID" in connection reference script

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
- `fsi_lifecyclecomplianceevent` table is immutable (no delete for non-admin roles) with 7-year Dataverse LTR.
