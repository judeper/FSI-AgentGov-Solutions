# Dataverse Schema Reference

> Auto-generated from `create_mcm_dataverse_schema.py`. Do not edit manually.

## Tables

| SchemaName | Logical Name | Description | Primary Name Attribute |
|---|---|---|---|
| fsi_MessageCenterLog | fsi_messagecenterlog | M365 Message Center post tracking with agent impact assessments | fsi_messagecenterid |

## Alternate Keys

| Key Name | Table | Key Attributes | Purpose |
|---|---|---|---|
| fsi_MessageCenterIdKey | fsi_messagecenterlog | `fsi_messagecenterid` | Enables idempotent upsert via `PATCH .../fsi_messagecenterlogs(fsi_messagecenterid='MCxxxxx')` |

## Columns

### fsi_MessageCenterLog (`fsi_messagecenterlog`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_MessageCenterId | fsi_messagecenterid | String | Yes | The MC post ID from M365 Message Center |  |
| fsi_Title | fsi_title | String | No | Title of the Message Center post |  |
| fsi_Category | fsi_category | Picklist | No | Category of the Message Center post | **fsi_MCM_messagecategory**: `100000000` = Feature, `100000001` = Admin, `100000002` = Security |
| fsi_Severity | fsi_severity | Picklist | No | Severity level of the Message Center post | **fsi_MCM_messageseverity**: `100000000` = High, `100000001` = Normal, `100000002` = Critical |
| fsi_Services | fsi_services | String | No | Comma-separated list of affected services |  |
| fsi_StartDateTime | fsi_startdatetime | DateTime | No | Start date and time of the message |  |
| fsi_ActionRequiredByDateTime | fsi_actionrequiredbydatetime | DateTime | No | Deadline for required action |  |
| fsi_LastModifiedDateTime | fsi_lastmodifieddatetime | DateTime | No | When the Message Center post was last modified |  |
| fsi_EndDateTime | fsi_enddatetime | DateTime | No | End date and time of the message |  |
| fsi_IsMajorChange | fsi_ismajorchange | Boolean | No | Whether the post represents a major change | `1` = Yes, `0` = No |
| fsi_Body | fsi_body | Memo | No | Full message body of the Message Center post |  |
| fsi_AssessmentStatus | fsi_assessmentstatus | Picklist | No | Current assessment status for agent impact | **fsi_MCM_assessmentstatus**: `100000000` = NotAssessed, `100000001` = Reviewed, `100000002` = ImpactsAgents, `100000003` = NoImpact |
| fsi_Assessment | fsi_assessment | Memo | No | Analyst notes on agent impact assessment |  |
| fsi_ImpactsAgents | fsi_impactsagents | Boolean | No | Whether this change impacts AI agents | `1` = Yes, `0` = No |
| fsi_AssessedBy | fsi_assessedby | String | No | UPN of the analyst who assessed the post |  |
| fsi_AssessedDate | fsi_assesseddate | DateTime | No | When the assessment was completed |  |
| fsi_ActionsTaken | fsi_actionstaken | Memo | No | Record of actions taken in response to the post |  |
| fsi_NotifiedOn | fsi_notifiedon | DateTime | No | When notification was sent for this post |  |
| fsi_Tags | fsi_tags | String | No | Comma-separated tags for categorization |  |
| fsi_HasAttachments | fsi_hasattachments | Boolean | No | Whether the Message Center post has attachments | `1` = Yes, `0` = No |

## Option Sets

### MCM Option Sets

#### fsi_MCM_messagecategory

Category of the Message Center post

| Value | Label |
|---|---|
| 100000000 | Feature |
| 100000001 | Admin |
| 100000002 | Security |

#### fsi_MCM_messageseverity

Severity level of the Message Center post

| Value | Label |
|---|---|
| 100000000 | High |
| 100000001 | Normal |
| 100000002 | Critical |

#### fsi_MCM_assessmentstatus

Assessment status of a Message Center post for agent impact

| Value | Label |
|---|---|
| 100000000 | NotAssessed |
| 100000001 | Reviewed |
| 100000002 | ImpactsAgents |
| 100000003 | NoImpact |
