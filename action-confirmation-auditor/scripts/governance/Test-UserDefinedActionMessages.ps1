<#
.SYNOPSIS
    Validates that Copilot Studio agents have user-defined action messages
    configured per zone governance requirements.

.DESCRIPTION
    Scans Power Platform environments for Copilot Studio agents and checks
    whether each agent has user-defined action messages enabled. This setting
    controls whether custom messages are displayed to users before an agent
    performs an action, supporting human-in-the-loop confirmation workflows.

    Zone-based policy enforcement:
    - Zone 3 (Enterprise/Regulated): User-defined action messages required
    - Zone 2 (Team/Collaborative): User-defined action messages recommended
    - Zone 1 (Personal Productivity): User-defined action messages optional (advisory)

    Results are exported as evidence-compatible JSON or console output. Violations
    are classified by severity based on zone assignment and written to Dataverse
    when -PersistResults is specified.

    This script supports compliance with FINRA 3110, GLBA 501(b), and SOX 404
    by providing auditable evidence that agent action messages include
    appropriate user-facing disclosures before execution.

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
    Include draft/unpublished agents. By default, only published (active) agents are scanned.

.PARAMETER DataverseUrl
    ELM Dataverse URL for zone classification lookup. If not provided, zone classification
    falls back to environment naming convention.

.PARAMETER OutputFormat
    Output format: Table (default), Json, or Object.

.PARAMETER PersistResults
    When specified with -DataverseUrl, writes violations to fsi_actionauditresults.

.PARAMETER WhatIf
    Preview mode -- shows what violations would be reported without persisting.

.EXAMPLE
    . .\Test-UserDefinedActionMessages.ps1
    Test-UserDefinedActionMessages -WhatIf

    Dry-run scan of all environments for user-defined action message compliance.

.EXAMPLE
    . .\Test-UserDefinedActionMessages.ps1
    Test-UserDefinedActionMessages -IncludeEnvironments @("env-id-1") -OutputFormat Json

    Scan specific environments with JSON output for evidence pipeline.

.OUTPUTS
    PSCustomObject[] -- One object per agent with properties:
    EnvironmentId, EnvironmentDisplayName, Zone, AgentId, AgentName,
    HasUserDefinedActionMessages, PolicyRequirement, IsCompliant, Severity,
    ViolationType, RetrievedAt

.NOTES
    File: Test-UserDefinedActionMessages.ps1
    Version: 1.0.2
    Solution: Action Confirmation Auditor (ACA)
    Control: 1.23 (Step-Up Authentication for Agent Operations)
    Regulations: FINRA 3110, GLBA 501(b), SOX 404
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

