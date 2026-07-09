<#
.SYNOPSIS
    Retrieves expected settings and severity mappings for a zone.

.DESCRIPTION
    Loads zone configuration from baseline JSON and provides helper methods
    for comparing settings and determining violation severity.

.PARAMETER Zone
    The governance zone: Zone1, Zone2, Zone3, or Unknown.

.PARAMETER BaselinePath
    Path to zone-settings-baseline.json file.

.OUTPUTS
    PSCustomObject with zone configuration and helper methods.

.EXAMPLE
    $zoneConfig = Get-ExpectedSettings -Zone "Zone1"
    $severity = $zoneConfig.GetSeverity("bot-limitSharingMode", "noLimit")
    # Returns: Critical

.NOTES
    File: Get-ExpectedSettings.ps1
    Version: 1.2.0
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Zone1', 'Zone2', 'Zone3', 'Unknown')]
    [string]$Zone,
    
    [Parameter()]
    [string]$BaselinePath = "$PSScriptRoot/../../templates/zone-settings-baseline.json"
)

# Resolve path
$resolvedPath = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($BaselinePath)

if (-not (Test-Path $resolvedPath)) {
    throw "Baseline file not found: $resolvedPath"
}

# Load baseline
$baseline = Get-Content $resolvedPath -Raw | ConvertFrom-Json

# Get zone configuration
$zoneConfig = $baseline.zones.$Zone

if (-not $zoneConfig) {
    throw "Zone configuration not found for: $Zone"
}

# Build output object with helper methods
$result = [PSCustomObject]@{
    Zone              = $Zone
    Description       = $zoneConfig.description
    Expected          = $zoneConfig.expected
    Violations        = $zoneConfig.violations
    RegulatoryContext = $baseline.regulatory_context
    SettingDescriptions = $baseline.setting_descriptions
}

# Add GetSeverity method
$result | Add-Member -MemberType ScriptMethod -Name 'GetSeverity' -Value {
    param([string]$SettingKey, [string]$ActualValue)
    
    # Build violation lookup key
    $lookupKey = "${SettingKey}_${ActualValue}"
    
    # Check violations mapping
    if ($this.Violations.PSObject.Properties.Name -contains $lookupKey) {
        return $this.Violations.$lookupKey
    }
    
    # Check for 'any_setting' fallback (Zone3)
    if ($this.Violations.PSObject.Properties.Name -contains 'any_setting') {
        return $this.Violations.any_setting
    }
    
    # Default to Warning
    return 'Warning'
}

# Add GetExpectedValue method
$result | Add-Member -MemberType ScriptMethod -Name 'GetExpectedValue' -Value {
    param([string]$SettingKey)
    
    if ($this.Expected.PSObject.Properties.Name -contains $SettingKey) {
        return $this.Expected.$SettingKey
    }
    
    return $null
}

# Add GetRegulatoryContext method
$result | Add-Member -MemberType ScriptMethod -Name 'GetRegulatoryContext' -Value {
    param([string]$Severity)
    
    if ($this.RegulatoryContext.PSObject.Properties.Name -contains $Severity) {
        return $this.RegulatoryContext.$Severity
    }
    
    return "No regulatory context defined for severity: $Severity"
}

# Add GetSettingDescription method
$result | Add-Member -MemberType ScriptMethod -Name 'GetSettingDescription' -Value {
    param([string]$SettingKey, [string]$Value)
    
    if ($this.SettingDescriptions.PSObject.Properties.Name -contains $SettingKey) {
        $settingDef = $this.SettingDescriptions.$SettingKey
        if ($settingDef.PSObject.Properties.Name -contains $Value) {
            return $settingDef.$Value
        }
    }
    
    return "Unknown setting or value: $SettingKey = $Value"
}

return $result
