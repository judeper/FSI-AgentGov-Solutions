# Prerequisites — Cross-Solution Integration

## Required Solutions

All of the following solutions must be deployed before enabling integration:

| Solution | Minimum Version | Required For |
|----------|----------------|--------------|
| Audit Configuration Validator (ACV) | v1.0.0 | Dashboard feed for Control 1.7 |
| Session Security Configurator (SSC) | v1.0.0 | Dashboard feed for Controls 1.23, 1.11 |
| Agent Access Governance Monitor (AAM) | v1.0.0 | Dashboard feed for Control 3.8 |
| Content Moderation Governance Monitor (CMM) | v1.0.0 | Dashboard feed for Control 1.8 |
| File Upload Security Configurator (FUS) | v1.0.0 | Dashboard feed for Control 1.14 |
| Conditional Access Automation (CAA) | v1.1.0 | Dashboard feed for Controls 1.11, 1.23, 1.18 |
| Compliance Dashboard (CD) | v1.0.0 | Assessment target |
| Environment Lifecycle Management (ELM) | v1.1.2 | Provisioning hook source (optional) |
| Agent Observability Foundation | v1.2.0 | Centralized telemetry, log analytics workspace, and shared Application Insights workbooks consumed by integration sync runs |

## Environment Requirements

- **Power Platform environment** with Dataverse enabled
- **Managed Environment** recommended for Zone 2/3
- All solutions deployed to the **same Dataverse environment** (or accessible via cross-environment queries)

## Authentication

The integration scripts are managed-identity-first (see the `Connect-DataverseApi`
parameter sets in `IntegrationConfig.psm1`). Pick the strongest method available
in your environment:

- **Managed identity (recommended for Azure-hosted automation)**: System-assigned or
  user-assigned managed identity on the Azure Automation account / Function / runner.
- **Interactive mode**: A signed-in user with read access to all solution tables and
  write access to the Compliance Dashboard tables. Requires the `MSAL.PS` module.
- **Service principal (legacy dev-only fallback)**: App registration with a client
  secret. Use a client-credentials token (the module requests the
  `https://<org>.crm.dynamics.com/.default` scope) — not the delegated
  `user_impersonation` scope, which applies only to interactive sign-in.

### Dataverse Application User (required for managed identity and service principal)

A valid OAuth token alone is **not** sufficient for non-interactive identities. The
managed identity's (or app registration's) service principal must be added to the
Dataverse environment as an **Application User** and assigned a security role, or
every Web API call returns `403 Forbidden` even though authentication succeeds.

1. Create an Application User for the identity's App (client) ID — see
   [Manage application users in the Power Platform admin center](https://learn.microsoft.com/en-us/power-platform/admin/manage-application-users#create-an-application-user).
2. Assign a security role that grants the access this integration needs — see
   [Configure a custom security role](https://learn.microsoft.com/en-us/power-platform/admin/database-security#create-or-configure-a-custom-security-role):
   - **Read** on all Tier 2 solution validation-history tables
     (`fsi_auditvalidationhistory`, `fsi_validationhistory`, `fsi_accessvalidationhistory`,
     `fsi_moderationvalidationhistory`, `fsi_fileuploadvalidationhistory`,
     `fsi_capolicyvalidationhistory`).
   - **Read** on the ACV `fsi_environmentregistry` table (required for
     `Register-ProvisionedEnvironment.ps1`) plus **Create/Write** to register
     provisioned environments.
   - **Read/Write** on the Compliance Dashboard tables (`fsi_controlmaster`,
     `fsi_controlassessment`, `fsi_complianceevidence`).

## PowerShell Requirements

- PowerShell 7.x
- Modules:
  - `MSAL.PS` — required **only** for `-Interactive` or legacy `-ClientId`/`-ClientSecret`
    service-principal authentication. Not needed for managed-identity runs.
  - `IntegrationConfig` — this solution's shared constants module
    (`scripts/powershell/IntegrationConfig.psm1`), imported by each script.

> The scripts call the Dataverse Web API directly via `Invoke-RestMethod`; no
> `Microsoft.PowerApps.Administration.PowerShell` cmdlets are required.

## Network Access

- HTTPS access to Dataverse API endpoints (`*.crm.dynamics.com`)
- HTTPS access to Microsoft Graph API (for ELM provisioning hooks)
