# Prerequisites

## Required Permissions

### Microsoft Entra ID

| Permission | Scope | Purpose |
|-----------|-------|---------|
| Environment.Read | Power Platform | Enumerate environments |
| Dynamics CRM user_impersonation | Delegated | Read/write Dataverse tables |

### Power Platform

| Role | Scope | Purpose |
|------|-------|---------|
| Power Platform Admin | Tenant | Enumerate all environments |
| System Administrator | Dataverse org | Read bot table, write baselines/violations |

### Azure Automation (Optional)

| Permission | Purpose |
|-----------|---------|
| Automation Contributor | Import and manage runbook |
| Managed identity access | Recommended runtime authentication for Dataverse and Power Platform APIs |
| Certificate access | Fallback authentication when managed identity is not available |

## Required Modules

### PowerShell

```powershell
# Install required modules
Install-Module -Name MSAL.PS -MinimumVersion 4.37.0 -Scope CurrentUser
Install-Module -Name Microsoft.PowerApps.Administration.PowerShell -Scope CurrentUser
```

### Python

```bash
pip install -r scripts/requirements.txt
```

Required packages:
- `msal>=1.30.0` — Microsoft Authentication Library for legacy interactive/client-secret fallback
- `requests>=2.32.0` — HTTP client
- `azure-identity>=1.23.0` — managed identity, workload identity, and developer credential chain

## Microsoft Entra ID App Registration

1. Navigate to **Entra ID** > **App registrations** > **New registration**
2. Name: `FSI-FileUploadSecurity` (or your naming convention)
3. Supported account types: **Single tenant**
4. Add API permissions:
   - Dynamics CRM: `user_impersonation`
5. Grant admin consent
6. Create a certificate for non-interactive authentication:
   ```powershell
   $cert = New-SelfSignedCertificate `
       -Subject "CN=FSI-FileUploadSecurity" `
       -KeySpec Signature `
       -KeyLength 2048 `
       -NotAfter (Get-Date).AddYears(2) `
       -CertStoreLocation "Cert:\LocalMachine\My"
   ```
7. Upload the certificate public key (`.cer`) to the app registration

## Authentication Pattern

Use the strongest available identity option for the runtime:

1. System-assigned managed identity for Azure Automation, Functions, or other Azure-hosted runners.
2. User-assigned managed identity when a dedicated governance identity is required.
3. Workload identity federation for GitHub Actions or other OIDC-capable CI runners.
4. Interactive/developer credentials for one-off admin workstation runs.
5. Client secret only as a legacy development fallback.

## Environment Variables

Set these for CLI-based deployment:

| Variable | Description | Example |
|----------|-------------|---------|
| `FUS_DATAVERSE_URL` | Dataverse org URL | `https://governance.crm.dynamics.com` |
| `FUS_MANAGED_IDENTITY_CLIENT_ID` | Optional user-assigned managed identity client ID | `12345-abcd-...` |
| `FUS_TENANT_ID` | Microsoft Entra ID tenant ID; required for interactive or legacy client-secret auth | `contoso.onmicrosoft.com` |
| `FUS_CLIENT_ID` | App registration client ID for interactive, workload identity, or legacy client-secret auth | `12345-abcd-...` |
| `FUS_CLIENT_SECRET` | Legacy dev-only client secret; use managed identity in production | `***` |

## External Dependencies

### Zone Classification

The zone classification logic (`scripts/private/Get-ZoneClassification.ps1`) is self-contained within this solution. It uses a two-tier approach:

1. **ELM Dataverse lookup** (preferred) — queries the `fsi_acv_environmentregistrations` table when `-DataverseUrl` and `-AccessToken` are provided
2. **Naming convention fallback** — pattern-matches the environment display name when ELM data is unavailable

Unclassifiable environments default to Zone 3 (most restrictive) for fail-safe governance. To ensure accurate zone classification, pass `-DataverseUrl` to `Get-AgentFileUploadSettings`.

## Network Requirements

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `login.microsoftonline.com` | HTTPS | Authentication |
| `*.crm.dynamics.com` | HTTPS | Dataverse API |
| `api.bap.microsoft.com` | HTTPS | Power Platform admin API |

---

*File Upload Security Configurator — Prerequisites*
