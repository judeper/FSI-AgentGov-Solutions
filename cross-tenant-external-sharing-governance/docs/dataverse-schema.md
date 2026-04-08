# Dataverse Schema

Table definitions for the Cross-Tenant External Sharing Governance solution.

> Auto-generated from `create_ctsg_dataverse_schema.py`. Regenerate after schema changes:
> ```bash
> python scripts/create_ctsg_dataverse_schema.py --output-docs
> ```

---

## Schema Overview

```
┌─────────────────────────────┐
│  fsi_approvedexternaltenant │
│  (approved tenant allow list)│
│  AK: fsi_tenantid           │
└──────────────┬──────────────┘
               │
               │ Lookup (nullable)
               ▼
┌─────────────────────────────┐       ┌─────────────────────────────┐
│  fsi_externalsharefinding   │       │ fsi_tenantisolationrecord   │
│  (detected violations)      │       │ (daily PP isolation snaps)  │
│  AK: fsi_agentid +          │       └─────────────────────────────┘
│      fsi_externaltenantid + │
│      fsi_findingtype         │       ┌─────────────────────────────┐
└─────────────────────────────┘       │ fsi_entractarecord          │
                                      │ (weekly Entra CTA snaps)    │
┌─────────────────────────────┐       └─────────────────────────────┘
│ fsi_crosstenantcompliance-  │
│ event                       │
│ (immutable audit log)       │
│ [LTR-enabled]               │
└─────────────────────────────┘

AK  = Alternate Key
LTR = Long-Term Retention
```

---

## Tables Overview

| # | SchemaName | Logical Name | Display Name | Ownership | Description |
|---|-----------|-------------|--------------|-----------|-------------|
| 1 | fsi_ApprovedExternalTenant | fsi_approvedexternaltenant | Approved External Tenant | UserOwned | Authoritative allow list of approved external tenants |
| 2 | fsi_ExternalShareFinding | fsi_externalsharefinding | External Share Finding | OrganizationOwned | Detected external sharing violations |
| 3 | fsi_TenantIsolationRecord | fsi_tenantisolationrecord | Tenant Isolation Record | OrganizationOwned | Daily tenant isolation audit snapshots |
| 4 | fsi_EntraCTARecord | fsi_entractarecord | Entra CTA Record | OrganizationOwned | Weekly Entra CTA audit snapshots |
| 5 | fsi_CrossTenantComplianceEvent | fsi_crosstenantcomplianceevent | Cross-Tenant Compliance Event | OrganizationOwned | Immutable compliance event log |

---

## Table 1: Approved External Tenant

**SchemaName:** `fsi_ApprovedExternalTenant`
**Logical Name:** `fsi_approvedexternaltenant`
**Ownership:** UserOwned

Authoritative allow list of approved external tenants. Each record represents one external Microsoft Entra ID tenant authorized for cross-tenant interaction with documented business justification and dual approval.

### Columns

