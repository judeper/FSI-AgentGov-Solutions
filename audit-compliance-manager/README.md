# Audit Compliance Manager (ACM)

> **Status:** Completed

Unified audit compliance solution for Microsoft 365 and Power Platform environments. Consolidates the Audit Configuration Validator (ACV) and Audit Logging Compliance Automation (ALCA) into a single solution that validates audit configurations, detects compliance gaps, and remediates non-compliant environments.

> **Note:** This solution was formed by merging ACV v1.0.0 and ALCA v1.0.0. See [CHANGELOG.md](./CHANGELOG.md) for history.

## Prerequisites

### 1. Licensing

| License | Purpose |
|---------|---------|
| Microsoft 365 E3/E5 | Unified Audit Log, mailbox auditing |
| Purview Compliance | Retention policies, advanced audit features |
| Power Platform Admin | Environment enumeration, audit settings |
| Power Apps Premium | Dataverse tables for validation and compliance tracking |
| Azure Automation | Runbook hosting with Managed Identity (ALCA remediation) |

### 2. Roles Required

| Role | Purpose |
|------|---------|
| Exchange Online Admin | Unified Audit Log configuration, Search-UnifiedAuditLog |
| Purview Compliance Admin | Purview retention policy access |
| Power Platform Admin | Environment enumeration, audit configuration |
| Entra Global Admin | Managed Identity role assignments |
| System Administrator | Dataverse table creation, security roles |

### 3. Python Environment

```bash
# Python 3.10 or later required
python --version

# Install dependencies
pip install -r scripts/requirements.txt
```

### 4. Runtime Requirements

| Component | Version |
|-----------|---------|
| PowerShell | 7.2+ |
| Microsoft.PowerApps.Administration.PowerShell | 2.0+ |
| ExchangeOnlineManagement | 3.0+ |
| Azure Automation Runtime | 7.2 (for ALCA remediation runbooks) |

## What This Solution Does

### Audit Configuration Validation (from ACV)

- **Validates** tenant-level audit configuration (Unified Audit Log, mailbox audit)
- **Validates** environment-level audit configuration (Power Platform audit retention)
- **Classifies** validation results by zone (Zone 1: 180d, Zone 2: 365d, Zone 3: 730d)
- **Stores** validation history in Dataverse (immutable, append-only)
- **Detects** grace period violations (newly enabled audit configs)
- **Tracks** environment registry with zone classification and override capability
- **Exports** compliance evidence to JSON with SHA-256 integrity hashing
- **Verifies** evidence file integrity for audit examination submissions

### Audit Logging Compliance Automation (from ALCA)

- **Detects** Purview unified audit and Dataverse audit configuration status across all Power Platform environments
- **Remediates** non-compliant environments by enabling org-level and entity-level Dataverse auditing
- **Tracks** compliance status in Dataverse with upsert-based record management
- **Notifies** governance teams via email with compliance summaries and CSV reports
- **Supports** approval-gated remediation via Power Automate

**This is an audit compliance solution** — it helps organizations maintain and remediate audit configurations that support compliance with FINRA 4511, SEC 17a-3/4, and SOX 404.

## Quick Start

### Step 1: Deploy Dataverse Infrastructure (ACV)

```bash
# Dry run first to preview changes
python scripts/deploy.py \
    --environment-url https://org.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --interactive \
    --dry-run

# Full deployment
python scripts/deploy.py \
    --environment-url https://org.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --interactive
```

The deployment script creates:
- Global option sets (Severity, Scope, Zone, Environment Status, Environment Type)
- AuditValidationHistory table (org-owned, immutable)
- EnvironmentRegistry table (org-owned, admin-managed)
- Environment variables for zone thresholds (180d/365d/730d)
- Connection references for Dataverse and Office 365

### Step 2: Deploy ALCA Compliance Schema

```python
# Create the audit environment compliance tracking table
python scripts/create_audit_compliance_schema.py \
    --environment-url https://org.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --interactive
```

### Step 3: Run Tenant-Level Validation

```powershell
# Validate tenant audit configuration for Zone 3 (730-day retention)
.\scripts\Invoke-TenantAuditValidation.ps1 -Zone 3 -Verbose

# With JSON output for automation
.\scripts\Invoke-TenantAuditValidation.ps1 -Zone 3 -OutputPath .\results.json
```

### Step 4: Register and Validate Environments

```powershell
# Discover and register all Power Platform environments
.\scripts\Invoke-EnvironmentDiscovery.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId "<your-tenant-id>" `
    -Interactive

# Validate all registered environments
.\scripts\Invoke-EnvironmentAuditValidation.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId "<your-tenant-id>" `
    -Interactive
```

### Step 5: Run Compliance Detection (ALCA)

