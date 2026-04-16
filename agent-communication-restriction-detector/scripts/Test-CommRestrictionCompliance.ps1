<#
.SYNOPSIS
    Validates agent-to-agent communication against zone-specific governance
    requirements for multi-agent orchestration limits.

.DESCRIPTION
    Orchestrates a full communication restriction compliance scan:
    1. Enumerates Power Platform environments
    2. Queries each environment's Dataverse for Copilot Studio agents
    3. Retrieves skill registrations per agent (target agent references)
    4. Loads approved communication routes from Dataverse
    5. Pipes registrations to Compare-CommRestrictionCompliance for policy evaluation
    6. Reports violations with severity classification and regulatory context

    This is the primary validation script for the Agent Communication Restriction
    Detector (ACRD) solution. It validates per-agent communication patterns
    against zone-based governance policies defined by Control 2.17.

    Combines Get-AgentSkillRegistrations and Compare-CommRestrictionCompliance
    into a single validation workflow with dry-run mode, multiple output formats,
    summary statistics, and environment/agent filtering.

.NOTES
    File: Test-CommRestrictionCompliance.ps1
    Version: 1.0.1
    Solution: Agent Communication Restriction Detector (ACRD)
    Control: 2.17 (Multi-Agent Orchestration Limits)
    Regulations: FINRA 3110, GLBA 501(b), SOX 404

    Part of FSI Agent Governance Framework
#>

#Requires -Version 7.0
#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

