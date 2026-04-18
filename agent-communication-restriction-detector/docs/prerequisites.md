# Prerequisites

Requirements for deploying the Agent Communication Restriction Detector (ACRD) solution.

## PowerShell Requirements

| Requirement | Version | Purpose |
|-------------|---------|---------|
| PowerShell | 7.0+ | Core runtime |
| Microsoft.PowerApps.Administration.PowerShell | 2.0.180+ | Power Platform environment enumeration |
| Az.Accounts | 2.0+ | Dataverse token acquisition (interactive mode) |
| MSAL.PS | 4.37+ | Evidence export authentication (`Install-Module MSAL.PS`) |

## Python Requirements

| Requirement | Version | Purpose |
|-------------|---------|---------|
| Python | 3.9+ | Deployment scripts runtime |
| msal | 1.24+ | Entra ID authentication |
| requests | 2.31+ | Dataverse Web API HTTP client |

Install Python dependencies:

```bash
pip install -r scripts/requirements.txt
```

## Installation

```powershell
# Install Power Platform Admin module
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Force -Scope CurrentUser

# Install Az.Accounts for Dataverse authentication
Install-Module -Name Az.Accounts -Force -Scope CurrentUser

# Install MSAL.PS for evidence export
Install-Module -Name MSAL.PS -Force -Scope CurrentUser
```

## Microsoft Entra ID App Registration

A Microsoft Entra ID app registration is required for both interactive and non-interactive authentication.

### Registration Steps

1. Navigate to [Azure Portal](https://portal.azure.com) > **Entra ID** > **App registrations**
2. Click **New registration**
3. Name: `ACRD-CommRestrictionDetector` (or your organization's naming convention)
4. Supported account types: **Single tenant**
5. Redirect URI: `http://localhost` (for interactive auth)
6. Click **Register**

### API Permissions

| API | Permission | Type | Purpose |
|-----|-----------|------|---------|
| Dynamics CRM | `user_impersonation` | Delegated | Dataverse read/write for schema and data |
| Microsoft Graph | `Environment.Read.All` | Application | Power Platform environment enumeration |

> **Note:** After adding permissions, an admin must grant consent for the tenant.

### Certificate Authentication (Recommended for Automation)

For non-interactive Azure Automation execution:

1. Generate a self-signed certificate or use a CA-issued certificate
2. Upload the `.cer` file to the app registration (Certificates & secrets > Certificates)
3. Upload the `.pfx` file to the Azure Automation account (Certificates blade)
4. Record the certificate thumbprint for configuration

## Permissions

### Power Platform

The executing user or service principal must have one of:

- Power Platform Admin role
- Dynamics 365 Service Admin role
- Entra Global Admin role

These roles are required to enumerate environments and query agent skill registrations across the tenant.

### Dataverse (Per-Environment)

To query bot, botcomponent, and skill registration records, the executing identity needs read access to the `bot`, `botcomponent`, and `botcomponentextendedmetadata` tables in each target environment's Dataverse instance.

| Role | Environment | Purpose |
|------|-------------|---------|
| System Administrator or System Customizer | Target environments | Read bot, botcomponent, and skill registration records |
| Dataverse User | Governance environment | Write scan results, violations, approved routes |

### Service Principal (Automated Scans)

For non-interactive automation:

1. Register an app in Entra ID (see above)
2. Create a client secret or certificate
3. Add the app as an application user in each Dataverse environment
4. Grant appropriate security roles

## Azure Automation Account

For scheduled daily scans via Power Automate:

1. Create an Azure Automation account (or reuse an existing governance account)
2. Import the `Start-CommRestrictionValidationRunbook.ps1` as a PowerShell 7.2 runbook
3. Upload the authentication certificate to the Certificates blade
4. Install required modules: `MSAL.PS`, `Microsoft.PowerApps.Administration.PowerShell`, `Az.Accounts` (the runbook uses MSAL.PS for cert-based Dataverse auth, the admin module for environment enumeration, and Az.Accounts is required transitively by `ACRDClient.psm1` if any helper is dot-sourced)
5. Configure runbook parameters (tenant ID, client ID, certificate thumbprint, Dataverse URL)

## Network Requirements

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `api.powerplatform.com` | HTTPS | Power Platform API |
| `api.bap.microsoft.com` | HTTPS | Power Platform Admin API |
| `*.crm.dynamics.com` | HTTPS | Dataverse (bot table queries, schema deployment) |
| `login.microsoftonline.com` | HTTPS | OAuth token acquisition |

## Environment Lifecycle Management (ELM) Integration

For zone classification via ELM, the ELM solution must be deployed with:

- `fsi_environment` table containing zone classifications
- Environment records linked to Power Platform environment GUIDs

Without ELM, zone classification falls back to naming convention matching (e.g., `-Z3-` in environment name maps to Zone 3).

## External Dependency: Shared Zone Classification Module

The private helper `scripts/private/Get-ZoneClassification.ps1` delegates to a shared module located at `scripts/shared/Get-ZoneClassification.ps1` (outside this solution directory, in the parent repository). This shared module provides the core zone classification logic used across multiple governance solutions.

**Impact:** If the shared module is absent on the deployment target, zone classification will fail at runtime for all environments. Agents will not be assigned to zones, and all violations will be classified as "Warning" severity instead of their correct Critical/High/Medium severity.

**Resolution options:**

1. Deploy the shared module alongside this solution at the expected relative path (`../../../scripts/shared/Get-ZoneClassification.ps1` from `scripts/private/`)
2. Replace `scripts/private/Get-ZoneClassification.ps1` with a self-contained implementation that does not delegate to the shared module

## Dataverse Schema

For Dataverse persistence features (scan history, violation tracking, approved communication routes):

| Table | Purpose |
|-------|---------|
| `fsi_CommScanRun` | Per-scan summary records with agent and environment counts |
| `fsi_AgentCommViolation` | Per-agent communication violations with severity |
| `fsi_ApprovedCommRoute` | Approved agent-to-agent communication routes |
| `fsi_CommException` | Exception requests for blocked communication patterns |
| `fsi_AgentSkillRegistration` | Per-agent skill registration tracking |

### Deployment Scripts

Deploy the Dataverse schema using the Python scripts in `scripts/`:

```bash
# Install Python dependencies
pip install -r scripts/requirements.txt

# Deploy all components (schema, connection refs, env vars) -- dry-run first
python scripts/deploy.py \
    --environment-url https://org.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --interactive \
    --dry-run

# Deploy for real
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
