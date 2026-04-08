<#
.SYNOPSIS
    End-to-end file upload compliance validation orchestrator.

.DESCRIPTION
    Orchestrates the complete file upload compliance validation pipeline:
    1. Enumerate Power Platform environments (with filters)
    2. Query agents for file upload and content moderation settings
    3. Compare against zone-specific governance policies
    4. Generate multi-format compliance reports

    Supports dry-run mode for testing without Dataverse queries.

.NOTES
    File: Test-FileUploadCompliance.ps1
    Version: 1.0.0
    Solution: File Upload Security Configurator (v8)
#>

#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

[CmdletBinding()]
param(
    #region Environment Filters

    [Parameter()]
    [string[]]$IncludeEnvironments,

    [Parameter()]
    [string[]]$ExcludeEnvironments,

    [Parameter()]
    [switch]$ExcludeSandbox,

    [Parameter()]
    [switch]$ExcludeTrial,

    [Parameter()]
    [switch]$ExcludeDefault,

    [Parameter()]
    [ValidateRange(0, 168)]
    [int]$GracePeriodHours = 48,

    #endregion

    #region Output Options

    [Parameter()]
    [ValidateSet('Table', 'JSON', 'CSV')]
    [string]$OutputFormat = 'Table',

    [Parameter()]
    [string]$OutputPath,

    #endregion

    #region Behavioral Options

    [Parameter()]
    [switch]$IncludeCompliant,

    [Parameter()]
    [switch]$IncludeDrafts,

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [string]$BaselinePath,

    [Parameter()]
    [string]$DataverseUrl,

    [Parameter()]
    [int]$Top = 0

    #endregion
)

#region Import Dependencies

$scriptRoot = $PSScriptRoot

# Dot-source Get and Compare scripts
. (Join-Path $scriptRoot 'Get-AgentFileUploadSettings.ps1')
. (Join-Path $scriptRoot 'Compare-FileUploadCompliance.ps1')

#endregion

#region Banner

$banner = @"

╔══════════════════════════════════════════════════════════════╗
║           File Upload Security Configurator v1.0.0          ║
║         FSI Agent Governance Framework - Control 1.14       ║
╚══════════════════════════════════════════════════════════════╝

"@

Write-Host $banner -ForegroundColor Cyan

#endregion

#region Dry-Run Mode

if ($DryRun) {
    Write-Host "  Mode: DRY RUN (no Dataverse queries)" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "  Configuration:" -ForegroundColor White
    Write-Host "    Output Format:        $OutputFormat"
    Write-Host "    Include Compliant:    $($IncludeCompliant.IsPresent)"
    Write-Host "    Include Drafts:       $($IncludeDrafts.IsPresent)"
    Write-Host "    Grace Period:         $GracePeriodHours hours"
    Write-Host "    Environment Filter:   $(if ($IncludeEnvironments) { 'Include: ' + ($IncludeEnvironments -join ', ') } elseif ($ExcludeEnvironments) { 'Exclude: ' + ($ExcludeEnvironments -join ', ') } else { 'All (with type filters)' })"
    Write-Host "    Exclude Sandbox:      $($ExcludeSandbox.IsPresent)"
    Write-Host "    Exclude Trial:        $($ExcludeTrial.IsPresent)"
    Write-Host "    Exclude Default:      $($ExcludeDefault.IsPresent)"
    Write-Host "    Top Cap:              $(if ($Top -gt 0) { $Top } else { 'None' })"
    Write-Host "    Baseline Path:        $(if ($BaselinePath) { $BaselinePath } else { 'Default (templates/fileupload-baseline.json)' })"
    Write-Host "    ELM Dataverse URL:    $(if ($DataverseUrl) { $DataverseUrl } else { 'Not configured (naming convention fallback)' })"
    Write-Host ""
    Write-Host "  Zone Policy Summary:" -ForegroundColor White

    # Load and display baseline
    $displayBaselinePath = if ($BaselinePath) { $BaselinePath } else { Join-Path $scriptRoot '..' 'templates' 'fileupload-baseline.json' }
    if (Test-Path $displayBaselinePath) {
        $bl = Get-Content $displayBaselinePath -Raw | ConvertFrom-Json
        foreach ($zoneKey in @('Zone 1', 'Zone 2', 'Zone 3')) {
            if ($bl.zoneRequirements.PSObject.Properties.Name -contains $zoneKey) {
                $zp = $bl.zoneRequirements.$zoneKey
                $status = if ($zp.fileUploadAllowed) { 'Allowed' } else { 'Disabled' }
                $approval = if ($zp.requiresApproval) { 'Required' } else { 'Not required' }
                Write-Host "    $($zoneKey): File Upload=$status, Approval=$approval, Min Moderation=$($zp.minimumModerationLevel)"
            }
        }
    }

    Write-Host ""
    Write-Host "  To execute the actual scan, remove the -DryRun flag." -ForegroundColor Gray
    return
}

