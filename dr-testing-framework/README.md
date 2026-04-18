# DR Readiness Validation Framework (DR-Testing-Framework)

> **Version:** 2.0.0 | **Controls:** 2.4, 2.1, 1.9

Scheduled validation that the post-recovery state of an AI agent environment in Microsoft Power Platform is observable, reachable, and correctly configured — packaging structured evidence for FFIEC BCP, FINRA Rule 4370, OCC Heightened Standards, and SEC Rule 17a-4(f) supervisory review.

## What this framework actually does (and does not do)

This framework is **post-recovery validation and evidence packaging**, not recovery execution. Power Platform environments and Copilot Studio agents are tenant-bound metadata managed by Microsoft — a customer script cannot back them up, restore them point-in-time, or fail traffic to a paired region. Those operations are performed by Microsoft via the Power Platform admin center (PPAC) restore APIs and ALM solution re-deployment. Read the table below carefully before classifying outputs as recovery-test evidence.

| Capability | This framework | What you still need |
|------------|----------------|----------------------|
| Verify a previously restored agent is reachable, has its components, and is in `Active` state | ✅ Yes (`AgentReadinessCheck`) | A separately performed restore via PPAC or solution re-import |
| Verify a target Dataverse environment is reachable and authenticates a known service principal | ✅ Yes (`EnvironmentReachabilityCheck`) | Microsoft-side restore of the environment to a paired region (PPAC) |
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
| **Honest target presentation** | Each scenario lists its RTO target and a clear note that the script does not measure actual RTO |
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

### 1. Agent Restore

Restore a Copilot Studio agent from backup/export.

| Metric | Target | Validation |
|--------|--------|------------|
| **RTO** | 4 hours | Agent operational |
| **RPO** | 24 hours | Configuration current |

### 2. Environment Failover

Switch agent workload to backup environment.

| Metric | Target | Validation |
|--------|--------|------------|
| **RTO** | 2 hours | Environment accessible |
| **RPO** | 1 hour | Data synchronized |

### 3. Data Recovery

Restore Dataverse data from backup.

| Metric | Target | Validation |
|--------|--------|------------|
| **RTO** | 4 hours | Data accessible |
| **RPO** | 24 hours | Data complete |

### 4. Full DR

Complete infrastructure recovery.

| Metric | Target | Validation |
|--------|--------|------------|
| **RTO** | 8 hours | Full functionality |
| **RPO** | 24 hours | All systems current |

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
| **Service Principal application user** in the target Dataverse environment with access to `bot`, `botcomponent`, `connectionreference`, `WhoAmI`, and the `fsi_drtestresult` table | Required for `Invoke-DRTest.ps1` to read agent state and write evidence rows |

### Dependencies

| Solution | Version | Purpose |
|----------|---------|---------|
| Environment Lifecycle Management | v1.2.0+ | Environment context only (informational — not imported or validated at runtime) |

## Quick Start

### 1. Deploy Dataverse Schema

```powershell
# Deploy schema using Python script
python scripts/create_drt_dataverse_schema.py --interactive

# Or deploy with dry-run first
python scripts/create_drt_dataverse_schema.py --dry-run --interactive
```

### 2. Run DR Test

```powershell
.\scripts\Invoke-DRTest.ps1 `
    -TestType "AgentRestore" `
    -AgentId "guid" `
    -Environment "https://your-org.crm.dynamics.com"
```

### 3. Review Results

Check test results in Dataverse.

> **Note:** For recurring validation runs, schedule the script via Azure Automation or GitHub Actions. `Export-DREvidence.ps1` paginates the full Dataverse history of test rows and packages a per-row JSON + summary into a versioned evidence directory — see [Evidence Export](docs/evidence-export.md).

> **Note (v2.0.0):** Earlier versions of this README claimed the script measures actual RTO/RPO. It does not — see [What this framework actually does](#what-this-framework-actually-does-and-does-not-do). The recorded `ProbeDurationHours` is the wall-clock duration of read-only API checks; the recorded `MinutesSinceLastResult` is the gap since the most recent prior evidence row was written. Neither of these is regulator-grade RTO or RPO on its own — pair them with the timestamps captured during the actual PPAC-initiated restore.

## Deployment

> **Planned** — A deployable Power Platform solution package (solution.xml, customizations.xml) for automated Dataverse schema deployment is planned to reduce deployment errors and support ALM pipelines. Until then, create the table manually as described below.

Alternatively, use the automated schema script:

```powershell
python scripts/create_drt_dataverse_schema.py --interactive

