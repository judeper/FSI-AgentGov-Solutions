# Conditional Access Automation

> **Status:** Production Ready | **Version:** v1.1.0

Automated deployment and compliance monitoring of Entra ID Conditional Access policies for Microsoft 365 AI workloads (Copilot Studio, Agent Builder, M365 Copilot).

> **Security Context:** This solution implements Zero Trust access controls for AI applications, ensuring consistent MFA enforcement and risk-based authentication across all governance zones.

## Prerequisites

### 1. Licensing

| License | Purpose |
|---------|---------|
| Microsoft Entra ID P1 | Basic Conditional Access policies |
| Microsoft Entra ID P2 | Risk-based policies, sign-in risk, user risk |
| Microsoft 365 E5 Security (optional) | Advanced threat protection integration |

### 2. Roles Required

| Role | Purpose |
|------|---------|
| Conditional Access Administrator | Create and manage CA policies |
| Security Administrator | View security reports and configurations |
| Application Administrator | Register service principal for automation |
| Global Reader | Audit existing policies (read-only) |

### 3. Dependencies

| Dependency | Purpose |
|------------|---------|
| Microsoft Graph API | CA policy management |
| Azure Key Vault | Credential storage for automation |
| PowerShell 7+ | Script execution |

### 4. Service Principal CA Policy Considerations

!!! warning "Service Principal Security Group Bypass"
    Service Principals used for automation may not be members of security groups used in CA policy assignments, causing them to bypass user-targeted CA controls. When deploying CA policies for AI workloads, consider:

    **For User-Targeted Policies:**
    - Policies targeting security groups will NOT apply to Service Principals
    - Service Principals authenticate as application identities without group membership

    **For Service Principal Protection:**
    - Create app-specific CA policies targeting Service Principal application IDs directly
    - Use Named Locations to restrict Service Principal sign-ins to trusted networks
    - Monitor Service Principal sign-ins via Entra ID logs (filter: User Type = Service Principal)

    This solution includes Service Principal CA policy templates in `templates/service-principals/` directory.

## Architecture

The solution is organized in two tiers:

| Tier | Components | Purpose |
|------|-----------|--------|
| **Tier 1 — Policy Automation** | PowerShell scripts, CA policy templates | Deploy, validate, and monitor CA policies via Graph API |
| **Tier 2 — Compliance Infrastructure** | Dataverse schema, Power Automate flows, Azure Automation runbook | Automated daily scans, evidence persistence, Teams alerting |

```
┌─────────────────────────┐     ┌──────────────────────────┐
│  Azure Automation       │────▶│  Microsoft Graph API     │
│  (Daily Runbook)        │     │  (CA Policy Read/Write)  │
└────────┬────────────────┘     └──────────────────────────┘
         │
         ▼
┌─────────────────────────┐     ┌──────────────────────────┐
│  Dataverse              │◀───▶│  Power Automate          │
│  (Baselines, History,   │     │  (Daily Compliance Flow, │
│   Violations)           │     │   ELM Provisioning Hook) │
└────────┬────────────────┘     └──────────┬───────────────┘
         │                                 │
         ▼                                 ▼
┌─────────────────────────┐     ┌──────────────────────────┐
│  Evidence Export         │     │  Teams Adaptive Card     │
│  (SHA-256 hashed JSON)  │     │  (Violation Alerts)      │
└─────────────────────────┘     └──────────────────────────┘
```

## What This Solution Does

- **Deploys** pre-configured Conditional Access policy templates for AI workloads
- **Enforces** MFA requirements based on governance zone (Zone 1/2/3)
- **Monitors** policy compliance and configuration drift with daily automated scans
- **Persists** validation results, violations, and baselines in Dataverse
- **Reports** on policy coverage gaps across AI applications
- **Exports** SHA-256 integrity-hashed evidence packages for regulatory examinations
- **Alerts** via Teams adaptive cards when violations are detected
- **Integrates** with Environment Lifecycle Management for new environment provisioning

**This is a security automation solution** — it helps organizations implement consistent Zero Trust controls for AI applications while maintaining audit trails and compliance evidence.

## Policy Templates

### Included Templates

| Template | Target | Zone | MFA Requirement |
|----------|--------|------|-----------------|
| `CA-CopilotStudio-Zone1.json` | Copilot Studio | Zone 1 | Risk-based |
| `CA-CopilotStudio-Zone2.json` | Copilot Studio | Zone 2 | Always required |
| `CA-CopilotStudio-Zone3.json` | Copilot Studio | Zone 3 | Always + Compliant device |
| `CA-AgentBuilder-Zone2.json` | Agent Builder | Zone 2 | Always required |
| `CA-AgentBuilder-Zone3.json` | Agent Builder | Zone 3 | Always + Compliant device |
| `CA-M365Copilot-AllZones.json` | M365 Copilot | All | Risk-based minimum |
| `CA-BlockLegacyAuth-AI.json` | All AI apps | All | Block legacy authentication |
| `CA-RequireCompliantDevice-Zone3.json` | Zone 3 apps | Zone 3 | Compliant/Hybrid joined |

