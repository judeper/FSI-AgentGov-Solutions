# DR Testing Framework

> **Status:** Work In Progress

Automated disaster recovery testing workflows for AI agent infrastructure, ensuring compliance with operational resilience requirements.

## Overview

The DR Testing Framework validates that AI agents and supporting infrastructure can be recovered within defined Recovery Time Objectives (RTO) and Recovery Point Objectives (RPO), supporting regulatory requirements for business continuity.

## Features

| Feature | Description |
|---------|-------------|
| **Automated Testing** | On-demand DR test execution (scheduling planned) |
| **RTO/RPO Measurement** | Track actual recovery times vs. targets (RPO measurement not yet implemented — see [Known Limitations](#known-limitations)) |
| **Validation Checks** | Verify agent functionality post-recovery |
| **Evidence Collection** | Generate compliance artifacts (not yet implemented) |
| **Gap Tracking** | Identify and monitor recovery gaps (not yet implemented) |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    DR Testing Framework                          │
├─────────────────────────────────────────────────────────────────┤
│  Scheduler  │  Test Runner  │  Validator  │  Evidence Generator  │
│  (planned)  │               │             │  (planned)           │
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
| **Power Platform Premium** | Power Automate flows |
| **Dataverse capacity** | Test result storage |
| **Azure Backup** | Environment backups (optional) |

### Permissions

| Role | Required For |
|------|--------------|
| **Power Platform Administrator** | Environment operations |
| **System Administrator** | Dataverse restore |
| **Backup Operator** | Azure Backup access |

### Dependencies

| Solution | Version | Purpose |
|----------|---------|---------|
| Environment Lifecycle Management | v1.1.0+ | Environment context |

## Quick Start

### 1. Deploy Dataverse Schema

> **Note:** The Dataverse schema package (`DRTestingFramework_1_0_0.zip`) is not yet included in this repository. You must manually create the `fsi_drtestresults` table with the required columns (`fsi_testtype`, `fsi_executedon`, `fsi_actualrto`, `fsi_targetrto`, `fsi_rtomet`, `fsi_actualrpo`, `fsi_targetrpo`, `fsi_rpomet`, `fsi_status`, `fsi_validationchecks`), or import a schema package when one is provided.

#### `fsi_drtestresults` Table Schema

| Column | Type | Description |
|--------|------|-------------|
| `fsi_testtype` | Single Line of Text | Test type: `AgentRestore`, `EnvironmentFailover`, `DataRecovery`, or `FullDR` |
| `fsi_executedon` | Single Line of Text | ISO 8601 UTC timestamp of test execution (e.g., `2026-02-19T04:00:00Z`) |
| `fsi_actualrto` | Decimal Number | Measured recovery time in hours, rounded to 2 decimal places |
| `fsi_targetrto` | Whole Number | Target RTO in hours (e.g., 4, 2, 8) |
| `fsi_rtomet` | Two Options (Boolean) | Whether the actual RTO met the target (`true`/`false`) |
| `fsi_actualrpo` | Decimal Number | Measured RPO in hours (currently `null`; reserved for future use) |
| `fsi_targetrpo` | Whole Number | Target RPO in hours (e.g., 24, 1) |
| `fsi_rpomet` | Two Options (Boolean) | Whether the actual RPO met the target (currently `null`; reserved for future use) |
| `fsi_status` | Whole Number (Option Set) | Test outcome: `1` = Pass, `2` = Fail |
| `fsi_validationchecks` | Multiple Lines of Text (Memo) | JSON-encoded array of validation check objects. Stored as a JSON string (not double-encoded). Each element has `Check` (string) and `Status` (string: `PASS`, `FAIL`, or `SKIPPED (DRY RUN)`). Example: `[{"Check":"Backup Located","Status":"PASS"}]`. Consumers should parse this field once with a JSON parser. |

```powershell
# Dataverse schema package is not yet included in this repository.
# Create the fsi_drtestresults table manually or import a schema package when available.
# pac solution import --path ./templates/DRTestingFramework_1_0_0.zip
```

### 2. Run DR Test

> **Note:** The `-Environment` URL must be a valid Dataverse URL matching `https://<org>.crm[N].dynamics.<tld>` (e.g., `.com`, `.us`, `.cn`, `.de`) or `https://<org>.crm.microsoftdynamics.us` (GCC High). The script validates this to prevent sending OAuth tokens to unintended endpoints.

```powershell
.\scripts\Invoke-DRTest.ps1 `
    -TestType "AgentRestore" `
    -AgentId "guid" `
    -Environment "https://your-org.crm.dynamics.com"
```

### 3. Review Results

Check test results in Dataverse.

**Planned:** `New-DRTestSchedule.ps1` and `Export-DREvidence.ps1` are under development.

> **Note:** Recovery steps in `Invoke-DRTest.ps1` are currently stub implementations using simulated timing (`Start-Sleep`). RTO/RPO measurements reflect simulated timing only. Replace `Start-Sleep` calls with actual backup/restore API calls for production use.

## Deployment

> **Planned** — Deployment instructions will be added when implementation is complete.

## Documentation

Detailed documentation is planned for a future release. See inline comments in `Invoke-DRTest.ps1` for usage.

## Test Execution Workflow

```
1. Schedule Test (planned)
   └─→ Define scenario, target, schedule

2. Pre-Test Baseline
   └─→ Capture current state, configuration hash

3. Execute Recovery
   └─→ Perform recovery procedure, measure time

4. Validate Functionality
   └─→ Run validation checks, verify responses

5. Document Results
   └─→ Record metrics, gaps, observations

6. Generate Evidence (planned)
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

> **Not yet implemented.** RPO targets are defined but actual RPO measurement requires backup timestamp comparison, which depends on integration with the backup/restore APIs. RPO fields are omitted from Dataverse results until measurement is implemented.

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

### FFIEC BCP

> Financial institutions must test business continuity plans.

**Coverage:** Automated testing with documented results.

### SEC Rule 17a-4

> Records must be recoverable.

**Coverage:** Data recovery validation with RPO measurement.

### FINRA Rule 4370

> Members must create and maintain business continuity plans.

**Coverage:** Documented testing with evidence collection.

## Known Limitations

| Limitation | Impact | Planned Resolution |
|------------|--------|-------------------|
| **RPO not measured** | `fsi_actualrpo` and `fsi_rpomet` are omitted from Dataverse results. RPO targets are defined but actual values require backup timestamp comparison via backup/restore APIs. | Future release will integrate with Azure Backup / Power Platform backup APIs to compute actual RPO. |
| **Recovery steps are stubs** | All recovery functions use `Start-Sleep` instead of real API calls. RTO measurements reflect simulated timing only. | Replace stubs with actual backup/restore API calls for production use. |
| **ClientSecret accepted as plaintext** | `$ClientSecret` is a `[string]` parameter. The value may appear in PowerShell transcript logs or process command lines. The script clears the variable after token acquisition. | Future release may accept `[SecureString]` or certificate-based authentication. |

## Related Controls

| Control | Relationship |
|---------|--------------|
| [2.4 - Business Continuity and Disaster Recovery](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.4-business-continuity-and-disaster-recovery.md) | Primary control for DR testing |
| [2.1 - Managed Environments](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.1-managed-environments.md) | Environment backup |
| [2.13 - Documentation](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.13-documentation-and-record-keeping.md) | Procedure documentation |
| [1.9 - Data Retention](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.9-data-retention-and-deletion-policies.md) | Backup retention |

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | February 2026 | Initial release |

## Troubleshooting

### Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Authentication failure | Expired token or insufficient permissions | Re-authenticate; verify service principal has Power Platform Administrator and Backup Operator roles |
| RTO target exceeded | Recovery steps slower than expected | Review environment size; pre-stage backups closer to target region |
| Validation checks fail | Agent or connectors not restored correctly | Verify backup integrity; re-run individual test scenario and review console output |
| Dataverse save error | Missing schema or insufficient Dataverse capacity | Import solution package; check storage quota |

### Logs

Review script console output for warnings and error messages. The script uses `Write-Host` and `Write-Warning` for diagnostic output.

## Support

For issues, see [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues).

---

*FSI Agent Governance Framework - DR Testing Framework v1.0.0*