| Column Display | SchemaName | Logical Name | Type | Required | Notes |
|---------------|-----------|-------------|------|----------|-------|
| Tenant Record ID | fsi_ApprovedExternalTenantId | fsi_approvedexternaltenantid | Uniqueidentifier | Yes | Primary key (auto-generated) |
| Tenant Name | fsi_TenantName | fsi_tenantname | String(200) | Yes | External org display name |
| Tenant ID | fsi_TenantId | fsi_tenantid | String(100) | Yes | Entra tenant GUID — alternate key |
| Primary Domain | fsi_PrimaryDomain | fsi_primarydomain | String(200) | Yes | Primary verified domain |
| Relationship Type | fsi_RelationshipType | fsi_relationshiptype | Choice | Yes | See option set below |
| Approval Status | fsi_ApprovalStatus | fsi_approvalstatus | Choice | Yes | See option set below |
| Approved By | fsi_ApprovedBy | fsi_approvedby | String(200) | No | Approver UPN |
| Approval Date | fsi_ApprovalDate | fsi_approvaldate | DateTime | No | UTC approval timestamp |
| Business Justification | fsi_BusinessJustification | fsi_businessjustification | Memo(10000) | Yes | Min 100 characters required |
| Risk Tier | fsi_RiskTier | fsi_risktier | Choice | Yes | See option set below |
| Permitted Access Scope | fsi_PermittedAccessScope | fsi_permittedaccessscope | Memo(10000) | Yes | Specific environments, agents, and connectors permitted |
| PP Isolation Direction | fsi_PPIsolationDirection | fsi_ppisolationdirection | Choice | No | See option set below |
| Entra B2B Collaboration | fsi_EntraB2BCollaboration | fsi_entrab2bcollaboration | Yes/No | Yes | Default: No |
| Entra B2B Direct Connect | fsi_EntraB2BDirectConnect | fsi_entrab2bdirectconnect | Yes/No | Yes | Default: No |
| Agent Share Permitted | fsi_AgentSharePermitted | fsi_agentsharepermitted | Yes/No | Yes | Default: No |
| Annual Review Due | fsi_AnnualReviewDue | fsi_annualreviewdue | DateTime | Yes | `fsi_approvaldate` + 12 months |
| Last Review Date | fsi_LastReviewDate | fsi_lastreviewdate | DateTime | No | Last periodic review timestamp |
| Requesting Team | fsi_RequestingTeam | fsi_requestingteam | String(200) | Yes | Internal team requesting the relationship |
| Security Attestation | fsi_SecurityAttestation | fsi_securityattestation | Yes/No | Yes | Default: No |
| Expiry Notes | fsi_ExpiryNotes | fsi_expirynotes | Memo(5000) | No | Populated when status is Expired or Revoked |
| Notes | fsi_Notes | fsi_notes | Memo(10000) | No | Additional governance notes |
| Created On | createdon | createdon | DateTime | Auto | Record creation timestamp |
| Modified On | modifiedon | modifiedon | DateTime | Auto | Last modification timestamp |

### Alternate Key

| Key Name | Columns | Purpose |
|----------|---------|---------|
| `fsi_ak_approvedtenant_tenantid` | `fsi_tenantid` | Unique tenant GUID prevents duplicate registrations. Enables upsert-based idempotent import. |

> **Note:** After schema deployment, the alternate key status may show **Pending** for up to 30 minutes while Dataverse builds the index. Check status in **Power Apps** > **Tables** > **Approved External Tenant** > **Keys**.

### Sample Data

```json
{
  "fsi_tenantname": "Contoso Financial Services",
  "fsi_tenantid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "fsi_primarydomain": "contoso.com",
  "fsi_relationshiptype": 0,
  "fsi_approvalstatus": 1,
  "fsi_approvedby": "governance.admin@yourorg.onmicrosoft.com",
  "fsi_approvaldate": "2026-01-15T00:00:00Z",
  "fsi_businessjustification": "Contoso Financial Services is a subsidiary providing shared services including agent development and data analytics. Cross-tenant access is required for joint Copilot Studio agent development in the shared innovation environment.",
  "fsi_risktier": 1,
  "fsi_permittedaccessscope": "DEV environment only. Agents: Innovation-CoPilot, Data-Analytics-Bot. Connectors: SharePoint, Dataverse.",
  "fsi_ppisolationdirection": 2,
  "fsi_entrab2bcollaboration": true,
  "fsi_entrab2bdirectconnect": false,
  "fsi_agentsharepermitted": true,
  "fsi_annualreviewdue": "2027-01-15T00:00:00Z",
  "fsi_requestingteam": "Innovation Lab",
  "fsi_securityattestation": true,
  "fsi_notes": "Annual review reminder set for 2026-10-15 (90 days prior)."
}
```

---

## Table 2: External Share Finding

**SchemaName:** `fsi_ExternalShareFinding`
**Logical Name:** `fsi_externalsharefinding`
**Ownership:** OrganizationOwned

Detected external sharing violations. Each record represents a single finding where agent sharing, guest access, or cross-tenant configuration does not align with the approved tenant allow list.

