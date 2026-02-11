# Prerequisites

Complete requirements for deploying the Conditional Access Automation solution.

## Licensing Requirements

### Required Licenses

| License | Purpose | Required For |
|---------|---------|--------------|
| Microsoft Entra ID P1 | Basic Conditional Access | All deployments |
| Microsoft Entra ID P2 | Risk-based CA, Sign-in risk | Zone 1 risk-based policies |

### Optional Licenses

| License | Purpose | Benefit |
|---------|---------|---------|
| Microsoft 365 E5 Security | Advanced threat protection | Enhanced risk signals |
| Microsoft Defender for Cloud Apps | App visibility | Shadow AI detection |

### License Verification

```powershell
# Connect to Microsoft Graph
Connect-MgGraph -Scopes "Organization.Read.All"

# Check tenant licenses
Get-MgSubscribedSku | Where-Object {
    $_.SkuPartNumber -match "AAD_PREMIUM|IDENTITY"
} | Select-Object SkuPartNumber, ConsumedUnits, PrepaidUnits
```

Expected output for P2:
```
SkuPartNumber           ConsumedUnits PrepaidUnits
-------------           ------------- ------------
AAD_PREMIUM_P2          150           200
```

---

## Role Requirements

### Deployment Roles

| Role | Purpose | Scope |
|------|---------|-------|
| Conditional Access Administrator | Create and manage CA policies | Required |
| Application Administrator | Register service principal | One-time setup |
| Security Administrator | View reports and logs | Optional (monitoring) |

### Automation Roles

The service principal requires these Microsoft Graph permissions:

| Permission | Type | Purpose |
|------------|------|---------|
| `Policy.Read.All` | Application | Read existing policies |
| `Policy.ReadWrite.ConditionalAccess` | Application | Create/update policies |
| `Application.Read.All` | Application | Read app registrations |
| `Directory.Read.All` | Application | Read directory objects |
| `AuditLog.Read.All` | Application | Read audit logs (evidence) |

### Role Assignment Verification

```powershell
# Check current user roles
Connect-MgGraph -Scopes "RoleManagement.Read.Directory"

$userId = (Get-MgContext).Account
Get-MgUserMemberOf -UserId $userId | Where-Object {
    $_.'@odata.type' -eq '#microsoft.graph.directoryRole'
} | Select-Object -ExpandProperty AdditionalProperties |
    Select-Object displayName
```

---

## Azure Key Vault

Required for secure credential storage in automated deployments.

### Key Vault Setup

```bash
# Create Key Vault (if needed)
az keyvault create \
    --name caa-credentials-kv \
    --resource-group rg-fsi-governance \
    --location eastus \
    --enable-soft-delete true \
    --enable-purge-protection true

# Grant access to automation identity
az keyvault set-policy \
    --name caa-credentials-kv \
    --object-id <service-principal-object-id> \
    --secret-permissions get list
```

### Required Secrets

| Secret Name | Content |
|-------------|---------|
| `CAA-SP-ClientId` | Service principal application ID |
| `CAA-SP-ClientSecret` | Service principal client secret |
| `CAA-TenantId` | Azure AD tenant ID |

---

## PowerShell Requirements

### PowerShell Version

- **Minimum:** PowerShell 7.0
- **Recommended:** PowerShell 7.4+

```powershell
# Check version
$PSVersionTable.PSVersion
```

### Required Modules

```powershell
# Install required modules
Install-Module Microsoft.Graph -Scope CurrentUser -Force
Install-Module Microsoft.Graph.Identity.SignIns -Scope CurrentUser -Force
Install-Module Az.KeyVault -Scope CurrentUser -Force
Install-Module Az.Accounts -Scope CurrentUser -Force

# Verify installation
Get-Module -ListAvailable Microsoft.Graph* | Select-Object Name, Version
```

### Module Versions

| Module | Minimum Version |
|--------|-----------------|
| Microsoft.Graph | 2.0.0 |
| Microsoft.Graph.Identity.SignIns | 2.0.0 |
| Az.KeyVault | 5.0.0 |
| Az.Accounts | 3.0.0 |

---

## Network Requirements

### Outbound Connectivity

