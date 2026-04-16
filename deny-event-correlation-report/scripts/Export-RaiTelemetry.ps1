<#
.SYNOPSIS
    Exports RAI (Responsible AI) telemetry from Azure Application Insights.

.DESCRIPTION
    Queries Application Insights for Copilot Studio ContentFiltered events,
    which indicate when Azure AI Content Safety blocked agent responses.

    Uses Microsoft Entra ID authentication for secure access.

.PARAMETER AppInsightsAppId
    The Application ID of your Application Insights resource.
    Found in Azure Portal > Application Insights > API Access.

.PARAMETER StartDate
    Start of the time window for query. Defaults to yesterday.

.PARAMETER EndDate
    End of the time window for query. Defaults to today.

.PARAMETER OutputPath
    Path for the exported CSV file. Defaults to current directory with date stamp.

.EXAMPLE
    Connect-AzAccount
    .\Export-RaiTelemetry.ps1 -AppInsightsAppId "abc123"
    Exports yesterday's RAI events using interactive authentication.

.EXAMPLE
    Connect-AzAccount -ServicePrincipal -TenantId $tenantId -Credential $cred
    .\Export-RaiTelemetry.ps1 -AppInsightsAppId "abc123"
    Exports using service principal authentication.

.NOTES
    Author: FSI Agent Governance Framework
    Version: 1.3
    Requires: Az.Accounts module
    Authentication: Microsoft Entra ID - uses Connect-AzAccount

.LINK
    https://github.com/judeper/FSI-AgentGov
#>

<#
================================================================================
  AUTHENTICATION MIGRATION COMPLETE - Microsoft Entra ID
================================================================================

  This script now uses Entra ID authentication via Connect-AzAccount.

  Migration completed: February 4, 2026

  The deprecated x-api-key authentication method has been removed.
  This script will continue working after March 31, 2026.

  Prerequisites:
  - Install Az.Accounts module: Install-Module Az.Accounts -Force
  - Authenticate before running: Connect-AzAccount
  - Grant Monitoring Reader role on Application Insights resource

================================================================================
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AppInsightsAppId,

    [Parameter()]
    [DateTime]$StartDate = (Get-Date).AddDays(-1).Date,

    [Parameter()]
    [DateTime]$EndDate = (Get-Date).Date,

    [Parameter()]
    [string]$OutputPath = ".\RaiTelemetry-$(Get-Date -Format 'yyyy-MM-dd').csv"
)

#Requires -Version 7.0
#Requires -Modules Az.Accounts

$ErrorActionPreference = "Stop"

#region Functions

