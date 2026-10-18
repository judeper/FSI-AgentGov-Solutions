# Troubleshooting

**Last Verified:** 2026-10-16

Product-documentation review only; no tenant execution was performed. See the
[verification record](verification-2026-10-16.md) for sources, discrepancies,
downstream review, and unresolved telemetry-schema assumptions.

## Common Issues

### 1. No Audit Data Returned

**Symptoms:**
- `Search-UnifiedAuditLog` returns no results
- Script reports "No CopilotInteraction events found"

**Causes and Solutions:**

| Cause | Solution |
|-------|----------|
| **Audit logging not enabled** | In **Exchange Online PowerShell**, run `Get-AdminAuditLogConfig \| FL UnifiedAuditLogIngestionEnabled`; the same property always returns False in Security & Compliance PowerShell |
| **Permission issue** | Audit cmdlets require **Audit Logs** or **View-Only Audit Logs** in Exchange; app-only connections also need the documented application permissions and effective cmdlet RBAC |
| **Date range too narrow** | Expand the window and recheck. Availability varies by workload; Microsoft's typical 60-90 minutes for core services is not a Copilot-specific SLA |
| **No Copilot activity** | Verify users are actively using Copilot in tenant |
| **Wrong RecordType** | This extractor uses `-RecordType CopilotInteraction` (261); confirm that the tested app/activity emits that record type before concluding there was no activity |

**Diagnostic Script:**

```powershell
# Run in Exchange Online PowerShell, not Security & Compliance PowerShell
Get-AdminAuditLogConfig | FL UnifiedAuditLogIngestionEnabled

# Test basic search
Search-UnifiedAuditLog -StartDate (Get-Date).AddDays(-7) -EndDate (Get-Date) -ResultSize 10
```