### Columns

| Column Display | SchemaName | Logical Name | Type | Required | Notes |
|---------------|-----------|-------------|------|----------|-------|
| Finding ID | fsi_ExternalShareFindingId | fsi_externalsharefindingid | Uniqueidentifier | Yes | Primary key (auto-generated) |
| Name | fsi_Name | fsi_name | String(200) | Yes | Auto-generated: "{FindingType} — {AgentName}" |
| Agent ID | fsi_AgentId | fsi_agentid | String(36) | Yes | Copilot Studio agent ID. Part of alternate key. |
| Agent Name | fsi_AgentName | fsi_agentname | String(200) | Yes | Agent display name |
| Environment ID | fsi_EnvironmentId | fsi_environmentid | String(36) | Yes | Power Platform environment ID |
| Environment Name | fsi_EnvironmentName | fsi_environmentname | String(200) | No | Environment display name |
| External Tenant ID | fsi_ExternalTenantTenantId | fsi_externaltenanttenantid | String(100) | Yes | External tenant GUID. Part of alternate key. |
| External Tenant Domain | fsi_ExternalTenantDomain | fsi_externaltenantdomain | String(200) | No | External tenant primary domain |
| Guest UPN | fsi_GuestUPN | fsi_guestupn | String(320) | No | Guest user UPN (for guest-based findings) |
| Guest Detection Method | fsi_GuestDetectionMethod | fsi_guestdetectionmethod | Choice | No | How guest home tenant was resolved. See option set below. |
| Finding Type | fsi_FindingType | fsi_findingtype | Choice | Yes | Type of violation. Part of alternate key. See option set below. |
| Governance Layer | fsi_GovernanceLayer | fsi_governancelayer | Choice | Yes | Which governance layer detected this finding |
| Severity | fsi_Severity | fsi_severity | Choice | Yes | Finding severity |
| Finding Status | fsi_FindingStatus | fsi_findingstatus | Choice | Yes | Current status of this finding |
| Remediation Status | fsi_RemediationStatus | fsi_remediationstatus | Choice | No | Remediation workflow status |
| Detected At | fsi_DetectedAt | fsi_detectedat | DateTime | Yes | UTC detection timestamp |
| Details | fsi_Details | fsi_details | Memo(10000) | No | JSON with finding-specific details |
| Approved Tenant Lookup | fsi_ApprovedExternalTenantLookup | fsi_approvedexternaltenantlookup | Lookup | No | Reference to approved tenant record (null if unapproved) |
| Created On | createdon | createdon | DateTime | Auto | Record creation timestamp |
| Modified On | modifiedon | modifiedon | DateTime | Auto | Last modification timestamp |

### Alternate Key

| Key Name | Columns | Purpose |
|----------|---------|---------|
| `fsi_ak_finding_dedup` | `fsi_agentid`, `fsi_externaltenanttenantid`, `fsi_findingtype` | Deduplication — prevents duplicate findings for the same agent + tenant + finding type combination. Flow upserts on this key. |

### Sample Data

```json
{
  "fsi_name": "Unapproved Tenant — Customer Service Agent",
  "fsi_agentid": "12345678-1234-1234-1234-123456789012",
  "fsi_agentname": "Customer Service Agent",
  "fsi_environmentid": "87654321-4321-4321-4321-210987654321",
  "fsi_environmentname": "Production - Customer Service",
  "fsi_externaltenanttenantid": "deadbeef-dead-beef-dead-beefdeadbeef",
  "fsi_externaltenantdomain": "unknown-partner.com",
  "fsi_guestupn": "ext.user_unknown-partner.com#EXT#@yourorg.onmicrosoft.com",
  "fsi_guestdetectionmethod": 0,
  "fsi_findingtype": 0,
  "fsi_governancelayer": 2,
  "fsi_severity": 0,
  "fsi_findingstatus": 0,
  "fsi_remediationstatus": 0,
  "fsi_detectedat": "2026-03-20T06:00:00Z",
  "fsi_details": "{\"sharingMethod\":\"DirectShare\",\"sharedObjectType\":\"CopilotAgent\",\"detectedDuring\":\"DailyScan\"}"
}
```

