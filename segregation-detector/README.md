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
│ Conflict      │ User Role     │ Exception     │ Audit           │
│ Rules         │ Assignments   │ Requests      │ Log             │
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

| Maker Role | Checker Role | Risk |
|------------|--------------|------|
| Agent Developer | Pipeline Approver | Self-approval of changes |
| Solution Developer | Solution Promoter | Unreviewed deployments |
| Flow Creator | Flow Approver | Bypass change management |
| Connection Creator | Connection Approver | Unapproved connections |
| DLP Policy Author | DLP Policy Approver | Self-exemption |

### Category 2: Segregation Conflicts

Roles that should never be held by the same person.

| Role A | Role B | Risk |
|--------|--------|------|
| Environment Admin | Agent Publisher | Admin promotes own work |
| Security Admin | Agent Developer | Security role separation |
| Compliance Admin | Agent Developer | Compliance role separation |
| Environment Creator | Environment Approver | Environment lifecycle separation |
| Data Steward | Data Consumer (sensitive) | Data access separation |

### Category 3: Privileged Access Conflicts

High-privilege roles that require additional controls.

| Privileged Role | Incompatible With | Risk |
|-----------------|-------------------|------|
| Global Admin | Any maker role | God mode abuse |
| Power Platform Admin | End user in same env | Admin as user |
| Privileged Role Admin | Application Admin | Privilege escalation prevention |
| Break-Glass Account | Any Non-Emergency Use | Emergency access only |

## Prerequisites

### Licensing

| Requirement | Purpose |
|-------------|---------|
| Power Platform Premium | Power Automate flows |
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

> **Note:** This release includes PowerShell scripts for scanning and rule import only.
> A deployable Power Platform solution package (solution.xml, customizations.xml, security
> role definitions, and detection flows) is planned for a future release. For now, create
> the Dataverse tables manually using the schema documentation below.

```powershell
# Create tables manually using docs/dataverse-schema.md
# Solution package import will be available in a future release.
```

Or create tables manually using [docs/dataverse-schema.md](docs/dataverse-schema.md).

### 2. Configure Conflict Rules

Load the default conflict rule set:

```powershell
.\scripts\Import-ConflictRules.ps1 -Environment "https://your-org.crm.dynamics.com"
```

### 3. Run Initial Scan

```powershell
.\scripts\Invoke-SoDScan.ps1 -Environment "https://your-org.crm.dynamics.com" -Verbose
```

### 4. Deploy Power Automate Flows

Flow configuration documentation is planned for a future release.
<!-- See [docs/flow-configuration.md](docs/flow-configuration.md) for flow setup. -->

### 5. Review Results

Open the SoD Detector dashboard in Power Apps to review detected conflicts.

## Documentation

| Document | Description |
|----------|-------------|
| [Prerequisites](docs/prerequisites.md) | Licensing and permission requirements |
| [Dataverse Schema](docs/dataverse-schema.md) | Table definitions |
| [Conflict Rules](docs/conflict-rules.md) | Rule configuration guide |
| Flow Configuration | Power Automate setup (planned) |
| Exception Workflow | Managing justified exceptions (planned) |
| [Troubleshooting](docs/troubleshooting.md) | Common issues and solutions |

## Detection Process

### Scheduled Scan (Daily)

1. Query all user role assignments from Entra ID
2. Query Power Platform environment roles
3. Compare against conflict rules matrix
4. Generate violations for new conflicts
5. Send summary report

> **Note:** Dataverse security role scanning (step 3 in architecture) and automatic resolution of stale violations are planned for a future release.
> Audit log writing to `fsi_sodauditlog` is not yet implemented — `Write-AuditLog` currently outputs to console only.

### Known Limitations

| Limitation | Impact | Status |
|------------|--------|--------|
| **Dataverse Security Role scanning (context=4)** | 11 of 14 default rules reference Dataverse Security Roles; these rules will not match until context=4 scanning is implemented | Planned |
| **Audit log persistence** | Scan events and violation detections are logged to console only, not written to `fsi_sodauditlog` in Dataverse | Planned |
| **Stale violation auto-resolution** | When a conflicting role is removed, the corresponding violation record remains open indefinitely; manual resolution required | Planned |
| **Power Automate flows** | Real-time detection (Graph API webhooks), scheduled scan automation, and pipeline-gate integration require flows not yet included | Planned |

### Real-Time Detection

1. Monitor role assignment changes via Graph API webhooks
2. Evaluate change against conflict rules
3. If violation detected:
   - Create violation record
   - Send immediate alert
   - Optionally block assignment (if integrated)

### Pipeline Gate (On Promotion)

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
| Violation creation fails | Dataverse schema missing or permission denied | Import solution package; verify System Administrator role on Dataverse |

### Logs

Review script output for `[ERROR]` entries. Enable verbose output with `-Verbose` flag.

## Support

For issues and feature requests, see the [FSI-AgentGov-Solutions](https://github.com/judeper/FSI-AgentGov-Solutions/issues) repository.

---

*FSI Agent Governance Framework - Segregation of Duties Detector v1.0.0*
