<#
.SYNOPSIS
    Runs 10 Copilot Studio governance benchmark checks and produces a unified report.

.DESCRIPTION
    Orchestrates a loop across 10 CIS-style governance checks for Copilot Studio agents,
    calling existing solution validation scripts and collecting results into a consolidated
    summary table (console) and JSON evidence file.

    Benchmark checks:
     1. Prevent Unauthorized Agent Actions
     2. User-Defined Action Messages
     3. Require Users to Sign In (Manual Auth)
     4. AI Agents Authentication Bypass
     5. Unrestricted Access to AI Agents
     6. AI Agents with File Analysis Enabled
     7. AI Agents Using Model Knowledge
     8. AI Agents using Semantic Search
     9. AI Agents with Insufficient Content Moderation
    10. Inter-agent Communication Restricted

    Each check maps to an existing governance solution script. Failures in one check
    do not prevent execution of the others.

.PARAMETER TenantId
    Microsoft Entra tenant ID for authentication.

.PARAMETER ClientId
    App registration client ID for service principal authentication.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication.

.PARAMETER DataverseUrl
    Dataverse environment URL for zone classification lookup.

.PARAMETER Zone
    Governance zone to validate against: Zone1, Zone2, or Zone3.
    Required for session security validation. Default: Zone3.

.PARAMETER OutputPath
    Path for JSON report output. Default: copilot-benchmark-<timestamp>.json
    in the current directory.

.PARAMETER ConfigPath
    Path to tenant configuration JSON file (required for session security check).

.PARAMETER ExcludeSandbox
    Exclude sandbox environments from all scans.

.PARAMETER ExcludeTrial
    Exclude trial environments from all scans.

.PARAMETER GracePeriodHours
    Hours to exclude newly created environments. Default: 48.

.PARAMETER SkipChecks
    Array of check numbers (1-10) to skip.

.PARAMETER WhatIf
    Preview mode — all sub-scripts run in dry-run/WhatIf mode. Safe to run.

.EXAMPLE
    .\Invoke-CopilotStudioBenchmark.ps1 -WhatIf

    Dry-run of all 10 checks with default settings.

.EXAMPLE
    .\Invoke-CopilotStudioBenchmark.ps1 -Zone Zone3 -DataverseUrl "https://org.crm.dynamics.com" -ExcludeSandbox -WhatIf

    Runs all checks for Zone3, excluding sandbox environments, in preview mode.

.EXAMPLE
    .\Invoke-CopilotStudioBenchmark.ps1 -TenantId $tid -ClientId $cid -CertificateThumbprint $ct -DataverseUrl $url -Zone Zone3

    Full run with service principal authentication.

.EXAMPLE
    .\Invoke-CopilotStudioBenchmark.ps1 -SkipChecks @(3, 5) -WhatIf

    Skip session security and sharing audit checks.

.OUTPUTS
    Console summary table with color-coded pass/fail status.
    JSON file at OutputPath with full results and per-check violation details.

.NOTES
    File: Invoke-CopilotStudioBenchmark.ps1
    Version: 1.0.0
    Part of FSI Agent Governance Framework
    Regulations: FINRA 3110/4511, SEC 17a-3/4, SOX 302/404, GLBA 501(b)
#>

#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [string]$ClientId,

    [Parameter()]
    [string]$CertificateThumbprint,

    [Parameter()]
    [string]$DataverseUrl,

    [Parameter()]
    [ValidateSet('Zone1', 'Zone2', 'Zone3')]
    [string]$Zone = 'Zone3',

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [string]$ConfigPath,

    [Parameter()]
    [switch]$ExcludeSandbox,

    [Parameter()]
    [switch]$ExcludeTrial,

    [Parameter()]
    [ValidateRange(0, 168)]
    [int]$GracePeriodHours = 48,

    [Parameter()]
    [ValidateRange(1, 10)]
    [int[]]$SkipChecks = @()
)

$ErrorActionPreference = 'Continue'

#region Script Root Resolution

$repoRoot = Split-Path $PSScriptRoot -Parent
if (-not (Test-Path (Join-Path $repoRoot 'action-confirmation-auditor'))) {
    $repoRoot = $PSScriptRoot
    if (-not (Test-Path (Join-Path $repoRoot 'action-confirmation-auditor'))) {
        throw "Cannot resolve repository root. Run this script from the scripts/ directory or repo root."
    }
}

#endregion

#region Banner

$banner = @"

====================================================================
  Copilot Studio Governance Benchmark Runner v1.0.0
  FSI Agent Governance Framework
