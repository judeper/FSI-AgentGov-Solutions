<#
.SYNOPSIS
    Retrieves Human-in-the-Loop checkpoint configuration for all Copilot
    Studio agents across Power Platform environments.

.DESCRIPTION
    Enumerates Power Platform environments, connects to each environment's
    Dataverse instance, queries the bot table for Copilot Studio agents,
    and scans flow definitions within bot components for references to the
    advancedapprovals connector — specifically the "Request for information"
    and "Run a multistage approval" actions.

    For each HITL checkpoint found, the script extracts: checkpoint type,
    checkpoint name, assigned reviewers, input count, and input types.
    Agents without any HITL checkpoints are also returned to enable gap
    analysis.

    This script operates at the flow level — one result per agent flow per
    environment. It queries bot and botcomponent tables to build a
    comprehensive picture of each agent's HITL posture.

.NOTES
    File: Get-AgentHitlSettings.ps1
    Version: 1.0.0
    Solution: HITL Workflow Governance (HWG)
    Controls: 2.12 (Supervision/FINRA Rule 3110), 2.17 (Multi-Agent Orchestration), 1.10 (Communication Compliance)
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

function Get-AgentHitlSettings {
    <#
    .SYNOPSIS
        Retrieves Human-in-the-Loop checkpoint configuration for all Copilot
        Studio agents across Power Platform environments.

    .DESCRIPTION
        Enumerates Power Platform environments, connects to each environment's
        Dataverse instance, queries the bot table for Copilot Studio agents,
        and scans flow definitions for advancedapprovals connector references
        including "Request for information" and "Run a multistage approval".

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
        . ./Get-AgentHitlSettings.ps1
        Get-AgentHitlSettings

        Retrieves HITL settings for all agents across all environments.

    .EXAMPLE
        . ./Get-AgentHitlSettings.ps1
        Get-AgentHitlSettings -ExcludeSandbox -ExcludeTrial -GracePeriodHours 24

        Retrieves settings excluding sandbox/trial environments and environments
        created within the last 24 hours.

    .EXAMPLE
        . ./Get-AgentHitlSettings.ps1
        Get-AgentHitlSettings -IncludeEnvironments "guid-1", "guid-2"

        Scans only the specified environments.

    .OUTPUTS
        PSCustomObject[] -- One object per agent flow with properties:
        EnvironmentGuid, EnvironmentName, Zone, AgentId, AgentName, FlowName,
        FlowId, CheckpointType, CheckpointName, AssignedReviewers, InputCount,
        HasHitlCheckpoint, AgentStatus, DataverseUrl, RetrievedAt
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

    . (Join-Path $privateRoot 'Test-ParameterValidation.ps1')

    Import-Module (Join-Path $privateRoot 'HWGClient.psm1') -Force

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

    function Get-BotHitlCheckpoints {
        <#
        .SYNOPSIS
            Extracts HITL checkpoint nodes from bot component flow definitions.
        .DESCRIPTION
            Queries botcomponent filtered by _botid_value for topic/flow definitions,
            parses content JSON for references to the advancedapprovals connector —
            specifically "Request for information" and "Run a multistage approval"
            action nodes. Extracts reviewer assignments, input counts, and titles.
        #>
        param(
            [Parameter(Mandatory)]
            [PSCustomObject]$Bot,

            [Parameter(Mandatory)]
            [string]$EnvDataverseUrl,

            [Parameter(Mandatory)]
            [string]$EnvToken
        )

        $checkpoints = [System.Collections.Generic.List[PSCustomObject]]::new()

        $baseUrl = $EnvDataverseUrl.TrimEnd('/')
        $headers = @{
            'Authorization'    = "Bearer $EnvToken"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }

        #region Query botcomponent for flow/topic definitions

        try {
            # componenttype 12 = Topic, componenttype 2 = Dialog/Skill
            $componentsUri = "$baseUrl/api/data/v9.2/botcomponents?" +
                "`$filter=_botid_value eq '$($Bot.botid)' and (componenttype eq 12 or componenttype eq 2)&" +
                "`$select=name,content,componenttype,botcomponentid"

            $componentsResponse = Invoke-RestMethod -Uri $componentsUri -Method Get -Headers $headers -ErrorAction Stop

            if ($componentsResponse.value) {
                foreach ($component in $componentsResponse.value) {
                    if (-not $component.content) { continue }

                    $flowName = $component.name
                    $flowId = $component.botcomponentid
                    $contentStr = $component.content

                    try {
                        $componentJson = $contentStr | ConvertFrom-Json -ErrorAction Stop
                    } catch {
                        Write-Verbose "Failed to parse botcomponent content for '$flowName' in bot '$($Bot.name)'"
                        continue
                    }

                    # Detect advancedapprovals connector references
                    # Pattern: "Request for information" action
                    $rfiMatches = [regex]::Matches(
                        $contentStr,
                        '(?i)"(?:actionName|name|operationId)"\s*:\s*"[^"]*(?:request\s+for\s+information|RequestForInformation)[^"]*"'
                    )

                    # Pattern: connector reference to advancedapprovals
                    $connectorMatches = [regex]::Matches(
                        $contentStr,
                        '(?i)"(?:connectorName|connectorId|connector)"\s*:\s*"[^"]*advancedapprovals[^"]*"'
                    )

                    # Pattern: "Run a multistage approval" action
                    $approvalMatches = [regex]::Matches(
                        $contentStr,
                        '(?i)"(?:actionName|name|operationId)"\s*:\s*"[^"]*(?:run\s+a?\s*multistage\s+approval|RunMultistageApproval|StartAndWaitForAnApprovalProcess|MultistageApproval)[^"]*"'
                    )

                    # Process RFI checkpoints
                    foreach ($match in $rfiMatches) {
                        $contextStart = [Math]::Max(0, $match.Index - 800)
                        $contextEnd = [Math]::Min($contentStr.Length, $match.Index + 1500)
                        $contextWindow = $contentStr.Substring($contextStart, $contextEnd - $contextStart)

                        $title = 'Request for Information'
                        $titleMatch = [regex]::Match($contextWindow, '(?i)"(?:title|displayName|subject)"\s*:\s*"([^"]+)"')
                        if ($titleMatch.Success) {
                            $title = $titleMatch.Groups[1].Value
                        }

                        $reviewers = @()
                        $reviewerMatch = [regex]::Match($contextWindow, '(?i)"(?:assignedTo|reviewers?|approvers?|recipients?)"\s*:\s*"([^"]+)"')
                        if ($reviewerMatch.Success) {
                            $reviewers = @($reviewerMatch.Groups[1].Value -split '[;,]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                        }

                        # Count input fields
                        $inputMatches = [regex]::Matches($contextWindow, '(?i)"(?:inputName|fieldName|parameterName)"\s*:\s*"([^"]+)"')
                        $inputCount = $inputMatches.Count

                        # Extract input types
                        $inputTypeMatches = [regex]::Matches($contextWindow, '(?i)"(?:inputType|fieldType|type)"\s*:\s*"([^"]+)"')
                        $inputTypes = @($inputTypeMatches | ForEach-Object { $_.Groups[1].Value })

                        $checkpoints.Add([PSCustomObject]@{
                            FlowName          = $flowName
                            FlowId            = $flowId
                            CheckpointType    = 'RequestForInformation'
                            CheckpointName    = $title
                            AssignedReviewers = $reviewers
                            InputCount        = $inputCount
                            InputTypes        = $inputTypes
                            HasHitlCheckpoint = $true
                        })
                    }

                    # Process multistage approval checkpoints
                    foreach ($match in $approvalMatches) {
                        $contextStart = [Math]::Max(0, $match.Index - 800)
                        $contextEnd = [Math]::Min($contentStr.Length, $match.Index + 1500)
                        $contextWindow = $contentStr.Substring($contextStart, $contextEnd - $contextStart)

                        $title = 'Run a Multistage Approval'
                        $titleMatch = [regex]::Match($contextWindow, '(?i)"(?:title|displayName|subject)"\s*:\s*"([^"]+)"')
                        if ($titleMatch.Success) {
                            $title = $titleMatch.Groups[1].Value
                        }

                        $reviewers = @()
                        $reviewerMatch = [regex]::Match($contextWindow, '(?i)"(?:assignedTo|reviewers?|approvers?|recipients?)"\s*:\s*"([^"]+)"')
                        if ($reviewerMatch.Success) {
                            $reviewers = @($reviewerMatch.Groups[1].Value -split '[;,]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
                        }

                        $inputCount = 0
                        $inputMatches = [regex]::Matches($contextWindow, '(?i)"(?:inputName|fieldName|parameterName)"\s*:\s*"([^"]+)"')
                        $inputCount = $inputMatches.Count

                        $inputTypes = @()
                        $inputTypeMatches = [regex]::Matches($contextWindow, '(?i)"(?:inputType|fieldType|type)"\s*:\s*"([^"]+)"')
                        $inputTypes = @($inputTypeMatches | ForEach-Object { $_.Groups[1].Value })

                        $checkpoints.Add([PSCustomObject]@{
                            FlowName          = $flowName
                            FlowId            = $flowId
                            CheckpointType    = 'MultistageApproval'
                            CheckpointName    = $title
                            AssignedReviewers = $reviewers
                            InputCount        = $inputCount
                            InputTypes        = $inputTypes
                            HasHitlCheckpoint = $true
                        })
                    }

                    # If connector reference found but no specific action matched,
                    # record a generic advancedapprovals reference
                    if ($connectorMatches.Count -gt 0 -and $rfiMatches.Count -eq 0 -and $approvalMatches.Count -eq 0) {
                        $checkpoints.Add([PSCustomObject]@{
                            FlowName          = $flowName
                            FlowId            = $flowId
                            CheckpointType    = 'AdvancedApprovalsGeneric'
                            CheckpointName    = 'Advanced Approvals Connector Reference'
                            AssignedReviewers = @()
                            InputCount        = 0
                            InputTypes        = @()
                            HasHitlCheckpoint = $true
                        })
                    }
                }
            }
        } catch {
            Write-Verbose "botcomponent query failed for $($Bot.name): $($_.Exception.Message)"
        }

        #endregion

        return $checkpoints.ToArray()
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

        $envDataverseUrl = $envDataverseUrl.TrimEnd('/')

        Write-Progress -Activity "Scanning environments for HITL checkpoint settings" `
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
            $hitlCheckpoints = Get-BotHitlCheckpoints -Bot $bot -EnvDataverseUrl $envDataverseUrl -EnvToken $envToken

            if ($hitlCheckpoints.Count -gt 0) {
                # One result per checkpoint found
                foreach ($cp in $hitlCheckpoints) {
                    $results.Add([PSCustomObject]@{
                        EnvironmentGuid    = $envId
                        EnvironmentName    = $envName
                        EnvironmentType    = $envType
                        Zone               = $zone
                        AgentId            = $bot.botid
                        AgentName          = $bot.name
                        FlowName           = $cp.FlowName
                        FlowId             = $cp.FlowId
                        CheckpointType     = $cp.CheckpointType
                        CheckpointName     = $cp.CheckpointName
                        AssignedReviewers  = $cp.AssignedReviewers
                        InputCount         = $cp.InputCount
                        InputTypes         = $cp.InputTypes
                        HasHitlCheckpoint  = $true
                        AgentStatus        = if ($bot.statecode -eq 0) { 'Active' } else { 'Inactive' }
                        DataverseUrl       = $envDataverseUrl
                        RetrievedAt        = (Get-Date).ToUniversalTime()
                    })
                }
            } else {
                # No HITL checkpoints — record the gap
                $results.Add([PSCustomObject]@{
                    EnvironmentGuid    = $envId
                    EnvironmentName    = $envName
                    EnvironmentType    = $envType
                    Zone               = $zone
                    AgentId            = $bot.botid
                    AgentName          = $bot.name
                    FlowName           = $null
                    FlowId             = $null
                    CheckpointType     = $null
                    CheckpointName     = $null
                    AssignedReviewers  = @()
                    InputCount         = 0
                    InputTypes         = @()
                    HasHitlCheckpoint  = $false
                    AgentStatus        = if ($bot.statecode -eq 0) { 'Active' } else { 'Inactive' }
                    DataverseUrl       = $envDataverseUrl
                    RetrievedAt        = (Get-Date).ToUniversalTime()
                })
            }

            # Check Top cap
            if ($Top -gt 0 -and $results.Count -ge $Top) {
                Write-Verbose "Top cap reached ($Top). Stopping enumeration."
                $topReached = $true
                break
            }
        }
    }

    # Complete progress bar
    Write-Progress -Activity "Scanning environments for HITL checkpoint settings" -Completed

    Write-Verbose "Total agent flow results retrieved: $($results.Count)"

    return $results.ToArray()

    #endregion
}
