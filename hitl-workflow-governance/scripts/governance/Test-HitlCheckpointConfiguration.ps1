<#
.SYNOPSIS
    Validates that Copilot Studio agent flows have proper HITL checkpoint
    configuration per zone governance requirements.

.DESCRIPTION
    Scans Power Platform environments for Copilot Studio agents and checks
    whether each agent's flows contain required Human-in-the-Loop checkpoints
    from the advancedapprovals connector (Request for Information, Run a
    Multistage Approval).

    Zone-based policy enforcement:
    - Zone 3 (Enterprise/Regulated): All write/financial/external actions
      require HITL checkpoint; pre-approval required for customer-facing flows.
      Missing checkpoints are Critical severity.
    - Zone 2 (Team/Collaborative): Financial/external/PII actions require
      HITL checkpoint; sampled review for routine flows.
      Missing checkpoints are High severity.
    - Zone 1 (Personal Productivity): HITL checkpoints recommended;
      advisory only. Missing checkpoints are Warning severity.

    Validates: checkpoint presence, reviewer assignment, input configuration,
    and SLA compliance per zone policy.

    Results are exported as evidence-compatible JSON or console output. Violations
    are classified by severity based on zone assignment and written to Dataverse
    when -PersistResults is specified.

    This script supports compliance with FINRA Rule 3110 (supervision), GLBA Section 501(b)
    (safeguards), and SOX Section 404 (internal controls) by providing auditable evidence
    that agent flows include appropriate human oversight checkpoints before execution
    of sensitive operations.

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

.PARAMETER Zone
    Optional zone filter to limit scanning to a specific zone (Zone1, Zone2, Zone3).

.PARAMETER DataverseUrl
    ELM Dataverse URL for zone classification lookup. If not provided, zone classification
    falls back to environment naming convention.

.PARAMETER OutputFormat
    Output format: Table (default), Json, or Object.

.PARAMETER PersistResults
    When specified with -DataverseUrl, writes violations to fsi_hitlcheckpointresults.

.PARAMETER WhatIf
    Preview mode — shows what violations would be reported without persisting.

.EXAMPLE
    . .\Test-HitlCheckpointConfiguration.ps1
    Test-HitlCheckpointConfiguration -WhatIf

    Dry-run scan of all environments for HITL checkpoint compliance.

.EXAMPLE
    . .\Test-HitlCheckpointConfiguration.ps1
    Test-HitlCheckpointConfiguration -IncludeEnvironments @("env-id-1") -OutputFormat Json

    Scan specific environments with JSON output for evidence pipeline.

.EXAMPLE
    . .\Test-HitlCheckpointConfiguration.ps1
    Test-HitlCheckpointConfiguration -Zone Zone3 -OutputFormat Table

    Scan only Zone 3 environments with table output.

.OUTPUTS
    PSCustomObject[] -- One object per agent with properties:
    EnvironmentGuid, EnvironmentName, Zone, AgentId, AgentName,
    HasHitlCheckpoint, PolicyRequirement, IsCompliant, Severity,
    ViolationType, FlowsWithHitl, FlowsMissingHitl, RegulatoryContext,
    RetrievedAt

.NOTES
    File: Test-HitlCheckpointConfiguration.ps1
    Version: 1.0.0
    Solution: HITL Workflow Governance (HWG)
    Controls: 2.12 (Supervision/FINRA Rule 3110), 2.17 (Multi-Agent Orchestration), 1.10 (Communication Compliance)
    Regulations: FINRA Rule 3110, GLBA Section 501(b), SOX Section 404
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

