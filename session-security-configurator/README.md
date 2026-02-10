# Session Security Configurator

> **Status:** v1.0.0 — Complete

Automated session security baseline management for Microsoft 365 AI agent administration, supporting compliance with FINRA, SEC, and GLBA session control requirements.

## Prerequisites

### Licensing

| License | Purpose |
|---------|---------|
| Microsoft 365 E5 or E5 Security | Conditional Access, authentication contexts, authentication strength policies |
| Power Platform per-user or per-app | Dataverse storage, Power Automate flows |
| Azure Automation (optional) | Scheduled runbook execution |

### Roles Required

| Role | Purpose |
|------|---------|
| Security Administrator | Deploy authentication contexts, CA policies |
| Privileged Role Administrator | Configure PIM settings |
| Power Platform Administrator | Deploy Dataverse schema |
| System Administrator (Dataverse) | Create tables, security roles |

### PowerShell Modules

```powershell
Install-Module Microsoft.Graph.Authentication, `
    Microsoft.Graph.Identity.SignIns, `
    Microsoft.Graph.Identity.DirectoryManagement, `
    MSAL.PS -Scope CurrentUser
```

## What This Solution Does

- **Deploys** authentication contexts (c1-c5) for zone-based session control
- **Configures** Conditional Access step-up policies with zone-specific session limits
- **Validates** session security configurations against governance baselines
- **Captures** session baselines for Zone 1 (8h), Zone 2 (4h), Zone 3 (1h)
- **Validates** authentication strength policies (Standard, Passwordless, Phishing-resistant)
- **Audits** CA policy conflicts before enforcement
- **Verifies** break-glass account exclusions from session policies
- **Stores** validation history in Dataverse (immutable audit trail)
- **Detects** configuration drift with Teams and email alerting
- **Exports** compliance evidence to JSON with SHA-256 integrity hashing
- **Verifies** evidence file integrity for audit examination submissions

**This is a session security compliance solution** — it helps organizations maintain session controls that support compliance with FINRA 4511/3110, SEC 17a-3/4, GLBA 501(b), and SOX 302/404.

## Quick Start

### Step 1: Deploy Dataverse Infrastructure

```bash
# Preview deployment
python scripts/deploy.py \
    --dataverse-url https://org.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --interactive \
    --dry-run

# Full deployment
python scripts/deploy.py \
    --dataverse-url https://org.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --interactive
```

### Step 2: Deploy Authentication Contexts

```powershell
.\scripts\Deploy-AuthContexts.ps1 -TenantId <your-tenant-id> -Verbose
```

### Step 3: Deploy Step-Up Policies

```powershell
# Deploy Zone 3 step-up policy (most restrictive)
.\scripts\Deploy-StepUpPolicies.ps1 `
    -TenantId <your-tenant-id> `
    -Zone 3 `
    -ReportOnly `
    -Verbose
```

### Step 4: Validate Configuration

```powershell
# Validate Zone 3 session configuration
.\scripts\Test-SessionCompliance.ps1 -Zone 3 -Verbose

# Capture baseline for future drift detection
.\scripts\Invoke-BaselineCapture.ps1 `
    -DataverseUrl https://org.crm.dynamics.com `
    -TenantId <your-tenant-id> `
    -Zone 3 `
    -Interactive
```

### Step 5: Export Compliance Evidence

```powershell
# Export session security validation evidence
.\scripts\Export-SessionSecurityEvidence.ps1 `
    -DataverseUrl https://org.crm.dynamics.com `
    -TenantId <your-tenant-id> `
    -OutputDirectory .\exports `
    -Interactive

# Verify evidence integrity
.\scripts\Test-EvidenceIntegrity.ps1 `
    -EvidenceFilePath .\exports\session-security-evidence-All-20260209-143022.json
```

## Zone Requirements

Zone classification determines session security thresholds:

| Zone | Sign-In Frequency | Auth Strength | Compliant Device | Use Cases |
|------|------------------|---------------|------------------|-----------|
| Zone 1 | 8 hours | Standard MFA | Not required | Personal productivity agents |
| Zone 2 | 4 hours | Passwordless | Recommended | Team collaboration agents |
| Zone 3 | 1 hour | Phishing-resistant | Required | Enterprise managed, customer-facing AI |

