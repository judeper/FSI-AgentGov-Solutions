# Dataverse Schema Reference

> Auto-generated from `create_erv_dataverse_schema.py`. Do not edit manually.

This schema records pre-promotion resilience validation evidence for Copilot Studio agents, supporting OCC 2011-12 / Fed SR 11-7 pre-deployment validation, SEC 17a-4 evidence retention, and FINRA 4511 change-control records. It records validation findings, not agent runtime behavior.

## Tables

| SchemaName | Logical Name | Description | Primary Name Attribute |
|---|---|---|---|
| fsi_ERValidationResult | fsi_ervalidationresult | Pre-promotion resilience validation records for Copilot Studio agents, with structural findings and tamper-evident evidence metadata | fsi_name |

## Columns

### fsi_ERValidationResult (`fsi_ervalidationresult`)

| SchemaName | Logical Name | Type | Required | Description | Option Set |
|---|---|---|---|---|---|
| fsi_Name | fsi_name | String | Yes | Unique identifier for the validation run |  |
| fsi_AgentId | fsi_agentid | String | No | Copilot Studio bot component ID of the agent being validated |  |
| fsi_EnvironmentUrl | fsi_environmenturl | String | No | Target environment URL for the validation run |  |
| fsi_TestType | fsi_testtype | Picklist | Yes | Type of validation executed: FallbackCoverageCheck, ConnectorResilienceCheck, ErrorRecoveryCheck, EarlyReleaseReadinessCheck | **fsi_erv_testtype**: `100000000` = FallbackCoverageCheck, `100000001` = ConnectorResilienceCheck, `100000002` = ErrorRecoveryCheck, `100000003` = EarlyReleaseReadinessCheck |
| fsi_TestStatus | fsi_teststatus | Picklist | Yes | Overall pass/fail/skipped result of the validation | **fsi_erv_teststatus**: `100000000` = Pass, `100000001` = Fail, `100000002` = Skipped |
| fsi_FindingDetail | fsi_findingdetail | Memo | No | JSON document of structured findings produced by the validation run |  |
| fsi_ExecutedOn | fsi_executedon | DateTime | Yes | UTC timestamp when the validation was executed |  |
| fsi_AgentVersion | fsi_agentversion | String | No | Solution/agent version that was validated |  |
| fsi_EvidenceHash | fsi_evidencehash | String | No | SHA-256 hash (hex) of the finding detail for tamper-evident evidence |  |
| fsi_GapCount | fsi_gapcount | Integer | No | Number of resilience gaps detected by the validation |  |
| fsi_PromotionReady | fsi_promotionready | Boolean | No | Composite gate: true only when all structural checks pass and the early-release readiness probe passes | `1` = Yes, `0` = No |
| fsi_CorrelationId | fsi_correlationid | String | No | Short hex correlation ID linking this result to the audit log file on disk and to sibling rows in the run |  |

## Option Sets

### fsi_erv_testtype

Type of early-release resilience validation executed against a Copilot Studio agent

| Value | Label |
|---|---|
| 100000000 | FallbackCoverageCheck |
| 100000001 | ConnectorResilienceCheck |
| 100000002 | ErrorRecoveryCheck |
| 100000003 | EarlyReleaseReadinessCheck |

### fsi_erv_teststatus

Pass/Fail/Skipped outcome of an early-release validation

| Value | Label |
|---|---|
| 100000000 | Pass |
| 100000001 | Fail |
| 100000002 | Skipped |
