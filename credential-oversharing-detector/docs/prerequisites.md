# Prerequisites

## Software Requirements

| Component | Version | Purpose |
|-----------|---------|---------|
| PowerShell | 7.1+ | Core scanning and governance scripts |
| Microsoft.PowerApps.Administration.PowerShell | 2.0.180+ | Power Platform environment and agent queries |
| Python | 3.9+ | Dataverse schema setup and evidence export |
| Az.Accounts | Latest | Service principal authentication |
| Microsoft.Graph (optional) | 2.0+ | Entra ID service principal queries |

## Licensing

- **Power Platform per-user or per-app plan** — required for Dataverse table creation and read/write operations
- **Microsoft 365 E3/E5 or equivalent** — required for Teams notification delivery
- **Power Automate per-user or per-flow plan** — required for scheduled scanning and approval flows

## Required Permissions

### Power Platform Administration

- **Power Platform Admin** or **Dynamics 365 Service Admin** role — required for cross-environment agent scanning
- **Environment-level System Administrator** — required for Dataverse table operations (schema creation, record read/write)

### Microsoft Entra ID

The PowerShell scanners do **not** call Microsoft Graph today. If you extend
this solution to enrich findings with app registration metadata or service
principal ownership, the minimal least-privilege scopes are:

| Permission | Type | Purpose (only if Graph enrichment is enabled) |
|-----------|------|---------|
| `Application.Read.All` | Application | Read app registration metadata |
| `ServicePrincipal.Read.All` | Application | Read service principal metadata (preferred over `Directory.Read.All`) |

### Service Principal Setup

1. Register an application in Entra ID (requires Entra Global Admin or Application Administrator)
2. Grant Power Platform admin consent for required Graph API scopes
3. Store client secret in Azure Key Vault (recommended for production deployments)
4. Create an application user in each target Dataverse environment with System Administrator role

### Network Endpoints

The following endpoints must be accessible from the execution environment:

| Endpoint | Purpose |
|----------|---------|
| `api.powerplatform.com` | Power Platform admin API |
| `api.bap.microsoft.com` | Business Application Platform API |
| `*.crm.dynamics.com` | Dataverse Web API |
| `graph.microsoft.com` | Microsoft Graph (optional, for Entra queries) |

## Environment Lifecycle Management Integration

If using the Environment Lifecycle Management (ELM) solution, zone classification is read from the `fsi_environments` Dataverse table automatically. Otherwise, environments resolve to `Unknown` zone and policy is applied per the `Unknown` entry in `templates/zone-credential-policy.json`. (Naming-convention fallback heuristics are not implemented in this version — use ELM or pre-populate `fsi_environments` for accurate zone resolution.)

## Important Notes

- The Microsoft "Enforce safe sharing by detecting credential oversharing" feature is in public preview as of April 2026. Verify current feature status before production deployment.
- Preview features may have different security, compliance, and data residency commitments. Review Microsoft Power Platform preview terms.
- This solution supports compliance with FINRA Rule 4511(a) record-keeping and OCC 2011-12 operational risk requirements but does not guarantee regulatory compliance on its own. Organizations should verify configuration helps meet their specific obligations.
