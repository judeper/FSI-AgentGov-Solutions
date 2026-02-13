# Audit Logging Compliance Automation

> **Status:** v1.0.0 — In Development

Automated detection and remediation of Microsoft 365 and Power Platform audit logging compliance gaps. Supports compliance with US financial services regulations through enterprise-grade Azure Automation runbooks with Managed Identity authentication.

## What This Solution Does

- **Detects** Purview unified audit and Dataverse audit configuration status across all Power Platform environments
- **Remediates** non-compliant environments by enabling org-level and entity-level Dataverse auditing
- **Tracks** compliance status in Dataverse with upsert-based record management
- **Notifies** governance teams via email with compliance summaries and CSV reports
- **Supports** approval-gated remediation via Power Automate

**This solution complements the Audit Configuration Validator (ACV v1.0.0)** — ACV validates configurations with drift detection and SHA-256 evidence; ALCA detects gaps and remediates them with automated approval workflows.

## Prerequisites

### Licensing

| License | Purpose |
|---------|---------|
| Microsoft 365 E3/E5 | Unified Audit Log access |
| Power Platform Admin | Environment enumeration, audit settings |
| Power Apps Premium | Dataverse compliance tracking table |
| Azure Automation | Runbook hosting with Managed Identity |

### Roles Required

| Role | Purpose |
|------|---------|
| Power Platform Admin | Environment enumeration, audit configuration |
| Exchange Online Admin | Unified audit log status, Search-UnifiedAuditLog |
| Entra Global Admin | Managed Identity role assignments |
| System Administrator | Dataverse Application User in target environments |

### Runtime Requirements

| Component | Version |
|-----------|---------|
| PowerShell | 7.2+ |
| Microsoft.PowerApps.Administration.PowerShell | 2.0+ |
| ExchangeOnlineManagement | 3.0+ |
| Azure Automation Runtime | 7.2 |

## Components

| Component | File | Purpose |
|-----------|------|---------|
| Helper Module | `src/AuditComplianceHelpers.psm1` | Shared functions (retry, MI auth, Dataverse, email) |
| Module Manifest | `src/AuditComplianceHelpers.psd1` | Module metadata and exports |
| Detection Runbook | `src/Check-AuditLoggingCompliance.ps1` | Scan environments for audit compliance |
| Remediation Runbook | `src/Enable-AuditLogging.ps1` | Enable auditing on non-compliant environments |
| Schema Script | `src/create_audit_compliance_schema.py` | Dataverse table creation |
| Approval Flow | `src/audit-remediation-approval-flow.json` | Power Automate approval template |
| Unit Tests | `src/AuditComplianceHelpers.Tests.ps1` | Pester 5 tests for helper module |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Helper Module: AuditComplianceHelpers.psm1                     │
│  - Invoke-WithRetry (exponential backoff + jitter)              │
│  - Get-ManagedIdentityToken (Azure Automation MI)               │
│  - Get-DataverseToken (Dataverse-specific token)                │
│  - Invoke-DataverseRequest (Web API wrapper)                    │
│  - Write-DataverseComplianceRecord (upsert pattern)             │
│  - Send-ComplianceNotification (Graph sendMail)                 │
└─────────────────────────────────────────────────────────────────┘
                           │
              ┌────────────┴────────────┐
              ▼                         ▼
┌──────────────────────────┐  ┌──────────────────────────┐
│  Detection Runbook       │  │  Remediation Runbook     │
│  Check-AuditLogging...   │  │  Enable-AuditLogging...  │
│  - MI Auth               │  │  - MI Auth               │
│  - Environment scanning  │  │  - Org-level enablement  │
│  - Compliance checks     │  │  - Entity-level enablement│
│  - Dataverse upsert      │  │  - Validation            │
│  - Email notification    │  │  - WhatIf support        │
└──────────────────────────┘  └──────────────────────────┘
              │                         │
              ▼                         ▼
┌─────────────────────────────────────────────────────────────────┐
│  Dataverse: fsi_auditenvironmentcompliance                      │
│  - Upsert by fsi_environmentid                                  │
│  - Status: Compliant / Non-Compliant / Remediation Pending      │
└─────────────────────────────────────────────────────────────────┘
```

## Related Controls

This solution helps support implementation of:

- **Control 1.7** — Comprehensive Audit Logging and Compliance
  - Automated detection of Purview unified audit and Dataverse audit status
  - Remediation with entity-level audit enablement for Copilot Studio entities
  - Compliance tracking via Dataverse with upsert-based record management
  - Governance-approved remediation via Power Automate approval workflow

## Relationship to ACV

| Capability | ACV (v1.0.0) | ALCA (v1.0.0) |
|------------|-------------|---------------|
| Configuration validation | ✅ Zone-based thresholds | ✅ Purview + Dataverse status |
| Drift detection | ✅ SHA-256 evidence | — |
| Remediation | — | ✅ Automated enablement |
| Entity-level audit | — | ✅ 6 Copilot Studio entities |
| Auth model | Certificate-based | Managed Identity |
| Data pattern | Immutable history | Upsert per environment |
| Approval workflow | — | ✅ Power Automate |

## Documentation

- [Deployment Guide](./docs/deployment-guide.md) — Azure Automation setup, MI permissions
- [Scheduling Guide](./docs/scheduling-guide.md) — Runbook scheduling configuration
- [Testing Scenarios](./docs/testing-scenarios.md) — 15 test scenarios with verification
- [Troubleshooting](./docs/troubleshooting.md) — 10 common issues and resolutions

## Security Considerations

- **NEVER** uses interactive authentication or hardcoded credentials
- System-Assigned Managed Identity provides enterprise-grade auth
- Dataverse Application User with least-privilege System Administrator role
- Shared mailbox for email notifications (no user mailbox access)
- WhatIf mode for safe remediation dry runs

## Version History

See [CHANGELOG.md](./CHANGELOG.md) for detailed release notes.
