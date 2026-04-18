# Dataverse Schema Reference

> Auto-generated from `create_drt_dataverse_schema.py`. Do not edit manually.

This schema supports DR validation evidence retention helpful for FFIEC BCP, SEC 17a-4, OCC Heightened Standards, and FINRA Rule 4370. (Note: OCC Bulletin 2011-12 covers model risk, not business continuity — DR mappings here are to FFIEC BCP and OCC Heightened Standards.)

## Tables

| SchemaName | Logical Name | Description | Primary Name Attribute |
|---|---|---|---|
| fsi_DRTestResult | fsi_drtestresult | Disaster recovery test execution records with RTO measurements and validation results | fsi_name |

## Columns

### fsi_DRTestResult (`fsi_drtestresult`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String | Yes | Unique identifier for the DR test result |  |
| fsi_TestType | fsi_testtype | String | Yes | Type of DR test executed: AgentRestore, EnvironmentFailover, DataRecovery, FullDR |  |
| fsi_ExecutedOn | fsi_executedon | DateTime | Yes | UTC timestamp when the DR test was executed |  |
| fsi_ActualRTO | fsi_actualrto | Decimal | Yes | **v2.0.0:** stores `ProbeDurationHours` — wall-clock duration of the read-only validation. NOT regulator-grade RTO of the underlying recovery operation. Column name preserved for v1.x compatibility. |
| fsi_TargetRTO | fsi_targetrto | Integer | Yes | Target recovery time objective in hours |  |
| fsi_RTOMet | fsi_rtomet | Boolean | Yes | Whether the actual RTO met the target RTO | `1` = Yes, `0` = No |
| fsi_Status | fsi_status | Picklist | Yes | Overall pass/fail result of the DR test | **fsi_drt_teststatus**: `1` = Pass, `2` = Fail |
| fsi_ValidationChecks | fsi_validationchecks | Memo | No | JSON array of individual validation check results from the DR test execution |  |
| fsi_CorrelationId | fsi_correlationid | String | No | Short hex correlation ID linking this result to the audit log file on disk |  |

## Option Sets

### fsi_drt_teststatus

Pass/Fail outcome of a disaster recovery test

| Value | Label |
|---|---|
| 1 | Pass |
| 2 | Fail |