| Endpoint | Port | Purpose |
|----------|------|---------|
| `graph.microsoft.com` | 443 | Microsoft Graph API |
| `login.microsoftonline.com` | 443 | Entra ID authentication |
| `*.vault.azure.net` | 443 | Azure Key Vault |

### Firewall Rules

If using Azure Firewall or corporate proxy:

```
graph.microsoft.com:443
login.microsoftonline.com:443
*.vault.azure.net:443
management.azure.com:443
```

---

## Break-Glass Accounts

**Critical:** Before deploying any CA policies, ensure you have emergency access accounts.

### Requirements

1. **Two accounts minimum** - Redundancy for emergency access
2. **Cloud-only** - No on-premises sync dependency
3. **Excluded from ALL CA policies** - Never blocked
4. **Strong credentials** - Long passwords, hardware keys
5. **Monitored** - Alerts on any sign-in

### Setup Verification

```powershell
# Verify break-glass accounts exist
$breakGlassAccounts = @(
    "breakglass1@yourtenant.onmicrosoft.com",
    "breakglass2@yourtenant.onmicrosoft.com"
)

foreach ($account in $breakGlassAccounts) {
    $user = Get-MgUser -Filter "userPrincipalName eq '$account'"
    if ($user) {
        Write-Host "✓ Found: $account" -ForegroundColor Green
    } else {
        Write-Host "✗ Missing: $account" -ForegroundColor Red
    }
}
```

### Add to Templates

Update all policy templates to exclude break-glass accounts:

```json
{
  "conditions": {
    "users": {
      "excludeUsers": [
        "<break-glass-account-1-object-id>",
        "<break-glass-account-2-object-id>"
      ]
    }
  }
}
```

---

## Application Registrations

### AI Applications to Target

Identify the application IDs for AI workloads in your tenant:

| Application | App ID (Global) | Notes |
|-------------|-----------------|-------|
| Microsoft 365 Copilot | `fb8d773d-7ef8-4ec0-a117-179f88add510` | M365 embedded Copilot |
| Copilot Studio | Varies by tenant | Check enterprise apps |
| Power Platform | `475226c6-020e-4fb2-8571-c63252b0c2f4` | Power Apps/Automate |

### Find Application IDs

```powershell
# List enterprise applications for AI services
Get-MgServicePrincipal -Filter "displayName eq 'Microsoft 365 Copilot'" |
    Select-Object DisplayName, AppId, Id

# Or search by keyword
Get-MgServicePrincipal -Filter "startswith(displayName, 'Copilot')" |
    Select-Object DisplayName, AppId
```

---

## Pre-Deployment Checklist

### Licensing
- [ ] Entra ID P1 or P2 active
- [ ] Licenses assigned to target users
- [ ] Risk-based licensing (P2) if using Zone 1 templates

### Roles
- [ ] Conditional Access Administrator assigned
- [ ] Application Administrator for SP setup
- [ ] Global Reader for audit (optional)

### Azure
- [ ] Key Vault created/identified
- [ ] Access policies configured
- [ ] Service principal registered

### PowerShell
- [ ] PowerShell 7+ installed
- [ ] Microsoft.Graph modules installed
- [ ] Az modules installed

### Break-Glass
- [ ] Two emergency accounts created
- [ ] Accounts are cloud-only
- [ ] Object IDs documented for exclusions

### Applications
- [ ] Target application IDs identified
- [ ] Applications exist in enterprise apps

---

## Estimated Deployment Time

| Phase | Duration | Activities |
|-------|----------|------------|
| Prerequisites | 1-2 hours | Licensing, roles, Key Vault |
| Service Principal | 30 minutes | Registration and permissions |
| Template customization | 1-2 hours | Update exclusions, app IDs |
| Deployment (report-only) | 30 minutes | Deploy and verify |
| Testing | 2-4 hours | Validate policy behavior |
| Enable policies | 30 minutes | Switch from report-only |
| **Total** | **5-9 hours** | Across 1-2 days |

---

## Tier 2: Azure Automation Requirements

These prerequisites are required for unattended daily compliance scans via Azure Automation.

### Azure Automation Account

| Requirement | Detail |
|-------------|--------|
| Azure Automation account | Standard tier, any supported region |
| Identity | System-assigned managed identity **or** certificate-based service principal |
| Runbook runtime | PowerShell 7.2+ runtime environment |
| Az.Accounts module | Imported into Automation account (v3.0.0+) |

