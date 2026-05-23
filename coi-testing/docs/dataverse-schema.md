# COI Testing — Dataverse Schema

This solution does not yet ship a `create_coi_dataverse_schema.py` generator;
create the `fsi_coitestresult` table manually from the column list below.
The shared `scripts/shared/dataverse_client.py` library can be used to script
table creation programmatically, but no turnkey generator is provided in this
solution today.

## Table: `fsi_coitestresult`

- **Display name:** COI Test Result
- **Schema name:** `fsi_COITestResult`
- **Logical name:** `fsi_coitestresult`
- **Entity set name (OData):** `fsi_coitestresults`
- **Primary name attribute:** `fsi_scenarioid`

### Columns

| Logical Name | Schema Name | Type | Required | Description |
|--------------|-------------|------|----------|-------------|
| `fsi_scenarioid` | `fsi_ScenarioId` | String (Text, 50) | Required | Scenario identifier (e.g., `PB-001`, `SU-002`). Primary name. |
| `fsi_scenarioname` | `fsi_ScenarioName` | String (Text, 255) | Required | Human-readable scenario name. |
| `fsi_category` | `fsi_Category` | String (Text, 100) | Required | One of `proprietary_bias`, `suitability`, `fee_transparency`, `cross_selling`. |
| `fsi_status` | `fsi_Status` | Choice (Option Set) | Required | See **Status option set** below. |
| `fsi_executedon` | `fsi_ExecutedOn` | DateTime (UTC) | Required | When the scenario ran. |
| `fsi_findings` | `fsi_Findings` | String (Multiline Text, 10000) | Optional | JSON array of finding objects emitted by the runner. |

### Status option set (`fsi_status`)

| Label | Value | Meaning |
|-------|-------|---------|
| PASS | `100000000` | Agent behaved appropriately. |
| FAIL | `100000001` | Potential COI detected. |
| SKIPPED | `100000002` | Scenario could not execute (current default until the Direct Line agent-interaction layer ships). |
| WARN | `100000003` | Borderline behavior requiring review. |
| ERROR | `100000004` | Test execution failed (exception during run). |

> Dataverse Choice columns require integer values in the `100000000+` range.
> The runner (`scripts/run_coi_tests.py`) writes these values directly via the
> Web API; do not alter the values without simultaneously updating
> `status_map` in `save_results()`.

## OData query examples

```http
GET {{environment}}/api/data/v9.2/fsi_coitestresults?$select=fsi_scenarioid,fsi_status,fsi_executedon&$orderby=fsi_executedon desc
GET {{environment}}/api/data/v9.2/fsi_coitestresults?$filter=fsi_status eq 100000001
```
