<#
.SYNOPSIS
    Retrieves action invocation settings and confirmation status for all Copilot
    Studio agents across Power Platform environments.

.DESCRIPTION
    Enumerates Power Platform environments, connects to each environment's
    Dataverse instance, queries the bot table for Copilot Studio agents,
    and extracts action invocation details from topic definitions including
    connector calls, cloud flow calls, plugin invocations, HTTP requests,
    and whether each action has a preceding confirmation/approval pattern.

    This script operates at agent granularity -- one result per agent per
    environment. It queries bot and botcomponent tables to build a
    comprehensive picture of each agent's action confirmation posture.

.NOTES
    File: Get-AgentActionSettings.ps1
    Version: 1.2.1
    Solution: Action Confirmation Auditor (ACA)
    Control: 2.12 (Human-in-the-Loop checkpoints for AI agent actions); supports 1.10 (Communication Compliance / FINRA 3110 supervision)
#>

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

function Get-AgentActionSettings {
    <#
    .SYNOPSIS
        Retrieves action invocation settings and confirmation status for all Copilot
        Studio agents across Power Platform environments.

    .DESCRIPTION
        Enumerates Power Platform environments, connects to each environment's
        Dataverse instance, queries the bot table for Copilot Studio agents,
        and extracts action invocation details from bot component topic definitions.

        For each action invocation node found in a topic, this function determines
        whether a confirmation or approval pattern precedes the action in the
        conversation flow. Conservative parsing returns "Unable to Determine" for
        unrecognized structures.

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
        . ./Get-AgentActionSettings.ps1
        Get-AgentActionSettings

        Retrieves action settings for all agents across all environments.

    .EXAMPLE
        . ./Get-AgentActionSettings.ps1
        Get-AgentActionSettings -ExcludeSandbox -ExcludeTrial -GracePeriodHours 24

        Retrieves settings excluding sandbox and trial environments, and environments
        created within the last 24 hours.

    .EXAMPLE
        . ./Get-AgentActionSettings.ps1
        Get-AgentActionSettings -IncludeEnvironments "guid-1", "guid-2"

        Scans only the specified environments.

    .OUTPUTS
        PSCustomObject[] -- One object per agent with properties:
        EnvironmentId, EnvironmentDisplayName, EnvironmentType, Zone, AgentId,
        AgentName, Actions (array), TotalActions, ActionsWithConfirmation,
        ActionsMissingConfirmation, AgentStatus, DataverseUrl, LastPublished,
        RetrievedAt
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

    # Import ACAClient module (Get-AgentBots, Connect-ACADataverse, etc.)
    Import-Module (Join-Path $privateRoot 'ACAClient.psm1') -Force

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

    function Get-BotActionConfig {
        <#
        .SYNOPSIS
            Extracts action invocation nodes and confirmation status from bot topic definitions.
        .DESCRIPTION
            Queries botcomponent filtered by _parentbotid_value for topic definitions (componenttype 12),
            parses content (YAML or JSON) for action invocation nodes (connector calls, cloud flow calls,
            plugin invocations, HTTP requests), and checks for preceding confirmation/approval
            patterns. Conservative parsing returns 'Unable to Determine' for unrecognized structures.
        #>
        param(
            [Parameter(Mandatory)]
            [PSCustomObject]$Bot,

            [Parameter(Mandatory)]
            [string]$EnvDataverseUrl,

            [Parameter(Mandatory)]
            [string]$EnvToken
        )

        $actions = [System.Collections.Generic.List[PSCustomObject]]::new()

        # Fail-closed marker: set when a component's content is empty or unparseable so the agent
        # is never scored Compliant on content we could not actually read.
        $unassessableContentSeen = $false

        $baseUrl = $EnvDataverseUrl.TrimEnd('/')
        $headers = @{
            'Authorization'    = "Bearer $EnvToken"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }

        #region Query botcomponent for topic definitions

        try {
            # componenttype 12 = Topic, componenttype 2 = Dialog/Skill
            $componentsUri = "$baseUrl/api/data/v9.2/botcomponents?" +
                "`$filter=_parentbotid_value eq '$($Bot.botid)' and (componenttype eq 12 or componenttype eq 2)&" +
                "`$select=name,content,componenttype,botcomponentid"

            $componentsResponse = Invoke-RestMethod -Uri $componentsUri -Method Get -Headers $headers -ErrorAction Stop

            if ($componentsResponse.value) {
                foreach ($component in $componentsResponse.value) {
                    $topicName = $component.name
                    $topicId = $component.botcomponentid

                    # Empty content cannot be assessed for action/confirmation posture. Track it so
                    # the agent is never scored falsely Compliant on content we never actually saw.
                    if (-not $component.content) {
                        $unassessableContentSeen = $true
                        Write-Verbose "Empty botcomponent content for '$topicName' in bot '$($Bot.name)' -- cannot assess"
                        continue
                    }

                    $contentStr = $component.content

                    # Copilot Studio topics are authored as YAML; exported/legacy components may be
                    # JSON. Determine a parse format defensively. A failed parse must NOT silently
                    # skip the component (that reads as Compliant); it is flagged Indeterminate below.
                    $contentFormat = 'Unparseable'
                    try {
                        $contentStr | ConvertFrom-Json -ErrorAction Stop | Out-Null
                        $contentFormat = 'Json'
                    } catch {
                        if (Get-Command ConvertFrom-Yaml -ErrorAction SilentlyContinue) {
                            try {
                                $contentStr | ConvertFrom-Yaml -ErrorAction Stop | Out-Null
                                $contentFormat = 'Yaml'
                            } catch {
                                $contentFormat = 'Unparseable'
                            }
                        }
                    }

                    # Detect action invocation nodes. Patterns match BOTH JSON ("kind": "X") and
                    # YAML (kind: X) node shapes so real YAML topics are not silently skipped.
                    $actionNodes = @()
                    $kindMap = [ordered]@{
                        'InvokeFlowAction'      = 'CloudFlowAction'
                        'InvokeConnectorAction' = 'ConnectorAction'
                        'InvokeSkillAction'     = 'PluginAction'
                        'HttpRequest'           = 'HttpRequest'
                        'InvokePlugin'          = 'PluginAction'
                        'InvokeCustomAction'    = 'CustomAction'
                    }
                    foreach ($kind in $kindMap.Keys) {
                        $kindPattern = '["'']?kind["'']?\s*:\s*["'']?' + [regex]::Escape($kind) + '\b'
                        foreach ($match in [regex]::Matches($contentStr, $kindPattern)) {
                            $actionNodes += @{ Kind = $kind; ActionType = $kindMap[$kind]; Position = $match.Index }
                        }
                    }

                    # Non-empty content that no parser could read AND that exposes no recognizable
                    # action node is genuinely indeterminate. Skip scoring it as an action but record
                    # that we saw unassessable content so the agent fails closed (never Compliant by
                    # omission) via the marker emitted after the component loop.
                    if ($contentFormat -eq 'Unparseable' -and $actionNodes.Count -eq 0) {
                        $unassessableContentSeen = $true
                        Write-Verbose "Unparseable botcomponent content for '$topicName' in bot '$($Bot.name)' -- marking Indeterminate"
                        continue
                    }

                    # For each action node, determine action name, connector, HTTP method, confirmation status
                    foreach ($actionNode in $actionNodes) {
                        $actionName = 'Unknown'
                        $connectorName = $null
                        $httpMethod = $null
        $confirmationStatus = 'UnableToDetermine'

                        # Try to extract action name from nearby JSON/YAML context
                        # Look backwards from the action position for a name field
                        $contextStart = [Math]::Max(0, $actionNode.Position - 500)
                        $contextEnd = [Math]::Min($contentStr.Length, $actionNode.Position + 1000)
                        $contextWindow = $contentStr.Substring($contextStart, $contextEnd - $contextStart)

                        # Extract action/flow name (JSON "name": "X" or YAML name: X)
                        $nameMatch = [regex]::Match($contextWindow, '["'']?(?:actionName|flowName|skillName|pluginName|name)["'']?\s*:\s*["'']?([^"''\r\n,}]+)')
                        if ($nameMatch.Success) {
                            $actionName = $nameMatch.Groups[1].Value.Trim()
                        }

                        # Extract connector name for connector actions
                        if ($actionNode.ActionType -eq 'ConnectorAction') {
                            $connMatch = [regex]::Match($contextWindow, '["'']?(?:connectorName|connectorId|connector)["'']?\s*:\s*["'']?([^"''\r\n,}]+)')
                            if ($connMatch.Success) {
                                $connectorName = $connMatch.Groups[1].Value.Trim()
                            }
                        }

                        # Extract HTTP method for HTTP requests
                        if ($actionNode.ActionType -eq 'HttpRequest') {
                            $methodMatch = [regex]::Match($contextWindow, '["'']?(?:method|httpMethod)["'']?\s*:\s*["'']?([^"''\r\n,}]+)')
                            if ($methodMatch.Success) {
                                $httpMethod = $methodMatch.Groups[1].Value.Trim().ToUpper()
                            }
                        }

                        # Check for confirmation/approval patterns BEFORE the action node
                        # Look for confirmation patterns in the preceding 2000 characters.
                        # Node patterns match both JSON ("kind": "X") and YAML (kind: X) shapes.
                        $lookbackStart = [Math]::Max(0, $actionNode.Position - 2000)
                        $precedingWindow = $contentStr.Substring($lookbackStart, $actionNode.Position - $lookbackStart)

                        # Confirmation pattern: Question or Message nodes with confirm/approve text
                        $hasQuestionConfirm = $precedingWindow -match '["'']?kind["'']?\s*:\s*["'']?Question\b' -and
                            ($precedingWindow -match '(?i)(confirm|approve|proceed|are you sure|do you want|shall I|would you like|verify|authorization)')

                        $hasMessageConfirm = $precedingWindow -match '["'']?kind["'']?\s*:\s*["'']?Message\b' -and
                            ($precedingWindow -match '(?i)(confirm|approve|proceed|are you sure|do you want|shall I|would you like|verify|authorization)')

                        # Confirmation pattern: Condition branches (yes/no branching)
                        $hasConditionBranch = $precedingWindow -match '["'']?kind["'']?\s*:\s*["'']?ConditionBranch\b' -and
                            ($precedingWindow -match '(?i)(confirm|approve|yes|proceed)')

                        # Confirmation pattern: Approval action nodes
                        $hasApprovalAction = $precedingWindow -match '(?i)["'']?kind["'']?\s*:\s*["'']?(StartApproval|WaitForApproval|ApprovalAction)\b'

                        # Confirmation pattern: Adaptive Card with submit action (common confirmation UI)
                        $hasAdaptiveCardConfirm = $precedingWindow -match '["'']?kind["'']?\s*:\s*["'']?SendAdaptiveCard\b' -and
                            ($precedingWindow -match '(?i)(confirm|approve|submit|Action\.Submit)')

                        if ($hasQuestionConfirm -or $hasApprovalAction -or $hasAdaptiveCardConfirm) {
                            $confirmationStatus = 'Present'
                        } elseif ($hasMessageConfirm -or $hasConditionBranch) {
                            $confirmationStatus = 'Partial'
                        } else {
                            # Check if the action is the very first node (no preceding nodes at all)
                            $hasPrecedingNodes = $precedingWindow -match '["'']?kind["'']?\s*:\s*["'']?(Question|Message|ConditionBranch|SendAdaptiveCard)\b'
                            if (-not $hasPrecedingNodes) {
                                # No recognizable preceding conversation nodes -- likely auto-triggered
                                $confirmationStatus = 'Missing'
                            } else {
                                # There are preceding nodes but none match confirmation patterns
                                $confirmationStatus = 'Missing'
                            }
                        }

                        $actions.Add([PSCustomObject]@{
                            ActionName         = $actionName
                            ActionType         = $actionNode.ActionType
                            ConnectorName      = $connectorName
                            HttpMethod         = $httpMethod
                            ConfirmationStatus = $confirmationStatus
                            TopicName          = $topicName
                            TopicId            = $topicId
                        })
                    }
                }
            }
        } catch {
            Write-Verbose "botcomponent query failed for $($Bot.name): $($_.Exception.Message)"
            # A failed component query means we could not read this agent's topics at all.
            $unassessableContentSeen = $true
        }

        # Fail-closed: if we saw content we could not assess (empty, unparseable, or a failed
        # query) and detected no actions at all, surface a single Indeterminate marker so the
        # agent is never scored Compliant by omission. Real YAML detection is best-effort; this
        # guarantees unseen content reads as UnableToDetermine, not as silent compliance.
        if ($actions.Count -eq 0 -and $unassessableContentSeen) {
            $actions.Add([PSCustomObject]@{
                ActionName         = 'IndeterminateContent'
                ActionType         = 'Unknown'
                ConnectorName      = $null
                HttpMethod         = $null
                ConfirmationStatus = 'UnableToDetermine'
                TopicName          = '(unparseable or empty topic content)'
                TopicId            = $null
            })
        }

        #endregion

        return $actions.ToArray()
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
        Write-Progress -Activity "Scanning environments for agent action settings" `
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
            # Extract action configuration from bot topic definitions
            $actionList = Get-BotActionConfig -Bot $bot -EnvDataverseUrl $envDataverseUrl -EnvToken $envToken

            # Calculate confirmation statistics
            $totalActions = $actionList.Count
            $withConfirmation = @($actionList | Where-Object { $_.ConfirmationStatus -eq 'Present' }).Count
            $missingConfirmation = @($actionList | Where-Object { $_.ConfirmationStatus -ne 'Present' }).Count

            # Build result object
            $agentResult = [PSCustomObject]@{
                EnvironmentId              = $envId
                EnvironmentDisplayName     = $envName
                EnvironmentType            = $envType
                Zone                       = $zone
                AgentId                    = $bot.botid
                AgentName                  = $bot.name
                Actions                    = $actionList
                TotalActions               = $totalActions
                ActionsWithConfirmation    = $withConfirmation
                ActionsMissingConfirmation = $missingConfirmation
                AgentStatus                = if ($bot.statecode -eq 0) { 'Active' } else { 'Inactive' }
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
    Write-Progress -Activity "Scanning environments for agent action settings" -Completed

    Write-Verbose "Total agents retrieved: $($results.Count)"

    return $results.ToArray()

    #endregion
}
