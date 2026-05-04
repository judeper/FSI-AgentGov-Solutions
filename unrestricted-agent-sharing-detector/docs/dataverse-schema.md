# Dataverse Schema Reference

> Auto-generated from `create_uasd_dataverse_schema.py`. Do not edit manually.

## Tables

| SchemaName | Logical Name | Description | Primary Name Attribute |
|---|---|---|---|
| fsi_SharingViolation | fsi_sharingviolation | Detected unrestricted agent sharing violations | fsi_name |
| fsi_SharingException | fsi_sharingexception | Approved exceptions to sharing policy violations | fsi_name |
| fsi_AgentSharingSetting | fsi_agentsharingsetting | Current sharing configuration for each agent | fsi_agentid |
| fsi_ApprovedSecurityGroup | fsi_approvedsecuritygroup | Pre-approved Entra ID security groups for agent sharing | fsi_entraidgroupid |
| fsi_SharingPolicy | fsi_sharingpolicy | Zone-specific agent sharing policy definitions | fsi_name |

## Columns

### fsi_SharingViolation (`fsi_sharingviolation`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String | Yes | Unique violation identifier |  |
| fsi_AgentId | fsi_agentid | String | Yes | Unique identifier of the agent |  |
| fsi_AgentName | fsi_agentname | String | No | Display name of the agent |  |
| fsi_EnvironmentId | fsi_environmentid | String | No | Power Platform environment identifier |  |
| fsi_EnvironmentName | fsi_environmentname | String | No | Display name of the environment |  |
| fsi_ViolationType | fsi_violationtype | Picklist | Yes | Type of sharing violation detected | **fsi_UASD_violationtype**: `100000000` = ORG_WIDE_SHARING, `100000001` = PUBLIC_INTERNET_LINK, `100000002` = UNAPPROVED_GROUP, `100000003` = EXCESSIVE_INDIVIDUAL, `100000004` = CROSS_TENANT_ACCESS, `100000005` = POLICY_VIOLATION |
| fsi_ViolationStatus | fsi_violationstatus | Picklist | Yes | Current status of the violation | **fsi_UASD_violationstatus**: `100000000` = Open, `100000001` = Remediated, `100000002` = Exception Approved, `100000003` = False Positive, `100000004` = Remediation Failed |
| fsi_Severity | fsi_severity | Picklist | Yes | Severity level of the violation | **fsi_UASD_severity**: `100000000` = Critical, `100000001` = High, `100000002` = Medium, `100000003` = Low |
| fsi_Description | fsi_description | Memo | No | Detailed description of the violation |  |
| fsi_PrincipalDetails | fsi_principaldetails | Memo | No | Details of principals involved in the violation |  |
| fsi_EvidenceJson | fsi_evidencejson | Memo | No | JSON evidence payload for the violation |  |
| fsi_DetectedAt | fsi_detectedat | DateTime | Yes | When the violation was detected |  |
| fsi_RemediatedAt | fsi_remediatedat | DateTime | No | When the violation was remediated |  |
| fsi_RemediationResult | fsi_remediationresult | Memo | No | Result details of remediation action |  |
| fsi_ScanRunId | fsi_scanrunid | String | No | GUID correlating all records in one scan run |  |