---

## Table 3: Tenant Isolation Record

**SchemaName:** `fsi_TenantIsolationRecord`
**Logical Name:** `fsi_tenantisolationrecord`
**Ownership:** OrganizationOwned

Daily Power Platform tenant isolation audit snapshots. Each record captures the full isolation rule configuration at a point in time, enabling drift detection by comparing consecutive snapshots.

### Columns

| Column Display | SchemaName | Logical Name | Type | Required | Notes |
|---------------|-----------|-------------|------|----------|-------|
| Record ID | fsi_TenantIsolationRecordId | fsi_tenantisolationrecordid | Uniqueidentifier | Yes | Primary key (auto-generated) |
| Name | fsi_Name | fsi_name | String(200) | Yes | Auto-generated: "PP Isolation — {SnapshotDate}" |
| Snapshot Date | fsi_SnapshotDate | fsi_snapshotdate | DateTime | Yes | UTC date of snapshot collection |
| Isolation Enabled | fsi_IsolationEnabled | fsi_isolationenabled | Yes/No | Yes | Whether PP tenant isolation is enabled |
| Total Rule Count | fsi_TotalRuleCount | fsi_totalrulecount | WholeNumber | Yes | Total number of isolation rules |
| Inbound Rule Count | fsi_InboundRuleCount | fsi_inboundrulecount | WholeNumber | Yes | Inbound-only rules |
| Outbound Rule Count | fsi_OutboundRuleCount | fsi_outboundrulecount | WholeNumber | Yes | Outbound-only rules |
| Both Direction Rule Count | fsi_BothDirectionRuleCount | fsi_bothdirectionrulecount | WholeNumber | Yes | Bidirectional rules |
| Compliance Status | fsi_IsolationComplianceStatus | fsi_isolationcompliancestatus | Choice | Yes | See option set below |
| Drift Detected | fsi_DriftDetected | fsi_driftdetected | Yes/No | Yes | Config differs from prior snapshot |
| Drift Details | fsi_DriftDetails | fsi_driftdetails | Memo(10000) | No | JSON diff of changed rules |
| Rules JSON | fsi_RulesJson | fsi_rulesjson | Memo(100000) | No | Full PP isolation rule snapshot (JSON) |
| Collected By | fsi_CollectedBy | fsi_collectedby | String(200) | Yes | Script or flow that collected the snapshot |
| Created On | createdon | createdon | DateTime | Auto | Record creation timestamp |

### Sample Data

```json
{
  "fsi_name": "PP Isolation — 2026-03-20",
  "fsi_snapshotdate": "2026-03-20T06:00:00Z",
  "fsi_isolationenabled": true,
  "fsi_totalrulecount": 5,
  "fsi_inboundrulecount": 2,
  "fsi_outboundrulecount": 1,
  "fsi_bothdirectionrulecount": 2,
  "fsi_isolationcompliancestatus": 0,
  "fsi_driftdetected": false,
  "fsi_rulesjson": "[{\"tenantId\":\"a1b2c3d4-e5f6-7890-abcd-ef1234567890\",\"direction\":\"Both\",\"tenantName\":\"Contoso Financial Services\"}]",
  "fsi_collectedby": "Flow 1 — PP Isolation Scanner"
}
```

---

## Table 4: Entra CTA Record

**SchemaName:** `fsi_EntraCTARecord`
**Logical Name:** `fsi_entractarecord`
**Ownership:** OrganizationOwned

Weekly Entra Cross-Tenant Access policy audit snapshots. Each record captures the CTA configuration for one partner tenant at a point in time, enabling drift detection against approved settings.

### Columns

