<#
.SYNOPSIS
    Orchestrates agent access compliance scanning across Power Platform environments.

.DESCRIPTION
    Main entry point for the Agent Access Governance Monitor. Queries environments,
    compares settings against zone-specific baselines, generates compliance reports
    with severity classification, and outputs results in multiple formats.

    Supports dry-run mode via -WhatIf for validation without persistence.

.PARAMETER ExcludeSandbox
    Exclude Sandbox type environments from compliance scan.

.PARAMETER ExcludeTrial
    Exclude Trial type environments from compliance scan.

.PARAMETER ExcludeDefault
    Exclude the Default environment from compliance scan.

.PARAMETER GracePeriodHours
    Hours to exclude newly created environments from violation reporting.
    Valid range: 0-168 (1 week). Default: 48 hours.
    Environments within grace period are scanned but flagged as 'InGracePeriod'.

.PARAMETER DataverseUrl
    Dataverse URL for ELM (Environment Lifecycle Management) zone lookup.
    If not provided, falls back to environment naming convention for zone classification.

.PARAMETER OutputFormat
    Output format for results. Default: Table.
    - Table: Human-readable console output with color-coded severities
    - JSON: JSON string for integration with other tools
    - Object: PSCustomObject for PowerShell pipeline processing

.PARAMETER IncludeCompliant
    Include environments that pass all compliance checks in output.
    By default, only non-compliant environments are returned.

.PARAMETER BaselinePath
    Path to zone-settings-baseline.json file.
    Defaults to ../templates/zone-settings-baseline.json relative to script location.

.EXAMPLE
    .\Test-AgentAccessCompliance.ps1
    
    Runs compliance scan with default settings, outputs table format to console.

.EXAMPLE
    .\Test-AgentAccessCompliance.ps1 -ExcludeSandbox -ExcludeTrial -OutputFormat JSON
    
    Scans production-like environments and outputs JSON for automation.

.EXAMPLE
    .\Test-AgentAccessCompliance.ps1 -IncludeCompliant -OutputFormat Object | Export-Csv report.csv
    
    Exports full compliance report to CSV including compliant environments.

.EXAMPLE
    .\Test-AgentAccessCompliance.ps1 -GracePeriodHours 0 -WhatIf
    
    Validates what would be checked without grace period filtering.
    WhatIf mode skips any persistence operations (Phase 2).

.EXAMPLE
    .\Test-AgentAccessCompliance.ps1 -DataverseUrl "https://contoso-elm.crm.dynamics.com"
    
    Uses ELM Dataverse table for zone classification lookup.

.OUTPUTS
    Varies by OutputFormat:
    - Table: Console output (no object returned)
    - JSON: JSON string
    - Object: PSCustomObject with Summary, ZoneSummary, Environments, OverallStatus

.NOTES
    File: Test-AgentAccessCompliance.ps1
    Version: 0.1.0
    Requires: Microsoft.PowerApps.Administration.PowerShell module

    Part of FSI Agent Governance Framework
    Controls: 2.5 (Agent Sharing Scope), 2.6 (Restrict Team-Created Agent Sharing)
    Regulations: FINRA 4511, SOX 404, GLBA 501(b)
#>

#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()]
    [switch]$ExcludeSandbox,
    
    [Parameter()]
    [switch]$ExcludeTrial,
    
    [Parameter()]
    [switch]$ExcludeDefault,
    
    [Parameter()]
    [ValidateRange(0, 168)]
    [int]$GracePeriodHours = 48,
    
    [Parameter()]
    [string]$DataverseUrl,
    
    [Parameter()]
    [string]$DataverseToken,
    
    [Parameter()]
    [switch]$PersistResults,
    
    [Parameter()]
    [ValidateSet('Table', 'JSON', 'Object')]
    [string]$OutputFormat = 'Table',
    
    [Parameter()]
    [switch]$IncludeCompliant,
    
    [Parameter()]
    [string]$BaselinePath
)