### Policy Naming Convention

```
CA-[Application]-[Zone]-[Requirement]
```

Examples:
- `CA-CopilotStudio-Zone3-MFA-CompliantDevice`
- `CA-AgentBuilder-Zone2-MFA-Required`
- `CA-AllAI-BlockLegacyAuth`

## Quick Start

### Step 1: Register Service Principal

```powershell
# Install required modules
Install-Module Microsoft.Graph -Scope CurrentUser
Install-Module Az.KeyVault -Scope CurrentUser

# Register service principal
.\scripts\Register-ServicePrincipal.ps1 `
    -TenantId "<tenant-id>" `
    -AppName "CAA-Automation-SP" `
    -KeyVaultName "<vault-name>"
```

### Step 2: Deploy Policy Templates

```powershell
# Dry run first to preview changes
.\scripts\Deploy-CAPolicies.ps1 `
    -TenantId "<tenant-id>" `
    -TemplateSet "Zone3" `
    -DryRun

# Deploy policies
.\scripts\Deploy-CAPolicies.ps1 `
    -TenantId "<tenant-id>" `
    -TemplateSet "Zone3" `
    -EnablePolicies $false  # Deploy in report-only mode first
```

### Step 3: Verify Compliance

```powershell
# Check policy coverage
.\scripts\Test-PolicyCompliance.ps1 `
    -TenantId "<tenant-id>" `
    -OutputPath "./reports"
```

### Step 4: Enable Policies

After testing in report-only mode:

```powershell
# Enable policies
.\scripts\Deploy-CAPolicies.ps1 `
    -TenantId "<tenant-id>" `
    -TemplateSet "Zone3" `
    -EnablePolicies $true
```

### Step 5: Export Compliance Evidence

```powershell
# Export last 30 days of compliance evidence with SHA-256 integrity hash
.\scripts\Export-CAAComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -OutputPath "./evidence"

# Verify evidence integrity
.\scripts\Test-EvidenceIntegrity.ps1 `
    -EvidencePath "./evidence/CAA-Evidence-*.json"
```

## Zone-Based Policy Requirements

| Zone | MFA | Device Compliance | Session Controls | Risk-Based |
|------|-----|-------------------|------------------|------------|
| **Zone 1** | Risk-based | Optional | 8-hour timeout | Sign-in risk medium+ |
| **Zone 2** | Always | Recommended | 4-hour timeout | Sign-in risk low+ |
| **Zone 3** | Always | Required | 1-hour timeout | Any risk blocks |

### Zone 1 - Personal Productivity

- MFA required only for risky sign-ins (medium or above)
- No device compliance requirement
- Standard session timeout (8 hours)
- Suitable for personal agents with limited data access

### Zone 2 - Team Collaboration

- MFA always required for AI application access
- Device compliance recommended but not enforced
- Reduced session timeout (4 hours)
- Suitable for team agents with shared data access

### Zone 3 - Enterprise Managed

- MFA always required
- Compliant or Hybrid Azure AD joined device required
- Short session timeout (1 hour)
- Block access from any risky sign-in
- Required for agents accessing sensitive/regulated data

## Scripts Reference

### Register-ServicePrincipal.ps1

Creates and configures a service principal for CA policy automation.

```powershell
.\scripts\Register-ServicePrincipal.ps1 `
    -TenantId "<tenant-id>" `
    -AppName "CAA-Automation-SP" `
    -KeyVaultName "<vault-name>" `
    [-DryRun]
```

**Permissions granted:**
- `Policy.Read.All` - Read CA policies
- `Policy.ReadWrite.ConditionalAccess` - Manage CA policies
- `Application.Read.All` - Read application registrations
- `Directory.Read.All` - Read directory data

### Deploy-CAPolicies.ps1

Deploys Conditional Access policy templates.

```powershell
.\scripts\Deploy-CAPolicies.ps1 `
    -TenantId "<tenant-id>" `
    -TemplateSet "<All|Zone1|Zone2|Zone3>" `
    [-TemplatePath "./templates"] `
    [-EnablePolicies <$true|$false>] `
    [-DryRun]
```

**Parameters:**
- `TemplateSet` - Which templates to deploy (All, Zone1, Zone2, Zone3)
- `EnablePolicies` - Deploy enabled ($true) or report-only ($false)
- `DryRun` - Preview changes without deploying

