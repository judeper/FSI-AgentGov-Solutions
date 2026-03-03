# Segregation of Duties Detector

> **Status:** Validated

Automated role conflict detection for Maker/Checker enforcement in AI agent deployment pipelines, supporting SOX 404 IT General Controls.

## Overview

The Segregation of Duties (SoD) Detector identifies and prevents conflicts where users have incompatible roles in the AI agent development and deployment lifecycle. It enforces the principle that no single individual should control all phases of a critical process.

## Features

| Feature | Description |
|---------|-------------|
| **Role Conflict Detection** | Identifies users with incompatible role combinations |
| **Real-Time Alerts** | Immediate notification when violations are detected (planned) |
| **Exception Workflow** | Documented approval process for justified exceptions |
| **Pipeline Integration** | Blocks promotions when SoD violations exist (planned) |
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
| Power Platform Premium | PowerShell detection scripts; Power Automate flows (planned) |
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

Create tables manually using [docs/dataverse-schema.md](docs/dataverse-schema.md).

### 2. Configure Conflict Rules

Load the default conflict rule set:

```powershell
.\scripts\Import-ConflictRules.ps1 -Environment "https://your-org.crm.dynamics.com"
```

### 3. Run Initial Scan

```powershell
.\scripts\Invoke-SoDScan.ps1 -Environment "https://your-org.crm.dynamics.com" -Verbose
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
2. Ensures independent review

## Regulatory Alignment

### SOX 404 - IT General Controls

| ITGC Category | SoD Detector Coverage |
|---------------|----------------------|
| Access Controls | Role assignment monitoring |
| Change Management | Maker/checker enforcement |
| Segregation of Duties | Conflict detection and prevention |

### COSO Framework

| Component | Coverage |
|-----------|----------|
| Control Activities | Automated SoD enforcement |
| Information & Communication | Alert notifications |
| Monitoring Activities | Continuous detection |

### OCC Heightened Standards

| Requirement | Coverage |
|-------------|----------|
| Risk Management | Conflict risk identification |
| Internal Controls | Automated enforcement |
| Audit Trail | Complete violation history |

## Related Controls

| Control | Relationship |
|---------|--------------|
| [2.1 - Managed Environments](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.1-managed-environments.md) | Environment role context |
| [2.3 - Change Management](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-2-management/2.3-change-management-and-release-planning.md) | Pipeline integration |
| [1.18 - Application-Level RBAC](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.18-application-level-role-based-access-control.md) | Role definitions |

## Known Limitations

| Limitation | Description |
|------------|-------------|
| **No solution package** | No managed/unmanaged ZIP or `solution.xml` is included. Dataverse tables must be created manually per [dataverse-schema.md](docs/dataverse-schema.md). |
| **GCC environments** | GCC environments (`crm9.dynamics.com`) are not supported because the BAP API endpoint for GCC is undetermined. Commercial (`crm.dynamics.com`), GCC High (`crm.microsoftdynamics.us`), EMEA (`crm4`), APAC (`crm5`), and other commercial regions are supported. |
| **No token refresh** | Access tokens expire after ~60 minutes. In large tenants, scans may exceed this duration, causing 401 failures partway through. `Invoke-WithRetry` does not retry 401 errors and no re-authentication is attempted. For large environments, consider splitting scans or refreshing tokens externally. |
| **No batch violation creation** | `New-Violation` creates individual Dataverse records via separate POST calls. Using the Dataverse `$batch` endpoint would reduce API round-trips and allow atomic creation. For environments with many new violations, this may cause throttling. |
| **No automated tests** | PowerShell scripts do not have a Pester test suite. Validate with `-DryRun` before production use. Contributions welcome. |
| **Console-only audit log** | `Write-AuditLog` outputs structured logs to the console but does not persist records to the `fsi_sodauditlog` Dataverse table. A persistent audit trail requires manual log forwarding (e.g., to Azure Monitor or a SIEM). |
| **Unsupported role contexts** | Entra ID App Role assignments (context 2) and Custom Application Roles (context 5) are not queried. Rules targeting these contexts will not match. |
| **Group-based role assignments** | Entra ID role assignments through security groups are not expanded. Only direct user assignments are evaluated. Users who inherit conflicting roles via group membership will not be detected. |
| **No auto-reconciliation** | Violations are not automatically closed when the underlying role conflict is removed. Stale violations accumulate with status "Open" until manually resolved. |
| **Expired exception blindness** | Violations with approved exceptions (status 4) are not re-flagged after the exception's expiration date passes. Periodically query `fsi_sodexception` for records where `fsi_expirationdate < today` and `fsi_status = 4` to identify stale exceptions requiring review. |

## Version History

| Version | Date | Changes |
|---------|------|---------|
| 1.0.0 | February 2026 | Initial release |

## Troubleshooting

### Common Issues

| Issue | Cause | Resolution |
|-------|-------|------------|
| Authentication failure | Expired token or wrong service principal permissions | Re-authenticate; verify Global Reader and Power Platform Administrator roles |
| No conflict rules found | Rules not imported or all disabled | Run `Import-ConflictRules.ps1`; verify `fsi_enabled` is `true` in Dataverse |
| Empty scan results | No role assignments returned from Graph API | Check service principal has `Directory.Read.All` permission |
| Violation creation fails | Dataverse schema missing or permission denied | Create tables manually per [dataverse-schema.md](docs/dataverse-schema.md); verify System Administrator role on Dataverse |

### Logs

Review script output for `[WARN]` audit log entries and red-highlighted error messages. Enable verbose output with `-Verbose` flag.

## Support

For issues and feature requests, see the [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues) repository.

---

*FSI Agent Governance Framework - Segregation of Duties Detector v1.0.0*