| Column Display | SchemaName | Logical Name | Type | Required | Notes |
|---------------|-----------|-------------|------|----------|-------|
| Record ID | fsi_EntraCTARecordId | fsi_entractarecordid | Uniqueidentifier | Yes | Primary key (auto-generated) |
| Name | fsi_Name | fsi_name | String(200) | Yes | Auto-generated: "CTA — {PartnerDomain} — {SnapshotDate}" |
| Snapshot Date | fsi_SnapshotDate | fsi_snapshotdate | DateTime | Yes | UTC date of snapshot collection |
| Partner Tenant ID | fsi_PartnerTenantId | fsi_partnertenantid | String(100) | Yes | Partner tenant GUID |
| Partner Tenant Domain | fsi_PartnerTenantDomain | fsi_partnertenantdomain | String(200) | No | Partner tenant primary domain |
| B2B Collaboration Inbound | fsi_B2BCollaborationInbound | fsi_b2bcollaborationinbound | Yes/No | Yes | Inbound B2B collaboration enabled |
| B2B Collaboration Outbound | fsi_B2BCollaborationOutbound | fsi_b2bcollaborationoutbound | Yes/No | Yes | Outbound B2B collaboration enabled |
| B2B Direct Connect Inbound | fsi_B2BDirectConnectInbound | fsi_b2bdirectconnectinbound | Yes/No | Yes | Inbound B2B direct connect enabled |
| B2B Direct Connect Outbound | fsi_B2BDirectConnectOutbound | fsi_b2bdirectconnectoutbound | Yes/No | Yes | Outbound B2B direct connect enabled |
| Inbound Trust Settings | fsi_InboundTrustSettings | fsi_inboundtrustsettings | Memo(10000) | No | JSON — MFA and device compliance trust |
| Outbound Trust Settings | fsi_OutboundTrustSettings | fsi_outboundtrustsettings | Memo(10000) | No | JSON — outbound trust configuration |
| Compliance Status | fsi_CTAComplianceStatus | fsi_ctacompliancestatus | Choice | Yes | See option set below |
| Drift Detected | fsi_DriftDetected | fsi_driftdetected | Yes/No | Yes | Policy differs from prior snapshot |
| Drift Details | fsi_DriftDetails | fsi_driftdetails | Memo(10000) | No | JSON diff of changed policies |
| Policy JSON | fsi_PolicyJson | fsi_policyjson | Memo(100000) | No | Full CTA policy snapshot (JSON) |
| Collected By | fsi_CollectedBy | fsi_collectedby | String(200) | Yes | Script or flow that collected the snapshot |
| Created On | createdon | createdon | DateTime | Auto | Record creation timestamp |

### Sample Data

```json
{
  "fsi_name": "CTA — contoso.com — 2026-03-20",
  "fsi_snapshotdate": "2026-03-20T06:00:00Z",
  "fsi_partnertenantid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "fsi_partnertenantdomain": "contoso.com",
  "fsi_b2bcollaborationinbound": true,
  "fsi_b2bcollaborationoutbound": false,
  "fsi_b2bdirectconnectinbound": false,
  "fsi_b2bdirectconnectoutbound": false,
  "fsi_inboundtrustsettings": "{\"isMfaAccepted\":true,\"isCompliantDeviceAccepted\":true,\"isHybridAzureADJoinedDeviceAccepted\":false}",
  "fsi_outboundtrustsettings": "{\"isMfaAccepted\":false,\"isCompliantDeviceAccepted\":false,\"isHybridAzureADJoinedDeviceAccepted\":false}",
  "fsi_ctacompliancestatus": 0,
  "fsi_driftdetected": false,
  "fsi_collectedby": "Flow 3 — Entra CTA Scanner"
}
```

---

## Table 5: Cross-Tenant Compliance Event

**SchemaName:** `fsi_CrossTenantComplianceEvent`
**Logical Name:** `fsi_crosstenantcomplianceevent`
**Ownership:** OrganizationOwned

Immutable compliance event log for all cross-tenant governance actions. Designed for Dataverse Long-Term Retention (LTR) to support 7-year SEC 17a-3/4 and FINRA 4511 record-keeping requirements.

> **Important:** This table should be configured with Dataverse LTR after deployment. Records should not be modified or deleted once created. The table is append-only by design.

