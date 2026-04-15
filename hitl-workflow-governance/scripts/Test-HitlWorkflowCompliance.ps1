<#
.SYNOPSIS
    Validates HITL checkpoint configuration for all Copilot Studio agents
    against zone-specific governance requirements.

.DESCRIPTION
    Orchestrates a full HITL workflow compliance scan:
    1. Enumerates Power Platform environments
    2. Queries each environment's Dataverse for Copilot Studio agents
    3. Retrieves HITL checkpoint settings per agent flow
    4. Validates each flow's checkpoint status against zone policies
    5. Reports violations with severity classification and regulatory context

    This is the primary validation script for the HITL Workflow Governance
    (HWG) solution. It validates per-agent HITL checkpoint posture against
    zone-based governance policies defined by Controls 2.12, 2.17, and 1.10.

    Combines Get-AgentHitlSettings and zone policy evaluation into a single
    validation workflow with dry-run mode, multiple output formats, summary
    statistics, and environment/agent filtering.

.NOTES
    File: Test-HitlWorkflowCompliance.ps1
    Version: 1.0.0
    Solution: HITL Workflow Governance (HWG)
    Controls: 2.12 (Supervision/FINRA 3110), 2.17 (Multi-Agent Orchestration), 1.10 (Communication Compliance)
    Regulations: FINRA 3110, GLBA 501(b), SOX 404

    Part of FSI Agent Governance Framework
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

