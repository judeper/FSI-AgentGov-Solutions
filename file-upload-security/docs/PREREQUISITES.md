# Prerequisites

## Required Permissions

### Microsoft Entra ID (Azure AD)

| Permission | Scope | Purpose |
|-----------|-------|---------|
| Application.Read.All | Delegated or Application | Enumerate Entra ID app registrations |
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
| Certificate access | Certificate-based authentication |

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
- `msal>=1.30.0` — Microsoft Authentication Library
- `requests>=2.32.0` — HTTP client

## Entra ID App Registration

1. Navigate to **Entra ID** > **App registrations** > **New registration**
2. Name: `FSI-FileUploadSecurity` (or your naming convention)
3. Supported account types: **Single tenant**
4. Add API permissions:
   - Microsoft Graph: `Application.Read.All`
   - Dynamics CRM: `user_impersonation`
5. Grant admin consent
6. Create a certificate for non-interactive authentication:
   ```powershell
   $cert = New-SelfSignedCertificate `
       -Subject "CN=FSI-FileUploadSecurity" `
       -KeySpec Signature `
       -KeyLength 2048 `
       -NotAfter (Get-Date).AddYears(2) `
       -CertStoreLocation "Cert:\CurrentUser\My"
   ```
7. Upload the certificate public key (`.cer`) to the app registration

## Environment Variables

Set these for CLI-based deployment:

| Variable | Description | Example |
|----------|-------------|---------|
| `FUS_TENANT_ID` | Azure AD tenant ID | `contoso.onmicrosoft.com` |
| `FUS_CLIENT_ID` | App registration client ID | `12345-abcd-...` |
| `FUS_CLIENT_SECRET` | Client secret (dev only) | `***` |
| `FUS_DATAVERSE_URL` | Dataverse org URL | `https://governance.crm.dynamics.com` |

## Network Requirements

| Endpoint | Protocol | Purpose |
|----------|----------|---------|
| `login.microsoftonline.com` | HTTPS | Authentication |
| `*.crm.dynamics.com` | HTTPS | Dataverse API |
| `api.bap.microsoft.com` | HTTPS | Power Platform admin API |

---

*File Upload Security Configurator — Prerequisites*
