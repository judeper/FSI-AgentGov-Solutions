<#
.SYNOPSIS
    Retrieves content moderation settings for all Copilot Studio agents across
    Power Platform environments.

.DESCRIPTION
    Enumerates Power Platform environments, connects to each environment's
    Dataverse instance, queries the bot table for Copilot Studio agents,
    and extracts the content moderation level from the agent's generative
    AI configuration.

    Unlike the Agent Access Monitor (v6) which queries environment-level settings,
    this script operates at agent granularity — one result per agent per environment.

.NOTES
    File: Get-AgentModerationSettings.ps1
    Version: 1.0.1
    Solution: Content Moderation Monitor (v7)
#>

#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

function Get-AgentModerationSettings {
    <#
    .SYNOPSIS
        Retrieves content moderation settings for all Copilot Studio agents across
        Power Platform environments.

    .DESCRIPTION
        Enumerates Power Platform environments, connects to each environment's
        Dataverse instance, queries the bot table for Copilot Studio agents,
        and extracts the content moderation level from the agent's generative
        AI configuration.

        Unlike the Agent Access Monitor (v6) which queries environment-level settings,
        this script operates at agent granularity — one result per agent per environment.

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
        Optional ELM Dataverse URL for zone classification lookup. If not provided,
        zone classification falls back to environment naming convention.

    .PARAMETER Top
        Limit total results returned. Use as a safety cap for large tenants.
        Default 0 means no limit.

    .EXAMPLE
        . ./Get-AgentModerationSettings.ps1
        Get-AgentModerationSettings

        Retrieves moderation settings for all agents across all environments.

    .EXAMPLE
        . ./Get-AgentModerationSettings.ps1
        Get-AgentModerationSettings -ExcludeSandbox -ExcludeTrial -GracePeriodHours 24

        Retrieves settings excluding sandbox and trial environments, and environments
        created within the last 24 hours.

    .EXAMPLE
        . ./Get-AgentModerationSettings.ps1
        Get-AgentModerationSettings -IncludeEnvironments "guid-1", "guid-2"

        Scans only the specified environments.

    .EXAMPLE
        . ./Get-AgentModerationSettings.ps1
        . ./Compare-ModerationCompliance.ps1
        Get-AgentModerationSettings -ExcludeSandbox | Compare-ModerationCompliance

        Retrieves moderation settings and pipes to compliance comparison.

    .EXAMPLE
        . ./Get-AgentModerationSettings.ps1
        Get-AgentModerationSettings -IncludeDrafts -Top 100

        Retrieves settings including draft agents, capped at 100 results.

    .OUTPUTS
        PSCustomObject[] — One object per agent with properties:
        AgentId, AgentName, AgentStatus, ContentModerationLevel,
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

    # Dot-source validation helpers (defines Test-EnvironmentFilter and others)
    . (Join-Path $privateRoot 'Test-ParameterValidation.ps1')

    # Import CMMClient module (Get-AgentBots, Get-BotModerationLevel, etc.)
    Import-Module (Join-Path $privateRoot 'CMMClient.psm1') -Force

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
        <#
        .SYNOPSIS
            Tests whether an individual environment passes the configured filters.
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
        # Most often this is an unauthenticated session. Surface a friendlier hint.
        $msg = $_.Exception.Message
        if ($msg -match 'authenticated|sign in|token|credential') {
            throw "Failed to retrieve Power Platform environments: $msg`n`nRun 'Add-PowerAppsAccount' (or pass a service-principal context) before invoking Get-AgentModerationSettings."
        }
        throw "Failed to retrieve Power Platform environments: $msg"
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
        Write-Progress -Activity "Scanning environments for agents" `
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
        $zoneResult = & (Join-Path $privateRoot 'Get-ZoneClassification.ps1') `
            -EnvironmentId $envId `
            -EnvironmentDisplayName $envName `
            -DataverseUrl $DataverseUrl `
            -AccessToken $elmToken
        # Extract Zone string from PSCustomObject returned by Get-ZoneClassification.ps1
        $zone = if ($zoneResult -is [PSCustomObject] -and $zoneResult.Zone) { $zoneResult.Zone } else { "$zoneResult" }

        Write-Verbose "Zone classification for $envName`: $zone"

        # Process each agent
        foreach ($bot in $bots) {
            # Extract content moderation level
            $moderationLevel = Get-BotModerationLevel -Bot $bot

            # Build result object
            $agentResult = [PSCustomObject]@{
                AgentId                = $bot.botid
                AgentName              = $bot.name
                AgentStatus            = if ($bot.statecode -eq 0) { 'Active' } else { 'Inactive' }
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
    Write-Progress -Activity "Scanning environments for agents" -Completed

    Write-Verbose "Total agents retrieved: $($results.Count)"

    # Runtime assertion: if all agents returned 'Unknown' moderation level,
    # the bot.configuration JSON key may have changed — warn about potential false-negatives
    if ($results.Count -gt 0) {
        $unknownCount = ($results | Where-Object { $_.ContentModerationLevel -eq 'Unknown' }).Count
        if ($unknownCount -eq $results.Count) {
            Write-Warning ("All $($results.Count) agent(s) returned 'Unknown' content moderation level. " +
                "The bot.configuration JSON key for content moderation may have changed. " +
                "Results may contain false-negatives. See TROUBLESHOOTING.md for guidance.")
        }
    }

    return $results.ToArray()

    #endregion
}
