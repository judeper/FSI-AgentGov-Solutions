# Delivery Checklist

Pre-deployment validation items for Cross-Tenant External Sharing Governance. Complete **ALL** items before setting `fsi_CTSG_IsCrossTenantGovernanceEnabled = "true"`.

> **Warning:** Activating governance flows without completing this checklist may trigger false-positive remediation actions against legitimate cross-tenant relationships.

## API Schema Validation

- [ ] **Power Platform tenant isolation:** Validate the tenant isolation policy with the documented Microsoft.PowerApps.Administration.PowerShell cmdlet before enabling Flow 1.
  - Command run: `Get-PowerAppTenantIsolationPolicy -TenantId <tenantId>`
  - Confirmed tenant isolation state property in returned policy: _______________
  - Confirmed allow-list/rules collection property and entry shape: _______________
  - Confirmed each rule exposes tenant identifier and allowed direction: Yes / No
  - Date validated: _______________
  - Validated by: _______________

- [ ] **Power Platform tenant isolation updates:** If Flow 4/5 will request policy updates, validate `Set-PowerAppTenantIsolationPolicy -TenantId <tenantId> -TenantIsolationPolicy <policyObject>` in a non-production tenant first.
  - Write endpoint/cmdlet availability confirmed: Yes / Not available (use manual PPAC steps)
  - Date validated: _______________

- [ ] **Copilot Studio agent role assignments:** `GET .../bots/{botId}/roleAssignments?api-version=<confirmed-version>`
  - Returns guest user role assignments: Yes / No
  - Identifiable `principalType` field: Yes / No
  - Confirmed response field names: _______________
  - If principalType not available, fallback to guestUserIndex comparison: Confirmed / Not needed

## Dependent Solution Validation

- [ ] `agent-registry-automation` deployed and active
  - `fsi_agentinventory` table accessible: Yes / No
  - Confirmed zone column name: `fsi_zone` (logical name)
  - OptionSet values: Zone 1=1, Zone 2=2, Zone 3=3
  - Date validated: _______________

- [ ] `unrestricted-agent-sharing-detector` deployed and active
  - Date validated: _______________

## Dataverse Deployment

- [ ] All 5 tables deployed via `create_ctsg_dataverse_schema.py`
- [ ] Entity set names confirmed:
  - `fsi_approvedexternaltenants`: _______________
  - `fsi_externalsharefindings`: _______________
  - `fsi_tenantisolationrecords`: _______________
  - `fsi_entractarecords`: _______________
  - `fsi_crosstenantcomplianceevents`: _______________
- [ ] All OptionSet integer values confirmed against `docs/dataverse-schema.md` (auto-generated from `scripts/create_ctsg_dataverse_schema.py` — the source of truth; this solution does not ship an exported solution package per repo content policy). All `fsi_ctsg_*` option sets use the Dataverse-default 100000000-based encoding (v1.1.0 [BREAKING DEPLOY] migration; see CHANGELOG migration notes for re-key instructions).
  - `fsi_ctsg_approvalstatus`: Pending=100000000, Approved=100000001, Expired=100000002, Suspended=100000003, Revoked=100000004
  - `fsi_ctsg_findingstatus`: Open=100000000, Under Review=100000001, Remediated=100000002, Approved Exception=100000003, False Positive=100000004
  - `fsi_ctsg_severity`: Critical=100000000, High=100000001, Medium=100000002, Low=100000003
  - `fsi_ctsg_guestdetectionmethod`: EXT# Parsing=100000000, Mail Field=100000001, CreationType=100000002, Multi-Method Agreed=100000003, Unresolved=100000004
  - `fsi_ctsg_ppisolationdirection`: Inbound=100000000, Outbound=100000001, Both=100000002, None=100000003
  - `fsi_ctsg_isolationcompliancestatus`: Compliant=100000000, Non-Compliant - Isolation Disabled=100000001, Non-Compliant - Unapproved Entries=100000002
  - `fsi_ctsg_eventtype`: Tenant Isolation Validated=100000000, Tenant Isolation Violation=100000001, External Share Detected=100000002, External Share Remediated=100000003, Entra CTA Audited=100000004, Entra CTA Violation=100000005, Tenant Onboarding Initiated=100000006, Tenant Approved=100000007, Tenant Expired=100000008, Tenant Suspended=100000009, Tenant Revoked=100000010, Annual Review Due=100000011, Annual Review Overdue=100000012, Annual Review Completed=100000013, Remediation Approved=100000014, Remediation Rejected=100000015, API Schema Validation Failed=100000016, Feature Flag Skip=100000017, Flow Error=100000018, Duplicate Remediation Skipped=100000019, Critical Finding Manual Remediation Required=100000020
  - `fsi_acv_zone` (SHARED option set — retains legacy 0-based encoding): Unclassified=0, Zone 1=1, Zone 2=2, Zone 3=3 — see `create_ctsg_dataverse_schema.py` SHARED_OPTIONSETS comment for cross-solution rationale

