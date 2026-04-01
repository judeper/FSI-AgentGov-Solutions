# Prerequisites

Requirements for deploying the DR Testing Framework solution.

## PowerShell Requirements

| Requirement | Version | Purpose |
|-------------|---------|---------|
| PowerShell | 7.0+ | Core runtime (`#Requires -Version 7.0`) |
| Pester | 5.0+ | Test execution (for running `Invoke-DRTest.Tests.ps1` and `Export-DREvidence.Tests.ps1`) |

### Installation

```powershell
# Install Pester (if not already present)
Install-Module -Name Pester -MinimumVersion 5.0 -Force -Scope CurrentUser
```

## Entra ID App Registration

For non-interactive (automated) execution, register a service principal:

1. Register an application in **Microsoft Entra ID** → App registrations
2. Create a client secret (or certificate) and record the expiry date
3. Note the following values from the app registration overview:
   - **Directory (tenant) ID**
   - **Application (client) ID**
   - **Client secret value**

### Environment Variables

Set these environment variables before running the scripts:

| Variable | Description |
|----------|-------------|
| `AZURE_TENANT_ID` | Entra ID directory (tenant) ID |
| `AZURE_CLIENT_ID` | App registration application (client) ID |
| `AZURE_CLIENT_SECRET` | Client secret value |

```powershell
$env:AZURE_TENANT_ID     = "<your-tenant-id>"
$env:AZURE_CLIENT_ID     = "<your-client-id>"
$env:AZURE_CLIENT_SECRET  = "<your-client-secret>"
```

> **Security note:** Store secrets in a key vault or CI/CD secret store for production use. Avoid persisting credentials in shell profiles or scripts.

## Permissions

### Power Platform & Dataverse

The executing identity (user or service principal) requires the following roles:

| Role | Environment | Purpose |
|------|-------------|---------|
| Power Platform Administrator | Tenant-level | Environment operations and agent management |
| System Administrator | Dataverse environment | Write DR test results to `fsi_drtestresult` table |
| Backup Operator | Azure (optional) | Azure Backup access for environment backups |

For service principal access, add the app as an **application user** in each target Dataverse environment and assign the appropriate security roles.

## Dataverse Schema

The `fsi_drtestresult` table must exist in the target Dataverse environment before running DR tests. Create it using one of:

- **Manual creation** — Follow the column definitions in [dataverse-schema.md](dataverse-schema.md)
- **Schema script** — Run `create_drt_dataverse_schema.py` (when available) with `--output-docs` to generate schema documentation

> **Note:** A deployable Power Platform solution package for automated schema deployment is planned. Until then, create the table manually as described in the [README](../README.md#deployment).

## Network Requirements

The scripts communicate with Microsoft cloud endpoints. Verify that firewall and proxy rules permit outbound HTTPS traffic to the following:

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `*.crm.dynamics.com` | HTTPS | Dataverse API (commercial cloud) |
| `*.microsoftdynamics.us` | HTTPS | Dataverse API (GCC High) |
| `*.appsplatform.us` | HTTPS | Dataverse API (GCC High alternate) |
| `*.dynamics.cn` | HTTPS | Dataverse API (China sovereign cloud) |
| `login.microsoftonline.com` | HTTPS | Entra ID token acquisition (commercial) |
| `login.microsoftonline.us` | HTTPS | Entra ID token acquisition (GCC High) |
| `login.chinacloudapi.cn` | HTTPS | Entra ID token acquisition (China) |

Only the endpoints matching your cloud environment are required. Most organizations need only the commercial (`*.crm.dynamics.com` and `login.microsoftonline.com`) endpoints.

## Dependencies

| Solution | Version | Purpose |
|----------|---------|---------|
| Environment Lifecycle Management | v1.1.0+ | Environment context (informational — not imported or validated at runtime) |

## Python Requirements (Schema Script)

If using the Dataverse schema creation script:

| Requirement | Version | Purpose |
|-------------|---------|---------|
| Python | 3.9+ | Schema script runtime |
| `msal` | Latest | Dataverse authentication via MSAL |

```bash
pip install msal
```

## Licensing

| Requirement | Purpose |
|-------------|---------|
| Power Platform Premium | Power Automate flows (if using flow-based scheduling) |
| Dataverse capacity | Storage for `fsi_drtestresult` test records |
| Azure Backup | Environment backups (optional — required only for backup-based DR scenarios) |

> **Caveat:** This solution aids in meeting operational resilience requirements such as OCC 2011-12 and FFIEC business continuity guidance. It does not by itself satisfy any single regulation. Organizations should verify that their DR testing scope, frequency, and evidence retention meet their specific regulatory obligations.
