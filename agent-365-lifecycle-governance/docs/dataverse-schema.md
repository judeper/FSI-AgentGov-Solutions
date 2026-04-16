# Dataverse Schema Reference

> Auto-generated from `create_alg_dataverse_schema.py`. Do not edit manually.

## Tables

| SchemaName | Logical Name | Description | Primary Name Attribute |
|---|---|---|---|
| fsi_AgentLifecycleRecord | fsi_agentlifecyclerecord | Master lifecycle state for each governed agent | fsi_agentname |
| fsi_SponsorAssignment | fsi_sponsorassignment | Sponsor assignment history for agent lifecycle tracking | fsi_sponsorupn |
| fsi_AccessReview | fsi_accessreview | Access review records for agent lifecycle governance | fsi_name |
| fsi_DeactivationRequest | fsi_deactivationrequest | Deactivation approval requests for agent lifecycle management | fsi_name |
| fsi_LifecycleComplianceEvent | fsi_lifecyclecomplianceevent | Append-only event log for agent lifecycle compliance auditing | fsi_name |

## Columns

### fsi_AgentLifecycleRecord (`fsi_agentlifecyclerecord`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_AgentName | fsi_agentname | String | Yes | Display name from Entra/PPAC |  |
| fsi_AgentId | fsi_agentid | String | Yes | Entra Agent ID or Power Platform Bot ID — alternate key part 1 |  |
| fsi_EnvironmentId | fsi_environmentid | String | Yes | Power Platform environment GUID — alternate key part 2 |  |
| fsi_EntraObjectId | fsi_entraobjectid | String | No | Entra service principal object ID |  |
| fsi_GovernanceZone | fsi_governancezone | Picklist | Yes | Zone 1/2/3 governance classification | **fsi_ALG_governancezone**: `100000000` = Zone 1 (Personal), `100000001` = Zone 2 (Team/Departmental), `100000002` = Zone 3 (Enterprise/Customer-Facing) |
| fsi_LifecycleStage | fsi_lifecyclestage | Picklist | Yes | Current lifecycle stage of the agent | **fsi_ALG_lifecyclestage**: `100000000` = Onboarding, `100000001` = Active, `100000002` = Under Review, `100000003` = Inactive, `100000004` = Pending Deactivation, `100000005` = Deactivated, `100000006` = Deleted |
| fsi_SponsorUpn | fsi_sponsorupn | String | No | Current sponsor user principal name |  |
| fsi_SponsorObjectId | fsi_sponsorobjectid | String | No | Entra Object ID of the current sponsor |  |
| fsi_SponsorActive | fsi_sponsoractive | Boolean | Yes | Whether the current sponsor account is active in Entra | `1` = Yes, `0` = No |
| fsi_SponsorAssignedDate | fsi_sponsorassigneddate | DateTime | No | When the current sponsor was assigned |  |
| fsi_LastActivityDate | fsi_lastactivitydate | DateTime | No | Most recent detected activity date for the agent |  |
| fsi_LastActivitySource | fsi_lastactivitysource | Picklist | No | Source of the last activity signal | **fsi_ALG_lastactivitysource**: `100000000` = SignInLog, `100000001` = PPACModified, `100000002` = Published, `100000003` = Unknown |
| fsi_InactivityDays | fsi_inactivitydays | Integer | No | Number of days since the last detected activity |  |
| fsi_InactivityThreshold | fsi_inactivitythreshold | Integer | Yes | Inactivity threshold in days per zone (Zone 1: 180, Zone 2: 90, Zone 3: 30) |  |
| fsi_AccessReviewStatus | fsi_accessreviewstatus | Picklist | Yes | Current access review cycle status | **fsi_ALG_accessreviewstatus**: `100000000` = Not Started, `100000001` = In Progress, `100000002` = Completed, `100000003` = Overdue |
| fsi_NextReviewDue | fsi_nextreviewdue | DateTime | Yes | Date the next access review is due |  |
| fsi_LastReviewCompleted | fsi_lastreviewcompleted | DateTime | No | Date the last access review was completed |  |
| fsi_ReviewCadence | fsi_reviewcadence | Picklist | Yes | Frequency of access reviews for this agent | **fsi_ALG_reviewcadence**: `100000000` = Annual, `100000001` = Semi-Annual, `100000002` = Quarterly |
| fsi_CaPolicyAssigned | fsi_capolicyassigned | Boolean | Yes | Whether a Conditional Access policy is assigned to this agent | `1` = Yes, `0` = No |
| fsi_DeactivationRequested | fsi_deactivationrequested | Boolean | Yes | Whether a deactivation request is pending for this agent | `1` = Yes, `0` = No |
| fsi_FirstRegistered | fsi_firstregistered | DateTime | Yes | When the agent was first registered in lifecycle governance |  |
| fsi_LastUpdated | fsi_lastupdated | DateTime | Yes | When the lifecycle record was last updated |  |