# Generate schema documentation
python scripts/create_drt_dataverse_schema.py --output-docs
```

### Dataverse Schema: `fsi_drtestresult`

The `Save-TestResult` function writes to a custom Dataverse table with **logical name** `fsi_drtestresult` (singular). Dataverse will auto-generate the entity set name `fsi_drtestresults` used by the API. Create this table manually with the following columns:

> **Verification:** Confirm the entity set name by calling `GET {env}/api/data/v9.2/EntityDefinitions(LogicalName='fsi_drtestresult')?$select=EntitySetName`.

| Column (Logical Name) | Type | Description |
|------------------------|------|-------------|
| `fsi_testtype` | Single Line of Text (100) | Test type: AgentRestore, EnvironmentFailover, DataRecovery, FullDR |
| `fsi_executedon` | Date and Time | UTC timestamp of test execution |
| `fsi_actualrto` | Decimal Number | Actual recovery time in hours |
| `fsi_targetrto` | Whole Number | Target RTO in hours |
| `fsi_rtomet` | Yes/No (Boolean) | Whether actual RTO met the target |
| `fsi_status` | Choice (Option Set) | 1 = Pass, 2 = Fail |
| `fsi_validationchecks` | Multiple Lines of Text | JSON array of validation check results |
| `fsi_correlationid` | Single Line of Text (8) | Short correlation ID linking the Dataverse record to its audit log file |

## Documentation

| Document | Description |
|----------|-------------|
| [Prerequisites](docs/prerequisites.md) | Licensing, roles, dependencies, network requirements |
| [Dataverse Schema](docs/dataverse-schema.md) | Table and column definitions for fsi_drtestresult |
| [Evidence Export](docs/evidence-export.md) | Evidence packaging for compliance reporting |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and resolution steps |

## Test Execution Workflow

```
1. Schedule Test
   └─→ Define scenario, target, schedule

2. Pre-Test Baseline
   └─→ Capture current state, configuration hash

3. Execute Recovery
   └─→ Perform recovery procedure, measure time

4. Validate Functionality
   └─→ Run validation checks, verify responses

5. Document Results
   └─→ Record metrics, gaps, observations

6. Generate Evidence
   └─→ Export compliance artifacts
