# Delivery Checklist

Pre-deployment validation items for Cross-Tenant External Sharing Governance. Complete **ALL** items before setting `IsCrossTenantGovernanceEnabled = "true"`.

> **Warning:** Activating governance flows without completing this checklist may trigger false-positive remediation actions against legitimate cross-tenant relationships.

## API Schema Validation

- [ ] **API 1:** `GET /governance/tenantSettings?api-version=2022-03-01-preview`
  - Confirmed property name: `tenantIsolationEnabled`
  - Confirmed value: _______________
  - Date validated: _______________
  - Validated by: _______________

- [ ] **API 2:** `GET /governance/crossTenantPolicies?api-version=2022-03-01-preview`
  - Confirmed `value[]` array structure: Yes / No
  - Confirmed `tenantId` field name: _______________
  - Confirmed `direction` field name: _______________
  - Date validated: _______________

- [ ] **API 7:** `GET .../bots/{botId}/roleAssignments?api-version=2022-03-01-preview`
  - Returns guest user role assignments: Yes / No
  - Identifiable `principalType` field: Yes / No
  - Confirmed response field names: _______________
  - If principalType not available, fallback to guestUserIndex comparison: Confirmed / Not needed

## Power Platform Admin API Write Endpoints

- [ ] PPAC allow-list write endpoint for tenant isolation management:
  - Endpoint URL: _______________
  - Availability confirmed: Yes / Not available (use manual PPAC steps)
  - Date validated: _______________

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
- [ ] All OptionSet integer values confirmed against deployed solution XML
  - `fsi_ctsg_approvalstatus`: Pending=0, Approved=1, Expired=2, Suspended=3, Revoked=4
  - `fsi_ctsg_findingstatus`: Open=0, Under Review=1, Remediated=2, Approved Exception=3, False Positive=4
  - `fsi_ctsg_severity`: Critical=0, High=1, Medium=2, Low=3
  - `fsi_ctsg_guestdetectionmethod`: EXT# Parsing=0, Mail Field=1, CreationType=2, Multi-Method Agreed=3, Unresolved=4
  - `fsi_ctsg_ppisolationdirection`: Inbound=0, Outbound=1, Both=2, None=3
  - `fsi_ctsg_isolationcompliancestatus`: Compliant=0, Non-Compliant - Isolation Disabled=1, Non-Compliant - Unapproved Entries=2
  - `fsi_ctsg_eventtype`: TenantOnboarded=0, TenantSuspended=1, TenantRevoked=2, ViolationDetected=3, ViolationRemediated=4, ReviewCompleted=5, BaselineUpdated=6

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

- [ ] All 12 environment variables created via `create_ctsg_environment_variables.py`
- [ ] `CTABaseline_OutboundB2BBlocked` decision documented:
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

- [ ] `IsCrossTenantGovernanceEnabled` set to `"true"`
  - Date activated: _______________
  - Activated by: _______________

## Sign-Off

| Role | Name | Date | Signature |
|------|------|------|-----------|
| Power Platform Admin | | | |
| Security Team Lead | | | |
| Governance Committee | | | |
