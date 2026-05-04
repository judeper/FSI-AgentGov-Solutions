<#
.SYNOPSIS
    Exports CopilotInteraction deny events from Microsoft Purview Unified Audit Log.

.DESCRIPTION
    Extracts CopilotInteraction audit events where access was denied, including:
    - Resource access failures (Status = "failure")
    - DLP/sensitivity policy blocks (PolicyDetails present)

    Note: XPIA (Cross-Prompt Injection) and Jailbreak detections are NOT part
    of the CopilotInteraction audit schema. These fields are logged to Defender
    CloudAppEvents (requires Defender for Cloud Apps license). The extraction
    logic includes placeholder checks for forward compatibility, but they will
    not match on CopilotInteraction records. See architecture.md for details.

.PARAMETER StartDate
    Start of the time window for audit log search. Defaults to yesterday.

.PARAMETER EndDate
    End of the time window for audit log search. Defaults to today.

.PARAMETER OutputPath
    Path for the exported CSV file. Defaults to current directory with date stamp.

.PARAMETER MaxResults
    Maximum number of events to retrieve. Defaults to 50000 (API limit).

.EXAMPLE
    .\Export-CopilotDenyEvents.ps1
    Exports yesterday's deny events to the current directory.

.EXAMPLE
    .\Export-CopilotDenyEvents.ps1 -StartDate "2026-01-20" -EndDate "2026-01-21" -OutputPath "C:\Reports\deny.csv"
    Exports deny events for a specific date range to a specified path.

.NOTES
    Author: FSI Agent Governance Framework
    Version: 1.0
    Requires: ExchangeOnlineManagement module 3.0+, Purview Audit Reader role

    MICROSOFT GRAPH MIGRATION NOTE: `Search-UnifiedAuditLog` remains the
    documented production extractor for this script as of 2026-Q2. Microsoft
    Graph audit log search is available in beta at `/security/auditLog/queries`
    with `AuditLogsQuery.*` permissions; beta Graph APIs are subject to change
    and are not supported for production use. Track v1.0 readiness before
    replacing this extractor.

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
    [string]$OutputPath = ".\CopilotDenyEvents-$(Get-Date -Format 'yyyy-MM-dd').csv",

    [Parameter()]
    [int]$MaxResults = 50000,

    # App-only certificate auth (Azure Automation / unattended)
    [Parameter()]
    [string]$AppId,

    [Parameter()]
    [string]$CertificateThumbprint,

    [Parameter()]
    [string]$Organization,

    [Parameter()]
    [switch]$ManagedIdentity
)

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.0.0' }

$ErrorActionPreference = "Stop"

#region Functions

# Dot-source shared Exchange Online connection helper to avoid duplicate definitions
# when the orchestrator runs multiple scripts in-process.
. "$PSScriptRoot\Connect-ExchangeOnlineHelper.ps1"

function Get-CopilotAuditEvents {
    <#
    .SYNOPSIS
        Retrieves CopilotInteraction events from the Unified Audit Log.
    #>
    param(
        [DateTime]$Start,
        [DateTime]$End,
        [int]$MaxRecords
    )

    $allEvents = [System.Collections.Generic.List[object]]::new()
    $sessionId = [Guid]::NewGuid().ToString()
    $retrievedCount = 0

    Write-Host "Searching for CopilotInteraction events from $Start to $End..." -ForegroundColor Cyan

    do {
        $params = @{
            RecordType     = "CopilotInteraction"
            StartDate      = $Start
            EndDate        = $End
            SessionId      = $sessionId
            SessionCommand = "ReturnLargeSet"
            ResultSize     = 5000
        }

        # Retry loop for Search-UnifiedAuditLog throttling (HTTP 429)
        $results = $null
        $retryCount = 0
        $maxRetries = 3
        $baseDelay = 60
        while ($true) {
            try {
                $results = Search-UnifiedAuditLog @params -ErrorAction Stop
                break
            }
            catch {
                $retryCount++
                if ($retryCount -ge $maxRetries -or $_.Exception.Message -notmatch '429|throttl|Too Many Requests') {
                    throw
                }
                $delay = $baseDelay * [math]::Pow(2, $retryCount - 1)
                Write-Warning "Search-UnifiedAuditLog throttled. Retrying in ${delay}s (attempt $retryCount of $maxRetries)..."
                Start-Sleep -Seconds $delay
            }
        }

        if ($results) {
            $allEvents.AddRange($results)
            $retrievedCount = $allEvents.Count
            Write-Host "  Retrieved $retrievedCount events..." -ForegroundColor Gray

            if ($retrievedCount -ge $MaxRecords) {
                Write-Warning "Reached maximum result limit ($MaxRecords). Some events may be excluded."
                break
            }
        }
    } while ($results -and $results.Count -gt 0)

    Write-Host "Total events retrieved: $retrievedCount" -ForegroundColor Green
    return $allEvents
}