function Test-CommRestrictionCompliance {
    <#
    .SYNOPSIS
        Validates agent-to-agent communication against zone-specific governance
        requirements for multi-agent orchestration limits.

    .DESCRIPTION
        Orchestrates a full communication restriction compliance scan:
        1. Enumerates Power Platform environments
        2. Queries each environment's Dataverse for Copilot Studio agents
        3. Retrieves skill registrations per agent
        4. Loads approved communication routes from Dataverse
        5. Pipes to Compare-CommRestrictionCompliance for policy evaluation
        6. Reports violations with severity classification

    .PARAMETER WhatIf
        Preview mode - shows what violations would be reported without persisting
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
        Include compliant skill registrations in output (default: violations only).

    .PARAMETER DataverseUrl
        Optional ELM Dataverse URL for zone classification lookup.
        When provided with -PersistResults, also reads operational parameters
        from Dataverse environment variables and persists scan results.

    .PARAMETER DataverseToken
        Pre-obtained access token for Dataverse authentication. When provided
        with -DataverseUrl, uses this token instead of interactive auth.

    .PARAMETER PersistResults
        When specified with -DataverseUrl, writes scan summary to
        fsi_commscanrun and individual violations to
        fsi_agentcommviolations. Requires active Dataverse connection.

    .PARAMETER Top
        Limit total skill registrations processed (safety cap for large tenants).
        Default 0 means no limit.

    .EXAMPLE
        . ./Test-CommRestrictionCompliance.ps1
        Test-CommRestrictionCompliance -WhatIf

        Dry-run scan of all environments (default: published agents, violations only).

    .EXAMPLE
        . ./Test-CommRestrictionCompliance.ps1
        Test-CommRestrictionCompliance -IncludeEnvironments @("env-id-1", "env-id-2") -OutputFormat Json

        Scan specific environments with JSON output for evidence pipeline.

    .EXAMPLE
        . ./Test-CommRestrictionCompliance.ps1
        Test-CommRestrictionCompliance -ExcludeSandbox -ExcludeTrial -DataverseUrl "https://org.crm.dynamics.com" -PersistResults

        Production scan excluding sandbox/trial, using ELM for zone lookup, persisting results.

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
        [switch]$PersistResults,

        [Parameter()]
        [int]$Top = 0
    )

    #region Script Initialization

    $ErrorActionPreference = 'Stop'
    $scriptRoot = $PSScriptRoot
    $runId = [guid]::NewGuid().ToString()

    Write-Verbose "========================================="
    Write-Verbose "Agent Communication Restriction Detector v1.0.0"
    Write-Verbose "RunId: $runId"
    Write-Verbose "========================================="

    #endregion

    #region Import Dependencies

    # Dot-source companion scripts to load their functions
    $getRegistrationsScript = Join-Path $scriptRoot 'Get-AgentSkillRegistrations.ps1'
    $compareComplianceScript = Join-Path $scriptRoot 'Compare-CommRestrictionCompliance.ps1'

    foreach ($requiredScript in @($getRegistrationsScript, $compareComplianceScript)) {
        if (-not (Test-Path $requiredScript)) {
            throw "Required script not found: $requiredScript"
        }
    }

    Write-Verbose "Loading Get-AgentSkillRegistrations from: $getRegistrationsScript"
    . $getRegistrationsScript

    Write-Verbose "Loading Compare-CommRestrictionCompliance from: $compareComplianceScript"
    . $compareComplianceScript

    # Import private modules
    $privateRoot = Join-Path $scriptRoot 'private'
    . (Join-Path $privateRoot 'Test-ParameterValidation.ps1')

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
    $approvedRoutes = @()
    $commExceptions = @()

    if ($DataverseUrl) {
        try {
            Import-Module (Join-Path $privateRoot 'ACRDClient.psm1') -Force

            if ($DataverseToken) {
                Connect-ACRDDataverse -DataverseUrl $DataverseUrl -AccessToken $DataverseToken
            } else {
                Connect-ACRDDataverse -DataverseUrl $DataverseUrl
            }

            $connection = Get-ACRDConnection
            if ($connection.IsConnected) {
                $dataverseConnected = $true
                Write-Verbose "Connected to Dataverse: $DataverseUrl"

                # Read operational parameters from Dataverse env vars
                # Rule: explicit parameter values always override Dataverse values
                $dvGracePeriod = Get-ACRDEnvironmentVariable -Name 'GracePeriodHours' -DefaultValue $null
                if (-not $PSBoundParameters.ContainsKey('GracePeriodHours') -and $null -ne $dvGracePeriod) {
                    $GracePeriodHours = [int]$dvGracePeriod
                    Write-Verbose "GracePeriodHours from Dataverse: $GracePeriodHours"
                }

                $dvIncludeDrafts = Get-ACRDEnvironmentVariable -Name 'IncludeDrafts' -DefaultValue $null
                if (-not $PSBoundParameters.ContainsKey('IncludeDrafts') -and $null -ne $dvIncludeDrafts -and $dvIncludeDrafts -eq 'true') {
                    $IncludeDrafts = [switch]::Present
                    Write-Verbose "IncludeDrafts from Dataverse: true"
                }

                $dvIncludeSandbox = Get-ACRDEnvironmentVariable -Name 'IncludeSandbox' -DefaultValue $null
                if (-not $PSBoundParameters.ContainsKey('ExcludeSandbox') -and $null -ne $dvIncludeSandbox -and $dvIncludeSandbox -eq 'true') {
                    $ExcludeSandbox = $false
                    Write-Verbose "IncludeSandbox from Dataverse: true (ExcludeSandbox overridden)"
                }

                # Load approved communication routes
                Write-Verbose "Loading approved communication routes..."
                $approvedRoutes = Get-ApprovedCommRoutes -ActiveOnly
                Write-Verbose "Loaded $($approvedRoutes.Count) approved route(s)"

                # Load active exceptions
                Write-Verbose "Loading active communication exceptions..."
                $commExceptions = Get-CommExceptions -ActiveOnly
                Write-Verbose "Loaded $($commExceptions.Count) active exception(s)"
            }
        } catch {
            Write-Warning "Dataverse connection failed: $($_.Exception.Message). Continuing in standalone mode."
        }
    }

    #endregion

    #region Build Query Parameters

    # Build parameter hashtable for Get-AgentSkillRegistrations
    $queryParams = @{
        GracePeriodHours = $GracePeriodHours
    }

    if ($IncludeEnvironments) {
        $queryParams['IncludeEnvironments'] = $IncludeEnvironments
    }
    if ($ExcludeEnvironments) {
        $queryParams['ExcludeEnvironments'] = $ExcludeEnvironments
    }
    if ($ExcludeSandbox) {
        $queryParams['ExcludeSandbox'] = $true
    }
    if ($ExcludeTrial) {
        $queryParams['ExcludeTrial'] = $true
    }
    if ($ExcludeDefault) {
        $queryParams['ExcludeDefault'] = $true
    }
    if ($IncludeDrafts) {
        $queryParams['IncludeDrafts'] = $true
    }
    if ($DataverseUrl) {
        $queryParams['DataverseUrl'] = $DataverseUrl
    }
    if ($Top -gt 0) {
        $queryParams['Top'] = $Top
    }

    #endregion

    #region Data Collection

    Write-Verbose "Querying agent skill registrations..."

    if ($PSCmdlet.ShouldProcess("All Power Platform environments", "Query agent skill registrations")) {
        $skillRegistrations = Get-AgentSkillRegistrations @queryParams
    } else {
        # WhatIf mode - still collect data for display (read-only operation)
        $skillRegistrations = Get-AgentSkillRegistrations @queryParams
    }

    if (-not $skillRegistrations -or $skillRegistrations.Count -eq 0) {
        Write-Warning "No skill registrations found matching the specified criteria."

        Write-Host ""
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host "  Agent Communication Restriction Scan" -ForegroundColor Cyan
        Write-Host "  Control 2.17 - Multi-Agent Orchestration Limits" -ForegroundColor Gray
        Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC" -ForegroundColor Gray
        Write-Host "  RunId: $runId" -ForegroundColor Gray
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Environments scanned: 0"
        Write-Host "Skill registrations:  0"
        Write-Host "No agent-to-agent communications found to evaluate." -ForegroundColor Yellow
        if ($WhatIfPreference) {
            Write-Host ""
            Write-Host "[DRY RUN] Preview mode - no data persisted." -ForegroundColor Gray
        }
        Write-Host ""
        Write-Host "==========================================" -ForegroundColor Cyan

        switch ($OutputFormat) {
            'Json' {
                return @{
                    metadata = @{
                        RunId              = $runId
                        TotalSkillsScanned = 0
                        TotalEnvironments  = 0
                        TotalAgents        = 0
                        CompliantSkills    = 0
                        ViolationCount     = 0
                        CriticalCount      = 0
                        HighCount          = 0
                        MediumCount        = 0
                        WarningCount       = 0
                        OverallStatus      = 'Passed'
                        ScanTimestamp      = (Get-Date).ToUniversalTime().ToString('o')
                        DryRun             = $WhatIfPreference
                        Control            = '2.17'
                    }
                    results = @()
                } | ConvertTo-Json -Depth 5
            }
            'Object' { return @() }
            'Table'  { return }
        }
    }

    Write-Verbose "Found $($skillRegistrations.Count) skill registration(s) across environments"

    #endregion

    #region Build Agent Owner Map for Maker/Checker

    # Pre-build owner map from all collected registrations so Compare-
    # CommRestrictionCompliance can perform maker/checker checks
    $agentOwnerMap = @{}
    foreach ($reg in $skillRegistrations) {
        if ($reg.AgentId -and $reg.OwnerId -and -not $agentOwnerMap.ContainsKey($reg.AgentId)) {
            $agentOwnerMap[$reg.AgentId] = $reg.OwnerId
        }
    }

    Write-Verbose "Agent owner map built: $($agentOwnerMap.Count) agent(s)"

    #endregion

    #region Compliance Evaluation via Pipeline

    Write-Verbose "Evaluating skill registrations against zone communication policies..."

    # Build parameters for Compare-CommRestrictionCompliance
    $compareParams = @{
        ApprovedRoutes  = $approvedRoutes
        CommExceptions  = $commExceptions
        AgentOwnerMap   = $agentOwnerMap
    }

    if ($IncludeCompliant) {
        $compareParams['IncludeCompliant'] = $true
    }

    # Pipe skill registrations through the compliance evaluation pipeline
    $complianceResults = @($skillRegistrations | Compare-CommRestrictionCompliance @compareParams)

    Write-Verbose "Compliance evaluation complete: $($complianceResults.Count) result(s) emitted"

    #endregion

    #region Calculate Summary Statistics

    # Count unique environments and agents from skill registrations
    $uniqueEnvironments = ($skillRegistrations | Select-Object -Property EnvironmentId -Unique).Count
    $uniqueAgents = ($skillRegistrations | Select-Object -Property AgentId -Unique).Count

    # Separate violations from compliant results
    $violationResults = @($complianceResults | Where-Object { -not $_.IsCompliant })

    # Calculate compliant count: total registrations minus violations
    $compliantSkillCount = if ($IncludeCompliant) {
        @($complianceResults | Where-Object { $_.IsCompliant }).Count
    } else {
        $skillRegistrations.Count - $violationResults.Count
    }

    $violationSkillCount = $violationResults.Count

    # Count violations by severity
    $criticalCount = @($violationResults | Where-Object { $_.Severity -eq 'Critical' }).Count
    $highCount     = @($violationResults | Where-Object { $_.Severity -eq 'High' }).Count
    $mediumCount   = @($violationResults | Where-Object { $_.Severity -eq 'Medium' }).Count
    $warningCount  = @($violationResults | Where-Object { $_.Severity -eq 'Warning' }).Count

    $summary = [PSCustomObject]@{
        RunId              = $runId
        TotalSkillsScanned = $skillRegistrations.Count
        TotalEnvironments  = $uniqueEnvironments
        TotalAgents        = $uniqueAgents
        CompliantSkills    = $compliantSkillCount
        ViolationCount     = $violationSkillCount
        CriticalCount      = $criticalCount
        HighCount          = $highCount
        MediumCount        = $mediumCount
        WarningCount       = $warningCount
        ScanTimestamp      = (Get-Date).ToUniversalTime().ToString('o')
        DryRun             = $WhatIfPreference
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
    Write-Host "  Agent Communication Restriction Scan" -ForegroundColor Cyan
    Write-Host "  Control 2.17 - Multi-Agent Orchestration Limits" -ForegroundColor Gray
    Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC" -ForegroundColor Gray
    Write-Host "  RunId: $runId" -ForegroundColor Gray
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    # Overall status with color coding
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

    Write-Host "Environments scanned:     $($summary.TotalEnvironments)"
    Write-Host "Unique agents:            $($summary.TotalAgents)"
    Write-Host "Skill registrations:      $($summary.TotalSkillsScanned)"
    Write-Host "Compliant:                $($summary.CompliantSkills)" -ForegroundColor Green
    Write-Host "Violations:               $($summary.ViolationCount)" -ForegroundColor $(if ($summary.ViolationCount -gt 0) { 'Red' } else { 'Green' })

    if ($summary.CriticalCount -gt 0) {
        Write-Host "  CRITICAL:               $($summary.CriticalCount)" -ForegroundColor DarkRed
    }
    if ($summary.HighCount -gt 0) {
        Write-Host "  HIGH:                   $($summary.HighCount)" -ForegroundColor Red
    }
    if ($summary.MediumCount -gt 0) {
        Write-Host "  MEDIUM:                 $($summary.MediumCount)" -ForegroundColor Yellow
    }
    if ($summary.WarningCount -gt 0) {
        Write-Host "  WARNING:                $($summary.WarningCount)" -ForegroundColor DarkYellow
    }

    if ($dataverseConnected) {
        Write-Host "  Approved routes loaded: $($approvedRoutes.Count)" -ForegroundColor Gray
        Write-Host "  Active exceptions:      $($commExceptions.Count)" -ForegroundColor Gray
    }

    if ($WhatIfPreference) {
        Write-Host ""
        Write-Host "[DRY RUN] No data persisted. Re-run without -WhatIf to persist results." -ForegroundColor Gray
    }

    Write-Host ""

    #endregion

    #region Persist Results to Dataverse

    if ($PersistResults -and $dataverseConnected) {
        # Collect unique environment names for the summary
        $environmentNameList = ($skillRegistrations | Select-Object -Property EnvironmentDisplayName -Unique |
            ForEach-Object { $_.EnvironmentDisplayName }) -join ', '

        # Write scan run summary
        $scanSummary = @{
            OverallStatus       = $overallStatus
            TotalAgents         = $uniqueAgents
            TotalSkills         = $skillRegistrations.Count
            CompliantCount      = $compliantSkillCount
            ViolationCount      = $violationSkillCount
            EnvironmentsScanned = $environmentNameList
        }

        if ($PSCmdlet.ShouldProcess("Dataverse scan run history", "Write scan results")) {
            try {
                Write-ACRDScanRun -ScanResult $scanSummary -RunId $runId
                Write-Verbose "Scan run history written with RunId: $runId"
            } catch {
                Write-Warning "Failed to write scan run history: $($_.Exception.Message)"
            }
        }

        # Write individual violations
        foreach ($violation in $violationResults) {
            $violationLabel = "$($violation.AgentName) -> $($violation.TargetAgentName) in $($violation.EnvironmentDisplayName)"

            if ($PSCmdlet.ShouldProcess($violationLabel, "Write violation")) {
                try {
                    # Use the primary (highest-severity) violation type for the Dataverse record
                    $primaryViolationType = if ($violation.Violations -and $violation.Violations.Count -gt 0) {
                        ($violation.Violations | Select-Object -First 1).ViolationType
                    } else {
                        $violation.ViolationType
                    }

                    $violationData = @{
                        EnvironmentId          = $violation.EnvironmentId
                        EnvironmentDisplayName = $violation.EnvironmentDisplayName
                        CallingAgentId         = $violation.AgentId
                        CallingAgentName       = $violation.AgentName
                        TargetAgentId          = $violation.TargetAgentId
                        TargetAgentName        = $violation.TargetAgentName
                        SourceZone             = $violation.SourceZone
                        TargetZone             = $violation.TargetZone
                        ViolationType          = $primaryViolationType
                        ViolationStatus        = 'Open'
                        SkillName              = $violation.SkillName
                        TargetEnvironmentId    = $violation.TargetEnvironmentId
                        Severity               = $violation.Severity
                        RegulatoryContext       = $violation.RegulatoryContext
                    }
                    Write-ACRDViolation -Violation $violationData -RunId $runId
                } catch {
                    Write-Warning "Failed to write violation for $($violation.AgentName): $($_.Exception.Message)"
                }
            }
        }

        Write-Output "Results persisted to Dataverse (RunId: $runId, Violations: $($violationResults.Count))"
    } elseif ($PersistResults -and -not $dataverseConnected) {
        Write-Warning "PersistResults requested but Dataverse not connected. Results not persisted."
    }

    #endregion

    #region Format Output

    $outputResults = $complianceResults

    switch ($OutputFormat) {
        'Table' {
            if ($outputResults.Count -gt 0) {
                Write-Host "-----------------------------------------" -ForegroundColor Gray
                Write-Host "Communication Compliance Details:" -ForegroundColor White
                Write-Host "-----------------------------------------" -ForegroundColor Gray

                # Group by agent for cleaner display
                $groupedByAgent = $outputResults | Group-Object -Property AgentName

                foreach ($agentGroup in $groupedByAgent) {
                    $firstEntry = $agentGroup.Group[0]

                    # Agent header with color based on worst violation in group
                    $agentViolations = @($agentGroup.Group | Where-Object { -not $_.IsCompliant })
                    $agentHeaderColor = if ($agentViolations.Count -eq 0) {
                        'Green'
                    } else {
                        $worstSeverity = $agentViolations | ForEach-Object { $_.Severity } |
                            Sort-Object { @('Critical', 'High', 'Medium', 'Warning').IndexOf($_) } |
                            Select-Object -First 1
                        switch ($worstSeverity) {
                            'Critical' { 'DarkRed' }
                            'High'     { 'Red' }
                            'Medium'   { 'Yellow' }
                            'Warning'  { 'DarkYellow' }
                            default    { 'White' }
                        }
                    }

                    Write-Host ""
                    Write-Host "  Agent: $($agentGroup.Name)" -ForegroundColor $agentHeaderColor
                    Write-Host "    Environment: $($firstEntry.EnvironmentDisplayName) ($($firstEntry.SourceZone))" -ForegroundColor Gray

                    foreach ($entry in $agentGroup.Group) {
                        $severityColor = switch ($entry.Severity) {
                            'Critical' { 'DarkRed' }
                            'High'     { 'Red' }
                            'Medium'   { 'Yellow' }
                            'Warning'  { 'DarkYellow' }
                            default    { 'Green' }
                        }

                        if ($entry.IsCompliant) {
                            Write-Host "      [OK] " -NoNewline -ForegroundColor Green
                        } else {
                            Write-Host "      [$($entry.Severity)] " -NoNewline -ForegroundColor $severityColor
                        }

                        $targetLabel = if ($entry.TargetAgentName) { $entry.TargetAgentName } else { $entry.TargetAgentId }
                        Write-Host "$($entry.SkillName) -> $targetLabel" -ForegroundColor White

                        Write-Host "        Route:       $($entry.RouteType) ($($entry.SourceZone) -> $($entry.TargetZone))" -ForegroundColor Gray

                        if ($entry.IsCrossEnvironment) {
                            Write-Host "        Target Env:  $($entry.TargetEnvironmentId)" -ForegroundColor Gray
                        }

                        if (-not $entry.IsCompliant) {
                            Write-Host "        Violation:   $($entry.ViolationType)" -ForegroundColor $severityColor
                            Write-Host "        Policy:      $($entry.PolicyApplied)" -ForegroundColor $severityColor
                            if ($entry.RegulatoryContext) {
                                Write-Host "        Regulatory:  $($entry.RegulatoryContext)" -ForegroundColor $severityColor
                            }
                        }
                    }
                }
                Write-Host ""
            } else {
                Write-Host "No violations found. All scanned communications are compliant." -ForegroundColor Green
                Write-Host ""
            }

            Write-Host "==========================================" -ForegroundColor Cyan
        }
        'Json' {
            @{
                metadata = @{
                    RunId              = $summary.RunId
                    TotalSkillsScanned = $summary.TotalSkillsScanned
                    TotalEnvironments  = $summary.TotalEnvironments
                    TotalAgents        = $summary.TotalAgents
                    CompliantSkills    = $summary.CompliantSkills
                    ViolationCount     = $summary.ViolationCount
                    CriticalCount      = $summary.CriticalCount
                    HighCount          = $summary.HighCount
                    MediumCount        = $summary.MediumCount
                    WarningCount       = $summary.WarningCount
                    ScanTimestamp      = $summary.ScanTimestamp
                    DryRun             = $summary.DryRun
                    OverallStatus      = $overallStatus
                    Control            = '2.17'
                }
                results = @($outputResults | ForEach-Object {
                    @{
                        AgentId                = $_.AgentId
                        AgentName              = $_.AgentName
                        TargetAgentId          = $_.TargetAgentId
                        TargetAgentName        = $_.TargetAgentName
                        EnvironmentId          = $_.EnvironmentId
                        EnvironmentDisplayName = $_.EnvironmentDisplayName
                        SourceZone             = $_.SourceZone
                        TargetZone             = $_.TargetZone
                        SkillName              = $_.SkillName
                        RouteType              = $_.RouteType
                        IsCompliant            = $_.IsCompliant
                        Severity               = $_.Severity
                        ViolationType          = $_.ViolationType
                        PolicyApplied          = $_.PolicyApplied
                        RegulatoryContext       = $_.RegulatoryContext
                        IsCrossEnvironment     = $_.IsCrossEnvironment
                        IsCrossTenant          = $_.IsCrossTenant
                    }
                })
            } | ConvertTo-Json -Depth 5
        }
        'Object' {
            $outputResults
        }
    }

    #endregion
}