#endregion

#region Execute Validation Pipeline

try {

$startTime = Get-Date
$runId = [Guid]::NewGuid().ToString()

Write-Host "  Run ID:     $runId" -ForegroundColor Gray
Write-Host "  Started:    $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
Write-Host ""

# Step 1: Enumerate agents with file upload settings
Write-Host "  [1/3] Enumerating agents..." -ForegroundColor White

$getParams = @{}
if ($IncludeEnvironments)  { $getParams['IncludeEnvironments']  = $IncludeEnvironments }
if ($ExcludeEnvironments)  { $getParams['ExcludeEnvironments']  = $ExcludeEnvironments }
if ($ExcludeSandbox)       { $getParams['ExcludeSandbox']       = $true }
if ($ExcludeTrial)         { $getParams['ExcludeTrial']         = $true }
if ($ExcludeDefault)       { $getParams['ExcludeDefault']       = $true }
if ($PSBoundParameters.ContainsKey('GracePeriodHours')) { $getParams['GracePeriodHours'] = $GracePeriodHours }
if ($IncludeDrafts)        { $getParams['IncludeDrafts']        = $true }
if ($DataverseUrl)         { $getParams['DataverseUrl']         = $DataverseUrl }
if ($Top -gt 0)            { $getParams['Top']                  = $Top }

$agentSettings = Get-AgentFileUploadSettings @getParams

if (-not $agentSettings -or $agentSettings.Count -eq 0) {
    Write-Host "  No agents found. Validation complete." -ForegroundColor Yellow
    return
}

$fileUploadEnabledCount = ($agentSettings | Where-Object { $_.FileUploadEnabled -eq $true }).Count

Write-Host "        Found $($agentSettings.Count) agent(s) across environments" -ForegroundColor Green
Write-Host "        File uploads enabled: $fileUploadEnabledCount" -ForegroundColor $(if ($fileUploadEnabledCount -gt 0) { 'Yellow' } else { 'Green' })

# Step 2: Compare against zone policies
Write-Host "  [2/3] Evaluating compliance..." -ForegroundColor White

$compareParams = @{
    AgentSettings = $agentSettings
}
if ($BaselinePath) { $compareParams['BaselinePath'] = $BaselinePath }
if ($IncludeCompliant) { $compareParams['IncludeCompliant'] = $true }

$complianceResults = Compare-FileUploadCompliance @compareParams

# Calculate summary statistics
$totalAgents = $agentSettings.Count
$violations = if ($complianceResults) { @($complianceResults | Where-Object { -not $_.IsCompliant }) } else { @() }
$compliant = $totalAgents - $violations.Count
$overallStatus = if ($violations.Count -eq 0) { 'COMPLIANT' } else { 'VIOLATIONS_FOUND' }

$severitySummary = @{
    Critical = ($violations | Where-Object { $_.Severity -eq 'Critical' }).Count
    High     = ($violations | Where-Object { $_.Severity -eq 'High' }).Count
    Medium   = ($violations | Where-Object { $_.Severity -eq 'Medium' }).Count
    Warning  = ($violations | Where-Object { $_.Severity -eq 'Warning' }).Count
}

Write-Host "        Compliant: $compliant / $totalAgents" -ForegroundColor $(if ($violations.Count -eq 0) { 'Green' } else { 'Yellow' })

if ($violations.Count -gt 0) {
    Write-Host "        Violations: $($violations.Count)" -ForegroundColor Red
    foreach ($sev in @('Critical', 'High', 'Medium', 'Warning')) {
        if ($severitySummary[$sev] -gt 0) {
            $color = switch ($sev) {
                'Critical' { 'Red' }
                'High'     { 'Red' }
                'Medium'   { 'Yellow' }
                'Warning'  { 'Yellow' }
            }
            Write-Host "          $($sev): $($severitySummary[$sev])" -ForegroundColor $color
        }
    }
}

# Step 3: Format and output results
Write-Host "  [3/3] Generating output ($OutputFormat)..." -ForegroundColor White

$resultsToOutput = if ($complianceResults) { @($complianceResults) } else { @() }

switch ($OutputFormat) {
    'Table' {
        Write-Host ""

        if ($resultsToOutput.Count -gt 0) {
            $resultsToOutput | Format-Table -AutoSize -Property @(
                'AgentName',
                @{Name='Zone'; Expression={$_.Zone}; Width=8},
                @{Name='FileUpload'; Expression={if ($_.FileUploadEnabled) {'Enabled'} else {'Disabled'}}; Width=10},
                @{Name='Expected'; Expression={$_.ExpectedFileUpload}; Width=10},
                @{Name='Moderation'; Expression={$_.ContentModerationLevel}; Width=12},
                @{Name='Compliant'; Expression={if ($_.IsCompliant) {'Yes'} else {'NO'}}; Width=10},
                @{Name='Severity'; Expression={$_.Severity}; Width=10},
                'EnvironmentDisplayName'
            )
        } else {
            if ($IncludeCompliant) {
                Write-Host "  No agents found in scan results." -ForegroundColor Gray
            } else {
                Write-Host "  All agents compliant — no violations to display." -ForegroundColor Green
                Write-Host "  Use -IncludeCompliant to see all agents." -ForegroundColor Gray
            }
        }
    }
    'JSON' {
        $jsonOutput = [PSCustomObject]@{
            metadata = [PSCustomObject]@{
                runId          = $runId
                timestamp      = (Get-Date).ToUniversalTime().ToString('o')
                solution       = 'File Upload Security Configurator'
                version        = '1.0.0'
                control        = '1.14'
                totalAgents    = $totalAgents
                compliant      = $compliant
                violations     = $violations.Count
                fileUploadEnabled = $fileUploadEnabledCount
                overallStatus  = $overallStatus
                severity       = $severitySummary
            }
            results = $resultsToOutput
        }

        $jsonString = $jsonOutput | ConvertTo-Json -Depth 10

        if ($OutputPath) {
            $jsonString | Out-File -FilePath $OutputPath -Encoding utf8
            Write-Host "        JSON output written to: $OutputPath" -ForegroundColor Green
        } else {
            Write-Output $jsonString
        }
    }
    'CSV' {
        $csvPath = if ($OutputPath) { $OutputPath } else {
            Join-Path $scriptRoot ".." "file-upload-compliance-$(Get-Date -Format 'yyyy-MM-dd-HHmmss').csv"
        }

        if ($resultsToOutput.Count -gt 0) {
            $resultsToOutput | Select-Object `
                AgentId, AgentName, EnvironmentId, EnvironmentDisplayName, Zone,
                FileUploadEnabled, ExpectedFileUpload,
                ContentModerationLevel, ExpectedModerationLevel,
                IsCompliant, FileUploadCompliant, ModerationCompliant,
                Severity, ViolationType, RegulatoryContext, AgentStatus |
                Export-Csv -Path $csvPath -NoTypeInformation -Encoding utf8

            Write-Host "        CSV output written to: $csvPath" -ForegroundColor Green
        } else {
            Write-Host "        No results to export." -ForegroundColor Gray
        }
    }
}

#endregion

#region Summary Banner

$elapsed = (Get-Date) - $startTime

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor $(if ($overallStatus -eq 'COMPLIANT') { 'Green' } else { 'Red' })
Write-Host "║  Status: $($overallStatus.PadRight(50))║" -ForegroundColor $(if ($overallStatus -eq 'COMPLIANT') { 'Green' } else { 'Red' })
Write-Host "║  Agents: $($totalAgents.ToString().PadRight(50))║" -ForegroundColor White
Write-Host "║  File Uploads Enabled: $($fileUploadEnabledCount.ToString().PadRight(37))║" -ForegroundColor $(if ($fileUploadEnabledCount -gt 0) { 'Yellow' } else { 'White' })
Write-Host "║  Compliant: $($compliant.ToString().PadRight(47))║" -ForegroundColor Green
Write-Host "║  Violations: $($violations.Count.ToString().PadRight(46))║" -ForegroundColor $(if ($violations.Count -gt 0) { 'Red' } else { 'Green' })
Write-Host "║  Duration: $($elapsed.ToString('mm\:ss').PadRight(48))║" -ForegroundColor Gray
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor $(if ($overallStatus -eq 'COMPLIANT') { 'Green' } else { 'Red' })
Write-Host ""

#endregion

} catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  At: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    throw
}
