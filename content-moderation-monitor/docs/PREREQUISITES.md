# Prerequisites

Requirements for deploying the Content Moderation Monitor solution.

## PowerShell Requirements

| Requirement | Version | Purpose |
|-------------|---------|---------|
| PowerShell | 7.0+ | Core runtime |
| Microsoft.PowerApps.Administration.PowerShell | 2.0.180+ | Power Platform environment enumeration |
| Az.Accounts | 2.0+ | Dataverse token acquisition (interactive mode) |
| MSAL.PS | 4.37+ | Evidence export authentication (`Install-Module MSAL.PS`) |

## Installation

```powershell
# Install Power Platform Admin module
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Force -Scope CurrentUser

# Install Az.Accounts for Dataverse authentication
Install-Module -Name Az.Accounts -Force -Scope CurrentUser
```

## Permissions

### Power Platform

The executing user or service principal must have one of:
- Power Platform Admin role
- Dynamics 365 Service Admin role
- Global Admin role

These roles are required to enumerate environments and query bot records across the tenant.

### Dataverse (Per-Environment)

To query bot records, the executing identity needs read access to the `bot` and `botcomponent` tables in each target environment's Dataverse instance.

| Role | Environment | Purpose |
|------|-------------|---------|
| System Administrator or System Customizer | Target environments | Read bot table records |
| Dataverse User | Governance environment | Write validation results (Phase 2+) |

### Service Principal (Automated Scans)

For non-interactive automation:

1. Register an app in Entra ID
2. Create a client secret or certificate
3. Add the app as an application user in each Dataverse environment
4. Grant appropriate security roles

## Network Requirements

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| api.powerplatform.com | HTTPS | Power Platform API |
| api.bap.microsoft.com | HTTPS | Power Platform Admin API |
| *.crm.dynamics.com | HTTPS | Dataverse (bot table queries) |
| login.microsoftonline.com | HTTPS | OAuth token acquisition |

## Environment Lifecycle Management (ELM) Integration

For zone classification via ELM, the ELM solution must be deployed with:
- `fsi_environment` table containing zone classifications
- Environment records linked to Power Platform environment GUIDs

Without ELM, zone classification falls back to naming convention matching (e.g., `-Z3-` in environment name maps to Zone 3).

## Dataverse Schema (Phase 2+)

For Dataverse persistence features (validation history, violation tracking):

| Table | Purpose |
|-------|---------|
| `fsi_moderationbaseline` | Captured moderation baselines |
| `fsi_moderationvalidationhistory` | Immutable validation run records |
| `fsi_moderationviolation` | Individual agent-level violations |
