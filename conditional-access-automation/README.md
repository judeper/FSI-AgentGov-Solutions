---
# v1.6.0 CAPE alignment metadata
applicable_patterns: [P4, P5, P6]
applicable_drivers:
  - ai_governance
  - technology_data
coe_function: govern
---
# Conditional Access Automation

> **Version:** v2.0.2
> **Status:** Live
> **Validated against framework version:** v1.6.0

Automated deployment and compliance monitoring of Entra ID Conditional Access policies for Microsoft 365 AI workloads (Copilot Studio, Agent Builder, M365 Copilot).

> **Security Context:** This solution implements Zero Trust access controls for AI applications, supporting consistent MFA enforcement and risk-based authentication across all governance zones.

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

    This solution documents Service Principal CA policy considerations in the Prerequisites section above.

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
- **Applies** MFA or MFA-satisfying authentication-strength requirements based on governance zone (Zone 1/2/3)
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
| `CA-AgentBuilder-Zone1.json` | Agent Builder | Zone 1 | Risk-based |
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
    -ConfigPath "./config.json" `
    -TemplateSet "Zone3" `
    -DryRun

# Deploy policies
.\scripts\Deploy-CAPolicies.ps1 `
    -TenantId "<tenant-id>" `
    -ConfigPath "./config.json" `
    -TemplateSet "Zone3" `
    -EnablePolicies $false  # Deploy in report-only mode first
```

### Step 3: Verify Compliance

```powershell
# Check policy coverage
.\scripts\Test-PolicyCompliance.ps1 `
    -TenantId "<tenant-id>" `
    -ConfigPath "./config.json" `
    -OutputPath "./reports"
```

### Step 4: Enable Policies

After testing in report-only mode:

```powershell
# Enable policies
.\scripts\Deploy-CAPolicies.ps1 `
    -TenantId "<tenant-id>" `
    -ConfigPath "./config.json" `
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
| **Zone 1** | Risk-based (medium+) | Optional | 8-hour timeout | `signInRiskLevels: medium, high` (CA-CopilotStudio-Zone1) |
| **Zone 2** | Always | Recommended | 4-hour timeout | Not enforced in default template — see note |
| **Zone 3** | Always | Required | 1-hour timeout | Optional risk-block add-on (CA-RiskBased-Zone3) |

> **Note on risk-based policies:** Sign-in and user-risk evaluation requires
> **Microsoft Entra ID P2** (risk evaluation is a P2 feature). Templates that
> rely on `signInRiskLevels` / `userRiskLevels` will only function on tenants
> licensed for Entra ID P2. Tenants on P1 only should rely on the MFA +
> compliant-device controls and omit the risk-based templates.
>
> **Authentication strengths:** Microsoft Graph models authentication strengths
> as `grantControls.authenticationStrength`, not as a `builtInControls: ["mfa"]`
> entry. Use the built-in **Phishing-resistant MFA strength** for Zone 3 after
> confirming passkey/FIDO2, Windows Hello for Business, or certificate-based
> authentication readiness. Do not combine `mfa` and `authenticationStrength`
> in the same policy; retrieve built-in/custom strength IDs from
> `GET /policies/authenticationStrengthPolicies` before authoring tenant-specific
> templates.
>
> **Continuous Access Evaluation (CAE):** CAE is on by default for Conditional
> Access. The bundled templates configure sign-in frequency and persistent
> browser controls only. Strict location enforcement for CAE is preview and
> should be adopted only after tenant validation of named locations and supported
> applications.

### Zone 1 - Personal Productivity

- MFA required only for risky sign-ins (`signInRiskLevels: medium, high`)
- No device compliance requirement
- Standard session timeout (8 hours)
- Suitable for personal agents with limited data access
- **Requires Entra ID P2** for risk evaluation

### Zone 2 - Team Collaboration

- MFA always required for AI application access
- Device compliance recommended but not enforced (use Intune compliance policy
  separately if required)
- Reduced session timeout (4 hours)
- Suitable for team agents with shared data access
- Works on Entra ID P1

### Zone 3 - Enterprise Managed