```

## Validation Checks

### Agent Functionality

| Check | Method | Pass Criteria |
|-------|--------|---------------|
| Agent responds | Send test prompt | Response received |
| Correct identity | Check agent metadata | Matches backup |
| Topics functional | Test key topics | Expected responses |

### Connector Availability

| Check | Method | Pass Criteria |
|-------|--------|---------------|
| Connections valid | List connections | All active |
| Data accessible | Test query | Results returned |
| Auth working | Verify tokens | No auth errors |

### Security Policies

| Check | Method | Pass Criteria |
|-------|--------|---------------|
| DLP applied | Check policy status | Policies active |
| RBAC intact | Verify permissions | Roles correct |
| Audit logging | Check audit trail | Events captured |

## Metrics

### RTO Measurement

```
Actual RTO = Recovery Complete Time - Incident Start Time
RTO Met = Actual RTO <= Target RTO
```

### RPO Measurement

```
Actual RPO = Incident Start Time - Last Backup Time
RPO Met = Actual RPO <= Target RPO
```

### Success Rate

```
DR Success Rate = (Passed Tests / Total Tests) × 100
```

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

The framework generates compliance evidence:

- Test execution log
- Validation results
- RTO/RPO measurements
- Gap list with status
- Screenshot evidence (optional)
- Signed attestation template

## Scheduling

### Recommended Frequency

| Test Type | Frequency | Rationale |
|-----------|-----------|-----------|
| Agent Restore | Quarterly | Verify backup integrity |
| Environment Failover | Semi-annual | Major procedure |
| Data Recovery | Quarterly | Data protection validation |
| Full DR | Annual | Comprehensive assessment |

## Regulatory Alignment

### OCC Heightened Standards

> Large banks must maintain effective operational resilience.

**Coverage:** Regular DR testing validates recovery capabilities.

### FFIEC BCP (Business Continuity Planning Booklet)

> Financial institutions must test business continuity plans on a defined cadence and retain the test evidence.

**Coverage:** Scheduled validation runs with persisted, hashed Dataverse evidence rows and an exportable per-test JSON package, helping support FFIEC BCP testing-evidence requirements. RPO is **not** measured by this framework — Microsoft does not expose Dataverse backup timestamps to customer queries; pair the script's evidence rows with backup-timestamp documentation supplied by Microsoft via support requests.

### SEC Rule 17a-4(f)

> Records must be retained, indexed, and recoverable for a defined period in a non-rewritable, non-erasable format.

**Coverage:** This framework writes evidence rows and exports per-test JSON packages to support 17a-4 evidence retention, but **the regulation's tamper-evidence requirement is satisfied only when the export is written to immutable storage** (Azure Blob immutability policy, Purview retention lock, or equivalent). The framework does not enforce immutability — that is the customer's responsibility downstream of `Export-DREvidence.ps1`.

### FINRA Rule 4370

> Members must create and maintain business continuity plans.

**Coverage:** Documented testing with evidence collection.

## Related Controls

| Control | Relationship |
|---------|--------------|
| [2.4 - Business Continuity and Disaster Recovery](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.4-business-continuity-and-disaster-recovery.md) | Primary — recovery validation and evidence-collection cadence |
| [2.1 - Managed Environments](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.1-managed-environments.md) | Validates that a managed environment is reachable and correctly configured post-restore |
| [1.9 - Data Retention](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.9-data-retention-and-deletion-policies.md) | Evidence-row retention pairs with the long-tail retention requirements |

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 2.0.0 | April 2026 | **BREAKING.** Renamed test scenarios to validation checks; relabeled `ActualRTO`→`ProbeDurationHours` and `ActualRPO`→`MinutesSinceLastResult` to stop misrepresenting the measurements; added `-AllowConnectivityOnly` for fail-closed auth; pagination via `@odata.nextLink`; switched record-count to `$count=true&$top=0`; bumped to PowerShell 7.1; dropped Azure Backup / Backup Operator from prereqs; corrected Decimal env-var type code; fixed `fsi_executedon` to `TimeZoneIndependent`; dropped Control 2.13 from Related Controls (catalog mismatch); aligned ELM dependency floor to v1.2.0 |
| 1.2.1 | April 2026 | Save-TestResult fix: include required `fsi_name` primary attribute for Dataverse writes |
| 1.2.0 | April 2026 | Environment variables, connection references, real Dataverse implementations in Invoke-DRTest and Export-DREvidence |
| 1.1.0 | April 2026 | Dataverse schema script, documentation suite, prerequisites guide |
| 1.0.2 | March 2026 | Sovereign cloud auth endpoint mapping, ClientId validation, exit code 2 for persistence failures |
| 1.0.1 | March 2026 | Write-AuditLog stream fix, Retry-After support, SSRF validation, verbose diagnostics |
| 1.0.0 | February 2026 | Initial release |

## Troubleshooting

### Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Authentication failure | Expired token, insufficient permissions, or wrong auth endpoint for sovereign clouds | Re-authenticate; verify service principal has Power Platform Administrator and Backup Operator roles. For sovereign tenants, the script auto-selects the correct Entra ID endpoint (China: `login.chinacloudapi.cn`, GCC High: `login.microsoftonline.us`). |
| RTO target exceeded | Recovery steps slower than expected | Review environment size; pre-stage backups closer to target region |
| Validation checks fail | Agent or connectors not restored correctly post-restore | Verify the post-restore agent state in Power Platform admin center; re-run the individual scenario with `-Verbose` |
| Dataverse save error | Missing schema or insufficient Dataverse capacity | Run `python scripts/create_drt_dataverse_schema.py --interactive` to create / verify the table; check storage quota in PPAC |

### Logs

Review script output for `[ERROR]` and `[WARN]` audit log entries. Enable verbose output with `-Verbose` for diagnostic details on token acquisition, retry attempts, and Dataverse saves.

### Exit Codes

| Code | Meaning |
|------|---------|
| **0** | Test passed, results saved (or DryRun / no credentials) |
| **1** | Test failed (RTO exceeded or validation check failed) |
| **2** | Test passed but Dataverse persistence failed (auth error or save error) |

## Support

For issues, see [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues).

---

*FSI Agent Governance Framework - DR Testing Framework v2.0.0*
