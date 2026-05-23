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

- **Interactive mode**: User with read access to all solution tables + write to CD tables
- **Service Principal mode**: App registration with Dataverse API permissions
  - `user_impersonation` scope on the Dataverse environment
  - Security roles: Read on all Tier 2 solution tables, CD Assessor role on Compliance Dashboard

## PowerShell Requirements

- PowerShell 7.x
- Modules:
  - `MSAL.PS` — Authentication
  - `Microsoft.PowerApps.Administration.PowerShell` — Environment discovery
  - `IntegrationConfig` — This solution's shared constants module

## Network Access

- HTTPS access to Dataverse API endpoints (`*.crm.dynamics.com`)
- HTTPS access to Microsoft Graph API (for ELM provisioning hooks)
