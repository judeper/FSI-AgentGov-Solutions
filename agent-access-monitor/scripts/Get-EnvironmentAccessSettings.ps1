<#
.SYNOPSIS
    Retrieves agent access settings from Power Platform environments.

.DESCRIPTION
    Queries all Power Platform environments using the Power Platform Administration
    module and extracts bot/agent access governance settings from the extended
    settings configuration. Maps environments to governance zones and environment
    groups for compliance monitoring.

.PARAMETER IncludeEnvironments
    Array of environment IDs or display names to include. Mutually exclusive with ExcludeEnvironments.

.PARAMETER ExcludeEnvironments
    Array of environment IDs or display names to exclude. Mutually exclusive with IncludeEnvironments.

.PARAMETER ExcludeSandbox
    Exclude Sandbox type environments from results.

.PARAMETER ExcludeDefault
    Exclude the Default environment from results.

.PARAMETER ExcludeTrial
    Exclude Trial type environments from results.

.PARAMETER GracePeriodHours
    Hours to exclude newly created environments. Valid range: 0-168 (default: 48).

.PARAMETER DataverseUrl
    Optional Dataverse URL for ELM zone lookup. If not provided, uses naming convention fallback.

.PARAMETER AccessToken
    Optional access token for Dataverse authentication.

.EXAMPLE
    Get-EnvironmentAccessSettings
    
    Returns access settings for all environments using naming convention for zone classification.

.EXAMPLE
    Get-EnvironmentAccessSettings -ExcludeSandbox -ExcludeTrial -GracePeriodHours 24
    
    Returns settings for production-like environments, excluding those created in last 24 hours.

.EXAMPLE
    Get-EnvironmentAccessSettings -IncludeEnvironments "Trading-Z3-Prod", "Compliance-Z3-Prod"
    
    Returns settings only for the specified environments.

.EXAMPLE
    Get-EnvironmentAccessSettings -DataverseUrl "https://contoso-elm.crm.dynamics.com"
    
    Returns settings with zone lookup from ELM Dataverse table.

.OUTPUTS
    PSCustomObject[] with environment access settings:
    - EnvironmentId
    - EnvironmentDisplayName
    - EnvironmentType
    - CreatedTime
    - IsManaged
    - Zone
    - BotLimitSharingMode
    - BotAuthoringSharingDisabled
    - BotPublishedLimitSharingMode
    - EnvironmentGroupId
    - EnvironmentGroupName
    - RawSettings

.NOTES
    File: Get-EnvironmentAccessSettings.ps1
    Version: 1.1.2
    Requires: Microsoft.PowerApps.Administration.PowerShell module
#>

#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

[CmdletBinding()]
param(
    [Parameter()]
    [string[]]$IncludeEnvironments,
    
    [Parameter()]
    [string[]]$ExcludeEnvironments,
    
    [Parameter()]
    [switch]$ExcludeSandbox,
    
    [Parameter()]
    [switch]$ExcludeDefault,
    
    [Parameter()]
    [switch]$ExcludeTrial,
    
    [Parameter()]
    [ValidateRange(0, 168)]
    [int]$GracePeriodHours = 48,
    
    [Parameter()]
    [string]$DataverseUrl,
    
    [Parameter()]
    [string]$AccessToken
)

#region Import Private Helpers

$privateRoot = Join-Path $PSScriptRoot 'private'

# Import validation helpers
. (Join-Path $privateRoot 'Test-ParameterValidation.ps1')

#endregion

#region Parameter Validation

Write-Verbose "Validating filter parameters..."

$filterConfig = Test-EnvironmentFilter `
    -IncludeEnvironments $IncludeEnvironments `
    -ExcludeEnvironments $ExcludeEnvironments `
    -ExcludeSandbox:$ExcludeSandbox `
    -ExcludeDefault:$ExcludeDefault `
    -ExcludeTrial:$ExcludeTrial `
    -GracePeriodHours $GracePeriodHours

Write-Verbose "Filter mode: $($filterConfig.FilterMode)"

#endregion

#region Helper Functions

