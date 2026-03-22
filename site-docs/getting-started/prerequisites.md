# Common Prerequisites

These prerequisites are shared across most solutions. Individual solutions may have additional requirements documented in their own prerequisites pages.

## Microsoft 365 & Power Platform

| Requirement | Details |
|------------|---------|
| **Microsoft 365 E5** (or equivalent) | Required for Purview, Defender, and advanced compliance features |
| **Power Platform Premium** | Required for Dataverse, custom connectors, and cloud flows |
| **Copilot Studio** | Required for agent management and configuration auditing |
| **Power BI Pro** (or Premium) | Required for compliance dashboards and analytics |

## Azure Services

| Service | Purpose | Solutions |
|---------|---------|-----------|
| **Azure App Registration** | Service principal authentication | Most solutions |
| **Azure Key Vault** | Secret and certificate management | All production deployments |
| **Azure Log Analytics** | Centralized logging and KQL queries | Agent Observability Foundation, Deny Event Correlation |
| **Azure Automation** (optional) | Scheduled runbook execution | Solutions with PowerShell automation |

## Permissions

### Power Platform Admin

- Environment administrator or System Administrator security role
- Power Platform Service Admin (for tenant-level operations)
- Dataverse table create/read/write permissions

### Microsoft Graph

- `Organization.Read.All` — Tenant configuration
- `Directory.Read.All` — User and group lookups
- `Policy.Read.All` — Conditional access policies (for CA Automation)

### Purview & Compliance

- Compliance Administrator or equivalent for audit log access
- eDiscovery permissions for evidence export scenarios

## Dataverse Setup

All solutions that store governance data use Dataverse with a shared publisher prefix:

| Setting | Value |
|---------|-------|
| **Publisher prefix** | `fsi` |
| **Solution name** | Per-solution (e.g., `AgentAccessMonitor`) |
| **Environment** | Dedicated governance environment recommended |

Each solution includes a `create_*_dataverse_schema.py` script to deploy its tables. Run with `--output-docs` to generate schema documentation.

## Shared Utilities

Two shared utilities in `scripts/shared/` are used across solutions:

- **`dataverse_client.py`** — Python Dataverse Web API client with MSAL authentication, retry logic, and dry-run mode
- **`Get-ZoneClassification.ps1`** — PowerShell function to determine governance zone (1/2/3) for an environment

See [Shared Utilities](../reference/shared-utilities.md) for details.

## Network Requirements

| Endpoint | Port | Purpose |
|----------|------|---------|
| `login.microsoftonline.com` | 443 | Microsoft Entra ID authentication |
| `*.crm.dynamics.com` | 443 | Dataverse API |
| `graph.microsoft.com` | 443 | Microsoft Graph API |
| `management.azure.com` | 443 | Azure Management API |
| `*.api.powerplatform.com` | 443 | Power Platform API |
