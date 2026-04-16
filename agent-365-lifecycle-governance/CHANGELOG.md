# Changelog

All notable changes to the Agent 365 Lifecycle Governance solution.

## [1.1.2] - 2026-04-08

### Fixed

- flow-configuration.md: replaced all picklist string labels with integer values matching `fsi_ALG_*` option sets (e.g., `'Active'` → `100000001`, `'In Progress'` → `100000001`)
- flow-configuration.md: replaced non-existent columns — `fsi_eventdate` → `fsi_timestamp`, `fsi_correlationid` → `fsi_relatedrecordid`, `fsi_reviewcompleteddate` → `fsi_decisiondate`, `fsi_reviewoutcome` → `fsi_certifierdecision`
- flow-configuration.md: replaced `fsi_agentid` on child tables (SponsorAssignment, AccessReview, DeactivationRequest) with `fsi_AgentLifecycleRecordLookup@odata.bind` lookup binding
- flow-configuration.md: moved `fsi_sponsorupn` on compliance event table into `fsi_eventdetails` JSON
- flow-configuration.md: replaced `fsi_agentname` on DeactivationRequest with `fsi_name`
- flow-configuration.md: added missing required fields — `fsi_sponsordisplayname`, `fsi_assignedby`, `fsi_AgentLifecycleRecordLookup@odata.bind` on SponsorAssignment; `fsi_name`, `fsi_triggeredby`, `fsi_timestamp` on LifecycleComplianceEvent; `fsi_name`, `fsi_zonecadence`, `fsi_AgentLifecycleRecordLookup@odata.bind` on AccessReview; `fsi_name`, `fsi_AgentLifecycleRecordLookup@odata.bind` on DeactivationRequest
- flow-configuration.md: corrected event type values — `"Feature Flag Skip"` → Zone Assigned with detail in fsi_eventdetails, `"Access Review Created"` → Access Review Started, `"Access Review Denied"` → Access Review Completed with certifier decision, `"Activity Data Unavailable"` → Inactivity Detected with detail, `"Duplicate Request Skipped"` → Deactivation Requested with detail, `"Agent Deactivated"` → Agent Disabled, `"Sponsor Reassigned"` → Sponsor Assigned with detail, `"Deletion Hold Extended"` → Deactivation Approved with detail
- flow-configuration.md: added `fsi_disabledate` to Flow 4 Step 5c deactivation approval update
- create_alg_dataverse_schema.py: replaced "Immutable event log" with "Append-only event log" for fsi_LifecycleComplianceEvent description
- dataverse-schema.md: replaced "Immutable event log" with "Append-only event log"
- DELIVERY-CHECKLIST.md: replaced "Immutable compliance event records" with "Append-only compliance event records (requires no-delete security roles)"
- Deploy-LifecycleGovernance-Baseline.ps1: documented `DataverseEnvironmentUrl` parameter as reserved for future Dataverse validation
- canvas-app-guide.md: corrected "Informational" to "None" in compliance impact dropdown to match fsi_ALG_complianceimpact option set
- Updated version footers in DELIVERY-CHECKLIST.md, canvas-app-guide.md, power-bi-dashboard.md, troubleshooting.md to v1.1.1

## [1.1.1] - 2026-04-15

### Fixed

- Test-LifecycleCompliance.ps1: compliance status now returns UNKNOWN when Dataverse queries fail instead of false COMPLIANT
- Test-LifecycleCompliance.ps1: InactiveAgents count now included in compliance decision logic
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
- **PowerShell scripts:** Deploy-LifecycleGovernance-Baseline.ps1, Test-LifecycleCompliance.ps1
- **Templates:** Adaptive Card v1.2 for sponsor assignment notification, sample configuration JSON
- **Documentation:** Prerequisites, canvas app guide, Power BI dashboard guide, troubleshooting
- **Delivery checklist:** Phased pre-deployment and post-deployment validation tasks
- **Feature flag:** `IsAgent365LifecycleEnabled` gates all Agent 365 API calls until GA

### Notes

- Agent 365 GA target: May 1, 2026. Set feature flag to "false" until licensing is confirmed.
- Entra Lifecycle Workflow tasks for agents require Frontier-enabled tenant for pre-GA testing.
- Default access review decision is "Deny" — silence equals revocation in FSI regulatory contexts.
- `fsi_lifecyclecomplianceevent` table supports append-only operation when no-delete security roles are configured, with 7-year Dataverse LTR.