Zone thresholds are configurable via Dataverse environment variables.

## Validation Dimensions

SSC validates six session security dimensions:

| Dimension | Description |
|-----------|-------------|
| SessionControls | Sign-in frequency, persistent browser settings |
| AuthStrength | Authentication strength policy enforcement |
| PIMSettings | PIM activation window and approval requirements |
| BreakGlass | Break-glass account CA policy exclusions |
| ConflictAudit | Overlapping CA policy detection |
| Orchestrator | Overall validation run coordination |

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    SSC Architecture                         │
├─────────────────────────────────────────────────────────────┤
│  Deployment Layer                                           │
│  ├── Deploy-AuthContexts.ps1 (c1-c5 contexts)              │
│  ├── Deploy-StepUpPolicies.ps1 (CA policies)               │
│  └── deploy.py (Dataverse schema)                          │
├─────────────────────────────────────────────────────────────┤
│  Validation Layer                                           │
│  ├── Test-SessionCompliance.ps1 (on-demand)                │
│  ├── Start-SessionValidationRunbook.ps1 (scheduled)        │
│  └── Private helpers (Connect-GraphSession, Compare-*)     │
├─────────────────────────────────────────────────────────────┤
│  Evidence Layer                                             │
│  ├── Export-SessionSecurityEvidence.ps1                    │
│  └── Test-EvidenceIntegrity.ps1                            │
├─────────────────────────────────────────────────────────────┤
│  Storage Layer (Dataverse)                                  │
│  ├── fsi_SessionBaseline (config storage)                  │
│  ├── fsi_ValidationHistory (immutable audit log)           │
│  └── fsi_DriftViolation (alerts)                           │
├─────────────────────────────────────────────────────────────┤
│  Alerting Layer                                             │
│  ├── Power Automate flow (daily orchestration)             │
│  ├── Teams adaptive cards (failed/error severity)          │
│  └── Email distribution (all drift alerts)                 │
└─────────────────────────────────────────────────────────────┘
```

## Scripts Reference

### Deployment Scripts

| Script | Purpose |
|--------|---------|
| deploy.py | Deploy Dataverse schema (tables, option sets, environment variables) |
| Deploy-AuthContexts.ps1 | Create authentication contexts c1-c5 |
| Deploy-StepUpPolicies.ps1 | Create zone-specific CA policies |

### Validation Scripts

| Script | Purpose |
|--------|---------|
| Test-SessionCompliance.ps1 | On-demand session security validation |
| Invoke-BaselineCapture.ps1 | Capture current config as baseline |
| Start-SessionValidationRunbook.ps1 | Azure Automation scheduled validation |

### Evidence Scripts

| Script | Purpose |
|--------|---------|
| Export-SessionSecurityEvidence.ps1 | Export validation history with SHA-256 hash |
| Test-EvidenceIntegrity.ps1 | Verify evidence file integrity |

### Private Helpers

| Script | Purpose |
|--------|---------|
| Connect-GraphSession.ps1 | Graph authentication wrapper |
| Test-BreakGlassExclusion.ps1 | Break-glass exclusion verification |
| Compare-SessionBaseline.ps1 | Baseline drift comparison |
| Get-SSCValidationResults.ps1 | Dataverse query helper |

## Documentation

- [Prerequisites](docs/PREREQUISITES.md) — Licensing, roles, and module requirements
- [Dataverse Schema](docs/DATAVERSE-SCHEMA.md) — Table and option set reference
- [Flow Setup](docs/FLOW_SETUP.md) — Power Automate daily validation configuration
- [Evidence Export Guide](docs/EVIDENCE-EXPORT-GUIDE.md) — Compliance evidence export instructions
- [Troubleshooting](docs/TROUBLESHOOTING.md) — Common issues and resolutions

## FSI-AgentGov Integration

This solution supports the following FSI-AgentGov controls:

| Control | Description |
|---------|-------------|
| [1.23](https://judeper.github.io/FSI-AgentGov/controls/pillar-1-security/1.23-session-security-step-up-authentication/) | Session Security and Step-Up Authentication |

## Related Solutions

- **Audit Configuration Validator** — Complementary audit retention validation
- **Conditional Access Automation** — Additional CA policy management

## License

MIT License. See [LICENSE](../LICENSE) for details.