- MFA always required
- Compliant or Microsoft Entra hybrid joined device required
- Short session timeout (1 hour)
- Required for agents accessing sensitive/regulated data
- Works on Entra ID P1 (base policies) — add the optional
  `CA-RiskBased-Zone3-Block.json` template for "block on any risk" behavior
  (requires Entra ID P2)

## Power Platform Conditional Access scope notes

When policies target individual applications instead of **Office 365** or **All cloud apps**, keep Power Platform host apps and **Microsoft Flow Service** requirements consistent. Microsoft Learn documents broken embedded flow connections when SharePoint, Teams, Excel, Power Automate, and Microsoft Flow Service have different MFA/device/Terms of Use requirements. If individual app targeting is required, explicitly review Microsoft Flow Service (`7df0a125-d3be-4c96-aa54-591f83ff541c`) alongside Copilot Studio, Power Apps, Power Automate, and M365 Copilot service principals.

## Scripts Reference

### Register-ServicePrincipal.ps1

Creates and configures a service principal for CA policy automation when managed identity is unavailable. Managed identity is preferred for Azure-hosted automation; client secrets are legacy dev-only fallback.

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
- `AuditLog.Read.All` - Read sign-in and audit logs

### Deploy-CAPolicies.ps1

Deploys Conditional Access policy templates.

```powershell
.\scripts\Deploy-CAPolicies.ps1 `
    -TenantId "<tenant-id>" `
    -ConfigPath "./config.json" `
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
    -ConfigPath "./config.json" `
    -OutputPath "./reports" `
    [-IncludeReportOnly]
