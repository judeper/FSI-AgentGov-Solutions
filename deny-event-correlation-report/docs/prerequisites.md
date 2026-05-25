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

**Recommendation:** Use an Azure Automation managed identity for scheduled extraction. Use a dedicated user only for manual troubleshooting, and validate the exact Purview/Exchange RBAC role set in your tenant before production use.

### Application Insights

| Permission | Scope | Required |
|------------|-------|----------|
| **Reader** | App Insights resource | Query telemetry |
| **Monitoring Reader** | App Insights resource | Managed identity / Entra ID authentication (recommended) |
| ~~**API Key (Read)**~~ | ~~App Insights resource~~ | ~~REST API access~~ (deprecated March 31, 2026) |

> ⚠️ **Deprecation Warning:** API key authentication (`x-api-key`) is deprecated and will be removed **March 31, 2026**. See [Authentication Migration](#authentication-migration) for Entra ID setup.

### Defender for Cloud Apps (Optional)

| Permission | Scope | Required |
|------------|-------|----------|
| **ThreatHunting.Read.All** | Microsoft Graph | Run Advanced Hunting queries |

**Module required:** `Microsoft.Graph.Security`

```powershell
Install-Module Microsoft.Graph.Security -Force
# Managed identity or certificate auth is recommended for automation where supported.
# Interactive delegated auth is acceptable for one-off validation.
Connect-MgGraph -Scopes "ThreatHunting.Read.All"
```

### Azure Automation (Optional)

| Role | Scope | Capabilities |
|------|-------|--------------|
| **Automation Contributor** | Automation Account | Manage runbooks, schedules |
| **Key Vault Secrets User** | Key Vault | Read non-secret configuration or approved certificate metadata |
| **Storage Blob Data Contributor** | Storage Account | Upload exports |

### Power BI

| Role | Scope | Capabilities |
|------|-------|--------------|
| **Member** or **Contributor** | Workspace | View and interact with reports |
| **Admin** | Workspace | Configure data source credentials |

## Automation Identity Setup

### Recommended: Azure Automation Managed Identity

Use a system-assigned or user-assigned managed identity for scheduled runbooks. This avoids stored passwords and aligns with current Exchange Online PowerShell and Azure Monitor authentication guidance.

1. Enable the managed identity on the Azure Automation account.
2. Grant the identity the required Exchange Online application permission and role assignments for unattended Exchange Online PowerShell:
   - Office 365 Exchange Online API permission: `Exchange.ManageAsApp`
   - Exchange role assignment appropriate for audit search in your tenant (for example, View-Only Audit Logs / audit-reader duties)
   - Validate with `Search-UnifiedAuditLog` before enabling the schedule.
3. Grant Azure RBAC on supporting resources:
   - **Monitoring Reader** on the Application Insights component
   - **Storage Blob Data Contributor** on the target storage account when uploads are enabled
   - **Key Vault Secrets User** only when the runbook reads non-secret configuration from Key Vault
4. Connect from the runbook with managed identity:

```powershell
Connect-AzAccount -Identity
Connect-ExchangeOnline -ManagedIdentity -Organization "example.onmicrosoft.com"

.\scripts\Invoke-DailyDenyReport.ps1 `
    -ExchangeManagedIdentity `
    -ExchangeOrganization "example.onmicrosoft.com" `
    -AppInsightsAppId "<application-insights-app-id>" `
    -StorageAccountName "stgovernance"
```

### Fallback: Certificate-Based App-Only Exchange Online Auth

Use certificate-based app-only authentication when the scheduler cannot use Azure managed identity. Store the certificate private key in the platform certificate store or a managed HSM/Key Vault flow approved by your security team; do not store certificate passwords in source control.

```powershell
Connect-ExchangeOnline `
    -AppId "<app-client-id>" `
    -CertificateThumbprint "<certificate-thumbprint>" `
    -Organization "example.onmicrosoft.com"

.\scripts\Invoke-DailyDenyReport.ps1 `
    -ExchangeAppId "<app-client-id>" `
    -ExchangeCertificateThumbprint "<certificate-thumbprint>" `
    -ExchangeOrganization "example.onmicrosoft.com"
```

### Microsoft Graph Audit Search Preview

The production extractors currently use `Search-UnifiedAuditLog`. Microsoft Graph exposes Microsoft Purview audit search in beta at `GET/POST /security/auditLog/queries` with `AuditLogsQuery.*` permissions (for example, `AuditLogsQuery.Read.All` or service-specific permissions). Because Microsoft Graph beta APIs are subject to change and are not supported for production use, treat this as a preview migration path until the endpoint is available in v1.0 and validated for your tenant.

### Application Insights Access

1. Assign **Monitoring Reader** to the managed identity or certificate-backed service principal on the Application Insights resource.
2. Authenticate with `Connect-AzAccount -Identity` in Azure Automation or with a certificate-backed service principal on non-Azure schedulers.
3. `Export-RaiTelemetry.ps1` obtains an Entra ID token with `Get-AzAccessToken -ResourceUrl "https://api.applicationinsights.io"`.

### Azure Key Vault Usage

Use Key Vault for non-secret configuration values (for example, `AppInsightsAppId`) or certificate lifecycle integration. Do not store user passwords for scheduled extraction.

```powershell
az keyvault secret set `
    --vault-name "kv-deny-report" `
    --name "AppInsightsAppId" `
    --value "<application-insights-app-id>"
```

### Legacy Development-Only Client Secret Fallback

Client secrets are not recommended for production runbooks. If a developer workstation temporarily uses a service principal secret for local testing, mark the code path clearly and replace it before deployment:

```powershell
# legacy: dev-only — replace with managed identity in production
$credential = Get-Credential -Message "Service principal client secret for local testing only"
Connect-AzAccount -ServicePrincipal -TenantId "<tenant-id>" -Credential $credential
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
union isfuzzy=true
    (customEvents | project EventTime = timestamp, EventName = name, Dimensions = todynamic(customDimensions)),
    (AppEvents | project EventTime = TimeGenerated, EventName = Name, Dimensions = todynamic(Properties))
| where EventTime > ago(1h)
| where EventName == "MicrosoftCopilotStudio"
| take 10
```

## Pre-Deployment Checklist

- [ ] Microsoft 365 E5/E5 Compliance license assigned
- [ ] Managed identity enabled, or certificate-based Exchange Online app-only auth configured
- [ ] Application Insights resource created
- [ ] Monitoring Reader assigned to the managed identity or certificate-backed service principal
- [ ] Copilot Studio agents configured with App Insights (Zone 2/3)
- [ ] Azure Blob Storage account created (optional)
- [ ] Azure Key Vault configured for non-secret settings or certificate metadata (optional)
- [ ] Power BI workspace created with appropriate access
- [ ] Network connectivity verified from execution environment

---

## Authentication Migration

> **Note:** API key authentication is no longer the recommended path. Use managed identity or certificate-backed Entra ID authentication for new deployments.

### Timeline

| Date | Event |
|------|-------|
| **Now** | Use managed identity-first authentication for Azure Automation runbooks |
| **March 31, 2026** | x-api-key authentication permanently disabled |
| **After March 31, 2026** | Runbooks that still depend on API keys fail until migrated |

### Migration Steps

1. **Enable managed identity** on the Azure Automation account, or configure certificate-based app-only auth for non-Azure schedulers.
2. **Assign Monitoring Reader** on the Application Insights component.
3. **Assign Exchange Online unattended auth** permissions and role assignments for Purview Audit extraction.
4. **Update runbook invocation** to pass `-ExchangeManagedIdentity -ExchangeOrganization "example.onmicrosoft.com"` or the certificate-based parameters.
5. **Remove API key and client secret dependencies** from Key Vault. Retain only non-secret configuration such as the Application Insights App ID.
6. **Test before scheduling** with a one-day window and `-SkipDefenderEvents` until Microsoft Graph authentication is configured.

### Reference

- [Azure Monitor API migration guide](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/api/migrate-batch-and-beta)
- [Entra ID authentication for Azure Monitor](https://learn.microsoft.com/en-us/azure/azure-monitor/logs/api/access-api)

---

*FSI Agent Governance Framework v1.6.0*