#region Script Initialization

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot

# Banner
Write-Verbose "========================================="
Write-Verbose "Agent Access Governance Monitor v0.1.0"
Write-Verbose "========================================="

#endregion

#region Dataverse Integration

if ($DataverseUrl) {
    try {
        Import-Module "$PSScriptRoot/private/AAMClient.psm1" -Force
        Connect-AAMDataverse -DataverseUrl $DataverseUrl -AccessToken $DataverseToken
        
        # Read operational parameters from Dataverse environment variables
        $dvGracePeriod = Get-AAMEnvironmentVariable -Name "GracePeriodHours" -DefaultValue $GracePeriodHours
        if ($dvGracePeriod -ne $GracePeriodHours) {
            Write-Verbose "Dataverse override: GracePeriodHours=$dvGracePeriod (was $GracePeriodHours)"
            $GracePeriodHours = [int]$dvGracePeriod
        }
        
        $dvIncludeSandbox = Get-AAMEnvironmentVariable -Name "IncludeSandbox" -DefaultValue "false"
        if ($dvIncludeSandbox -eq "true" -and $ExcludeSandbox) {
            Write-Verbose "Dataverse override: IncludeSandbox=true, overriding -ExcludeSandbox switch"
            $ExcludeSandbox = $false
        }
        
        Write-Verbose "Dataverse parameters loaded successfully"
    } catch {
        Write-Warning "Cannot read from Dataverse: $($_.Exception.Message). Using default parameters."
    }
}

#endregion

#region Dot-Source Dependencies

# Import companion scripts
$getSettingsScript = Join-Path $scriptRoot 'Get-EnvironmentAccessSettings.ps1'
$compareComplianceScript = Join-Path $scriptRoot 'Compare-ZoneCompliance.ps1'

if (-not (Test-Path $getSettingsScript)) {
    throw "Required script not found: $getSettingsScript"
}

if (-not (Test-Path $compareComplianceScript)) {
    throw "Required script not found: $compareComplianceScript"
}

Write-Verbose "Loading Get-EnvironmentAccessSettings from: $getSettingsScript"
Write-Verbose "Loading Compare-ZoneCompliance from: $compareComplianceScript"

#endregion

#region Build Parameters for Get-EnvironmentAccessSettings

$getSettingsParams = @{
    GracePeriodHours = $GracePeriodHours
}

if ($ExcludeSandbox) {
    $getSettingsParams['ExcludeSandbox'] = $true
}

if ($ExcludeTrial) {
    $getSettingsParams['ExcludeTrial'] = $true
}

if ($ExcludeDefault) {
    $getSettingsParams['ExcludeDefault'] = $true
}

if ($DataverseUrl) {
    $getSettingsParams['DataverseUrl'] = $DataverseUrl
}

#endregion

#region Query Environment Settings

Write-Verbose "Querying Power Platform environments..."

# Build argument list for script invocation
$argList = @()
if ($ExcludeSandbox) { $argList += '-ExcludeSandbox' }
if ($ExcludeTrial) { $argList += '-ExcludeTrial' }
if ($ExcludeDefault) { $argList += '-ExcludeDefault' }
$argList += "-GracePeriodHours", $GracePeriodHours
if ($DataverseUrl) { $argList += "-DataverseUrl", $DataverseUrl }

$environmentSettings = & $getSettingsScript @getSettingsParams

if (-not $environmentSettings -or $environmentSettings.Count -eq 0) {
    Write-Warning "No environments found matching the specified criteria."
    
    $emptyResult = [PSCustomObject]@{
        Summary = [PSCustomObject]@{
            ValidationTime     = (Get-Date -Format 'o')
            TotalEnvironments  = 0
            CompliantCount     = 0
            ViolationCount     = 0
            CriticalViolations = 0
            HighViolations     = 0
            WarningViolations  = 0
            InfoViolations     = 0
        }
        ZoneSummary = [PSCustomObject]@{
            Zone1   = 0
            Zone2   = 0
            Zone3   = 0
            Unknown = 0
        }
        Environments  = @()
        OverallStatus = 'Passed'
    }
    
    switch ($OutputFormat) {
        'JSON'   { return $emptyResult | ConvertTo-Json -Depth 10 }
        'Object' { return $emptyResult }
        'Table'  { 
            Write-Host "`nNo environments found to scan.`n" -ForegroundColor Yellow
            return 
        }
    }
}

