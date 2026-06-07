# Prerequisites

Requirements for deploying the DR Testing Framework solution.

## PowerShell Requirements

| Requirement | Version | Purpose |
|-------------|---------|---------|
| PowerShell | 7.1+ | Core runtime (`#Requires -Version 7.1`) — uses PowerShell 7 behavior consistently across scripts |
| Pester | 5.0+ | Test execution (for running `Invoke-DRTest.Tests.ps1` and `Export-DREvidence.Tests.ps1`) |
| Az.Accounts | Current | Recommended way to acquire a Dataverse access token from managed identity or workload identity in Azure-hosted automation |
| Microsoft.PowerApps.Administration.PowerShell | Current | Operator-run PPAC/Admin-module backup, restore, and copy tasks such as `Backup-PowerAppEnvironment` and `Copy-PowerAppEnvironment` |

### Installation

```powershell
Install-Module -Name Pester -MinimumVersion 5.0 -Force -Scope CurrentUser
Install-Module -Name Az.Accounts -Scope CurrentUser
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser
```

## Authentication

Use a managed-identity-first pattern for automation:

1. Assign a system-assigned or user-assigned managed identity to the automation host.
2. Add that identity as a Dataverse application user in each target environment.
3. Grant only the security roles needed to read bot metadata and write `fsi_drtestresult` rows.
4. Acquire a Dataverse token and pass it with `-AccessToken` or `--access-token`.

Example for Azure-hosted PowerShell automation:

```powershell
Connect-AzAccount -Identity
$environment = "https://contoso.crm.dynamics.com"
$tokenResponse = Get-AzAccessToken -ResourceUrl $environment
$accessToken = if ($tokenResponse.Token -is [securestring]) {
    [System.Net.NetworkCredential]::new('', $tokenResponse.Token).Password
} else {
    $tokenResponse.Token
}

.\scripts\Invoke-DRTest.ps1 `
    -TestType AgentReadinessCheck `
    -AgentId "00000000-0000-0000-0000-000000000000" `
    -Environment $environment `
    -AccessToken $accessToken
```

For GitHub Actions or other CI/CD systems, prefer workload identity federation to acquire the Dataverse token, then pass it through `DATAVERSE_ACCESS_TOKEN` / `DRT_ACCESS_TOKEN`.

### Legacy local-development fallback

Client secrets are supported only for local development and compatibility testing.

```powershell
# legacy: dev-only — replace with managed identity in production
$env:AZURE_TENANT_ID     = "<your-tenant-id>"
$env:AZURE_CLIENT_ID     = "<your-client-id>"
$env:AZURE_CLIENT_SECRET  = "<your-client-secret>"
```

> **Security note:** Store development secrets in an approved secret store and rotate them frequently. Do not persist credentials in shell profiles, scripts, or repository files.

## Permissions

### Power Platform & Dataverse

The executing identity requires the following roles:

| Role | Environment | Purpose |
|------|-------------|---------|
| Power Platform Admin | Tenant-level | Operator role for PPAC environment restore/copy operations; not required by the validation script itself |
| System Administrator or equivalent custom role | Dataverse environment | Read agent metadata and write validation results to `fsi_drtestresult` |

For service principal or managed identity access, add the identity as an **application user** in each target Dataverse environment and assign the appropriate security roles.

## Dataverse Schema

The `fsi_drtestresult` table must exist in the target Dataverse environment before running DR tests. Create it using one of:

- **Manual creation** — Follow the column definitions in [dataverse-schema.md](dataverse-schema.md)
- **Schema script** — Run `create_drt_dataverse_schema.py --output-docs` to generate schema documentation, then run the script with `--access-token` for deployment

```powershell
python scripts/create_drt_dataverse_schema.py --output-docs
python scripts/create_drt_dataverse_schema.py `
    --environment-url https://contoso.crm.dynamics.com `
    --access-token $env:DRT_ACCESS_TOKEN
```

## Network Requirements

The scripts communicate with Microsoft cloud endpoints. Verify that firewall and proxy rules permit outbound HTTPS traffic to the following:

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `*.crm.dynamics.com` | HTTPS | Dataverse API |
| `login.microsoftonline.com` | HTTPS | Microsoft Entra ID token acquisition |

## Dependencies

| Solution | Version | Purpose |
|----------|---------|---------|
| Environment Lifecycle Management | v1.2.0+ | Environment context (informational — not imported or validated at runtime) |

## Python Requirements (Schema Script)

If using the Dataverse schema creation script:

| Requirement | Version | Purpose |
|-------------|---------|---------|
| Python | 3.9+ | Schema script runtime |
| `msal` | Latest | Legacy interactive or client-secret authentication fallback via the shared Dataverse client |

```bash
pip install -r scripts/requirements.txt
```

For production automation, set `DRT_ACCESS_TOKEN` from managed identity or workload identity and use `--access-token`.

## Licensing

| Requirement | Purpose |
|-------------|---------|
| Power Platform per-app or per-user license | Required for any Power Platform environment hosting the agents under validation |
| Dataverse capacity | Storage for `fsi_drtestresult` validation records and at least 1 GB free capacity for restore operations performed outside this framework |

> Power Platform environment backups are managed by Microsoft and are not administered through Azure Backup. Environment restore is performed via PPAC or current Power Apps admin module operations such as `Backup-PowerAppEnvironment`; this framework validates the post-recovery state.

> **Caveat:** This solution aids in meeting operational resilience expectations such as FFIEC BCP, OCC Heightened Standards, FINRA Rule 4370, and SEC Rule 17a-4(f). It does not by itself satisfy any single regulation. Organizations should verify that their DR testing scope, frequency, and evidence retention meet their specific regulatory obligations.
