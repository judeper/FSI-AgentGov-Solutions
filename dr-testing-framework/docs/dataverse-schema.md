# Dataverse Schema Reference

> Auto-generated from `create_drt_dataverse_schema.py`. Do not edit manually.

This schema supports DR validation evidence retention helpful for FFIEC BCP, SEC 17a-4, OCC Heightened Standards, and FINRA Rule 4370. It records validation evidence, not platform backup or failover execution.

## Tables

| SchemaName | Logical Name | Description | Primary Name Attribute |
|---|---|---|---|
| fsi_DRTestResult | fsi_drtestresult | Disaster recovery validation records with probe-duration metrics and validation results | fsi_name |

## Columns

### fsi_DRTestResult (`fsi_drtestresult`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String | Yes | Unique identifier for the DR test result |  |
| fsi_TestType | fsi_testtype | String | Yes | Type of DR validation executed: AgentReadinessCheck, EnvironmentReachabilityCheck, DataverseAccessCheck, FullValidation |  |
| fsi_ExecutedOn | fsi_executedon | DateTime | Yes | UTC timestamp when the DR test was executed |  |
| fsi_ActualRTO | fsi_actualrto | Decimal | Yes | v2.0.1: stores ProbeDurationHours, the wall-clock duration of read-only validation checks. Not regulator-grade RTO. |  |
| fsi_TargetRTO | fsi_targetrto | Integer | Yes | v2.0.1: stores ProbeDurationTargetHours, the validation budget in hours. Not regulator-grade RTO. |  |
| fsi_RTOMet | fsi_rtomet | Boolean | Yes | Whether the validation probe completed within the configured probe budget | `1` = Yes, `0` = No |
| fsi_Status | fsi_status | Picklist | Yes | Overall pass/fail result of the DR test | **fsi_drt_teststatus**: `1` = Pass, `2` = Fail |
| fsi_ValidationChecks | fsi_validationchecks | Memo | No | JSON array of individual validation check results from the DR test execution |  |
| fsi_CorrelationId | fsi_correlationid | String | No | Short hex correlation ID linking this result to the audit log file on disk |  |

## Option Sets

### fsi_drt_teststatus

Pass/Fail outcome of a disaster recovery validation

| Value | Label |
|---|---|
| 1 | Pass |
| 2 | Fail |