function Invoke-AppInsightsQuery {
    <#
    .SYNOPSIS
        Executes a KQL query against Application Insights REST API using Entra ID authentication.
    #>
    param(
        [string]$AppId,
        [string]$Query
    )

    # Get access token for Application Insights API
    # Migrated from deprecated x-api-key to Entra ID token-based authentication (February 2026)
    try {
        $token = Get-AzAccessToken -ResourceUrl "https://api.applicationinsights.io"
        if (-not $token) {
            throw "Failed to acquire access token. Ensure you have authenticated with Connect-AzAccount."
        }
    }
    catch {
        throw "Authentication failed: $_. Run Connect-AzAccount before executing this script."
    }

    # Az.Accounts ≥3.0 returns Token as SecureString; convert to plaintext for HTTP header
    $tokenString = if ($token.Token -is [System.Security.SecureString]) {
        $token.Token | ConvertFrom-SecureString -AsPlainText
    } else {
        $token.Token
    }

    $headers = @{
        "Authorization" = "Bearer $tokenString"
        "Content-Type" = "application/json"
    }

    # URL encode the query (using .NET built-in for cross-platform compatibility)
    $encodedQuery = [System.Uri]::EscapeDataString($Query)

    $uri = "https://api.applicationinsights.io/v1/apps/$AppId/query?query=$encodedQuery"

    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
        return $response
    }
    catch {
        if ($_.Exception.Response) {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $statusDesc = $_.Exception.Response.StatusDescription

            switch ($statusCode) {
                401 { throw "Authentication failed. Ensure you have authenticated with Connect-AzAccount and have Monitoring Reader role on the Application Insights resource." }
                403 { throw "Access denied. Ensure your account has Monitoring Reader role on the Application Insights resource." }
                404 { throw "Application Insights resource not found. Check AppInsightsAppId." }
                429 {
                    # Rate limited — retry with bounded backoff
                    $retryAfter = 60
                    if ($_.Exception.Response.Headers -and $_.Exception.Response.Headers["Retry-After"]) {
                        $parsedRetry = 0
                        if ([int]::TryParse($_.Exception.Response.Headers["Retry-After"], [ref]$parsedRetry) -and $parsedRetry -gt 0 -and $parsedRetry -le 300) {
                            $retryAfter = $parsedRetry
                        }
                    }
                    if (-not (Get-Variable -Name '_retryDepth' -Scope Script -ErrorAction SilentlyContinue)) {
                        $script:_retryDepth = 0
                    }
                    $script:_retryDepth++
                    if ($script:_retryDepth -gt 3) {
                        $script:_retryDepth = 0
                        throw "Rate limit retry exhausted after 3 attempts."
                    }
                    Write-Warning "Rate limited by Application Insights API. Retry $($script:_retryDepth)/3 in ${retryAfter}s..."
                    Start-Sleep -Seconds $retryAfter
                    try {
                        $result = Invoke-AppInsightsQuery -AppId $AppId -Query $Query
                        $script:_retryDepth = 0
                        return $result
                    }
                    catch {
                        $script:_retryDepth = 0
                        throw
                    }
                }
                default { throw "API request failed: $statusCode - $statusDesc" }
            }
        }
        throw "API request failed: $_"
    }
}

function ConvertFrom-AppInsightsResponse {
    <#
    .SYNOPSIS
        Converts Application Insights API response to PowerShell objects.
    #>
    param(
        [object]$Response
    )

    if (-not $Response.tables -or $Response.tables.Count -eq 0) {
        return @()
    }

    $table = $Response.tables[0]
    $columns = $table.columns | ForEach-Object { $_.name }
    $rows = $table.rows

    $results = foreach ($row in $rows) {
        $obj = @{}
        for ($i = 0; $i -lt $columns.Count; $i++) {
            $obj[$columns[$i]] = $row[$i]
        }
        [PSCustomObject]$obj
    }

    return $results
}

#endregion Functions

#region Main Execution

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " RAI Telemetry Extraction" -ForegroundColor Cyan
    Write-Host " FSI Agent Governance Framework" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    # Check for Az.Accounts module
    if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
        throw "Az.Accounts module is not installed. Run: Install-Module Az.Accounts -Force"
    }

    # Verify authentication
    try {
        $context = Get-AzContext
        if (-not $context) {
            throw "Not authenticated. Please run Connect-AzAccount before executing this script."
        }
        Write-Host "Authenticated as: $($context.Account.Id)" -ForegroundColor Green
        Write-Host "Subscription: $($context.Subscription.Name)`n" -ForegroundColor Gray
    }
    catch {
        throw "Authentication check failed: $_. Please run Connect-AzAccount."
    }

    # Validate parameters
    if ($StartDate -ge $EndDate) {
        throw "StartDate must be before EndDate."
    }

    # Convert to UTC before formatting to ensure the 'Z' suffix is accurate
    $startIso = $StartDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $endIso = $EndDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    $kqlQuery = @"