### Columns

| Column Display | SchemaName | Logical Name | Type | Required | Notes |
|---------------|-----------|-------------|------|----------|-------|
| Event ID | fsi_CrossTenantComplianceEventId | fsi_crosstenantcomplianceeventid | Uniqueidentifier | Yes | Primary key (auto-generated) |
| Name | fsi_Name | fsi_name | String(200) | Yes | Auto-generated event title |
| Event Type | fsi_EventType | fsi_eventtype | Choice | Yes | See option set below |
| Event Timestamp | fsi_EventTimestamp | fsi_eventtimestamp | DateTime | Yes | UTC event timestamp |
| Actor UPN | fsi_ActorUPN | fsi_actorupn | String(320) | No | UPN of user or service that triggered the event |
| Target Tenant ID | fsi_TargetTenantId | fsi_targettenantid | String(100) | No | Target external tenant GUID |
| Target Tenant Domain | fsi_TargetTenantDomain | fsi_targettenantdomain | String(200) | No | Target tenant primary domain |
| Description | fsi_Description | fsi_description | Memo(10000) | Yes | Event description |
| Compliance Impact | fsi_ComplianceImpact | fsi_complianceimpact | Choice | Yes | See option set below |
| Related Finding ID | fsi_RelatedFindingId | fsi_relatedfindingid | String(36) | No | GUID of related `fsi_externalsharefinding` record |
| Evidence JSON | fsi_EvidenceJson | fsi_evidencejson | Memo(100000) | No | Immutable evidence payload (JSON) |
| Correlation ID | fsi_CorrelationId | fsi_correlationid | String(36) | No | Correlation ID for tracing related events |
| Created On | createdon | createdon | DateTime | Auto | Record creation timestamp |

### Sample Data

```json
{
  "fsi_name": "Tenant Approved — Contoso Financial Services",
  "fsi_eventtype": 0,
  "fsi_eventtimestamp": "2026-01-15T14:30:00Z",
  "fsi_actorupn": "governance.admin@yourorg.onmicrosoft.com",
  "fsi_targettenantid": "a1b2c3d4-e5f6-7890-abcd-ef1234567890",
  "fsi_targettenantdomain": "contoso.com",
  "fsi_description": "External tenant Contoso Financial Services approved for cross-tenant collaboration. Scope: DEV environment, Innovation-CoPilot and Data-Analytics-Bot agents.",
  "fsi_complianceimpact": 0,
  "fsi_evidencejson": "{\"approvalType\":\"DualApproval\",\"securityAttestationCompleted\":true,\"approvedScope\":\"DEV only\",\"riskTier\":\"High\"}",
  "fsi_correlationid": "corr-11111-aaaa-2222-bbbb-333333333333"
}
```

---

## Option Sets

### fsi_ctsg_approvalstatus

Used by: `fsi_approvedexternaltenant.fsi_approvalstatus`

| Value | Label | Description |
|-------|-------|-------------|
| 0 | Pending | Onboarding request submitted; awaiting approvals |
| 1 | Approved | Both approvals received; access authorized |
| 2 | Expired | Approval request timed out (10 business days) |
| 3 | Suspended | Temporarily suspended pending review |
| 4 | Revoked | Access permanently removed |

### fsi_ctsg_relationshiptype

Used by: `fsi_approvedexternaltenant.fsi_relationshiptype`

| Value | Label | Description |
|-------|-------|-------------|
| 0 | Subsidiary | Wholly or majority-owned subsidiary |
| 1 | Joint Venture | Joint venture partner |
| 2 | Vendor | Third-party vendor or service provider |
| 3 | Client | Client or customer organization |
| 4 | Regulatory Body | Regulatory authority or examiner |
| 5 | Other | Other approved relationship type |

### fsi_ctsg_risktier

Used by: `fsi_approvedexternaltenant.fsi_risktier`