### fsi_SponsorAssignment (`fsi_sponsorassignment`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_SponsorUpn | fsi_sponsorupn | String | Yes | User principal name of the sponsor |  |
| fsi_SponsorObjectId | fsi_sponsorobjectid | String | Yes | Entra Object ID of the sponsor |  |
| fsi_SponsorDisplayName | fsi_sponsordisplayname | String | Yes | Display name of the sponsor from Entra |  |
| fsi_AssignmentDate | fsi_assignmentdate | DateTime | Yes | When this sponsor assignment was made |  |
| fsi_AssignmentReason | fsi_assignmentreason | Picklist | Yes | Reason for this sponsor assignment | **fsi_ALG_assignmentreason**: `100000000` = Initial Onboarding, `100000001` = Sponsor Departure, `100000002` = Escalation, `100000003` = Manual Reassignment |
| fsi_AssignedBy | fsi_assignedby | String | Yes | Flow name or UPN that performed the assignment |  |
| fsi_EndDate | fsi_enddate | DateTime | No | When this sponsor assignment ended |  |
| fsi_IsCurrent | fsi_iscurrent | Boolean | Yes | Whether this is the current active sponsor assignment | `1` = Yes, `0` = No |
| fsi_AgentLifecycleRecordLookup | fsi_agentlifecyclerecordlookup | Lookup | Yes | Parent agent lifecycle record for this sponsor assignment |  |

### fsi_AccessReview (`fsi_accessreview`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String | Yes | Access review record name |  |
| fsi_EntraReviewId | fsi_entrareviewid | String | No | Entra ID access review definition identifier |  |
| fsi_EntraReviewInstanceId | fsi_entrareviewinstanceid | String | No | Entra ID access review instance identifier |  |
| fsi_ReviewType | fsi_reviewtype | Picklist | Yes | Type of access review (Scheduled, Triggered, Ad Hoc) | **fsi_ALG_reviewtype**: `100000000` = Scheduled, `100000001` = Triggered, `100000002` = Ad Hoc |
| fsi_ZoneCadence | fsi_zonecadence | Picklist | Yes | Review cadence derived from the agent governance zone | **fsi_ALG_reviewcadence**: `100000000` = Annual, `100000001` = Semi-Annual, `100000002` = Quarterly |
| fsi_ReviewStartDate | fsi_reviewstartdate | DateTime | Yes | When the access review period started |  |
| fsi_ReviewDueDate | fsi_reviewduedate | DateTime | Yes | Deadline for completing the access review |  |
| fsi_CertifierUpn | fsi_certifierupn | String | Yes | UPN of the person responsible for certifying the review |  |
| fsi_ReviewStatus | fsi_reviewstatus | Picklist | Yes | Current status of the access review | **fsi_ALG_reviewstatus**: `100000000` = Pending, `100000001` = In Progress, `100000002` = Completed, `100000003` = Overdue, `100000004` = Escalated |
| fsi_CertifierDecision | fsi_certifierdecision | Picklist | No | Decision made by the certifier | **fsi_ALG_certifierdecision**: `100000000` = Approved, `100000001` = Denied, `100000002` = Not Reviewed |
| fsi_DecisionNotes | fsi_decisionnotes | Memo | No | Certifier notes explaining the review decision |  |
| fsi_DecisionDate | fsi_decisiondate | DateTime | No | When the certifier made their decision |  |
| fsi_AccessChangesMade | fsi_accesschangesmade | Memo | No | Description of access changes resulting from the review |  |
| fsi_EscalationTarget | fsi_escalationtarget | String | No | UPN or group the review was escalated to |  |
| fsi_EscalationDate | fsi_escalationdate | DateTime | No | When the review was escalated |  |
| fsi_AgentLifecycleRecordLookup | fsi_agentlifecyclerecordlookup | Lookup | Yes | Parent agent lifecycle record for this access review |  |

