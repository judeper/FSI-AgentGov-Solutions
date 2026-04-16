#Requires -Version 7.0

<#
.SYNOPSIS
    Retrieves a summary report of all RAG knowledge sources and their validation status.

.DESCRIPTION
    Queries Dataverse for all registered knowledge sources and their latest
    validation results, computing aggregate health metrics for operational
    monitoring and compliance reporting.

    The summary includes:
    - Source counts by status (Active, Stale, Failed, etc.)
    - Source counts by type (SharePoint, Dataverse, Azure Blob, External)
    - Sources never validated
    - Sources with recent hash changes (last 7 days)
    - Stale sources (last validated exceeds freshness threshold)
    - Overall health status (Healthy/Warning/Critical)

    This script supports FSI-AgentGov Controls:
    - 2.16 (RAG Source Integrity) — source health monitoring
    - 1.7 (Audit Logging) — operational status reporting
    - 2.13 (Documentation) — compliance status documentation

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).

.PARAMETER TenantId
    Microsoft Entra ID tenant ID for authentication.

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID for service principal authentication.

.PARAMETER ClientSecret
    Client secret as SecureString. Production deployments should use
    certificate-based auth or managed identities.

.PARAMETER OutputFormat
    Output format: Table (console), JSON (serialized), or Object (PSCustomObject).
    Default: Table.

.PARAMETER IncludeArchived
    Include archived sources (status = 5) in the summary. By default, archived
    sources are excluded.

.PARAMETER Interactive
    Use interactive browser-based authentication instead of service principal.

.EXAMPLE
    .\Get-SourceValidationSummary.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -Interactive

    Displays a formatted console table summarizing all active knowledge sources
    and their validation status using interactive authentication.

.EXAMPLE
    .\Get-SourceValidationSummary.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345..." `
        -ClientSecret (ConvertTo-SecureString "secret" -AsPlainText -Force) `
        -OutputFormat JSON

    Returns summary as JSON for integration with monitoring systems or dashboards.

.EXAMPLE
    $summary = .\Get-SourceValidationSummary.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -Interactive `
        -OutputFormat Object `
        -IncludeArchived

    if ($summary.OverallStatus -eq 'Critical') {
        Send-AlertNotification -Message "RAG source validation critical"
    }

    Returns PSCustomObject for programmatic consumption in automation scripts.

.OUTPUTS
    Depends on OutputFormat:
    - Table: Formatted console output (no pipeline object)
    - JSON: JSON string
    - Object: PSCustomObject with OverallStatus, Sources, Summary, ByStatus,
      BySourceType, NeverValidated, RecentHashChanges, StaleSources properties

.NOTES
    Version: 1.0.0
    Requires:
    - PowerShell 7.0 or later
    - MSAL.PS module for interactive authentication
    - RSV Dataverse schema deployed (fsi_knowledgesources, fsi_validationresults,
      fsi_sourcechanges tables)

    Overall status logic:
    - Critical: Any sources with Validation Failed status, or hash mismatches
      detected in last 7 days
    - Warning: Any stale sources, or sources never validated
    - Healthy: All sources active with current validations
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    # Production deployments should use certificate-based auth or managed identities.
    [Parameter(Mandatory = $false)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'JSON', 'Object')]
    [string]$OutputFormat = 'Table',

    [Parameter(Mandatory = $false)]
    [switch]$IncludeArchived,

    [Parameter(Mandatory = $false)]
    [switch]$Interactive
)

$ErrorActionPreference = "Stop"

#region Initialization

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  RAG Source Validation Summary                   ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  FSI-AgentGov RAG Source Validator                ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Validate Dataverse URL to prevent token exfiltration
if ($DataverseUrl -notmatch '^https://[a-z0-9\-]+\.(crm[0-9]*\.dynamics\.com|crm\.microsoftdynamics\.us|crm\.appsplatform\.us|crm\.dynamics\.cn)/?$') {
    throw "Invalid DataverseUrl '$DataverseUrl'. Expected a Dataverse environment URL (e.g., https://contoso.crm.dynamics.com)."
}
$DataverseUrl = $DataverseUrl.TrimEnd('/')

#endregion

#region Authentication

Write-Host "Authenticating to Dataverse..." -ForegroundColor Cyan

$dataverseScope = "$DataverseUrl/.default"

if ($Interactive) {
    try {
        if (-not (Get-Module -ListAvailable -Name MSAL.PS)) {
            throw "MSAL.PS module is required for interactive authentication. Install with: Install-Module MSAL.PS -Scope CurrentUser"
        }
        Import-Module MSAL.PS -ErrorAction Stop

        $msalParams = @{
            Scopes      = @($dataverseScope)
            Interactive = $true
        }
        if ($TenantId) { $msalParams.TenantId = $TenantId }
        if ($ClientId) { $msalParams.ClientId = $ClientId }

        $authResult = Get-MsalToken @msalParams
        $accessToken = $authResult.AccessToken
    }
    catch {
        Write-Error "Interactive authentication failed: $($_.Exception.Message)"
        throw
    }
}
else {
    # Service principal with client secret
    if (-not $TenantId) {
        throw "TenantId is required for service principal authentication. Use -Interactive for browser-based auth."
    }
    if (-not $ClientId) {
        throw "ClientId is required for service principal authentication. Use -Interactive for browser-based auth."
    }
    if ($null -eq $ClientSecret) {
        throw "ClientSecret is required for service principal authentication. Use -Interactive for browser-based auth."
    }

    $clientSecretPlain = [System.Net.NetworkCredential]::new('', $ClientSecret).Password

    $tokenBody = @{
        client_id     = $ClientId
        client_secret = $clientSecretPlain
        scope         = $dataverseScope
        grant_type    = "client_credentials"
    }
    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    try {
        $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $tokenBody `
            -ContentType "application/x-www-form-urlencoded" -MaximumRetryCount 3 -RetryIntervalSec 5
        $accessToken = $tokenResponse.access_token
    }
    catch {
        Write-Error "Service principal authentication failed: $($_.Exception.Message)"
        throw
    }
}