function Test-HitlWorkflowCompliance {
    <#
    .SYNOPSIS
        Validates HITL checkpoint configuration for all Copilot Studio agents
        against zone-specific governance requirements.

    .DESCRIPTION
        Orchestrates a full HITL workflow compliance scan across Power Platform
        environments. For each agent's flows, applies zone-specific HITL
        checkpoint policies and reports violations with appropriate severity.

    .PARAMETER WhatIf
        Preview mode — shows what violations would be reported without persisting
        to Dataverse or triggering alerts. Always safe to run.

    .PARAMETER OutputFormat
        Output format: Table (default), Json, or Object.
        - Table: Formatted table with color-coded severity
        - Json: Machine-readable JSON for evidence export pipeline
        - Object: Raw PSCustomObject[] for pipeline consumption

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
        Valid range: 0-168 (1 week).

    .PARAMETER IncludeDrafts
        Include draft/unpublished agents (default: published only).

    .PARAMETER IncludeCompliant
        Include compliant agents in output (default: violations only).

    .PARAMETER DataverseUrl
        Optional ELM Dataverse URL for zone classification lookup.
        When provided with -PersistResults, also reads operational parameters
        from Dataverse environment variables and persists scan results.

    .PARAMETER DataverseToken
        Pre-obtained access token for Dataverse authentication.

    .PARAMETER TenantId
        Azure AD tenant ID for authentication.

    .PARAMETER ClientId
        Azure AD application (client) ID for service principal authentication.

    .PARAMETER ClientSecret
        Client secret for service principal authentication.

    .PARAMETER Interactive
        Use interactive browser-based authentication.

    .PARAMETER PersistResults
        When specified with -DataverseUrl, writes validation summary to
        fsi_hitlscanruns and individual violations to
        fsi_hitlcheckpointresults. Requires active Dataverse connection.

    .PARAMETER Top
        Limit total agents processed (safety cap for large tenants).
        Default 0 means no limit.

    .EXAMPLE
        . ./Test-HitlWorkflowCompliance.ps1
        Test-HitlWorkflowCompliance -WhatIf

        Dry-run scan of all environments (default: published agents, violations only).

    .EXAMPLE
        . ./Test-HitlWorkflowCompliance.ps1
        Test-HitlWorkflowCompliance -IncludeEnvironments @("env-id-1") -OutputFormat Json

        Scan specific environments with JSON output for evidence pipeline.

    .EXAMPLE
        . ./Test-HitlWorkflowCompliance.ps1
        Test-HitlWorkflowCompliance -IncludeCompliant -IncludeDrafts

        Full scan including compliant agents and drafts.

    .OUTPUTS
        Formatted table (default), JSON string, or PSCustomObject[] depending on -OutputFormat.
        Summary statistics are always written to the host output stream.
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
        [switch]$IncludeCompliant,

        [Parameter()]
        [string]$DataverseUrl,

        [Parameter()]
        [string]$DataverseToken,

        [Parameter()]
        [string]$TenantId,

        [Parameter()]
        [string]$ClientId,

        [Parameter()]
        [string]$ClientSecret,

        [Parameter()]
        [switch]$Interactive,

        [Parameter()]
        [switch]$PersistResults,

        [Parameter()]
        [int]$Top = 0
    )

    #region Script Initialization

    $ErrorActionPreference = 'Stop'
    $scriptRoot = $PSScriptRoot
    $runId = [guid]::NewGuid().ToString()

    Write-Verbose "========================================="
    Write-Verbose "HITL Workflow Governance v1.0.0"
    Write-Verbose "RunId: $runId"
    Write-Verbose "========================================="

    #endregion

    #region Import Dependencies

    # Dot-source companion script to load Get-AgentHitlSettings function
    $getSettingsScript = Join-Path $scriptRoot 'Get-AgentHitlSettings.ps1'

    if (-not (Test-Path $getSettingsScript)) {
        throw "Required script not found: $getSettingsScript"
    }

    Write-Verbose "Loading Get-AgentHitlSettings from: $getSettingsScript"
    . $getSettingsScript

    # Import private helpers
    $privateRoot = Join-Path $scriptRoot 'private'
    Import-Module (Join-Path $privateRoot 'HWGClient.psm1') -Force

    #endregion

    #region Zone Policy Definitions

    function Get-ExpectedHitlPolicy {
        <#
        .SYNOPSIS
            Returns the expected HITL checkpoint policy for a given zone.
        #>
        param(
            [Parameter(Mandatory)]
            [string]$Zone
        )

        switch ($Zone) {
            'Zone3' {
                return [PSCustomObject]@{
                    Zone                    = 'Zone3'
                    RequiresHitl            = $true
                    RequiresReviewer        = $true
                    MinimumInputs           = 1
                    AdvisoryOnly            = $false
                    MissingSeverity         = 'Critical'
                    ReviewerMissingSeverity = 'Critical'
                    InputSeverity           = 'High'
                    RegulatoryContext        = 'Zone 3 (Enterprise/Regulated) - HITL checkpoints required for all write/financial/external actions per FINRA 3110 supervisory requirements'
                }
            }
            'Zone2' {
                return [PSCustomObject]@{
                    Zone                    = 'Zone2'
                    RequiresHitl            = $true
                    RequiresReviewer        = $true
                    MinimumInputs           = 0
                    AdvisoryOnly            = $false
                    MissingSeverity         = 'High'
                    ReviewerMissingSeverity = 'High'
                    InputSeverity           = 'Medium'
                    RegulatoryContext        = 'Zone 2 (Team/Collaborative) - HITL checkpoints required for financial/external/PII actions per GLBA 501(b) safeguards'
                }
            }
            'Zone1' {
                return [PSCustomObject]@{
                    Zone                    = 'Zone1'
                    RequiresHitl            = $false
                    RequiresReviewer        = $false
                    MinimumInputs           = 0
                    AdvisoryOnly            = $true
                    MissingSeverity         = 'Warning'
                    ReviewerMissingSeverity = 'Warning'
                    InputSeverity           = 'Warning'
                    RegulatoryContext        = 'Zone 1 (Personal Productivity) - HITL checkpoints recommended, advisory monitoring only'
                }
            }
            default {
                return [PSCustomObject]@{
                    Zone                    = 'Unknown'
                    RequiresHitl            = $false
                    RequiresReviewer        = $false
                    MinimumInputs           = 0
                    AdvisoryOnly            = $true
                    MissingSeverity         = 'Warning'
                    ReviewerMissingSeverity = 'Warning'
                    InputSeverity           = 'Warning'
                    RegulatoryContext        = 'Unclassified environment - Zone classification required before policy enforcement'
                }
            }
        }
    }

    #endregion

    #region Display Scan Configuration

    Write-Verbose "Scan configuration:"
    Write-Verbose "  OutputFormat:       $OutputFormat"
    Write-Verbose "  ExcludeSandbox:     $($ExcludeSandbox.IsPresent)"
    Write-Verbose "  ExcludeTrial:       $($ExcludeTrial.IsPresent)"
    Write-Verbose "  ExcludeDefault:     $($ExcludeDefault.IsPresent)"
    Write-Verbose "  GracePeriodHours:   $GracePeriodHours"
    Write-Verbose "  IncludeDrafts:      $($IncludeDrafts.IsPresent)"
    Write-Verbose "  IncludeCompliant:   $($IncludeCompliant.IsPresent)"
    Write-Verbose "  Top:                $(if ($Top -gt 0) { $Top } else { 'No limit' })"
    Write-Verbose "  WhatIf:             $WhatIfPreference"
    if ($DataverseUrl) {
        Write-Verbose "  DataverseUrl:       $DataverseUrl"
    }
    if ($DataverseToken) {
        Write-Verbose "  DataverseToken:     (provided)"
    }
    if ($PersistResults) {
        Write-Verbose "  PersistResults:     True"
    }

    #endregion

    #region Dataverse Integration

    $dataverseConnected = $false

    if ($DataverseUrl) {
        try {
            if ($DataverseToken) {
                Connect-HWGDataverse -DataverseUrl $DataverseUrl -AccessToken $DataverseToken
            } else {
                Connect-HWGDataverse -DataverseUrl $DataverseUrl
            }

            $connection = Get-HWGConnection
            if ($connection.IsConnected) {
                $dataverseConnected = $true
                Write-Verbose "Connected to Dataverse: $DataverseUrl"

                # Read operational parameters from Dataverse env vars
                $dvGracePeriod = Get-HWGEnvironmentVariable -Name 'GracePeriodHours' -DefaultValue $null
                if (-not $PSBoundParameters.ContainsKey('GracePeriodHours') -and $null -ne $dvGracePeriod) {
                    $GracePeriodHours = [int]$dvGracePeriod
                    Write-Verbose "GracePeriodHours from Dataverse: $GracePeriodHours"
                }

                $dvIncludeDrafts = Get-HWGEnvironmentVariable -Name 'IncludeDrafts' -DefaultValue $null
                if (-not $PSBoundParameters.ContainsKey('IncludeDrafts') -and $null -ne $dvIncludeDrafts -and $dvIncludeDrafts -eq 'true') {
                    $IncludeDrafts = [switch]::Present
                    Write-Verbose "IncludeDrafts from Dataverse: true"
                }

                $dvIncludeSandbox = Get-HWGEnvironmentVariable -Name 'IncludeSandbox' -DefaultValue $null
                if (-not $PSBoundParameters.ContainsKey('ExcludeSandbox') -and $null -ne $dvIncludeSandbox -and $dvIncludeSandbox -eq 'true') {
                    $ExcludeSandbox = $false
                    Write-Verbose "IncludeSandbox from Dataverse: true (ExcludeSandbox overridden)"
                }
            }
        } catch {
            Write-Warning "Dataverse connection failed: $($_.Exception.Message). Continuing in standalone mode."
        }
    }

    #endregion

    #region Build Parameters and Collect Data

    # Build parameter hashtable for Get-AgentHitlSettings
    $queryParams = @{
        GracePeriodHours = $GracePeriodHours
    }

    if ($IncludeEnvironments) { $queryParams['IncludeEnvironments'] = $IncludeEnvironments }
    if ($ExcludeEnvironments) { $queryParams['ExcludeEnvironments'] = $ExcludeEnvironments }
    if ($ExcludeSandbox)      { $queryParams['ExcludeSandbox'] = $true }
    if ($ExcludeTrial)        { $queryParams['ExcludeTrial'] = $true }
    if ($ExcludeDefault)      { $queryParams['ExcludeDefault'] = $true }
    if ($IncludeDrafts)       { $queryParams['IncludeDrafts'] = $true }
    if ($DataverseUrl)        { $queryParams['DataverseUrl'] = $DataverseUrl }
    if ($Top -gt 0)           { $queryParams['Top'] = $Top }

    Write-Verbose "Querying agent HITL settings..."

    if ($PSCmdlet.ShouldProcess("All Power Platform environments", "Query agent HITL checkpoint settings")) {
        $agentSettings = Get-AgentHitlSettings @queryParams
    } else {
        # WhatIf mode — still collect data for display (read-only operation)
        $agentSettings = Get-AgentHitlSettings @queryParams
    }

    if (-not $agentSettings -or $agentSettings.Count -eq 0) {
        Write-Warning "No agents found matching the specified criteria."

        Write-Host "`n=== HITL Workflow Compliance Scan ===" -ForegroundColor Cyan
        Write-Host "Environments scanned: 0"
        Write-Host "Agents scanned:       0"
        Write-Host "No agents found to evaluate." -ForegroundColor Yellow
        if ($WhatIfPreference) {
            Write-Host "`n[DRY RUN] Preview mode - no data persisted." -ForegroundColor Gray
        }
        Write-Host "=============================================`n" -ForegroundColor Cyan

        switch ($OutputFormat) {
            'Json' {
                return @{
                    metadata = @{
                        RunId                    = $runId
                        TotalAgentsScanned       = 0
                        TotalEnvironments        = 0
                        TotalFlowsScanned        = 0
                        FlowsWithHitl            = 0
                        FlowsMissingHitl         = 0
                        ViolationCount           = 0
                        CriticalCount            = 0
                        HighCount                = 0
                        MediumCount              = 0
                        WarningCount             = 0
                        ScanTimestamp            = (Get-Date).ToUniversalTime().ToString('o')
                        DryRun                   = $WhatIfPreference
                        Controls                 = @('2.12', '2.17', '1.10')
                    }
                    results = @()
                } | ConvertTo-Json -Depth 5
            }
            'Object' { return @() }
            'Table'  { return }
        }
    }

    Write-Verbose "Found $($agentSettings.Count) agent flow result(s) across environments"

    #endregion

    #region Compliance Evaluation

    Write-Verbose "Evaluating HITL checkpoint compliance against zone policies..."

    $complianceResults = [System.Collections.Generic.List[PSCustomObject]]::new()

    # Group results by agent to evaluate at agent level
    $agentGroups = $agentSettings | Group-Object -Property AgentId

    # Load exception records if Dataverse is connected
    $exceptions = @{}
    if ($dataverseConnected) {
        try {
            $exceptionRecords = Get-HitlCheckpointExceptions
            if ($exceptionRecords) {
                foreach ($exc in $exceptionRecords) {
                    $key = "$($exc.AgentId)|$($exc.ActionName)"
                    $exceptions[$key] = $exc
                }
            }
            Write-Verbose "Loaded $($exceptions.Count) exception record(s)"
        } catch {
            Write-Verbose "Exception table query failed: $($_.Exception.Message). Continuing without exceptions."
        }
    }

    foreach ($group in $agentGroups) {
        $agentFlows = $group.Group
        $firstFlow = $agentFlows[0]

        # Get zone policy for this agent's environment
        $policy = Get-ExpectedHitlPolicy -Zone $firstFlow.Zone

        $agentViolations = @()
        $agentIsCompliant = $true

        # Check if the agent has ANY HITL checkpoint
        $hasAnyHitl = @($agentFlows | Where-Object { $_.HasHitlCheckpoint }).Count -gt 0
        $hitlFlows = @($agentFlows | Where-Object { $_.HasHitlCheckpoint })
        $totalFlows = ($agentFlows | Select-Object -Property FlowName -Unique).Count

        if (-not $hasAnyHitl) {
            # MissingHitlCheckpoint violation
            if ($policy.RequiresHitl) {
                $agentIsCompliant = $false
                $agentViolations += [PSCustomObject]@{
                    ViolationType      = 'MissingHitlCheckpoint'
                    Severity           = $policy.MissingSeverity
                    FlowName           = $null
                    FlowId             = $null
                    CheckpointType     = $null
                    Details            = "No HITL checkpoints found in any agent flow"
                    RegulatoryContext   = $policy.RegulatoryContext
                }
            } elseif ($policy.AdvisoryOnly) {
                $agentViolations += [PSCustomObject]@{
                    ViolationType      = 'AdvisoryMissingHitlCheckpoint'
                    Severity           = 'Warning'
                    FlowName           = $null
                    FlowId             = $null
                    CheckpointType     = $null
                    Details            = "No HITL checkpoints found (advisory)"
                    RegulatoryContext   = $policy.RegulatoryContext
                }
            }
        } else {
            # Check each HITL checkpoint for reviewer and input compliance
            foreach ($flow in $hitlFlows) {
                # Check for exception
                $exceptionKey = "$($flow.AgentId)|$($flow.FlowName)"
                if ($exceptions.ContainsKey($exceptionKey)) {
                    Write-Verbose "Exception found for $($flow.AgentName) flow $($flow.FlowName)"
                    continue
                }

                # MissingReviewer check
                if ($policy.RequiresReviewer -and ($null -eq $flow.AssignedReviewers -or $flow.AssignedReviewers.Count -eq 0)) {
                    $agentIsCompliant = $false
                    $agentViolations += [PSCustomObject]@{
                        ViolationType      = 'MissingReviewer'
                        Severity           = $policy.ReviewerMissingSeverity
                        FlowName           = $flow.FlowName
                        FlowId             = $flow.FlowId
                        CheckpointType     = $flow.CheckpointType
                        Details            = "HITL checkpoint '$($flow.CheckpointName)' has no assigned reviewers"
                        RegulatoryContext   = $policy.RegulatoryContext
                    }
                }

                # InsufficientInputs check
                if ($policy.MinimumInputs -gt 0 -and $flow.InputCount -lt $policy.MinimumInputs) {
                    $agentIsCompliant = $false
                    $agentViolations += [PSCustomObject]@{
                        ViolationType      = 'InsufficientInputs'
                        Severity           = $policy.InputSeverity
                        FlowName           = $flow.FlowName
                        FlowId             = $flow.FlowId
                        CheckpointType     = $flow.CheckpointType
                        Details            = "HITL checkpoint '$($flow.CheckpointName)' has $($flow.InputCount) inputs (minimum: $($policy.MinimumInputs))"
                        RegulatoryContext   = $policy.RegulatoryContext
                    }
                }
            }
        }

        # Build compliance result for this agent
        if (-not $agentIsCompliant -or $IncludeCompliant) {
            $complianceResults.Add([PSCustomObject]@{
                EnvironmentGuid        = $firstFlow.EnvironmentGuid
                EnvironmentName        = $firstFlow.EnvironmentName
                EnvironmentType        = $firstFlow.EnvironmentType
                Zone                   = $firstFlow.Zone
                AgentId                = $firstFlow.AgentId
                AgentName              = $firstFlow.AgentName
                AgentStatus            = $firstFlow.AgentStatus
                TotalFlows             = $totalFlows
                FlowsWithHitl          = $hitlFlows.Count
                FlowsMissingHitl       = $totalFlows - $hitlFlows.Count
                HasHitlCheckpoint      = $hasAnyHitl
                IsCompliant            = $agentIsCompliant
                Violations             = $agentViolations
                ViolationCount         = $agentViolations.Count
                Severity               = if ($agentViolations.Count -gt 0) {
                    $sevOrder = @('Critical', 'High', 'Medium', 'Low', 'Warning')
                    $highestSev = 'Warning'
                    foreach ($s in $sevOrder) {
                        if ($agentViolations.Severity -contains $s) { $highestSev = $s; break }
                    }
                    $highestSev
                } else { 'None' }
                RegulatoryContext       = $policy.RegulatoryContext
                DataverseUrl           = $firstFlow.DataverseUrl
            })
        }
    }

    #endregion

    #region Calculate Summary Statistics

    $uniqueAgentIds = ($agentSettings | Select-Object -Property AgentId -Unique).Count
    $uniqueEnvironments = ($agentSettings | Select-Object -Property EnvironmentGuid -Unique).Count
    $totalFlowResults = $agentSettings.Count
    $flowsWithHitl = @($agentSettings | Where-Object { $_.HasHitlCheckpoint }).Count
    $flowsMissingHitl = @($agentSettings | Where-Object { -not $_.HasHitlCheckpoint }).Count

    $compliantResults = @($complianceResults | Where-Object { $_.IsCompliant })
    $violationResults = @($complianceResults | Where-Object { -not $_.IsCompliant })

    $compliantAgentCount = if ($IncludeCompliant) {
        $compliantResults.Count
    } else {
        $uniqueAgentIds - $complianceResults.Count
    }

    $violationAgentCount = if ($IncludeCompliant) {
        $violationResults.Count
    } else {
        $complianceResults.Count
    }

    $criticalCount = @($violationResults | Where-Object { $_.Severity -eq 'Critical' }).Count
    $highCount     = @($violationResults | Where-Object { $_.Severity -eq 'High' }).Count
    $mediumCount   = @($violationResults | Where-Object { $_.Severity -eq 'Medium' }).Count
    $warningCount  = @($violationResults | Where-Object { $_.Severity -eq 'Warning' }).Count

    $summary = [PSCustomObject]@{
        RunId                 = $runId
        TotalAgentsScanned    = $uniqueAgentIds
        TotalEnvironments     = $uniqueEnvironments
        TotalFlowsScanned     = $totalFlowResults
        FlowsWithHitl         = $flowsWithHitl
        FlowsMissingHitl      = $flowsMissingHitl
        CompliantAgents       = $compliantAgentCount
        ViolationCount        = $violationAgentCount
        CriticalCount         = $criticalCount
        HighCount             = $highCount
        MediumCount           = $mediumCount
        WarningCount          = $warningCount
        ScanTimestamp         = (Get-Date).ToUniversalTime().ToString('o')
        DryRun                = $WhatIfPreference
    }

    # Determine overall status
    $overallStatus = 'Passed'
    if ($criticalCount -gt 0) {
        $overallStatus = 'Critical'
    } elseif ($highCount -gt 0) {
        $overallStatus = 'Failed'
    } elseif ($mediumCount -gt 0 -or $warningCount -gt 0) {
        $overallStatus = 'Review'
    }

    #endregion

    #region Summary Banner

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  HITL Workflow Compliance Scan" -ForegroundColor Cyan
    Write-Host "  Controls 2.12 / 2.17 / 1.10" -ForegroundColor Gray
    Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC" -ForegroundColor Gray
    Write-Host "  RunId: $runId" -ForegroundColor Gray
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    # Overall status
    $statusColor = switch ($overallStatus) {
        'Critical' { 'Red' }
        'Failed'   { 'Red' }
        'Review'   { 'Yellow' }
        'Passed'   { 'Green' }
        default    { 'White' }
    }
    Write-Host "Overall Status: " -NoNewline
    Write-Host $overallStatus -ForegroundColor $statusColor
    Write-Host ""

    Write-Host "Environments scanned: $($summary.TotalEnvironments)"
    Write-Host "Agents scanned:       $($summary.TotalAgentsScanned)"
    Write-Host "Total flows:          $($summary.TotalFlowsScanned)"
    Write-Host "  With HITL:          $($summary.FlowsWithHitl)" -ForegroundColor Green
    Write-Host "  Missing HITL:       $($summary.FlowsMissingHitl)" -ForegroundColor $(if ($summary.FlowsMissingHitl -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "Compliant agents:     $($summary.CompliantAgents)" -ForegroundColor Green
    Write-Host "Agents w/ violations: $($summary.ViolationCount)" -ForegroundColor $(if ($summary.ViolationCount -gt 0) { 'Red' } else { 'Green' })

    if ($summary.CriticalCount -gt 0) {
        Write-Host "  CRITICAL:           $($summary.CriticalCount)" -ForegroundColor DarkRed
    }
    if ($summary.HighCount -gt 0) {
        Write-Host "  HIGH:               $($summary.HighCount)" -ForegroundColor Red
    }
    if ($summary.MediumCount -gt 0) {
        Write-Host "  MEDIUM:             $($summary.MediumCount)" -ForegroundColor Yellow
    }
    if ($summary.WarningCount -gt 0) {
        Write-Host "  WARNING:            $($summary.WarningCount)" -ForegroundColor DarkYellow
    }

    if ($WhatIfPreference) {
        Write-Host ""
        Write-Host "[DRY RUN] No data persisted. Re-run without -WhatIf to persist results." -ForegroundColor Gray
    }

    Write-Host ""

    #endregion

    #region Persist Results to Dataverse

    if ($PersistResults -and $dataverseConnected) {
        $environmentNameList = ($agentSettings | Select-Object -Property EnvironmentName -Unique |
            ForEach-Object { $_.EnvironmentName }) -join ', '

        $validationSummary = @{
            OverallStatus        = $overallStatus
            TotalAgents          = $uniqueAgentIds
            TotalFlows           = $totalFlowResults
            FlowsWithHitl        = $flowsWithHitl
            CompliantCount       = $compliantAgentCount
            ViolationCount       = $violationAgentCount
            EnvironmentsScanned  = $uniqueEnvironments
        }

        if ($PSCmdlet.ShouldProcess("Dataverse validation history", "Write HITL scan results")) {
            try {
                Write-HitlScanRun -ValidationResult $validationSummary -RunId $runId
                Write-Verbose "Validation history written with RunId: $runId"
            } catch {
                Write-Warning "Failed to write validation history: $($_.Exception.Message)"
            }
        }

        # Write individual violations
        foreach ($agentResult in $violationResults) {
            foreach ($violation in $agentResult.Violations) {
                if ($PSCmdlet.ShouldProcess("$($agentResult.AgentName) flow $($violation.FlowName)", "Write violation")) {
                    try {
                        $violationData = @{
                            EnvironmentGuid    = $agentResult.EnvironmentGuid
                            EnvironmentName    = $agentResult.EnvironmentName
                            AgentId            = $agentResult.AgentId
                            AgentName          = $agentResult.AgentName
                            Zone               = $agentResult.Zone
                            FlowName           = $violation.FlowName
                            FlowId             = $violation.FlowId
                            CheckpointType     = $violation.CheckpointType
                            ViolationType      = $violation.ViolationType
                            Severity           = $violation.Severity
                            Details            = $violation.Details
                            RegulatoryContext   = $violation.RegulatoryContext
                        }
                        Write-HitlViolation -Violation $violationData -RunId $runId
                    } catch {
                        Write-Warning "Failed to write violation for $($agentResult.AgentName): $($_.Exception.Message)"
                    }
                }
            }
        }

        Write-Host "Results persisted to Dataverse (RunId: $runId, Violations: $($violationResults.Count))" -ForegroundColor Green
    } elseif ($PersistResults -and -not $dataverseConnected) {
        Write-Warning "PersistResults requested but Dataverse not connected. Results not persisted."
    }

    #endregion

    #region Format Output

    $outputResults = if ($IncludeCompliant) {
        $complianceResults.ToArray()
    } else {
        @($complianceResults | Where-Object { -not $_.IsCompliant })
    }

    switch ($OutputFormat) {
        'Table' {
            if ($outputResults.Count -gt 0) {
                Write-Host "-----------------------------------------" -ForegroundColor Gray
                Write-Host "Agent Compliance Details:" -ForegroundColor White
                Write-Host "-----------------------------------------" -ForegroundColor Gray

                foreach ($agent in $outputResults) {
                    $severityColor = switch ($agent.Severity) {
                        'Critical' { 'DarkRed' }
                        'High'     { 'Red' }
                        'Medium'   { 'Yellow' }
                        'Warning'  { 'DarkYellow' }
                        'Low'      { 'Gray' }
                        default    { 'Green' }
                    }

                    Write-Host ""
                    if ($agent.IsCompliant) {
                        Write-Host "  [OK] " -NoNewline -ForegroundColor Green
                    } else {
                        Write-Host "  [$($agent.Severity)] " -NoNewline -ForegroundColor $severityColor
                    }
                    Write-Host "$($agent.AgentName)" -ForegroundColor White

                    Write-Host "    Environment:      $($agent.EnvironmentName)" -ForegroundColor Gray
                    Write-Host "    Zone:             $($agent.Zone)" -ForegroundColor Gray
                    Write-Host "    Total Flows:      $($agent.TotalFlows)" -ForegroundColor Gray
                    Write-Host "    With HITL:        $($agent.FlowsWithHitl)" -ForegroundColor Gray
                    Write-Host "    Missing HITL:     $($agent.FlowsMissingHitl)" -ForegroundColor Gray
                    Write-Host "    Status:           $($agent.AgentStatus)" -ForegroundColor Gray

                    if (-not $agent.IsCompliant -and $agent.Violations) {
                        foreach ($v in $agent.Violations) {
                            $vColor = switch ($v.Severity) {
                                'Critical' { 'DarkRed' }
                                'High'     { 'Red' }
                                'Medium'   { 'Yellow' }
                                default    { 'DarkYellow' }
                            }
                            Write-Host "    Violation:        $($v.ViolationType) - $($v.Details)" -ForegroundColor $vColor
                        }
                        if ($agent.RegulatoryContext) {
                            Write-Host "    Regulatory:       $($agent.RegulatoryContext)" -ForegroundColor $severityColor
                        }
                    }
                }
                Write-Host ""
            } else {
                Write-Host "No violations found. All scanned agents have proper HITL checkpoints." -ForegroundColor Green
                Write-Host ""
            }

            Write-Host "==========================================" -ForegroundColor Cyan
        }
        'Json' {
            @{
                metadata = @{
                    RunId                 = $summary.RunId
                    TotalAgentsScanned    = $summary.TotalAgentsScanned
                    TotalEnvironments     = $summary.TotalEnvironments
                    TotalFlowsScanned     = $summary.TotalFlowsScanned
                    FlowsWithHitl         = $summary.FlowsWithHitl
                    FlowsMissingHitl      = $summary.FlowsMissingHitl
                    CompliantAgents       = $summary.CompliantAgents
                    ViolationCount        = $summary.ViolationCount
                    CriticalCount         = $summary.CriticalCount
                    HighCount             = $summary.HighCount
                    MediumCount           = $summary.MediumCount
                    WarningCount          = $summary.WarningCount
                    ScanTimestamp         = $summary.ScanTimestamp
                    DryRun                = $summary.DryRun
                    OverallStatus         = $overallStatus
                    Controls              = @('2.12', '2.17', '1.10')
                }
                results = @($outputResults | ForEach-Object {
                    @{
                        AgentId            = $_.AgentId
                        AgentName          = $_.AgentName
                        EnvironmentName    = $_.EnvironmentName
                        Zone               = $_.Zone
                        TotalFlows         = $_.TotalFlows
                        FlowsWithHitl      = $_.FlowsWithHitl
                        FlowsMissingHitl   = $_.FlowsMissingHitl
                        HasHitlCheckpoint  = $_.HasHitlCheckpoint
                        IsCompliant        = $_.IsCompliant
                        Severity           = $_.Severity
                        ViolationCount     = $_.ViolationCount
                        Violations         = @($_.Violations | ForEach-Object {
                            @{
                                ViolationType    = $_.ViolationType
                                Severity         = $_.Severity
                                FlowName         = $_.FlowName
                                CheckpointType   = $_.CheckpointType
                                Details          = $_.Details
                            }
                        })
                        RegulatoryContext   = $_.RegulatoryContext
                        AgentStatus        = $_.AgentStatus
                    }
                })
            } | ConvertTo-Json -Depth 7
        }
        'Object' {
            $outputResults
        }
    }

    #endregion
}
