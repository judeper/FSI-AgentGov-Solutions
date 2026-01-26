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
| **Permission issue** | Confirm service account has "View-Only Audit Logs" role |
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

**Symptoms:**
- REST API returns 401/403 error
- "Authentication failed" error message

**Causes and Solutions:**

| Cause | Solution |
|-------|----------|
| **Invalid API key** | Regenerate API key in Azure Portal |
| **Wrong App ID** | Verify Application ID (not Instrumentation Key) |
| **Key expired** | Create new API key if policy requires rotation |
| **Insufficient permissions** | Ensure API key has "Read telemetry" permission |
| **Resource not found** | Verify App Insights resource exists and ID is correct |

**Diagnostic Steps:**

```powershell
# Test API connectivity
$headers = @{ "x-api-key" = "your-key" }
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
| **Wrong query** | Verify query filters for `name == "MicrosoftCopilotStudio"` |
| **Telemetry delay** | Allow 5-10 minutes for telemetry to appear |

**Verification Query:**

```kql
// Check if any Copilot Studio events exist
customEvents
| where timestamp > ago(7d)
| where name == "MicrosoftCopilotStudio"
| summarize count() by name
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
| **Wrong authentication** | Use `-UseConnectedAccount` for Azure AD auth |

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
| **MFA required** | Use certificate-based auth for automation |
| **Conditional Access** | Exclude service account from CA policies |
| **Network timeout** | Check firewall rules for Exchange Online endpoints |

**Certificate-Based Authentication Setup:**

```powershell
# For automation, configure certificate auth
Connect-ExchangeOnline `
    -CertificateThumbprint "your-cert-thumbprint" `
    -AppId "your-app-id" `
    -Organization "contoso.onmicrosoft.com"
```

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
.\Export-CopilotDenyEvents.ps1 -Verbose

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

*FSI Agent Governance Framework v1.2 - January 2026*