function Get-ExtendedSetting {
    <#
    .SYNOPSIS
        Extracts a setting from governanceConfiguration.settings.extendedSettings.
    #>
    param(
        [Parameter(Mandatory)]
        $Environment,
        
        [Parameter(Mandatory)]
        [string]$SettingKey
    )
    
    try {
        $extendedSettings = $Environment.Internal.governanceConfiguration.settings.extendedSettings
        if ($extendedSettings -and $extendedSettings.PSObject.Properties.Name -contains $SettingKey) {
            return $extendedSettings.$SettingKey
        }
    } catch {
        Write-Verbose "Setting '$SettingKey' not found in environment: $($Environment.DisplayName)"
    }
    
    return $null
}

function Test-LocalEnvironmentFilter {
    <#
    .SYNOPSIS
        Tests if an environment passes the configured filters.
    #>
    param(
        [Parameter(Mandatory)]
        $Environment,
        
        [Parameter(Mandatory)]
        $FilterConfig
    )
    
    $envId = $Environment.EnvironmentName
    $envName = $Environment.DisplayName
    $envType = $Environment.EnvironmentType
    $createdTime = $Environment.CreatedTime
    
    # Include filter - whitelist mode
    if ($FilterConfig.FilterMode -eq 'Include') {
        foreach ($include in $FilterConfig.IncludeEnvironments) {
            if ($envId -eq $include -or $envName -like "*$include*") {
                return $true
            }
        }
        return $false
    }
    
    # Exclude filter - blacklist mode
    if ($FilterConfig.FilterMode -eq 'Exclude') {
        foreach ($exclude in $FilterConfig.ExcludeEnvironments) {
            if ($envId -eq $exclude -or $envName -like "*$exclude*") {
                Write-Verbose "Excluding environment by explicit filter: $envName"
                return $false
            }
        }
    }
    
    # Type filters
    if ($FilterConfig.ExcludeSandbox -and $envType -eq 'Sandbox') {
        Write-Verbose "Excluding Sandbox environment: $envName"
        return $false
    }
    
    if ($FilterConfig.ExcludeDefault -and $envType -eq 'Default') {
        Write-Verbose "Excluding Default environment: $envName"
        return $false
    }
    
    if ($FilterConfig.ExcludeTrial -and $envType -like '*Trial*') {
        Write-Verbose "Excluding Trial environment: $envName"
        return $false
    }
    
    # Grace period filter
    if ($FilterConfig.GraceCutoff -and $createdTime -gt $FilterConfig.GraceCutoff) {
        Write-Verbose "Excluding environment within grace period: $envName (created: $createdTime)"
        return $false
    }
    
    return $true
}

#endregion

#region Main Logic

Write-Verbose "Retrieving Power Platform environments..."

try {
    $environments = Get-AdminPowerAppEnvironment -ErrorAction Stop
    Write-Verbose "Found $($environments.Count) total environments"
} catch {
    throw "Failed to retrieve environments: $($_.Exception.Message)"
}

# Build environment group lookup
Write-Verbose "Retrieving environment groups..."
$groupLookup = @{}

try {
    $groups = Get-AdminPowerAppEnvironmentGroup -ErrorAction SilentlyContinue
    if ($groups) {
        foreach ($group in $groups) {
            $groupLookup[$group.Id] = $group
            Write-Verbose "Loaded group: $($group.DisplayName)"
        }
    }
} catch {
    Write-Warning "Failed to retrieve environment groups: $($_.Exception.Message)"
}

# Process environments
$results = @()

# Pre-fetch zone classifications in a single batch query to avoid N+1 HTTP requests
$zoneLookup = @{}
if ($DataverseUrl -and $AccessToken) {
    try {
        $headers = @{
            'Authorization'    = "Bearer $AccessToken"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }
        $uri = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2/fsi_accessbaselines?`$filter=fsi_isactive eq true&`$select=fsi_environmentguid,fsi_zone"
        $maxRetries = 3
        $allRecords = @()
        $currentUri = $uri
        do {
            $response = $null
            for ($i = 0; $i -lt $maxRetries; $i++) {
                try {
                    $response = Invoke-RestMethod -Uri $currentUri -Method Get -Headers $headers -ErrorAction Stop
                    break
                } catch {
                    $statusCode = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { 0 }
                    if (($statusCode -eq 429 -or $statusCode -ge 500) -and $i -lt ($maxRetries - 1)) {
                        $delay = [math]::Pow(2, $i)
                        Write-Verbose "Zone batch query failed (HTTP $statusCode), retrying in ${delay}s..."
                        Start-Sleep -Seconds $delay
                    } else {
                        throw
                    }
                }
            }
            if ($response.value) {
                $allRecords += $response.value
            }
            $currentUri = $response.'@odata.nextLink'
        } while ($currentUri)
        $zoneMap = @{ 100000001 = 'Zone1'; 100000002 = 'Zone2'; 100000003 = 'Zone3' }
        if ($allRecords) {
            foreach ($record in $allRecords) {
                $envGuid = $record.fsi_environmentguid
                $zoneValue = $record.fsi_zone
                if ($envGuid -and $zoneMap.ContainsKey([int]$zoneValue)) {
                    $zoneLookup[$envGuid] = $zoneMap[[int]$zoneValue]
                }
            }
        }
        Write-Verbose "Pre-fetched zone classifications for $($zoneLookup.Count) environment(s)"
    } catch {
        Write-Warning "Batch zone lookup failed: $($_.Exception.Message). Using naming convention classification as fallback."
    }
}

