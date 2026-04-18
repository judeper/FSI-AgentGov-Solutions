# Prerequisites

## Licensing Requirements

### Microsoft 365

| License | Required For |
|---------|--------------|
| **Microsoft 365 E5** or **E5 Compliance** | Unified Audit Log access, extended retention |
| **Power BI Pro** (per user) | Dashboard viewing and scheduled refresh |
| **Power BI Premium** (optional) | Higher refresh frequency, larger datasets |

### Azure

| Service | Required For |
|---------|--------------|
| **Azure Subscription** | Application Insights, Blob Storage, Automation |
| **Application Insights** | RAI telemetry capture |
| **Azure Automation** (optional) | Scheduled extraction |
| **Azure Key Vault** (optional) | Credential management |

### Copilot Studio

| License | Required For |
|---------|--------------|
| **Copilot Studio Premium** | Per-agent Application Insights configuration |

## Permissions

### Microsoft Purview (Audit Log Access)

| Role | Scope | Capabilities |
|------|-------|--------------|
| **Purview Compliance Admin** | Tenant | Full audit access, search, export |
| **View-Only Audit Logs** | Tenant | Search and export only |
| **Security Reader** | Tenant | Read-only access |

**Recommendation:** Create dedicated service account with "View-Only Audit Logs" role for automated extraction.

### Application Insights

| Permission | Scope | Required |
|------------|-------|----------|
| **Reader** | App Insights resource | Query telemetry |
| **Monitoring Reader** | App Insights resource | Entra ID authentication (recommended) |
| ~~**API Key (Read)**~~ | ~~App Insights resource~~ | ~~REST API access~~ (deprecated March 31, 2026) |

