# Prerequisites

Requirements for deploying the Agent Access Governance Monitor solution.

## PowerShell Requirements

| Requirement | Version | Purpose |
|-------------|---------|---------|
| PowerShell | 7.4 | Core runtime (Azure Automation supports PowerShell 7.4; 7.1/7.2 are retired) |
| Microsoft.PowerApps.Administration.PowerShell | 2.0.180+ | Power Platform queries |
| Microsoft.Graph | 2.0+ | Entra ID group queries (optional) |

## Installation

```powershell
# Install Power Platform Admin module
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Force -Scope CurrentUser

# Optional: Install Graph module for ELM zone lookup
Install-Module -Name Microsoft.Graph -Force -Scope CurrentUser
```

## Permissions

### Authentication model

Use the strongest available unattended identity for the execution host:

1. Managed identity for Azure-hosted deployment automation (`python scripts/deploy.py --managed-identity` or `--managed-identity-client-id`).
2. Workload identity federation for CI/CD (`python scripts/deploy.py --workload-identity --client-id <app-id>`).
3. Interactive (device-code) authentication for one-off administrator workstations — the default for the PowerShell scripts via `-Interactive`.
4. Service-principal authentication via client secret (`-ClientSecret`) for unattended PowerShell runs. Modern OAuth is acquired through `Get-AAMAccessToken`; the archived MSAL.PS module and certificate-thumbprint auth are no longer used.
5. Client secrets are a legacy dev-only fallback; do not use them in production runbooks or customer-facing automation where a managed identity is available.

### Power Platform

The executing identity must have one of:
- Power Platform Admin role
- Dynamics 365 Service Admin role
- Entra Global Admin role

### Microsoft Graph (Optional - for ELM zone lookup)

| Permission | Type | Purpose |
|------------|------|---------|
| Organization.Read.All | Application | Tenant configuration |
| Group.Read.All | Application | Admin exclusion groups |

## Dataverse (Phase 2+)

For Dataverse persistence features:

| Role | Environment | Purpose |
|------|-------------|---------|
| System Administrator | Governance environment | Schema deployment |
| Dataverse User | Governance environment | Runtime queries |

## Network Requirements

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| api.powerplatform.com | HTTPS | Power Platform API |
| api.bap.microsoft.com | HTTPS | Power Platform Admin |
| *.crm.dynamics.com | HTTPS | Dataverse (optional) |

## Environment Lifecycle Management (ELM) Integration

For zone classification via ELM, the ELM solution must be deployed with:
- `fsi_accessbaselines` table containing zone classifications
- Environment records linked to Power Platform environment GUIDs

Without ELM, zone classification falls back to naming convention matching.
