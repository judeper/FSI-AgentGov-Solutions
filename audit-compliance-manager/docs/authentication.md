# Authentication Guide — Audit Compliance Manager

This guide covers authentication methods used by the Audit Compliance Manager (ACM) solution, including Microsoft Entra ID app registrations, API permissions, Managed Identity, certificate-based app-only auth, legacy dev-only client secrets, and interactive authentication for development.

## 1. Microsoft Entra ID App Registration

Use managed identity first for production automation. The ALCA runbooks use a System-Assigned Managed Identity. The ACV component still uses a Microsoft Entra app registration for interactive bootstrap, Power Automate-triggered validation, and certificate-based app-only fallback when managed identity is not available for the execution host.

### 1.1 Create the App Registration

1. Sign in to the [Microsoft Entra admin center](https://entra.microsoft.com)
2. Navigate to **Identity** → **Applications** → **App registrations**
3. Click **+ New registration**
4. Configure:
   - **Name:** `ACM-AuditComplianceManager`
   - **Supported account types:** Accounts in this organizational directory only (Single tenant)
   - **Redirect URI:** Leave blank (not needed for service principal authentication)
5. Click **Register**
6. Record the following values from the **Overview** page:
   - **Application (client) ID** — used as `--client-id` in Python scripts and `ClientId` in Power Automate flows
   - **Directory (tenant) ID** — used as `--tenant-id`

### 1.2 Configure Authentication

1. Navigate to **Authentication** in the app registration
2. Under **Advanced settings**:
   - For **production** (certificate / Managed Identity / app-only): set **Allow public client flows** to **No**. No redirect URI required.
   - For **interactive setup** (the `--interactive` quick-start path used by `deploy.py`, `create_*_schema.py`, and `ACVClient` / `ALCAClient`): you must set **Allow public client flows** to **Yes** AND register a public-client/native-app redirect URI of `http://localhost`. The interactive scripts use `msal.PublicClientApplication.acquire_token_interactive()`, which requires a public-client app registration.
3. The recommended pattern is **two app registrations**: one public-client app for interactive bootstrap, one confidential-client (or system-assigned MI) for production runbooks.

## 2. API Permissions

Navigate to **API permissions** → **+ Add a permission** and add the following:

### 2.1 Microsoft Graph

| Permission | Type | Purpose |
|-----------|------|---------|
| `Mail.Send` | Application | Send compliance notification emails via shared mailbox |
| `SecurityEvents.Read.All` | Application | Legacy Graph-based security event access used by earlier ACV validation paths |
| `AuditLogsQuery.Read.All` | Application | Optional Microsoft Graph Audit Search API access for `/security/auditLog/queries` validation when your organization allows the current Graph audit query endpoint |

### 2.2 Dynamics CRM (Dataverse)

| Permission | Type | Purpose |
|-----------|------|---------|
| `user_impersonation` | Delegated | Interactive Dataverse access during initial setup and testing |

> **Note:** For automated (non-interactive) Dataverse access, configure the service principal or Managed Identity as a Dataverse Application User instead of using delegated permissions. See [Section 5.3](#53-grant-dataverse-application-user-access).

### 2.3 Exchange Online

| Permission | Type | Purpose |
|-----------|------|---------|
| `Exchange.ManageAsApp` | Application | Service principal access to Exchange Online cmdlets (`Get-AdminAuditLogConfig`, `Search-UnifiedAuditLog`) |

### 2.4 Office 365 Security & Compliance Center (Purview / IPPS)

| Permission | Type | Purpose |
|-----------|------|---------|
| `Compliance.ManageAsApp` (Office 365 Exchange Online > Application permissions) | Application | Service principal access to `Connect-IPPSSession` for Purview retention policy validation only (used by `Test-PurviewRetention.ps1` and `Connect-AuditServices.ps1`). Unified Audit Log enablement must still be verified in Exchange Online PowerShell with `Get-AdminAuditLogConfig`. Pair this permission with the **Purview Compliance Admin** role on the service principal. |

### 2.5 Microsoft Graph Audit Search API version note

Microsoft Learn documents the Audit Search API under Microsoft Graph security audit log resources (`/security/auditLog/queries` and `/security/auditLog/queries/{id}/records`) with `AuditLogsQuery-*` permissions. Treat this as an optional query path for ACM until your tenant policy approves the Graph endpoint/version shown in the Microsoft Learn version selector; the shipped validators continue to use Exchange Online PowerShell for Unified Audit Log enablement verification.

### 2.6 Grant Admin Consent

After adding all permissions:

1. Click **Grant admin consent for [Your Organization]**
2. Confirm by clicking **Yes**
3. Verify all permissions show **Status: Granted** with a green checkmark

## 3. Certificate-Based Authentication

Certificate-based authentication is used by the ACV component for non-interactive, automated validation runs via Azure Automation runbooks and Power Automate flows.

### 3.1 Generate a Self-Signed Certificate

Run in PowerShell 7.2+:

```powershell
# Generate a self-signed certificate valid for 2 years
$cert = New-SelfSignedCertificate `
    -Subject "CN=ACM-AuditComplianceManager" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyExportPolicy Exportable `
    -KeySpec Signature `
    -KeyLength 2048 `
    -KeyAlgorithm RSA `
    -HashAlgorithm SHA256 `
    -NotAfter (Get-Date).AddYears(2)

# Display the thumbprint (save this value)
Write-Output "Certificate Thumbprint: $($cert.Thumbprint)"
```

### 3.2 Export the Public Key (.cer)

```powershell
# Export public key for upload to Entra ID app registration
Export-Certificate `
    -Cert "Cert:\CurrentUser\My\$($cert.Thumbprint)" `
    -FilePath ".\ACM-AuditComplianceManager.cer"
```

Upload to Entra ID:

1. Navigate to your app registration → **Certificates & secrets** → **Certificates** tab
2. Click **Upload certificate**
3. Select the `.cer` file
4. Click **Add**

### 3.3 Export the Private Key (.pfx)

```powershell
# Export private key for upload to Azure Automation
$password = ConvertTo-SecureString -String "<your-pfx-password>" -Force -AsPlainText
Export-PfxCertificate `
    -Cert "Cert:\CurrentUser\My\$($cert.Thumbprint)" `
    -FilePath ".\ACM-AuditComplianceManager.pfx" `
    -Password $password
```

Upload to Azure Automation:

1. Navigate to **Azure Automation Account** → **Certificates**
2. Click **+ Add a certificate**
3. Upload the `.pfx` file with the password
4. Record the certificate name for use in runbook parameters

### 3.4 Certificate Renewal

Certificates should be renewed before expiration:

1. Generate a new certificate using the same steps above
2. Upload the new public key to the app registration (old cert can remain until cutover)
3. Upload the new private key to Azure Automation
4. Update the `CertificateThumbprint` variable in all Power Automate flows
5. Remove the old certificate after verifying the new one works

## 4. Client Secret Authentication (Legacy Development Fallback)

Client secrets are a legacy development-only fallback. Use them only for local testing when managed identity or certificate-based app-only authentication is not feasible; replace them with managed identity or certificates before production use.

### 4.1 Create a Client Secret

1. Navigate to your app registration → **Certificates & secrets** → **Client secrets** tab
2. Click **+ New client secret**
3. Configure:
   - **Description:** `ACM Development` (or descriptive name)
   - **Expires:** 6 months (recommended maximum for production; 24 months available)
4. Click **Add**
5. **Immediately copy the secret value** — it is only shown once

### 4.2 Usage in Scripts

```bash
# legacy: dev-only — replace with managed identity in production
# Use client secret instead of certificate for Python scripts
python scripts/deploy.py \
    --environment-url https://org.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --client-id <your-app-client-id> \
    --client-secret <your-secret-value>
```

> **Security Warning:** Never commit client secrets to source control. Client-secret examples are for development only; use managed identity or certificate-based app-only authentication for production deployments.

## 5. Managed Identity Setup for Azure Automation

The ALCA component (detection and remediation runbooks) uses System-Assigned Managed Identity for authentication. This is the recommended production authentication method because there are no certificates or secrets to manage.

### 5.1 Enable System-Assigned Managed Identity

1. Navigate to **Azure Portal** → **Automation Accounts** → your account
2. Under **Account Settings**, click **Identity**
3. On the **System assigned** tab, set **Status** to **On**
4. Click **Save** and confirm
5. Record the **Object (principal) ID** — needed for permission assignments

### 5.2 Assign Entra ID Roles

Assign the following roles to the Managed Identity using PowerShell or the Entra admin center:

```powershell
# Connect to Microsoft Graph
Connect-MgGraph -Scopes "RoleManagement.ReadWrite.Directory"

$miObjectId = "<managed-identity-object-id>"

# Assign Power Platform Admin role (Entra display name: Power Platform Administrator)
$ppAdminRole = Get-MgDirectoryRole -Filter "displayName eq 'Power Platform Administrator'"
New-MgDirectoryRoleMember -DirectoryRoleId $ppAdminRole.Id `
    -BodyParameter @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$miObjectId" }

# Assign Exchange Online Admin (Entra role display name = 'Exchange Administrator')
$exAdminRole = Get-MgDirectoryRole -Filter "displayName eq 'Exchange Administrator'"
New-MgDirectoryRoleMember -DirectoryRoleId $exAdminRole.Id `
    -BodyParameter @{ "@odata.id" = "https://graph.microsoft.com/v1.0/directoryObjects/$miObjectId" }
```

### 5.3 Grant Dataverse Application User Access

The Managed Identity must be configured as an Application User in **every** Dataverse environment you want to scan or remediate:

1. Navigate to the [Power Platform admin center](https://admin.powerplatform.microsoft.com)
2. Select the target environment → **Settings** → **Users + permissions** → **Application users**
3. Click **+ New app user**
4. Click **+ Add an app** and search for the Managed Identity by its Object ID or name
5. Select the **Business unit** (root business unit)
6. Under **Security roles**, assign **System Administrator**
7. Click **Create**

Repeat for each environment the solution will monitor.

> **Important:** Without the Application User configuration, remediation will fail with `401 Unauthorized` errors. This is a per-environment setting — there is no tenant-wide option.

### 5.4 Grant Microsoft Graph API Permissions

```powershell
# Grant Mail.Send permission to the Managed Identity
Connect-MgGraph -Scopes "Application.Read.All", "AppRoleAssignment.ReadWrite.All"

$miObjectId = "<managed-identity-object-id>"
$graphApp = Get-MgServicePrincipal -Filter "appId eq '00000003-0000-0000-c000-000000000000'"
$mailSendRole = $graphApp.AppRoles | Where-Object { $_.Value -eq "Mail.Send" }

New-MgServicePrincipalAppRoleAssignment `
    -ServicePrincipalId (Get-MgServicePrincipal -Filter "displayName eq '<automation-account-name>'").Id `
    -PrincipalId $miObjectId `
    -ResourceId $graphApp.Id `
    -AppRoleId $mailSendRole.Id
```

## 6. Interactive Authentication (Development/Testing)

For local development and initial setup, use interactive authentication to avoid configuring service principals or Managed Identities.

### 6.1 Python Scripts (MSAL Interactive)

```bash
# The --interactive flag triggers browser-based OAuth login
python scripts/deploy.py \
    --environment-url https://org.crm.dynamics.com \
    --tenant-id <your-tenant-id> \
    --client-id <your-app-client-id> \
    --interactive
```

The `--interactive` flag uses MSAL's interactive auth flow, which opens a browser window for sign-in. The signed-in user must have sufficient permissions (Entra Global Admin or Dataverse System Administrator).

### 6.2 PowerShell Scripts (ACV Validators)

```powershell
# ACV validators use the -Interactive switch for local testing
.\scripts\Invoke-TenantAuditValidation.ps1 -Zone Zone3 -Interactive -Verbose

.\scripts\Invoke-EnvironmentDiscovery.ps1 `
    -DataverseUrl "https://org.crm.dynamics.com" `
    -TenantId "<your-tenant-id>" `
    -Interactive
```

### 6.3 PowerShell Scripts (ALCA Runbooks)

ALCA scripts (`Test-AuditLoggingCompliance.ps1`, `Enable-AuditLogging.ps1`) are designed for Azure Automation and use Managed Identity by default. For local testing outside Azure Automation, authentication is not directly supported — use the ACV validators for local validation, and test ALCA runbooks via the Azure Automation **Test pane**.

## 7. Troubleshooting

### Common Authentication Errors

| Error | Cause | Solution |
|-------|-------|----------|
| `AADSTS700016: Application not found` | Incorrect `--client-id` or app not in the specified tenant | Verify the Application (client) ID matches the app registration |
| `AADSTS7000215: Invalid client secret` | Client secret expired or incorrect | Regenerate the client secret and update the configuration |
| `AADSTS700027: Certificate validation failed` | Certificate not uploaded to app registration or thumbprint mismatch | Re-upload the `.cer` file and verify the thumbprint |
| `401 Unauthorized` on Dataverse API | Managed Identity or Service Principal not configured as Application User | Add the identity as an Application User with System Administrator role |
| `403 Forbidden` on Exchange Online | Missing `Exchange.ManageAsApp` permission or Exchange Online Admin role | Add the API permission and assign the Exchange Online Admin role (Entra display name: `Exchange Administrator`) |
| `Connect-ExchangeOnline: Access denied` | Managed Identity missing Exchange Online Admin role | Assign the Exchange Online Admin role (Entra display name: `Exchange Administrator`) to the MI |
| `Get-AdminPowerAppEnvironment: Unauthorized` | Missing Power Platform Admin role | Assign the Power Platform Admin role (Entra display name: `Power Platform Administrator`) |
| `Send-MgUserMail: Insufficient privileges` | Missing `Mail.Send` permission or admin consent not granted | Add Mail.Send (Application) permission and grant admin consent |
| `Certificate not found in Automation Account` | Certificate not uploaded or name mismatch | Navigate to Automation Account → Certificates and verify upload |

### Verifying Permissions

```powershell
# Check Entra ID role assignments for a Managed Identity
Connect-MgGraph -Scopes "Directory.Read.All"
$mi = Get-MgServicePrincipal -Filter "displayName eq '<automation-account-name>'"
Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $mi.Id | Format-Table

# Check Dataverse Application User
# Navigate to: Power Platform admin center → Environment → Settings → Application users
# Verify the MI appears with System Administrator role
```

---

**Version:** 1.0.4
**Last Updated:** 2026-04-17
**Solution:** Audit Compliance Manager (ACM)
