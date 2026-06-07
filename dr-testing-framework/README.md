---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P4, P5]
applicable_drivers:
  - ai_governance
  - technology_data
coe_function: govern
---
# DR Readiness Validation Framework (DR-Testing-Framework)

> **Version:** v2.0.2
> **Status:** Live
> **Validated against framework version:** v1.6.0

Scheduled validation that the post-recovery state of an AI agent environment in Microsoft Power Platform is observable, reachable, and correctly configured — packaging structured evidence for FFIEC BCP, FINRA Rule 4370, OCC Heightened Standards, and SEC Rule 17a-4(f) supervisory review.

## What this framework actually does (and does not do)

This framework is **post-recovery validation and evidence packaging**, not recovery execution. Power Platform environments and Copilot Studio agents are tenant-bound metadata managed by Microsoft — a customer script cannot back them up, restore them point-in-time, or fail traffic to another region. Those operations are performed through the Power Platform admin center (PPAC), the current Power Apps admin module cmdlets, Microsoft-led DR processes where applicable, and ALM solution re-deployment. Read the table below carefully before classifying outputs as recovery-test evidence.

| Capability | This framework | What you still need |
|------------|----------------|----------------------|
| Verify a previously restored agent is reachable, has its components, and is in `Active` state | ✅ Yes (`AgentReadinessCheck`) | A separately performed restore via PPAC or solution re-import |
| Verify a target Dataverse environment is reachable and authenticates a known identity | ✅ Yes (`EnvironmentReachabilityCheck`) | A separately completed PPAC/Admin-module restore, copy, or Microsoft-led DR event; document whether the operation was same-region restore, copy to another environment, or Microsoft-managed failover |
| Verify the DR-evidence Dataverse table is queryable, paginate it, and hash a snapshot for integrity | ✅ Yes (`DataverseAccessCheck`) | Backup-timestamp comparison for true RPO (Microsoft does not expose backup timestamps to customer queries) |
| Initiate a Power Platform environment restore | ❌ No | PPAC UI / Power Platform admin REST API (out of scope) |
| Fail traffic to a backup region | ❌ No | This is platform-level and customer-invisible |
| Compute true RTO (incident → service-restored) | ❌ No | Manual recording of incident and restore timestamps |
| Compute true RPO (last successful backup) | ❌ No | Backup timestamps are not exposed by Microsoft |

The script writes an audit log on every run and appends a row to `fsi_drtestresult` — these rows are the *operational evidence* an examiner expects to see, but they prove the **validation occurred**, not that recovery was performed end-to-end. Treat the artifacts accordingly.

## Features

| Feature | Description |
|---------|-------------|
| **Scheduled or on-demand checks** | Run `Invoke-DRTest.ps1` from Azure Automation, GitHub Actions, or ad hoc |
| **Probe-time tracking** | Records wall-clock time of each check and labels it as `ProbeDurationHours` (NOT recovery time) |
| **Last-test-recency tracking** | `MinutesSinceLastResult` reports gap since the last DR-evidence row was written (NOT RPO) |
| **Honest target presentation** | Each scenario lists a validation probe budget and a clear note that the script does not measure actual RTO |
| **Validation checks** | Confirms agent component count, statecode, connection references, WhoAmI security context |
| **Pagination-safe queries** | All Dataverse reads follow `@odata.nextLink` and use `$count=true` for true counts |
| **Fail-closed auth** | Missing credentials are an error, not a silent PASS (use `-AllowConnectivityOnly` to opt in) |
| **Evidence export** | `Export-DREvidence.ps1` paginates the full results history and emits a per-test JSON + summary |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    DR Testing Framework                          │
├─────────────────────────────────────────────────────────────────┤
│  Scheduler  │  Test Runner  │  Validator  │  Evidence Generator │
└─────────────┴───────────────┴─────────────┴─────────────────────┘
                              ▲
                              │ Test Execution
                              │
