# Prerequisites

## Tooling

| Tool | Purpose | Notes |
|------|---------|-------|
| PowerShell 7.1+ | Runs `Invoke-EarlyReleaseValidation.ps1` and `Export-ValidationEvidence.ps1` | `#Requires -Version 7.1` |
| Power Platform CLI (`pac`) | Exports and unpacks the target agent solution | `pac solution export` then `pac solution unpack` |
| Python 3.12+ | Runs the Dataverse schema and connection-reference scripts | `pip install -r scripts/requirements.txt` |

## Identity and access

The three structural checks run **offline** and need no credentials — they read the unpacked
solution on disk.

Evidence persistence and the (deferred) live probe need Dataverse access:

| Role | Why |
|------|-----|
| Power Platform admin | Export/unpack the target agent solution and reach the early-release ring environment. |
| Security admin | Microsoft Entra app registration / admin consent, and Dataverse system administrator access to create the `fsi_ervalidationresult` schema and write evidence rows. |

Authentication standard: prefer **managed identity / workload identity** via an access token
(`-AccessToken` or `DATAVERSE_ACCESS_TOKEN`). The legacy service-principal client-secret path
(`TenantId` / `ClientId` / `ClientSecret`) is for dev/lab only; the secret is wrapped into a
`SecureString` immediately and never persisted.

## Schema deployment

```bash
# Generate the schema reference doc offline (no credentials)
python scripts/create_erv_dataverse_schema.py --output-docs

# Create the table + option sets in Dataverse (managed identity / workload identity)
python scripts/create_erv_dataverse_schema.py \
    --environment-url https://your-org.crm.dynamics.com \
    --access-token "$DATAVERSE_ACCESS_TOKEN"
```

## Environment variables

| Variable | Used by | Notes |
|----------|---------|-------|
| `ERV_ENVIRONMENT_URL` | Python schema / connection-reference scripts | Dataverse environment URL |
| `ERV_TENANT_ID` / `ERV_CLIENT_ID` / `ERV_CLIENT_SECRET` | Python scripts (legacy SP path) | Dev/lab only |
| `ERV_ACCESS_TOKEN` | Python scripts | Preferred (managed identity / workload identity) |
| `AZURE_TENANT_ID` / `AZURE_CLIENT_ID` / `AZURE_CLIENT_SECRET` | PowerShell scripts (legacy SP path) | Dev/lab only |
| `DATAVERSE_ACCESS_TOKEN` | PowerShell scripts | Preferred |

The early-release-ring environment-config variables (`create_erv_environment_variables.py`) are
**pending MSCAT Part 2** and documented as a stub.
