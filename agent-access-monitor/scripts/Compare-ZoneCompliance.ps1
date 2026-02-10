<#
.SYNOPSIS
    Compares environment access settings against zone compliance baselines.

.DESCRIPTION
    Accepts environment access settings (from Get-EnvironmentAccessSettings) and
    compares each setting against the expected values for the environment's zone.
    Identifies violations with severity classification and regulatory context.

.PARAMETER EnvironmentSettings
    Array of environment settings objects from Get-EnvironmentAccessSettings.
    Accepts pipeline input.

.PARAMETER BaselinePath
    Path to zone-settings-baseline.json. Defaults to ../templates/zone-settings-baseline.json.

.PARAMETER IncludeCompliant
    Include environments that pass all compliance checks in output.
    By default, only non-compliant environments are returned.

.EXAMPLE
    Get-EnvironmentAccessSettings | Compare-ZoneCompliance
    
    Returns compliance results for all non-compliant environments.

.EXAMPLE
    Get-EnvironmentAccessSettings -ExcludeSandbox | Compare-ZoneCompliance -IncludeCompliant
    
    Returns compliance results for all environments including compliant ones.

.EXAMPLE
    $settings = Get-EnvironmentAccessSettings
    $violations = Compare-ZoneCompliance -EnvironmentSettings $settings
    $violations | Where-Object { $_.HighestSeverity -eq 'Critical' }
    
    Filters for environments with critical violations.

.OUTPUTS
    PSCustomObject[] with compliance results:
    - EnvironmentId
    - EnvironmentDisplayName
    - EnvironmentType
    - Zone
    - IsCompliant
    - ViolationCount
    - HighestSeverity
    - Violations (array of violation details)

.NOTES
    File: Compare-ZoneCompliance.ps1
    Version: 0.1.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline)]
    [PSCustomObject[]]$EnvironmentSettings,
    
    [Parameter()]
    [string]$BaselinePath,
    
    [Parameter()]
    [switch]$IncludeCompliant
)

begin {
    #region Load Baseline
    
    # Default baseline path
    if (-not $BaselinePath) {
        $BaselinePath = Join-Path $PSScriptRoot '..' 'templates' 'zone-settings-baseline.json'
    }
    
    # Resolve path
    $resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BaselinePath)
    
    if (-not (Test-Path $resolvedPath)) {
        throw "Baseline file not found: $resolvedPath"
    }
    
    Write-Verbose "Loading baseline from: $resolvedPath"
    $baseline = Get-Content $resolvedPath -Raw | ConvertFrom-Json
    
    # Severity ranking for determining highest severity
    $severityRank = @{
        'Critical' = 4
        'High'     = 3
        'Warning'  = 2
        'Info'     = 1
    }
    
    # Settings to check
    $settingsToCheck = @(
        'BotLimitSharingMode',
        'BotAuthoringSharingDisabled',
        'BotPublishedLimitSharingMode'
    )
    
    # Mapping from property names to baseline keys
    $settingKeyMap = @{
        'BotLimitSharingMode'         = 'bot-limitSharingMode'
        'BotAuthoringSharingDisabled' = 'bot-authoringSharingDisabled'
        'BotPublishedLimitSharingMode' = 'bot-publishedBotLimitSharingMode'
    }
    
    # Results collection for pipeline processing
    $allResults = @()
    
    #endregion
    
    #region Helper Functions
    
    function Get-ZoneConfig {
        param(
            [string]$Zone,
            $Baseline
        )
        
        if ($Baseline.zones.PSObject.Properties.Name -contains $Zone) {
            return $Baseline.zones.$Zone
        }
        
        # Default to Unknown zone handling
        return $Baseline.zones.Unknown
    }
    
    function Get-ViolationSeverity {
        param(
            [string]$Zone,
            [string]$SettingKey,
            [string]$ActualValue,
            $ZoneConfig
        )
        
        # Build lookup key
        $lookupKey = "${SettingKey}_${ActualValue}"
        
        # Check specific violation mapping
        if ($ZoneConfig.violations.PSObject.Properties.Name -contains $lookupKey) {
            return $ZoneConfig.violations.$lookupKey
        }
        
        # Check for 'any_setting' fallback (Zone1)
        if ($ZoneConfig.violations.PSObject.Properties.Name -contains 'any_setting') {
            return $ZoneConfig.violations.any_setting
        }
        
        # Default
        return 'Warning'
    }
    
    function Get-RegulatoryContext {
        param(
            [string]$Severity,
            $Baseline
        )
        
        if ($Baseline.regulatory_context.PSObject.Properties.Name -contains $Severity) {
            return $Baseline.regulatory_context.$Severity
        }
        
        return "No regulatory context defined for severity: $Severity"
    }
    
    function Get-SettingDescription {
        param(
            [string]$SettingKey,
            [string]$Value,
            $Baseline
        )
        
        if ($Baseline.setting_descriptions.PSObject.Properties.Name -contains $SettingKey) {
            $settingDef = $Baseline.setting_descriptions.$SettingKey
            $valueStr = $Value.ToString().ToLower()
            if ($settingDef.PSObject.Properties.Name -contains $valueStr) {
                return $settingDef.$valueStr
            }
        }
        
        return "Unknown setting or value: $SettingKey = $Value"
    }
    
    #endregion
}

