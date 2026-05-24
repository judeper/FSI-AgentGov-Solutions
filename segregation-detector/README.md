---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P3, P4]
applicable_drivers:
  - ai_governance
  - technology_data
coe_function: govern
---
# Segregation of Duties Detector

> **Version:** v1.2.1
> **Status:** Live
> **Validated against framework version:** v1.6.0

Automated role conflict detection that supports Maker/Checker controls in AI agent deployment pipelines, helping address SOX Section 404 IT General Controls.

## Overview

The Segregation of Duties (SoD) Detector identifies users who hold incompatible role combinations in the AI agent development and deployment lifecycle. It supports the principle that no single individual should control all phases of a critical process. The shipped scripts perform detection and reporting; runtime pipeline gating and real-time alerts are roadmap items (see Features table).

## Features

| Feature | Description |
|---------|-------------|
| **Role Conflict Detection** | Identifies users with incompatible role combinations |
| **Real-Time Alerts** | Immediate notification when violations are detected (planned) |
| **Exception Workflow** | Documented approval process for justified exceptions |
| **Pipeline Integration** | Blocks promotions when SoD violations exist via `Invoke-SoDScan.ps1` exit code (CI gate); native ALM-pipeline pre-deploy hook is planned |
| **Audit Reporting** | Quarterly SoD compliance reports for auditors |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│                    Segregation Detector                          │
├─────────────────────────────────────────────────────────────────┤
│  Role Analyzer  │  Conflict Engine  │  Exception Mgr  │ Reports │
└─────────────────┴───────────────────┴─────────────────┴─────────┘
                              ▲
                              │ Analysis
                              │
┌─────────────────────────────────────────────────────────────────┐
│                    Dataverse (SoD Hub)                           │
├───────────────┬───────────────┬───────────────┬─────────────────┤
│ Conflict      │ SoD           │ Exception     │ Audit           │
│ Rules         │ Violations    │ Requests      │ Log             │
└───────────────┴───────────────┴───────────────┴─────────────────┘
                              ▲
                              │ Data Sources
                              │