### fsi_DeactivationRequest (`fsi_deactivationrequest`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String | Yes | Deactivation request record name |  |
| fsi_TriggerReason | fsi_triggerreason | Picklist | Yes | Reason that triggered the deactivation request | **fsi_ALG_triggerreason**: `100000000` = Inactivity Threshold, `100000001` = Sponsor Departed, `100000002` = Access Review Denied, `100000003` = Manual Request, `100000004` = Access Expiry |
| fsi_InactivityDaysAtTrigger | fsi_inactivitydaysattrigger | Integer | No | Number of inactivity days when the deactivation was triggered |  |
| fsi_RequestedBy | fsi_requestedby | String | Yes | Flow name or UPN that initiated the deactivation request |  |
| fsi_RequestDate | fsi_requestdate | DateTime | Yes | When the deactivation was requested |  |
| fsi_ApprovalStatus | fsi_approvalstatus | Picklist | Yes | Current approval status of the deactivation request | **fsi_ALG_approvalstatus**: `100000000` = Pending, `100000001` = Approved, `100000002` = Rejected, `100000003` = Cancelled |
| fsi_ApproverUpn | fsi_approverupn | String | No | UPN of the person who approved or rejected the request |  |
| fsi_ApprovalDate | fsi_approvaldate | DateTime | No | When the deactivation request was approved or rejected |  |
| fsi_ApprovalNotes | fsi_approvalnotes | Memo | No | Notes from the approver regarding the decision |  |
| fsi_DisableDate | fsi_disabledate | DateTime | No | When the agent was disabled in Entra/Power Platform |  |
| fsi_DeletionHoldUntil | fsi_deletionholduntil | DateTime | No | Date until which deletion is held for recovery purposes |  |
| fsi_DeletionDate | fsi_deletiondate | DateTime | No | When the agent was permanently deleted |  |
| fsi_DeletionConfirmedBy | fsi_deletionconfirmedby | String | No | UPN or flow name that confirmed the deletion |  |
| fsi_AgentLifecycleRecordLookup | fsi_agentlifecyclerecordlookup | Lookup | Yes | Parent agent lifecycle record for this deactivation request |  |

### fsi_LifecycleComplianceEvent (`fsi_lifecyclecomplianceevent`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String | Yes | Compliance event record name |  |
| fsi_AgentId | fsi_agentid | String | Yes | Agent identifier (stored as string for immutability) |  |
| fsi_AgentName | fsi_agentname | String | No | Agent display name at the time of the event |  |
| fsi_EnvironmentId | fsi_environmentid | String | No | Power Platform environment identifier at event time |  |
| fsi_EventType | fsi_eventtype | Picklist | Yes | Type of lifecycle compliance event | **fsi_ALG_eventtype**: `100000000` = Sponsor Assigned, `100000001` = Sponsor Departed, `100000002` = Orphan Detected, `100000003` = Access Review Started, `100000004` = Access Review Completed, `100000005` = Access Review Overdue, `100000006` = Access Review Escalated, `100000007` = Inactivity Detected, `100000008` = Deactivation Requested, `100000009` = Deactivation Approved, `100000010` = Deactivation Rejected, `100000011` = Agent Disabled, `100000012` = Agent Deleted, `100000013` = Zone Assigned, `100000014` = CA Policy Validated |
| fsi_EventDetails | fsi_eventdetails | Memo | No | Detailed description or JSON payload for the event |  |
| fsi_ComplianceImpact | fsi_complianceimpact | Picklist | Yes | Compliance impact level of the event | **fsi_ALG_complianceimpact**: `100000000` = None, `100000001` = Low, `100000002` = Medium, `100000003` = High, `100000004` = Critical |
| fsi_TriggeredBy | fsi_triggeredby | String | Yes | Flow name or UPN that triggered the event |  |
| fsi_Timestamp | fsi_timestamp | DateTime | Yes | When the compliance event occurred |  |
| fsi_RelatedRecordId | fsi_relatedrecordid | String | No | GUID of a related Dataverse record for cross-reference |  |

## Alternate Keys

| SchemaName | Entity | Key Attributes |
|---|---|---|
| fsi_AgentEnvironmentKey | fsi_agentlifecyclerecord | fsi_agentid, fsi_environmentid |

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

> **⚠️ Important:** `fsi_acv_zone` and `fsi_ALG_governancezone` use **incompatible value mappings** for zones. `fsi_acv_zone` starts with Unclassified at 100000000, shifting zone numbers up by one (Zone 1 = 100000001). ALG tables bind exclusively to `fsi_ALG_governancezone` (Zone 1 = 100000000). When building flows, always use `fsi_ALG_governancezone` values for ALG tables — do **not** substitute `fsi_acv_zone` values from ELM lookups without remapping.