```powershell
# Detect audit logging compliance gaps across environments
.\scripts\Check-AuditLoggingCompliance.ps1
```

### Step 6: Remediate Non-Compliant Environments (ALCA)

```powershell
# Dry run remediation
.\scripts\Enable-AuditLogging.ps1 -WhatIf

# Execute remediation
.\scripts\Enable-AuditLogging.ps1
```

### Step 7: Export Compliance Evidence

```powershell
# Export last 30 days of tenant validation evidence
.\scripts\Export-AuditValidationEvidence.ps1 `
    -DataverseUrl https://org.crm.dynamics.com `
    -TenantId <your-tenant-id> `
    -Scope Tenant `
    -OutputDirectory .\exports `
    -Interactive

# Verify evidence integrity
.\scripts\Test-EvidenceIntegrity.ps1 -EvidenceFilePath .\exports\tenant-validation-20260206-143500.json
```

## Zone Requirements

Zone classification determines minimum audit retention thresholds:

| Zone | Retention | Scope | Typical Use Cases |
|------|-----------|-------|-------------------|
| Zone 1 | 180 days | Personal Productivity | Individual developer environments, testing |
| Zone 2 | 365 days | Team Collaboration | Department applications, team agents |
| Zone 3 | 730 days | Enterprise Managed | Production agents, customer-facing AI |

Zone thresholds are configurable via Dataverse environment variables:
- `fsi_ACV_Zone1RetentionDays` (default: 180)
- `fsi_ACV_Zone2RetentionDays` (default: 365)
- `fsi_ACV_Zone3RetentionDays` (default: 730)

## Capability Matrix

| Capability | ACV Component | ALCA Component |
|------------|---------------|----------------|
| Configuration validation | ✅ Zone-based thresholds | ✅ Purview + Dataverse status |
| Drift detection | ✅ SHA-256 evidence | — |
| Remediation | — | ✅ Automated enablement |
| Entity-level audit | — | ✅ 6 Copilot Studio entities |
| Auth model | Certificate-based | Managed Identity |
| Data pattern | Immutable history | Upsert per environment |
| Approval workflow | — | ✅ Power Automate |
| Evidence export | ✅ JSON + SHA-256 | — |

## Data Model

### AuditValidationHistory Table (ACV)

Immutable validation results (organization-owned, append-only):

| Key Column | Type | Purpose |
|------------|------|---------|
| `fsi_name` | Text | ENV-{name}-{timestamp} or TENANT-{timestamp} |
| `fsi_runid` | GUID | Correlates all records in one execution |
| `fsi_scope` | Choice | Tenant or Environment |
| `fsi_environmentid` | Text | Power Platform environment ID (null for tenant scope) |
| `fsi_zone` | Choice | Zone at time of validation (denormalized) |
| `fsi_severity` | Choice | Passed, Warning, GracePeriod, Failed, Error |
| `fsi_validationtype` | Text | UnifiedAuditLog, MailboxAudit, PurviewRetention, etc. |
| `fsi_rawvalue` | Text | Actual config values |
| `fsi_reason` | Text | Human-readable explanation |
| `fsi_timestamp` | DateTime | When validation ran |

### EnvironmentRegistry Table (ACV)

Administrator-managed environment catalog:

| Key Column | Type | Purpose |
|------------|------|---------|
| `fsi_name` | Text | Environment display name |
| `fsi_environmentid` | Text | Power Platform environment GUID (unique) |
| `fsi_zone` | Choice | Assigned governance zone |
| `fsi_status` | Choice | Active or Inactive |
| `fsi_environmenttype` | Choice | Production, Sandbox, Developer, Trial, Default |
| `fsi_overrideinclude` | Boolean | Admin override to include Trial/Dev environments |
| `fsi_lastvalidated` | DateTime | Last successful validation timestamp |

### AuditEnvironmentCompliance Table (ALCA)

Compliance tracking with upsert by environment ID:

| Key Column | Type | Purpose |
|------------|------|---------|
| `fsi_environmentid` | Text | Power Platform environment GUID (alternate key) |
| `fsi_status` | Choice | Compliant, Non-Compliant, Remediation Pending |

## Components

### Scripts

