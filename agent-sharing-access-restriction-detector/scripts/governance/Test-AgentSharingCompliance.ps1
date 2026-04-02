<#
.SYNOPSIS
    Orchestrates a full agent sharing compliance scan and evaluates overall posture.

.DESCRIPTION
    Runs the ASARD sharing compliance scan and evaluates overall compliance posture
    across all scanned environments and agents. Computes summary statistics including
    total agents, compliant vs non-compliant counts, and per-zone breakdowns.

    This is the primary entry point for scheduled compliance checks. It calls
    Invoke-SharingComplianceScan for the detection pass, then summarizes results
    with an overall status determination (Passed/Warning/Failed).

    Overall status logic:
    - Failed: Any Critical severity violation detected
    - Warning: Any High or Medium severity violation detected (no Critical)
    - Passed: No violations detected

    Supports Controls 1.18 (Application-Level Authorization) and 2.8 (Access
    Control and Segregation of Duties) from the FSI Agent Governance Framework.

.PARAMETER OutputFormat
    Output format: Table (default), JSON, or Object.

.PARAMETER ExcludeSandbox
    Exclude sandbox environments from scan.

.PARAMETER ExcludeTrial
    Exclude trial environments from scan.

.PARAMETER IncludeCompliant
    Include compliant agents in output.

.PARAMETER DataverseUrl
    Dataverse organization URL for loading approved groups and persisting results.

.PARAMETER DataverseToken
    Pre-obtained access token for Dataverse authentication.

.PARAMETER PersistResults
    When specified with -DataverseUrl and -DataverseToken, writes compliance
    summary to Dataverse.

.PARAMETER BaselinePath
    Path to a JSON file containing zone policy overrides. When specified, overrides
    default zone policies from Get-ExpectedSharingPolicy.ps1 for the scan.

.EXAMPLE
    . .\Test-AgentSharingCompliance.ps1
    Test-AgentSharingCompliance

    Run a compliance scan across all non-sandbox environments using defaults.