====================================================================

"@

Write-Host $banner -ForegroundColor Cyan

#endregion

#region Check Definitions

$checks = @(
    @{
        Id          = 1
        Name        = 'Prevent Unauthorized Agent Actions'
        Solution    = 'action-confirmation-auditor'
        Script      = 'scripts\Test-ActionConfirmationCompliance.ps1'
        Type        = 'Function'
        Function    = 'Test-ActionConfirmationCompliance'
        Control     = '1.23'
    },
    @{
        Id          = 2
        Name        = 'User-Defined Action Messages'
        Solution    = 'action-confirmation-auditor'
        Script      = 'scripts\governance\Test-UserDefinedActionMessages.ps1'
        Type        = 'Function'
        Function    = 'Test-UserDefinedActionMessages'
        Control     = '1.23'
    },
    @{
        Id          = 3
        Name        = 'Require Users to Sign In (Manual Auth)'
        Solution    = 'session-security-configurator'
        Script      = 'scripts\Test-SessionCompliance.ps1'
        Type        = 'Script'
        Function    = $null
        Control     = '1.23, 1.11'
    },
    @{
        Id          = 4
        Name        = 'AI Agents Authentication Bypass'
        Solution    = 'agent-access-monitor'
        Script      = 'scripts\Test-AgentAccessCompliance.ps1'
        Type        = 'Script'
        Function    = $null
        Control     = '3.8'
    },
    @{
        Id          = 5
        Name        = 'Unrestricted Access to AI Agents'
        Solution    = 'unrestricted-agent-sharing-detector'
        Script      = 'scripts\governance\Invoke-SharingAudit.ps1'
        Type        = 'ScriptFile'
        Function    = $null
        Control     = '1.1, 3.8'
    },
    @{
        Id          = 6
        Name        = 'AI Agents with File Analysis Enabled'
        Solution    = 'file-upload-security'
        Script      = 'scripts\Test-FileUploadCompliance.ps1'
        Type        = 'Script'
        Function    = $null
        Control     = '1.14, 1.8, 1.4'
    },
    @{
        Id          = 7
        Name        = 'AI Agents Using Model Knowledge'
        Solution    = 'generative-ai-config-auditor'
        Script      = 'scripts\Test-GenAIConfigCompliance.ps1'
        Type        = 'Function'
        Function    = 'Test-GenAIConfigCompliance'
        Control     = '2.24'
    },
    @{
        Id          = 8
        Name        = 'AI Agents using Semantic Search'
        Solution    = 'generative-ai-config-auditor'
        Script      = 'scripts\Test-GenAIConfigCompliance.ps1'
        Type        = 'Function'
        Function    = 'Test-GenAIConfigCompliance'
        Control     = '2.24'
    },
    @{
        Id          = 9
        Name        = 'AI Agents with Insufficient Content Moderation'
        Solution    = 'content-moderation-monitor'
        Script      = 'scripts\Test-ContentModerationCompliance.ps1'
        Type        = 'Function'
        Function    = 'Test-ContentModerationCompliance'
        Control     = '1.8, 1.14'
    },
    @{
        Id          = 10
        Name        = 'Inter-agent Communication Restricted'
        Solution    = 'agent-communication-restriction-detector'
        Script      = 'scripts\Test-CommRestrictionCompliance.ps1'
        Type        = 'Function'
        Function    = 'Test-CommRestrictionCompliance'
        Control     = '2.17'
    }
)

#endregion

#region Build Common Parameters

$commonFunctionParams = @{}
if ($DataverseUrl)    { $commonFunctionParams['DataverseUrl'] = $DataverseUrl }
if ($ExcludeSandbox)  { $commonFunctionParams['ExcludeSandbox'] = $true }
if ($ExcludeTrial)    { $commonFunctionParams['ExcludeTrial'] = $true }
if ($PSBoundParameters.ContainsKey('GracePeriodHours')) {
    $commonFunctionParams['GracePeriodHours'] = $GracePeriodHours
}

$commonScriptParams = @{}
if ($DataverseUrl)    { $commonScriptParams['-DataverseUrl'] = $DataverseUrl }
if ($ExcludeSandbox)  { $commonScriptParams['-ExcludeSandbox'] = $true }
if ($ExcludeTrial)    { $commonScriptParams['-ExcludeTrial'] = $true }
if ($PSBoundParameters.ContainsKey('GracePeriodHours')) {
    $commonScriptParams['-GracePeriodHours'] = $GracePeriodHours
}

#endregion

#region Run Benchmark Loop

