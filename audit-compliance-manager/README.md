# Audit Compliance Manager (ACM)

> **Version:** v1.0.3
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
| Microsoft.PowerApps.Administration.PowerShell | 2.0.180+ |
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
    --client-id <your-app-client-id> \
    --interactive \
    --dry-run

# Full deployment
python scripts/deploy.py \
    --environment-url https://org.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --client-id <your-app-client-id> \
    --interactive
```

The deployment script creates:
- Global option sets (Severity, Scope, Zone, Environment Status, Environment Type)
- AuditValidationHistory table (org-owned, immutable)
- EnvironmentRegistry table (org-owned, admin-managed)
- Environment variables for zone thresholds (180d/365d/730d)
- Connection references for Dataverse and Office 365 (Approvals, Teams, and Azure Automation connections referenced by the documented flows must be created manually in Power Automate — they are not provisioned by `create_connection_references.py`)

### Step 2: Deploy ALCA Compliance Schema

```python
# Create the audit environment compliance tracking table
python scripts/create_audit_compliance_schema.py \
    --environment-url https://org.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --client-id <your-app-client-id> \
    --interactive
```

### Step 3: Run Tenant-Level Validation

```powershell
# Validate tenant audit configuration against Zone 3 thresholds (default: 730 days target)
# NOTE: Whether your tenant actually retains 730 days of UAL data depends on your
# Microsoft 365 license. Audit Standard (E3) retains 90/180 days; Audit Premium (E5)
# retains 1 year by default and up to 10 years with the audit log retention add-on.
# This script reports the *configured* thresholds and flags shortfalls; it does not
# extend retention beyond what your license permits.
.\scripts\Invoke-TenantAuditValidation.ps1 -Zone Zone3 -Verbose

# With JSON output for automation
.\scripts\Invoke-TenantAuditValidation.ps1 -Zone Zone3 -OutputPath .\results.json
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

### Step 4a: Transition to Azure Automation

Steps 1–4 run interactively for initial setup and validation. For ongoing automated compliance monitoring (Steps 5–7), deploy the scripts to Azure Automation with Managed Identity authentication:

1. **Create an Azure Automation Account** with System-Assigned Managed Identity enabled
2. **Assign the Managed Identity** the required roles:
   - Power Platform Admin (Entra ID role)
   - Exchange Online Admin (Entra ID role)
   - Mail.Send (Microsoft Graph API permission — admin consent required)
   - Dataverse Application User with System Administrator role (per environment)
3. **Import PowerShell modules** into the Automation Account:
   - `Microsoft.PowerApps.Administration.PowerShell` (2.0+)
   - `ExchangeOnlineManagement` (3.0+)
   - `AuditComplianceHelpers` (custom module — ZIP and upload `.psm1` + `.psd1`)
4. **Create and publish runbooks** from the ALCA scripts (see [docs/deployment-guide.md](./docs/deployment-guide.md) for detailed steps)

> **Note:** ALCA scripts use Managed Identity authentication automatically when running inside Azure Automation. No certificates or client secrets are needed for the ALCA detection/remediation runbooks.

### Step 5: Run Compliance Detection (ALCA)

```powershell
# Detect audit logging compliance gaps across environments
.\scripts\Test-AuditLoggingCompliance.ps1 `
    -DataverseEnvironmentUrl "https://org.crm.dynamics.com" `
    -TenantDomain "contoso.onmicrosoft.com"
```

### Step 6: Remediate Non-Compliant Environments (ALCA)

```powershell
# Dry run remediation
.\scripts\Enable-AuditLogging.ps1 `
    -DataverseEnvironmentUrl "https://org.crm.dynamics.com" `
    -TenantDomain "contoso.onmicrosoft.com" -WhatIf

# Execute remediation
.\scripts\Enable-AuditLogging.ps1 `
    -DataverseEnvironmentUrl "https://org.crm.dynamics.com" `
    -TenantDomain "contoso.onmicrosoft.com"
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
.\scripts\Test-EvidenceIntegrity.ps1 -EvidenceFilePath .\exports\Tenant-validation-20260206-143500.json
```

## Zone Requirements

Zone classification determines minimum audit retention thresholds:

