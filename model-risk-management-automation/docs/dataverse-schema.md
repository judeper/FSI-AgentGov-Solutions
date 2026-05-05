# Dataverse Schema Reference

> Auto-generated from `create_mrm_dataverse_schema.py`. Do not edit manually.

## Tables

| SchemaName | Logical Name | Description | Ownership | Primary Name Attribute |
|---|---|---|---|---|
| fsi_ModelInventory | fsi_modelinventory | Master model risk management record for each AI agent | UserOwned | fsi_modelname |
| fsi_MrmRiskRating | fsi_mrmriskrating | Risk scoring evidence and composite rating for model inventory records | OrganizationOwned | fsi_scoredby |
| fsi_ValidationCycle | fsi_validationcycle | Validation cycle tracking for model inventory records | UserOwned | fsi_cycleid |
| fsi_ValidationFinding | fsi_validationfinding | Individual findings from validation cycles | UserOwned | fsi_findingid |
| fsi_MonitoringRecord | fsi_monitoringrecord | Periodic monitoring results for model inventory records | OrganizationOwned | fsi_monitoringperiod |
| fsi_MrmComplianceEvent | fsi_mrmcomplianceevent | Immutable audit log of MRM compliance events | OrganizationOwned | fsi_eventid |

## Columns

### fsi_ModelInventory (`fsi_modelinventory`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_ModelName | fsi_modelname | String | Yes | Display name from agent registry |  |
| fsi_AgentId | fsi_agentid | String | Yes | Power Platform Bot ID — Alternate Key part 1 |  |
| fsi_EnvironmentId | fsi_environmentid | String | Yes | Power Platform environment GUID — Alternate Key part 2 |  |
| fsi_EntraAgentId | fsi_entraagentid | String | No | From Microsoft Entra Agent ID / Agent 365 registry when available |  |
| fsi_ModelId | fsi_modelid | String | No | Auto Number format MRM-{YYYY}-{00000} — set by Dataverse |  |
| fsi_BusinessFunction | fsi_businessfunction | Memo | No | Declared use case — drives MRM tier assignment |  |
| fsi_MrmTier | fsi_mrmtier | Picklist | Yes |  | **fsi_mrm_mrmtier**: `100000001` = Tier 1 - Full MRM, `100000002` = Tier 2 - Enhanced MRM, `100000003` = Tier 3 - Standard MRM, `100000004` = Tier 4 - Minimal MRM |
| fsi_UnderlyingModel | fsi_underlyingmodel | String | Yes | e.g., GPT-5 Chat, Claude 3.7 |  |
| fsi_ModelProvider | fsi_modelprovider | Picklist | Yes |  | **fsi_mrm_modelprovider**: `100000000` = Microsoft, `100000001` = Anthropic, `100000002` = OpenAI, `100000003` = Custom, `100000004` = Third-Party |
| fsi_DecisionOutputType | fsi_decisionoutputtype | Picklist | Yes |  | **fsi_mrm_decisionoutputtype**: `100000000` = Quantitative Estimate, `100000001` = Decision Support, `100000002` = Information Retrieval, `100000003` = Productivity |
| fsi_Materiality | fsi_materiality | Picklist | Yes |  | **fsi_mrm_materiality**: `100000000` = High, `100000001` = Medium, `100000002` = Low |
| fsi_DataInputs | fsi_datainputs | Memo | No | Input data sources description |  |
| fsi_KnownLimitations | fsi_knownlimitations | Memo | No | Documented limitations per SR 11-7 |  |
| fsi_IntendedUsers | fsi_intendedusers | String | Yes | Target user population |  |
| fsi_GovernanceZone | fsi_governancezone | Picklist | Yes |  | **fsi_acv_zone**: `100000000` = Unclassified, `100000001` = Zone 1, `100000002` = Zone 2, `100000003` = Zone 3 |
| fsi_OwnerUpn | fsi_ownerupn | String | Yes | First Line of Defense |  |
| fsi_OwnerDepartment | fsi_ownerdepartment | String | No |  |  |
| fsi_MrmOfficerUpn | fsi_mrmofficerupn | String | No | Second Line of Defense |  |
| fsi_AuditorUpn | fsi_auditorupn | String | No | Third Line of Defense |  |
| fsi_MrmStatus | fsi_mrmstatus | Picklist | Yes |  | **fsi_mrm_mrmstatus**: `100000000` = Pending Submission, `100000001` = Submitted, `100000002` = Risk Scored, `100000003` = Validation Scheduled, `100000004` = In Validation, `100000005` = Validated, `100000006` = Conditionally Approved, `100000007` = Rejected, `100000008` = Retired |
| fsi_CurrentRiskRating | fsi_currentriskrating | Picklist | Yes |  | **fsi_mrm_riskrating**: `100000000` = Critical, `100000001` = High, `100000002` = Medium, `100000003` = Low |
| fsi_ValidationCadence | fsi_validationcadence | Picklist | Yes |  | **fsi_mrm_validationcadence**: `100000000` = Annual, `100000001` = Biennial, `100000002` = Triennial |
| fsi_LastValidatedDate | fsi_lastvalidateddate | DateTime | No |  |  |
| fsi_NextValidationDue | fsi_nextvalidationdue | DateTime | Yes |  |  |
| fsi_ValidationStatus | fsi_validationstatus | Picklist | Yes |  | **fsi_mrm_validationstatus**: `100000001` = Not Started, `100000002` = Submitted, `100000003` = In Progress, `100000004` = Findings Issued, `100000005` = Remediated, `100000006` = Validated |
| fsi_AgentCardVersion | fsi_agentcardversion | String | No |  |  |
| fsi_AgentCardUrl | fsi_agentcardurl | String | No |  |  |
| fsi_AgentCardFormat | fsi_agentcardformat | Picklist | No |  | **fsi_mrm_agentcardformat**: `100000000` = Word, `100000001` = JSON |
| fsi_MaterialChangeFlag | fsi_materialchangeflag | Boolean | No | Triggers revalidation | `1` = Yes, `0` = No |
| fsi_MaterialChangeDesc | fsi_materialchangedesc | Memo | No |  |  |
| fsi_FirstSubmitted | fsi_firstsubmitted | DateTime | Yes |  |  |
| fsi_LastUpdated | fsi_lastupdated | DateTime | Yes |  |  |