$runId = [Guid]::NewGuid().ToString()
$startTime = Get-Date
$results = @()

Write-Host "  Run ID:     $runId" -ForegroundColor Gray
Write-Host "  Zone:       $Zone" -ForegroundColor Gray
Write-Host "  Started:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host "  Checks:     $($checks.Count - $SkipChecks.Count) of $($checks.Count)" -ForegroundColor Gray
Write-Host "  WhatIf:     $($WhatIfPreference -or $PSBoundParameters.ContainsKey('WhatIf'))" -ForegroundColor Gray
Write-Host ""

foreach ($check in $checks) {
    $checkId = $check.Id
    $checkName = $check.Name

    # Skip if requested
    if ($SkipChecks -contains $checkId) {
        Write-Host "  [$checkId/10] $checkName — SKIPPED" -ForegroundColor DarkGray
        $results += [PSCustomObject]@{
            CheckId        = $checkId
            CheckName      = $checkName
            Solution       = $check.Solution
            Control        = $check.Control
            Status         = 'Skipped'
            ViolationCount = 0
            AgentsScanned  = 0
            Duration       = '0.0s'
            ErrorMessage   = $null
            Details        = @()
        }
        continue
    }

    $scriptPath = Join-Path $repoRoot $check.Solution $check.Script
    if (-not (Test-Path $scriptPath)) {
        Write-Host "  [$checkId/10] $checkName — " -NoNewline
        Write-Host "MISSING" -ForegroundColor Red
        Write-Host "           Script not found: $scriptPath" -ForegroundColor DarkGray
        $results += [PSCustomObject]@{
            CheckId        = $checkId
            CheckName      = $checkName
            Solution       = $check.Solution
            Control        = $check.Control
            Status         = 'Error'
            ViolationCount = 0
            AgentsScanned  = 0
            Duration       = '0.0s'
            ErrorMessage   = "Script not found: $scriptPath"
            Details        = @()
        }
        continue
    }

    Write-Host "  [$checkId/10] $checkName..." -NoNewline
    $checkStart = Get-Date
    $checkResult = $null
    $violationCount = 0
    $agentsScanned = 0
    $status = 'Pass'
    $errorMsg = $null
    $details = @()

    try {
        switch ($check.Type) {
            'Function' {
                # Dot-source the script to load the function
                . $scriptPath

                $funcParams = @{} + $commonFunctionParams
                $funcParams['OutputFormat'] = 'Object'

                if ($WhatIfPreference -or $PSBoundParameters.ContainsKey('WhatIf')) {
                    $funcParams['WhatIf'] = $true
                }

                $checkResult = & $check.Function @funcParams

                if ($checkResult) {
                    $details = @($checkResult)
                    $agentsScanned = $details.Count
                    $violationCount = @($details | Where-Object {
                        ($_.PSObject.Properties.Name -contains 'IsCompliant' -and -not $_.IsCompliant) -or
                        ($_.PSObject.Properties.Name -contains 'Severity' -and $_.Severity -ne 'None' -and $_.Severity -ne 'Compliant')
                    }).Count
                    if ($violationCount -gt 0) { $status = 'Fail' }
                }
            }

            'Script' {
                # Script-level param scripts — call with &
                $scriptParams = @{}
                if ($DataverseUrl)   { $scriptParams['DataverseUrl'] = $DataverseUrl }
                if ($ExcludeSandbox) { $scriptParams['ExcludeSandbox'] = $true }
                if ($ExcludeTrial)   { $scriptParams['ExcludeTrial'] = $true }
                if ($PSBoundParameters.ContainsKey('GracePeriodHours')) {
                    $scriptParams['GracePeriodHours'] = $GracePeriodHours
                }

                # Special handling for session-security-configurator
                if ($check.Solution -eq 'session-security-configurator') {
                    $scriptParams['Zone'] = $Zone
                    if ($ConfigPath)              { $scriptParams['ConfigPath'] = $ConfigPath }
                    if ($TenantId)                { $scriptParams['TenantId'] = $TenantId }
                    if ($ClientId)                { $scriptParams['ClientId'] = $ClientId }
                    if ($CertificateThumbprint)   { $scriptParams['CertificateThumbprint'] = $CertificateThumbprint }
                    if (-not $ClientId)            { $scriptParams['Interactive'] = $true }

                    # Remove inapplicable params for this script
                    $scriptParams.Remove('ExcludeSandbox')
                    $scriptParams.Remove('ExcludeTrial')
                    $scriptParams.Remove('GracePeriodHours')

                    $checkResult = & $scriptPath @scriptParams
                    if ($checkResult) {
                        $details = @($checkResult)
                        $agentsScanned = 1
                        if ($checkResult.PSObject.Properties.Name -contains 'OverallStatus') {
                            if ($checkResult.OverallStatus -ne 'Passed') {
                                $status = 'Fail'
                                $violationCount = 1
                            }
                        }
                    }
                }
                # Agent access monitor and file upload security
                else {
                    $scriptParams['OutputFormat'] = 'Object'
                    if ($WhatIfPreference -or $PSBoundParameters.ContainsKey('WhatIf')) {
                        if ($check.Solution -eq 'file-upload-security') {
                            $scriptParams['DryRun'] = $true
                            $scriptParams['OutputFormat'] = 'JSON'
                        } else {
                            $scriptParams['WhatIf'] = $true
                        }
                    }

                    $checkResult = & $scriptPath @scriptParams
                    if ($checkResult) {
                        # File upload returns JSON string; parse if needed
                        if ($checkResult -is [string]) {
                            try {
                                $parsed = $checkResult | ConvertFrom-Json
                                if ($parsed.results) { $details = @($parsed.results) }
                                if ($parsed.metadata) {
                                    $agentsScanned = $parsed.metadata.totalAgents
                                    $violationCount = $parsed.metadata.violations
                                }
                            } catch {
                                $details = @($checkResult)
                                $agentsScanned = 1
                            }
                        } else {
                            $details = @($checkResult)
                            if ($checkResult.PSObject.Properties.Name -contains 'OverallStatus') {
                                if ($checkResult.OverallStatus -eq 'VIOLATIONS_FOUND' -or $checkResult.OverallStatus -eq 'Failed') {
                                    $status = 'Fail'
                                }
                            }
                            if ($checkResult.PSObject.Properties.Name -contains 'Summary') {
                                $agentsScanned = if ($checkResult.Summary.TotalEnvironments) { $checkResult.Summary.TotalEnvironments } else { 0 }
                                $violationCount = if ($checkResult.Summary.NonCompliant) { $checkResult.Summary.NonCompliant } else { 0 }
                            }
                        }
                        if ($violationCount -gt 0) { $status = 'Fail' }
                    }
                }
            }

            'ScriptFile' {
                # Invoke-SharingAudit writes to file; use temp path
                $tempOutput = Join-Path ([System.IO.Path]::GetTempPath()) "benchmark-sharing-$runId.json"
                $sharingParams = @{
                    OutputFormat    = 'JSON'
                    OutputPath      = $tempOutput
                    IncludeEvidence = $true
                }
                if ($TenantId) { $sharingParams['HomeTenantId'] = $TenantId }

                & $scriptPath @sharingParams

                if (Test-Path $tempOutput) {
                    try {
                        $sharingData = Get-Content $tempOutput -Raw | ConvertFrom-Json
                        if ($sharingData) {
                            $details = if ($sharingData -is [array]) { $sharingData } else { @($sharingData) }
                            $agentsScanned = $details.Count
                            $violationCount = $details.Count
                            if ($violationCount -gt 0) { $status = 'Fail' }
                        }
                    } catch {
                        $errorMsg = "Failed to parse sharing audit output: $_"
                        $status = 'Error'
                    }
                    Remove-Item $tempOutput -Force -ErrorAction SilentlyContinue
                }
            }
        }
    }
    catch {
        $status = 'Error'
        $errorMsg = $_.Exception.Message
    }

    $checkDuration = ((Get-Date) - $checkStart).TotalSeconds

    # Display inline status
    $statusColor = switch ($status) {
        'Pass'    { 'Green' }
        'Fail'    { 'Red' }
        'Error'   { 'Yellow' }
        'Skipped' { 'DarkGray' }
    }
    Write-Host " $status" -ForegroundColor $statusColor -NoNewline
    Write-Host " ($violationCount violations, $([math]::Round($checkDuration, 1))s)" -ForegroundColor Gray

    if ($errorMsg) {
        Write-Host "           Error: $errorMsg" -ForegroundColor DarkYellow
    }

    $results += [PSCustomObject]@{
        CheckId        = $checkId
        CheckName      = $checkName
        Solution       = $check.Solution
        Control        = $check.Control
        Status         = $status
        ViolationCount = $violationCount
        AgentsScanned  = $agentsScanned
        Duration       = "$([math]::Round($checkDuration, 1))s"
        ErrorMessage   = $errorMsg
        Details        = $details
    }
}