| Zone | Retention | Scope | Typical Use Cases |
|------|-----------|-------|-------------------|
| Zone 1 | 180 days | Personal Productivity | Individual developer environments, testing |
| Zone 2 | 365 days | Team Collaboration | Department applications, team agents |
| Zone 3 | 730 days (target) | Enterprise Managed | Production agents, customer-facing AI |

> **Retention reality check:** The thresholds above are FSI Agent Governance Framework *targets*. Your actual M365 audit retention is set by your license: Audit Standard (E3) = 90/180 days; Audit Premium (E5) = 1 year by default, up to 10 years with the audit log retention add-on. This solution validates *configured* retention against zone thresholds and flags shortfalls — it does not change the underlying license-bounded retention.

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
| `fsi_status` | Integer | Active (1) or Inactive (2) |
| `fsi_environmenttype` | Choice | Production, Sandbox, Developer, Trial, Default |
| `fsi_overrideinclude` | Boolean | Admin override to include Trial/Dev environments |
| `fsi_lastvalidated` | DateTime | Last successful validation timestamp |

### AuditEnvironmentCompliance Table (ALCA)

Compliance tracking with upsert by environment ID:

| Key Column | Type | Purpose |
|------------|------|---------|
| `fsi_environmentid` | Text | Power Platform environment GUID (alternate key) |
| `fsi_compliancestatus` | Choice | Compliant, Non-Compliant, Remediation Pending, Error |

## Platform Update Notes

### Data Subject Request (DSR) Compliance Endpoints (April 2026)