### fsi_MrmRiskRating (`fsi_mrmriskrating`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_ScoredBy | fsi_scoredby | String | Yes | UPN of the person who performed risk scoring |  |
| fsi_ScoringDate | fsi_scoringdate | DateTime | Yes |  |  |
| fsi_IsCurrent | fsi_iscurrent | Boolean | Yes |  | `1` = Yes, `0` = No |
| fsi_Score_DecisionImpact | fsi_score_decisionimpact | Integer | Yes | 1-5 |  |
| fsi_Score_DataSensitivity | fsi_score_datasensitivity | Integer | Yes | 1-5 |  |
| fsi_Score_UserPopulation | fsi_score_userpopulation | Integer | Yes | 1-5 |  |
| fsi_Score_Complexity | fsi_score_complexity | Integer | Yes | 1-5 |  |
| fsi_Score_Explainability | fsi_score_explainability | Integer | Yes | 1-5 |  |
| fsi_Score_RegulatoryExposure | fsi_score_regulatoryexposure | Integer | Yes | 1-5 |  |
| fsi_Score_ChangeFrequency | fsi_score_changefrequency | Integer | Yes | 1-5 |  |
| fsi_TotalScore | fsi_totalscore | Integer | Yes | Sum 7-35 |  |
| fsi_CompositeRating | fsi_compositerating | Picklist | Yes |  | **fsi_mrm_compositerating**: `100000000` = Critical, `100000001` = High, `100000002` = Medium, `100000003` = Low |
| fsi_ScoringRationale | fsi_scoringrationale | Memo | No | Min 100 chars for examiner review |  |
| fsi_ZoneWeightRationale | fsi_zoneweightrationale | Memo | No | Documents dual-zone scoring |  |
| fsi_MrmOfficerOverride | fsi_mrmofficeroverride | Boolean | Yes |  | `1` = Yes, `0` = No |
| fsi_OverrideRationale | fsi_overriderationale | Memo | No |  |  |
| fsi_OverrideApprovedBy | fsi_overrideapprovedby | String | No |  |  |