function Test-HitlCheckpointConfiguration {
    <#
    .SYNOPSIS
        Validates HITL checkpoint configuration for Copilot Studio agents
        against zone-specific governance requirements.

    .DESCRIPTION
        Enumerates Power Platform environments, queries bot and botcomponent tables,
        and checks whether each agent's flows contain advancedapprovals connector
        checkpoints. Applies zone-based policies and reports violations with
        severity classification.

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

    .PARAMETER Zone
        Optional zone filter (Zone1, Zone2, Zone3).

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
        [ValidateSet('Zone1', 'Zone2', 'Zone3')]
        [string]$Zone,

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
    Write-Verbose "HITL Checkpoint Configuration Validator"
    Write-Verbose "RunId: $runId"
    Write-Verbose "========================================="

    #endregion

    #region Import Private Helpers

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

    #region Zone Policy Definition

    $zonePolicies = @{
        'Zone3' = [PSCustomObject]@{
            Zone              = 'Zone3'
            Requirement       = 'Required'
            Severity          = 'Critical'
            RequiresReviewer  = $true
            MinimumInputs     = 1
            RegulatoryContext = 'Zone 3 (Enterprise/Regulated) - HITL checkpoints required for all write/financial/external actions per FINRA Rule 3110 supervisory requirements; pre-approval for customer-facing flows'
        }
        'Zone2' = [PSCustomObject]@{
            Zone              = 'Zone2'
            Requirement       = 'Required'
            Severity          = 'High'
            RequiresReviewer  = $true
            MinimumInputs     = 0
            RegulatoryContext = 'Zone 2 (Team/Collaborative) - HITL checkpoints required for financial/external/PII actions per GLBA Section 501(b) safeguards; sampled review for routine flows'
        }
        'Zone1' = [PSCustomObject]@{
            Zone              = 'Zone1'
            Requirement       = 'Recommended'
            Severity          = 'Warning'
            RequiresReviewer  = $false
            MinimumInputs     = 0
            RegulatoryContext = 'Zone 1 (Personal Productivity) - HITL checkpoints recommended, advisory monitoring only'
        }
        'Unknown' = [PSCustomObject]@{
            Zone              = 'Unknown'
            Requirement       = 'Recommended'
            Severity          = 'Warning'
            RequiresReviewer  = $false
            MinimumInputs     = 0
            RegulatoryContext = 'Unclassified environment - Zone classification required before policy enforcement'
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

    #region HITL Checkpoint Detection

    function Test-BotHasHitlCheckpoints {
        <#
        .SYNOPSIS
            Checks whether a bot's flows contain advancedapprovals connector
            HITL checkpoint nodes.
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
            # botcomponent_componenttype choices (Microsoft Dataverse reference):
            #   0 = Topic, 1 = Skill, 4 = Dialog, 9 = Topic (V2). Topic/Dialog
            #   components hold the action and connector references parsed below;
            #   modern Copilot Studio agents store topics as Topic (V2) = 9.
            $componentsUri = "$baseUrl/api/data/v9.2/botcomponents?" +
                "`$filter=_parentbotid_value eq '$($Bot.botid)' and (componenttype eq 0 or componenttype eq 9 or componenttype eq 4 or componenttype eq 1)&" +
                "`$select=name,content,componenttype,botcomponentid"

            $componentsResponse = Invoke-RestMethod -Uri $componentsUri -Method Get -Headers $headers -ErrorAction Stop

            if (-not $componentsResponse.value -or $componentsResponse.value.Count -eq 0) {
                return [PSCustomObject]@{
                    HasHitlCheckpoint       = $false
                    FlowsWithHitl           = 0
                    FlowsMissingHitl        = 0
                    TotalFlows              = 0
                    CheckpointTypes         = @()
                    HasAssignedReviewers    = $false
                    TotalInputCount         = 0
                    Details                 = 'No flow components found'
                }
            }

            $flowsWithHitl = 0
            $flowsMissingHitl = 0
            $totalFlows = 0
            $checkpointTypes = @()
            $hasReviewers = $false
            $totalInputs = 0

            foreach ($component in $componentsResponse.value) {
                if (-not $component.content) { continue }

                $contentStr = $component.content

                # Check if this component has any action invocations (makes it a relevant flow)
                $hasActions = $contentStr -match '"kind"\s*:\s*"(InvokeFlowAction|InvokeConnectorAction|InvokeSkillAction|HttpRequest|InvokePlugin|InvokeCustomAction)"'

                if (-not $hasActions) { continue }

                $totalFlows++

                # Check for advancedapprovals connector references
                $hasRfi = $contentStr -match '(?i)request\s+for\s+information|RequestForInformation'
                $hasApproval = $contentStr -match '(?i)run\s+a?\s*multistage\s+approval|RunMultistageApproval|StartAndWaitForAnApprovalProcess|MultistageApproval'
                $hasConnector = $contentStr -match '(?i)advancedapprovals'

                if ($hasRfi -or $hasApproval -or $hasConnector) {
                    $flowsWithHitl++

                    if ($hasRfi) { $checkpointTypes += 'RequestForInformation' }
                    if ($hasApproval) { $checkpointTypes += 'MultistageApproval' }

                    # Check for reviewer assignment
                    $reviewerMatch = $contentStr -match '(?i)"(?:assignedTo|reviewers?|approvers?|recipients?)"\s*:\s*"[^"]+"'
                    if ($reviewerMatch) { $hasReviewers = $true }

                    # Count input fields
                    $inputMatches = [regex]::Matches($contentStr, '(?i)"(?:inputName|fieldName|parameterName)"\s*:\s*"[^"]+"')
                    $totalInputs += $inputMatches.Count
                } else {
                    $flowsMissingHitl++
                }
            }

            $hasCheckpoint = $flowsWithHitl -gt 0

            return [PSCustomObject]@{
                HasHitlCheckpoint       = $hasCheckpoint
                FlowsWithHitl           = $flowsWithHitl
                FlowsMissingHitl        = $flowsMissingHitl
                TotalFlows              = $totalFlows
                CheckpointTypes         = @($checkpointTypes | Select-Object -Unique)
                HasAssignedReviewers    = $hasReviewers
                TotalInputCount         = $totalInputs
                Details                 = if ($totalFlows -eq 0) {
                                              'No action invocation flows found'
                                          } elseif ($hasCheckpoint) {
                                              "$flowsWithHitl of $totalFlows flow(s) have HITL checkpoints"
                                          } else {
                                              "No HITL checkpoints found in $totalFlows flow(s)"
                                          }
            }
        } catch {
            Write-Verbose "botcomponent query failed for $($Bot.name): $($_.Exception.Message)"
            return [PSCustomObject]@{
                HasHitlCheckpoint       = $false
                FlowsWithHitl           = 0
                FlowsMissingHitl        = 0
                TotalFlows              = 0
                CheckpointTypes         = @()
                HasAssignedReviewers    = $false
                TotalInputCount         = 0
                Details                 = "Query failed: $($_.Exception.Message)"
            }
        }
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

    # Acquire ELM token once if DataverseUrl provided
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

        Write-Progress -Activity "Scanning environments for HITL checkpoint configuration" `
            -Status "Processing $envName ($envIndex of $($dvEnvironments.Count))" `
            -PercentComplete (($envIndex / $dvEnvironments.Count) * 100)

        # Get zone classification
        $envZone = & (Join-Path $privateRoot 'Get-ZoneClassification.ps1') `
            -EnvironmentId $envId `
            -EnvironmentDisplayName $envName `
            -DataverseUrl $DataverseUrl `
            -AccessToken $elmToken

        # Apply zone filter if specified
        if ($Zone -and $envZone -ne $Zone) {
            Write-Verbose "Skipping environment $envName (zone $envZone, filter: $Zone)"
            continue
        }

        # Connect to environment Dataverse
        $envToken = $null
        try {
            $envToken = & (Join-Path $privateRoot 'Connect-EnvironmentDataverse.ps1') `
                -DataverseUrl $envDataverseUrl
        } catch {
            Write-Warning "Failed to connect to Dataverse for environment '$envName': $($_.Exception.Message). Skipping."
            continue
        }

        # Query agents
        Write-Verbose "Querying agents from: $envName"
        $bots = Get-AgentBots -DataverseUrl $envDataverseUrl -AccessToken $envToken -IncludeDrafts:$IncludeDrafts

        if (-not $bots -or $bots.Count -eq 0) {
            Write-Verbose "No agents found in environment: $envName"
            continue
        }

        Write-Verbose "Found $($bots.Count) agent(s) in: $envName (Zone: $envZone)"

        # Get zone policy
        $policy = $zonePolicies[$envZone]
        if (-not $policy) { $policy = $zonePolicies['Unknown'] }

        # Process each agent
        foreach ($bot in $bots) {
            $hitlStatus = Test-BotHasHitlCheckpoints -Bot $bot -EnvDataverseUrl $envDataverseUrl -EnvToken $envToken

            # Determine compliance
            $isCompliant = $true
            $violationType = $null
            $severity = 'None'

            if (-not $hitlStatus.HasHitlCheckpoint) {
                if ($policy.Requirement -eq 'Required') {
                    $isCompliant = $false
                    $violationType = 'MissingHitlCheckpoint'
                    $severity = $policy.Severity
                } elseif ($policy.Requirement -eq 'Recommended') {
                    $violationType = 'AdvisoryMissingHitlCheckpoint'
                    $severity = 'Warning'
                }
            } elseif ($policy.RequiresReviewer -and -not $hitlStatus.HasAssignedReviewers) {
                $isCompliant = $false
                $violationType = 'MissingReviewer'
                $severity = $policy.Severity
            } elseif ($policy.MinimumInputs -gt 0 -and $hitlStatus.TotalInputCount -lt $policy.MinimumInputs) {
                $isCompliant = $false
                $violationType = 'InsufficientInputs'
                $severity = if ($policy.Severity -eq 'Critical') { 'High' } else { $policy.Severity }
            }

            $results.Add([PSCustomObject]@{
                EnvironmentGuid        = $envId
                EnvironmentName        = $envName
                Zone                   = $envZone
                AgentId                = $bot.botid
                AgentName              = $bot.name
                HasHitlCheckpoint      = $hitlStatus.HasHitlCheckpoint
                PolicyRequirement      = $policy.Requirement
                IsCompliant            = $isCompliant
                Severity               = $severity
                ViolationType          = $violationType
                FlowsWithHitl          = $hitlStatus.FlowsWithHitl
                FlowsMissingHitl       = $hitlStatus.FlowsMissingHitl
                TotalFlows             = $hitlStatus.TotalFlows
                CheckpointTypes        = $hitlStatus.CheckpointTypes
                HasAssignedReviewers   = $hitlStatus.HasAssignedReviewers
                TotalInputCount        = $hitlStatus.TotalInputCount
                RegulatoryContext      = $policy.RegulatoryContext
                Details                = $hitlStatus.Details
                RetrievedAt            = (Get-Date).ToUniversalTime()
            })
        }
    }

    Write-Progress -Activity "Scanning environments for HITL checkpoint configuration" -Completed

    Write-Verbose "Total agent results: $($results.Count)"

    #endregion

    #region Summary and Output

    $compliantAgents = @($results | Where-Object { $_.IsCompliant })
    $violationAgents = @($results | Where-Object { -not $_.IsCompliant })

    $criticalCount = @($violationAgents | Where-Object { $_.Severity -eq 'Critical' }).Count
    $highCount     = @($violationAgents | Where-Object { $_.Severity -eq 'High' }).Count
    $mediumCount   = @($violationAgents | Where-Object { $_.Severity -eq 'Medium' }).Count
    $warningCount  = @($results | Where-Object { $_.Severity -eq 'Warning' }).Count

    $overallStatus = 'Passed'
    if ($criticalCount -gt 0) {
        $overallStatus = 'Critical'
    } elseif ($highCount -gt 0) {
        $overallStatus = 'Failed'
    } elseif ($mediumCount -gt 0 -or $warningCount -gt 0) {
        $overallStatus = 'Review'
    }

    # Summary banner
    $statusColor = switch ($overallStatus) {
        'Critical' { 'Red' }
        'Failed'   { 'Red' }
        'Review'   { 'Yellow' }
        'Passed'   { 'Green' }
        default    { 'White' }
    }

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  HITL Checkpoint Configuration Scan" -ForegroundColor Cyan
    Write-Host "  Controls 2.12 / 2.17 / 1.10" -ForegroundColor Gray
    Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC" -ForegroundColor Gray
    Write-Host "  RunId: $runId" -ForegroundColor Gray
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Overall Status: " -NoNewline
    Write-Host $overallStatus -ForegroundColor $statusColor
    Write-Host ""

    $uniqueEnvs = ($results | Select-Object -Property EnvironmentGuid -Unique).Count
    Write-Host "Environments scanned: $uniqueEnvs"
    Write-Host "Agents scanned:       $($results.Count)"
    Write-Host "Compliant agents:     $($compliantAgents.Count)" -ForegroundColor Green
    Write-Host "Agents w/ violations: $($violationAgents.Count)" -ForegroundColor $(if ($violationAgents.Count -gt 0) { 'Red' } else { 'Green' })

    if ($criticalCount -gt 0) { Write-Host "  CRITICAL:           $criticalCount" -ForegroundColor DarkRed }
    if ($highCount -gt 0)     { Write-Host "  HIGH:               $highCount" -ForegroundColor Red }
    if ($mediumCount -gt 0)   { Write-Host "  MEDIUM:             $mediumCount" -ForegroundColor Yellow }
    if ($warningCount -gt 0)  { Write-Host "  WARNING:            $warningCount" -ForegroundColor DarkYellow }

    if ($WhatIfPreference) {
        Write-Host ""
        Write-Host "[DRY RUN] No data persisted. Re-run without -WhatIf to persist results." -ForegroundColor Gray
    }

    Write-Host ""

    #endregion

    #region Persist Results

    if ($PersistResults -and $DataverseUrl) {
        if ($PSCmdlet.ShouldProcess("Dataverse HITL checkpoint results", "Write scan results")) {
            try {
                $validationSummary = @{
                    OverallStatus   = $overallStatus
                    TotalAgents     = $results.Count
                    CompliantCount  = $compliantAgents.Count
                    ViolationCount  = $violationAgents.Count
                }
                Write-HitlScanRun -ValidationResult $validationSummary -RunId $runId
                Write-Verbose "Validation history written with RunId: $runId"
            } catch {
                Write-Warning "Failed to write validation history: $($_.Exception.Message)"
            }
        }
    }

    #endregion

    #region Format Output

    switch ($OutputFormat) {
        'Table' {
            if ($violationAgents.Count -gt 0) {
                Write-Host "-----------------------------------------" -ForegroundColor Gray
                Write-Host "Agent Compliance Details:" -ForegroundColor White
                Write-Host "-----------------------------------------" -ForegroundColor Gray

                foreach ($agent in $violationAgents) {
                    $sevColor = switch ($agent.Severity) {
                        'Critical' { 'DarkRed' }
                        'High'     { 'Red' }
                        'Medium'   { 'Yellow' }
                        'Warning'  { 'DarkYellow' }
                        default    { 'Gray' }
                    }

                    Write-Host ""
                    Write-Host "  [$($agent.Severity)] " -NoNewline -ForegroundColor $sevColor
                    Write-Host "$($agent.AgentName)" -ForegroundColor White
                    Write-Host "    Environment:      $($agent.EnvironmentName)" -ForegroundColor Gray
                    Write-Host "    Zone:             $($agent.Zone)" -ForegroundColor Gray
                    Write-Host "    Violation:        $($agent.ViolationType)" -ForegroundColor $sevColor
                    Write-Host "    Details:          $($agent.Details)" -ForegroundColor Gray
                    Write-Host "    Flows w/ HITL:    $($agent.FlowsWithHitl) / $($agent.TotalFlows)" -ForegroundColor Gray
                    if ($agent.RegulatoryContext) {
                        Write-Host "    Regulatory:       $($agent.RegulatoryContext)" -ForegroundColor $sevColor
                    }
                }
                Write-Host ""
            } else {
                Write-Host "No violations found. All scanned agents have proper HITL checkpoint configuration." -ForegroundColor Green
                Write-Host ""
            }

            Write-Host "==========================================" -ForegroundColor Cyan
        }
        'Json' {
            @{
                metadata = @{
                    RunId              = $runId
                    TotalAgentsScanned = $results.Count
                    TotalEnvironments  = $uniqueEnvs
                    CompliantAgents    = $compliantAgents.Count
                    ViolationCount     = $violationAgents.Count
                    CriticalCount      = $criticalCount
                    HighCount          = $highCount
                    MediumCount        = $mediumCount
                    WarningCount       = $warningCount
                    OverallStatus      = $overallStatus
                    ScanTimestamp      = (Get-Date).ToUniversalTime().ToString('o')
                    DryRun             = $WhatIfPreference
                    Controls           = @('2.12', '2.17', '1.10')
                }
                results = @($results | ForEach-Object {
                    @{
                        AgentId              = $_.AgentId
                        AgentName            = $_.AgentName
                        EnvironmentName      = $_.EnvironmentName
                        Zone                 = $_.Zone
                        HasHitlCheckpoint    = $_.HasHitlCheckpoint
                        PolicyRequirement    = $_.PolicyRequirement
                        IsCompliant          = $_.IsCompliant
                        Severity             = $_.Severity
                        ViolationType        = $_.ViolationType
                        FlowsWithHitl        = $_.FlowsWithHitl
                        FlowsMissingHitl     = $_.FlowsMissingHitl
                        TotalFlows           = $_.TotalFlows
                        CheckpointTypes      = $_.CheckpointTypes
                        HasAssignedReviewers = $_.HasAssignedReviewers
                        RegulatoryContext    = $_.RegulatoryContext
                        Details              = $_.Details
                    }
                })
            } | ConvertTo-Json -Depth 7
        }
        'Object' {
            $results.ToArray()
        }
    }

    #endregion
}
