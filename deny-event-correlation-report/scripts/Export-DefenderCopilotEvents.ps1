<#
.SYNOPSIS
    Exports Defender CloudAppEvents for Copilot prompt injection and jailbreak detections.

.DESCRIPTION
    Queries Microsoft Defender for Cloud Apps (via Advanced Hunting) for Copilot-related
    threat detections including:
    - XPIA (Cross-domain Prompt Injection Attack) events
    - UPIA (User Prompt Injection Attack) events
    - Jailbreak attempt detections

    These detections are NOT available in the CopilotInteraction audit schema (Purview);
    they are exclusively logged to Defender CloudAppEvents.

.PARAMETER StartDate
    Start of the time window for query. Defaults to yesterday.

.PARAMETER EndDate
    End of the time window for query. Defaults to today.

.PARAMETER OutputPath
    Path for the exported CSV file. Defaults to current directory with date stamp.

.EXAMPLE
    Connect-MgGraph -Scopes "ThreatHunting.Read.All"
    .\Export-DefenderCopilotEvents.ps1
    Exports yesterday's XPIA/Jailbreak detections.

.NOTES
    Author: FSI Agent Governance Framework
    Version: 2.0.0
    Requires: Microsoft.Graph.Security module, Defender for Cloud Apps license
    Authentication: Entra ID via Connect-MgGraph

.LINK
    https://github.com/judeper/FSI-AgentGov
#>

[CmdletBinding()]
param(
    [Parameter()]
    [DateTime]$StartDate = (Get-Date).AddDays(-1).Date,

    [Parameter()]
    [DateTime]$EndDate = (Get-Date).Date,

    [Parameter()]
    [string]$OutputPath = ".\DefenderCopilotEvents-$(Get-Date -Format 'yyyy-MM-dd').csv"
)

#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Security

#region Main Execution

# Track whether Graph was already connected at entry so we don't disconnect a
# session the caller (orchestrator) may still need.
$graphAlreadyConnected = $null -ne (Get-MgContext -ErrorAction SilentlyContinue)

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " Defender CloudAppEvents Extraction" -ForegroundColor Cyan
    Write-Host " FSI Agent Governance Framework" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    # Validate parameters
    if ($StartDate -ge $EndDate) {
        throw "StartDate must be before EndDate."
    }

    # Verify Graph connection
    $context = Get-MgContext
    if (-not $context) {
        throw "Not authenticated. Run Connect-MgGraph -Scopes 'ThreatHunting.Read.All' before executing this script."
    }
    Write-Host "Authenticated as: $($context.Account)" -ForegroundColor Green

    # Build KQL query for Advanced Hunting
    # Note: This query uses broad string matching (RawEventData has "PromptInjection")
    # while the standalone KQL (cloud-app-events.kql) uses precise boolean field checks
    # (parsedFields.XPIADetected == true). See cloud-app-events.kql lines 15-19 for details.
    $startIso = $StartDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss\Z")
    $endIso = $EndDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss\Z")

    $kqlQuery = @"
CloudAppEvents
| where Timestamp between (datetime('$startIso') .. datetime('$endIso'))
| where ActionType in ("CopilotInteraction", "CopilotMessageCreated")
| where RawEventData has "PromptInjection" or RawEventData has "Jailbreak" or RawEventData has "XPIA"
| extend
    ThreatCategory = tostring(parse_json(RawEventData).ThreatCategory),
    AgentId = tostring(parse_json(RawEventData).AgentId),
    AgentName = tostring(parse_json(RawEventData).AgentName),
    AppHost = tostring(parse_json(RawEventData).AppHost)
| project
    Timestamp,
    AccountDisplayName,
    AccountId,
    Application,
    ActionType,
    AgentId,
    AgentName,
    AppHost,
    ThreatCategory
| order by Timestamp desc
"@

    Write-Host "Querying Defender Advanced Hunting..." -ForegroundColor Cyan
    Write-Host "  Time Range: $startIso to $endIso" -ForegroundColor Gray

    # Execute Advanced Hunting query with retry logic
    $body = @{ Query = $kqlQuery } | ConvertTo-Json
    $maxRetries = 3
    $attempt = 0
    $response = $null

    while ($true) {
        try {
            $response = Invoke-MgGraphRequest -Method POST -Uri "https://graph.microsoft.com/v1.0/security/runHuntingQuery" -Body $body -ContentType "application/json"
            break
        }
        catch {
            $statusCode = $null
            # Invoke-MgGraphRequest wraps errors in Microsoft.Graph.PowerShell exceptions
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
            elseif ($_.Exception.Message -match 'HTTP (\d{3})') {
                $statusCode = [int]$Matches[1]
            }

            if ($statusCode -eq 429 -or ($statusCode -ge 500 -and $statusCode -le 599)) {
                $attempt++
                if ($attempt -ge $maxRetries) {
                    throw "Graph API error (HTTP $statusCode) after $maxRetries retries: $_"
                }
                $retryAfter = 30 * $attempt
                if ($statusCode -eq 429 -and $_.Exception.Response.Headers) {
                    $retryHeader = $_.Exception.Response.Headers | Where-Object { $_.Key -eq 'Retry-After' }
                    if ($retryHeader) { $retryAfter = [int]$retryHeader.Value[0] }
                }
                Write-Warning "Graph API error (HTTP $statusCode). Retrying in $retryAfter seconds (attempt $attempt of $maxRetries)..."
                Start-Sleep -Seconds $retryAfter
                continue
            }
            throw
        }
    }

    if (-not $response.results -or @($response.results).Count -eq 0) {
        Write-Host "No XPIA/Jailbreak events found for the specified date range." -ForegroundColor Yellow
        Write-Host "Note: Requires Defender for Cloud Apps with Copilot protection enabled." -ForegroundColor Gray
        exit 0
    }

    $events = $response.results
    $eventCount = @($events).Count
    Write-Host "Defender events found: $eventCount" -ForegroundColor Green

    # Convert to export format
    $exportEvents = $events | ForEach-Object {
        [PSCustomObject]@{
            Timestamp       = $_.Timestamp
            UserId          = if ($_.AccountId) { $_.AccountId } else { $_.AccountDisplayName }
            Application     = $_.Application
            ActionType      = $_.ActionType
            AgentId         = $_.AgentId
            AgentName       = $_.AgentName
            AppHost         = $_.AppHost
            ThreatCategory  = $_.ThreatCategory
            IsXPIA          = $_.ThreatCategory -match "XPIA|PromptInjection"
            IsJailbreak     = $_.ThreatCategory -match "Jailbreak"
        }
    }

    # Summary statistics
    Write-Host "`n--- Summary ---" -ForegroundColor Cyan
    $summary = @{
        "Total Events"        = $eventCount
        "XPIA Detections"     = @($exportEvents | Where-Object { $_.IsXPIA }).Count
        "Jailbreak Attempts"  = @($exportEvents | Where-Object { $_.IsJailbreak }).Count
        "Unique Users"        = @($exportEvents | Select-Object -ExpandProperty UserId -Unique).Count
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
finally {
    # Only disconnect if this script initiated the Graph session, not the caller
    if (-not $graphAlreadyConnected) {
        try {
            Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        }
        catch { }
    }
}

#endregion Main Execution