### fsi_ValidationCycle (`fsi_validationcycle`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_CycleId | fsi_cycleid | String | No | Auto Number |  |
| fsi_ValidationType | fsi_validationtype | Picklist | Yes |  | **fsi_mrm_validationtype**: `100000000` = Initial, `100000001` = Periodic, `100000002` = Material Change, `100000003` = Ad Hoc |
| fsi_MrmTierAtStart | fsi_mrmtieratstart | Picklist | Yes |  | **fsi_mrm_mrmtier**: `100000001` = Tier 1 - Full MRM, `100000002` = Tier 2 - Enhanced MRM, `100000003` = Tier 3 - Standard MRM, `100000004` = Tier 4 - Minimal MRM |
| fsi_RatingAtStart | fsi_ratingatstart | Picklist | Yes |  | **fsi_mrm_riskrating**: `100000000` = Critical, `100000001` = High, `100000002` = Medium, `100000003` = Low |
| fsi_CycleStatus | fsi_cyclestatus | Picklist | Yes |  | **fsi_mrm_cyclestatus**: `100000001` = Not Started, `100000002` = Submitted, `100000003` = In Progress, `100000004` = Findings Issued, `100000005` = Remediated, `100000006` = Validated, `100000007` = Rejected |
| fsi_SubmittedDate | fsi_submitteddate | DateTime | No |  |  |
| fsi_AssignedDate | fsi_assigneddate | DateTime | No |  |  |
| fsi_ValidatorUpn | fsi_validatorupn | String | No |  |  |
| fsi_ValidatorDepartment | fsi_validatordepartment | String | No |  |  |
| fsi_ValidationStartDate | fsi_validationstartdate | DateTime | No |  |  |
| fsi_FindingsIssuedDate | fsi_findingsissueddate | DateTime | No |  |  |
| fsi_RemediationDueDate | fsi_remediationduedate | DateTime | No |  |  |
| fsi_RemediationSubmittedDate | fsi_remediationsubmitteddate | DateTime | No |  |  |
| fsi_ValidationCompletedDate | fsi_validationcompleteddate | DateTime | No |  |  |
| fsi_ValidationOutcome | fsi_validationoutcome | Picklist | No |  | **fsi_mrm_validationoutcome**: `100000000` = Validated - No Findings, `100000001` = Validated - Findings Resolved, `100000002` = Conditionally Approved, `100000003` = Rejected |
| fsi_OutcomeRationale | fsi_outcomerationale | Memo | No |  |  |
| fsi_SlaBreachFlag | fsi_slabreachflag | Boolean | Yes |  | `1` = Yes, `0` = No |
| fsi_SlaBreachDetails | fsi_slabreachdetails | Memo | No |  |  |
| fsi_EscalationTarget | fsi_escalationtarget | String | No |  |  |

