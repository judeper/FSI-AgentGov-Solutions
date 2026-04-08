# Changelog

All notable changes to the Agent Sharing Access Restriction Detector are documented here.

## [1.0.3] — April 2026

### Added
- Dataverse schema script with 2 tables, 3 option sets, and `--output-docs` support
- Environment variables script (4 variables for template URL, BAP API, approval timeout, governance lead)
- Connection references script (Dataverse, Teams, Approvals, HTTP Premium)
- PowerShell governance scripts: Invoke-SharingComplianceScan, Test-AgentSharingCompliance, Get-ExpectedSharingPolicy, Export-SharingComplianceEvidence, Test-EvidenceIntegrity
- Python zone rules engine (asard_zone_rules.py) with zone policy evaluation
- Auto-generated Dataverse schema documentation
- Seven new columns on AgentSharingCompliance table: SharingType, ViolationType, Severity, Description, ScanRunId, SharedGroupIds, RegulatoryContext

### Fixed
- Aligned PS script column references with Dataverse schema (`fsi_groupid` → `fsi_securitygroupid`, `fsi_groupname` → `fsi_securitygroupname`)
- Removed `exit 0` from Invoke-SharingComplianceScan.ps1 and Test-AgentSharingCompliance.ps1 (broke dot-sourcing)
- Fixed snake_case column names in docs and adaptive card templates to match Dataverse logical names
- Fixed ComplianceStatus option set values in docs (was 0–3, corrected to 100000000–100000003)
- Fixed CHANGELOG date ordering (v1.0.2 was incorrectly dated July 2025)
- Added MSAL.PS deprecation notice in Export-SharingComplianceEvidence.ps1

## [1.0.2] — March 2026

### Changed
- Restructured solution to follow standard layout
- Moved adaptive card templates from `src/` to `templates/`
- Removed exported Power Automate flow JSON from `src/` (per content policy)
- Added `docs/` with `flow-configuration.md` and `prerequisites.md`

## [1.0.1] — March 2026

### Fixed
- **CRITICAL**: ApprovalTimeoutDays null guard now uses `coalesce()` in both branches of the ternary, preventing null from producing an invalid ISO 8601 duration (`"PD"`)
- **WARNING**: Unknown zone values now default to Zone 1 (most restrictive — remove all access) instead of Zone 3 (least restrictive) in `Build_Permission_Objects` and `Build_Approval_Card_Data`
- **WARNING**: `Start_Approval` and `Wait_For_Approval` wrapped in `Scope_Approval` with `Handle_Approval_Scope_Failure` error handler that updates Dataverse to Error status on connector failure
- **WARNING**: Exception review queries (`Query_Expiring_Exceptions`, `Query_Expired_Exceptions`) increased `$top` from 100 to 5,000 (Dataverse maximum) to reduce silent data loss risk

### Documentation
- Added N+1 approved groups query pattern to README Known Limitations
- Updated exception query pagination documentation to reflect 5,000 record limit

## [1.0.0] — February 2026

### Added
- Remediation approval workflow (`asard-remediation-approval-workflow.json`) for governance-gated sharing corrections
- Exception review workflow (`asard-exception-review-workflow.json`) for automated expiration handling and renewal notifications
- Violation alert adaptive card (`adaptive-card-asard-alert.json`) for Teams notifications
- Remediation approval adaptive card (`adaptive-card-asard-remediation-approval.json`) for approval requests
- Remediation result adaptive card (`adaptive-card-asard-remediation-result.json`) for outcome notifications
- Exception expiring warning card (`adaptive-card-asard-exception-expiring.json`) for proactive renewal prompts
- Exception expired notification card (`adaptive-card-asard-exception-expired.json`) for expiration alerts
- All 7 artifacts created for zone-based agent sharing governance