Microsoft has expanded the [Power Platform REST API](https://learn.microsoft.com/en-us/rest/api/power-platform/) with new DSR compliance endpoints covering:

- **Flow DSR** — Export and delete flow run data for individual data subjects
- **Approval DSR** — Export and delete approval records
- **Transcript DSR** — Export and delete Copilot Studio conversation transcripts
- **Prompt DSR** — Export and delete AI prompt history

**Impact on this solution:** ACM currently validates audit configuration and retention but does not cover DSR processing workflows. Organizations subject to GDPR, CCPA, or similar privacy regulations should consider:

- Incorporating DSR endpoint availability checks into the environment validation scan
- Documenting DSR processing procedures alongside audit retention policies
- Verifying that Dataverse audit retention periods do not conflict with DSR deletion obligations

> **Note:** DSR compliance automation is not yet included in ACM scripts. Organizations should track DSR capabilities through their privacy operations program and evaluate integration in a future release.

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
| Detection Runbook | `scripts/Test-AuditLoggingCompliance.ps1` | ALCA | Scan environments for audit compliance |
| Remediation Runbook | `scripts/Enable-AuditLogging.ps1` | ALCA | Enable auditing on non-compliant environments |
| Unified Audit Log Check | `scripts/Test-UnifiedAuditLog.ps1` | ACV | Validates unified audit log configuration |
| Mailbox Audit Check | `scripts/Test-MailboxAudit.ps1` | ACV | Validates mailbox audit settings |
| Purview Retention Check | `scripts/Test-PurviewRetention.ps1` | ACV | Validates Purview retention policies |
| Environment Audit Check | `scripts/Test-EnvironmentAudit.ps1` | ACV | Validates environment audit settings |
| Environment Retention Check | `scripts/Test-EnvironmentRetention.ps1` | ACV | Validates environment retention policies |
| Security Role Config | `scripts/Set-SecurityRoles.ps1` | ACV | Configures required security roles |
| Validator Tests | `scripts/Validators.Tests.ps1` | ACV | Pester 5 tests for validator scripts |
| Unit Tests | `scripts/AuditComplianceHelpers.Tests.ps1` | ALCA | Pester 5 tests for helper module |
| Connect Audit Services | `scripts/private/Connect-AuditServices.ps1` | ACV | Authenticates to M365 audit services |
| Connect Power Platform | `scripts/private/Connect-PowerPlatform.ps1` | ACV | Authenticates to Power Platform |
| Compare Baseline | `scripts/private/Compare-ValidationBaseline.ps1` | ACV | Compares results against baseline |
| Get Validation Results | `scripts/private/Get-ValidationResults.ps1` | ACV | Retrieves validation result records |
| New Canary Event | `scripts/private/New-CanaryEvent.ps1` | ACV | Creates canary audit events for testing |
| Write Validation Result | `scripts/private/Write-ValidationResult.ps1` | ACV | Writes validation results to Dataverse |

### Templates

| Template | Origin | Purpose |
|----------|--------|---------|
| `templates/adaptive-card-tenant-alert.json` | ACV | Teams card for tenant drift alerts |
| `templates/adaptive-card-environment-alert.json` | ACV | Teams card for environment drift alerts |

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
│  Detection: Test-AuditLoggingCompliance.ps1                    │
│  - MI Auth, environment scanning, Dataverse upsert              │
│                                                                 │
│  Remediation: Enable-AuditLogging.ps1                           │
│  - Org-level + entity-level audit enablement, WhatIf support    │
│                                                                 │
│  Approval: ALCA Audit Remediation Approval flow                 │
│  - Governance-approved remediation (see docs/FLOW_SETUP.md)     │
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
| Compliance detection (ALCA) | **Automated** | `Test-AuditLoggingCompliance.ps1` |
| Remediation (ALCA) | **Automated** | `Enable-AuditLogging.ps1` |
| Power Automate flows | **Manual** | Build using docs/FLOW_SETUP.md instructions |
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
| `contoso.onmicrosoft.com` | Your tenant domain | Flow variables (see `docs/FLOW_SETUP.md`) |
| `compliance-alerts@example.com` | Your compliance team email | Flow variables (see `docs/FLOW_SETUP.md`) |
| `governance-lead@example.com` | Your governance lead email | Flow variables (see `docs/FLOW_SETUP.md`) |
| `compliance-team@example.com` | Your compliance team email | Flow variables (see `docs/FLOW_SETUP.md`) |
| `https://YOUR-ORG.crm.dynamics.com` | Your Dataverse environment URL | Flow variables (see `docs/FLOW_SETUP.md`) |

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
| **SEC 17a-3/4** | Record preservation | Evidence export with SHA-256 integrity hashing. Note: SEC 17a-4(b)(4) requires 3-year retention for communications (first 2 years readily accessible); 17a-4(a) requires 6 years for blotters/ledgers/customer records. This solution helps validate audit-log configuration but does not by itself satisfy WORM/non-erasable storage requirements — combine with compliant archival storage. |
| **SOX 404** | IT general controls | Automated validation, drift detection, approval workflows |
| **OCC 2011-12** | Model risk management | Zone classification, environment registry |
| **GLBA 501(b)** | Safeguards rule | Audit configuration validation, remediation tracking |

## Documentation

| Guide | Description |
|-------|-------------|
| [docs/AUTHENTICATION.md](./docs/AUTHENTICATION.md) | Entra ID app registration, API permissions, certificate and MI authentication |
| [docs/FLOW_SETUP.md](./docs/FLOW_SETUP.md) | Power Automate flow creation and configuration (ACV) |
| [docs/evidence-export-guide.md](./docs/evidence-export-guide.md) | Compliance evidence collection and verification (ACV) |
| [docs/deployment-guide.md](./docs/deployment-guide.md) | Azure Automation deployment, MI permissions (ALCA) |
| [docs/scheduling-guide.md](./docs/scheduling-guide.md) | Runbook scheduling configuration (ALCA) |
| [docs/testing-scenarios.md](./docs/testing-scenarios.md) | 15 test scenarios with verification (ALCA) |
| [docs/acv-CHANGELOG.md](./docs/acv-CHANGELOG.md) | Pre-merge ACV component changelog (historical) |
| [docs/alca-CHANGELOG.md](./docs/alca-CHANGELOG.md) | Pre-merge ALCA component changelog (historical) |

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
4. Build Power Automate flows manually using `docs/FLOW_SETUP.md`; `templates/` contains the adaptive cards (`adaptive-card-tenant-alert.json`, `adaptive-card-environment-alert.json`) referenced from the flows. (Per repo content policy, no exported flow JSON ships in this solution.)
5. Configure connection references — Dataverse and Office 365 are provisioned by `create_connection_references.py`; Approvals, Teams, and Azure Automation must be created manually before flow build.
6. Update placeholder values (see Configuration Placeholders above)
7. Activate cloud flows
8. Verify deployment using the validation scripts

## Version History

See [CHANGELOG.md](./CHANGELOG.md) for detailed release notes.