process {
    foreach ($envSetting in $EnvironmentSettings) {
        Write-Verbose "Checking compliance for: $($envSetting.EnvironmentDisplayName)"
        
        $zone = $envSetting.Zone
        $violations = @()
        $highestSeverityRank = 0
        $highestSeverity = 'None'
        
        # Get zone configuration
        $zoneConfig = Get-ZoneConfig -Zone $zone -Baseline $baseline
        
        # Handle Unknown zone
        if ($zone -eq 'Unknown') {
            $violation = [PSCustomObject]@{
                Setting           = 'Zone Classification'
                SettingKey        = 'zone'
                ExpectedValue     = 'Zone1, Zone2, or Zone3'
                ActualValue       = 'Unknown'
                Severity          = 'Warning'
                Description       = 'Environment is not assigned to a governance zone'
                RegulatoryContext = Get-RegulatoryContext -Severity 'Warning' -Baseline $baseline
            }
            $violations += $violation
            $highestSeverity = 'Warning'
            $highestSeverityRank = $severityRank['Warning']
        } else {
            # Check each setting against expected values
            foreach ($settingProp in $settingsToCheck) {
                $settingKey = $settingKeyMap[$settingProp]
                $actualValue = $envSetting.$settingProp
                
                # Skip if setting is null (not configured)
                if ($null -eq $actualValue) {
                    Write-Verbose "Setting '$settingProp' is null, skipping check"
                    continue
                }
                
                # Get expected value
                $expectedValue = $null
                if ($zoneConfig.expected.PSObject.Properties.Name -contains $settingKey) {
                    $expectedValue = $zoneConfig.expected.$settingKey
                }
                
                # Compare values (handle boolean and string comparison)
                $isViolation = $false
                if ($null -ne $expectedValue) {
                    # Normalize boolean comparison
                    $actualNormalized = $actualValue
                    $expectedNormalized = $expectedValue
                    
                    if ($actualValue -is [bool]) {
                        $actualNormalized = $actualValue.ToString().ToLower()
                    } elseif ($actualValue -is [string]) {
                        $actualNormalized = $actualValue.ToLower()
                    }
                    
                    if ($expectedValue -is [bool]) {
                        $expectedNormalized = $expectedValue.ToString().ToLower()
                    } elseif ($expectedValue -is [string]) {
                        $expectedNormalized = $expectedValue.ToLower()
                    }
                    
                    $isViolation = $actualNormalized -ne $expectedNormalized
                }
                
                if ($isViolation) {
                    $severity = Get-ViolationSeverity `
                        -Zone $zone `
                        -SettingKey $settingKey `
                        -ActualValue $actualValue.ToString() `
                        -ZoneConfig $zoneConfig
                    
                    $violation = [PSCustomObject]@{
                        Setting           = $settingProp
                        SettingKey        = $settingKey
                        ExpectedValue     = $expectedValue
                        ActualValue       = $actualValue
                        Severity          = $severity
                        Description       = Get-SettingDescription -SettingKey $settingKey -Value $actualValue.ToString() -Baseline $baseline
                        RegulatoryContext = Get-RegulatoryContext -Severity $severity -Baseline $baseline
                    }
                    
                    $violations += $violation
                    
                    # Track highest severity
                    if ($severityRank.ContainsKey($severity) -and $severityRank[$severity] -gt $highestSeverityRank) {
                        $highestSeverityRank = $severityRank[$severity]
                        $highestSeverity = $severity
                    }
                }
            }
        }
        
        # Build result
        $isCompliant = $violations.Count -eq 0
        
        $result = [PSCustomObject]@{
            EnvironmentId          = $envSetting.EnvironmentId
            EnvironmentDisplayName = $envSetting.EnvironmentDisplayName
            EnvironmentType        = $envSetting.EnvironmentType
            Zone                   = $zone
            IsCompliant            = $isCompliant
            ViolationCount         = $violations.Count
            HighestSeverity        = $highestSeverity
            Violations             = $violations
        }
        
        # Apply IncludeCompliant filter
        if ($isCompliant -and -not $IncludeCompliant) {
            Write-Verbose "Skipping compliant environment: $($envSetting.EnvironmentDisplayName)"
            continue
        }
        
        $allResults += $result
    }
}

end {
    # Summary logging
    $totalEnvironments = $allResults.Count
    $nonCompliantCount = ($allResults | Where-Object { -not $_.IsCompliant }).Count
    $criticalCount = ($allResults | Where-Object { $_.HighestSeverity -eq 'Critical' }).Count
    $highCount = ($allResults | Where-Object { $_.HighestSeverity -eq 'High' }).Count
    
    Write-Verbose "Compliance check complete:"
    Write-Verbose "  Total environments: $totalEnvironments"
    Write-Verbose "  Non-compliant: $nonCompliantCount"
    Write-Verbose "  Critical violations: $criticalCount"
    Write-Verbose "  High violations: $highCount"
    
    return $allResults
}
