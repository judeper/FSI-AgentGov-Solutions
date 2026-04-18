# Session Security Configurator Prerequisites

This document outlines all requirements for deploying and operating the Session Security Configurator (SSC) solution.

## Licensing Requirements

| Requirement | Purpose |
|------------|---------|
| Microsoft 365 E5 or E5 Security | Conditional Access, authentication contexts, authentication strength policies |
| Power Platform per-user or per-app license | Dataverse storage, Power Automate flows |
| Azure Automation (optional) | Scheduled runbook execution for daily validation |

## Role Requirements

| Role | Purpose |
|------|---------|
| Entra ID Security Administrator | Deploy authentication contexts, configure CA policies |
| Entra ID Privileged Role Administrator | Configure PIM settings for AI admin roles |
| Power Platform Administrator | Deploy Dataverse schema, bind connection references |
| System Administrator (Dataverse) | Create tables, configure security roles |
| Automation Operator (optional) | Execute Azure Automation runbooks |

## PowerShell Module Requirements

The following PowerShell modules are required for SSC scripts:

- `Microsoft.Graph.Authentication` (v2.0+)
- `Microsoft.Graph.Identity.SignIns`
- `Microsoft.Graph.Identity.DirectoryManagement`
- `Microsoft.Graph.Identity.Governance` (optional — required for PIM validation in Test-SessionCompliance.ps1)
- `Microsoft.Graph.Beta.Identity.SignIns` (optional — required for Zone 3 risky-user policy in Deploy-StepUpPolicies.ps1)
- `MSAL.PS` (for evidence export with service principal)

Install all required modules:

```powershell
Install-Module Microsoft.Graph.Authentication, `
    Microsoft.Graph.Identity.SignIns, `
    Microsoft.Graph.Identity.DirectoryManagement, `
    Microsoft.Graph.Identity.Governance, `
    Microsoft.Graph.Beta.Identity.SignIns, `
    MSAL.PS -Scope CurrentUser
```

## Python Requirements

Python scripts handle Dataverse schema deployment:

- Python 3.10 or later
- `msal` package (Microsoft Authentication Library)
- `requests` package (HTTP client)

Install dependencies:

```bash
pip install -r scripts/requirements.txt
```

## Dataverse Requirements

- Dataverse environment with available capacity
- System Customizer or System Administrator role for schema deployment
- Connection references configured for:
  - Dataverse (Microsoft Dataverse)
  - Office 365 Outlook (email alerts)
  - Microsoft Teams (adaptive card notifications)

## Network Requirements

SSC scripts require outbound access to:

| Endpoint | Purpose |
|----------|---------|
| `https://login.microsoftonline.com` | Microsoft Entra ID authentication |
| `https://graph.microsoft.com` | Microsoft Graph API |
| `https://*.crm.dynamics.com` | Dataverse API |

## Azure Automation Requirements (Optional)

For scheduled validation via Azure Automation:

- Azure Automation Account with PowerShell 7.2+ runtime
- Certificate uploaded to Automation Account Certificates blade
- Modules installed: `Microsoft.Graph.Identity.SignIns`, `Microsoft.Graph.Groups`, `Microsoft.Graph.Identity.Governance`, `MSAL.PS`
- App registration with the following Microsoft Graph application permissions:

**Required for validation (`Test-SessionCompliance.ps1`, `Start-SessionValidationRunbook.ps1`):**

  - `Policy.Read.All` (read CA policies)
  - `GroupMember.Read.All` (read group memberships for break-glass exclusion checks)
  - `RoleManagement.Read.Directory` (read PIM role assignments and policies)

**Required for deployment (`Deploy-StepUpPolicies.ps1`, `Deploy-AuthContexts.ps1`):**

  - `Policy.ReadWrite.ConditionalAccess` (create/update CA policies and authentication context references)

> **Note:** Some legacy documentation mentioned `Application.Read.All` and `Directory.Read.All` — the
> current code paths do not require either. `GroupMember.Read.All` (more narrowly scoped than
> `Directory.Read.All`) covers all break-glass and group-membership reads performed by SSC.

## Governance Zone Alignment

SSC enforces zone-specific session security controls as defined in the FSI-AgentGov framework:

| Zone | Sign-In Frequency | Auth Strength | Compliant Device |
|------|------------------|---------------|------------------|
| Zone 1 (Personal Productivity) | 8 hours | Standard MFA | Not required |
| Zone 2 (Team Collaboration) | 4 hours | Passwordless MFA | Recommended |
| Zone 3 (Enterprise Managed) | 1 hour | Phishing-resistant MFA | Required |

## Validation Checklist

Before deployment, verify:

- [ ] Microsoft 365 E5 or E5 Security license assigned
- [ ] Power Platform license assigned
- [ ] Security Administrator role assigned
- [ ] Privileged Role Administrator role assigned (for PIM)
- [ ] Power Platform Administrator role assigned
- [ ] PowerShell modules installed
- [ ] Python 3.10+ installed
- [ ] Network access to required endpoints
- [ ] Dataverse environment provisioned
- [ ] Break-glass accounts identified for exclusion

## Next Steps

After confirming prerequisites:

1. Review [Dataverse Schema](DATAVERSE-SCHEMA.md) documentation
2. Deploy infrastructure using `python scripts/deploy.py`
3. Follow [Flow Setup](FLOW_SETUP.md) for automated validation