┌─────────────┬───────────────┬───────────────┬───────────────────┐
│ Entra ID    │ Power Platform│ Dataverse     │ Environment       │
│ Role        │ Environment   │ Security      │ Lifecycle         │
│ Assignments │ Roles         │ Roles         │ Management        │
└─────────────┴───────────────┴───────────────┴───────────────────┘
```

## Conflict Categories

### Category 1: Maker/Checker Conflicts

Same user cannot both create and approve in the same workflow.

| Maker Role | Context | Checker Role | Context | Risk |
|------------|---------|--------------|---------|------|
| Agent Developer | 4 - DV Sec | Pipeline Approver | 4 - DV Sec | Self-approval of changes |
| Solution Developer | 4 - DV Sec | Solution Promoter | 4 - DV Sec | Unreviewed deployments |
| Flow Creator | 4 - DV Sec | Flow Approver | 4 - DV Sec | Bypass change management |
| DLP Policy Author | 3 - PP Env | DLP Policy Approver | 3 - PP Env | Self-exemption from DLP policies |
| Connection Creator | 4 - DV Sec | Connection Approver | 4 - DV Sec | Unreviewed connection approval |

### Category 2: Segregation Conflicts

Roles that should never be held by the same person.

| Role A | Context | Role B | Context | Risk |
|--------|---------|--------|---------|------|
| System Administrator | 4 - DV Sec | Agent Publisher | 4 - DV Sec | Admin promotes own work |
| Security Administrator | 1 - Entra | Agent Developer | 4 - DV Sec | Security/development overlap |
| Compliance Administrator | 1 - Entra | Agent Developer | 4 - DV Sec | Compliance/development overlap |
| Environment Creator | 3 - PP Env | Environment Approver | 3 - PP Env | Environment lifecycle overlap |
| Data Steward | 4 - DV Sec | Data Consumer | 4 - DV Sec | Data access separation |

### Category 3: Privileged Access Conflicts

High-privilege roles that require additional controls.

| Privileged Role | Context | Incompatible With | Context | Risk |
|-----------------|---------|-------------------|---------|------|
| Global Administrator | 1 - Entra | Agent Developer | 4 - DV Sec | God mode abuse |
| Power Platform Administrator | 1 - Entra | Basic User | 4 - DV Sec | Admin as user |
| Privileged Role Administrator | 1 - Entra | Application Administrator | 1 - Entra | Privilege escalation |
| Break-Glass Account | 1 - Entra | Basic User | 4 - DV Sec | Emergency access misuse |

> **Context values:** 1 = Entra ID Directory Role, 3 = Power Platform Environment Role, 4 = Dataverse Security Role. See [conflict-rules.md](docs/conflict-rules.md) for all context codes.

## Prerequisites

### Licensing

| Requirement | Purpose |
|-------------|---------|
| Power Platform admin access | Environment and role enumeration for detection scripts |
| Dataverse capacity | Conflict tracking storage |
| Microsoft Entra ID P1+ | Role assignment queries |

### Permissions

| Role | Required For |
|------|--------------|
| Global Reader | Entra ID role queries |
| Power Platform Administrator | Environment role queries |
| System Administrator (Dataverse) | Table creation and access |

### Dependencies

| Solution | Version | Purpose |
|----------|---------|---------|
| Environment Lifecycle Management | v1.1.0+ | Environment context (optional) |

## Quick Start

### 1. Deploy Dataverse Schema

Use [docs/dataverse-schema.md](docs/dataverse-schema.md), regenerated from `scripts/create_sd_dataverse_schema.py`, to create tables with the exact SchemaNames, logical names, and choice values required by the scripts.

### 2. Configure Conflict Rules

Load the default conflict rule set:

```powershell
.\scripts\Import-ConflictRules.ps1 -Environment "https://your-org.crm.dynamics.com" -AuthMode ManagedIdentity
```

### 3. Run Initial Scan

```powershell
.\scripts\Invoke-SoDScan.ps1 -Environment "https://your-org.crm.dynamics.com" -AuthMode ManagedIdentity -Verbose
```

### 4. Review Results

Review scan output for detected conflicts. A Power Apps dashboard for visual review is planned for a future release.

## Documentation

| Document | Description |
|----------|-------------|
| [Prerequisites](docs/prerequisites.md) | Licensing and permission requirements |
| [Dataverse Schema](docs/dataverse-schema.md) | Table definitions |
| [Conflict Rules](docs/conflict-rules.md) | Rule configuration guide |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and solutions |

### Scripts

| Script | Description |
|--------|-------------|
| `scripts/Invoke-SoDScan.ps1` | Scans for SoD violations across Entra ID, Power Platform, and Dataverse |
| `scripts/Import-ConflictRules.ps1` | Imports conflict rule sets into Dataverse |
| `scripts/create_sd_dataverse_schema.py` | Generates the Dataverse schema reference used as the table and choice-value source of truth |
| `scripts/SoDShared.ps1` | Shared helper module (`Invoke-WithRetry`, `Get-AccessToken`, `Get-LoginEndpoint`, `Get-GraphEndpoint`, `Get-BapApiBaseUrl`) dot-sourced by both scripts |

## Detection Process

### Scheduled Scan (Daily)

1. Query all user role assignments from Entra ID
2. Query Power Platform environment roles
3. Query Dataverse security roles
4. Compare against conflict rules matrix
5. Generate violations for new conflicts
6. Update status for resolved conflicts (planned)
7. Send summary report (planned)

### Real-Time Detection (Planned)

1. Monitor role assignment changes via Graph API webhooks
2. Evaluate change against conflict rules
3. If violation detected:
   - Create violation record
   - Send immediate alert
   - Optionally block assignment (if integrated)

### Pipeline Gate (Planned — On Promotion)

1. Before agent promotion, query user roles
2. Check if promoter has maker role for same agent
3. If conflict exists:
   - Block promotion
   - Require different approver
   - Or verify approved exception exists

## Exception Management

### Exception Types

| Type | Duration | Approval Level |
|------|----------|----------------|
| **Emergency** | 24 hours | Manager + Compliance |
| **Temporary** | 30 days | Director + Compliance |
| **Permanent** | Annual review | VP + Legal + Compliance |

### Exception Workflow

```
Request → Manager Review → Compliance Review → Approval/Denial
                ↓                   ↓
           Document             Document
           Justification        Risk Acceptance