Write-Verbose "Found $($environmentSettings.Count) environment(s)"

#endregion

#region Compare Zone Compliance

Write-Verbose "Comparing against zone baselines..."

# Build parameters for Compare-ZoneCompliance
$compareParams = @{
    EnvironmentSettings = $environmentSettings
}

if ($IncludeCompliant) {
    $compareParams['IncludeCompliant'] = $true
}

if ($BaselinePath) {
    $compareParams['BaselinePath'] = $BaselinePath
}

$complianceResults = & $compareComplianceScript @compareParams

#endregion

#region Calculate Summary Statistics

$validationTime = Get-Date -Format 'o'

# Count environments by zone
$zoneCounts = @{
    Zone1   = 0
    Zone2   = 0
    Zone3   = 0
    Unknown = 0
}

foreach ($env in $environmentSettings) {
    $zone = $env.Zone
    if ($zoneCounts.ContainsKey($zone)) {
        $zoneCounts[$zone]++
    } else {
        $zoneCounts['Unknown']++
    }
}

# Count violations by severity
$violationCounts = @{
    Critical = 0
    High     = 0
    Warning  = 0
    Info     = 0
}

$compliantCount = 0
$nonCompliantEnvs = @()

foreach ($result in $complianceResults) {
    if ($result.IsCompliant) {
        $compliantCount++
    } else {
        $nonCompliantEnvs += $result
        foreach ($violation in $result.Violations) {
            $severity = $violation.Severity
            if ($violationCounts.ContainsKey($severity)) {
                $violationCounts[$severity]++
            }
        }
    }
}

# If IncludeCompliant is false, complianceResults only contains non-compliant
# We need to calculate compliant count from total minus non-compliant
if (-not $IncludeCompliant) {
    $compliantCount = $environmentSettings.Count - $complianceResults.Count
    $nonCompliantEnvs = $complianceResults
}

$totalViolations = $violationCounts.Critical + $violationCounts.High + $violationCounts.Warning + $violationCounts.Info

# Determine overall status
$overallStatus = 'Passed'
if ($violationCounts.Critical -gt 0) {
    $overallStatus = 'Failed'
} elseif ($violationCounts.High -gt 0) {
    $overallStatus = 'Warning'
} elseif ($totalViolations -gt 0) {
    $overallStatus = 'Review'
}

#endregion

#region Build Result Object

$summary = [PSCustomObject]@{
    ValidationTime     = $validationTime
    TotalEnvironments  = $environmentSettings.Count
    CompliantCount     = $compliantCount
    ViolationCount     = $totalViolations
    CriticalViolations = $violationCounts.Critical
    HighViolations     = $violationCounts.High
    WarningViolations  = $violationCounts.Warning
    InfoViolations     = $violationCounts.Info
}

$zoneSummary = [PSCustomObject]@{
    Zone1   = $zoneCounts.Zone1
    Zone2   = $zoneCounts.Zone2
    Zone3   = $zoneCounts.Zone3
    Unknown = $zoneCounts.Unknown
}

$result = [PSCustomObject]@{
    Summary       = $summary
    ZoneSummary   = $zoneSummary
    Environments  = if ($IncludeCompliant) { $complianceResults } else { $nonCompliantEnvs }
    OverallStatus = $overallStatus
}

#endregion

#region Dataverse Persistence