## Adjacent Control Validation

- [ ] Tenant Restrictions v2 policy reviewed in Microsoft Entra cross-tenant access settings / Global Secure Access for outbound authentication-plane enforcement.
- [ ] SharePoint tenant external sharing reviewed with `Set-SPOTenant` settings and representative `Get-SPOSite -Detailed | Select SharingCapability` output.
- [ ] OneDrive sharing capability reviewed with `Set-SPOTenant -OneDriveSharingCapability` or user-level OneDrive sharing settings where applicable.
- [ ] Copilot Studio Managed Environment agent sharing limits reviewed; existing agent access reviewed separately because sharing limits affect future sharing attempts.

## Managed Identity Configuration

- [ ] `MI-CrossTenantReadOnly` provisioned
  - Assigned permissions: Policy.Read.All, User.Read.All, CrossTenantInformation.ReadBasic.All, Organization.Read.All, PowerPlatform.Admin.Read.All
  - Date configured: _______________

- [ ] `MI-CrossTenantReadWrite` provisioned
  - Assigned permissions: Policy.ReadWrite.CrossTenantAccess, User.Read.All, CrossTenantInformation.ReadBasic.All, PowerPlatform.Admin.ReadWrite.All
  - Policy.ReadWrite.CrossTenantAccess approved by Entra Global Admin: Yes / Pending
  - Date configured: _______________

## Baseline and Registry Population

- [ ] `Deploy-CrossTenantBaseline.ps1` executed successfully
  - Baseline report file: _______________
  - Date run: _______________

- [ ] All existing cross-tenant relationships registered in `fsi_approvedexternaltenant`
  - Total tenants registered: _______________
  - All entries have `fsi_approvalstatus = "Approved"`: Yes / No

## Environment Configuration

- [ ] All 13 environment variables created via `create_ctsg_environment_variables.py`
- [ ] `fsi_CTSG_CTABaselineOutboundB2BBlocked` decision documented:
  - Zone 1/2 value: _______________
  - Zone 3 value: _______________
  - Business rationale: _______________

## Flow Deployment

- [ ] Flow 1 (Validate-TenantIsolation-Daily) built and tested
- [ ] Flow 2 (Detect-ExternalAgentShares-Daily) built and tested
- [ ] Flow 3 (Audit-EntraCrossTenantSettings-Weekly) built and tested
- [ ] Flow 4 (Execute-ExternalTenantOnboarding) built and tested
- [ ] Flow 5 (Remediate-UnauthorizedExternalAccess) built and tested
- [ ] Flow 6 (Send-AnnualReviewReminders-Daily) built and tested

## Post-Deployment

- [ ] `fsi_crosstenantcomplianceevent` Long-Term Retention configured (7-year)
  - Configured via: Power Platform Admin Center
  - Date configured: _______________

- [ ] `fsi_CTSG_IsCrossTenantGovernanceEnabled` set to `"true"`
  - Date activated: _______________
  - Activated by: _______________

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Power Platform Admin | | | |
| Security Team Lead | | | |
| Governance Committee | | | |
