# Audit Configuration Validator

> **Status:** v1.0.0 — Complete

Automated validation of Microsoft 365 and Power Platform audit configurations to support compliance with US financial services regulations.

## Prerequisites

### 1. Licensing

| License | Purpose |
|---------|---------|
| Microsoft 365 E3/E5 | Unified Audit Log, mailbox auditing |
| Purview Compliance | Retention policies, advanced audit features |
| Power Platform Admin | Environment discovery, configuration validation |
| Power Apps Premium | Dataverse tables for validation history |

### 2. Roles Required

| Role | Purpose |
|------|---------|
| Exchange Online Admin | Unified Audit Log configuration |
| Compliance Admin | Purview retention policy access |
| Power Platform Admin | Environment enumeration, audit settings |
| System Administrator | Dataverse table creation, security roles |

### 3. Python Environment

```bash
# Python 3.10 or later required
python --version

# Install dependencies
pip install -r scripts/requirements.txt
```

## What This Solution Does

- **Validates** tenant-level audit configuration (Unified Audit Log, mailbox audit)
- **Validates** environment-level audit configuration (Power Platform audit retention)
- **Classifies** validation results by zone (Zone 1: 180d, Zone 2: 365d, Zone 3: 730d)
- **Stores** validation history in Dataverse (immutable, append-only)
- **Detects** grace period violations (newly enabled audit configs)
- **Tracks** environment registry with zone classification and override capability
- **Exports** compliance evidence to JSON with SHA-256 integrity hashing
- **Verifies** evidence file integrity for audit examination submissions

**This is an audit compliance solution** - it helps organizations maintain audit configurations that support compliance with FINRA 4511, SEC 17a-3/4, and SOX 404.

## Quick Start

### Step 1: Deploy Dataverse Infrastructure

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

### Step 2: Run Tenant-Level Validation

```powershell
# Validate tenant audit configuration for Zone 3 (730-day retention)
.\scripts\Invoke-TenantAuditValidation.ps1 -Zone 3 -Verbose

# With JSON output for automation
.\scripts\Invoke-TenantAuditValidation.ps1 -Zone 3 -OutputPath .\results.json
```

### Step 3: Register Environments

```python
# Discover and register all Power Platform environments
python scripts/discover_environments.py \
    --environment-url https://org.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --interactive
```

### Step 4: Validate Environment Configurations

```python
# Validate all registered environments
python scripts/validate_environments.py \
    --environment-url https://org.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --interactive
```

### Step 5: Export Compliance Evidence

```powershell
# Export last 30 days of tenant validation evidence
.\scripts\Export-AuditValidationEvidence.ps1 `
    -DataverseUrl https://org.crm.dynamics.com `
    -TenantId <your-tenant-id> `
    -Scope Tenant `
    -OutputDirectory .\exports `
    -Interactive

# Export environment validation evidence
.\scripts\Export-AuditValidationEvidence.ps1 `
    -DataverseUrl https://org.crm.dynamics.com `
    -TenantId <your-tenant-id> `
    -Scope Environment `
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

## Data Model

### AuditValidationHistory Table

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
| `fsi_rawvalue` | Text | Actual config values (e.g., "AuditEnabled=true,RetentionDays=90") |
| `fsi_reason` | Text | Human-readable explanation |
| `fsi_timestamp` | DateTime | When validation ran |

### EnvironmentRegistry Table

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

## Known Limitations

| Capability | Status | Script/Alternative |
|------------|--------|-------------------|
| Create Dataverse tables | **Automated** | `deploy.py` |
| Create environment variables | **Automated** | `deploy.py` |
| Create connection references | **Automated** | `deploy.py` |
| Tenant-level validation | **Automated** | PowerShell scripts (Phase 1) |
| Environment discovery | **Automated** | `discover_environments.py` (Phase 2) |
| Environment validation | **Automated** | `validate_environments.py` (Phase 2) |
| Power Automate flow | **Template** | Import from JSON templates in src/ (see docs/FLOW_SETUP.md) |
| Alerting configuration | **Template** | Configured via Power Automate flows |
| Evidence export | **Automated** | Export-AuditValidationEvidence.ps1 |

## Who Should Use This

| Audience | Use Case |
|----------|----------|
| Platform Operations | Monitor audit configuration drift |
| AI Governance Committee | Enforce zone-based audit retention |
| Compliance Teams | Validate regulatory audit requirements |
| Auditors | Export validation history for examinations |

## Architecture

```
┌─────────────────────────────────────────────────────────────────┐
│  Phase 1: PowerShell Validators (Tenant-Level)                  │
│  - Test-UnifiedAuditLog.ps1                                     │
│  - Test-MailboxAudit.ps1                                        │
│  - Test-PurviewRetention.ps1                                    │
│  - Invoke-TenantAuditValidation.ps1 (orchestrator)              │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Phase 2: Python Infrastructure (Environment-Level)             │
│  - acv_client.py (Dataverse Web API client)                     │
│  - create_dataverse_schema.py (tables, option sets)             │
│  - create_environment_variables.py (zone thresholds)            │
│  - create_connection_references.py (Dataverse, Office 365)      │
│  - deploy.py (orchestrator)                                     │
│  - discover_environments.py (Power Platform API)                │
│  - validate_environments.py (environment audit config)          │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Phase 3: Automated Orchestration & Alerting                    │
│  - Start-TenantValidationRunbook.ps1 (Azure Automation)         │
│  - Start-EnvironmentValidationRunbook.ps1 (Azure Automation)    │
│  - Compare-ValidationBaseline.ps1 (drift detection)             │
│  - Power Automate flows (daily schedule, alert routing)         │
└─────────────────────────────────────────────────────────────────┘
                           │
                           ▼
┌─────────────────────────────────────────────────────────────────┐
│  Phase 4: Evidence Export & Framework Integration               │
│  - Export-AuditValidationEvidence.ps1 (JSON + SHA-256)          │
│  - Test-EvidenceIntegrity.ps1 (hash verification)               │
│  - Evidence export guide for auditors                           │
└─────────────────────────────────────────────────────────────────┘
```

## Version History

See [CHANGELOG.md](./CHANGELOG.md) for detailed release notes.

## Documentation

- [Flow Setup Guide](./docs/FLOW_SETUP.md) - Power Automate flow creation and configuration
- [Evidence Export Guide](./docs/evidence-export-guide.md) - Compliance evidence collection and verification

## Related Controls

This solution helps support implementation of:

- **Control 1.7** - Audit Log Configuration (framework controls)
- Tenant-level audit validation (Unified Audit Log, mailbox audit)
- Environment-level audit validation (Power Platform audit retention)
- Zone-based retention thresholds (180d/365d/730d)
- Automated daily validation with drift detection (Power Automate)
- Evidence export with SHA-256 integrity hashing

## Security Considerations

- Validation history is **organization-owned** - security roles must remove Write/Delete privileges post-deployment
- Service Principal requires **Office 365 Exchange Online** and **Power Platform Administrator** API permissions
- Connection references bind at runtime - use managed identities in production
- Grace period prevents false positives for newly enabled configurations (default: 24 hours)
