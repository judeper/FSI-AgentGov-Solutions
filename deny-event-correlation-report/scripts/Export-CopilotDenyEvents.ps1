<#
.SYNOPSIS
    Exports CopilotInteraction deny events from Microsoft Purview Unified Audit Log.

.DESCRIPTION
    Extracts CopilotInteraction audit events where access was denied, including:
    - Resource access failures (Status = "failure")
    - DLP/sensitivity policy blocks (PolicyDetails present)
    - Cross-prompt injection attempts (XPIADetected = true)
    - Jailbreak attempts (JailbreakDetected = true)

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
    Requires: ExchangeOnlineManagement module, Purview Audit Reader role

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
    [int]$MaxResults = 50000
)

#region Functions

function Connect-ToExchangeOnline {
    <#
    .SYNOPSIS
        Connects to Exchange Online if not already connected.
    #>
    if (-not (Get-Command Search-UnifiedAuditLog -ErrorAction SilentlyContinue)) {
        Write-Verbose "Connecting to Exchange Online..."
        try {
            Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
            Write-Verbose "Connected to Exchange Online."
        }
        catch {
            throw "Failed to connect to Exchange Online: $_"
        }
    }
    else {
        Write-Verbose "Already connected to Exchange Online."
    }
}

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

        $results = Search-UnifiedAuditLog @params

        if ($results) {
            $allEvents.AddRange($results)
            $retrievedCount = $allEvents.Count
            Write-Host "  Retrieved $retrievedCount events..." -ForegroundColor Gray

            if ($retrievedCount -ge $MaxRecords) {
                Write-Warning "Reached maximum result limit ($MaxRecords). Some events may be excluded."
                break
            }
        }
    } while ($results.Count -eq 5000)

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

                if ($resource.XPIADetected -eq $true) {
                    $isDeny = $true
                    $denyReasons.Add("XPIA")
                }
            }

            # Check Messages for jailbreak detection
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
                    RawAuditData    = $AuditRecord.AuditData
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

    # Connect to Exchange Online
    Connect-ToExchangeOnline

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