```

### Required Documentation

- Business justification
- Compensating controls
- Monitoring plan
- Review schedule
- Risk acceptance signature

## Reports

### Daily Violation Summary

- New violations detected
- Violations resolved
- Open violation count by category
- High-risk users (multiple violations)

### Quarterly Audit Report

- Total violations by period
- Exception utilization
- Trend analysis
- Remediation effectiveness
- Recommendations

### On-Demand User Report

- All roles for specific user
- Active conflicts
- Exception status
- Historical violations

## Integration Points

### Environment Lifecycle Management

When ELM provisions a new environment:
1. SoD Detector receives notification
2. Scans initial role assignments
3. Validates no conflicts before activation

### Pipeline Governance

Before pipeline promotion:
1. SoD Detector validates promoter
2. Confirms no maker/checker conflict
3. Returns pass/fail to pipeline

### FINRA Supervision Workflow

For supervision queue assignments:
1. Validates supervisor isn't also the agent developer
2. Supports independent review

## Regulatory Alignment

### SOX Section 404 - IT General Controls

| ITGC Category | SoD Detector Coverage |
|---------------|----------------------|
| Access Controls | Role assignment monitoring |
| Change Management | Supports Maker/Checker via detection |
| Segregation of Duties | Conflict detection (native runtime blocking in Power Platform pipelines is planned) |

### COSO Framework

| Component | Coverage |
|-----------|----------|
| Control Activities | Detection of role-based SoD conflicts |
| Information & Communication | Alert notifications |
| Monitoring Activities | Continuous detection |

### OCC Heightened Standards

| Requirement | Coverage |
|-------------|----------|
| Risk Management | Conflict risk identification |
| Internal Controls | Detection feeding into manual remediation |
| Audit Trail | Complete violation history |

## Related Controls

| Control | Relationship |
|---------|--------------|
| [2.8 - Access Control and Segregation of Duties](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.8-access-control-and-segregation-of-duties.md) | Primary — role conflict detection supporting Maker/Checker controls |
| [2.1 - Managed Environments](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.1-managed-environments.md) | Environment role context |
| [2.3 - Change Management](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.3-change-management-and-release-planning.md) | Pipeline integration |

## Platform Update Notes

### Power Platform RBAC REST API (April 2026)

Microsoft has introduced new [REST API endpoints for RBAC role assignments](https://learn.microsoft.com/en-us/rest/api/power-platform/authorization/role-based-access-control) in the Power Platform, including:

- **RBAC role assignment management** — Create, list, and delete role assignments for users, groups, and service principals at tenant, environment group, or environment scope
- **Copilot agent reassignment** — Programmatic transfer of agent ownership
- **Built-in roles** — Power Platform Owner, Contributor, Reader, RBAC Administrator

**Impact on this solution:** These new API endpoints provide a more comprehensive source of role assignment data than the current Graph API + PowerShell cmdlet approach used by `Invoke-SoDScan.ps1`. Future enhancements should consider:

- Querying the RBAC REST API for environment-scoped role assignments to supplement Entra ID directory role queries
- Adding conflict rules for the new built-in Power Platform RBAC roles (Owner, Contributor, RBAC Administrator)
- Monitoring agent reassignment events as potential SoD bypass vectors

> **Note:** The RBAC REST API is currently in preview. Monitor [Microsoft documentation](https://learn.microsoft.com/en-us/rest/api/power-platform/) for GA availability before production integration.

## Known Limitations

| Limitation | Description |
|------------|-------------|
| **No solution package** | No managed/unmanaged ZIP or `solution.xml` is included. Dataverse tables must be created manually per [dataverse-schema.md](docs/dataverse-schema.md). |
| **GCC environments** | GCC environments (`crm9.dynamics.com`) are not supported because the BAP API endpoint for GCC is undetermined. Commercial (`crm.dynamics.com`), GCC High (`crm.microsoftdynamics.us`), EMEA (`crm4`), APAC (`crm5`), and other commercial regions are supported. |
| **No token refresh** | Access tokens expire after ~60 minutes. In large tenants, scans may exceed this duration, causing 401 failures partway through. `Invoke-WithRetry` does not retry 401 errors and no re-authentication is attempted. For large environments, consider splitting scans or refreshing tokens externally. |
| **No batch violation creation** | `New-Violation` creates individual Dataverse records via separate POST calls. Using the Dataverse `$batch` endpoint would reduce API round-trips and allow atomic creation. For environments with many new violations, this may cause throttling. |
| **No automated tests** | PowerShell scripts do not have a Pester test suite. Validate with `-DryRun` before production use. Contributions welcome. |
| **Console-only audit log** | `Write-AuditLog` writes via `Write-Host`, which bypasses the PowerShell pipeline and **cannot be redirected** with `6>&1` to capture for SIEM ingestion. The shipped script does not persist records to the `fsi_sodauditlog` Dataverse table either. To get a durable audit trail you must rewrite `Write-AuditLog` to use `Write-Information -InformationAction Continue` (or `Write-Output` of structured objects) and capture the stream, or POST directly to `fsi_sodauditlogs` when not in `-DryRun`. |
| **PIM-eligible roles not evaluated** | Active Entra role assignments are queried through Microsoft Graph v1.0 `/roleManagement/directory/roleAssignmentScheduleInstances`, including active PIM assignment instances. Users who are PIM-eligible but not currently activated for conflicting roles are **not** detected. To cover this gap, separately query `/roleManagement/directory/roleEligibilityScheduleInstances?$expand=principal` and merge the results, or document that eligibility activations must be reviewed through Entra PIM access reviews. |
| **Unsupported role contexts** | Entra ID App Role assignments and Custom Application Roles are not queried. Rules targeting these contexts will not match. |
| **Group-based role assignments** | Entra ID role assignments through security groups are not expanded. Only direct user assignments are evaluated. Users who inherit conflicting roles via group membership will not be detected. |
| **No auto-reconciliation** | Violations are not automatically closed when the underlying role conflict is removed. Stale violations accumulate with status "Open" until manually resolved. |
| **Expired exception blindness** | Violations with approved exceptions are not re-flagged after the exception's expiration date passes. Periodically query `fsi_sodexception` for records where `fsi_expirationdate < today` and `fsi_status = 100000003` (Approved) to identify stale exceptions requiring review. |

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.2.1 | 2026-05-23 | Council-review remediation: ASCII punctuation sweep, doc cleanup, CHANGELOG finalization (see CHANGELOG) |
| 1.2.0 | 2026-05-12 | Microsoft Learn refresh: managed-identity-first auth, Graph PIM schedule instances, schema source of truth |
| 1.1.0 | April 2026 | Council review fixes |
| 1.0.0 | February 2026 | Initial release |

## Troubleshooting

### Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Authentication failure | Expired token or workload identity permissions | Re-authenticate; verify Global Reader and Power Platform Administrator roles plus required Graph application permissions |
| No conflict rules found | Rules not imported or all disabled | Run `Import-ConflictRules.ps1`; verify `fsi_enabled` is `true` in Dataverse |
| Empty scan results | No active role assignment schedule instances returned from Graph API | Check the identity has `RoleAssignmentSchedule.Read.Directory`, `RoleManagement.Read.Directory`, and `Directory.Read.All` (or higher privileged Graph permissions) |
| Violation creation fails | Dataverse schema missing or permission denied | Create tables per [dataverse-schema.md](docs/dataverse-schema.md); verify System Administrator role on Dataverse |

### Logs

Review script output for `[WARN]` audit log entries and red-highlighted error messages. Enable verbose output with `-Verbose` flag.

## Support

For issues and feature requests, see the [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues) repository.

---

*FSI Agent Governance Framework - Segregation of Duties Detector v1.2.1*