```

**Output:**
- `PolicyCoverage-YYYY-MM-DD.json` - Coverage analysis
- `PolicyGaps-YYYY-MM-DD.json` - Identified gaps

### Watch-PolicyDrift.ps1

Monitors for unauthorized policy changes.

```powershell
.\scripts\Watch-PolicyDrift.ps1 `
    -TenantId "<tenant-id>" `
    -BaselinePath "./baselines/baseline.json" `
    [-ConfigPath "./config.json"]
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

See [docs/EVIDENCE_EXPORT.md](./docs/evidence-export.md) for the complete command reference and JSON schema.

### Regulatory Alignment

| Regulation | Requirement | How This Helps |
|------------|-------------|----------------|
| **SOX 404** | IT general controls | Consistent access policies |
| **GLBA 501(b)** | Safeguards rule (FTC 16 CFR Part 314) | Multi-factor authentication |
| **Zero Trust Principles** | Verify explicitly | Risk-based authentication |

## Troubleshooting

### Common Issues

| Issue | Cause | Solution |
|-------|-------|----------|
| Deployment fails with 403 | Insufficient permissions | Grant Policy.ReadWrite.ConditionalAccess |
| Policy not applying | Report-only mode | Enable policy after testing |
| Users blocked unexpectedly | Missing exclusion | Add break-glass accounts to exclusions |
| MFA prompt loops | Session controls conflict | Check for overlapping policies |

## Known Limitations & Roadmap

### Validation Runbook

`scripts/Start-CAAValidationRunbook.ps1` is fully implemented with compliance checks, drift detection against stored baselines, and Dataverse persistence for validation history and violation records. Both flows (daily and provisioning hook) invoke this runbook for automated compliance validation.

### Dataverse Client Module

`scripts/private/CAAClient.psm1` provides 8 Dataverse functions (Connect, Read, Write) for baseline storage, validation history, and violation tracking. `Export-CAAComplianceEvidence.ps1` uses CAAClient for Dataverse queries with a fallback to `Get-AzAccessToken -AsSecureString` when the module is unavailable. The Dataverse schema is deployed via `create_caa_dataverse_schema.py`, `create_caa_environment_variables.py`, and `create_caa_connection_references.py`.

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
| [docs/SCHEMA.md](./docs/schema.md) | Dataverse tables, option sets, environment variables, connection references |
| [docs/EVIDENCE_EXPORT.md](./docs/evidence-export.md) | Evidence export command reference, JSON schema, hash verification |
| [docs/policy-templates.md](./docs/policy-templates.md) | Template specifications and customization |
| [docs/deployment-guide.md](./docs/deployment-guide.md) | Step-by-step deployment |
| [docs/compliance-monitoring.md](./docs/compliance-monitoring.md) | Drift detection and reporting |
| [docs/troubleshooting.md](./docs/troubleshooting.md) | Error recovery procedures |

## Related Controls

This solution supports:

- [Control 1.11: Conditional Access and Phishing-Resistant MFA](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.11-conditional-access-and-phishing-resistant-mfa.md)
- [Control 1.23: Step-Up Authentication for Agent Operations](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.23-step-up-authentication-for-agent-operations.md)
- [Control 1.18: Application-Level Authorization and RBAC](https://github.com/judeper/FSI-AgentGov/blob/main/docs/controls/pillar-1-security/1.18-application-level-authorization-and-role-based-access-control-rbac.md)

## Playbook Reference

Implementation guidance in FSI-AgentGov:

- [Control 1.11 Portal Walkthrough](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/control-implementations/1.11/portal-walkthrough.md)
- [Control 1.11 PowerShell Setup](https://github.com/judeper/FSI-AgentGov/blob/main/docs/playbooks/control-implementations/1.11/powershell-setup.md)

## Components

### Tier 1 — Policy Automation

| Component | File | Purpose |
|-----------|------|--------|
| Policy Templates | `templates/*.json` | 9 CA policy templates for AI workloads |
| Deploy Policies | `scripts/Deploy-CAPolicies.ps1` | Template deployment with WhatIf support |
| Service Principal | `scripts/Register-ServicePrincipal.ps1` | App registration with Key Vault integration |
| Compliance Check | `scripts/Test-PolicyCompliance.ps1` | Coverage verification with Dataverse persistence |
| Drift Monitor | `scripts/Watch-PolicyDrift.ps1` | Multi-dimensional drift detection |
| Baseline Export | `scripts/Export-PolicyBaseline.ps1` | Policy snapshot capture |

### Tier 2 — Compliance Infrastructure

| Component | File | Purpose |
|-----------|------|--------|
| Dataverse Schema | `scripts/create_caa_dataverse_schema.py` | 3 tables, 2 shared option sets |
| Environment Variables | `scripts/create_caa_environment_variables.py` | 7 runtime configuration variables |
| Connection References | `scripts/create_caa_connection_references.py` | 3 Power Automate connector references (Graph connector planned) |
| Daily Compliance Flow | See [docs/](./docs/) | Automated daily validation scan (build manually in Power Automate) |
| ELM Provisioning Hook | See [docs/](./docs/) | Zone-based policy deployment on environment creation (build manually in Power Automate) |
| Teams Alert Card | `templates/adaptive-card-caa-alert.json` | Violation notification template |
| Evidence Export | `scripts/Export-CAAComplianceEvidence.ps1` | SHA-256 integrity-hashed evidence packages |
| Evidence Verification | `scripts/Test-EvidenceIntegrity.ps1` | Hash verification for exported evidence |
| CAAClient Module | `scripts/private/CAAClient.psm1` | 8 Dataverse functions (Connect, Read, Write) |
| Automation Runbook | `scripts/Start-CAAValidationRunbook.ps1` | Unattended daily execution via Azure Automation |

## Configuration Placeholders

Flow-specific placeholders (Dataverse URL, tenant ID, certificate thumbprint, Teams channel IDs, etc.) are configured when manually building the Power Automate flows. See the [docs/](./docs/) folder for step-by-step build instructions.

## Known Issues and Operational Notes

### Module Architecture

The `conditional-access-automation` module (`scripts/conditional-access-automation.psd1`) exports reusable helper functions from `scripts/private/` (e.g., `Connect-CAAGraphSession`, `Get-CAAPolicyBaseline`, `Compare-CAAPolicyBaseline`) and the Dataverse client from `scripts/private/CAAClient.psm1`.

The top-level scripts (`Deploy-CAPolicies.ps1`, `Test-PolicyCompliance.ps1`, `Register-ServicePrincipal.ps1`, `Watch-PolicyDrift.ps1`, `Export-PolicyBaseline.ps1`, `Export-CAAComplianceEvidence.ps1`, `Test-EvidenceIntegrity.ps1`) are **standalone entry points** with their own `param()` blocks and `#Requires` directives. Run them directly:

```powershell
.\scripts\Test-PolicyCompliance.ps1 -TenantId $tenantId -ConfigPath .\config.json
.\scripts\Watch-PolicyDrift.ps1 -TenantId $tenantId -BaselinePath .\baseline.json
```

Do **not** expect these scripts to be available as functions via `Import-Module conditional-access-automation`. The module provides the internal helper functions only.

### PowerShell Script Considerations

| Script | Note | Mitigation |
|--------|------|------------|
| `Register-ServicePrincipal.ps1` | Uses `ConvertTo-SecureString -AsPlainText` to convert credential values before storing in Key Vault. This is the required pattern for `Set-AzKeyVaultSecret` — the plaintext value exists only in process memory during the call and is not persisted outside Key Vault. | Ensure the script is run from a secure workstation. Do not pass credentials via command-line arguments (they appear in process lists). |
| `Register-ServicePrincipal.ps1` | Has `#Requires -Modules Az.KeyVault` — users who only need compliance checking or drift detection do not need Az.KeyVault installed. Run `Test-PolicyCompliance.ps1` or `Watch-PolicyDrift.ps1` directly as standalone scripts. | Only install Az.KeyVault when running `Register-ServicePrincipal.ps1`. |
| `Deploy-CAPolicies.ps1` | Placeholder substitution (e.g., `<zone-3-users-group-id>`) does not validate that substituted values are well-formed GUIDs before calling the Graph API. | Always run with `-WhatIf` first. Graph API will reject malformed GUIDs, but the error message may be unclear. A future enhancement will add GUID format validation pre-deployment. |
| `Watch-PolicyDrift.ps1` | Uses `exit 0`/`exit 1` for CI/CD exit codes. These are correct for standalone/CI usage but will terminate the calling PowerShell session if invoked in-process. | Run as a standalone script. If refactored into a module function, replace `exit` with `return`. |
| `Test-EvidenceIntegrity.ps1` | Uses `exit 1` for CI/CD error signaling (same caveat as Watch-PolicyDrift). | Run as a standalone script. If refactored into a module function, replace `exit` with `return`. |
| `Export-CAAComplianceEvidence.ps1` | The `-DataverseUrl` org name extraction (`$tenantHint`) passes an org name where a tenant GUID is expected by `Connect-CAADataverse`. The fallback `Get-MgContext` resolution defaults to `'unknown'` since the script never connects to Graph directly. | Both issues should be addressed when Phase 2 Dataverse integration is built — accept an explicit `-TenantId` parameter or extract from an existing Graph context. |

### Adaptive Card Template Variables

The `templates/adaptive-card-caa-alert.json` template uses `${...}` variables (e.g., `${DocsBaseUrl}`, `${OverallStatus}`, `${SeverityStyle}`). These are **design-time references only** — the Power Automate flows build the adaptive card inline using `@{outputs(...)}` and `@{body(...)}` expressions in Compose actions. The template file documents the expected card structure and variable catalog in its `_metadata.templateVariables` section but is not loaded at runtime.

The `${DocsBaseUrl}` variable should resolve to the organization's FSI-AgentGov documentation site root URL. Set this as an environment variable or configure it in the flow's Compose action.

### Provisioning Hook Concurrency

The provisioning hook flow uses a `manual` (HTTP Request) trigger with `concurrency.runs` set to `1`, which serializes all incoming ELM `ProvisioningCompleted` calls. If multiple environments are provisioned simultaneously, each zone verification queues behind the previous one, potentially violating ELM SLA expectations.

**Recommendation:** Evaluate with stakeholders whether serialized execution is acceptable. If provisioning volume is low (< 5 environments/day), serialization is acceptable. For high-volume provisioning, consider removing the concurrency limit, partitioning by zone, or accepting concurrent runs with idempotent Dataverse writes.

### Dataverse Pagination

The `List_Validation_Records` operations in both flows use `$top: 1` to retrieve a single record, which avoids the Dataverse 5000-record page limit. If the OData filter is ever broadened to return multiple records, implement `@odata.nextLink` pagination handling to avoid silent result truncation.

## Version

2.0.1 - 2026-Q2 Microsoft Learn refresh

See [CHANGELOG.md](./CHANGELOG.md) for version history.

## License

MIT - See LICENSE in repository root