| Component | File | Origin | Purpose |
|-----------|------|--------|---------|
| Dataverse Client (ACV) | `scripts/acv_client.py` | ACV | Web API client with MSAL auth |
| Dataverse Client (ALCA) | `scripts/alca_client.py` | ALCA | Web API client for compliance tracking |
| Schema Deployment | `scripts/create_dataverse_schema.py` | ACV | ACV tables and option sets |
| ALCA Schema | `scripts/create_audit_compliance_schema.py` | ALCA | Compliance tracking table |
| Environment Variables | `scripts/create_environment_variables.py` | ACV | Zone threshold configuration |
| Connection References | `scripts/create_connection_references.py` | ACV | Dataverse and Office 365 connectors |
| Deployment Orchestrator | `scripts/deploy.py` | ACV | Full ACV infrastructure deployment |
| Tenant Validation | `scripts/Invoke-TenantAuditValidation.ps1` | ACV | Orchestrates tenant-level checks |
| Environment Discovery | `scripts/Invoke-EnvironmentDiscovery.ps1` | ACV | Discovers Power Platform environments |
| Environment Validation | `scripts/Invoke-EnvironmentAuditValidation.ps1` | ACV | Validates environment audit configs |
| Evidence Export | `scripts/Export-AuditValidationEvidence.ps1` | ACV | JSON export with SHA-256 hashing |
| Evidence Integrity | `scripts/Test-EvidenceIntegrity.ps1` | ACV | Hash verification utility |
| Tenant Runbook | `scripts/Start-TenantValidationRunbook.ps1` | ACV | Azure Automation wrapper |
| Environment Runbook | `scripts/Start-EnvironmentValidationRunbook.ps1` | ACV | Azure Automation wrapper |
| Helper Module | `scripts/AuditComplianceHelpers.psm1` | ALCA | Shared functions (retry, MI auth, Dataverse, email) |
| Module Manifest | `scripts/AuditComplianceHelpers.psd1` | ALCA | Module metadata and exports |
| Detection Runbook | `scripts/Check-AuditLoggingCompliance.ps1` | ALCA | Scan environments for audit compliance |
| Remediation Runbook | `scripts/Enable-AuditLogging.ps1` | ALCA | Enable auditing on non-compliant environments |
| Unit Tests | `scripts/AuditComplianceHelpers.Tests.ps1` | ALCA | Pester 5 tests for helper module |

### Templates

| Template | Origin | Purpose |
|----------|--------|---------|
| `templates/tenant-validation-flow.json` | ACV | Daily tenant validation Power Automate flow |
| `templates/environment-validation-flow.json` | ACV | Daily environment validation Power Automate flow |
| `templates/adaptive-card-tenant-alert.json` | ACV | Teams card for tenant drift alerts |
| `templates/adaptive-card-environment-alert.json` | ACV | Teams card for environment drift alerts |
| `templates/audit-remediation-approval-flow.json` | ALCA | Approval-gated remediation Power Automate flow |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  ACV: Configuration Validation                                  │
│  Phase 1: PowerShell Validators (Tenant-Level)                  │
│  - Test-UnifiedAuditLog.ps1                                     │
│  - Test-MailboxAudit.ps1                                        │
│  - Test-PurviewRetention.ps1                                    │
│  - Invoke-TenantAuditValidation.ps1 (orchestrator)              │
│                                                                 │
│  Phase 2: Python Infrastructure (Environment-Level)             │
│  - deploy.py (Dataverse schema + env vars + connections)        │
│  - Invoke-EnvironmentDiscovery.ps1 / acv_client.py              │
│                                                                 │
│  Phase 3: Automated Orchestration & Alerting                    │
│  - Azure Automation runbooks + Power Automate flows             │
│  - Compare-ValidationBaseline.ps1 (drift detection)             │
│                                                                 │
│  Phase 4: Evidence Export                                       │
│  - Export-AuditValidationEvidence.ps1 (JSON + SHA-256)          │
│  - Test-EvidenceIntegrity.ps1 (hash verification)               │
└─────────────────────────────────────────────────────────────────┘

