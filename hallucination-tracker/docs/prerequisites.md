# Prerequisites

## Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Platform Premium** | Power Automate flows for feedback collection |
| **Dataverse capacity** | Feedback storage (fsi_hallucinationreports table) |
| **Power BI Pro** | Dashboard visualization |

## Azure AD App Registration

The pattern analysis script authenticates via an Azure AD app registration with client credentials.

### Required Environment Variables

| Variable | Description |
|----------|-------------|
| `AZURE_TENANT_ID` | Azure AD tenant ID |
| `AZURE_CLIENT_ID` | App registration client ID |
| `AZURE_CLIENT_SECRET` | App registration client secret |

### App Registration Permissions

The app registration requires an environment-level application user in the target Dataverse environment, which is the supported approach for the client credentials flow used by this script.

## Permissions

| Role | Required For |
|------|--------------|
| **Basic User** (or custom read-only role) | Dataverse table read access (the analysis script performs read-only queries) |
| **Power BI Creator** | Dashboard development |
| **Environment Maker** | Solution import |

## Dependencies

| Solution | Version | Purpose |
|----------|---------|---------|
| FINRA Supervision Workflow | v1.0.0+ | Supervisor feedback source |

## Python Dependencies

Install with:

```bash
pip install -r scripts/requirements.txt
```

Required packages: `msal`, `requests`.