### fsi_SharingException (`fsi_sharingexception`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String | Yes | Unique exception identifier |  |
| fsi_AgentId | fsi_agentid | String | Yes | Unique identifier of the agent |  |
| fsi_AgentName | fsi_agentname | String | No | Display name of the agent |  |
| fsi_EnvironmentId | fsi_environmentid | String | No | Power Platform environment identifier |  |
| fsi_EnvironmentName | fsi_environmentname | String | No | Display name of the environment |  |
| fsi_ViolationType | fsi_violationtype | Picklist | Yes | Type of sharing violation excepted | **fsi_UASD_violationtype**: `100000000` = ORG_WIDE_SHARING, `100000001` = PUBLIC_INTERNET_LINK, `100000002` = UNAPPROVED_GROUP, `100000003` = EXCESSIVE_INDIVIDUAL, `100000004` = CROSS_TENANT_ACCESS, `100000005` = POLICY_VIOLATION |
| fsi_ExceptionStatus | fsi_exceptionstatus | Picklist | Yes | Current status of the exception request | **fsi_UASD_exceptionstatus**: `100000000` = Pending, `100000001` = Approved, `100000002` = Rejected, `100000003` = Expired |
| fsi_DataClassification | fsi_dataclassification | Picklist | No | Data classification level of affected data | **fsi_UASD_dataclassification**: `100000000` = Public, `100000001` = Internal, `100000002` = Confidential, `100000003` = Restricted |
| fsi_BusinessJustification | fsi_businessjustification | Memo | Yes | Business justification for the exception |  |
| fsi_RequestedBy | fsi_requestedby | String | No | UPN of the person who requested the exception |  |
| fsi_RequestedAt | fsi_requestedat | DateTime | No | When the exception was requested |  |
| fsi_RequestedDuration | fsi_requestedduration | Decimal | Yes | Requested exception duration in days |  |
| fsi_ApprovedBySecurity | fsi_approvedbysecurity | String | No | UPN of security approver |  |
| fsi_ApprovedByDataOwner | fsi_approvedbydataowner | String | No | UPN of data owner approver |  |
| fsi_ApprovedByCompliance | fsi_approvedbycompliance | String | No | UPN of compliance approver |  |
| fsi_ApprovedAt | fsi_approvedat | DateTime | No | When the exception was approved |  |
| fsi_ExpiresAt | fsi_expiresat | DateTime | No | When the exception expires |  |
| fsi_RelatedViolationId | fsi_relatedviolationid | Lookup | No | Optional link to the violation record this exception addresses |  |

### fsi_AgentSharingSetting (`fsi_agentsharingsetting`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_AgentId | fsi_agentid | String | Yes | Unique agent identifier |  |
| fsi_AgentDisplayName | fsi_agentdisplayname | String | No | Display name of the agent |  |
| fsi_EnvironmentId | fsi_environmentid | String | No | Power Platform environment identifier |  |
| fsi_EnvironmentDisplayName | fsi_environmentdisplayname | String | No | Display name of the environment |  |
| fsi_SharingScope | fsi_sharingscope | String | No | Current sharing scope of the agent |  |
| fsi_SecurityGroupsJson | fsi_securitygroupsjson | Memo | No | JSON array of security groups the agent is shared with |  |
| fsi_IndividualSharesJson | fsi_individualsharesjson | Memo | No | JSON array of individual users the agent is shared with |  |
| fsi_PublicLinkEnabled | fsi_publiclinkenabled | Boolean | No | Whether a public internet link is enabled for this agent | `1` = Yes, `0` = No |
| fsi_CrossTenantEnabled | fsi_crosstenantenabled | Boolean | No | Whether cross-tenant access is enabled for this agent | `1` = Yes, `0` = No |
| fsi_LastScannedAt | fsi_lastscannedat | DateTime | No | When this agent was last scanned |  |
| fsi_BreakGlassExclude | fsi_breakglassexclude | Boolean | No | Whether this agent is excluded from scanning via break-glass | `1` = Yes, `0` = No |

### fsi_ApprovedSecurityGroup (`fsi_approvedsecuritygroup`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_EntraIdGroupId | fsi_entraidgroupid | String | Yes | Entra ID object ID of the security group |  |
| fsi_DisplayName | fsi_displayname | String | Yes | Display name of the security group |  |
| fsi_Description | fsi_description | Memo | No | Description of the security group purpose |  |
| fsi_ZoneClassification | fsi_zoneclassification | Picklist | No | Governance zone classification for this group | **fsi_UASD_zoneclassification**: `100000000` = Zone 1 (Personal), `100000001` = Zone 2 (Team), `100000002` = Zone 3 (Enterprise) |
| fsi_IsActive | fsi_isactive | Boolean | Yes | Whether this group approval is currently active | `1` = Yes, `0` = No |
| fsi_ApprovedBy | fsi_approvedby | String | No | UPN of the person who approved this group |  |
| fsi_ApprovedAt | fsi_approvedat | DateTime | No | When this group was approved |  |