$totalDuration = ((Get-Date) - $startTime).TotalSeconds

#endregion

#region Summary Table

Write-Host ""
Write-Host "  ================================================================" -ForegroundColor Cyan
Write-Host "  BENCHMARK SUMMARY" -ForegroundColor Cyan
Write-Host "  ================================================================" -ForegroundColor Cyan
Write-Host ""

$passCount = @($results | Where-Object { $_.Status -eq 'Pass' }).Count
$failCount = @($results | Where-Object { $_.Status -eq 'Fail' }).Count
$errorCount = @($results | Where-Object { $_.Status -eq 'Error' }).Count
$skipCount = @($results | Where-Object { $_.Status -eq 'Skipped' }).Count

Write-Host "  Pass: $passCount  |  Fail: $failCount  |  Error: $errorCount  |  Skipped: $skipCount" -ForegroundColor White
Write-Host "  Total Duration: $([math]::Round($totalDuration, 1))s" -ForegroundColor Gray
Write-Host ""

# Table header
$headerFormat = "  {0,-4} {1,-50} {2,-8} {3,-12} {4,-10}"
Write-Host ($headerFormat -f '#', 'Benchmark Check', 'Status', 'Violations', 'Duration') -ForegroundColor White
Write-Host ("  " + ("-" * 84)) -ForegroundColor DarkGray

