# Dataverse Schema Reference

> Auto-generated from `create_ctsg_dataverse_schema.py`. Do not edit manually.

## Tables

| SchemaName | Logical Name | Ownership | Description |
|---|---|---|---|
| fsi_ApprovedExternalTenant | fsi_approvedexternaltenant | UserOwned | Authoritative allow list of approved external tenants and their permitted access scope |
| fsi_ExternalShareFinding | fsi_externalsharefinding | OrganizationOwned | Detected external sharing violations per agent and per connection |
| fsi_TenantIsolationRecord | fsi_tenantisolationrecord | OrganizationOwned | Tenant isolation configuration audit history — one record per daily Flow 1 run |
| fsi_EntraCTARecord | fsi_entractarecord | OrganizationOwned | Entra cross-tenant access settings audit history — one record per weekly Flow 3 run |
| fsi_CrossTenantComplianceEvent | fsi_crosstenantcomplianceevent | OrganizationOwned | Immutable audit log of all cross-tenant governance events — no delete for non-admins |

## Columns

### fsi_ApprovedExternalTenant (`fsi_approvedexternaltenant`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_TenantName | fsi_tenantname | String(200) | Yes | Display name of the external organization |  |
| fsi_TenantId | fsi_tenantid | String(100) | Yes | Entra Tenant ID (GUID) |  |
| fsi_PrimaryDomain | fsi_primarydomain | String(200) | Yes | Primary verified domain |  |
| fsi_RelationshipType | fsi_relationshiptype | Picklist | Yes | Type of relationship with external tenant | `fsi_ctsg_relationshiptype` |
| fsi_ApprovalStatus | fsi_approvalstatus | Picklist | Yes | Governance approval status | `fsi_ctsg_approvalstatus` |
| fsi_ApprovedBy | fsi_approvedby | String(200) | No | UPN of governance committee approver |  |
| fsi_ApprovalDate | fsi_approvaldate | DateTime | No | Date approval was granted |  |
| fsi_BusinessJustification | fsi_businessjustification | Memo(10000) | No | Minimum 100 characters |  |
| fsi_RiskTier | fsi_risktier | Picklist | Yes | Risk tier classification | `fsi_ctsg_risktier` |
| fsi_PermittedAccessScope | fsi_permittedaccessscope | Memo(10000) | Yes | Specific environments, agents, or connectors permitted |  |
| fsi_PPIsolationDirection | fsi_ppisolationdirection | Picklist | No | Power Platform tenant isolation direction | `fsi_ctsg_ppisolationdirection` |
| fsi_EntraB2BCollaboration | fsi_entrab2bcollaboration | Boolean | Yes | Whether Entra B2B collaboration is permitted |  |
| fsi_EntraB2BDirectConnect | fsi_entrab2bdirectconnect | Boolean | Yes | Whether Entra B2B direct connect is permitted |  |
| fsi_AgentSharePermitted | fsi_agentsharepermitted | Boolean | Yes | Whether agent sharing with this tenant is permitted |  |
| fsi_AnnualReviewDue | fsi_annualreviewdue | DateTime | Yes | Next annual review due date |  |
| fsi_LastReviewDate | fsi_lastreviewdate | DateTime | No | Date of most recent annual review |  |
| fsi_RequestingTeam | fsi_requestingteam | String(200) | Yes | Team that requested the external tenant relationship |  |
| fsi_SecurityAttestation | fsi_securityattestation | Boolean | Yes | Whether security attestation has been completed |  |
| fsi_ExpiryNotes | fsi_expirynotes | Memo(5000) | No | Populated when status is Expired |  |
| fsi_Notes | fsi_notes | Memo(10000) | No | Additional notes and comments |  |

### fsi_ExternalShareFinding (`fsi_externalsharefinding`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_AgentId | fsi_agentid | String(100) | No | Power Platform Bot ID (Layer 3 only; null for tenant-level findings) |  |
| fsi_AgentName | fsi_agentname | String(500) | No | Display name from agent registry (Layer 3 only) |  |
| fsi_EnvironmentId | fsi_environmentid | String(100) | No | Power Platform environment ID (Layer 3 only) |  |
| fsi_ExternalTenantTenantId | fsi_externaltenanttenantid | String(100) | Yes | Tenant ID — populated even if not in registry |  |
| fsi_ExternalTenantName | fsi_externaltenantname | String(500) | No | Resolved via API |  |
| fsi_ExternalUserUpn | fsi_externaluserupn | String(500) | No | Layer 3 findings only |  |
| fsi_GuestDetectionMethod | fsi_guestdetectionmethod | Picklist | No | Method used to detect guest user | `fsi_ctsg_guestdetectionmethod` |
| fsi_FindingType | fsi_findingtype | Picklist | Yes | Classification of the external sharing finding | `fsi_ctsg_findingtype` |
| fsi_GovernanceLayer | fsi_governancelayer | Picklist | Yes | Which governance layer detected the finding | `fsi_ctsg_governancelayer` |
| fsi_Severity | fsi_severity | Picklist | Yes | Finding severity level | `fsi_ctsg_severity` |
| fsi_FindingStatus | fsi_findingstatus | Picklist | Yes | Current status of the finding | `fsi_ctsg_findingstatus` |
| fsi_DetectedDate | fsi_detecteddate | DateTime | Yes | When the finding was first detected |  |
| fsi_DetectedBy | fsi_detectedby | String(200) | Yes | Flow name |  |
| fsi_RemediationStatus | fsi_remediationstatus | Picklist | Yes | Current remediation status | `fsi_ctsg_remediationstatus` |
| fsi_RemediationDate | fsi_remediationdate | DateTime | No | When remediation was completed |  |
| fsi_RemediationNotes | fsi_remediationnotes | Memo(10000) | No | Details about remediation actions taken |  |
| fsi_AssignedTo | fsi_assignedto | String(200) | No | UPN of assigned reviewer |  |