### fsi_SharingPolicy (`fsi_sharingpolicy`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String | Yes | Sharing policy name |  |
| fsi_ZoneClassification | fsi_zoneclassification | Picklist | Yes | Governance zone this policy applies to | **fsi_UASD_zoneclassification**: `100000000` = Zone 1 (Personal), `100000001` = Zone 2 (Team), `100000002` = Zone 3 (Enterprise) |
| fsi_MaxIndividualShares | fsi_maxindividualshares | Integer | No | Maximum number of individual user shares allowed |  |
| fsi_AllowOrgWidesharing | fsi_alloworgwidesharing | Boolean | No | Whether organization-wide sharing is allowed | `1` = Yes, `0` = No |
| fsi_AllowPublicLink | fsi_allowpubliclink | Boolean | No | Whether public internet links are allowed | `1` = Yes, `0` = No |
| fsi_AllowCrossTenant | fsi_allowcrosstenant | Boolean | No | Whether cross-tenant sharing is allowed | `1` = Yes, `0` = No |
| fsi_ApprovedGroupsOnly | fsi_approvedgroupsonly | Boolean | No | Whether sharing is restricted to approved security groups only | `1` = Yes, `0` = No |
| fsi_IsActive | fsi_isactive | Boolean | Yes | Whether this policy is currently active | `1` = Yes, `0` = No |
| fsi_CreatedBy | fsi_createdby | String | No | UPN of the person who created this policy |  |
| fsi_CreatedAt | fsi_createdat | DateTime | No | When this policy was created |  |
| fsi_ModifiedAt | fsi_modifiedat | DateTime | No | When this policy was last modified |  |

## Option Sets

### Shared Option Sets

#### fsi_acv_zone

Governance zone classification

| Value | Label |
|---|---|
| 100000000 | Unclassified |
| 100000001 | Zone 1 |
| 100000002 | Zone 2 |
| 100000003 | Zone 3 |

> **⚠️ Important:** `fsi_acv_zone` and `fsi_UASD_zoneclassification` use **incompatible value mappings** for zones. `fsi_acv_zone` starts with Unclassified at 100000000, shifting zone numbers up by one (Zone 1 = 100000001). UASD tables bind exclusively to `fsi_UASD_zoneclassification` (Zone 1 = 100000000). When building flows, always use `fsi_UASD_zoneclassification` values for UASD tables — do **not** substitute `fsi_acv_zone` values from ELM lookups without remapping.

### UASD Option Sets

#### fsi_UASD_violationtype

Type of sharing violation detected

| Value | Label |
|---|---|
| 100000000 | ORG_WIDE_SHARING |
| 100000001 | PUBLIC_INTERNET_LINK |
| 100000002 | UNAPPROVED_GROUP |
| 100000003 | EXCESSIVE_INDIVIDUAL |
| 100000004 | CROSS_TENANT_ACCESS |
| 100000005 | POLICY_VIOLATION |

#### fsi_UASD_violationstatus

Current status of a sharing violation

| Value | Label |
|---|---|
| 100000000 | Open |
| 100000001 | Remediated |
| 100000002 | Exception Approved |
| 100000003 | False Positive |
| 100000004 | Remediation Failed |

#### fsi_UASD_severity

Severity level of sharing violation

| Value | Label |
|---|---|
| 100000000 | Critical |
| 100000001 | High |
| 100000002 | Medium |
| 100000003 | Low |

#### fsi_UASD_exceptionstatus

Status of a sharing exception request

| Value | Label |
|---|---|
| 100000000 | Pending |
| 100000001 | Approved |
| 100000002 | Rejected |
| 100000003 | Expired |

#### fsi_UASD_dataclassification

Data classification level

| Value | Label |
|---|---|
| 100000000 | Public |
| 100000001 | Internal |
| 100000002 | Confidential |
| 100000003 | Restricted |

#### fsi_UASD_zoneclassification

Governance zone classification for sharing policies

| Value | Label |
|---|---|
| 100000000 | Zone 1 (Personal) |
| 100000001 | Zone 2 (Team) |
| 100000002 | Zone 3 (Enterprise) |

## Relationships

| SchemaName | Referenced Entity | Referencing Entity | Lookup Column |
|---|---|---|---|
| fsi_SharingViolation_SharingException | fsi_sharingviolation | fsi_sharingexception | fsi_RelatedViolationId |
