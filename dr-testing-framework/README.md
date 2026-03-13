# DR Testing Framework

> **Status:** Work In Progress

Automated disaster recovery testing workflows for AI agent infrastructure, ensuring compliance with operational resilience requirements.

## Overview

The DR Testing Framework validates that AI agents and supporting infrastructure can be recovered within defined Recovery Time Objectives (RTO) and Recovery Point Objectives (RPO), supporting regulatory requirements for business continuity.

## Features

| Feature | Description |
|---------|-------------|
| **Automated Testing** | Scheduled and on-demand DR test execution |
| **RTO/RPO Measurement** | Track actual recovery times vs. targets (Note: RPO measurement is not yet implemented — requires backup timestamp comparison) |
| **Validation Checks** | Verify agent functionality post-recovery |
| **Evidence Collection** | Generate compliance artifacts (stub — `Export-DREvidence.ps1` packages audit logs; full Dataverse export planned) |
| **Gap Tracking** | Identify and monitor recovery gaps (planned) |

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
| Environment Lifecycle Management | v1.1.0+ | Environment context (informational — not imported or validated at runtime) |

## Quick Start

### 1. Deploy Dataverse Schema

```powershell
# Template package not yet available — deploy Dataverse schema manually per the Deployment section
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

**Planned:** `New-DRTestSchedule.ps1` is under development. `Export-DREvidence.ps1` is available as a stub — it packages audit log files into an evidence directory and generates a JSON metadata file. Full Dataverse query and attestation support is planned.

> **Note:** Recovery steps in `Invoke-DRTest.ps1` are currently stub implementations using simulated timing (`Start-Sleep`). RTO/RPO measurements reflect simulated timing only. Replace `Start-Sleep` calls with actual backup/restore API calls for production use.

## Deployment

> **Planned** — A deployable Power Platform solution package (solution.xml, customizations.xml) for automated Dataverse schema deployment is planned to reduce deployment errors and support ALM pipelines. Until then, create the table manually as described below.

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

Detailed documentation is planned for a future release. See inline comments in `Invoke-DRTest.ps1` for usage.

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

### FFIEC BCP

> Financial institutions must test business continuity plans.

**Coverage:** Automated testing with documented results. (Note: RPO measurement is not yet implemented — actual RPO validation requires backup timestamp comparison.)

### SEC Rule 17a-4

> Records must be recoverable.

**Coverage:** Data recovery validation with RPO measurement. (Note: RPO measurement is not yet implemented — currently tracks targets only. Actual RPO validation requires backup timestamp comparison.)

### FINRA Rule 4370

> Members must create and maintain business continuity plans.

**Coverage:** Documented testing with evidence collection.

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
| 1.0.2 | March 2026 | Sovereign cloud auth endpoint mapping, ClientId validation, exit code 2 for persistence failures |
| 1.0.1 | March 2026 | Write-AuditLog stream fix, Retry-After support, SSRF validation, verbose diagnostics |
| 1.0.0 | February 2026 | Initial release |

## Troubleshooting

### Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Authentication failure | Expired token, insufficient permissions, or wrong auth endpoint for sovereign clouds | Re-authenticate; verify service principal has Power Platform Administrator and Backup Operator roles. For sovereign tenants, the script auto-selects the correct Entra ID endpoint (China: `login.chinacloudapi.cn`, GCC High: `login.microsoftonline.us`). |
| RTO target exceeded | Recovery steps slower than expected | Review environment size; pre-stage backups closer to target region |
| Validation checks fail | Agent or connectors not restored correctly | Verify backup integrity; re-run individual test scenario with `-Verbose` |
| Dataverse save error | Missing schema or insufficient Dataverse capacity | Import solution package; check storage quota |

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

*FSI Agent Governance Framework - DR Testing Framework v1.0.2*