This ten-record sample tests basic search, not completeness. See Microsoft's
[audit-status caveat](https://learn.microsoft.com/purview/audit-log-enable-disable),
[audit permissions and availability](https://learn.microsoft.com/purview/audit-search),
and [Copilot activity coverage](https://learn.microsoft.com/purview/audit-copilot).

### 2. Application Insights Query Fails

> **Note:** API key authentication is deprecated. Use Entra ID authentication for all new deployments. Microsoft's retirement notice for the `x-api-key` query path set the retirement date to **September 30, 2026** (extended from the originally announced March 31, 2026); as of 2026-10-09 that date has passed, so do not rely on API keys for querying Application Insights.
>
> **⚠️ Warning: x-api-key query authentication retirement date passed (September 30, 2026)**
>
> If you are troubleshooting API key authentication issues, note that Microsoft's announced retirement date for this authentication method was **September 30, 2026** (extended from March 31, 2026). Organizations should migrate to Entra ID authentication rather than continuing to troubleshoot API key issues.
>
> **Migration Path:**
>
> 1. Use the existing managed identity, or a certificate-backed application's service principal
> 2. Assign Monitoring Reader (or an appropriate supported read role) on the Application Insights resource
> 3. Authenticate with `Connect-AzAccount` and request the Application Insights audience token with `Get-AzAccessToken`; the shipped extractor has no `-ApiKey` parameter
>
> See [Authentication Migration](prerequisites.md#authentication-migration) for complete migration steps.
>
> Sources: [Entra query authentication](https://learn.microsoft.com/azure/azure-monitor/app/azure-ad-authentication#query-application-insights-by-using-microsoft-entra-authentication),
> [Monitoring Reader](https://learn.microsoft.com/azure/role-based-access-control/built-in-roles/monitor#monitoring-reader),
> and Microsoft's [retirement extension notice](https://www.microsoft.com/releasecommunications/api/v2/Azure/rss/transition-to-azure-ad-to-query-data-from-azure-monitor-application-insights-by-31-march-2026)
> (re-fetched 2026-10-16; announced date, not a tenant shutdown observation).

**Symptoms:**
- REST API returns 401/403 error
- "Authentication failed" error message

**Causes and Solutions:**

| Cause | Solution |
|-------|----------|
| **Legacy API key dependency** | Migrate the runbook to managed identity or certificate-backed Entra ID authentication |
| **Wrong App ID** | Use the Application Insights Application ID in the query URL, not its instrumentation key or the authenticating app registration's client ID |
| **Expired legacy credential** | Replace the secret path with managed identity or certificate-backed Entra ID authentication |
| **Insufficient permissions** | Assign Monitoring Reader on the Application Insights resource to the managed identity or service principal |
| **Resource not found** | Verify App Insights resource exists and ID is correct |

**Diagnostic Steps (Entra ID - Recommended):**

```powershell
# PowerShell 7+ is required for ConvertFrom-SecureString -AsPlainText
# Test API connectivity with managed identity / Entra ID authentication
Connect-AzAccount -Identity  # Azure Automation managed identity
# Or, on non-Azure schedulers:
# Connect-AzAccount -ServicePrincipal -ApplicationId $AppId -TenantId $TenantId -CertificateThumbprint $Thumbprint
$tokenResult = Get-AzAccessToken -ResourceUrl "https://api.applicationinsights.io" -AsSecureString
# Az.Accounts 5.0+ returns Token as SecureString by default; never log the token or headers
$token = if ($tokenResult.Token -is [System.Security.SecureString]) {
    $tokenResult.Token | ConvertFrom-SecureString -AsPlainText
} else {
    $tokenResult.Token
}
$headers = @{ "Authorization" = "Bearer $token" }
$query = [System.Uri]::EscapeDataString("customEvents | take 1")
$uri = "https://api.applicationinsights.io/v1/apps/your-app-id/query?query=$query"
Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
```

### 3. No RAI Telemetry Events

**Symptoms:**
- Application Insights query returns no ContentFiltered events
- RAI telemetry CSV is empty

**Causes and Solutions:**

| Cause | Solution |
|-------|----------|
| **Agent not configured** | Check **Settings > Advanced > Application Insights > Connection string** and relevant logging settings; also check whether an environment data policy blocks the Application Insights in Copilot Studio connector |
| **Channel mismatch** | Test the Copilot Studio test canvas and deployed channel separately; Microsoft documents telemetry during testing, so publishing is not a universal prerequisite |
| **No filtering occurred** | `ContentFiltered` indicates a blocked response; filtering can be triggered by user input or generated output. An empty query alone does not establish that no block occurred |
| **Wrong query** | Start with Microsoft's property-bag search below; inspect actual event names and dimensions before adding exact predicates |
| **Telemetry delay** | Allow for variable ingestion delay and recheck; no fixed Copilot Studio 5-10-minute bound was verified |

**Verification Query:**

```kql
// Diagnostic discovery only: inspect raw events before adopting a production classifier
union isfuzzy=true
    (customEvents | project EventTime = timestamp, EventName = name, Dimensions = todynamic(customDimensions)),
    (AppEvents | project EventTime = TimeGenerated, EventName = Name, Dimensions = todynamic(Properties))
| where EventTime > ago(7d)
| where Dimensions contains "ContentFiltered"
| project EventTime, EventName, Dimensions
```

Microsoft's [RAI troubleshooting query](https://learn.microsoft.com/troubleshoot/power-platform/copilot-studio/generative-answers/agent-response-filtered-by-responsible-ai)
searches custom dimensions for `ContentFiltered`; it does not establish the
shipped extractor's exact `MicrosoftCopilotStudio` / `EventType` predicates or
`BotId`, `BotName`, `FilterReason`, `FilterCategory`, and `FilterSeverity` fields.
Those remain **tenant-validation assumptions**, not a verified Microsoft schema.
Compare a sanitized positive example with `Export-RaiTelemetry.ps1` and
`content-filtered-events.kql` before production use; neither an empty CSV nor
blank dimensions proves absence of filtering. The broad diagnostic may also
match incidental text and is not a drop-in production classifier.
See [agent telemetry and settings](https://learn.microsoft.com/microsoft-copilot-studio/advanced-bot-framework-composer-capture-telemetry)
and the [AppEvents schema](https://learn.microsoft.com/azure/azure-monitor/reference/tables/appevents).

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
| **Network restriction** | Check storage firewall and runner connectivity; Azure Automation is not included in the trusted-services firewall exception |
| **Wrong authentication** | Use `-UseConnectedAccount` for Microsoft Entra ID auth |

**Diagnostic Script:**

```powershell
# After Connect-AzAccount (or Connect-AzAccount -Identity on the Azure runner)
# Test list access to the intended container, not upload permission
$context = New-AzStorageContext -StorageAccountName "youraccount" -UseConnectedAccount
Get-AzStorageContainer -Name "deny-events" -Context $context
```

Listing does not prove write access. Under separate authorization, test a new
uniquely named blob in the target container; do not remove immutability protection
to make a rerun overwrite succeed. See [Entra storage authorization](https://learn.microsoft.com/azure/storage/blobs/authorize-data-operations-powershell),
[immutable storage](https://learn.microsoft.com/azure/storage/blobs/immutable-storage-overview),
and [Automation networking restrictions](https://learn.microsoft.com/azure/automation/automation-runbook-execution).

### 5. Power BI Refresh Fails

**Symptoms:**
- Scheduled refresh shows "Failed"
- "Data source error" or "Credentials expired"

**Causes and Solutions:**

| Cause | Solution |
|-------|----------|
| **Credentials expired** | Review the semantic model's connection and credential settings; gateway-managed credentials are maintained on the gateway connection |
| **Storage key rotated** | Only for account-key authentication: update that connection's key; Entra-authenticated connections do not use it |
| **File not found** | Verify extraction ran and file exists at expected path |
| **Schema change** | Update transformations/model for changed CSV columns, refresh and validate in Power BI Desktop, then republish the semantic model |
| **Gateway offline** | For on-premises sources, check gateway status |

**Resolution Steps:**

1. Open Power BI Service
2. Open the workspace and the **semantic model's Settings**
3. Review refresh history, **Gateway and cloud connections**, and **Data source credentials**
4. Update credentials where the connection is managed (semantic model, cloud connection, or gateway)
5. Retry refresh and inspect its result

See [scheduled refresh](https://learn.microsoft.com/power-bi/connect-data/refresh-scheduled-refresh)
and [schema refresh](https://learn.microsoft.com/power-bi/connect-data/refresh-data).

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
| **Conditional Access** | Workload-identity Conditional Access applies to supported single-tenant service principals and requires Workload Identities Premium; managed identities are excluded, so review their resource assignments and network controls separately |
| **Network timeout** | Check firewall rules for Exchange Online endpoints |

**Managed Identity / Certificate-Based Authentication Setup:**

```powershell
# Preferred in Azure Automation
Connect-ExchangeOnline -ManagedIdentity -Organization "example.onmicrosoft.com"

# Windows-only thumbprint example: the scheduler must have the certificate/private key
Connect-ExchangeOnline `
    -CertificateThumbprint "your-cert-thumbprint" `
    -AppId "your-app-id" `
    -Organization "example.onmicrosoft.com"
```

These commands connect; they do not grant permissions. Complete the documented
`Exchange.ManageAsApp`, consent, and role setup for
[managed identities](https://learn.microsoft.com/powershell/exchange/connect-exo-powershell-managed-identity)
or [certificate app-only authentication](https://learn.microsoft.com/powershell/exchange/app-only-auth-powershell-v2),
then validate access to the audit cmdlet. See the
[managed-identity Conditional Access exclusion](https://learn.microsoft.com/entra/identity/conditional-access/workload-identity).

### 7. Microsoft Graph Audit Search (v1.0)

The Graph audit search endpoint (`POST /security/auditLog/queries`) is generally available on the Microsoft Graph v1.0 endpoint with `AuditLogsQuery.Read.All` (or service-specific `AuditLogsQuery-*.Read.All`) permissions. If you call it through the Graph PowerShell SDK outside this production extractor, the v1.0 `auditLogQuery` cmdlets (for example, `New-MgSecurityAuditLogQuery`) are available in `Microsoft.Graph.Security`; the `Microsoft.Graph.Beta.Security` module has the beta equivalents. Validate query coverage and response shapes for regulated evidence before relying on it.

## Performance Issues

### Slow Audit Log Search

**Symptoms:**
- Search takes >30 minutes
- Timeout errors

**Solutions:**

1. **Narrow date range** - Search smaller windows (1 day instead of 7)
2. **Use pagination** - Repeat calls with the same `SessionId` and `SessionCommand ReturnLargeSet`, using `ResultSize 5000`, until no results remain; split windows that reach the 50,000-result session ceiling
3. **Filter early** - Use `-UserIds` for user UPNs and appropriate record-type/operation filters, rather than free-text user matching
4. **Measure scheduling** - Select a schedule based on observed tenant behavior; Microsoft does not document an early-morning UTC performance advantage

Use explicit UTC boundaries and verify window coverage. See
[`Search-UnifiedAuditLog`](https://learn.microsoft.com/powershell/module/exchangepowershell/search-unifiedauditlog).

### Large Export Files

**Symptoms:**
- CSV files exceed 100MB
- Power BI refresh slow

**Solutions:**

1. **Compress archival copies** - `Compress-Archive` produces ZIP files; retain a refresh-compatible source unless decompression is explicitly implemented
2. **Incremental load** - Configure `RangeStart`/`RangeEnd` and date-based file/row filtering; confirm the query actually prunes source reads rather than downloading all CSVs each refresh
3. **Filter in extraction** - Only export deny events, not all interactions
4. **Archive old data** - Azure Cold is online; Archive blobs must be rehydrated before reading and should be excluded from live refresh

See [incremental-refresh requirements](https://learn.microsoft.com/power-bi/connect-data/incremental-refresh-overview)
and [Blob access tiers](https://learn.microsoft.com/azure/storage/blobs/access-tiers-overview).

## Logging and Diagnostics

### Enable Verbose Logging

```powershell
# Run scripts with -Verbose flag
.\scripts\Export-CopilotDenyEvents.ps1 -Verbose

# Or set preference
$VerbosePreference = "Continue"
```

For published Azure Automation runbooks, also enable verbose logging in the
runbook settings **before** starting the job; the local preference alone does not
retain that stream in job history.

### Check Azure Automation Job Output

1. Open Azure Automation Account
2. Select **Jobs** (or the runbook's job history)
3. Select the failed job
4. Inspect output/error streams or **All logs**, as exposed by the portal

See [runbook output and logging settings](https://learn.microsoft.com/azure/automation/automation-runbook-output-and-messages).

### Application Insights Diagnostics

```kql
// Inspect application traces, not a definitive ingestion-health diagnostic
traces
| where timestamp > ago(1h)
| where severityLevel >= 2  // Warning and above
| project timestamp, message, severityLevel
```

Application Insights [Warning severity is 2](https://learn.microsoft.com/dotnet/api/microsoft.applicationinsights.datacontracts.severitylevel);
3 is Error. No matching traces does not establish ingestion health.

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