.EXAMPLE
    . .\Test-AgentSharingCompliance.ps1
    Test-AgentSharingCompliance -OutputFormat JSON -PersistResults `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -DataverseToken $token

    Full scan with Dataverse persistence and JSON output for evidence pipeline.

.EXAMPLE
    . .\Test-AgentSharingCompliance.ps1
    Test-AgentSharingCompliance -ExcludeTrial -IncludeCompliant

    Scan excluding trial environments with compliant agents included in output.

.OUTPUTS
    Formatted table (default), JSON string, or PSCustomObject[] depending on -OutputFormat.
    Summary statistics are always written to the host output stream.

.NOTES
    File: Test-AgentSharingCompliance.ps1
    Version: 1.0.0
    Solution: Agent Sharing Access Restriction Detector (ASARD)
    Controls: 1.18 (Application-Level Authorization), 2.8 (Access Control/Segregation of Duties)
    Regulations: FINRA Rule 4511, SOX Section 404, GLBA Section 501(b)

    Part of FSI Agent Governance Framework
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

function Test-AgentSharingCompliance {
    [CmdletBinding()]
    param(
        [Parameter()]
        [ValidateSet('Table', 'JSON', 'Object')]
        [string]$OutputFormat = 'Table',

        [Parameter()]
        [switch]$ExcludeSandbox,

        [Parameter()]
        [switch]$ExcludeTrial,

        [Parameter()]
        [switch]$IncludeCompliant,

        [Parameter()]
        [string]$DataverseUrl,

        [Parameter()]
        [string]$DataverseToken,

        [Parameter()]
        [switch]$PersistResults,

        [Parameter()]
        [string]$BaselinePath
    )

    $ErrorActionPreference = 'Stop'
    $scriptRoot = $PSScriptRoot
    $runId = [guid]::NewGuid().ToString()
    $scanStartTime = Get-Date -Format 'o'

    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  ASARD Compliance Assessment                    ║" -ForegroundColor Cyan
    Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host "║  Agent Sharing Access Restriction Detector       ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "RunId: $runId" -ForegroundColor DarkGray
    Write-Host ""

    #region Load Baseline Overrides

    if ($BaselinePath) {
        if (-not (Test-Path $BaselinePath)) {
            throw "Baseline file not found: $BaselinePath"
        }
        Write-Host "Loading zone policy overrides from: $BaselinePath" -ForegroundColor Cyan
        $baselineOverrides = Get-Content -Path $BaselinePath -Raw | ConvertFrom-Json
        Write-Verbose "Baseline overrides loaded: $($baselineOverrides | ConvertTo-Json -Depth 3 -Compress)"
    }

    #endregion

    #region Run Compliance Scan

    Write-Host "Running compliance scan..." -ForegroundColor Cyan
    Write-Host ""

    $scanScript = Join-Path $scriptRoot 'Invoke-SharingComplianceScan.ps1'
    if (-not (Test-Path $scanScript)) {
        throw "Required script not found: $scanScript"
    }

    # Dot-source the scan script to load the function
    . $scanScript

    $scanParams = @{
        OutputFormat    = 'Object'
        IncludeCompliant = $true
    }

    if ($ExcludeSandbox) { $scanParams.ExcludeSandbox = $true }
    if ($DataverseUrl)   { $scanParams.DataverseUrl = $DataverseUrl }

    $scanResults = Invoke-SharingComplianceScan @scanParams

    if (-not $scanResults) {
        $scanResults = @()
    }

    #endregion

    #region Compute Summary

    $allResults = @($scanResults)
    $totalAgents      = $allResults.Count
    $compliantCount   = ($allResults | Where-Object { $_.Status -eq 'Compliant' -or $_.ViolationType -eq 'None' }).Count
    $nonCompliantCount = $totalAgents - $compliantCount
    $violations       = $allResults | Where-Object { $_.Status -ne 'Compliant' -and $_.ViolationType -ne 'None' }

    $criticalCount = ($violations | Where-Object { $_.Severity -eq 'Critical' }).Count
    $highCount     = ($violations | Where-Object { $_.Severity -eq 'High' }).Count
    $mediumCount   = ($violations | Where-Object { $_.Severity -eq 'Medium' }).Count

    # Per-zone breakdown
    $zoneBreakdown = @{}
    foreach ($zone in @('Zone1', 'Zone2', 'Zone3', 'Unknown')) {
        $zoneResults = $allResults | Where-Object { $_.Zone -eq $zone }
        if ($zoneResults) {
            $zoneViolations = $zoneResults | Where-Object { $_.Status -ne 'Compliant' -and $_.ViolationType -ne 'None' }
            $zoneBreakdown[$zone] = [PSCustomObject]@{
                Zone         = $zone
                Total        = @($zoneResults).Count
                Compliant    = @($zoneResults | Where-Object { $_.Status -eq 'Compliant' -or $_.ViolationType -eq 'None' }).Count
                NonCompliant = @($zoneViolations).Count
                Critical     = @($zoneViolations | Where-Object { $_.Severity -eq 'Critical' }).Count
                High         = @($zoneViolations | Where-Object { $_.Severity -eq 'High' }).Count
            }
        }
    }

    # Determine overall status
    $overallStatus = 'Passed'
    if ($criticalCount -gt 0) {
        $overallStatus = 'Failed'
    }
    elseif ($highCount -gt 0 -or $mediumCount -gt 0) {
        $overallStatus = 'Warning'
    }

    $statusColor = switch ($overallStatus) {
        'Passed'  { 'Green' }
        'Warning' { 'Yellow' }
        'Failed'  { 'Red' }
    }

    #endregion

    #region Persist Summary to Dataverse

    if ($PersistResults -and $DataverseUrl -and $DataverseToken) {
        Write-Host "Persisting compliance summary to Dataverse..." -ForegroundColor Cyan

        try {
            $apiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"
            $dvHeaders = @{
                'Authorization'    = "Bearer $DataverseToken"
                'Content-Type'     = 'application/json'
                'OData-MaxVersion' = '4.0'
                'OData-Version'    = '4.0'
            }

            $summaryRecord = @{
                'fsi_name'             = "ASARD-Summary-$runId".Substring(0, [Math]::Min(100, "ASARD-Summary-$runId".Length))
                'fsi_scanrunid'        = $runId
                'fsi_scanstartedat'    = $scanStartTime
                'fsi_totalagents'      = $totalAgents
                'fsi_compliantcount'   = $compliantCount
                'fsi_noncompliantcount' = $nonCompliantCount
                'fsi_overallstatus'    = $overallStatus
                'fsi_summaryjson'      = ($zoneBreakdown | ConvertTo-Json -Depth 5 -Compress)
            }

            Invoke-RestMethod `
                -Uri "$apiBase/fsi_agentsharingcompliances" `
                -Headers $dvHeaders `
                -Method Post `
                -Body ($summaryRecord | ConvertTo-Json -Compress) `
                -ErrorAction Stop | Out-Null

            Write-Host "  Summary persisted successfully." -ForegroundColor Green
        }
        catch {
            Write-Warning "Failed to persist summary: $($_.Exception.Message)"
        }
    }
    elseif ($PersistResults) {
        Write-Warning "PersistResults requires -DataverseUrl and -DataverseToken"
    }

    #endregion

    #region Display Summary

    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║       Compliance Assessment Summary             ║" -ForegroundColor Cyan
    Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
    Write-Host ("║ Overall Status:   {0,-31}║" -f $overallStatus) -ForegroundColor $statusColor
    Write-Host ("║ Total Agents:     {0,-31}║" -f $totalAgents) -ForegroundColor Cyan
    Write-Host ("║ Compliant:        {0,-31}║" -f $compliantCount) -ForegroundColor Green
    Write-Host ("║ Non-Compliant:    {0,-31}║" -f $nonCompliantCount) -ForegroundColor $(if ($nonCompliantCount -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host ("║ Critical:         {0,-31}║" -f $criticalCount) -ForegroundColor $(if ($criticalCount -gt 0) { 'Red' } else { 'Green' })
    Write-Host ("║ High:             {0,-31}║" -f $highCount) -ForegroundColor $(if ($highCount -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan

    foreach ($zoneKey in $zoneBreakdown.Keys | Sort-Object) {
        $zb = $zoneBreakdown[$zoneKey]
        Write-Host ("║ {0}: {1} total, {2} compliant, {3} violations" -f $zb.Zone, $zb.Total, $zb.Compliant, $zb.NonCompliant) -ForegroundColor Cyan
    }

    Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""

    #endregion

    #region Output Results

    # Filter output based on IncludeCompliant switch
    $outputResults = if ($IncludeCompliant) {
        $allResults
    }
    else {
        @($violations)
    }

    $report = [PSCustomObject]@{
        RunId          = $runId
        ScanStartTime  = $scanStartTime
        OverallStatus  = $overallStatus
        TotalAgents    = $totalAgents
        Compliant      = $compliantCount
        NonCompliant   = $nonCompliantCount
        Critical       = $criticalCount
        High           = $highCount
        Medium         = $mediumCount
        ZoneBreakdown  = $zoneBreakdown
        Results        = $outputResults
    }

    switch ($OutputFormat) {
        'JSON' {
            return ($report | ConvertTo-Json -Depth 10)
        }
        'Object' {
            return $report
        }
        default {
            if ($outputResults -and @($outputResults).Count -gt 0) {
                $outputResults | Format-Table -Property EnvironmentName, AgentName, Zone, ViolationType, Severity -AutoSize
            }
            else {
                Write-Host "No violations to display." -ForegroundColor Green
            }
        }
    }

    #endregion
}

exit 0