foreach ($r in $results) {
    $rowStatus = $r.Status
    $statusColor = switch ($rowStatus) {
        'Pass'    { 'Green' }
        'Fail'    { 'Red' }
        'Error'   { 'Yellow' }
        'Skipped' { 'DarkGray' }
    }

    $line = $headerFormat -f $r.CheckId, $r.CheckName, '', $r.ViolationCount, $r.Duration
    $statusStart = $line.IndexOf('        ') + 6
    Write-Host ("  {0,-4} {1,-50} " -f $r.CheckId, $r.CheckName) -NoNewline
    Write-Host ("{0,-8} " -f $rowStatus) -ForegroundColor $statusColor -NoNewline
    Write-Host ("{0,-12} {1,-10}" -f $r.ViolationCount, $r.Duration) -ForegroundColor Gray
}

Write-Host ("  " + ("-" * 84)) -ForegroundColor DarkGray
Write-Host ""

#endregion

#region JSON Export

if (-not $OutputPath) {
    $OutputPath = Join-Path (Get-Location) "copilot-benchmark-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').json"
}

$reportObject = [PSCustomObject]@{
    RunId       = $runId
    Timestamp   = (Get-Date).ToUniversalTime().ToString('o')
    Zone        = $Zone
    Parameters  = [PSCustomObject]@{
        TenantId             = if ($TenantId) { '***' } else { $null }
        DataverseUrl         = $DataverseUrl
        Zone                 = $Zone
        ExcludeSandbox       = $ExcludeSandbox.IsPresent
        ExcludeTrial         = $ExcludeTrial.IsPresent
        GracePeriodHours     = $GracePeriodHours
        WhatIf               = ($WhatIfPreference -or $PSBoundParameters.ContainsKey('WhatIf'))
    }
    Summary     = [PSCustomObject]@{
        TotalChecks    = $checks.Count
        Passed         = $passCount
        Failed         = $failCount
        Errors         = $errorCount
        Skipped        = $skipCount
        DurationSeconds = [math]::Round($totalDuration, 1)
    }
    Checks      = $results | ForEach-Object {
        [PSCustomObject]@{
            CheckId        = $_.CheckId
            CheckName      = $_.CheckName
            Solution       = $_.Solution
            Control        = $_.Control
            Status         = $_.Status
            ViolationCount = $_.ViolationCount
            AgentsScanned  = $_.AgentsScanned
            Duration       = $_.Duration
            ErrorMessage   = $_.ErrorMessage
        }
    }
    Details     = @{}
}

# Add per-check violation details (exclude raw details from summary)
foreach ($r in $results) {
    if ($r.Details -and $r.Details.Count -gt 0) {
        $reportObject.Details["check-$($r.CheckId)"] = $r.Details
    }
}

$jsonReport = $reportObject | ConvertTo-Json -Depth 10

try {
    $jsonReport | Out-File -FilePath $OutputPath -Encoding utf8
    Write-Host "  Report exported to: $OutputPath" -ForegroundColor Green
} catch {
    Write-Host "  Failed to write report: $_" -ForegroundColor Yellow
    Write-Host "  JSON output:" -ForegroundColor Gray
    Write-Output $jsonReport
}

Write-Host ""

#endregion
