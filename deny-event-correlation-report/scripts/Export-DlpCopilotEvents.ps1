<#
.SYNOPSIS
    Exports DLP events for the Microsoft 365 Copilot policy location.

.DESCRIPTION
    Extracts DlpRuleMatch audit events where the workload is Copilot-related,
    or where DLP policies targeting the Copilot location were triggered.

.PARAMETER StartDate
    Start of the time window for audit log search. Defaults to yesterday.

.PARAMETER EndDate
    End of the time window for audit log search. Defaults to today.

.PARAMETER OutputPath
    Path for the exported CSV file. Defaults to current directory with date stamp.

.PARAMETER MaxResults
    Maximum number of events to retrieve. Defaults to 50000 (API limit).

.PARAMETER PolicyNameFilter
    Optional filter to match specific policy names (supports wildcards).

.EXAMPLE
    .\Export-DlpCopilotEvents.ps1
    Exports yesterday's DLP events for Copilot to the current directory.

.EXAMPLE
    .\Export-DlpCopilotEvents.ps1 -PolicyNameFilter "*NPI*"
    Exports DLP events for policies containing "NPI" in the name.

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
    [string]$OutputPath = ".\DlpCopilotEvents-$(Get-Date -Format 'yyyy-MM-dd').csv",

    [Parameter()]
    [int]$MaxResults = 50000,

    [Parameter()]
    [string]$PolicyNameFilter = "*"
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

