# Prerequisites

## Licensing

| Requirement | Purpose |
|-------------|---------|
| **Power Platform Premium** | Power Automate flows or approved automation for feedback collection |
| **Dataverse capacity** | Feedback storage (`fsi_hallucinationreports` table) |
| **Power BI Pro** | Dashboard visualization |
| **Azure AI Content Safety** | Optional groundedness detection for automated checks |
| **Microsoft Foundry project** | Optional offline/online evaluation and cluster analysis |

## Authentication

Use the strongest available authentication method for the runtime:

1. **System-assigned managed identity** for Azure-hosted automation.
2. **User-assigned managed identity** when a specific identity must be shared across resources. Set `AZURE_MANAGED_IDENTITY_CLIENT_ID` for `analyze_patterns.py`.
3. **Workload identity federation** for CI runners. Set `AZURE_TENANT_ID`, `AZURE_CLIENT_ID`, and `AZURE_FEDERATED_TOKEN_FILE`.
4. **Azure CLI / Azure PowerShell developer credentials** for one-off admin workstation analysis.
5. **Client secret** only as a legacy development fallback. Do not document it as the recommended production path.

### Legacy dev-only environment variables

| Variable | Description |
|----------|-------------|
| `AZURE_TENANT_ID` | Microsoft Entra ID tenant ID |
| `AZURE_CLIENT_ID` | App registration client ID |
| `AZURE_CLIENT_SECRET` | App registration client secret (legacy dev-only fallback) |

The Dataverse setup scripts use `HT_TENANT_ID`, `HT_CLIENT_ID`, `HT_CLIENT_SECRET`, and `HT_ENVIRONMENT_URL` when running non-interactively. Prefer `--interactive` for admin workstations and managed identity or workload identity for production automation.

### App registration permissions

If using workload identity or the legacy client-secret fallback, the app registration requires an environment-level application user in the target Dataverse environment. Grant only the Dataverse table permissions required for the operation. The pattern analysis script performs read-only queries against `fsi_hallucinationreports`.

## Permissions

| Role | Required For |
|------|--------------|
| **Basic User** (or custom read-only role) | Dataverse table read access for analysis queries |
| **Bot Transcript Viewer** | Viewing Copilot Studio reaction comments and transcript details |
| **Power BI Creator** | Dashboard development |
| **Environment Maker** | Solution import and Dataverse setup |
| **Microsoft 365 admin center Product Feedback access** | Viewing/exporting Microsoft 365 Copilot feedback; use least-privilege roles documented by Microsoft 365 admin center |

## Dependencies

| Solution | Version | Purpose |
|----------|---------|---------|
| FINRA Supervision Workflow | v1.0.0+ | Supervisor feedback source |

## Python Dependencies

Install with:

```bash
pip install -r scripts/requirements.txt
```

Required packages: `requests`, `azure-identity`, and `msal` (for the legacy client-secret fallback).