┌─────────────────────────────────────────────────────────────────┐
│                    Dataverse (Test Registry)                     │
├────────────────┬────────────────┬────────────────┬──────────────┤
│ Test           │ Test           │ Validation     │ Recovery     │
│ Schedule       │ Execution      │ Result         │ Gap          │
└────────────────┴────────────────┴────────────────┴──────────────┘
                              ▲
                              │ Recovery Targets
                              │
┌─────────────┬───────────────┬───────────────┬───────────────────┐
│ Copilot     │ Power Platform│ Dataverse     │ Azure             │
│ Studio      │ Environments  │ Data          │ Dependencies      │
└─────────────┴───────────────┴───────────────┴───────────────────┘
```

## Test Scenarios

The v2 scenario names describe **validation checks**. Legacy v1 names are still accepted by the CLI for one minor release and are normalized automatically.

### 1. AgentReadinessCheck (legacy alias: AgentRestore)

Validates that a restored, copied, or redeployed Copilot Studio agent is present in Dataverse, has component records, and is active.

| Metric | Target | Validation evidence |
|--------|--------|---------------------|
| **ProbeDurationHours** | 0.25 hours | Read-only API checks complete within the validation budget |
| **Operator RTO/RPO evidence** | Captured outside this script | PPAC/Admin-module restore timestamps, solution import logs, or incident timeline |

### 2. EnvironmentReachabilityCheck (legacy alias: EnvironmentFailover)

Validates that the target Dataverse environment endpoint responds and that authenticated `WhoAmI` succeeds after the operator completes the recovery step.

| Metric | Target | Validation evidence |
|--------|--------|---------------------|
| **ProbeDurationHours** | 0.10 hours | Dataverse endpoint and organization metadata are reachable |
| **Operator RTO/RPO evidence** | Captured outside this script | PPAC restore/copy operation details and service health incident notes |

### 3. DataverseAccessCheck (legacy alias: DataRecovery)

Validates that the `fsi_drtestresult` table is queryable, recent rows can be hashed, and server-side counts are available.

| Metric | Target | Validation evidence |
|--------|--------|---------------------|
| **MinutesSinceLastResult** | 1440 minutes | Gap since the last validation row, not the Dataverse backup timestamp |
| **Operator RPO evidence** | Captured outside this script | Backup/restore timestamp evidence from PPAC or Microsoft support records |

### 4. FullValidation (legacy alias: FullDR)

Runs all three validation checks and aggregates their results into one evidence row.

| Metric | Target | Validation evidence |
|--------|--------|---------------------|
| **ProbeDurationHours** | 0.75 hours | Combined validation budget for all read-only checks |
| **Coverage** | All validation types run | Evidence export reports missing validation types as `IncompleteValidationCoverage` |

## Prerequisites

### Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Platform per-app or per-user license** | Required for any Power Platform environment that hosts Copilot Studio agents under validation |
| **Dataverse capacity** | Storage for `fsi_drtestresult` rows (one row per test run; budget for the long-tail retention period mandated by SEC 17a-4) |
| **PowerShell 7.1+** | The script uses `Get-Date -AsUTC` (added in PowerShell 7.1). Earlier versions will fail at runtime |

> Power Platform environment backups are managed by Microsoft and are not administered through Azure Backup. Restore is performed via the Power Platform admin center (PPAC), not by this framework.

### Permissions

| Role | Required For |
|------|--------------|
| **Power Platform Admin** (Microsoft Entra ID) | Performing any environment restore from PPAC (out of scope of this script — listed for the operator) |
| **Application user** (managed identity, workload identity, or service principal) in the target Dataverse environment with access to `bot`, `botcomponent`, `connectionreference`, `WhoAmI`, and the `fsi_drtestresult` table | Required for `Invoke-DRTest.ps1` to read agent state and write evidence rows |

### Dependencies

| Solution | Version | Purpose |
|----------|---------|---------|
| Environment Lifecycle Management | v1.2.0+ | Environment context only (informational — not imported or validated at runtime) |

## Quick Start

### 1. Deploy Dataverse Schema

```powershell
# Prefer an access token acquired through managed identity or workload identity
python scripts/create_drt_dataverse_schema.py `
    --environment-url https://your-org.crm.dynamics.com `
    --access-token $env:DRT_ACCESS_TOKEN