```powershell
# Verify Azure Automation account
Get-AzAutomationAccount -ResourceGroupName "rg-fsi-governance" |
    Select-Object AutomationAccountName, State, Location

# Import required module
Import-AzAutomationModule `
    -AutomationAccountName "caa-automation" `
    -ResourceGroupName "rg-fsi-governance" `
    -Name "Az.Accounts" `
    -ContentLinkUri "https://www.powershellgallery.com/api/v2/package/Az.Accounts"
```

### Certificate Authentication

For unattended runbook execution, certificate-based authentication is recommended over client secrets.

| Requirement | Detail |
|-------------|--------|
| Certificate | Self-signed or CA-issued, RSA 2048-bit minimum |
| Key Vault storage | Certificate stored in Azure Key Vault |
| App registration | Certificate uploaded to Entra ID app registration |
| Automation credential | Certificate thumbprint configured in Automation account |

```powershell
# Create self-signed certificate for automation
$cert = New-SelfSignedCertificate `
    -Subject "CN=CAA-Automation" `
    -CertStoreLocation "Cert:\CurrentUser\My" `
    -KeyExportPolicy Exportable `
    -KeySpec Signature `
    -KeyLength 2048 `
    -NotAfter (Get-Date).AddYears(2)
```

---

## Tier 2: Dataverse Requirements

These prerequisites are required for compliance evidence persistence and Power Automate flows.

### Power Platform Environment

| Requirement | Detail |
|-------------|--------|
| Power Platform environment | Production or Sandbox with Dataverse database |
| Dataverse database | Provisioned and accessible |
| Security role | Service account assigned System Administrator or custom role with table CRUD |
| CAA schema deployed | Three tables created via `create_dataverse_schema.py` |

### Dataverse Deployment Checklist

- [ ] Power Platform environment created
- [ ] Dataverse database provisioned
- [ ] Service account has appropriate security role
- [ ] Schema deployed (`python scripts/create_dataverse_schema.py`)
- [ ] Environment variables deployed (`python scripts/create_environment_variables.py`)
- [ ] Connection references deployed (`python scripts/create_connection_references.py`)

### API Permissions for Dataverse

In addition to the Graph API permissions listed above, Dataverse access requires:

| Permission | Scope | Purpose |
|------------|-------|---------|
| Dataverse Web API | `https://<org>.crm.dynamics.com/.default` | Read/write Dataverse tables |

---

## Tier 2: Expanded Permissions Reference

### Complete API Permissions Table

| API Permission | Type | Purpose | Admin Consent |
|---------------|------|---------|:-------------:|
| `Policy.Read.All` | Application | Read CA policies | Yes |
| `Policy.ReadWrite.ConditionalAccess` | Application | Create/update CA policies | Yes |
| `Application.Read.All` | Application | Read app registrations | Yes |
| `Directory.Read.All` | Application | Read directory objects (users, groups) | Yes |
| `AuditLog.Read.All` | Application | Read audit logs for evidence collection | Yes |

### Automation Network Endpoints

| Endpoint | Port | Purpose |
|----------|------|---------|
| `graph.microsoft.com` | 443 | Microsoft Graph API (CA policy management) |
| `login.microsoftonline.com` | 443 | Entra ID authentication |
| `*.vault.azure.net` | 443 | Azure Key Vault (credential storage) |
| `*.crm.dynamics.com` | 443 | Dataverse Web API (evidence persistence) |
| `management.azure.com` | 443 | Azure Management API (Automation account) |

---

## Tier 2: Pre-Deployment Checklist

### Azure Automation
- [ ] Automation account created in target subscription
- [ ] System-assigned managed identity enabled (or certificate configured)
- [ ] Az.Accounts module imported
- [ ] Runbook uploaded (`Start-CAAValidationRunbook.ps1`)

### Dataverse
- [ ] Power Platform environment with Dataverse provisioned
- [ ] Service account security role assigned
- [ ] Schema deployed (3 tables, 2 option sets)
- [ ] Environment variables deployed (7 variables)
- [ ] Connection references deployed (4 references)

### Power Automate
- [ ] Daily compliance flow imported (`caa-daily-compliance-flow.json`)
- [ ] Connection references configured with valid connections
- [ ] Flow tested in manual trigger mode before enabling schedule