| Value | Label | Description |
|-------|-------|-------------|
| 0 | Critical | Unrestricted data flow; highest scrutiny; monthly review |
| 1 | High | Sensitive data exchange; quarterly review |
| 2 | Medium | Limited data exchange; semi-annual review |
| 3 | Low | Read-only or metadata access; annual review |

### fsi_ctsg_ppisolationdirection

Used by: `fsi_approvedexternaltenant.fsi_ppisolationdirection`

| Value | Label | Description |
|-------|-------|-------------|
| 0 | Inbound | External tenant can access your environments |
| 1 | Outbound | Your users can access external tenant environments |
| 2 | Both | Bidirectional access permitted |

### fsi_ctsg_guestdetectionmethod

Used by: `fsi_externalsharefinding.fsi_guestdetectionmethod`

| Value | Label | Description |
|-------|-------|-------------|
| 0 | EXT# Parsing | Home tenant domain extracted from EXT# UPN format alone |
| 1 | Mail Field | Home tenant domain extracted from mail field alone |
| 2 | CreationType | B2B origin confirmed via `creationType="Invitation"` — domain not independently resolved |
| 3 | Multi-Method Agreed | Two or more methods independently resolved the same domain |
| 4 | Unresolved | All three methods failed; domain could not be determined |

### fsi_ctsg_findingtype

Used by: `fsi_externalsharefinding.fsi_findingtype`

| Value | Label | Description |
|-------|-------|-------------|
| 0 | Unapproved Tenant | Agent shared with tenant not on approved list |
| 1 | Scope Exceeded | Access scope exceeds approved boundaries |
| 2 | Missing Attestation | Security attestation missing or expired |
| 3 | Expired Approval | Tenant approval expired without renewal |
| 4 | Isolation Gap | PP tenant isolation rule missing for approved tenant |
| 5 | CTA Drift | Entra CTA policy differs from approved configuration |
| 6 | Unauthorized Guest | Guest user from unapproved tenant detected |

### fsi_ctsg_governancelayer

Used by: `fsi_externalsharefinding.fsi_governancelayer`

| Value | Label | Description |
|-------|-------|-------------|
| 0 | Power Platform Isolation | PP tenant isolation rules (Flow 1) |
| 1 | Entra CTA | Entra cross-tenant access policies (Flow 2) |
| 2 | Copilot Studio Sharing | Copilot Studio agent sharing settings (Flow 3) |
| 3 | Guest User Audit | Entra ID guest user enumeration (Flow 3) |

### fsi_ctsg_severity

Used by: `fsi_externalsharefinding.fsi_severity`

| Value | Label | Description |
|-------|-------|-------------|
| 0 | Critical | Immediate remediation required |
| 1 | High | Remediation within 24 hours |
| 2 | Medium | Remediation within 7 days |
| 3 | Low | Informational; review at convenience |

### fsi_ctsg_findingstatus

Used by: `fsi_externalsharefinding.fsi_findingstatus`

| Value | Label | Description |
|-------|-------|-------------|
| 0 | Open | Finding detected; not yet addressed |
| 1 | Acknowledged | Finding acknowledged by governance team |
| 2 | Remediated | Finding resolved and verified |
| 3 | Risk Accepted | Finding accepted with documented justification |
| 4 | False Positive | Finding determined to be a false positive |

### fsi_ctsg_remediationstatus

Used by: `fsi_externalsharefinding.fsi_remediationstatus`

| Value | Label | Description |
|-------|-------|-------------|
| 0 | Pending | Remediation not started |
| 1 | In Progress | Remediation underway |
| 2 | Completed | Remediation confirmed complete |
| 3 | Escalated | Escalated to governance committee |

### fsi_ctsg_isolationcompliancestatus

Used by: `fsi_tenantisolationrecord.fsi_isolationcompliancestatus`

| Value | Label | Description |
|-------|-------|-------------|
| 0 | Compliant | Isolation configuration matches approved tenant list |
| 1 | Drift Detected | Configuration differs from approved baseline |
| 2 | Not Configured | Tenant isolation is not enabled |

### fsi_ctsg_ctacompliancestatus

