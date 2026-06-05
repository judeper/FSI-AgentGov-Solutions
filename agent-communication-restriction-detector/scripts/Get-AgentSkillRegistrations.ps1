<#
.SYNOPSIS
    Retrieves agent skill registrations for all Copilot Studio agents
    across Power Platform environments.

.DESCRIPTION
    Enumerates Power Platform environments, connects to each environment's
    Dataverse instance, queries the bot table for Copilot Studio agents,
    and extracts skill registration details including target agent references,
    manifest URLs, and zone classifications.

    This script operates at skill granularity -- one result per skill per
    agent per environment. It queries bot and botcomponent tables to build
    a comprehensive picture of each agent's communication posture.

.NOTES
    File: Get-AgentSkillRegistrations.ps1
    Version: 1.1.1
    Solution: Agent Communication Restriction Detector (ACRD)
    Control: 2.17 (Multi-Agent Orchestration Limits)
#>

#Requires -Version 5.1
#Requires -PSEdition Desktop
#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

function Get-AgentSkillRegistrations {
    <#
    .SYNOPSIS
        Retrieves agent skill registrations for all Copilot Studio agents
        across Power Platform environments.

    .DESCRIPTION
        Enumerates Power Platform environments, connects to each environment's
        Dataverse instance, queries the bot table for Copilot Studio agents,
        and extracts skill registration details including target agent references,
        manifest URLs, and zone classifications for communication policy evaluation.

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
        . ./Get-AgentSkillRegistrations.ps1
        Get-AgentSkillRegistrations

        Retrieves skill registrations for all agents across all environments.

    .EXAMPLE
        . ./Get-AgentSkillRegistrations.ps1
        Get-AgentSkillRegistrations -ExcludeSandbox -ExcludeTrial -GracePeriodHours 24

        Retrieves registrations excluding sandbox and trial environments, and environments
        created within the last 24 hours.

    .EXAMPLE
        . ./Get-AgentSkillRegistrations.ps1
        Get-AgentSkillRegistrations -IncludeEnvironments "guid-1", "guid-2"

        Scans only the specified environments.

    .OUTPUTS
        PSCustomObject[] -- One object per skill registration with properties:
        EnvironmentId, EnvironmentDisplayName, Zone, AgentId, AgentName,
        SkillName, TargetAgentId, TargetAgentName, TargetEnvironmentId,
        TargetZone, ManifestUrl, OwnerId, DataverseUrl, RetrievedAt
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

    # Import ACRDClient module (Get-AgentBots, etc.)
    Import-Module (Join-Path $privateRoot 'ACRDClient.psm1') -Force

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

        # Include filter -- whitelist mode
        if ($FilterConfig.FilterMode -eq 'Include') {
            foreach ($include in $FilterConfig.IncludeEnvironments) {
                if ($envId -eq $include -or $envName -like "*$include*") {
                    return $true
                }
            }
            return $false
        }

        # Exclude filter -- blacklist mode
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

    function Get-BotSkillRegistrations {
        <#
        .SYNOPSIS
            Extracts skill registrations from bot components.
        .DESCRIPTION
            Queries botcomponent filtered by _botid_value to find skill/connector
            registrations that reference other agents. Parses component content JSON
            for target agent references and manifest URLs.
        #>
        param(
            [Parameter(Mandatory)]
            [PSCustomObject]$Bot,

            [Parameter(Mandatory)]
            [string]$EnvDataverseUrl,

            [Parameter(Mandatory)]
            [string]$EnvToken
        )

        $skills = @()
        $baseUrl = $EnvDataverseUrl.TrimEnd('/')
        $headers = @{
            'Authorization'    = "Bearer $EnvToken"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }

        try {
            # Query botcomponents for skill-type components. Per the botcomponent
            # table reference (botcomponent_componenttype option set), componenttype
            # 1 = Skill and 13 = Skill (V2). (Values 2 and 10 are "Bot variable" and
            # "Bot translations (V2)" respectively, not skills.) The bot a component
            # belongs to is the parentbotid lookup, exposed in OData as
            # _parentbotid_value; botcomponent has no _botid_value column. Lookup
            # GUIDs are filtered without quotes.
            # Ref: https://learn.microsoft.com/power-apps/developer/data-platform/reference/entities/botcomponent
            $componentsUri = "$baseUrl/api/data/v9.2/botcomponents?" +
                "`$filter=_parentbotid_value eq $($Bot.botid) and (componenttype eq 1 or componenttype eq 13)&" +
                "`$select=name,content,componenttype,schemaname"

            $componentsResponse = Invoke-RestMethod -Uri $componentsUri -Method Get -Headers $headers -ErrorAction Stop

            if ($componentsResponse.value) {
                foreach ($component in $componentsResponse.value) {
                    $skillEntry = @{
                        SkillName       = $component.name
                        TargetAgentId   = $null
                        TargetAgentName = $null
                        TargetEnvironmentId = $null
                        ManifestUrl     = $null
                    }

                    # Parse component content for target agent and manifest references
                    if ($component.content) {
                        try {
                            $contentStr = $component.content
                            $null = $contentStr | ConvertFrom-Json -ErrorAction Stop

                            # Look for skill manifest URL patterns
                            if ($contentStr -match '"manifestUrl"\s*:\s*"([^"]+)"') {
                                $skillEntry.ManifestUrl = $Matches[1]
                            } elseif ($contentStr -match '"manifest"\s*:\s*"([^"]+)"') {
                                $skillEntry.ManifestUrl = $Matches[1]
                            }

                            # Look for target bot/agent ID references. Current Copilot
                            # Studio connected-agent schema often stores the called agent
                            # by schema name rather than GUID.
                            if ($contentStr -match '"targetBotId"\s*:\s*"([^"]+)"') {
                                $skillEntry.TargetAgentId = $Matches[1]
                            } elseif ($contentStr -match '"skillBotId"\s*:\s*"([^"]+)"') {
                                $skillEntry.TargetAgentId = $Matches[1]
                            } elseif ($contentStr -match '"botId"\s*:\s*"([^"]+)"' -and $Matches[1] -ne $Bot.botid) {
                                $skillEntry.TargetAgentId = $Matches[1]
                            } elseif ($contentStr -match '"botSchemaName"\s*:\s*"([^"]+)"') {
                                $skillEntry.TargetAgentId = $Matches[1]
                            } elseif ($contentStr -match '"connectedAgentSchemaName"\s*:\s*"([^"]+)"') {
                                $skillEntry.TargetAgentId = $Matches[1]
                            } elseif ($contentStr -match '"agentSchemaName"\s*:\s*"([^"]+)"') {
                                $skillEntry.TargetAgentId = $Matches[1]
                            }

                            # Look for target agent name
                            if ($contentStr -match '"targetBotName"\s*:\s*"([^"]+)"') {
                                $skillEntry.TargetAgentName = $Matches[1]
                            } elseif ($contentStr -match '"skillBotName"\s*:\s*"([^"]+)"') {
                                $skillEntry.TargetAgentName = $Matches[1]
                            }

                            # Look for target environment ID (cross-environment skills)
                            if ($contentStr -match '"targetEnvironmentId"\s*:\s*"([^"]+)"') {
                                $skillEntry.TargetEnvironmentId = $Matches[1]
                            } elseif ($contentStr -match '"environmentId"\s*:\s*"([^"]+)"') {
                                $skillEntry.TargetEnvironmentId = $Matches[1]
                            }

                        } catch {
                            Write-Verbose "Failed to parse botcomponent content for '$($component.name)' in bot '$($Bot.name)'"
                        }
                    }

                    # Only include components that reference another agent or have a manifest
                    if ($skillEntry.TargetAgentId -or $skillEntry.ManifestUrl) {
                        $skills += [PSCustomObject]$skillEntry
                    }
                }
            }
        } catch {
            Write-Verbose "botcomponent query failed for $($Bot.name): $($_.Exception.Message)"
        }

        return $skills
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
        Write-Progress -Activity "Scanning environments for agent skill registrations" `
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
        $zone = & (Join-Path $privateRoot 'Get-ZoneClassification.ps1') `
            -EnvironmentId $envId `
            -EnvironmentDisplayName $envName `
            -DataverseUrl $DataverseUrl `
            -AccessToken $elmToken

        Write-Verbose "Zone classification for $envName`: $zone"

        # Process each agent
        foreach ($bot in $bots) {
            # Extract skill registrations
            $skillRegistrations = Get-BotSkillRegistrations -Bot $bot -EnvDataverseUrl $envDataverseUrl -EnvToken $envToken

            if (-not $skillRegistrations -or $skillRegistrations.Count -eq 0) {
                Write-Verbose "No skill registrations found for agent: $($bot.name)"
                continue
            }

            # Determine owner ID from bot record
            $ownerId = if ($bot._ownerid_value) { $bot._ownerid_value } else { $null }

            foreach ($skill in $skillRegistrations) {
                # Attempt to resolve target zone if target environment is known
                $targetZone = 'Unknown'
                if ($skill.TargetEnvironmentId -and $skill.TargetEnvironmentId -ne $envId) {
                    # Cross-environment skill -- try to classify target zone
                    try {
                        $targetEnvInfo = $dvEnvironments | Where-Object { $_.EnvironmentName -eq $skill.TargetEnvironmentId }
                        if ($targetEnvInfo) {
                            $targetZone = & (Join-Path $privateRoot 'Get-ZoneClassification.ps1') `
                                -EnvironmentId $skill.TargetEnvironmentId `
                                -EnvironmentDisplayName $targetEnvInfo.DisplayName `
                                -DataverseUrl $DataverseUrl `
                                -AccessToken $elmToken
                        }
                    } catch {
                        Write-Verbose "Unable to classify target zone for $($skill.TargetEnvironmentId): $($_.Exception.Message)"
                    }
                } elseif (-not $skill.TargetEnvironmentId -or $skill.TargetEnvironmentId -eq $envId) {
                    # Same environment -- same zone
                    $targetZone = $zone
                }

                $registrationResult = [PSCustomObject]@{
                    EnvironmentId          = $envId
                    EnvironmentDisplayName = $envName
                    Zone                   = $zone
                    AgentId                = $bot.botid
                    AgentName              = $bot.name
                    SkillName              = $skill.SkillName
                    TargetAgentId          = $skill.TargetAgentId
                    TargetAgentName        = $skill.TargetAgentName
                    TargetEnvironmentId    = $skill.TargetEnvironmentId
                    TargetZone             = $targetZone
                    ManifestUrl            = $skill.ManifestUrl
                    OwnerId                = $ownerId
                    DataverseUrl           = $envDataverseUrl
                    RetrievedAt            = (Get-Date).ToUniversalTime()
                }

                $results.Add($registrationResult)

                # Check Top cap
                if ($Top -gt 0 -and $results.Count -ge $Top) {
                    Write-Verbose "Top cap reached ($Top). Stopping enumeration."
                    $topReached = $true
                    break
                }
            }

            if ($topReached) { break }
        }
    }

    # Complete progress bar
    Write-Progress -Activity "Scanning environments for agent skill registrations" -Completed

    Write-Verbose "Total skill registrations retrieved: $($results.Count)"

    return $results.ToArray()

    #endregion
}