# Or preview with dry-run first
python scripts/create_drt_dataverse_schema.py `
    --environment-url https://your-org.crm.dynamics.com `
    --access-token $env:DRT_ACCESS_TOKEN `
    --dry-run
```

### 2. Run DR Test

```powershell
.\scripts\Invoke-DRTest.ps1 `
    -TestType "AgentReadinessCheck" `
    -AgentId "guid" `
    -Environment "https://your-org.crm.dynamics.com" `
    -AccessToken $env:DATAVERSE_ACCESS_TOKEN
```

### 3. Review Results

Check test results in Dataverse.

> **Note:** For recurring validation runs, schedule the script via Azure Automation or GitHub Actions. `Export-DREvidence.ps1` paginates the full Dataverse history of test rows and packages a per-row JSON + summary into a versioned evidence directory — see [Evidence Export](docs/evidence-export.md).

> **Note (v2.0.0):** Earlier versions of this README claimed the script measures actual RTO/RPO. It does not — see [What this framework actually does](#what-this-framework-actually-does-and-does-not-do). The recorded `ProbeDurationHours` is the wall-clock duration of read-only API checks; the recorded `MinutesSinceLastResult` is the gap since the most recent prior evidence row was written. Neither of these is regulator-grade RTO or RPO on its own — pair them with the timestamps captured during the actual PPAC-initiated restore.

## Deployment

No exported Power Platform runtime artifacts ship with this solution. Deploy the Dataverse table with the schema script or create it manually from the generated schema reference.

```powershell
python scripts/create_drt_dataverse_schema.py `
    --environment-url https://your-org.crm.dynamics.com `
    --access-token $env:DRT_ACCESS_TOKEN

python scripts/create_drt_dataverse_schema.py --output-docs
```

Client-secret authentication remains available for local development only and is marked in scripts as legacy dev-only. For production automation, acquire a Dataverse token using managed identity, user-assigned managed identity, workload identity federation, or another approved credential flow and pass it with `--access-token` / `-AccessToken`.

### Dataverse Schema: `fsi_drtestresult`

The `Save-TestResult` function writes to a custom Dataverse table with **logical name** `fsi_drtestresult` (singular). Dataverse will auto-generate the entity set name `fsi_drtestresults` used by the API. Create this table manually with the following columns or run the schema script above:

> **Verification:** Confirm the entity set name by calling `GET {env}/api/data/v9.2/EntityDefinitions(LogicalName='fsi_drtestresult')?$select=EntitySetName`.

| Column (Logical Name) | Type | Description |
|------------------------|------|-------------|
| `fsi_name` | Single Line of Text (100) | Required primary name for the validation row |
| `fsi_testtype` | Single Line of Text (100) | Validation type: AgentReadinessCheck, EnvironmentReachabilityCheck, DataverseAccessCheck, FullValidation |
| `fsi_executedon` | Date and Time (`TimeZoneIndependent`) | UTC timestamp of validation execution |
| `fsi_actualrto` | Decimal Number | Compatibility column that stores `ProbeDurationHours`; it is not actual RTO |
| `fsi_targetrto` | Whole Number | Compatibility column that stores `ProbeDurationTargetHours`; it is not target RTO |
| `fsi_rtomet` | Yes/No (Boolean) | Compatibility column that stores `ProbeWithinBudget` |
| `fsi_status` | Choice (Option Set) | 1 = Pass, 2 = Fail |
| `fsi_validationchecks` | Multiple Lines of Text | JSON array of validation check results |
| `fsi_correlationid` | Single Line of Text (8) | Short correlation ID linking the Dataverse record to its audit log file |

## Documentation

| Document | Description |
|----------|-------------|
| [Prerequisites](docs/prerequisites.md) | Licensing, roles, dependencies, network requirements |
| [Dataverse Schema](docs/dataverse-schema.md) | Table and column definitions for fsi_drtestresult |
| [Evidence Export](docs/evidence-export.md) | Evidence packaging for supervisory reporting |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and resolution steps |

## Test Execution Workflow

```
1. Plan Recovery Exercise
   └─→ Define scope, owner, target environment, and expected evidence

2. Execute Recovery Outside This Framework
   └─→ Use PPAC/Admin-module restore, environment copy, solution import, or Microsoft-led DR process

3. Run Post-Recovery Validation
   └─→ Execute Invoke-DRTest.ps1 against the recovered target

4. Persist Validation Evidence
   └─→ Write fsi_drtestresult rows and local audit logs

5. Package Evidence
   └─→ Export JSON, SHA-256 companion hash, and audit logs

6. Attach Operator Evidence
   └─→ Store PPAC/Admin-module timestamps, support ticket IDs, and incident timeline separately
```

## Validation Checks

### Agent readiness

| Check | Method | Pass Criteria |
|-------|--------|---------------|
| Agent present | Query `bots` by `botid` | Matching agent record found |
| Component inventory | Query `botcomponents` by parent bot | One or more component records found |
| Agent active state | Read `statecode` from `bots` | `statecode = 0` |

### Environment reachability

| Check | Method | Pass Criteria |
|-------|--------|---------------|
| Environment endpoint | HTTP request to Dataverse service root | Endpoint responds within timeout |
| Authenticated context | Dataverse `WhoAmI` | Organization/user context returned |
| Organization metadata | Query `organizations` | Organization record returned |

### Dataverse access and evidence integrity

| Check | Method | Pass Criteria |
|-------|--------|---------------|
| Evidence table access | Query `fsi_drtestresults` | Table is queryable |
| Snapshot hash | SHA-256 over recent evidence rows | Hash generated for evidence package |
| Record count | `$count=true&$top=0` | Server-side count returned |

## Metrics

### Validation probe duration

```
ProbeDurationHours = Validation Complete Time - Validation Start Time
ProbeWithinBudget = ProbeDurationHours <= ProbeDurationTargetHours
```

These values measure the script's read-only validation checks. They do not represent incident-to-recovery RTO.

### Last validation recency

```
MinutesSinceLastResult = Current Time - Most Recent fsi_drtestresult ExecutedOn
LastResultWithinThreshold = MinutesSinceLastResult <= MaxMinutesSinceLastResult
```

These values measure evidence cadence. They do not represent Dataverse backup recency or regulator-grade RPO.

### Success rate

```
Validation Success Rate = (Passed Validations / Total Validations) × 100
```

## Power Platform backup, restore, and regional notes (Microsoft Learn 2026-Q2)

- Power Platform and Dataverse system backups are Microsoft-managed for environments that have a database. By default, both system and manual backups are retained for seven days across all production and nonproduction environments. For production **Managed Environments**, a tenant admin (Power Platform Admin, Entra Global Admin, or Dynamics 365 admin) can extend the retention period to 7, 14, 21, or up to 28 days through the Power Platform admin center or PowerShell; the configured value applies to both system and manual backups.
- Manual backups are operator-initiated, may take 10-15 minutes before they are available for restore, do not count against storage capacity, and require at least 1 GB of available capacity to restore.
- Manual backups are restored in the same region where the environment was backed up. Do not treat Azure region pairs as customer-controlled failover for Power Platform environments.
- Use the current Power Apps admin module cmdlet `Backup-PowerAppEnvironment` for operator-initiated environment backups. `Copy-PowerAppEnvironment` copies source to target, but copied custom connectors receive new identifiers and flows may need connector rebinding.
- Azure region pairs can inform architecture decisions, but Azure paired regions do not automatically provide high availability or disaster recovery for customer workloads. Many newer regions rely on availability zones or service-specific geo-redundancy patterns.

## Application Insights telemetry review

Copilot Studio can send bot telemetry to Application Insights `customEvents`, and Dataverse platform telemetry appears in `requests`, `dependencies`, and `exceptions`. Use these queries as reviewer starting points when correlating DR validation runs with platform health:

```kusto
let window = 2h;
customEvents
| where timestamp > ago(window)
| extend designMode = tostring(customDimensions['designMode'])
| where designMode == 'False'
| summarize Events = count(), Users = dcount(user_Id) by bin(timestamp, 15m)
| render timechart
```

```kusto
let window = 2h;
requests
| where timestamp > ago(window)
| where url has '/api/data/v9.2/'
| summarize Count = count(), P95DurationMs = percentile(duration, 95), Failures = countif(success == false) by bin(timestamp, 15m)
| render timechart
```

```kusto
let window = 2h;
dependencies
| where timestamp > ago(window)
| where type startswith 'SDK' or type == 'Plugin'
| summarize Count = count(), P95DurationMs = percentile(duration, 95), Failures = countif(success == false) by type, bin(timestamp, 15m)
```

## Microsoft Entra resilience notes

Maintain Microsoft Entra emergency access accounts separately from normal administrator accounts. Microsoft Learn recommends two or more cloud-only emergency accounts, strong authentication that does not share the same dependencies as normal admin accounts, monitored sign-in/audit logs, and regular validation drills. Store emergency-access drill evidence with DR validation packages when identity resilience is in scope.

## Gap Management

### Gap Categories

| Category | Example | Priority |
|----------|---------|----------|
| **Process** | Manual step not documented | High |
| **Technical** | Backup job failing | Critical |
| **Resource** | Insufficient backup storage | Medium |
| **Knowledge** | Team unfamiliar with procedure | Medium |

### Gap Lifecycle

```
Identified → Documented → Assigned → Remediated → Verified → Closed
```

## Evidence Export

The framework generates validation evidence:

- Validation execution log
- Per-check validation results
- Probe-duration and validation-cadence metrics
- Gap list with missing validation types or failed checks
- SHA-256 companion hash for the exported JSON package
- Optional downstream attestation or immutable-storage proof

RTO/RPO evidence must come from the operator's PPAC/Admin-module restore timestamps, Microsoft support records, incident timeline, or approved runbook evidence. Store those artifacts beside the exported JSON package.

## Scheduling

### Recommended Frequency

| Test Type | Frequency | Rationale |
|-----------|-----------|-----------|
| AgentReadinessCheck | Quarterly | Validate restored or redeployed agent metadata and active state |
| EnvironmentReachabilityCheck | Semi-annual | Validate target environment reachability after recovery procedures |
| DataverseAccessCheck | Quarterly | Validate evidence table accessibility and row hashing |
| FullValidation | Annual | Validate complete post-recovery evidence coverage |

## Regulatory Alignment

### OCC Heightened Standards

> Large banks must maintain effective operational resilience.

**Coverage:** Regular post-recovery validation supports operational-resilience evidence when paired with operator recovery records.

### FFIEC BCP (Business Continuity Planning Booklet)

> Financial institutions must test business continuity plans on a defined cadence and retain the test evidence.

**Coverage:** Scheduled validation runs with persisted, hashed Dataverse evidence rows and an exportable per-test JSON package, helping support FFIEC BCP testing-evidence requirements. RPO is **not** measured by this framework — Microsoft does not expose Dataverse backup timestamps to customer queries; pair the script's evidence rows with backup-timestamp documentation supplied by Microsoft via support requests.

### SEC Rule 17a-4(f)

> Records must be retained, indexed, and recoverable for a defined period in a non-rewritable, non-erasable format.

**Coverage:** This framework writes evidence rows and exports per-test JSON packages to support 17a-4 evidence retention, but **the regulation's tamper-evidence requirement is satisfied only when the export is written to immutable storage** (Azure Blob immutability policy, Purview retention lock, or equivalent). The framework does not enforce immutability — that is the customer's responsibility downstream of `Export-DREvidence.ps1`.

### FINRA Rule 4370

> Members must create and maintain business continuity plans.

**Coverage:** Documented validation with evidence collection supports BCP documentation.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [2.4 - Business Continuity and Disaster Recovery](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.4-business-continuity-and-disaster-recovery.md) | Primary — recovery validation and evidence-collection cadence |
| [2.1 - Managed Environments](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.1-managed-environments.md) | Validates that a managed environment is reachable and correctly configured post-restore |
| [1.9 - Data Retention](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.9-data-retention-and-deletion-policies.md) | Evidence-row retention pairs with the long-tail retention requirements |

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0.2 | May 2026 | Council review remediations: M-1 secret-zeroize hardening in `Export-DREvidence.ps1`; M-2 swapped `@()`/`+=` to `[List[object]]` for performance; m-5 dry-run gating moved off `client.dry_run` to function `dry_run` parameter in v2.0.0 schema scripts; m-6 KQL `extract` regex tightened to capture entity-set name; bonus PS 5.1 `Get-Date -AsUTC` defensive fix; em-dash sweep across `.ps1` files |
| 2.0.1 | April 2026 | Microsoft Learn 2026-Q2 refresh: aligned Power Platform backup/restore notes, evidence export semantics, generated schema wording, Application Insights telemetry examples, and managed-identity-first authentication guidance |
| 2.0.0 | April 2026 | **BREAKING.** Renamed test scenarios to validation checks; relabeled `ActualRTO`→`ProbeDurationHours` and `ActualRPO`→`MinutesSinceLastResult` to stop misrepresenting the measurements; added `-AllowConnectivityOnly` for fail-closed auth; pagination via `@odata.nextLink`; switched record-count to `$count=true&$top=0`; bumped to PowerShell 7.1; dropped Azure Backup / Backup Operator from prereqs; corrected Decimal env-var type code; fixed `fsi_executedon` to `TimeZoneIndependent`; dropped Control 2.13 from Related Controls (catalog mismatch); aligned ELM dependency floor to v1.2.0 |
| 1.2.1 | April 2026 | Save-TestResult fix: include required `fsi_name` primary attribute for Dataverse writes |
| 1.2.0 | April 2026 | Environment variables, connection references, real Dataverse implementations in Invoke-DRTest and Export-DREvidence |
| 1.1.0 | April 2026 | Dataverse schema script, documentation suite, prerequisites guide |
| 1.0.2 | March 2026 | Auth endpoint mapping, ClientId validation, exit code 2 for persistence failures |
| 1.0.1 | March 2026 | Write-AuditLog stream fix, Retry-After support, SSRF validation, verbose diagnostics |
| 1.0.0 | February 2026 | Initial release |

## Troubleshooting

### Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Authentication failure | Expired access token, insufficient permissions, or legacy client secret issue | Prefer a fresh managed-identity/workload-identity `-AccessToken`; for local development, verify service-principal credentials and Dataverse application-user access. |
| Probe budget exceeded | Validation checks took longer than the configured probe budget | Review API latency, Dataverse throttling, and Application Insights telemetry; do not treat this as actual RTO evidence by itself |
| Validation checks fail | Agent or connectors not restored correctly post-restore | Verify the post-restore agent state in Power Platform admin center; re-run the individual scenario with `-Verbose` |
| Dataverse save error | Missing schema or insufficient Dataverse capacity | Run `python scripts/create_drt_dataverse_schema.py --output-docs` and deploy the schema with `--access-token`; check storage quota in PPAC |

### Logs

Review script output for `[ERROR]` and `[WARN]` audit log entries. Enable verbose output with `-Verbose` for diagnostic details on token acquisition, retry attempts, and Dataverse saves.

### Exit Codes

| Code | Meaning |
|------|---------|
| **0** | Validation passed and results saved (or DryRun / explicitly requested `-AllowConnectivityOnly` probe) |
| **1** | Validation failed |
| **2** | Validation passed but Dataverse persistence failed, or evidence export found no data/incomplete coverage |

## Support

For issues, see [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues).

---

*FSI Agent Governance Framework - DR Testing Framework v2.0.2*