### fsi_ValidationFinding (`fsi_validationfinding`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_FindingId | fsi_findingid | String | No | Auto Number |  |
| fsi_Sr117Pillar | fsi_sr117pillar | Picklist | Yes |  | **fsi_mrm_sr117pillar**: `100000000` = Pillar 1 (Development), `100000001` = Pillar 2 (Validation), `100000002` = Pillar 3 (Governance) |
| fsi_FindingCategory | fsi_findingcategory | Picklist | Yes |  | **fsi_mrm_findingcategory**: `100000000` = Conceptual Soundness, `100000001` = Data Integrity, `100000002` = Performance, `100000003` = Bias/Fairness, `100000004` = Documentation, `100000005` = Access Control, `100000006` = Monitoring Gap, `100000007` = Scope Limitation |
| fsi_Severity | fsi_severity | Picklist | Yes |  | **fsi_mrm_severity**: `100000001` = Critical, `100000002` = High, `100000003` = Medium, `100000004` = Low |
| fsi_FindingDescription | fsi_findingdescription | Memo | No | Min 100 chars |  |
| fsi_RequiredRemediation | fsi_requiredremediation | Memo | No | Min 50 chars |  |
| fsi_RemediationStatus | fsi_remediationstatus | Picklist | Yes |  | **fsi_mrm_remediationstatus**: `100000001` = Open, `100000002` = In Progress, `100000003` = Submitted for Review, `100000004` = Closed |
| fsi_OwnerResponse | fsi_ownerresponse | Memo | No |  |  |
| fsi_ValidatorClosureNotes | fsi_validatorclosurenotes | Memo | No |  |  |
| fsi_DueDate | fsi_duedate | DateTime | Yes |  |  |
| fsi_ClosedDate | fsi_closeddate | DateTime | No |  |  |

### fsi_MonitoringRecord (`fsi_monitoringrecord`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_MonitoringPeriod | fsi_monitoringperiod | String | Yes | ISO week e.g. 2026-W12 |  |
| fsi_MonitoringDate | fsi_monitoringdate | DateTime | Yes |  |  |
| fsi_SessionCount | fsi_sessioncount | Integer | No | Total sessions in monitoring period |  |
| fsi_ErrorRate | fsi_errorrate | Decimal | No | Error rate as percentage |  |
| fsi_EscalationRate | fsi_escalationrate | Decimal | No | Escalation rate as percentage |  |
| fsi_AvgConfidence | fsi_avgconfidence | Decimal | No | Average confidence score |  |
| fsi_OutOfScopeTriggers | fsi_outofscopetriggers | Integer | No | Count of out-of-scope trigger events |  |
| fsi_UserSatisfaction | fsi_usersatisfaction | Decimal | No | User satisfaction score |  |
| fsi_DriftSignalDetected | fsi_driftsignaldetected | Boolean | Yes |  | `1` = Yes, `0` = No |
| fsi_DriftSignalDetails | fsi_driftsignaldetails | Memo | No |  |  |
| fsi_ThresholdBreachFlag | fsi_thresholdbreachflag | Boolean | Yes |  | `1` = Yes, `0` = No |
| fsi_RevalidationTriggered | fsi_revalidationtriggered | Boolean | Yes |  | `1` = Yes, `0` = No |
| fsi_DataSource | fsi_datasource | Picklist | Yes |  | **fsi_mrm_datasource**: `100000000` = Copilot Analytics, `100000001` = PPAC Telemetry, `100000002` = Manual Entry, `100000003` = Not Available |
| fsi_MonitoringNotes | fsi_monitoringnotes | Memo | No |  |  |