> ⚠️ **Deprecation Warning:** API key authentication (`x-api-key`) is deprecated and will be removed **March 31, 2026**. See [Authentication Migration](#authentication-migration) for Entra ID setup.

### Defender for Cloud Apps (Optional)

| Permission | Scope | Required |
|------------|-------|----------|
| **ThreatHunting.Read.All** | Microsoft Graph | Run Advanced Hunting queries |

**Module required:** `Microsoft.Graph.Security`

```powershell
Install-Module Microsoft.Graph.Security -Force
Connect-MgGraph -Scopes "ThreatHunting.Read.All"
```

### Azure Automation (Optional)

| Role | Scope | Capabilities |
|------|-------|--------------|
| **Automation Contributor** | Automation Account | Manage runbooks, schedules |
| **Key Vault Secrets User** | Key Vault | Read secrets for credentials |
| **Storage Blob Data Contributor** | Storage Account | Upload exports |

### Power BI

| Role | Scope | Capabilities |
|------|-------|--------------|
| **Member** or **Contributor** | Workspace | View and interact with reports |
| **Admin** | Workspace | Configure data source credentials |

## Service Account Setup

### 1. Create Dedicated Service Account

```powershell
# Microsoft Graph PowerShell (recommended — MSOnline module is deprecated)
# NOTE: Use a managed identity or certificate-based authentication in production.
# Avoid PasswordNeverExpires; use conditional access policies and key rotation instead.
$PasswordProfile = @{
    Password                      = "<strong-temporary-password>"
    ForceChangePasswordNextSignIn = $true
}
New-MgUser `
    -UserPrincipalName "svc-deny-report@example.com" `
    -DisplayName "Deny Report Service Account" `
    -UsageLocation "US" `
    -PasswordProfile $PasswordProfile `
    -AccountEnabled:$true `
    -MailNickname "svc-deny-report"

# Assign minimum required license (E5 Compliance)
Set-MgUserLicense -UserId "svc-deny-report@example.com" `
    -AddLicenses @(@{SkuId = "<E5-Compliance-SkuId>"}) `
    -RemoveLicenses @()
```

### 2. Assign Purview Roles

```powershell
# Connect to Security & Compliance PowerShell
Connect-IPPSSession  # Requires ExchangeOnlineManagement v3.0+

# Add to View-Only Audit Logs role group
Add-RoleGroupMember -Identity "View-Only Audit Logs" `
    -Member "svc-deny-report@example.com"
```

### 3. Configure Application Insights Access

#### Option A: Entra ID Authentication (Recommended)

Starting **March 31, 2026**, API key authentication will no longer work. Configure Entra ID authentication now:

1. Create or use an existing service principal (App Registration)
2. Assign **Monitoring Reader** role on the Application Insights resource:
   ```bash
   az role assignment create \
       --assignee "your-service-principal-id" \
       --role "Monitoring Reader" \
       --scope "/subscriptions/{sub}/resourceGroups/{rg}/providers/microsoft.insights/components/{appinsights}"
   ```
3. Store the service principal credentials in Azure Key Vault
4. Use `Connect-AzAccount` with service principal in automation

#### Option B: API Key (Historical Reference - Removed March 31, 2026)

> **Removed:** As of March 31, 2026 the `x-api-key` authentication path no
> longer functions on the Application Insights REST API. New deployments must
> use Entra ID authentication (Option A above). The steps below are retained
> only for context when migrating older runbooks.

1. Navigate to Azure Portal > Application Insights resource
2. Go to **Configure** > **API Access**
3. Click **Create API key**
4. Name: "Deny Report Service"
5. Permissions: **Read telemetry**
6. Copy the API key (store securely)

### 4. Configure Azure Key Vault (Recommended)

```powershell
# Create Key Vault
az keyvault create `
    --name "kv-deny-report" `
    --resource-group "rg-governance" `
    --location "eastus"

# Store credentials
az keyvault secret set `
    --vault-name "kv-deny-report" `
    --name "ExoServiceAccount" `
    --value "svc-deny-report@example.com"

# NOTE: AppInsightsApiKey no longer needed after Entra ID migration.
# Store service principal credentials instead — see Authentication Migration section below.
```

## Network Requirements

### Outbound Connectivity

| Endpoint | Port | Purpose |
|----------|------|---------|
| `outlook.office365.com` | 443 | Exchange Online PowerShell |
| `compliance.microsoft.com` | 443 | Purview audit search |
| `api.applicationinsights.io` | 443 | App Insights REST API |
| `*.blob.core.windows.net` | 443 | Azure Blob Storage |
| `graph.microsoft.com` | 443 | Defender Advanced Hunting (Graph API) |
| `*.vault.azure.net` | 443 | Azure Key Vault |

### Firewall Rules

If running from on-premises or restricted network:

1. Allow outbound HTTPS (443) to Microsoft endpoints
2. Allow PowerShell remoting ports if using Exchange Online module v2
3. Consider Azure Automation for cloud-native execution

## Copilot Studio Agent Configuration

For RAI telemetry, each Copilot Studio agent requires Application Insights configuration.

### Per-Agent Setup Steps

1. Open **Copilot Studio** portal
2. Select the agent
3. Navigate to **Settings** > **Generative AI**
4. Enable **Advanced settings**
5. Enter Application Insights **Connection String** (not Instrumentation Key)
6. **Save** and **Publish** the agent

### Connection String Format

```
InstrumentationKey=xxx;IngestionEndpoint=https://xxx.in.applicationinsights.azure.com/;LiveEndpoint=https://xxx.livediagnostics.monitor.azure.com/;ApplicationId=xxx
```

### Verification

After configuration, send a test message to the agent and verify telemetry appears:

```kql
customEvents
| where timestamp > ago(1h)
| where name == "MicrosoftCopilotStudio"
| take 10
```

## Pre-Deployment Checklist

- [ ] Microsoft 365 E5/E5 Compliance license assigned
- [ ] Service account created with View-Only Audit Logs role
- [ ] Application Insights resource created
- [ ] ~~Application Insights API key generated and stored~~ **OR** Entra ID service principal configured (recommended)
- [ ] Copilot Studio agents configured with App Insights (Zone 2/3)
- [ ] Azure Blob Storage account created (optional)
- [ ] Azure Key Vault configured with credentials (optional)
- [ ] Power BI workspace created with appropriate access
- [ ] Network connectivity verified from execution environment

---

## Authentication Migration

> **Note:** API key authentication is deprecated. Use Entra ID authentication for all new deployments.

### Timeline

| Date | Event |
|------|-------|
| **Now** | Begin migration to Entra ID authentication |
| **March 31, 2026** | x-api-key authentication **permanently disabled** |
| **After March 31, 2026** | All scripts using API keys will fail |

### Migration Steps

1. **Create Service Principal**
   ```bash
   az ad sp create-for-rbac --name "DenyReportService" --skip-assignment
   ```
   Save the output (appId, password, tenant).

2. **Assign Monitoring Reader Role**
   ```bash
   az role assignment create \
       --assignee "{appId}" \
       --role "Monitoring Reader" \
       --scope "/subscriptions/{sub}/resourceGroups/{rg}/providers/microsoft.insights/components/{appinsights-name}"
   ```

3. **Store Credentials in Key Vault**
   ```bash
   az keyvault secret set --vault-name "kv-deny-report" --name "ServicePrincipalId" --value "{appId}"
   az keyvault secret set --vault-name "kv-deny-report" --name "ServicePrincipalSecret" --value "{password}"
   az keyvault secret set --vault-name "kv-deny-report" --name "TenantId" --value "{tenant}"
   ```

4. **Update Scripts**

   Replace API key authentication with Entra ID:
   ```powershell
   # Old (deprecated)
   $headers = @{ "x-api-key" = $ApiKey }

   # New (Entra ID)
   Connect-AzAccount -ServicePrincipal -ApplicationId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
   $tokenResult = Get-AzAccessToken -ResourceUrl "https://api.applicationinsights.io"
   # Az.Accounts ≥3.0 returns Token as SecureString; convert to plaintext for HTTP header
   $tokenString = if ($tokenResult.Token -is [System.Security.SecureString]) {
       $tokenResult.Token | ConvertFrom-SecureString -AsPlainText
   } else {
       $tokenResult.Token
   }
   $headers = @{ "Authorization" = "Bearer $tokenString" }
   ```

5. **Test Before Deadline**

   Run test queries with new authentication to verify access before March 31, 2026.

### Reference

- [Azure Monitor deprecation announcement](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/api/deprecation)
- [Entra ID authentication for Azure Monitor](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/api/access-api)

---

*FSI Agent Governance Framework v1.2 - January 2026*