┌─────────────────────────────────────────────────────────────────┐
│  ALCA: Gap Detection & Remediation                              │
│  Helper Module: AuditComplianceHelpers.psm1                     │
│  - Invoke-WithRetry, Get-ManagedIdentityToken                   │
│  - Invoke-DataverseRequest, Send-ComplianceNotification         │
│                                                                 │
│  Detection: Check-AuditLoggingCompliance.ps1                    │
│  - MI Auth, environment scanning, Dataverse upsert              │
│                                                                 │
│  Remediation: Enable-AuditLogging.ps1                           │
│  - Org-level + entity-level audit enablement, WhatIf support    │
│                                                                 │
│  Approval: audit-remediation-approval-flow.json                 │
│  - Governance-approved remediation via Power Automate            │
└─────────────────────────────────────────────────────────────────┘
```

## Known Limitations

| Capability | Status | Script/Alternative |
|------------|--------|-------------------|
| Create Dataverse tables (ACV) | **Automated** | `deploy.py` |
| Create environment variables | **Automated** | `deploy.py` |
| Create connection references | **Automated** | `deploy.py` |
| Tenant-level validation | **Automated** | PowerShell scripts |
| Environment discovery | **Automated** | `Invoke-EnvironmentDiscovery.ps1` |
| Environment validation | **Automated** | `Invoke-EnvironmentAuditValidation.ps1` |
| Compliance detection (ALCA) | **Automated** | `Check-AuditLoggingCompliance.ps1` |
| Remediation (ALCA) | **Automated** | `Enable-AuditLogging.ps1` |
| Power Automate flows | **Template** | Import from JSON templates |
| Alerting configuration | **Template** | Configured via Power Automate flows |
| Evidence export | **Automated** | `Export-AuditValidationEvidence.ps1` |
| ALCA Dataverse schema | **Automated** | `create_audit_compliance_schema.py` |

## Who Should Use This

| Audience | Use Case |
|----------|----------|
| Platform Operations | Monitor audit configuration drift, remediate gaps |
| AI Governance Committee | Enforce zone-based audit retention |
| Compliance Teams | Validate regulatory audit requirements |
| Auditors | Export validation history for examinations |

## Configuration Placeholders

The following placeholder values in solution files must be replaced with your organization's values before deployment:

| Placeholder | Replace With | Files |
|------------|-------------|-------|
| `contoso.onmicrosoft.com` | Your tenant domain | `templates/environment-validation-flow.json`, `templates/tenant-validation-flow.json`, `scripts/Check-AuditLoggingCompliance.ps1`, `scripts/Enable-AuditLogging.ps1` |
| `compliance-alerts@contoso.com` | Your compliance team email | `templates/environment-validation-flow.json`, `templates/tenant-validation-flow.json` |
| `governance-lead@contoso.com` | Your governance lead email | `templates/audit-remediation-approval-flow.json` |
| `compliance-team@contoso.com` | Your compliance team email | `templates/audit-remediation-approval-flow.json` |
| `https://YOUR-ORG.crm.dynamics.com` | Your Dataverse environment URL | `templates/audit-remediation-approval-flow.json` |

## Security Considerations

- Validation history is **organization-owned** — security roles must remove Write/Delete privileges post-deployment
- ACV uses certificate-based Service Principal authentication; ALCA uses System-Assigned Managed Identity
- Connection references bind at runtime — use managed identities in production
- Grace period helps prevent false positives for newly enabled configurations (default: 24 hours)
- ALCA **never** uses interactive authentication or hardcoded credentials
- WhatIf mode available for safe remediation dry runs
- Shared mailbox for email notifications (no user mailbox access)

## FSI Regulatory Alignment

| Regulation | Requirement | How This Solution Helps |
|------------|-------------|------------------------|
| **FINRA 4511** | Books and records retention | Zone-based audit retention validation, immutable logs |
| **SEC 17a-3/4** | Record preservation | Evidence export with SHA-256 integrity hashing |
| **SOX 404** | IT general controls | Automated validation, drift detection, approval workflows |
| **OCC 2011-12** | Model risk management | Zone classification, environment registry |
| **GLBA 501(b)** | Safeguards rule | Audit configuration validation, remediation tracking |

## Documentation

| Guide | Description |
|-------|-------------|
| [docs/FLOW_SETUP.md](./docs/FLOW_SETUP.md) | Power Automate flow creation and configuration (ACV) |
| [docs/evidence-export-guide.md](./docs/evidence-export-guide.md) | Compliance evidence collection and verification (ACV) |
| [docs/deployment-guide.md](./docs/deployment-guide.md) | Azure Automation deployment, MI permissions (ALCA) |
| [docs/scheduling-guide.md](./docs/scheduling-guide.md) | Runbook scheduling configuration (ALCA) |
| [docs/testing-scenarios.md](./docs/testing-scenarios.md) | 15 test scenarios with verification (ALCA) |

## Related Controls

This solution helps support implementation of:

- **Control 1.7** — Comprehensive Audit Logging and Compliance
  - Tenant-level audit validation (Unified Audit Log, mailbox audit)
  - Environment-level audit validation (Power Platform audit retention)
  - Zone-based retention thresholds (180d/365d/730d)
  - Automated daily validation with drift detection (Power Automate)
  - Evidence export with SHA-256 integrity hashing
  - Automated detection and remediation of Purview and Dataverse audit gaps
  - Governance-approved remediation via Power Automate approval workflow

## Deployment

1. Install Python dependencies: `pip install -r scripts/requirements.txt`
2. Deploy ACV Dataverse infrastructure using `scripts/deploy.py`
3. Deploy ALCA compliance schema using `scripts/create_audit_compliance_schema.py`
4. Import Power Automate flow templates from `templates/`
5. Configure connection references (see prerequisites)
6. Update placeholder values (see Configuration Placeholders above)
7. Activate cloud flows
8. Verify deployment using the validation scripts

## Version History

See [CHANGELOG.md](./CHANGELOG.md) for detailed release notes.
