<#
.SYNOPSIS
    Retrieves file upload settings for all Copilot Studio agents across
    Power Platform environments.

.DESCRIPTION
    Enumerates Power Platform environments, connects to each environment's
    Dataverse instance, queries the bot table for Copilot Studio agents,
    and extracts the file upload enabled status and content moderation level
    from each agent's configuration.

    Operates at agent granularity — one result per agent per environment.

.NOTES
    File: Get-AgentFileUploadSettings.ps1
    Version: 1.0.0
    Solution: File Upload Security Configurator (v8)
#>

#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

function Get-AgentFileUploadSettings {
    <#
    .SYNOPSIS
        Retrieves file upload settings for all Copilot Studio agents across
        Power Platform environments.

    .DESCRIPTION
        Enumerates Power Platform environments, connects to each environment's
        Dataverse instance, queries the bot table for Copilot Studio agents,
        and extracts the file upload enabled status and content moderation level.

    .PARAMETER IncludeEnvironments
        Limit scan to specific environment IDs. Mutually exclusive with ExcludeEnvironments.

    .PARAMETER ExcludeEnvironments
        Exclude specific environment IDs from scan. Mutually exclusive with IncludeEnvironments.

    .PARAMETER ExcludeSandbox
        Exclude sandbox environments from the scan.

    .PARAMETER ExcludeTrial
        Exclude trial environments from the scan.

    .PARAMETER ExcludeDefault
        Exclude the default environment from the scan.

    .PARAMETER GracePeriodHours
        Exclude environments created within this many hours. Valid range: 0-168 (default: 48).

    .PARAMETER IncludeDrafts
        Include draft/unpublished agents. By default, only published (active) agents
        are returned.

    .PARAMETER DataverseUrl
        Optional ELM Dataverse URL for zone classification lookup.

    .PARAMETER Top
        Limit total results returned. Default 0 means no limit.

    .EXAMPLE
        . ./Get-AgentFileUploadSettings.ps1
        Get-AgentFileUploadSettings

        Retrieves file upload settings for all agents across all environments.

    .EXAMPLE
        . ./Get-AgentFileUploadSettings.ps1
        . ./Compare-FileUploadCompliance.ps1
        Get-AgentFileUploadSettings -ExcludeSandbox | Compare-FileUploadCompliance

        Retrieves file upload settings and pipes to compliance comparison.

    .OUTPUTS
        PSCustomObject[] — One object per agent with properties:
        AgentId, AgentName, AgentStatus, FileUploadEnabled, ContentModerationLevel,
        EnvironmentId, EnvironmentDisplayName, EnvironmentType,
        Zone, DataverseUrl, LastPublished, RetrievedAt
    #>
    [CmdletBinding()]
    param(
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

        [Parameter()]
        [switch]$IncludeDrafts,

        [Parameter()]
        [string]$DataverseUrl,

        [Parameter()]
        [int]$Top = 0
    )

    #region Import Private Helpers

    $privateRoot = Join-Path $PSScriptRoot 'private'

    # Dot-source validation helpers
    . (Join-Path $privateRoot 'Test-ParameterValidation.ps1')
    . (Join-Path $privateRoot 'Get-ZoneClassification.ps1')

    # Import FUSClient module
    Import-Module (Join-Path $privateRoot 'FUSClient.psm1') -Force

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

    #region Local Helper Functions

    function Test-EnvironmentPassesFilter {
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

        # Include filter — whitelist mode
        if ($FilterConfig.FilterMode -eq 'Include') {
            foreach ($include in $FilterConfig.IncludeEnvironments) {
                if ($envId -eq $include -or $envName -like "*$include*") {
                    return $true
                }
            }
            return $false
        }

        # Exclude filter — blacklist mode
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

    # Retrieve all Power Platform environments
    Write-Verbose "Retrieving Power Platform environments..."

    try {
        $allEnvironments = Get-AdminPowerAppEnvironment -ErrorAction Stop
        Write-Verbose "Found $($allEnvironments.Count) total environments"
    } catch {
        throw "Failed to retrieve Power Platform environments: $($_.Exception.Message)"
    }

    # Apply filters
    $filteredEnvironments = @()

    foreach ($env in $allEnvironments) {
        if (Test-EnvironmentPassesFilter -Environment $env -FilterConfig $filterConfig) {
            $filteredEnvironments += $env
        }
    }

    Write-Verbose "Environments after filter: $($filteredEnvironments.Count)"

    # Filter to environments WITH Dataverse instances
    $dvEnvironments = @()

    foreach ($env in $filteredEnvironments) {
        if ($env.Internal.properties.linkedEnvironmentMetadata) {
            $dvEnvironments += $env
        } else {
            Write-Verbose "Skipping environment without Dataverse: $($env.DisplayName)"
        }
    }

    Write-Verbose "Environments with Dataverse: $($dvEnvironments.Count)"

    if ($dvEnvironments.Count -eq 0) {
        Write-Warning "No environments with Dataverse instances found after filtering."
        return @()
    }

    # Acquire ELM token once if DataverseUrl provided (for zone classification)
    $elmToken = $null

    if ($DataverseUrl) {
        Write-Verbose "Acquiring ELM Dataverse token for zone lookup..."
        try {
            $elmToken = & (Join-Path $privateRoot 'Connect-EnvironmentDataverse.ps1') `
                -DataverseUrl $DataverseUrl
            Write-Verbose "ELM token acquired"
        } catch {
            Write-Warning "Failed to connect to ELM Dataverse ($DataverseUrl): $($_.Exception.Message). Zone lookup will fall back to naming convention."
            $DataverseUrl = $null
        }
    }

    # Process each environment
    $results = [System.Collections.Generic.List[PSCustomObject]]::new()
    $envIndex = 0
    $topReached = $false

    foreach ($env in $dvEnvironments) {
        if ($topReached) { break }

        $envIndex++
        $envId = $env.EnvironmentName
        $envName = $env.DisplayName
        $envType = $env.EnvironmentType
        $envDataverseUrl = $env.Internal.properties.linkedEnvironmentMetadata.instanceUrl

        if (-not $envDataverseUrl) {
            Write-Warning "Dataverse URL not found for environment: $envName ($envId). Skipping."
            continue
        }

        # Normalize Dataverse URL
        $envDataverseUrl = $envDataverseUrl.TrimEnd('/')

        # Progress reporting
        Write-Progress -Activity "Scanning environments for file upload settings" `
            -Status "Processing $envName ($envIndex of $($dvEnvironments.Count))" `
            -PercentComplete (($envIndex / $dvEnvironments.Count) * 100)

        # Connect to environment Dataverse
        Write-Verbose "Connecting to Dataverse for environment: $envName ($envDataverseUrl)"

        $envToken = $null
        try {
            $envToken = & (Join-Path $privateRoot 'Connect-EnvironmentDataverse.ps1') `
                -DataverseUrl $envDataverseUrl
        } catch {
            Write-Warning "Failed to connect to Dataverse for environment '$envName': $($_.Exception.Message). Skipping."
            continue
        }

        # Query agents (bots) from this environment
        Write-Verbose "Querying agents from: $envName"
        $bots = Get-AgentBots -DataverseUrl $envDataverseUrl -AccessToken $envToken -IncludeDrafts:$IncludeDrafts

        if (-not $bots -or $bots.Count -eq 0) {
            Write-Verbose "No agents found in environment: $envName"
            continue
        }

        Write-Verbose "Found $($bots.Count) agent(s) in: $envName"

        # Get zone classification for this environment
        $zone = Get-ZoneClassification `
            -EnvironmentId $envId `
            -EnvironmentDisplayName $envName `
            -DataverseUrl $DataverseUrl `
            -AccessToken $elmToken

        Write-Verbose "Zone classification for $envName`: $zone"

        # Process each agent
        foreach ($bot in $bots) {
            # Extract file upload enabled status
            $fileUploadEnabled = Get-BotFileUploadEnabled -Bot $bot

            # Extract content moderation level (for cross-check)
            $moderationLevel = Get-BotModerationLevel -Bot $bot

            # Build result object
            $agentResult = [PSCustomObject]@{
                AgentId                = $bot.botid
                AgentName              = $bot.name
                AgentStatus            = if ($bot.statecode -eq 0) { 'Active' } else { 'Inactive' }
                FileUploadEnabled      = $fileUploadEnabled
                ContentModerationLevel = $moderationLevel
                EnvironmentId          = $envId
                EnvironmentDisplayName = $envName
                EnvironmentType        = $envType
                Zone                   = $zone
                DataverseUrl           = $envDataverseUrl
                LastPublished          = $bot.publishedon
                RetrievedAt            = (Get-Date)
            }

            $results.Add($agentResult)

            # Check Top cap
            if ($Top -gt 0 -and $results.Count -ge $Top) {
                Write-Verbose "Top cap reached ($Top). Stopping enumeration."
                $topReached = $true
                break
            }
        }
    }

    # Complete progress bar
    Write-Progress -Activity "Scanning environments for file upload settings" -Completed

    Write-Verbose "Total agents retrieved: $($results.Count)"

    return $results.ToArray()

    #endregion
}