### fsi_MrmComplianceEvent (`fsi_mrmcomplianceevent`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_EventId | fsi_eventid | String | No | Auto Number |  |
| fsi_EventType | fsi_eventtype | Picklist | Yes |  | **fsi_mrm_eventtype**: `100000000` = Inventory Submitted, `100000001` = Inventory Sync Failed, `100000002` = Risk Scored, `100000003` = Risk Rating Changed, `100000004` = Validation Cycle Opened, `100000005` = Validation Assigned, `100000006` = Findings Issued, `100000007` = Remediation Submitted, `100000008` = Validation Completed, `100000009` = Validation Rejected, `100000010` = Material Change Detected, `100000011` = Agent Card Generated, `100000012` = Agent Card Fallback Used, `100000013` = Monitoring Alert, `100000014` = Revalidation Triggered, `100000015` = Model Retired |
| fsi_EventTimestamp | fsi_eventtimestamp | DateTime | Yes |  |  |
| fsi_TriggeredBy | fsi_triggeredby | String | Yes |  |  |
| fsi_EventDetails | fsi_eventdetails | Memo | No | JSON payload |  |
| fsi_PreviousValue | fsi_previousvalue | String | No |  |  |
| fsi_NewValue | fsi_newvalue | String | No |  |  |
| fsi_Sr117Pillar | fsi_sr117pillar | Picklist | Yes |  | **fsi_mrm_sr117pillar**: `100000000` = Pillar 1 (Development), `100000001` = Pillar 2 (Validation), `100000002` = Pillar 3 (Governance) |
| fsi_ComplianceImpact | fsi_complianceimpact | Picklist | Yes |  | **fsi_mrm_complianceimpact**: `100000000` = None, `100000001` = Low, `100000002` = Medium, `100000003` = High, `100000004` = Critical |

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

### MRM Option Sets

#### fsi_mrm_mrmtier

Model Risk Management tier classification

| Value | Label |
|---|---|
| 100000001 | Tier 1 - Full MRM |
| 100000002 | Tier 2 - Enhanced MRM |
| 100000003 | Tier 3 - Standard MRM |
| 100000004 | Tier 4 - Minimal MRM |

#### fsi_mrm_modelprovider

Underlying model provider

| Value | Label |
|---|---|
| 100000000 | Microsoft |
| 100000001 | Anthropic |
| 100000002 | OpenAI |
| 100000003 | Custom |
| 100000004 | Third-Party |

#### fsi_mrm_decisionoutputtype

Type of decision or output the model produces

| Value | Label |
|---|---|
| 100000000 | Quantitative Estimate |
| 100000001 | Decision Support |
| 100000002 | Information Retrieval |
| 100000003 | Productivity |

#### fsi_mrm_materiality

Materiality level of the model output

| Value | Label |
|---|---|
| 100000000 | High |
| 100000001 | Medium |
| 100000002 | Low |

#### fsi_mrm_mrmstatus

Lifecycle status of the model inventory record

| Value | Label |
|---|---|
| 100000000 | Pending Submission |
| 100000001 | Submitted |
| 100000002 | Risk Scored |
| 100000003 | Validation Scheduled |
| 100000004 | In Validation |
| 100000005 | Validated |
| 100000006 | Conditionally Approved |
| 100000007 | Rejected |
| 100000008 | Retired |

#### fsi_mrm_riskrating

Composite risk rating of the model

| Value | Label |
|---|---|
| 100000000 | Critical |
| 100000001 | High |
| 100000002 | Medium |
| 100000003 | Low |

#### fsi_mrm_validationcadence

Scheduled validation frequency

| Value | Label |
|---|---|
| 100000000 | Annual |
| 100000001 | Biennial |
| 100000002 | Triennial |

#### fsi_mrm_validationstatus

Current validation status of the model

| Value | Label |
|---|---|
| 100000001 | Not Started |
| 100000002 | Submitted |
| 100000003 | In Progress |
| 100000004 | Findings Issued |
| 100000005 | Remediated |
| 100000006 | Validated |

#### fsi_mrm_agentcardformat

Format of the agent model card

| Value | Label |
|---|---|
| 100000000 | Word |
| 100000001 | JSON |

#### fsi_mrm_compositerating

Composite risk rating derived from scoring dimensions

| Value | Label |
|---|---|
| 100000000 | Critical |
| 100000001 | High |
| 100000002 | Medium |
| 100000003 | Low |

#### fsi_mrm_validationtype

Type of validation cycle

| Value | Label |
|---|---|
| 100000000 | Initial |
| 100000001 | Periodic |
| 100000002 | Material Change |
| 100000003 | Ad Hoc |

#### fsi_mrm_cyclestatus

Current status of the validation cycle