foreach ($env in $environments) {
    Write-Verbose "Processing environment: $($env.DisplayName)"
    
    # Apply filters
    if (-not (Test-LocalEnvironmentFilter -Environment $env -FilterConfig $filterConfig)) {
        continue
    }
    
    # Get zone classification from pre-fetched lookup or fall back to naming convention
    $zone = $null
    if ($zoneLookup.ContainsKey($env.EnvironmentName)) {
        $zone = $zoneLookup[$env.EnvironmentName]
    } else {
        # Fallback: naming convention heuristic (no HTTP call needed)
        $name = $env.DisplayName
        if ($name -match '(?i)(prod|production|enterprise|zone\s*3)') {
            $zone = 'Zone3'
        } elseif ($name -match '(?i)(team|department|shared|zone\s*2)') {
            $zone = 'Zone2'
        } elseif ($name -match '(?i)(personal|dev|sandbox|zone\s*1)') {
            $zone = 'Zone1'
        } else {
            $zone = 'Unknown'
        }
    }
    
    Write-Verbose "Zone classification: $zone"
    
    # Extract bot access settings
    $botLimitSharingMode = Get-ExtendedSetting -Environment $env -SettingKey 'bot-limitSharingMode'
    $botAuthoringSharingDisabled = Get-ExtendedSetting -Environment $env -SettingKey 'bot-authoringSharingDisabled'
    $botPublishedLimitSharingMode = Get-ExtendedSetting -Environment $env -SettingKey 'bot-publishedBotLimitSharingMode'
    
    # Get environment group info
    $groupId = $null
    $groupName = $null
    
    if ($env.Internal.properties.environmentGroup) {
        $groupId = $env.Internal.properties.environmentGroup.id
        if ($groupLookup.ContainsKey($groupId)) {
            $groupName = $groupLookup[$groupId].DisplayName
        }
    }
    
    # Determine if environment is managed (has Microsoft Dataverse)
    $isManaged = $null -ne $env.Internal.properties.linkedEnvironmentMetadata
    
    # Build raw settings for debugging
    $rawSettings = @{}
    try {
        $extendedSettings = $env.Internal.governanceConfiguration.settings.extendedSettings
        if ($extendedSettings) {
            foreach ($prop in $extendedSettings.PSObject.Properties) {
                if ($prop.Name -like 'bot-*') {
                    $rawSettings[$prop.Name] = $prop.Value
                }
            }
        }
    } catch {
        Write-Verbose "Could not extract raw settings for: $($env.DisplayName)"
    }
    
    # Build result object
    $result = [PSCustomObject]@{
        EnvironmentId               = $env.EnvironmentName
        EnvironmentDisplayName      = $env.DisplayName
        EnvironmentType             = $env.EnvironmentType
        CreatedTime                 = $env.CreatedTime
        IsManaged                   = $isManaged
        Zone                        = $zone
        BotLimitSharingMode         = $botLimitSharingMode
        BotAuthoringSharingDisabled = $botAuthoringSharingDisabled
        BotPublishedLimitSharingMode = $botPublishedLimitSharingMode
        EnvironmentGroupId          = $groupId
        EnvironmentGroupName        = $groupName
        RawSettings                 = $rawSettings
    }
    
    $results += $result
}

Write-Verbose "Returning $($results.Count) environments after filtering"

return $results

#endregion