if ($DataverseUrl -and $PersistResults) {
    $runId = [guid]::NewGuid().ToString()
    
    # Build validation result hashtable for Write-AAMValidationHistory
    $validationResult = @{
        TotalEnvironments = $summary.TotalEnvironments
        CompliantCount    = $compliantCount
        ViolationCount    = $totalViolations
        OverallStatus     = $overallStatus
        ZoneSummary       = $zoneCounts
        ValidationTime    = $validationTime
    }
    
    # Write summary to validation history (immutable)
    if ($PSCmdlet.ShouldProcess("fsi_accessvalidationhistory", "Write validation summary (RunId=$runId)")) {
        try {
            Write-AAMValidationHistory -ValidationResult $validationResult -RunId $runId
            Write-Verbose "Validation history written: RunId=$runId"
        } catch {
            Write-Warning "Failed to write validation history: $($_.Exception.Message)"
        }
    }
    
    # Write individual violations
    $allViolations = @()
    foreach ($envResult in $nonCompliantEnvs) {
        foreach ($violation in $envResult.Violations) {
            $violationRecord = @{
                EnvironmentId          = $envResult.EnvironmentId
                EnvironmentDisplayName = $envResult.EnvironmentDisplayName
                Zone                   = $envResult.Zone
                ViolationType          = $violation.Setting
                Expected               = $violation.ExpectedValue
                Actual                 = $violation.ActualValue
                Severity               = $violation.Severity
                RegulatoryContext      = $violation.RegulatoryContext
            }
            $allViolations += $violationRecord
        }
    }
    
    foreach ($violation in $allViolations) {
        if ($PSCmdlet.ShouldProcess("fsi_accessviolations", "Write violation: $($violation.EnvironmentDisplayName) - $($violation.ViolationType)")) {
            try {
                Write-AAMViolation -Violation $violation -RunId $runId
            } catch {
                Write-Warning "Failed to write violation for $($violation.EnvironmentDisplayName): $($_.Exception.Message)"
            }
        }
    }
    
    if ($allViolations.Count -gt 0) {
        Write-Verbose "Wrote $($allViolations.Count) violation(s) to Dataverse"
    }
} elseif ($DataverseUrl -and -not $PersistResults) {
    Write-Verbose "Dataverse connected but -PersistResults not specified. Skipping persistence."
}

#endregion

#region Output Results

