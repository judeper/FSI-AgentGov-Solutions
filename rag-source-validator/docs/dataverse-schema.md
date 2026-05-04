# Dataverse Schema Reference

> Auto-generated from `create_rsv_dataverse_schema.py`. Do not edit manually.

## Tables

| SchemaName | Logical Name | Description | Ownership | Primary Name Attribute |
|---|---|---|---|---|
| fsi_KnowledgeSource | fsi_knowledgesource | RAG knowledge source registry with hash baselines and validation settings | UserOwned | fsi_sourcename |
| fsi_ValidationResult | fsi_validationresult | Immutable validation history for RAG knowledge sources | OrganizationOwned | fsi_resultname |
| fsi_SourceChange | fsi_sourcechange | Change tracking for RAG knowledge sources with review workflow | UserOwned | fsi_changename |

## Columns

### fsi_KnowledgeSource (`fsi_knowledgesource`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_SourceName | fsi_sourcename | String | Yes | Display name of the knowledge source |  |
| fsi_SourceType | fsi_sourcetype | Picklist | Yes |  | **fsi_RSV_sourcetype**: `1` = SharePoint Document Library, `2` = SharePoint List, `3` = SharePoint Page, `4` = Dataverse Table, `5` = Azure Blob Container, `6` = Azure Blob File, `7` = External API, `8` = Database Query, `9` = Public Website, `10` = OneDrive File or Folder, `11` = Microsoft 365 Copilot Connector External Item, `12` = Azure AI Search Index, `13` = Copilot Studio Uploaded Document |
| fsi_SourceUri | fsi_sourceuri | String | Yes | Full URI of the knowledge source |  |
| fsi_AgentId | fsi_agentid | String | Yes | Power Platform Bot ID referencing this source |  |
| fsi_Description | fsi_description | Memo | No | Detailed description of the knowledge source |  |
| fsi_CurrentHash | fsi_currenthash | String | No | SHA-256 hash of current source content |  |
| fsi_BaselineHash | fsi_baselinehash | String | No | SHA-256 hash captured at baseline |  |
| fsi_Status | fsi_status | Picklist | No |  | **fsi_RSV_sourcestatus**: `1` = Active, `2` = Pending Validation, `3` = Validation Failed, `4` = Stale, `5` = Archived |
| fsi_LastValidated | fsi_lastvalidated | DateTime | No | Timestamp of last successful validation |  |
| fsi_ValidationFrequency | fsi_validationfrequency | Picklist | No |  | **fsi_RSV_validationfrequency**: `1` = Realtime, `2` = Hourly, `3` = Daily, `4` = Weekly, `5` = Monthly |
| fsi_AlertOnChange | fsi_alertonchange | Boolean | No | Send notification when source content changes | `1` = Yes, `0` = No |
| fsi_FreshnessThreshold | fsi_freshnessthreshold | Integer | No | Maximum acceptable age in days before source is considered stale |  |
| fsi_LastModified | fsi_lastmodified | DateTime | No | Timestamp of last detected source modification |  |

### fsi_ValidationResult (`fsi_validationresult`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_ResultName | fsi_resultname | String | Yes | Auto-generated validation result identifier |  |
| fsi_ValidationTime | fsi_validationtime | DateTime | Yes | Timestamp when validation was performed |  |
| fsi_Result | fsi_result | Picklist | Yes |  | **fsi_RSV_validationresult**: `1` = Passed, `2` = Hash Mismatch, `3` = Schema Drift, `4` = Stale Content, `5` = Source Unavailable, `6` = Unexpected Error, `7` = Skipped - Not Implemented, `8` = Skipped - Unsupported Type |
| fsi_PreviousHash | fsi_previoushash | String | No | SHA-256 hash before this validation |  |
| fsi_CurrentHash | fsi_currenthash | String | No | SHA-256 hash at validation time |  |
| fsi_HashChanged | fsi_hashchanged | Boolean | No | Whether source hash changed since last validation | `1` = Yes, `0` = No |
| fsi_ChangeDetails | fsi_changedetails | Memo | No | Human-readable description of detected changes |  |
| fsi_ValidationType | fsi_validationtype | Picklist | No |  | **fsi_RSV_validationtype**: `1` = Scheduled, `2` = On-Demand, `3` = Webhook Triggered, `4` = Baseline Capture |
| fsi_Duration | fsi_duration | Integer | No | Validation duration in milliseconds |  |
| fsi_ErrorDetails | fsi_errordetails | Memo | No | Error stack trace or message when validation fails |  |

