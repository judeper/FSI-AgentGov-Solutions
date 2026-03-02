<#
.SYNOPSIS
    Retrieves generative AI configuration settings for all Copilot Studio agents
    across Power Platform environments.

.DESCRIPTION
    Enumerates Power Platform environments, connects to each environment's
    Dataverse instance, queries the bot table for Copilot Studio agents,
    and extracts generative AI configuration details including Azure OpenAI
    enablement, orchestration mode, knowledge sources, and generative answers
    node usage from bot component definitions.

    This script operates at agent granularity -- one result per agent per
    environment. It queries bot, bot_botsetting, and botcomponent tables
    to build a comprehensive picture of each agent's generative AI posture.

.NOTES
    File: Get-AgentGenAISettings.ps1
    Version: 1.0.0
    Solution: Generative AI Config Auditor (GAC)
    Control: 2.24 (Agent Feature Enablement Governance)
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

function Get-AgentGenAISettings {
    <#
    .SYNOPSIS
        Retrieves generative AI configuration settings for all Copilot Studio agents
        across Power Platform environments.

    .DESCRIPTION
        Enumerates Power Platform environments, connects to each environment's
        Dataverse instance, queries the bot table for Copilot Studio agents,
        and extracts generative AI configuration details including Azure OpenAI
        enablement, orchestration mode, knowledge sources, and generative answers
        node usage from bot component definitions.

        This script operates at agent granularity -- one result per agent per
        environment. It queries bot, bot_botsetting (if available) for AOAI toggle
        and orchestration mode, then botcomponent for topic definitions to detect
        generative answers nodes in topic content JSON.

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
        . ./Get-AgentGenAISettings.ps1
        Get-AgentGenAISettings

        Retrieves generative AI settings for all agents across all environments.

    .EXAMPLE
        . ./Get-AgentGenAISettings.ps1
        Get-AgentGenAISettings -ExcludeSandbox -ExcludeTrial -GracePeriodHours 24

        Retrieves settings excluding sandbox and trial environments, and environments
        created within the last 24 hours.

    .EXAMPLE
        . ./Get-AgentGenAISettings.ps1
        Get-AgentGenAISettings -IncludeEnvironments "guid-1", "guid-2"

        Scans only the specified environments.

    .EXAMPLE
        . ./Get-AgentGenAISettings.ps1
        . ./Compare-GenAIConfigCompliance.ps1
        Get-AgentGenAISettings -ExcludeSandbox | Compare-GenAIConfigCompliance

        Retrieves generative AI settings and pipes to compliance comparison.

    .EXAMPLE
        . ./Get-AgentGenAISettings.ps1
        Get-AgentGenAISettings -IncludeDrafts -Top 100

        Retrieves settings including draft agents, capped at 100 results.

    .OUTPUTS
        PSCustomObject[] -- One object per agent with properties:
        EnvironmentId, EnvironmentDisplayName, Zone, AgentId, AgentName,
        AzureOpenAIEnabled, OrchestrationMode, KnowledgeSourceCount,
        GenerativeAnswersNodeCount, AoaiConnectionId, ModelKnowledgeEnabled,
        SemanticSearchEnabled, AgentStatus, TopicSummary
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

    # Import GACClient module (Get-AgentBots, etc.)
    Import-Module (Join-Path $privateRoot 'GACClient.psm1') -Force

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

    function Get-BotGenAIConfig {
        <#
        .SYNOPSIS
            Extracts generative AI configuration from bot settings and components.
        .DESCRIPTION
            Queries bot_botsetting for AOAI toggle and orchestration mode, then
            queries botcomponent filtered by _botid_value to find generative answers
            nodes in topic content JSON. Conservative parsing returns 'Unable to Determine'
            for unknown structures.
        #>
        param(
            [Parameter(Mandatory)]
            [PSCustomObject]$Bot,

            [Parameter(Mandatory)]
            [string]$EnvDataverseUrl,

            [Parameter(Mandatory)]
            [string]$EnvToken
        )

        $config = [PSCustomObject]@{
            AzureOpenAIEnabled          = 'Unable to Determine'
            OrchestrationMode           = 'Unable to Determine'
            KnowledgeSourceCount        = 0
            GenerativeAnswersNodeCount  = 0
            AoaiConnectionId            = $null
            ModelKnowledgeEnabled       = 'Unable to Determine'
            SemanticSearchEnabled       = 'Unable to Determine'
            TopicSummary                = ''
        }

        $baseUrl = $EnvDataverseUrl.TrimEnd('/')
        $headers = @{
            'Authorization'    = "Bearer $EnvToken"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }

        #region Query bot_botsetting for AOAI toggle and orchestration mode

        try {
            $settingsUri = "$baseUrl/api/data/v9.2/bot_botsettings?" +
                "`$filter=_botid_value eq '$($Bot.botid)'&" +
                "`$select=fsi_aoaienabled,fsi_orchestrationmode,fsi_aoaiconnectionid,fsi_modelknowledgeenabled,fsi_semanticsearchenabled"

            $settingsResponse = Invoke-RestMethod -Uri $settingsUri -Method Get -Headers $headers -ErrorAction Stop

            if ($settingsResponse.value -and $settingsResponse.value.Count -gt 0) {
                $setting = $settingsResponse.value[0]

                # Parse AOAI enabled flag
                if ($null -ne $setting.fsi_aoaienabled) {
                    $config.AzureOpenAIEnabled = if ($setting.fsi_aoaienabled) { 'Yes' } else { 'No' }
                }

                # Parse orchestration mode
                if ($setting.fsi_orchestrationmode) {
                    $config.OrchestrationMode = $setting.fsi_orchestrationmode
                }

                # Parse AOAI connection ID
                if ($setting.fsi_aoaiconnectionid) {
                    $config.AoaiConnectionId = $setting.fsi_aoaiconnectionid
                }

                # Parse Model Knowledge enabled flag
                if ($null -ne $setting.fsi_modelknowledgeenabled) {
                    $config.ModelKnowledgeEnabled = if ($setting.fsi_modelknowledgeenabled) { 'Yes' } else { 'No' }
                }

                # Parse Semantic Search enabled flag
                if ($null -ne $setting.fsi_semanticsearchenabled) {
                    $config.SemanticSearchEnabled = if ($setting.fsi_semanticsearchenabled) { 'Yes' } else { 'No' }
                }
            }
        } catch {
            # bot_botsetting may not exist in all environments -- fall back gracefully
            Write-Verbose "bot_botsetting query failed for $($Bot.name): $($_.Exception.Message)"
        }

        #endregion

        #region Try extracting from bot.configuration JSON (fallback)

        if ($config.AzureOpenAIEnabled -eq 'Unable to Determine' -and $Bot.configuration) {
            try {
                $botConfig = $Bot.configuration | ConvertFrom-Json -ErrorAction Stop

                foreach ($key in @('AzureOpenAIEnabled', 'azureOpenAIEnabled', 'UseAzureOpenAI', 'useAzureOpenAI')) {
                    if ($botConfig.PSObject.Properties.Name -contains $key) {
                        $rawValue = $botConfig.$key
                        if ($rawValue -is [bool]) {
                            $config.AzureOpenAIEnabled = if ($rawValue) { 'Yes' } else { 'No' }
                        } elseif ($rawValue -is [string]) {
                            $config.AzureOpenAIEnabled = if ($rawValue -eq 'true') { 'Yes' } else { 'No' }
                        }
                        break
                    }
                }

                foreach ($key in @('OrchestrationMode', 'orchestrationMode', 'Orchestration')) {
                    if ($botConfig.PSObject.Properties.Name -contains $key) {
                        $rawValue = $botConfig.$key
                        if ($rawValue -is [string]) {
                            $config.OrchestrationMode = $rawValue
                        } elseif ($rawValue -is [PSCustomObject] -and $rawValue.PSObject.Properties.Name -contains 'mode') {
                            $config.OrchestrationMode = $rawValue.mode
                        }
                        break
                    }
                }

                # Fallback: Model Knowledge toggle
                if ($config.ModelKnowledgeEnabled -eq 'Unable to Determine') {
                    foreach ($key in @('ModelKnowledge', 'modelKnowledge', 'UseModelKnowledge', 'useModelKnowledge', 'AllowAIKnowledge', 'allowAIKnowledge')) {
                        if ($botConfig.PSObject.Properties.Name -contains $key) {
                            $rawValue = $botConfig.$key
                            if ($rawValue -is [bool]) {
                                $config.ModelKnowledgeEnabled = if ($rawValue) { 'Yes' } else { 'No' }
                            } elseif ($rawValue -is [string]) {
                                $config.ModelKnowledgeEnabled = if ($rawValue -eq 'true') { 'Yes' } else { 'No' }
                            }
                            break
                        }
                    }
                }

                # Fallback: Semantic Search toggle
                if ($config.SemanticSearchEnabled -eq 'Unable to Determine') {
                    foreach ($key in @('SemanticSearch', 'semanticSearch', 'UseSemanticSearch', 'useSemanticSearch', 'DataverseSearch', 'dataverseSearch')) {
                        if ($botConfig.PSObject.Properties.Name -contains $key) {
                            $rawValue = $botConfig.$key
                            if ($rawValue -is [bool]) {
                                $config.SemanticSearchEnabled = if ($rawValue) { 'Yes' } else { 'No' }
                            } elseif ($rawValue -is [string]) {
                                $config.SemanticSearchEnabled = if ($rawValue -eq 'true') { 'Yes' } else { 'No' }
                            }
                            break
                        }
                    }
                }
            } catch {
                Write-Verbose "Failed to parse bot configuration JSON for $($Bot.name): $($_.Exception.Message)"
            }
        }

        #endregion

        #region Query botcomponent for topic definitions

        try {
            # Filter botcomponents by _botid_value and componenttype for topics
            # componenttype 12 = Topic, componenttype 2 = Dialog/Skill
            $componentsUri = "$baseUrl/api/data/v9.2/botcomponents?" +
                "`$filter=_botid_value eq '$($Bot.botid)' and (componenttype eq 12 or componenttype eq 2)&" +
                "`$select=name,content,componenttype"

            $componentsResponse = Invoke-RestMethod -Uri $componentsUri -Method Get -Headers $headers -ErrorAction Stop

            $topicNames = @()
            $genAnswersCount = 0
            $knowledgeSourceCount = 0

            if ($componentsResponse.value) {
                foreach ($component in $componentsResponse.value) {
                    if ($component.name) {
                        $topicNames += $component.name
                    }

                    # Parse component content JSON for generative features
                    if ($component.content) {
                        try {
                            $componentJson = $component.content | ConvertFrom-Json -ErrorAction Stop

                            # Look for generative answers nodes in the component
                            $contentStr = $component.content

                            # Detect generative answers node patterns
                            if ($contentStr -match '"kind"\s*:\s*"GenerativeAnswers"' -or
                                $contentStr -match '"kind"\s*:\s*"SearchAndSummarize"' -or
                                $contentStr -match '"GenerativeAnswer"' -or
                                $contentStr -match '"generativeAnswers"') {
                                $genAnswersCount++
                            }

                            # Detect knowledge source references
                            if ($contentStr -match '"kind"\s*:\s*"KnowledgeSource"' -or
                                $contentStr -match '"dataSource"' -or
                                $contentStr -match '"knowledgeSources"') {

                                # Try to count individual knowledge sources
                                if ($componentJson.PSObject.Properties.Name -contains 'knowledgeSources') {
                                    $knowledgeSourceCount += @($componentJson.knowledgeSources).Count
                                } else {
                                    $knowledgeSourceCount++
                                }
                            }
                        } catch {
                            Write-Verbose "Failed to parse botcomponent content for '$($component.name)' in bot '$($Bot.name)'"
                        }
                    }
                }
            }

            $config.GenerativeAnswersNodeCount = $genAnswersCount
            $config.KnowledgeSourceCount = $knowledgeSourceCount
            $config.TopicSummary = ($topicNames | Select-Object -First 10) -join '; '

            if ($topicNames.Count -gt 10) {
                $config.TopicSummary += " (+$($topicNames.Count - 10) more)"
            }
        } catch {
            Write-Verbose "botcomponent query failed for $($Bot.name): $($_.Exception.Message)"
        }

        #endregion

        return $config
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
        Write-Progress -Activity "Scanning environments for agent GenAI settings" `
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
            # Extract generative AI configuration
            $genAIConfig = Get-BotGenAIConfig -Bot $bot -EnvDataverseUrl $envDataverseUrl -EnvToken $envToken

            # Build result object
            $agentResult = [PSCustomObject]@{
                EnvironmentId              = $envId
                EnvironmentDisplayName     = $envName
                EnvironmentType            = $envType
                Zone                       = $zone
                AgentId                    = $bot.botid
                AgentName                  = $bot.name
                AzureOpenAIEnabled         = $genAIConfig.AzureOpenAIEnabled
                OrchestrationMode          = $genAIConfig.OrchestrationMode
                KnowledgeSourceCount       = $genAIConfig.KnowledgeSourceCount
                GenerativeAnswersNodeCount = $genAIConfig.GenerativeAnswersNodeCount
                AoaiConnectionId           = $genAIConfig.AoaiConnectionId
                ModelKnowledgeEnabled      = $genAIConfig.ModelKnowledgeEnabled
                SemanticSearchEnabled      = $genAIConfig.SemanticSearchEnabled
                AgentStatus                = if ($bot.statecode -eq 0) { 'Active' } else { 'Inactive' }
                TopicSummary               = $genAIConfig.TopicSummary
                DataverseUrl               = $envDataverseUrl
                LastPublished              = $bot.publishedon
                RetrievedAt                = (Get-Date).ToUniversalTime()
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
    Write-Progress -Activity "Scanning environments for agent GenAI settings" -Completed

    Write-Verbose "Total agents retrieved: $($results.Count)"

    return $results.ToArray()

    #endregion
}