### ALG Option Sets

#### fsi_ALG_governancezone

Governance zone classification for lifecycle management

| Value | Label |
|---|---|
| 100000000 | Zone 1 (Personal) |
| 100000001 | Zone 2 (Team/Departmental) |
| 100000002 | Zone 3 (Enterprise/Customer-Facing) |

#### fsi_ALG_lifecyclestage

Current lifecycle stage of the agent

| Value | Label |
|---|---|
| 100000000 | Onboarding |
| 100000001 | Active |
| 100000002 | Under Review |
| 100000003 | Inactive |
| 100000004 | Pending Deactivation |
| 100000005 | Deactivated |
| 100000006 | Deleted |

#### fsi_ALG_lastactivitysource

Source of the most recent agent activity signal

| Value | Label |
|---|---|
| 100000000 | SignInLog |
| 100000001 | PPACModified |
| 100000002 | Published |
| 100000003 | Unknown |

#### fsi_ALG_accessreviewstatus

Current status of the access review cycle

| Value | Label |
|---|---|
| 100000000 | Not Started |
| 100000001 | In Progress |
| 100000002 | Completed |
| 100000003 | Overdue |

#### fsi_ALG_reviewcadence

Frequency of access review cycles

| Value | Label |
|---|---|
| 100000000 | Annual |
| 100000001 | Semi-Annual |
| 100000002 | Quarterly |

#### fsi_ALG_assignmentreason

Reason for sponsor assignment or reassignment

| Value | Label |
|---|---|
| 100000000 | Initial Onboarding |
| 100000001 | Sponsor Departure |
| 100000002 | Escalation |
| 100000003 | Manual Reassignment |

#### fsi_ALG_reviewtype

Type of access review

| Value | Label |
|---|---|
| 100000000 | Scheduled |
| 100000001 | Triggered |
| 100000002 | Ad Hoc |

#### fsi_ALG_reviewstatus

Current status of an access review instance

| Value | Label |
|---|---|
| 100000000 | Pending |
| 100000001 | In Progress |
| 100000002 | Completed |
| 100000003 | Overdue |
| 100000004 | Escalated |

#### fsi_ALG_certifierdecision

Access review certifier decision

| Value | Label |
|---|---|
| 100000000 | Approved |
| 100000001 | Denied |
| 100000002 | Not Reviewed |

#### fsi_ALG_triggerreason

Reason that triggered a deactivation request

| Value | Label |
|---|---|
| 100000000 | Inactivity Threshold |
| 100000001 | Sponsor Departed |
| 100000002 | Access Review Denied |
| 100000003 | Manual Request |
| 100000004 | Access Expiry |

#### fsi_ALG_approvalstatus

Status of a deactivation approval request

| Value | Label |
|---|---|
| 100000000 | Pending |
| 100000001 | Approved |
| 100000002 | Rejected |
| 100000003 | Cancelled |

#### fsi_ALG_eventtype

Type of lifecycle compliance event

| Value | Label |
|---|---|
| 100000000 | Sponsor Assigned |
| 100000001 | Sponsor Departed |
| 100000002 | Orphan Detected |
| 100000003 | Access Review Started |
| 100000004 | Access Review Completed |
| 100000005 | Access Review Overdue |
| 100000006 | Access Review Escalated |
| 100000007 | Inactivity Detected |
| 100000008 | Deactivation Requested |
| 100000009 | Deactivation Approved |
| 100000010 | Deactivation Rejected |
| 100000011 | Agent Disabled |
| 100000012 | Agent Deleted |
| 100000013 | Zone Assigned |
| 100000014 | CA Policy Validated |

#### fsi_ALG_complianceimpact

Compliance impact level of the lifecycle event

| Value | Label |
|---|---|
| 100000000 | None |
| 100000001 | Low |
| 100000002 | Medium |
| 100000003 | High |
| 100000004 | Critical |

## Relationships

| SchemaName | Referenced Entity | Referencing Entity | Lookup Column |
|---|---|---|---|
| fsi_AgentLifecycleRecord_SponsorAssignment | fsi_agentlifecyclerecord | fsi_sponsorassignment | fsi_AgentLifecycleRecordLookup |
| fsi_AgentLifecycleRecord_AccessReview | fsi_agentlifecyclerecord | fsi_accessreview | fsi_AgentLifecycleRecordLookup |
| fsi_AgentLifecycleRecord_DeactivationRequest | fsi_agentlifecyclerecord | fsi_deactivationrequest | fsi_AgentLifecycleRecordLookup |