### Test-PolicyCompliance.ps1

Verifies policy coverage and identifies gaps.

```powershell
.\scripts\Test-PolicyCompliance.ps1 `
    -TenantId "<tenant-id>" `
    -OutputPath "./reports" `
    [-IncludeReportOnly]
```

**Output:**
- `PolicyCoverage-YYYY-MM-DD.json` - Coverage analysis
- `PolicyGaps-YYYY-MM-DD.json` - Identified gaps
- `ComplianceReport-YYYY-MM-DD.html` - Human-readable report

### Watch-PolicyDrift.ps1

Monitors for unauthorized policy changes.

```powershell
.\scripts\Watch-PolicyDrift.ps1 `
    -TenantId "<tenant-id>" `
    -BaselinePath "./baseline" `
    -AlertWebhook "<teams-webhook-url>"
```

**Detects:**
- Disabled policies
- Modified conditions
- New exclusions
- Deleted policies

## Integration with ELM

The Conditional Access Automation solution integrates with [Environment Lifecycle Management](../environment-lifecycle-management/) to automatically apply appropriate policies when new environments are provisioned.

### Integration Points

1. **Environment Creation** - ELM provisioning flow calls CA deployment
2. **Zone Classification** - Zone determines which CA templates apply
3. **Security Group Binding** - CA policies target environment security groups

### Configuration

Add to ELM `SupervisionConfig`:

```json
{
  "conditionalAccess": {
    "enabled": true,
    "autoDeployPolicies": true,
    "templateMapping": {
      "Zone1": ["CA-CopilotStudio-Zone1"],
      "Zone2": ["CA-CopilotStudio-Zone2", "CA-AgentBuilder-Zone2"],
      "Zone3": ["CA-CopilotStudio-Zone3", "CA-AgentBuilder-Zone3", "CA-RequireCompliantDevice-Zone3"]
    }
  }
}
```

## Compliance Evidence

### Export Compliance Evidence

```powershell
# Export last 30 days of evidence from Dataverse
.\scripts\Export-CAAComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -OutputPath "./evidence"

# Export specific quarter
.\scripts\Export-CAAComplianceEvidence.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -OutputPath "./evidence" `
    -FromDate "2026-01-01" -ToDate "2026-03-31"

# Verify evidence integrity
.\scripts\Test-EvidenceIntegrity.ps1 `
    -EvidencePath "./evidence/CAA-Evidence-*.json"
```

**Exports:**
- `CAA-Evidence-<timestamp>.json` — Validation results, violations, baselines
- `CAA-Evidence-<timestamp>.json.sha256` — SHA-256 companion hash for tamper-evident verification

See [docs/EVIDENCE_EXPORT.md](./docs/EVIDENCE_EXPORT.md) for the complete command reference and JSON schema.

### Regulatory Alignment

| Regulation | Requirement | How This Helps |
|------------|-------------|----------------|
| **SOX 404** | IT general controls | Consistent access policies |
| **GLBA 501(b)** | Safeguards rule | Multi-factor authentication |
| **Zero Trust Principles** | Verify explicitly | Risk-based authentication |

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Deployment fails with 403 | Insufficient permissions | Grant Policy.ReadWrite.ConditionalAccess |
| Policy not applying | Report-only mode | Enable policy after testing |
| Users blocked unexpectedly | Missing exclusion | Add break-glass accounts to exclusions |
| MFA prompt loops | Session controls conflict | Check for overlapping policies |

### Break-Glass Accounts

Always exclude emergency access accounts from CA policies:

```json
{
  "conditions": {
    "users": {
      "excludeUsers": ["<break-glass-account-1>", "<break-glass-account-2>"]
    }
  }
}
```

See [docs/troubleshooting.md](./docs/troubleshooting.md) for complete error recovery procedures.

## Documentation

| Guide | Description |
|-------|-------------|
| [docs/prerequisites.md](./docs/prerequisites.md) | Licensing, roles, dependencies (Tier 1 + Tier 2) |
| [docs/SCHEMA.md](./docs/SCHEMA.md) | Dataverse tables, option sets, environment variables, connection references |
| [docs/EVIDENCE_EXPORT.md](./docs/EVIDENCE_EXPORT.md) | Evidence export command reference, JSON schema, hash verification |
| [docs/policy-templates.md](./docs/policy-templates.md) | Template specifications and customization |
| [docs/deployment-guide.md](./docs/deployment-guide.md) | Step-by-step deployment |
| [docs/compliance-monitoring.md](./docs/compliance-monitoring.md) | Drift detection and reporting |
| [docs/troubleshooting.md](./docs/troubleshooting.md) | Error recovery procedures |

