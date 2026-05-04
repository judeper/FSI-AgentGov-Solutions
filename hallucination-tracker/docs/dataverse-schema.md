# Dataverse Schema Reference

> Auto-generated from `create_ht_dataverse_schema.py`. Do not edit manually.

## Tables

| SchemaName | Logical Name | Description | Primary Name Attribute |
|---|---|---|---|
| fsi_HallucinationReport | fsi_hallucinationreport | Tracks hallucination reports for AI agent responses including category, severity, and remediation status | fsi_reportname |

## Columns

### fsi_HallucinationReport (`fsi_hallucinationreport`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_reportname | fsi_reportname | String | Yes | Unique hallucination report identifier |  |
| fsi_Category | fsi_category | Picklist | Yes | Category of hallucination reported | **fsi_HT_category**: `100000000` = FactualError, `100000001` = FabricatedData, `100000002` = CitationMissing, `100000003` = OutdatedInfo, `100000004` = ConfidenceOverstatement |
| fsi_Severity | fsi_severity | Picklist | Yes | Severity level of the hallucination | **fsi_HT_severity**: `100000000` = Low, `100000001` = Medium, `100000002` = High, `100000003` = Critical |
| fsi_AgentId | fsi_agentid | String | No | Unique identifier of the agent that produced the hallucination |  |
| fsi_AgentName | fsi_agentname | String | No | Display name of the agent |  |
| fsi_Description | fsi_description | Memo | No | Detailed description of the hallucination |  |
| fsi_Source | fsi_source | Picklist | No | Source of the hallucination report | **fsi_HT_source**: `100000000` = User, `100000001` = Supervisor, `100000002` = Automated, `100000003` = Customer, `100000004` = Microsoft365Copilot |
| fsi_ReportedBy | fsi_reportedby | String | No | Name or identifier of the person who submitted the report |  |
| fsi_ReportedAt | fsi_reportedat | DateTime | No | Timestamp when the hallucination was reported |  |
| fsi_ConversationId | fsi_conversationid | String | No | Identifier of the conversation where the hallucination occurred |  |
| fsi_UserQuery | fsi_userquery | Memo | No | The user query or prompt that triggered the hallucination |  |
| fsi_TopicName | fsi_topicname | String | No | Copilot Studio topic or Microsoft 365 Copilot app area associated with the feedback |  |
| fsi_TopicId | fsi_topicid | String | No | Topic, session, or app-scoped identifier used for feedback clustering |  |
| fsi_ChannelId | fsi_channelid | String | No | Channel where the feedback-producing interaction occurred |  |
| fsi_FeedbackComment | fsi_feedbackcomment | Memo | No | User, supervisor, or evaluator comment associated with the hallucination report |  |
| fsi_GroundednessDetected | fsi_groundednessdetected | Boolean | No | Whether an automated groundedness check flagged content as ungrounded | `1` = Yes, `0` = No |
| fsi_AgentResponse | fsi_agentresponse | Memo | No | The agent response containing the hallucination |  |
| fsi_CorrectAnswer | fsi_correctanswer | Memo | No | The correct or expected answer for comparison |  |
| fsi_IsResolved | fsi_isresolved | Boolean | No | Whether this hallucination report has been resolved | `1` = Yes, `0` = No |
| fsi_ResolvedBy | fsi_resolvedby | String | No | Name or identifier of the person who resolved the report |  |
| fsi_ResolvedAt | fsi_resolvedat | DateTime | No | Timestamp when the hallucination report was resolved |  |
| fsi_RemediationNotes | fsi_remediationnotes | Memo | No | Notes on actions taken to remediate the hallucination |  |

## Option Sets

### HT Option Sets

#### fsi_HT_category

Category of hallucination reported

| Value | Label |
|---|---|
| 100000000 | FactualError |
| 100000001 | FabricatedData |
| 100000002 | CitationMissing |
| 100000003 | OutdatedInfo |
| 100000004 | ConfidenceOverstatement |

#### fsi_HT_severity

Severity level of the hallucination

| Value | Label |
|---|---|
| 100000000 | Low |
| 100000001 | Medium |
| 100000002 | High |
| 100000003 | Critical |

#### fsi_HT_source

Source of the hallucination report

| Value | Label |
|---|---|
| 100000000 | User |
| 100000001 | Supervisor |
| 100000002 | Automated |
| 100000003 | Customer |
| 100000004 | Microsoft365Copilot |