Used by: `fsi_entractarecord.fsi_ctacompliancestatus`

| Value | Label | Description |
|-------|-------|-------------|
| 0 | Compliant | CTA policies match approved tenant list |
| 1 | Drift Detected | CTA policies differ from approved settings |
| 2 | Not Configured | CTA policies not configured for this tenant |
| 3 | Partial | Some policies configured; gaps remain |

### fsi_ctsg_eventtype

Used by: `fsi_crosstenantcomplianceevent.fsi_eventtype`

| Value | Label | Description |
|-------|-------|-------------|
| 0 | Tenant Approved | New external tenant approved for cross-tenant access |
| 1 | Tenant Revoked | External tenant access permanently revoked |
| 2 | Tenant Suspended | External tenant access temporarily suspended |
| 3 | Finding Detected | New sharing violation detected |
| 4 | Finding Remediated | Sharing violation resolved |
| 5 | Isolation Updated | PP tenant isolation rules updated |
| 6 | CTA Updated | Entra CTA policies updated |
| 7 | Annual Review Completed | Annual tenant review completed |
| 8 | Attestation Completed | Security attestation completed |

### fsi_ctsg_complianceimpact

Used by: `fsi_crosstenantcomplianceevent.fsi_complianceimpact`

| Value | Label | Description |
|-------|-------|-------------|
| 0 | High | Material compliance impact; regulatory notification may be required |
| 1 | Medium | Moderate compliance impact; internal escalation recommended |
| 2 | Low | Minor compliance impact; standard tracking |
| 3 | Informational | No direct compliance impact; logged for audit trail |

---

## Alternate Keys

| # | Table | Key Name | Columns | Purpose |
|---|-------|----------|---------|---------|
| 1 | `fsi_approvedexternaltenant` | `fsi_ak_approvedtenant_tenantid` | `fsi_tenantid` | Unique tenant GUID prevents duplicate registrations |
| 2 | `fsi_externalsharefinding` | `fsi_ak_finding_dedup` | `fsi_agentid`, `fsi_externaltenanttenantid`, `fsi_findingtype` | Deduplication — one finding per agent + tenant + type |

---

## Entity Relationships

| Parent Table | Child Table | Relationship Type | Foreign Key | Nullable |
|-------------|-------------|-------------------|-------------|----------|
| `fsi_approvedexternaltenant` | `fsi_externalsharefinding` | 1:N | `fsi_approvedexternaltenantlookup` | Yes |

> **Referential behavior:** The relationship uses **Remove Link** — deleting an approved tenant record clears the lookup on related findings but does not delete the findings themselves. This preserves violation history for audit purposes even after a tenant is removed from the allow list.

> **Note:** Tables 3, 4, and 5 are standalone (no foreign-key relationships). Correlation across tables is performed via `fsi_tenantid` / `fsi_partnertenantid` / `fsi_targettenantid` string matching in Power Automate flows and reporting queries.

---

## Design Decisions

### UserOwned vs. OrganizationOwned

Only `fsi_approvedexternaltenant` is **UserOwned** — this enables Dataverse row-level security so each approved tenant record can be owned by the requesting team's security group. All other tables are **OrganizationOwned** because they contain system-generated audit data that should be visible to all governance team members.

### Custom Choice Fields vs. statecode/statuscode

All tables use custom choice fields (e.g., `fsi_approvalstatus`, `fsi_findingstatus`) instead of Dataverse built-in `statecode`/`statuscode`. This matches the pattern used across the FSI-AgentGov-Solutions repository for cross-table consistency, deployment portability, and simplified Power Automate expressions.

### Immutable Compliance Events

`fsi_crosstenantcomplianceevent` is append-only by design. Security roles should grant only **Create** and **Read** permissions — never **Update** or **Delete**. Configure Dataverse Long-Term Retention (LTR) after deployment to support 7-year SEC 17a-3/4 retention.

---

*Cross-Tenant External Sharing Governance v1.0.0 — FSI Agent Governance Framework*
