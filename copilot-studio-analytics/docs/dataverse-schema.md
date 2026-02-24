# Dataverse Schema Reference

> Auto-generated from `create_csa_dataverse_schema.py`. Do not edit manually.

## Tables

| SchemaName | Logical Name | Description | Primary Name Attribute |
|---|---|---|---|
| fsi_CSASyncWatermark | fsi_csasyncwatermark | Tracks incremental sync state between Dataverse sessions and Application Insights | fsi_environmenturl |

## Columns

### fsi_CSASyncWatermark (`fsi_csasyncwatermark`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_EnvironmentUrl | fsi_environmenturl | String | Yes | Dataverse environment URL for this sync watermark |  |
| fsi_LastSyncTimestamp | fsi_lastsynctimestamp | DateTime | Yes | Timestamp of the last successful sync operation |  |
| fsi_RecordsSynced | fsi_recordssynced | Integer | No | Number of records synced in the last operation |  |
| fsi_SyncStatus | fsi_syncstatus | Picklist | Yes | Current status of the sync operation | **fsi_CSA_syncstatus**: `100000000` = Success, `100000001` = Failed, `100000002` = InProgress, `100000003` = Warning |
| fsi_SyncTier | fsi_synctier | Picklist | Yes | Sync tier level for this watermark entry | **fsi_CSA_synctier**: `100000000` = Tier1, `100000001` = Tier2 |
| fsi_ErrorMessage | fsi_errormessage | Memo | No | Error details for failed sync operations |  |

## Option Sets

### CSA Option Sets

#### fsi_CSA_syncstatus

Status of the Dataverse-to-App Insights sync operation

| Value | Label |
|---|---|
| 100000000 | Success |
| 100000001 | Failed |
| 100000002 | InProgress |
| 100000003 | Warning |

#### fsi_CSA_synctier

Sync tier level for the CSA pipeline

| Value | Label |
|---|---|
| 100000000 | Tier1 |
| 100000001 | Tier2 |