### fsi_SourceChange (`fsi_sourcechange`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_ChangeName | fsi_changename | String | Yes | Auto-generated change record identifier |  |
| fsi_ChangeType | fsi_changetype | Picklist | Yes |  | **fsi_RSV_changetype**: `1` = Content Modified, `2` = Schema Changed, `3` = Source Moved, `4` = Source Deleted, `5` = Permissions Changed, `6` = New Content Added |
| fsi_DetectedOn | fsi_detectedon | DateTime | Yes | Timestamp when the change was detected |  |
| fsi_PreviousValue | fsi_previousvalue | Memo | No | Content or metadata value before the change |  |
| fsi_NewValue | fsi_newvalue | Memo | No | Content or metadata value after the change |  |
| fsi_ChangedBy | fsi_changedby | String | No | UPN or identity that made the change |  |
| fsi_Reviewed | fsi_reviewed | Boolean | No | Whether the change has been reviewed | `1` = Yes, `0` = No |
| fsi_ReviewedBy | fsi_reviewedby | String | No | UPN of the reviewer |  |
| fsi_ReviewedOn | fsi_reviewedon | DateTime | No | Timestamp when the change was reviewed |  |
| fsi_Approved | fsi_approved | Boolean | No | Whether the reviewed change was approved | `1` = Yes, `0` = No |

## Option Sets

### RSV Option Sets

#### fsi_RSV_sourcetype

Type of RAG knowledge source

| Value | Label |
|---|---|
| 1 | SharePoint Document Library |
| 2 | SharePoint List |
| 3 | SharePoint Page |
| 4 | Dataverse Table |
| 5 | Azure Blob Container |
| 6 | Azure Blob File |
| 7 | External API |
| 8 | Database Query |
| 9 | Public Website |
| 10 | OneDrive File or Folder |
| 11 | Microsoft 365 Copilot Connector External Item |
| 12 | Azure AI Search Index |
| 13 | Copilot Studio Uploaded Document |

#### fsi_RSV_sourcestatus

Current status of the knowledge source

| Value | Label |
|---|---|
| 1 | Active |
| 2 | Pending Validation |
| 3 | Validation Failed |
| 4 | Stale |
| 5 | Archived |

#### fsi_RSV_validationfrequency

How often the source is validated

| Value | Label |
|---|---|
| 1 | Realtime |
| 2 | Hourly |
| 3 | Daily |
| 4 | Weekly |
| 5 | Monthly |

#### fsi_RSV_validationresult

Outcome of a source validation run

| Value | Label |
|---|---|
| 1 | Passed |
| 2 | Hash Mismatch |
| 3 | Schema Drift |
| 4 | Stale Content |
| 5 | Source Unavailable |
| 6 | Unexpected Error |
| 7 | Skipped - Not Implemented |
| 8 | Skipped - Unsupported Type |

#### fsi_RSV_validationtype

How the validation was triggered

| Value | Label |
|---|---|
| 1 | Scheduled |
| 2 | On-Demand |
| 3 | Webhook Triggered |
| 4 | Baseline Capture |

#### fsi_RSV_changetype

Type of change detected on a knowledge source

| Value | Label |
|---|---|
| 1 | Content Modified |
| 2 | Schema Changed |
| 3 | Source Moved |
| 4 | Source Deleted |
| 5 | Permissions Changed |
| 6 | New Content Added |

## Relationships

| SchemaName | Parent (Referenced) | Child (Referencing) | Lookup Column |
|---|---|---|---|
| fsi_ValidationResult_KnowledgeSource | fsi_knowledgesource | fsi_validationresult | fsi_KnowledgeSourceId |
| fsi_SourceChange_KnowledgeSource | fsi_knowledgesource | fsi_sourcechange | fsi_KnowledgeSourceId |