## Related Controls

This solution supports:

- [Control 1.11: Conditional Access and MFA](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.11-conditional-access-and-mfa.md)
- [Control 1.23: Step-Up Authentication](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.23-step-up-authentication-for-high-risk-operations.md)
- [Control 1.18: Application-Level RBAC](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.18-application-level-rbac.md)

## Playbook Reference

Implementation guidance in FSI-AgentGov:

- [Control 1.11 Portal Walkthrough](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/control-implementations/1.11/portal-walkthrough.md)
- [Control 1.11 PowerShell Setup](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/control-implementations/1.11/powershell-setup.md)

## Components

### Tier 1 — Policy Automation

| Component | File | Purpose |
|-----------|------|--------|
| Policy Templates | `templates/*.json` | 8 CA policy templates for AI workloads |
| Deploy Policies | `scripts/Deploy-CAPolicies.ps1` | Template deployment with WhatIf support |
| Service Principal | `scripts/Register-ServicePrincipal.ps1` | App registration with Key Vault integration |
| Compliance Check | `scripts/Test-PolicyCompliance.ps1` | Coverage verification with Dataverse persistence |
| Drift Monitor | `scripts/Watch-PolicyDrift.ps1` | Multi-dimensional drift detection |
| Baseline Export | `scripts/Export-PolicyBaseline.ps1` | Policy snapshot capture |

### Tier 2 — Compliance Infrastructure

| Component | File | Purpose |
|-----------|------|--------|
| Dataverse Schema | `scripts/create_dataverse_schema.py` | 3 tables, 2 shared option sets |
| Environment Variables | `scripts/create_environment_variables.py` | 7 runtime configuration variables |
| Connection References | `scripts/create_connection_references.py` | 4 Power Automate connector references |
| Daily Compliance Flow | `src/caa-daily-compliance-flow.json` | Automated daily validation scan |
| ELM Provisioning Hook | `src/caa-provisioning-hook-flow.json` | Zone-based policy deployment on environment creation |
| Teams Alert Card | `src/adaptive-card-caa-alert.json` | Violation notification template |
| Evidence Export | `scripts/Export-CAAComplianceEvidence.ps1` | SHA-256 integrity-hashed evidence packages |
| Evidence Verification | `scripts/Test-EvidenceIntegrity.ps1` | Hash verification for exported evidence |
| CAAClient Module | `scripts/private/CAAClient.psm1` | 8 Dataverse functions (Connect, Read, Write) |
| Automation Runbook | `scripts/Start-CAAValidationRunbook.ps1` | Unattended daily execution via Azure Automation |

## Configuration Placeholders

The following placeholder values in solution flow files must be replaced with your organization's values before deployment:

| Placeholder | Replace With | Files |
|------------|-------------|-------|
| `DataverseUrl` (empty) | Your Dataverse environment URL | `src/caa-daily-compliance-flow.json`, `src/caa-provisioning-hook-flow.json` |
| `TenantId` (empty) | Your Entra ID tenant ID | `src/caa-daily-compliance-flow.json`, `src/caa-provisioning-hook-flow.json` |
| `ClientId` (empty) | Your app registration client ID | `src/caa-daily-compliance-flow.json`, `src/caa-provisioning-hook-flow.json` |
| `CertificateThumbprint` (empty) | Your certificate thumbprint | `src/caa-daily-compliance-flow.json`, `src/caa-provisioning-hook-flow.json` |
| `SubscriptionId` (empty) | Your Azure subscription ID | `src/caa-daily-compliance-flow.json`, `src/caa-provisioning-hook-flow.json` |
| `ResourceGroup` (empty) | Your Azure resource group name | `src/caa-daily-compliance-flow.json`, `src/caa-provisioning-hook-flow.json` |
| `AutomationAccount` (empty) | Your Azure Automation account name | `src/caa-daily-compliance-flow.json`, `src/caa-provisioning-hook-flow.json` |
| `TeamsGroupId` (empty) | Your Teams group ID for alerts | `src/caa-daily-compliance-flow.json`, `src/caa-provisioning-hook-flow.json` |
| `TeamsChannelId` (empty) | Your Teams channel ID for alerts | `src/caa-daily-compliance-flow.json`, `src/caa-provisioning-hook-flow.json` |
| `ComplianceDistributionList` (empty) | Your compliance team distribution list | `src/caa-daily-compliance-flow.json` |
| `your-org` | Your GitHub organization name | `src/caa-daily-compliance-flow.json`, `src/caa-provisioning-hook-flow.json` |

## Version

1.1.0 - February 2026

See [CHANGELOG.md](./CHANGELOG.md) for version history.

## License

MIT - See LICENSE in repository root