function ConvertTo-DenyEvent {
    <#
    .SYNOPSIS
        Converts an audit record to a deny event object if it contains deny indicators.
    #>
    param(
        [Parameter(ValueFromPipeline)]
        [object]$AuditRecord
    )

    process {
        try {
            $auditData = $AuditRecord.AuditData | ConvertFrom-Json

            $isDeny = $false
            $denyReasons = [System.Collections.Generic.List[string]]::new()
            $policyNames = [System.Collections.Generic.List[string]]::new()
            $resourceIds = [System.Collections.Generic.List[string]]::new()

            # Check AccessedResources for deny indicators
            foreach ($resource in $auditData.AccessedResources) {
                if ($resource.ID) {
                    $resourceIds.Add($resource.ID)
                }

                if ($resource.Status -eq "failure") {
                    $isDeny = $true
                    $denyReasons.Add("ResourceFailure")
                }

                if ($resource.PolicyDetails) {
                    $isDeny = $true
                    $policyName = $resource.PolicyDetails.PolicyName
                    if ($policyName) {
                        $denyReasons.Add("PolicyBlock:$policyName")
                        $policyNames.Add($policyName)
                    }
                    else {
                        $denyReasons.Add("PolicyBlock")
                    }
                }

                # NOTE: XPIADetected is NOT part of the CopilotInteraction schema.
                # XPIA events come from Defender CloudAppEvents. This check is
                # retained for forward compatibility if the schema is extended.
                if ($resource.XPIADetected -eq $true) {
                    $isDeny = $true
                    $denyReasons.Add("XPIA")
                }
            }

            # NOTE: JailbreakDetected is NOT part of the CopilotInteraction schema.
            # Jailbreak events come from Defender CloudAppEvents. This check is
            # retained for forward compatibility if the schema is extended.
            foreach ($message in $auditData.Messages) {
                if ($message.JailbreakDetected -eq $true) {
                    $isDeny = $true
                    $denyReasons.Add("Jailbreak")
                }
            }

            if ($isDeny) {
                [PSCustomObject]@{
                    Timestamp       = $AuditRecord.CreationDate
                    UserId          = $auditData.UserId
                    Operation       = $auditData.Operation
                    AgentId         = $auditData.AgentId
                    AgentName       = $auditData.AgentName
                    AgentVersion    = $auditData.AgentVersion
                    AppHost         = $auditData.AppHost
                    AppIdentity     = $auditData.AppIdentity
                    DenyReason      = ($denyReasons | Select-Object -Unique) -join "; "
                    PolicyNames     = ($policyNames | Select-Object -Unique) -join "; "
                    ResourceCount   = $resourceIds.Count
                    ResourceIds     = $resourceIds -join "; "
                    HasXPIA         = $denyReasons -contains "XPIA"
                    HasJailbreak    = $denyReasons -contains "Jailbreak"
                    HasPolicyBlock  = ($denyReasons | Where-Object { $_ -like "PolicyBlock*" }).Count -gt 0
                }
            }
        }
        catch {
            Write-Warning "Failed to parse audit record: $_"
        }
    }
}

#endregion Functions

#region Main Execution

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " Copilot Deny Event Extraction" -ForegroundColor Cyan
    Write-Host " FSI Agent Governance Framework" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    # Validate parameters
    if ($StartDate -ge $EndDate) {
        throw "StartDate must be before EndDate."
    }

    # Connect to Exchange Online (interactive by default; cert/MI when params supplied)
    if ($ManagedIdentity) {
        if (-not $Organization) { throw "Organization is required for ManagedIdentity auth." }
        Connect-ToExchangeOnline -ManagedIdentity -Organization $Organization
    }
    elseif ($AppId -and $CertificateThumbprint -and $Organization) {
        Connect-ToExchangeOnline -AppId $AppId -CertificateThumbprint $CertificateThumbprint -Organization $Organization
    }
    else {
        Connect-ToExchangeOnline
    }

    # Retrieve audit events
    $auditEvents = Get-CopilotAuditEvents -Start $StartDate -End $EndDate -MaxRecords $MaxResults

    if (-not $auditEvents -or $auditEvents.Count -eq 0) {
        Write-Host "No CopilotInteraction events found for the specified date range." -ForegroundColor Yellow
        exit 0
    }

    # Filter for deny events
    Write-Host "Filtering for deny events..." -ForegroundColor Cyan
    $denyEvents = $auditEvents | ConvertTo-DenyEvent | Where-Object { $_ -ne $null }

    if (-not $denyEvents -or @($denyEvents).Count -eq 0) {
        Write-Host "No deny events found in the retrieved audit records." -ForegroundColor Yellow
        exit 0
    }

    $denyCount = @($denyEvents).Count
    Write-Host "Deny events found: $denyCount" -ForegroundColor Green

    # Summary statistics
    Write-Host "`n--- Summary ---" -ForegroundColor Cyan
    $summary = @{
        "Total Deny Events"  = $denyCount
        "XPIA Detections"    = @($denyEvents | Where-Object { $_.HasXPIA }).Count
        "Jailbreak Attempts" = @($denyEvents | Where-Object { $_.HasJailbreak }).Count
        "Policy Blocks"      = @($denyEvents | Where-Object { $_.HasPolicyBlock }).Count
        "Unique Users"       = @($denyEvents | Select-Object -ExpandProperty UserId -Unique).Count
        "Unique Agents"      = @($denyEvents | Where-Object { $_.AgentId } | Select-Object -ExpandProperty AgentId -Unique).Count
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
    $denyEvents | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

    Write-Host "`nExport complete!" -ForegroundColor Green
}
catch {
    Write-Error "Script execution failed: $_"
    exit 1
}
finally {
    # Optionally disconnect (commented out to allow reuse in orchestration)
    # Disconnect-ExchangeOnline -Confirm:$false
}

#endregion Main Execution
