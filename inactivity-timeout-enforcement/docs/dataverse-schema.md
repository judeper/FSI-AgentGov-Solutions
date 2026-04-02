# Dataverse Schema Reference

> Auto-generated from `create_ite_dataverse_schema.py`. Do not edit manually.

## Tables

| SchemaName | Logical Name | Description | Primary Name Attribute |
|---|---|---|---|
| fsi_EnvironmentPolicy | fsi_environmentpolicy | Zone policy configuration per environment for inactivity timeout | fsi_policyname |
| fsi_InactivityTimeoutCompliance | fsi_inactivitytimeoutcompliance | Immutable scan results for inactivity timeout compliance | fsi_compliancename |
| fsi_InactivityTimeoutErrorLog | fsi_inactivitytimeouterrorlog | Error audit trail for inactivity timeout scans | fsi_errorname |

## Columns

### fsi_EnvironmentPolicy (`fsi_environmentpolicy`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_PolicyName | fsi_policyname | String | Yes | Unique policy name |  |
| fsi_EnvironmentId | fsi_environmentid | String | Yes | Power Platform environment identifier |  |
| fsi_EnvironmentDisplayName | fsi_environmentdisplayname | String | No | Display name of the environment |  |
| fsi_Zone | fsi_zone | Picklist | Yes | Governance zone classification | **fsi_acv_zone**: `100000000` = Unclassified, `100000001` = Zone 1, `100000002` = Zone 2, `100000003` = Zone 3 |
| fsi_RequiredMaxDuration | fsi_requiredmaxduration | Integer | Yes | Maximum inactivity timeout in minutes |  |
| fsi_IsActive | fsi_isactive | Boolean | Yes | Whether this policy is currently active | `1` = Yes, `0` = No |

### fsi_InactivityTimeoutCompliance (`fsi_inactivitytimeoutcompliance`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_ComplianceName | fsi_compliancename | String | Yes | Unique compliance record identifier |  |
| fsi_EnvironmentId | fsi_environmentid | String | Yes | Power Platform environment identifier |  |
| fsi_EnvironmentName | fsi_environmentname | String | No | Display name of the environment |  |
| fsi_Zone | fsi_zone | Picklist | No | Governance zone classification | **fsi_acv_zone**: `100000000` = Unclassified, `100000001` = Zone 1, `100000002` = Zone 2, `100000003` = Zone 3 |
| fsi_InactivityTimeoutEnabled | fsi_inactivitytimeoutenabled | Boolean | No | Whether inactivity timeout is enabled on the environment | `1` = Yes, `0` = No |
| fsi_TimeoutDuration | fsi_timeoutduration | String | No | Configured timeout duration (ISO 8601 or minutes) |  |
| fsi_RequiredMaxDuration | fsi_requiredmaxduration | Integer | No | Maximum inactivity timeout required by policy in minutes |  |
| fsi_ComplianceStatus | fsi_compliancestatus | Picklist | Yes | Inactivity timeout compliance status | **fsi_ITE_compliancestatus**: `100000000` = Compliant, `100000001` = NonCompliant, `100000002` = Unknown |
| fsi_Notes | fsi_notes | Memo | No | Additional notes or details about the compliance result |  |
| fsi_LastScanDate | fsi_lastscandate | DateTime | No | When this compliance record was last scanned |  |
| fsi_ScanRunId | fsi_scanrunid | String | No | GUID correlating all records in one scan run |  |

### fsi_InactivityTimeoutErrorLog (`fsi_inactivitytimeouterrorlog`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_ErrorName | fsi_errorname | String | Yes | Unique error record identifier |  |
| fsi_EnvironmentId | fsi_environmentid | String | No | Power Platform environment identifier |  |
| fsi_ErrorType | fsi_errortype | Picklist | Yes | Type of error encountered during scan | **fsi_ITE_errortype**: `100000000` = MissingPolicy, `100000001` = Unauthorized, `100000002` = Forbidden, `100000003` = NotFound, `100000004` = Throttled, `100000005` = ParseError, `100000006` = DataverseError |
| fsi_ErrorRaw | fsi_errorraw | Memo | No | Raw error message or stack trace |  |
| fsi_Timestamp | fsi_timestamp | DateTime | Yes | When the error occurred |  |

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

### ITE Option Sets

#### fsi_ITE_compliancestatus

Inactivity timeout compliance status

| Value | Label |
|---|---|
| 100000000 | Compliant |
| 100000001 | NonCompliant |
| 100000002 | Unknown |

#### fsi_ITE_errortype

Type of error encountered during scan

| Value | Label |
|---|---|
| 100000000 | MissingPolicy |
| 100000001 | Unauthorized |
| 100000002 | Forbidden |
| 100000003 | NotFound |
| 100000004 | Throttled |
| 100000005 | ParseError |
| 100000006 | DataverseError |
