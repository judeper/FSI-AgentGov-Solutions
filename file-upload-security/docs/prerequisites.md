# Prerequisites

## Required Permissions

### Microsoft Entra ID

| Permission | Scope | Purpose |
|-----------|-------|---------|
| EnvironmentManagement.Environments.Read | Power Platform API (delegated) | Enumerate environments when calling the Power Platform API directly; the bundled PowerShell scripts use `Get-AdminPowerAppEnvironment`, which relies on the Power Platform Administrator role below |
| Dynamics CRM user_impersonation | Delegated (interactive runs only) | Read/write Dataverse tables when a signed-in user runs the scripts. Not needed for app-only (managed identity, certificate, or workload identity) runs, which use a Dataverse application user instead |

### Power Platform

| Role | Scope | Purpose |
|------|-------|---------|
| Power Platform Administrator | Tenant | Enumerate all environments |
| System Administrator | Dataverse org | Read bot table, write baselines/violations |

### Azure Automation (Optional)

| Permission | Purpose |
|-----------|---------|
| Automation Contributor | Import and manage runbook |
| Managed identity access | Recommended runtime authentication for Dataverse; register the managed identity's application (client) ID as a Dataverse application user. User-assigned identities are supported for Automation cloud jobs only |
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
   - Dynamics CRM: `user_impersonation` (delegated; only needed for interactive sign-in)
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
8. For non-interactive (app-only) authentication, create a Dataverse application user for the app registration in each target environment and assign it a security role. The delegated `user_impersonation` permission does not apply to app-only access

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

Unclassifiable environments default to Zone 1 (most restrictive) for fail-safe governance. To ensure accurate zone classification, pass `-DataverseUrl` to `Get-AgentFileUploadSettings`.

## Network Requirements

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `login.microsoftonline.com` | HTTPS | Authentication |
| `*.crm.dynamics.com` (regional variants such as `*.crm4.dynamics.com`) | HTTPS | Dataverse API |
| `api.admin.powerplatform.microsoft.com` | HTTPS | Power Platform admin center service (listed on Learn's Power Platform URLs page) |
| `*.api.powerplatform.com` | HTTPS | Power Platform API (listed on Learn's Power Platform URLs page) |
| `api.bap.microsoft.com` | HTTPS | Power Platform admin (BusinessAppPlatform) API host; documented on Learn as the host for admin REST calls but not listed on the Power Platform URLs page. Which host `Microsoft.PowerApps.Administration.PowerShell` calls is not documented on Learn; keep this entry if your firewall policy requires it |

---

*File Upload Security Configurator — Prerequisites — Last Verified: 2026-10-09*