function Get-DlpAuditEvents {
    <#
    .SYNOPSIS
        Retrieves DlpRuleMatch events from the Unified Audit Log.
    #>
    param(
        [DateTime]$Start,
        [DateTime]$End,
        [int]$MaxRecords
    )

    $allEvents = [System.Collections.Generic.List[object]]::new()
    $sessionId = [Guid]::NewGuid().ToString()
    $retrievedCount = 0

    Write-Host "Searching for DlpRuleMatch events from $Start to $End..." -ForegroundColor Cyan

    do {
        $params = @{
            RecordType     = "DlpRuleMatch"
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

    Write-Host "Total DLP events retrieved: $retrievedCount" -ForegroundColor Green
    return $allEvents
}

function ConvertTo-CopilotDlpEvent {
    <#
    .SYNOPSIS
        Converts a DLP audit record to a Copilot-related DLP event object.
    #>
    param(
        [Parameter(ValueFromPipeline)]
        [object]$AuditRecord,

        [string]$PolicyFilter
    )

    process {
        try {
            $auditData = $AuditRecord.AuditData | ConvertFrom-Json

            # Check if this is a Copilot-related DLP event
            $isCopilotRelated = (
                $auditData.Workload -eq "MicrosoftCopilot" -or
                $auditData.Workload -match "Copilot" -or
                ($auditData.PolicyDetails | Where-Object { $_.PolicyName -match "Copilot" }) -or
                ($auditData.PolicyDetails | Where-Object { $_.PolicyName -like $PolicyFilter -and $PolicyFilter -ne "*" })
            )

            if (-not $isCopilotRelated -and $PolicyFilter -eq "*") {
                # If no filter specified and not obviously Copilot-related, skip
                # Unless Workload contains Copilot indicators
                return
            }

            if ($isCopilotRelated -or $PolicyFilter -ne "*") {
                # Extract policy details
                $policyNames = ($auditData.PolicyDetails | ForEach-Object { $_.PolicyName }) -join "; "
                $ruleNames = ($auditData.PolicyDetails.Rules | ForEach-Object { $_.RuleName }) -join "; "
                $actions = ($auditData.PolicyDetails.Rules | ForEach-Object { $_.Actions } | Select-Object -Unique) -join "; "
                $severities = ($auditData.PolicyDetails.Rules | ForEach-Object { $_.Severity } | Select-Object -Unique) -join "; "

                # Extract sensitive information types
                $sitMatches = ($auditData.SensitiveInfoTypeData | ForEach-Object {
                    "$($_.SensitiveInfoTypeName) (Count: $($_.Count), Confidence: $($_.Confidence)%)"
                }) -join "; "

                $sitNames = ($auditData.SensitiveInfoTypeData | ForEach-Object { $_.SensitiveInfoTypeName }) -join "; "

                # Determine if user overrode
                $hasOverride = $null -ne $auditData.ExceptionInfo -and $auditData.ExceptionInfo -ne ""

                # Determine highest severity
                $severityOrder = @{ "Low" = 1; "Medium" = 2; "High" = 3 }
                $highestSeverity = ($auditData.PolicyDetails.Rules |
                    ForEach-Object { $_.Severity } |
                    Sort-Object { $severityOrder[$_] } -Descending |
                    Select-Object -First 1)

                [PSCustomObject]@{
                    Timestamp           = $AuditRecord.CreationDate
                    UserId              = $auditData.UserId
                    Workload            = $auditData.Workload
                    Operation           = $auditData.Operation
                    PolicyNames         = $policyNames
                    RuleNames           = $ruleNames
                    Actions             = $actions
                    Severity            = $highestSeverity
                    SensitiveInfoTypes  = $sitNames
                    SitMatchDetails     = $sitMatches
                    HasOverride         = $hasOverride
                    OverrideJustification = if ($hasOverride) { $auditData.ExceptionInfo } else { "" }
                    RecordType          = $auditData.RecordType
                    RawAuditData        = $AuditRecord.AuditData
                }
            }
        }
        catch {
            Write-Warning "Failed to parse DLP audit record: $_"
        }
    }
}

#endregion Functions

#region Main Execution

try {
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host " DLP Copilot Event Extraction" -ForegroundColor Cyan
    Write-Host " FSI Agent Governance Framework" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan

    # Validate parameters
    if ($StartDate -ge $EndDate) {
        throw "StartDate must be before EndDate."
    }

    # Connect to Exchange Online
    Connect-ToExchangeOnline

    # Retrieve DLP audit events
    $dlpEvents = Get-DlpAuditEvents -Start $StartDate -End $EndDate -MaxRecords $MaxResults

    if (-not $dlpEvents -or $dlpEvents.Count -eq 0) {
        Write-Host "No DlpRuleMatch events found for the specified date range." -ForegroundColor Yellow
        exit 0
    }

    # Filter for Copilot-related events
    Write-Host "Filtering for Copilot-related DLP events..." -ForegroundColor Cyan
    $copilotDlpEvents = $dlpEvents | ConvertTo-CopilotDlpEvent -PolicyFilter $PolicyNameFilter | Where-Object { $_ -ne $null }

    if (-not $copilotDlpEvents -or @($copilotDlpEvents).Count -eq 0) {
        Write-Host "No Copilot-related DLP events found." -ForegroundColor Yellow
        Write-Host "Note: Events are identified by Workload='MicrosoftCopilot' or policy names containing 'Copilot'." -ForegroundColor Gray
        exit 0
    }

    $eventCount = @($copilotDlpEvents).Count
    Write-Host "Copilot DLP events found: $eventCount" -ForegroundColor Green

    # Summary statistics
    Write-Host "`n--- Summary ---" -ForegroundColor Cyan
    $summary = @{
        "Total Events"     = $eventCount
        "Block Actions"    = @($copilotDlpEvents | Where-Object { $_.Actions -match "Block" }).Count
        "Warn Actions"     = @($copilotDlpEvents | Where-Object { $_.Actions -match "Warn" }).Count
        "Override Used"    = @($copilotDlpEvents | Where-Object { $_.HasOverride }).Count
        "High Severity"    = @($copilotDlpEvents | Where-Object { $_.Severity -eq "High" }).Count
        "Unique Users"     = @($copilotDlpEvents | Select-Object -ExpandProperty UserId -Unique).Count
        "Unique Policies"  = @($copilotDlpEvents | Select-Object -ExpandProperty PolicyNames -Unique).Count
    }

    foreach ($key in $summary.Keys) {
        Write-Host "  $key`: $($summary[$key])" -ForegroundColor Gray
    }

    # Export to CSV
    Write-Host "`nExporting to: $OutputPath" -ForegroundColor Cyan
    $copilotDlpEvents | Export-Csv -Path $OutputPath -NoTypeInformation -Encoding UTF8

    Write-Host "`nExport complete!" -ForegroundColor Green
}
catch {
    Write-Error "Script execution failed: $_"
    exit 1
}

#endregion Main Execution
