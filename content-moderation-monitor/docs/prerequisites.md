# Prerequisites

Requirements for deploying the Content Moderation Monitor solution.

## PowerShell Requirements

| Requirement | Version | Purpose |
|-------------|---------|---------|
| PowerShell | 7.2+ (matches Azure Automation runbook target; `Invoke-ModerationBaselineCapture.ps1` and Quick Start examples require PowerShell 7) | Core runtime |
| Microsoft.PowerApps.Administration.PowerShell | 2.0.180+ | Power Platform environment enumeration |
| Az.Accounts | 2.0+ | Dataverse token acquisition (interactive mode) |
| MSAL.PS | 4.37+ | Evidence export and runbook authentication (community-maintained; pin to 4.37.0 — see Known Limitations in CHANGELOG) |

## Installation

```powershell
# Install Power Platform Admin module
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Force -Scope CurrentUser

# Install Az.Accounts for Dataverse authentication
Install-Module -Name Az.Accounts -Force -Scope CurrentUser

# Install MSAL.PS for evidence export / runbook (pin matches script #Requires)
Install-Module -Name MSAL.PS -RequiredVersion 4.37.0 -Force -Scope CurrentUser
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

### Automation Identity (Managed Identity First)

For non-interactive automation, use the strongest identity available in this order:

1. System-assigned managed identity for Azure Automation or Azure-hosted runners.
2. User-assigned managed identity when the same identity must be shared across resources.
3. Workload identity federation for GitHub Actions or other CI/CD runners.
4. Certificate-based app registration when managed identity or federation is not available.
5. Client secret only as a legacy development fallback — `# legacy: dev-only — replace with managed identity in production`.

Add the automation identity as an application user in each Dataverse environment and grant the least-privilege security roles required for bot reads and CMM evidence writes.

## Network Requirements

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| api.powerplatform.com | HTTPS | Power Platform API |
| api.bap.microsoft.com | HTTPS | Power Platform Admin API |
| *.crm.dynamics.com | HTTPS | Dataverse (bot table queries) |
| login.microsoftonline.com | HTTPS | OAuth token acquisition |

## Environment Lifecycle Management (ELM) Integration

For zone classification via ELM, the ELM solution must be deployed with:
- `fsi_environmentrequests` table containing zone classifications
- Environment records linked to Power Platform environment GUIDs

Without ELM, zone classification falls back to naming convention matching (e.g., `-Z3-` in environment name maps to Zone 3).

## Dataverse Schema (Phase 2+)

For Dataverse persistence features (validation history, violation tracking):

| Table | Purpose |
|-------|---------|
| `fsi_moderationbaselines` | Captured moderation baselines |
| `fsi_moderationvalidationhistory` | Immutable validation run records |
| `fsi_moderationviolations` | Individual agent-level violations |

### Deployment Scripts

Deploy the Dataverse schema using the Python scripts in `scripts/`:

```bash
# Install Python dependencies
pip install -r scripts/requirements.txt

# Deploy all components (schema, connection refs, env vars)
python scripts/deploy.py \
    --environment-url https://org.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --interactive

# Or deploy individual components
python scripts/create_dataverse_schema.py --interactive
python scripts/create_connection_references.py --interactive
python scripts/create_environment_variables.py --interactive
```

**Python Requirements:** Python 3.9+, packages listed in `scripts/requirements.txt`.