| Value | Label |
|---|---|
| 100000001 | Not Started |
| 100000002 | Submitted |
| 100000003 | In Progress |
| 100000004 | Findings Issued |
| 100000005 | Remediated |
| 100000006 | Validated |
| 100000007 | Rejected |

#### fsi_mrm_validationoutcome

Final outcome of the validation cycle

| Value | Label |
|---|---|
| 100000000 | Validated - No Findings |
| 100000001 | Validated - Findings Resolved |
| 100000002 | Conditionally Approved |
| 100000003 | Rejected |

#### fsi_mrm_findingcategory

Category of the validation finding

| Value | Label |
|---|---|
| 100000000 | Conceptual Soundness |
| 100000001 | Data Integrity |
| 100000002 | Performance |
| 100000003 | Bias/Fairness |
| 100000004 | Documentation |
| 100000005 | Access Control |
| 100000006 | Monitoring Gap |
| 100000007 | Scope Limitation |

#### fsi_mrm_severity

Severity level of a validation finding

| Value | Label |
|---|---|
| 100000001 | Critical |
| 100000002 | High |
| 100000003 | Medium |
| 100000004 | Low |

#### fsi_mrm_remediationstatus

Status of finding remediation

| Value | Label |
|---|---|
| 100000001 | Open |
| 100000002 | In Progress |
| 100000003 | Submitted for Review |
| 100000004 | Closed |

#### fsi_mrm_sr117pillar

Fed SR 11-7 model risk management pillar

| Value | Label |
|---|---|
| 100000000 | Pillar 1 (Development) |
| 100000001 | Pillar 2 (Validation) |
| 100000002 | Pillar 3 (Governance) |

#### fsi_mrm_complianceimpact

Compliance impact level of the event

| Value | Label |
|---|---|
| 100000000 | None |
| 100000001 | Low |
| 100000002 | Medium |
| 100000003 | High |
| 100000004 | Critical |

#### fsi_mrm_eventtype

Type of MRM compliance event

| Value | Label |
|---|---|
| 100000000 | Inventory Submitted |
| 100000001 | Inventory Sync Failed |
| 100000002 | Risk Scored |
| 100000003 | Risk Rating Changed |
| 100000004 | Validation Cycle Opened |
| 100000005 | Validation Assigned |
| 100000006 | Findings Issued |
| 100000007 | Remediation Submitted |
| 100000008 | Validation Completed |
| 100000009 | Validation Rejected |
| 100000010 | Material Change Detected |
| 100000011 | Agent Card Generated |
| 100000012 | Agent Card Fallback Used |
| 100000013 | Monitoring Alert |
| 100000014 | Revalidation Triggered |
| 100000015 | Model Retired |

#### fsi_mrm_datasource

Source of monitoring data

| Value | Label |
|---|---|
| 100000000 | Copilot Analytics |
| 100000001 | PPAC Telemetry |
| 100000002 | Manual Entry |
| 100000003 | Not Available |

## Alternate Keys

| Entity | SchemaName | Key Columns |
|---|---|---|
| fsi_modelinventory | fsi_ModelInventoryUniqueKey | fsi_agentid, fsi_environmentid |

## Lookup Relationships

The following lookup columns require post-deployment setup in Power Platform
admin center or via the Dataverse OneToManyRelationshipMetadata API:

| Child Table | Lookup Column | Parent Table |
|---|---|---|
| fsi_mrmriskrating | fsi_ModelInventory_Lookup | fsi_modelinventory |
| fsi_validationcycle | fsi_ModelInventory_Lookup | fsi_modelinventory |
| fsi_validationfinding | fsi_ValidationCycle_Lookup | fsi_validationcycle |
| fsi_validationfinding | fsi_ModelInventory_Lookup | fsi_modelinventory |
| fsi_monitoringrecord | fsi_ModelInventory_Lookup | fsi_modelinventory |
| fsi_mrmcomplianceevent | fsi_ModelInventory_Lookup | fsi_modelinventory |