### fsi_TenantIsolationRecord (`fsi_tenantisolationrecord`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_AuditDate | fsi_auditdate | DateTime | Yes | Date of the tenant isolation audit |  |
| fsi_IsolationEnabled | fsi_isolationenabled | Boolean | Yes | Whether tenant isolation was enabled at audit time |  |
| fsi_AllowListCount | fsi_allowlistcount | Integer | Yes | Total entries in the tenant isolation allow list |  |
| fsi_ApprovedCount | fsi_approvedcount | Integer | Yes | Entries that match approved external tenants |  |
| fsi_UnapprovedCount | fsi_unapprovedcount | Integer | Yes | Entries not found in approved external tenants |  |
| fsi_AllowListSnapshot | fsi_allowlistsnapshot | Memo(100000) | Yes | JSON array of allow-list entries |  |
| fsi_ComplianceStatus | fsi_compliancestatus | Picklist | Yes | Isolation compliance assessment result | `fsi_ctsg_isolationcompliancestatus` |
| fsi_FindingsCreated | fsi_findingscreated | Integer | Yes | Number of findings created during this audit run |  |
| fsi_ApiSchemaConfirmed | fsi_apischemaconfirmed | Boolean | Yes | Whether API response matched expected schema |  |

### fsi_EntraCTARecord (`fsi_entractarecord`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_AuditDate | fsi_auditdate | DateTime | Yes | Date of the Entra CTA audit |  |
| fsi_DefaultInboundB2BBlocked | fsi_defaultinboundb2bblocked | Boolean | Yes | Whether default inbound B2B collaboration is blocked |  |
| fsi_DefaultOutboundB2BBlocked | fsi_defaultoutboundb2bblocked | Boolean | Yes | Whether default outbound B2B collaboration is blocked |  |
| fsi_DefaultDirectConnectBlocked | fsi_defaultdirectconnectblocked | Boolean | Yes | Whether default B2B direct connect is blocked |  |
| fsi_PartnerEntryCount | fsi_partnerentrycount | Integer | Yes | Total partner entries in CTA policy |  |
| fsi_ApprovedPartnerCount | fsi_approvedpartnercount | Integer | Yes | Partners matching approved external tenants |  |
| fsi_UnapprovedPartnerCount | fsi_unapprovedpartnercount | Integer | Yes | Partners not found in approved external tenants |  |
| fsi_PartnerSnapshot | fsi_partnersnapshot | Memo(100000) | Yes | JSON array of partner policy entries |  |
| fsi_ComplianceStatus | fsi_compliancestatus | Picklist | Yes | CTA compliance assessment result | `fsi_ctsg_ctacompliancestatus` |
| fsi_FindingsCreated | fsi_findingscreated | Integer | Yes | Number of findings created during this audit run |  |
| fsi_AutomaticUserConsentSettings | fsi_automaticuserconsentsettings | Memo(10000) | No | JSON snapshot of crossTenantAccessPolicyConfiguration automaticUserConsentSettings for this partner — captures inboundAllowed and outboundAllowed consent flags |  |
| fsi_InboundTrust | fsi_inboundtrust | Memo(10000) | No | JSON snapshot of crossTenantAccessPolicyConfiguration inboundTrust settings for this partner — captures isMfaAccepted, isCompliantDeviceAccepted, and isHybridAzureADJoinedDeviceAccepted flags |  |

### fsi_CrossTenantComplianceEvent (`fsi_crosstenantcomplianceevent`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_EventType | fsi_eventtype | Picklist | Yes | Classification of the governance event | `fsi_ctsg_eventtype` |
| fsi_EventTimestamp | fsi_eventtimestamp | DateTime | Yes | When the event occurred |  |
| fsi_TriggeredBy | fsi_triggeredby | String(200) | Yes | Flow name or user UPN |  |
| fsi_ExternalTenantTenantId | fsi_externaltenanttenantid | String(100) | No | Tenant ID of the external tenant involved |  |
| fsi_ExternalTenantName | fsi_externaltenantname | String(500) | No | Display name of the external tenant involved |  |
| fsi_EventDetails | fsi_eventdetails | Memo(10000) | No | JSON payload with event-specific data |  |
| fsi_ComplianceImpact | fsi_complianceimpact | Picklist | Yes | Regulatory compliance impact assessment | `fsi_ctsg_complianceimpact` |
| fsi_FrameworkVersion | fsi_frameworkversion | String(50) | No | FSI-AgentGov framework version tag |  |