Write-Host "Authentication successful." -ForegroundColor Green
Write-Host ""

$headers = @{
    "Authorization"    = "Bearer $accessToken"
    "Content-Type"     = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
}

#endregion

#region Helper: Paginated Query

function Invoke-DataverseQuery {
    param([string]$Uri, [hashtable]$Headers)

    $results = [System.Collections.Generic.List[object]]::new()
    $nextLink = $Uri
    while ($nextLink) {
        $response = Invoke-RestMethod -Uri $nextLink -Headers $Headers -Method Get `
            -MaximumRetryCount 3 -RetryIntervalSec 5
        if ($response.value) {
            $results.AddRange([object[]]$response.value)
        }
        $nextLink = $response.'@odata.nextLink'
    }
    return $results
}

#endregion

#region Query Knowledge Sources

Write-Host "Querying knowledge sources..." -ForegroundColor Cyan

$sourceFilter = if ($IncludeArchived) { "" } else { "`$filter=fsi_status ne 5&" }
$sourceSelect = "fsi_knowledgesourceid,fsi_sourcename,fsi_sourcetype,fsi_sourceuri,fsi_agentid,fsi_currenthash,fsi_baselinehash,fsi_status,fsi_lastvalidated,fsi_freshnessthreshold,fsi_lastmodified"
$sourceUri = "$DataverseUrl/api/data/v9.2/fsi_knowledgesources?${sourceFilter}`$select=$sourceSelect"

$knowledgeSources = Invoke-DataverseQuery -Uri $sourceUri -Headers $headers
Write-Host "Retrieved $($knowledgeSources.Count) knowledge sources" -ForegroundColor Green

#endregion

#region Query Latest Validation Per Source

Write-Host "Querying latest validation results..." -ForegroundColor Cyan

# Build a lookup of latest validation per source
$latestValidations = @{}

foreach ($source in $knowledgeSources) {
    $sourceId = $source.fsi_knowledgesourceid
    $valFilter = "_fsi_knowledgesourceid_value eq $sourceId"
    $valSelect = "fsi_validationresultid,fsi_validationtime,fsi_result,fsi_hashchanged,fsi_currenthash,fsi_errordetails"
    $valUri = "$DataverseUrl/api/data/v9.2/fsi_validationresults?`$filter=$valFilter&`$select=$valSelect&`$orderby=fsi_validationtime desc&`$top=1"

    try {
        $valResponse = Invoke-RestMethod -Uri $valUri -Headers $headers -Method Get `
            -MaximumRetryCount 3 -RetryIntervalSec 5
        if ($valResponse.value -and $valResponse.value.Count -gt 0) {
            $latestValidations[$sourceId] = $valResponse.value[0]
        }
    }
    catch {
        Write-Warning "Failed to query validation for source '$($source.fsi_sourcename)': $($_.Exception.Message)"
    }
}

Write-Host "Retrieved latest validations for $($latestValidations.Count) sources" -ForegroundColor Green

#endregion

#region Query Recent Hash Changes

Write-Host "Querying recent hash changes..." -ForegroundColor Cyan

$sevenDaysAgo = (Get-Date).AddDays(-7).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$changeFilter = "fsi_detectedon ge $sevenDaysAgo"
$changeSelect = "fsi_sourcechangeid,_fsi_knowledgesourceid_value,fsi_changetype,fsi_detectedon"
$changeUri = "$DataverseUrl/api/data/v9.2/fsi_sourcechanges?`$filter=$changeFilter&`$select=$changeSelect"

$recentChanges = Invoke-DataverseQuery -Uri $changeUri -Headers $headers

# Group by source for hash change detection (changetype 1 = Content Modified)
$sourcesWithRecentHashChanges = @($recentChanges |
    Where-Object { $_.fsi_changetype -eq 1 } |
    Select-Object -ExpandProperty _fsi_knowledgesourceid_value -Unique)

Write-Host "Found $($sourcesWithRecentHashChanges.Count) sources with hash changes in last 7 days" -ForegroundColor Green
Write-Host ""

#endregion

#region Compute Summary

# Label mappings
$sourceTypeLabels = @{
    1 = "SharePoint Document Library"; 2 = "SharePoint List"; 3 = "SharePoint Page"
    4 = "Dataverse Table"; 5 = "Azure Blob Container"; 6 = "Azure Blob File"
    7 = "External API"; 8 = "Database Query"
}

$statusLabels = @{
    1 = "Active"; 2 = "Pending Validation"; 3 = "Validation Failed"
    4 = "Stale"; 5 = "Archived"
}

$resultLabels = @{
    1 = "Passed"; 2 = "Failed - Hash Mismatch"; 3 = "Failed - Schema Drift"
    4 = "Failed - Stale Content"; 5 = "Failed - Source Unavailable"
    6 = "Failed - Unexpected Error"; 7 = "Skipped - Not Implemented"
    8 = "Skipped - Unsupported Type"
}

$now = (Get-Date).ToUniversalTime()

# By status
$byStatus = @{}
foreach ($source in $knowledgeSources) {
    $label = $statusLabels[[int]$source.fsi_status]
    if (-not $label) { $label = "Unknown ($($source.fsi_status))" }
    if (-not $byStatus.ContainsKey($label)) { $byStatus[$label] = 0 }
    $byStatus[$label]++
}

# By source type
$bySourceType = @{}
foreach ($source in $knowledgeSources) {
    $label = $sourceTypeLabels[[int]$source.fsi_sourcetype]
    if (-not $label) { $label = "Unknown ($($source.fsi_sourcetype))" }
    if (-not $bySourceType.ContainsKey($label)) { $bySourceType[$label] = 0 }
    $bySourceType[$label]++
}

# Never validated
$neverValidated = @($knowledgeSources | Where-Object {
    $null -eq $_.fsi_lastvalidated -or $_.fsi_lastvalidated -eq ''
})

# Stale sources (lastvalidated exceeds freshnessthreshold days)
$staleSources = [System.Collections.Generic.List[object]]::new()
foreach ($source in $knowledgeSources) {
    if ($null -eq $source.fsi_lastvalidated -or $source.fsi_lastvalidated -eq '') { continue }
    $threshold = if ($source.fsi_freshnessthreshold -and $source.fsi_freshnessthreshold -gt 0) {
        $source.fsi_freshnessthreshold
    } else { 7 }  # Default 7 days if not set
    $lastValidated = [datetime]::Parse($source.fsi_lastvalidated).ToUniversalTime()
    $daysSinceValidation = ($now - $lastValidated).TotalDays
    if ($daysSinceValidation -gt $threshold) {
        $staleSources.Add([PSCustomObject]@{
            Name              = $source.fsi_sourcename
            SourceId          = $source.fsi_knowledgesourceid
            LastValidated     = $source.fsi_lastvalidated
            ThresholdDays     = $threshold
            DaysSinceValidation = [math]::Round($daysSinceValidation, 1)
        })
    }
}

# Build per-source detail
$sourceDetails = foreach ($source in $knowledgeSources) {
    $sourceId = $source.fsi_knowledgesourceid
    $latestVal = $latestValidations[$sourceId]
    $lastResult = if ($latestVal) { $resultLabels[[int]$latestVal.fsi_result] } else { "Never Validated" }
    $lastTime = if ($latestVal) { $latestVal.fsi_validationtime } else { $null }
    $hasRecentChange = $sourceId -in $sourcesWithRecentHashChanges

    [PSCustomObject]@{
        Name              = $source.fsi_sourcename
        SourceType        = $sourceTypeLabels[[int]$source.fsi_sourcetype]
        Status            = $statusLabels[[int]$source.fsi_status]
        LastValidated     = $lastTime
        LastResult        = $lastResult
        RecentHashChange  = $hasRecentChange
        SourceId          = $sourceId
    }
}

# Counts for overall status
$failedCount = @($knowledgeSources | Where-Object { $_.fsi_status -eq 3 }).Count
$hashMismatchCount = @($latestValidations.Values | Where-Object { $_.fsi_result -eq 2 }).Count
$staleCount = $staleSources.Count
$neverValidatedCount = $neverValidated.Count

# Overall status
$overallStatus = "Healthy"
if ($failedCount -gt 0 -or $hashMismatchCount -gt 0) {
    $overallStatus = "Critical"
}
elseif ($staleCount -gt 0 -or $neverValidatedCount -gt 0) {
    $overallStatus = "Warning"
}
elseif ($knowledgeSources.Count -eq 0) {
    $overallStatus = "NoData"
}

$summaryTimestamp = $now.ToString("yyyy-MM-ddTHH:mm:ssZ")

#endregion

#region Build Result Object

$resultObj = [PSCustomObject]@{
    OverallStatus       = $overallStatus
    GeneratedAt         = $summaryTimestamp
    TotalSources        = $knowledgeSources.Count
    FailedSources       = $failedCount
    StaleSources        = $staleCount
    NeverValidatedCount = $neverValidatedCount
    RecentHashChanges   = $sourcesWithRecentHashChanges.Count
    ByStatus            = [PSCustomObject]$byStatus
    BySourceType        = [PSCustomObject]$bySourceType
    Sources             = @($sourceDetails)
    NeverValidated      = @($neverValidated | ForEach-Object {
        [PSCustomObject]@{
            Name     = $_.fsi_sourcename
            SourceId = $_.fsi_knowledgesourceid
            Status   = $statusLabels[[int]$_.fsi_status]
        }
    })
    StaleSourceDetails  = @($staleSources)
}

#endregion

#region Output

switch ($OutputFormat) {
    'JSON' {
        return ($resultObj | ConvertTo-Json -Depth 10)
    }
    'Object' {
        return $resultObj
    }
    'Table' {
        # Overall status banner
        $statusColor = switch ($overallStatus) {
            'Healthy'  { 'Green' }
            'Warning'  { 'Yellow' }
            'Critical' { 'Red' }
            default    { 'Gray' }
        }

        Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor $statusColor
        Write-Host ("║  Overall Status: {0,-32}║" -f $overallStatus) -ForegroundColor $statusColor
        Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor $statusColor
        Write-Host ""

        # Summary counts
        Write-Host "Summary" -ForegroundColor Cyan
        Write-Host "  Total Sources:       $($knowledgeSources.Count)"
        Write-Host "  Failed Sources:      $failedCount"
        Write-Host "  Stale Sources:       $staleCount"
        Write-Host "  Never Validated:     $neverValidatedCount"
        Write-Host "  Recent Hash Changes: $($sourcesWithRecentHashChanges.Count) (last 7 days)"
        Write-Host ""

        # By status
        Write-Host "By Status" -ForegroundColor Cyan
        foreach ($key in $byStatus.Keys | Sort-Object) {
            Write-Host "  ${key}: $($byStatus[$key])"
        }
        Write-Host ""

        # By source type
        Write-Host "By Source Type" -ForegroundColor Cyan
        foreach ($key in $bySourceType.Keys | Sort-Object) {
            Write-Host "  ${key}: $($bySourceType[$key])"
        }
        Write-Host ""

        # Source detail table
        Write-Host "Source Details" -ForegroundColor Cyan
        $sourceDetails | Format-Table -Property Name, SourceType, Status, LastValidated, LastResult, RecentHashChange -AutoSize

        # Warnings
        if ($neverValidatedCount -gt 0) {
            Write-Host "Never Validated Sources" -ForegroundColor Yellow
            $neverValidated | ForEach-Object {
                Write-Host "  - $($_.fsi_sourcename) ($($_.fsi_knowledgesourceid))" -ForegroundColor Yellow
            }
            Write-Host ""
        }

        if ($staleSources.Count -gt 0) {
            Write-Host "Stale Sources (exceeding freshness threshold)" -ForegroundColor Yellow
            $staleSources | Format-Table -Property Name, LastValidated, ThresholdDays, DaysSinceValidation -AutoSize
        }

        Write-Host "Generated at: $summaryTimestamp" -ForegroundColor Gray
        Write-Host ""
    }
}

#endregion
