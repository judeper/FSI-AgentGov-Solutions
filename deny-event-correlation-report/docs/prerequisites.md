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
| **Compliance Administrator** | Tenant | Full audit access, search, export |
| **View-Only Audit Logs** | Tenant | Search and export only |
| **Security Reader** | Tenant | Read-only access |

**Recommendation:** Create dedicated service account with "View-Only Audit Logs" role for automated extraction.

### Application Insights

| Permission | Scope | Required |
|------------|-------|----------|
| **Reader** | App Insights resource | Query telemetry |
| **API Key (Read)** | App Insights resource | REST API access |

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
# Microsoft 365 Admin Center or PowerShell
New-MsolUser `
    -UserPrincipalName "svc-deny-report@contoso.com" `
    -DisplayName "Deny Report Service Account" `
    -UsageLocation "US" `
    -PasswordNeverExpires $true

# Assign minimum required license (E5 Compliance)
Set-MsolUserLicense -UserPrincipalName "svc-deny-report@contoso.com" `
    -AddLicenses "contoso:SPE_E5"
```

### 2. Assign Purview Roles

```powershell
# Connect to Security & Compliance PowerShell
Connect-IPPSSession

# Add to View-Only Audit Logs role group
Add-RoleGroupMember -Identity "View-Only Audit Logs" `
    -Member "svc-deny-report@contoso.com"
```

### 3. Create Application Insights API Key

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
    --value "svc-deny-report@contoso.com"

az keyvault secret set `
    --vault-name "kv-deny-report" `
    --name "AppInsightsApiKey" `
    --value "your-api-key"
```

## Network Requirements

### Outbound Connectivity

| Endpoint | Port | Purpose |
|----------|------|---------|
| `outlook.office365.com` | 443 | Exchange Online PowerShell |
| `compliance.microsoft.com` | 443 | Purview audit search |
| `api.applicationinsights.io` | 443 | App Insights REST API |
| `*.blob.core.windows.net` | 443 | Azure Blob Storage |
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
- [ ] Application Insights API key generated and stored
- [ ] Copilot Studio agents configured with App Insights (Zone 2/3)
- [ ] Azure Blob Storage account created (optional)
- [ ] Azure Key Vault configured with credentials (optional)
- [ ] Power BI workspace created with appropriate access
- [ ] Network connectivity verified from execution environment

---

*FSI Agent Governance Framework v1.2 - January 2026*
