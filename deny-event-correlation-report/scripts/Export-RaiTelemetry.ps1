<#
.SYNOPSIS
    Exports RAI (Responsible AI) telemetry from Azure Application Insights.

.DESCRIPTION
    Queries Application Insights for Copilot Studio ContentFiltered events,
    which indicate when Azure AI Content Safety blocked agent responses.

.PARAMETER AppInsightsAppId
    The Application ID of your Application Insights resource.
    Found in Azure Portal > Application Insights > API Access.

.PARAMETER ApiKey
    The API key with read access to Application Insights.
    Create in Azure Portal > Application Insights > API Access > Create API key.

.PARAMETER StartDate
    Start of the time window for query. Defaults to yesterday.

.PARAMETER EndDate
    End of the time window for query. Defaults to today.

.PARAMETER OutputPath
    Path for the exported CSV file. Defaults to current directory with date stamp.

.EXAMPLE
    .\Export-RaiTelemetry.ps1 -AppInsightsAppId "abc123" -ApiKey "key123"
    Exports yesterday's RAI events to the current directory.

.EXAMPLE
    $key = Get-AzKeyVaultSecret -VaultName "myVault" -Name "AppInsightsKey" -AsPlainText
    .\Export-RaiTelemetry.ps1 -AppInsightsAppId "abc123" -ApiKey $key
    Exports using a key from Azure Key Vault.

.NOTES
    Author: FSI Agent Governance Framework
    Version: 1.0
    Requires: Application Insights API access, Az.KeyVault module (optional)

.LINK
    https://github.com/judeper/FSI-AgentGov
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$AppInsightsAppId,

    [Parameter(Mandatory)]
    [string]$ApiKey,

    [Parameter()]
    [DateTime]$StartDate = (Get-Date).AddDays(-1).Date,

    [Parameter()]
    [DateTime]$EndDate = (Get-Date).Date,

    [Parameter()]
    [string]$OutputPath = ".\RaiTelemetry-$(Get-Date -Format 'yyyy-MM-dd').csv"
)

#region Functions

function Invoke-AppInsightsQuery {
    <#
    .SYNOPSIS
        Executes a KQL query against Application Insights REST API.
    #>
    param(
        [string]$AppId,
        [string]$Key,
        [string]$Query
    )

    $headers = @{
        "x-api-key" = $Key
        "Content-Type" = "application/json"
    }

    # URL encode the query
    Add-Type -AssemblyName System.Web
    $encodedQuery = [System.Web.HttpUtility]::UrlEncode($Query)

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
                401 { throw "Authentication failed. Check your API key." }
                403 { throw "Access denied. Ensure API key has read permissions." }
                404 { throw "Application Insights resource not found. Check AppInsightsAppId." }
                429 { throw "Rate limited. Wait and retry." }
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

    # Validate parameters
    if ($StartDate -ge $EndDate) {
        throw "StartDate must be before EndDate."
    }

    # Build KQL query
    $startIso = $StartDate.ToString("yyyy-MM-ddTHH:mm:ssZ")
    $endIso = $EndDate.ToString("yyyy-MM-ddTHH:mm:ssZ")

    $kqlQuery = @"
customEvents
| where timestamp between(datetime('$startIso') .. datetime('$endIso'))
| where name == "MicrosoftCopilotStudio"
| extend eventType = tostring(customDimensions["EventType"])
| where eventType == "ContentFiltered"
| extend
    agentId = tostring(customDimensions["BotId"]),
    sessionId = tostring(customDimensions["ConversationId"]),
    turnId = tostring(customDimensions["TurnId"]),
    filterReason = tostring(customDimensions["FilterReason"]),
    filterCategory = tostring(customDimensions["FilterCategory"]),
    filterSeverity = tostring(customDimensions["FilterSeverity"]),
    userId = tostring(customDimensions["UserId"])
| project
    timestamp,
    agentId,
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

    # Execute query
    $response = Invoke-AppInsightsQuery -AppId $AppInsightsAppId -Key $ApiKey -Query $kqlQuery

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