function Test-UserDefinedActionMessages {
    <#
    .SYNOPSIS
        Validates user-defined action message configuration for Copilot Studio agents
        against zone-specific governance requirements.

    .DESCRIPTION
        Enumerates Power Platform environments, queries bot and botcomponent tables,
        and checks whether each agent has user-defined action messages configured.
        Applies zone-based policies and reports violations with severity classification.

    .PARAMETER IncludeEnvironments
        Limit scan to specific environment IDs.

    .PARAMETER ExcludeEnvironments
        Exclude specific environment IDs from scan.

    .PARAMETER ExcludeSandbox
        Exclude sandbox environments from scan.

    .PARAMETER ExcludeTrial
        Exclude trial environments from scan.

    .PARAMETER ExcludeDefault
        Exclude the default environment from scan.

    .PARAMETER GracePeriodHours
        Exclude environments created within this many hours (default: 48).

    .PARAMETER IncludeDrafts
        Include draft/unpublished agents (default: published only).

    .PARAMETER DataverseUrl
        ELM Dataverse URL for zone classification lookup.

    .PARAMETER OutputFormat
        Output format: Table (default), Json, or Object.

    .PARAMETER PersistResults
        Write violations to Dataverse when specified with -DataverseUrl.

    .OUTPUTS
        Formatted table, JSON string, or PSCustomObject[] depending on -OutputFormat.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter()]
        [ValidateSet('Table', 'Json', 'Object')]
        [string]$OutputFormat = 'Table',

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
        [switch]$PersistResults
    )

    #region Script Initialization

    $ErrorActionPreference = 'Stop'
    $scriptRoot = Split-Path -Parent $PSScriptRoot  # scripts/ directory
    $privateRoot = Join-Path $scriptRoot 'private'
    $runId = [guid]::NewGuid().ToString()

    Write-Verbose "========================================="
    Write-Verbose "User-Defined Action Messages Validator"
    Write-Verbose "RunId: $runId"
    Write-Verbose "========================================="

    #endregion

    #region Import Private Helpers

    . (Join-Path $privateRoot 'Test-ParameterValidation.ps1')

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

    #region Zone Policy Definition

    $zonePolicies = @{
        'Zone3' = [PSCustomObject]@{
            Zone              = 'Zone3'
            Requirement       = 'Required'
            Severity          = 'Critical'
            RegulatoryContext  = 'Zone 3 (Enterprise/Regulated) - User-defined action messages required for all agents per FINRA 3110 supervisory requirements'
        }
        'Zone2' = [PSCustomObject]@{
            Zone              = 'Zone2'
            Requirement       = 'Recommended'
            Severity          = 'Medium'
            RegulatoryContext  = 'Zone 2 (Team/Collaborative) - User-defined action messages recommended to support GLBA 501(b) safeguards'
        }
        'Zone1' = [PSCustomObject]@{
            Zone              = 'Zone1'
            Requirement       = 'Optional'
            Severity          = 'Low'
            RegulatoryContext  = 'Zone 1 (Personal Productivity) - User-defined action messages optional, advisory monitoring only'
        }
        'Unknown' = [PSCustomObject]@{
            Zone              = 'Unknown'
            Requirement       = 'Optional'
            Severity          = 'Warning'
            RegulatoryContext  = 'Unclassified environment - Zone classification required before policy enforcement'
        }
    }

    #endregion

    #region Environment Filter Helper

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

        if ($FilterConfig.FilterMode -eq 'Include') {
            foreach ($include in $FilterConfig.IncludeEnvironments) {
                if ($envId -eq $include -or $envName -like "*$include*") {
                    return $true
                }
            }
            return $false
        }

        if ($FilterConfig.FilterMode -eq 'Exclude') {
            foreach ($exclude in $FilterConfig.ExcludeEnvironments) {
                if ($envId -eq $exclude -or $envName -like "*$exclude*") {
                    Write-Verbose "Excluding environment by explicit filter: $envName"
                    return $false
                }
            }
        }

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

        if ($FilterConfig.GraceCutoff -and $createdTime -gt $FilterConfig.GraceCutoff) {
            Write-Verbose "Excluding environment within grace period: $envName (created: $createdTime)"
            return $false
        }

        return $true
    }

    #endregion

    #region Bot Action Message Detection

    function Test-BotHasUserDefinedActionMessages {
        <#
        .SYNOPSIS
            Checks whether a bot has user-defined action messages configured
            by inspecting botcomponent settings.
        #>
        param(
            [Parameter(Mandatory)]
            [PSCustomObject]$Bot,

            [Parameter(Mandatory)]
            [string]$EnvDataverseUrl,

            [Parameter(Mandatory)]
            [string]$EnvToken
        )

        $baseUrl = $EnvDataverseUrl.TrimEnd('/')
        $headers = @{
            'Authorization'    = "Bearer $EnvToken"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }

        try {
            # Query botcomponent for action-related components (componenttype 12 = Topic, 2 = Dialog/Skill)
            $componentsUri = "$baseUrl/api/data/v9.2/botcomponents?" +
                "`$filter=_botid_value eq '$($Bot.botid)' and (componenttype eq 12 or componenttype eq 2)&" +
                "`$select=name,content,componenttype,botcomponentid"

            $componentsResponse = Invoke-RestMethod -Uri $componentsUri -Method Get -Headers $headers -ErrorAction Stop

            if (-not $componentsResponse.value -or $componentsResponse.value.Count -eq 0) {
                return [PSCustomObject]@{
                    HasUserDefinedActionMessages = $false
                    ActionComponentCount         = 0
                    ComponentsWithMessages       = 0
                    Details                      = 'No action components found'
                }
            }

            $actionComponentCount = 0
            $componentsWithMessages = 0

            foreach ($component in $componentsResponse.value) {
                if (-not $component.content) { continue }

                $contentStr = $component.content

                # Detect action invocation nodes
                $hasActions = $contentStr -match '"kind"\s*:\s*"(InvokeFlowAction|InvokeConnectorAction|InvokeSkillAction|HttpRequest|InvokePlugin|InvokeCustomAction)"'

                if (-not $hasActions) { continue }

                $actionComponentCount++

                # Check for user-defined action message patterns:
                # 1. Custom message text before action execution
                # 2. UserDefinedActionMessage configuration in bot settings
                # 3. ActionConfirmationMessage or DisplayMessage nodes preceding actions
                $hasUserMessage = (
                    ($contentStr -match '"kind"\s*:\s*"Message"' -and
                     $contentStr -match '(?i)(before\s+(executing|running|performing)|about\s+to|will\s+now|action\s+message|user[\-\s]?defined[\-\s]?action)') -or
                    ($contentStr -match '(?i)"userdefinedactionmessage"') -or
                    ($contentStr -match '(?i)"actionconfirmationmessage"') -or
                    ($contentStr -match '(?i)"displaymessagebeforeaction"')
                )

                if ($hasUserMessage) {
                    $componentsWithMessages++
                }
            }

            # Agent has user-defined action messages if all action components include them
            $hasMessages = ($actionComponentCount -gt 0 -and $componentsWithMessages -eq $actionComponentCount)

            return [PSCustomObject]@{
                HasUserDefinedActionMessages = $hasMessages
                ActionComponentCount         = $actionComponentCount
                ComponentsWithMessages       = $componentsWithMessages
                Details                      = if ($actionComponentCount -eq 0) {
                                                   'No action invocation components found'
                                               } elseif ($hasMessages) {
                                                   "All $actionComponentCount action component(s) have user-defined messages"
                                               } else {
                                                   "$componentsWithMessages of $actionComponentCount action component(s) have user-defined messages"
                                               }
            }
        } catch {
            Write-Verbose "botcomponent query failed for $($Bot.name): $($_.Exception.Message)"
            return [PSCustomObject]@{
                HasUserDefinedActionMessages = $false
                ActionComponentCount         = 0
                ComponentsWithMessages       = 0
                Details                      = "Query failed: $($_.Exception.Message)"
            }
        }
    }

    #endregion

    #region Main Logic

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

    # Filter to environments with Dataverse instances
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

    # Acquire ELM token for zone classification
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

    foreach ($env in $dvEnvironments) {
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

        Write-Progress -Activity "Scanning environments for user-defined action messages" `
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

        # Query agents (bots)
        Write-Verbose "Querying agents from: $envName"
        $bots = Get-AgentBots -DataverseUrl $envDataverseUrl -AccessToken $envToken -IncludeDrafts:$IncludeDrafts

        if (-not $bots -or $bots.Count -eq 0) {
            Write-Verbose "No agents found in environment: $envName"
            continue
        }

        Write-Verbose "Found $($bots.Count) agent(s) in: $envName"

        # Get zone classification
        $zone = & (Join-Path $privateRoot 'Get-ZoneClassification.ps1') `
            -EnvironmentId $envId `
            -EnvironmentDisplayName $envName `
            -DataverseUrl $DataverseUrl `
            -AccessToken $elmToken

        Write-Verbose "Zone classification for ${envName}: $zone"

        $policy = $zonePolicies[$zone]
        if (-not $policy) { $policy = $zonePolicies['Unknown'] }

        # Process each agent
        foreach ($bot in $bots) {
            $messageCheck = Test-BotHasUserDefinedActionMessages `
                -Bot $bot `
                -EnvDataverseUrl $envDataverseUrl `
                -EnvToken $envToken

            # Determine compliance
            $isCompliant = switch ($policy.Requirement) {
                'Required'    { $messageCheck.HasUserDefinedActionMessages }
                'Recommended' { $true }  # Recommended = non-blocking
                'Optional'    { $true }  # Optional = always compliant
                default       { $true }
            }

            $violationType = if (-not $messageCheck.HasUserDefinedActionMessages -and $policy.Requirement -eq 'Required') {
                'MissingUserDefinedActionMessage'
            } elseif (-not $messageCheck.HasUserDefinedActionMessages -and $policy.Requirement -eq 'Recommended') {
                'MissingUserDefinedActionMessage'
            } else {
                $null
            }

            $severity = if ($violationType) { $policy.Severity } else { 'Passed' }

            $agentResult = [PSCustomObject]@{
                EnvironmentId                  = $envId
                EnvironmentDisplayName         = $envName
                EnvironmentType                = $envType
                Zone                           = $zone
                AgentId                        = $bot.botid
                AgentName                      = $bot.name
                AgentStatus                    = if ($bot.statecode -eq 0) { 'Active' } else { 'Inactive' }
                HasUserDefinedActionMessages   = $messageCheck.HasUserDefinedActionMessages
                ActionComponentCount           = $messageCheck.ActionComponentCount
                ComponentsWithMessages         = $messageCheck.ComponentsWithMessages
                PolicyRequirement              = $policy.Requirement
                IsCompliant                    = $isCompliant
                Severity                       = $severity
                ViolationType                  = $violationType
                RegulatoryContext               = $policy.RegulatoryContext
                Details                        = $messageCheck.Details
                RunId                          = $runId
                RetrievedAt                    = (Get-Date).ToUniversalTime()
            }

            $results.Add($agentResult)
        }
    }

    Write-Progress -Activity "Scanning environments for user-defined action messages" -Completed

    #endregion

    #region Persist Results to Dataverse

    if ($PersistResults -and $DataverseUrl -and -not $WhatIfPreference) {
        $violations = @($results | Where-Object { $_.ViolationType })

        if ($violations.Count -gt 0) {
            Write-Verbose "Persisting $($violations.Count) violation(s) to Dataverse..."

            $baseUrl = $DataverseUrl.TrimEnd('/')
            $headers = @{
                'Authorization'    = "Bearer $elmToken"
                'Accept'           = 'application/json'
                'OData-MaxVersion' = '4.0'
                'OData-Version'    = '4.0'
                'Content-Type'     = 'application/json'
            }

            foreach ($v in $violations) {
                # Map zone string to picklist integer
                $zoneInt = switch ($v.Zone) {
                    'Zone 1' { 1 }
                    'Zone 2' { 2 }
                    'Zone 3' { 3 }
                    default  { 0 }
                }

                $record = @{
                    fsi_name               = "UDAM-$($v.AgentId)-$(Get-Date -Format 'yyyyMMdd')"
                    fsi_environmentguid    = $v.EnvironmentId
                    fsi_environmentname    = $v.EnvironmentDisplayName
                    fsi_zone               = $zoneInt
                    fsi_agentid            = $v.AgentId
                    fsi_agentname          = $v.AgentName
                    fsi_actionname         = 'UserDefinedActionMessage'
                    fsi_actiontype         = 100000000  # ConnectorAction default
                    fsi_risklevel          = if ($v.ActionCategory) { $v.ActionCategory } else { 'Execute' }
                    fsi_confirmationstatus = 100000001  # Missing
                    fsi_violationstatus    = 100000000  # Open
                    fsi_violationtype      = $v.ViolationType
                    fsi_severity           = $v.Severity
                    fsi_regulatorycontext  = $v.RegulatoryContext
                    fsi_detectedat         = $v.RetrievedAt.ToString('yyyy-MM-ddTHH:mm:ssZ')
                    fsi_runid              = $runId
                }

                if ($PSCmdlet.ShouldProcess("fsi_actionauditresults", "Create violation record for $($v.AgentName)")) {
                    try {
                        $body = $record | ConvertTo-Json -Depth 5
                        Invoke-RestMethod -Uri "$baseUrl/api/data/v9.2/fsi_actionauditresults" `
                            -Method Post -Headers $headers -Body $body -ErrorAction Stop | Out-Null
                        Write-Verbose "Persisted violation for agent: $($v.AgentName)"
                    } catch {
                        Write-Warning "Failed to persist violation for $($v.AgentName): $($_.Exception.Message)"
                    }
                }
            }
        }
    }

    #endregion

    #region Output Results

    $totalAgents = $results.Count
    $compliantCount = @($results | Where-Object { $_.IsCompliant }).Count
    $violationCount = @($results | Where-Object { -not $_.IsCompliant }).Count
    $advisoryCount = @($results | Where-Object { $_.ViolationType -and $_.IsCompliant }).Count

    Write-Verbose "Total agents: $totalAgents"
    Write-Verbose "Compliant: $compliantCount"
    Write-Verbose "Violations: $violationCount"
    Write-Verbose "Advisory: $advisoryCount"

    switch ($OutputFormat) {
        'Json' {
            $output = [PSCustomObject]@{
                RunId              = $runId
                Timestamp          = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
                Control            = '1.23'
                CheckType          = 'UserDefinedActionMessages'
                TotalAgents        = $totalAgents
                Compliant          = $compliantCount
                Violations         = $violationCount
                Advisory           = $advisoryCount
                Results            = @($results)
            }
            return ($output | ConvertTo-Json -Depth 10)
        }
        'Object' {
            return $results.ToArray()
        }
        default {
            # Table output with summary
            Write-Host ""
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host "  User-Defined Action Messages Validation" -ForegroundColor Cyan
            Write-Host "  Control 1.23 - Step-Up Authentication" -ForegroundColor Gray
            Write-Host "==========================================" -ForegroundColor Cyan
            Write-Host ""
            Write-Host "  Total Agents:  $totalAgents" -ForegroundColor Cyan
            Write-Host "  Compliant:     $compliantCount" -ForegroundColor Green
            Write-Host "  Violations:    $violationCount" -ForegroundColor $(if ($violationCount -gt 0) { 'Red' } else { 'Green' })
            Write-Host "  Advisory:      $advisoryCount" -ForegroundColor Yellow
            Write-Host ""

            if ($results.Count -gt 0) {
                $results | Format-Table -Property `
                    @{Label = 'Environment'; Expression = { $_.EnvironmentDisplayName }; Width = 25 },
                    @{Label = 'Zone'; Expression = { $_.Zone }; Width = 8 },
                    @{Label = 'Agent'; Expression = { $_.AgentName }; Width = 25 },
                    @{Label = 'HasMessages'; Expression = { $_.HasUserDefinedActionMessages }; Width = 12 },
                    @{Label = 'Requirement'; Expression = { $_.PolicyRequirement }; Width = 12 },
                    @{Label = 'Compliant'; Expression = { $_.IsCompliant }; Width = 10 },
                    @{Label = 'Severity'; Expression = { $_.Severity }; Width = 10 } `
                    -AutoSize -Wrap
            }

            return $results.ToArray()
        }
    }

    #endregion
}