customEvents
| where timestamp between(datetime('$startIso') .. datetime('$endIso'))
| where name == "MicrosoftCopilotStudio"
| extend eventType = tostring(customDimensions["EventType"])
| where eventType == "ContentFiltered"
| extend
    agentId = tostring(customDimensions["BotId"]),
    agentName = tostring(customDimensions["BotName"]),
    sessionId = tostring(customDimensions["ConversationId"]),
    turnId = tostring(customDimensions["TurnId"]),
    filterReason = tostring(customDimensions["FilterReason"]),
    filterCategory = tostring(customDimensions["FilterCategory"]),
    filterSeverity = tostring(customDimensions["FilterSeverity"]),
    userId = tostring(customDimensions["UserId"])
| project
    timestamp,
    agentId,
    agentName,
    sessionId,
    turnId,
    filterReason,
    filterCategory,
    filterSeverity,
    userId,
    customDimensions
| order by timestamp desc
"@

    Write-Host "Querying Application Insights..." -ForegroundColor Cyan
    Write-Host "  App ID: $AppInsightsAppId" -ForegroundColor Gray
    Write-Host "  Time Range: $startIso to $endIso" -ForegroundColor Gray

    # Execute query using Entra ID authentication
    $response = Invoke-AppInsightsQuery -AppId $AppInsightsAppId -Query $kqlQuery

    # Check for truncation — App Insights API silently caps results at ~10K rows
    if ($response.tables -and $response.tables[0].rows.Count -ge 10000) {
        Write-Warning "App Insights query returned 10,000 rows — results may be truncated. Consider narrowing the date range."
    }

    # Convert response
    $raiEvents = ConvertFrom-AppInsightsResponse -Response $response

    if (-not $raiEvents -or @($raiEvents).Count -eq 0) {
        Write-Host "No RAI ContentFiltered events found for the specified date range." -ForegroundColor Yellow
        Write-Host "Note: Ensure Copilot Studio agents are configured with Application Insights." -ForegroundColor Gray
        exit 0
    }

    $eventCount = @($raiEvents).Count
    Write-Host "RAI events found: $eventCount" -ForegroundColor Green

    # Enhance with additional fields for export
    $exportEvents = $raiEvents | ForEach-Object {
        [PSCustomObject]@{
            Timestamp       = $_.timestamp
            AgentId         = $_.agentId
            AgentName       = $_.agentName
            SessionId       = $_.sessionId
            TurnId          = $_.turnId
            FilterReason    = $_.filterReason
            FilterCategory  = $_.filterCategory
            FilterSeverity  = $_.filterSeverity
            UserId          = $_.userId
            IsHighSeverity  = $_.filterSeverity -eq "High"
            CustomDimensions = $_.customDimensions | ConvertTo-Json -Compress
        }
    }

    # Summary statistics
    Write-Host "`n--- Summary ---" -ForegroundColor Cyan
    $summary = @{
        "Total Events"      = $eventCount
        "High Severity"     = @($exportEvents | Where-Object { $_.IsHighSeverity }).Count
        "Unique Agents"     = @($exportEvents | Where-Object { $_.AgentId } | Select-Object -ExpandProperty AgentId -Unique).Count
        "Unique Sessions"   = @($exportEvents | Where-Object { $_.SessionId } | Select-Object -ExpandProperty SessionId -Unique).Count
    }

    # Category breakdown
    $categories = $exportEvents | Group-Object -Property FilterCategory | Sort-Object Count -Descending
    foreach ($cat in $categories) {
        $summary["Category: $($cat.Name)"] = $cat.Count
    }

    foreach ($key in $summary.Keys) {
        Write-Host "  $key`: $($summary[$key])" -ForegroundColor Gray
    }

    # Ensure output directory exists
    $outputDir = Split-Path -Path $OutputPath -Parent
    if ($outputDir -and -not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }

    # Export to CSV
    Write-Host "`nExporting to: $OutputPath" -ForegroundColor Cyan
    $exportEvents | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

    Write-Host "`nExport complete!" -ForegroundColor Green
}
catch {
    Write-Error "Script execution failed: $_"
    exit 1
}

#endregion Main Execution