## Option Sets

### `fsi_acv_zone`

| Label | Value |
|---|---|
| Unclassified | 0 |
| Zone 1 | 1 |
| Zone 2 | 2 |
| Zone 3 | 3 |

### `fsi_ctsg_relationshiptype`

| Label | Value |
|---|---|
| Subsidiary | 100000000 |
| Partner | 100000001 |
| Vendor | 100000002 |
| Regulator | 100000003 |
| Auditor | 100000004 |
| Other | 100000005 |

### `fsi_ctsg_approvalstatus`

| Label | Value |
|---|---|
| Pending | 100000000 |
| Approved | 100000001 |
| Expired | 100000002 |
| Suspended | 100000003 |
| Revoked | 100000004 |

### `fsi_ctsg_risktier`

| Label | Value |
|---|---|
| Low | 100000000 |
| Medium | 100000001 |
| High | 100000002 |

### `fsi_ctsg_ppisolationdirection`

| Label | Value |
|---|---|
| Inbound | 100000000 |
| Outbound | 100000001 |
| Both | 100000002 |
| None | 100000003 |

### `fsi_ctsg_guestdetectionmethod`

| Label | Value |
|---|---|
| EXT# Parsing | 100000000 |
| Mail Field | 100000001 |
| CreationType | 100000002 |
| Multi-Method Agreed | 100000003 |
| Unresolved | 100000004 |

### `fsi_ctsg_findingtype`

| Label | Value |
|---|---|
| Unapproved Tenant Isolation Exception | 100000000 |
| Unapproved Guest Share | 100000001 |
| Unapproved B2B Access | 100000002 |
| Tenant Isolation Disabled | 100000003 |
| Approved Tenant - Review Required | 100000004 |

### `fsi_ctsg_governancelayer`

| Label | Value |
|---|---|
| Layer 1 (Tenant Isolation) | 100000000 |
| Layer 2 (Entra CTA) | 100000001 |
| Layer 3 (Agent Share) | 100000002 |

### `fsi_ctsg_severity`

| Label | Value |
|---|---|
| Critical | 100000000 |
| High | 100000001 |
| Medium | 100000002 |
| Low | 100000003 |

### `fsi_ctsg_findingstatus`

| Label | Value |
|---|---|
| Open | 100000000 |
| Under Review | 100000001 |
| Remediated | 100000002 |
| Approved Exception | 100000003 |
| False Positive | 100000004 |

### `fsi_ctsg_remediationstatus`

| Label | Value |
|---|---|
| Pending | 100000000 |
| Approved for Auto-Remediation | 100000001 |
| Manually Remediated | 100000002 |
| Deferred | 100000003 |

### `fsi_ctsg_isolationcompliancestatus`

| Label | Value |
|---|---|
| Compliant | 100000000 |
| Non-Compliant - Isolation Disabled | 100000001 |
| Non-Compliant - Unapproved Entries | 100000002 |

### `fsi_ctsg_ctacompliancestatus`

| Label | Value |
|---|---|
| Compliant | 100000000 |
| Non-Compliant - Permissive Defaults | 100000001 |
| Non-Compliant - Unapproved Partners | 100000002 |

### `fsi_ctsg_eventtype`

| Label | Value |
|---|---|
| Tenant Isolation Validated | 100000000 |
| Tenant Isolation Violation | 100000001 |
| External Share Detected | 100000002 |
| External Share Remediated | 100000003 |
| Entra CTA Audited | 100000004 |
| Entra CTA Violation | 100000005 |
| Tenant Onboarding Initiated | 100000006 |
| Tenant Approved | 100000007 |
| Tenant Expired | 100000008 |
| Tenant Suspended | 100000009 |
| Tenant Revoked | 100000010 |
| Annual Review Due | 100000011 |
| Annual Review Overdue | 100000012 |
| Annual Review Completed | 100000013 |
| Remediation Approved | 100000014 |
| Remediation Rejected | 100000015 |
| API Schema Validation Failed | 100000016 |
| Feature Flag Skip | 100000017 |
| Flow Error | 100000018 |
| Duplicate Remediation Skipped | 100000019 |
| Critical Finding Manual Remediation Required | 100000020 |

### `fsi_ctsg_complianceimpact`

| Label | Value |
|---|---|
| None | 100000000 |
| Low | 100000001 |
| Medium | 100000002 |
| High | 100000003 |
| Critical | 100000004 |

## Alternate Keys

| Key Name | Table | Columns |
|---|---|---|
| fsi_TenantIdUniqueKey | fsi_approvedexternaltenant | `fsi_tenantid` |

## Post-Deployment Steps

- Create lookup column `fsi_ApprovedExternalTenantLookup` on `fsi_externalsharefinding` referencing `fsi_approvedexternaltenant`. This relationship is handled as a post-deployment step.
