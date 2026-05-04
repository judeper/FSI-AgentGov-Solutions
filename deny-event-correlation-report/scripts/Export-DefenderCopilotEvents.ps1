<#
.SYNOPSIS
    Exports Defender CloudAppEvents for Copilot prompt injection and jailbreak detections.

.DESCRIPTION
    Queries Microsoft Defender XDR Advanced Hunting CloudAppEvents for Copilot-related
    threat detections including:
    - XPIA (Cross-domain Prompt Injection Attack) events
    - UPIA (User Prompt Injection Attack) events
    - Jailbreak attempt detections

    These detections are NOT available in the CopilotInteraction audit schema (Purview);
    they are logged to Defender CloudAppEvents when Defender for Cloud Apps is connected
    to Microsoft Defender XDR. The Defender for Cloud Apps alert REST API is a separate
    optional source for alert lifecycle metadata and is not used by this extractor.

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

$ErrorActionPreference = "Stop"

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

    # Build KQL query for Advanced Hunting.
    # NOTE: The published Defender XDR `CloudAppEvents` schema for Microsoft 365
    # Copilot exposes:
    #   - ActionType: `CopilotInteraction` (Copilot prompt/response activity)
    # The `CopilotMessageCreated` ActionType referenced in earlier docs is not
    # part of the public schema. Threat enrichment is exposed via
    # `RawEventData.ThreatCategory` (string values include `PromptInjection`,
    # `Jailbreak`, `XPIA`). The legacy boolean fields `XPIADetected`/
    # `JailbreakDetected` are not in the public schema and are NOT used here.
    $startIso = $StartDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    $endIso = $EndDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

    $kqlQuery = @"
CloudAppEvents
| where Timestamp between (datetime('$startIso') .. datetime('$endIso'))
| where ActionType == "CopilotInteraction"
| extend Parsed = parse_json(RawEventData)
| extend ThreatCategory = tostring(Parsed.ThreatCategory)
| where ThreatCategory in ("PromptInjection", "Jailbreak", "XPIA")
| extend
    AgentId = tostring(Parsed.AgentId),
    AgentName = tostring(Parsed.AgentName),
    AppHost = tostring(Parsed.AppHost)
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

    # Execute Advanced Hunting query with retry logic.
    # Invoke-MgGraphRequest surfaces errors as Microsoft.Graph.PowerShell.AuthenticationException
    # or HttpRequestException; the response body (if any) is on $_.ErrorDetails.Message
    # as a JSON string. Status code is parsed from $_.Exception.Response.StatusCode
    # when available, falling back to ErrorDetails JSON inspection.
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
            $errorCode = $null
            if ($_.Exception.Response -and $_.Exception.Response.StatusCode) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }
            if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                try {
                    $errBody = $_.ErrorDetails.Message | ConvertFrom-Json -ErrorAction Stop
                    if ($errBody.error.code) { $errorCode = $errBody.error.code }
                } catch { }
            }

            $isRetryable = ($statusCode -eq 429) -or
                ($statusCode -ge 500 -and $statusCode -le 599) -or
                ($errorCode -in @('TooManyRequests', 'ServiceUnavailable', 'InternalServerError'))

            if ($isRetryable) {
                $attempt++
                if ($attempt -ge $maxRetries) {
                    throw "Graph API error (HTTP $statusCode / code $errorCode) after $maxRetries retries: $_"
                }
                $retryAfter = 30 * $attempt
                if ($_.Exception.Response -and $_.Exception.Response.Headers) {
                    try {
                        $retryValues = $_.Exception.Response.Headers.GetValues('Retry-After')
                        $parsedRetryAfter = 0
                        if ($retryValues -and [int]::TryParse([string]$retryValues[0], [ref]$parsedRetryAfter) -and $parsedRetryAfter -gt 0 -and $parsedRetryAfter -le 300) {
                            $retryAfter = $parsedRetryAfter
                        }
                    } catch { }
                }
                Write-Warning "Graph API error (HTTP $statusCode / code $errorCode). Retrying in $retryAfter seconds (attempt $attempt of $maxRetries)..."
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
