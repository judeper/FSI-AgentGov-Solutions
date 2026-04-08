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
| fsi_AgentId | fsi_agentid | String(100) | Yes | Power Platform Bot ID |  |
| fsi_AgentName | fsi_agentname | String(500) | Yes | Display name from agent registry |  |
| fsi_EnvironmentId | fsi_environmentid | String(100) | Yes | Power Platform environment ID |  |
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
| Subsidiary | 0 |
| Partner | 1 |
| Vendor | 2 |
| Regulator | 3 |
| Auditor | 4 |
| Other | 5 |

### `fsi_ctsg_approvalstatus`

| Label | Value |
|---|---|
| Pending | 0 |
| Approved | 1 |
| Expired | 2 |
| Suspended | 3 |
| Revoked | 4 |

### `fsi_ctsg_risktier`

| Label | Value |
|---|---|
| Low | 0 |
| Medium | 1 |
| High | 2 |

### `fsi_ctsg_ppisolationdirection`

| Label | Value |
|---|---|
| Inbound | 0 |
| Outbound | 1 |
| Both | 2 |
| None | 3 |

### `fsi_ctsg_guestdetectionmethod`

| Label | Value |
|---|---|
| EXT# Parsing | 0 |
| Mail Field | 1 |
| CreationType | 2 |
| Multi-Method Agreed | 3 |
| Unresolved | 4 |

### `fsi_ctsg_findingtype`

| Label | Value |
|---|---|
| Unapproved Tenant Isolation Exception | 0 |
| Unapproved Guest Share | 1 |
| Unapproved B2B Access | 2 |
| Tenant Isolation Disabled | 3 |
| Approved Tenant - Review Required | 4 |

### `fsi_ctsg_governancelayer`

| Label | Value |
|---|---|
| Layer 1 (Tenant Isolation) | 0 |
| Layer 2 (Entra CTA) | 1 |
| Layer 3 (Agent Share) | 2 |

### `fsi_ctsg_severity`

| Label | Value |
|---|---|
| Critical | 0 |
| High | 1 |
| Medium | 2 |
| Low | 3 |

### `fsi_ctsg_findingstatus`

| Label | Value |
|---|---|
| Open | 0 |
| Under Review | 1 |
| Remediated | 2 |
| Approved Exception | 3 |
| False Positive | 4 |

### `fsi_ctsg_remediationstatus`

| Label | Value |
|---|---|
| Pending | 0 |
| Approved for Auto-Remediation | 1 |
| Manually Remediated | 2 |
| Deferred | 3 |

### `fsi_ctsg_isolationcompliancestatus`

| Label | Value |
|---|---|
| Compliant | 0 |
| Non-Compliant - Isolation Disabled | 1 |
| Non-Compliant - Unapproved Entries | 2 |

### `fsi_ctsg_ctacompliancestatus`

| Label | Value |
|---|---|
| Compliant | 0 |
| Non-Compliant - Permissive Defaults | 1 |
| Non-Compliant - Unapproved Partners | 2 |

### `fsi_ctsg_eventtype`

| Label | Value |
|---|---|
| Tenant Isolation Validated | 0 |
| Tenant Isolation Violation | 1 |
| External Share Detected | 2 |
| External Share Remediated | 3 |
| Entra CTA Audited | 4 |
| Entra CTA Violation | 5 |
| Tenant Onboarding Initiated | 6 |
| Tenant Approved | 7 |
| Tenant Expired | 8 |
| Tenant Suspended | 9 |
| Tenant Revoked | 10 |
| Annual Review Due | 11 |
| Annual Review Overdue | 12 |
| Annual Review Completed | 13 |
| Remediation Approved | 14 |
| Remediation Rejected | 15 |
| API Schema Validation Failed | 16 |

### `fsi_ctsg_complianceimpact`

| Label | Value |
|---|---|
| None | 0 |
| Low | 1 |
| Medium | 2 |
| High | 3 |
| Critical | 4 |

## Alternate Keys

| Key Name | Table | Columns |
|---|---|---|
| fsi_TenantIdUniqueKey | fsi_approvedexternaltenant | `fsi_tenantid` |
| fsi_FindingDeduplicationKey | fsi_externalsharefinding | `fsi_agentid`, `fsi_externaltenanttenantid`, `fsi_findingtype` |

## Post-Deployment Steps

- Create lookup column `fsi_ApprovedExternalTenantLookup` on `fsi_externalsharefinding` referencing `fsi_approvedexternaltenant`. This relationship is handled as a post-deployment step.
