# Troubleshooting

## Common Issues

### 1. No Audit Data Returned

**Symptoms:**
- `Search-UnifiedAuditLog` returns no results
- Script reports "No CopilotInteraction events found"

**Causes and Solutions:**

| Cause | Solution |
|-------|----------|
| **Audit logging not enabled** | Verify audit is on: `Get-AdminAuditLogConfig \| FL UnifiedAuditLogIngestionEnabled` |
| **Permission issue** | Confirm the managed identity, certificate-backed app, or delegated admin has the tenant role assignments required for audit search |
| **Date range too narrow** | Expand date range; note audit data has ~24hr latency |
| **No Copilot activity** | Verify users are actively using Copilot in tenant |
| **Wrong RecordType** | Confirm using `RecordType = "CopilotInteraction"` |

**Diagnostic Script:**

```powershell
# Check audit status
Get-AdminAuditLogConfig | FL UnifiedAuditLogIngestionEnabled

# Test basic search
Search-UnifiedAuditLog -StartDate (Get-Date).AddDays(-7) -EndDate (Get-Date) -ResultSize 10
```

### 2. Application Insights Query Fails

> **Note:** API key authentication is deprecated. Use Entra ID authentication for all new deployments. Microsoft is retiring the x-api-key query path on **September 30, 2026** (extended from the originally announced March 31, 2026).
>
> **⚠️ Warning: x-api-key query authentication retiring (September 30, 2026)**
>
> If you are troubleshooting API key authentication issues, note that this authentication method is **scheduled for retirement on September 30, 2026** (Microsoft extended this from March 31, 2026). Organizations should migrate to Entra ID authentication rather than continuing to troubleshoot API key issues.
>
> **Migration Path:**
>
> 1. Register an App in Entra ID with Monitoring Reader role
> 2. Replace `-ApiKey` parameter with `Connect-AzAccount` authentication
> 3. Use bearer token authentication via `Get-AzAccessToken`
>
> See [Authentication Migration](prerequisites.md#authentication-migration) for complete migration steps.
>
> *Last verified: 2026-06-04*

**Symptoms:**
- REST API returns 401/403 error
- "Authentication failed" error message

**Causes and Solutions:**

| Cause | Solution |
|-------|----------|
| **Legacy API key dependency** | Migrate the runbook to managed identity or certificate-backed Entra ID authentication |
| **Wrong App ID** | Verify Application ID (not Instrumentation Key) |
| **Expired legacy credential** | Replace the secret path with managed identity or certificate-backed Entra ID authentication |
| **Insufficient permissions** | Assign Monitoring Reader on the Application Insights resource to the managed identity or service principal |
| **Resource not found** | Verify App Insights resource exists and ID is correct |

**Diagnostic Steps (API Key - Deprecated):**

```powershell
# Historical only: API key connectivity test (x-api-key query auth retiring September 30, 2026)
$headers = @{ "x-api-key" = "your-key" }
$uri = "https://api.applicationinsights.io/v1/apps/your-app-id/query?query=customEvents|take 1"
Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
```

**Diagnostic Steps (Entra ID - Recommended):**

```powershell
# Test API connectivity with managed identity / Entra ID authentication
Connect-AzAccount -Identity  # Azure Automation managed identity
# Or, on non-Azure schedulers:
# Connect-AzAccount -ServicePrincipal -ApplicationId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
$tokenResult = Get-AzAccessToken -ResourceUrl "https://api.applicationinsights.io"
# Az.Accounts ≥5.0 returns Token as SecureString by default (opt-in via -AsSecureString since 2.17.0); convert to plaintext for HTTP header
$token = if ($tokenResult.Token -is [System.Security.SecureString]) {
    $tokenResult.Token | ConvertFrom-SecureString -AsPlainText
} else {
    $tokenResult.Token
}
$headers = @{ "Authorization" = "Bearer $token" }
$uri = "https://api.applicationinsights.io/v1/apps/your-app-id/query?query=customEvents|take 1"
Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
```

### 3. No RAI Telemetry Events

**Symptoms:**
- Application Insights query returns no ContentFiltered events
- RAI telemetry CSV is empty

**Causes and Solutions:**

| Cause | Solution |
|-------|----------|
| **Agent not configured** | Verify App Insights connection string in Copilot Studio agent settings |
| **Agent not published** | Publish agent after adding App Insights |
| **No filtering occurred** | RAI filters only log when content is blocked |
| **Wrong query** | Verify query filters for `EventName == "MicrosoftCopilotStudio"` after normalizing `customEvents` / `AppEvents` |
| **Telemetry delay** | Allow 5-10 minutes for telemetry to appear |

**Verification Query:**

```kql
// Check if any Copilot Studio events exist in either App Insights shape
union isfuzzy=true
    (customEvents | project EventTime = timestamp, EventName = name),
    (AppEvents | project EventTime = TimeGenerated, EventName = Name)
| where EventTime > ago(7d)
| where EventName == "MicrosoftCopilotStudio"
| summarize count() by EventName
```

### 4. Blob Upload Fails

**Symptoms:**
- "Failed to upload" error
- "AuthorizationFailure" or "403 Forbidden"

**Causes and Solutions:**

| Cause | Solution |
|-------|----------|
| **No RBAC permission** | Assign "Storage Blob Data Contributor" role |
| **Container doesn't exist** | Create container before upload |
| **Immutable policy conflict** | Ensure not trying to overwrite immutable blob |
| **Network restriction** | Check storage firewall allows access |
| **Wrong authentication** | Use `-UseConnectedAccount` for Microsoft Entra ID auth |

**Diagnostic Script:**

```powershell
# Test storage access
$context = New-AzStorageContext -StorageAccountName "youraccount" -UseConnectedAccount
Get-AzStorageContainer -Context $context
```

### 5. Power BI Refresh Fails

**Symptoms:**
- Scheduled refresh shows "Failed"
- "Data source error" or "Credentials expired"

**Causes and Solutions:**

| Cause | Solution |
|-------|----------|
| **Credentials expired** | Update data source credentials in dataset settings |
| **Storage key rotated** | Update storage account key in Power BI |
| **File not found** | Verify extraction ran and file exists at expected path |
| **Schema change** | If CSV columns changed, reimport in Power BI Desktop |
| **Gateway offline** | For on-premises sources, check gateway status |

**Resolution Steps:**

1. Open Power BI Service
2. Navigate to Dataset > Settings
3. Expand "Data source credentials"
4. Click "Edit credentials"
5. Re-enter credentials and test connection

### 6. Exchange Online Connection Issues

**Symptoms:**
- "Connect-ExchangeOnline" fails
- "The remote server returned an error"

**Causes and Solutions:**

| Cause | Solution |
|-------|----------|
| **Module not installed** | `Install-Module ExchangeOnlineManagement` |
| **Module outdated** | `Update-Module ExchangeOnlineManagement` |
| **MFA required** | Use managed identity in Azure Automation or certificate-based app-only auth for non-Azure schedulers |
| **Conditional Access** | Prefer workload identity controls for managed identities/apps instead of long-lived user service accounts |
| **Network timeout** | Check firewall rules for Exchange Online endpoints |

**Managed Identity / Certificate-Based Authentication Setup:**

```powershell
# Preferred in Azure Automation
Connect-ExchangeOnline -ManagedIdentity -Organization "example.onmicrosoft.com"

# Fallback for non-Azure schedulers: certificate auth
Connect-ExchangeOnline `
    -CertificateThumbprint "your-cert-thumbprint" `
    -AppId "your-app-id" `
    -Organization "example.onmicrosoft.com"
```

### 7. Microsoft Graph Audit Search (v1.0)

The Graph audit search endpoint (`POST /security/auditLog/queries`) is generally available on the Microsoft Graph v1.0 endpoint with `AuditLogsQuery.Read.All` (or service-specific `AuditLogsQuery-*.Read.All`) permissions. If you call it through the Graph PowerShell SDK outside this production extractor, the `auditLogQuery` cmdlets are currently available in `Microsoft.Graph.Beta.Security`; validate query coverage and response shapes for regulated evidence before relying on it.

## Performance Issues

### Slow Audit Log Search

**Symptoms:**
- Search takes >30 minutes
- Timeout errors

**Solutions:**

1. **Narrow date range** - Search smaller windows (1 day instead of 7)
2. **Use pagination** - Process results in batches of 5000
3. **Filter early** - Add FreeText filters if searching for specific users
4. **Run during off-peak** - Schedule for early morning UTC

### Large Export Files

**Symptoms:**
- CSV files exceed 100MB
- Power BI refresh slow

**Solutions:**

1. **Compress exports** - Use `Compress-Archive` before upload
2. **Incremental load** - Configure Power BI incremental refresh
3. **Filter in extraction** - Only export deny events, not all interactions
4. **Archive old data** - Move historical data to cold storage

## Logging and Diagnostics

### Enable Verbose Logging

```powershell
# Run scripts with -Verbose flag
.\scripts\Export-CopilotDenyEvents.ps1 -Verbose

# Or set preference
$VerbosePreference = "Continue"
```

### Check Azure Automation Job Output

1. Open Azure Automation Account
2. Navigate to **Process Automation** > **Jobs**
3. Select the failed job
4. Click **Output** or **Errors** tabs

### Application Insights Diagnostics

```kql
// Check for App Insights ingestion issues
traces
| where timestamp > ago(1h)
| where severityLevel >= 3  // Warning and above
| project timestamp, message, severityLevel
```

## Getting Help

### Log Collection

When reporting issues, include:

1. **Script output** - Full console output including errors
2. **Environment details** - PowerShell version, module versions
3. **Permissions** - Current role assignments
4. **Sanitized configuration** - Remove secrets but include structure

### Support Channels

- **Framework issues:** [FSI-AgentGov GitHub Issues](https://github.com/judeper/FSI-AgentGov/issues)
- **Solution issues:** [FSI-AgentGov-Solutions GitHub Issues](https://github.com/judeper/FSI-AgentGov-Solutions/issues)
- **Microsoft issues:** [Microsoft Support](https://support.microsoft.com)

---

*FSI Agent Governance Framework v1.6.0*
