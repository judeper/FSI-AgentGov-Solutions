# Prerequisites

Requirements for deploying the Agent Access Governance Monitor solution.

## PowerShell Requirements

| Requirement | Version | Purpose |
|-------------|---------|---------|
| PowerShell | 7.4+ | Shipped AAM module, runbook, and evidence-export minimum; not a support statement for the administration module |
| Microsoft.PowerApps.Administration.PowerShell | 2.0.180+ | Power Platform queries; Microsoft documents Windows PowerShell 5.x, not PowerShell 7.x, for this module |
| Microsoft.Graph | 2.0+ | Entra ID group queries (optional) |

> **Unresolved collector-host compatibility:** Microsoft's
> [Power Apps PowerShell guidance](https://learn.microsoft.com/power-platform/admin/powerapps-powershell)
> states that the administration modules require Windows PowerShell 5.x and use
> .NET Framework dependencies incompatible with PowerShell 6.0 and later. AAM's
> comparison script requires 7.0+, while its runbook and module require 7.4+.
> Neither selecting an Azure Automation 7.4 runtime nor downgrading the entire
> AAM execution chain to 5.1 establishes a supported configuration. Resolve this
> integration boundary and validate settings retrieval before deployment. No
> supported replacement collector or compatibility bridge is implemented by this
> documentation update.

## Licensing and product scope

- Agent-sharing rules require a **Managed Environment** and apply only to
  **agents that require authentication**. The viewer cap is per agent and is
  available when sharing is limited to individuals (no security groups). See
  [agent sharing controls](https://learn.microsoft.com/microsoft-copilot-studio/admin-sharing-controls-limits).
- Verify the environment users' qualifying entitlements against
  [Managed Environment licensing](https://learn.microsoft.com/power-platform/admin/managed-environment-licensing).
  Qualifying plans include Power Apps Premium, Power Automate Premium, and
  Microsoft Copilot Studio, with additional plans and meters subject to the
  conditions on that page. An administrator role alone is not a user license.
- The daily alert flow uses the
  [Microsoft Dataverse Premium connector](https://learn.microsoft.com/connectors/commondataserviceforapps/),
  even when Azure Automation is deferred. For a scheduled standalone flow,
  confirm Power Automate Premium for the owner or an appropriately allocated
  Power Automate Process license. Other included entitlements are context-bound;
  see the [Power Automate licensing FAQ](https://learn.microsoft.com/power-platform/admin/power-automate-licensing/faqs).

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