switch ($OutputFormat) {
    'JSON' {
        return $result | ConvertTo-Json -Depth 10
    }
    
    'Object' {
        return $result
    }
    
    'Table' {
        # Console output with colors
        Write-Host "`n=========================================" -ForegroundColor Cyan
        Write-Host "  Agent Access Compliance Report" -ForegroundColor Cyan
        Write-Host "  Generated: $($summary.ValidationTime)" -ForegroundColor Gray
        Write-Host "=========================================`n" -ForegroundColor Cyan
        
        # Overall Status
        $statusColor = switch ($overallStatus) {
            'Failed'  { 'Red' }
            'Warning' { 'Yellow' }
            'Review'  { 'DarkYellow' }
            'Passed'  { 'Green' }
            default   { 'White' }
        }
        Write-Host "Overall Status: " -NoNewline
        Write-Host $overallStatus -ForegroundColor $statusColor
        Write-Host ""
        
        # Summary Statistics
        Write-Host "Environment Summary:" -ForegroundColor White
        Write-Host "  Total Scanned:    $($summary.TotalEnvironments)"
        Write-Host "  Compliant:        $($summary.CompliantCount)" -ForegroundColor Green
        Write-Host "  Non-Compliant:    $($summary.TotalEnvironments - $summary.CompliantCount)" -ForegroundColor $(if ($summary.TotalEnvironments - $summary.CompliantCount -gt 0) { 'Red' } else { 'Green' })
        Write-Host ""
        
        # Zone Distribution
        Write-Host "Zone Distribution:" -ForegroundColor White
        Write-Host "  Zone1 (Personal):   $($zoneSummary.Zone1)"
        Write-Host "  Zone2 (Team):       $($zoneSummary.Zone2)"
        Write-Host "  Zone3 (Enterprise): $($zoneSummary.Zone3)"
        if ($zoneSummary.Unknown -gt 0) {
            Write-Host "  Unknown:            $($zoneSummary.Unknown)" -ForegroundColor Yellow
        }
        Write-Host ""
        
        # Violations by Severity
        Write-Host "Violations by Severity:" -ForegroundColor White
        if ($violationCounts.Critical -gt 0) {
            Write-Host "  Critical: $($violationCounts.Critical)" -ForegroundColor Red
        } else {
            Write-Host "  Critical: 0" -ForegroundColor Gray
        }
        if ($violationCounts.High -gt 0) {
            Write-Host "  High:     $($violationCounts.High)" -ForegroundColor Yellow
        } else {
            Write-Host "  High:     0" -ForegroundColor Gray
        }
        if ($violationCounts.Warning -gt 0) {
            Write-Host "  Warning:  $($violationCounts.Warning)" -ForegroundColor DarkYellow
        } else {
            Write-Host "  Warning:  0" -ForegroundColor Gray
        }
        if ($violationCounts.Info -gt 0) {
            Write-Host "  Info:     $($violationCounts.Info)" -ForegroundColor Cyan
        } else {
            Write-Host "  Info:     0" -ForegroundColor Gray
        }
        Write-Host ""
        
        # Non-Compliant Environments Detail
        if ($nonCompliantEnvs.Count -gt 0) {
            Write-Host "-----------------------------------------" -ForegroundColor Gray
            Write-Host "Non-Compliant Environments:" -ForegroundColor White
            Write-Host "-----------------------------------------" -ForegroundColor Gray
            
            foreach ($env in $nonCompliantEnvs) {
                $envSeverityColor = switch ($env.HighestSeverity) {
                    'Critical' { 'Red' }
                    'High'     { 'Yellow' }
                    'Warning'  { 'DarkYellow' }
                    'Info'     { 'Cyan' }
                    default    { 'White' }
                }
                
                Write-Host "`n  $($env.EnvironmentDisplayName)" -ForegroundColor White
                Write-Host "    ID: $($env.EnvironmentId)" -ForegroundColor Gray
                Write-Host "    Zone: $($env.Zone) | Type: $($env.EnvironmentType)" -ForegroundColor Gray
                Write-Host "    Highest Severity: " -NoNewline
                Write-Host $env.HighestSeverity -ForegroundColor $envSeverityColor
                Write-Host "    Violations ($($env.ViolationCount)):" -ForegroundColor Gray
                
                foreach ($violation in $env.Violations) {
                    $violationColor = switch ($violation.Severity) {
                        'Critical' { 'Red' }
                        'High'     { 'Yellow' }
                        'Warning'  { 'DarkYellow' }
                        'Info'     { 'Cyan' }
                        default    { 'White' }
                    }
                    
                    Write-Host "      [$($violation.Severity)] " -NoNewline -ForegroundColor $violationColor
                    Write-Host "$($violation.Setting): " -NoNewline
                    Write-Host "'$($violation.ActualValue)' (expected: '$($violation.ExpectedValue)')" -ForegroundColor Gray
                }
            }
            Write-Host ""
        }
        
        # Compliant environments (if requested)
        if ($IncludeCompliant) {
            $compliantEnvs = $complianceResults | Where-Object { $_.IsCompliant }
            if ($compliantEnvs.Count -gt 0) {
                Write-Host "-----------------------------------------" -ForegroundColor Gray
                Write-Host "Compliant Environments:" -ForegroundColor Green
                Write-Host "-----------------------------------------" -ForegroundColor Gray
                
                foreach ($env in $compliantEnvs) {
                    Write-Host "  [OK] $($env.EnvironmentDisplayName) ($($env.Zone))" -ForegroundColor Green
                }
                Write-Host ""
            }
        }
        
        Write-Host "=========================================`n" -ForegroundColor Cyan
    }
}

#endregion
