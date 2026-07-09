# Dataverse Schema Reference

> Auto-generated from `create_asard_dataverse_schema.py`. Do not edit manually.

## Tables

| SchemaName | Logical Name | Description | Primary Name Attribute |
|---|---|---|---|
| fsi_AgentSharingCompliance | fsi_agentsharingcompliance | Zone-based agent sharing compliance assessment records | fsi_complianceid |
| fsi_ApprovedSecurityGroupPolicy | fsi_approvedsecuritygrouppolicy | Pre-approved security group policies for agent sharing by zone | fsi_policyname |

## Columns

### fsi_AgentSharingCompliance (`fsi_agentsharingcompliance`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_ComplianceId | fsi_complianceid | String | Yes | Unique compliance assessment identifier |  |
| fsi_AgentId | fsi_agentid | String | Yes | Unique identifier of the agent |  |
| fsi_AgentName | fsi_agentname | String | No | Display name of the agent |  |
| fsi_EnvironmentId | fsi_environmentid | String | No | Power Platform environment identifier |  |
| fsi_EnvironmentName | fsi_environmentname | String | No | Display name of the environment |  |
| fsi_Zone | fsi_zone | Picklist | No | Governance zone classification | **fsi_acv_zone**: `100000000` = Unclassified, `100000001` = Zone 1, `100000002` = Zone 2, `100000003` = Zone 3 |
| fsi_ComplianceStatus | fsi_compliancestatus | Picklist | Yes | Compliance status of agent sharing configuration | **fsi_ASARD_compliancestatus**: `100000000` = Compliant, `100000001` = NonCompliant, `100000002` = Exception, `100000003` = Error |
| fsi_CurrentSharingPrincipals | fsi_currentsharingprincipals | Memo | No | JSON array of current sharing principals |  |
| fsi_ApprovedSharingPrincipals | fsi_approvedsharingprincipals | Memo | No | JSON array of approved sharing principals |  |
| fsi_ViolationDetails | fsi_violationdetails | Memo | No | JSON with violation specifics |  |
| fsi_DetectedAt | fsi_detectedat | DateTime | Yes | When the compliance assessment was performed |  |
| fsi_RemediatedAt | fsi_remediatedat | DateTime | No | When the violation was remediated |  |
| fsi_RemediationStatus | fsi_remediationstatus | Picklist | No | Status of sharing remediation action | **fsi_ASARD_remediationstatus**: `100000000` = Pending, `100000001` = Approved, `100000002` = Rejected, `100000003` = Completed, `100000004` = Failed |
| fsi_RemediationApprovedBy | fsi_remediationapprovedby | String | No | UPN of the person who approved remediation |  |
| fsi_RemediationNotes | fsi_remediationnotes | Memo | No | Notes on remediation actions taken |  |
| fsi_ExceptionExpiresAt | fsi_exceptionexpiresat | DateTime | No | When the compliance exception expires |  |
| fsi_ExceptionJustification | fsi_exceptionjustification | Memo | No | Business justification for compliance exception |  |
| fsi_ExceptionApprovedBy | fsi_exceptionapprovedby | String | No | UPN of the person who approved the exception |  |
| fsi_EvidenceJson | fsi_evidencejson | Memo | No | JSON evidence payload for audit trail |  |
| fsi_SharingType | fsi_sharingtype | String | No | Agent sharing type (SpecificUsers, OrgWide, Public) |  |
| fsi_ViolationType | fsi_violationtype | String | No | Type of sharing policy violation detected |  |
| fsi_Severity | fsi_severity | Integer | No | Violation severity code (100000000=Critical, 100000001=High, 100000002=Medium, 100000003=Low, 100000004=Informational) |  |
| fsi_Description | fsi_description | Memo | No | Human-readable description of the violation or compliance assessment |  |
| fsi_ScanRunId | fsi_scanrunid | String | No | Unique identifier for the scan run that produced this record |  |
| fsi_SharedGroupIds | fsi_sharedgroupids | Memo | No | JSON array of security group IDs the agent is shared with |  |
| fsi_RegulatoryContext | fsi_regulatorycontext | String | No | Applicable regulatory context for this compliance record |  |

### fsi_ApprovedSecurityGroupPolicy (`fsi_approvedsecuritygrouppolicy`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_PolicyName | fsi_policyname | String | Yes | Approved security group policy name |  |
| fsi_Zone | fsi_zone | Picklist | Yes | Governance zone this policy applies to | **fsi_acv_zone**: `100000000` = Unclassified, `100000001` = Zone 1, `100000002` = Zone 2, `100000003` = Zone 3 |
| fsi_SecurityGroupId | fsi_securitygroupid | String | Yes | Entra ID object ID of the approved security group |  |
| fsi_SecurityGroupName | fsi_securitygroupname | String | No | Display name of the approved security group |  |
| fsi_ApprovedBy | fsi_approvedby | String | No | UPN of the person who approved this policy |  |
| fsi_ApprovedAt | fsi_approvedat | DateTime | No | When this policy was approved |  |
| fsi_IsActive | fsi_isactive | Boolean | Yes | Whether this approved security group policy is currently active | `1` = Yes, `0` = No |
| fsi_SecurityEnabled | fsi_securityenabled | Boolean | Yes | Whether the Entra group has securityEnabled=true at admission time. Groups with securityEnabled=false are rejected. | `1` = Yes, `0` = No |
| fsi_MailEnabled | fsi_mailenabled | Boolean | Yes | Whether the Entra group has mailEnabled at admission time. Mail-enabled distribution groups are rejected. | `1` = Yes, `0` = No |
| fsi_GroupTypes | fsi_grouptypes | String | No | Comma-separated Entra groupTypes values at admission (e.g. DynamicMembership, Unified) |  |
| fsi_PolicyNotes | fsi_policynotes | Memo | No | Additional notes or context for this policy |  |

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

### ASARD Option Sets

#### fsi_ASARD_compliancestatus

Compliance status of agent sharing configuration

| Value | Label |
|---|---|
| 100000000 | Compliant |
| 100000001 | NonCompliant |
| 100000002 | Exception |
| 100000003 | Error |

#### fsi_ASARD_remediationstatus

Status of sharing remediation action

| Value | Label |
|---|---|
| 100000000 | Pending |
| 100000001 | Approved |
| 100000002 | Rejected |
| 100000003 | Completed |
| 100000004 | Failed |
