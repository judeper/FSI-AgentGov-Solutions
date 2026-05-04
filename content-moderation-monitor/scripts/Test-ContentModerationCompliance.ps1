<#
.SYNOPSIS
    Validates content moderation levels for all Copilot Studio agents against
    zone-specific governance requirements.

.DESCRIPTION
    Orchestrates a full content moderation compliance scan:
    1. Enumerates Power Platform environments
    2. Queries each environment's Dataverse for Copilot Studio agents
    3. Retrieves content moderation level for each agent
    4. Validates against zone requirements (Zone 1: Medium min, Zone 2/3: High)
    5. Reports violations with severity classification and regulatory context

    This is the primary validation script for the Content Moderation Governance
    Monitor (v7). Unlike the Agent Access Monitor (v6) which validates
    environment-level settings, this script validates per-agent content
    moderation configuration.

    Combines Get-AgentModerationSettings and Compare-ModerationCompliance into
    a single validation workflow with dry-run mode, multiple output formats,
    summary statistics, and environment/agent filtering.

.NOTES
    File: Test-ContentModerationCompliance.ps1
    Version: 1.0.0
    Solution: Content Moderation Monitor (v7)
    Controls: 1.27 (Primary), 1.8 (Complementary)
    Regulations: FINRA 3110, GLBA 501(b), SOX 404

    Part of FSI Agent Governance Framework
#>

#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

function Test-ContentModerationCompliance {
    <#
    .SYNOPSIS
        Validates content moderation levels for all Copilot Studio agents against
        zone-specific governance requirements.

    .DESCRIPTION
        Orchestrates a full content moderation compliance scan:
        1. Enumerates Power Platform environments
        2. Queries each environment's Dataverse for Copilot Studio agents
        3. Retrieves content moderation level for each agent
        4. Validates against zone requirements (Zone 1: Medium min, Zone 2/3: High)
        5. Reports violations with severity classification and regulatory context

        This is the primary validation script for the Content Moderation Governance
        Monitor (v7). Unlike the Agent Access Monitor (v6) which validates
        environment-level settings, this script validates per-agent content
        moderation configuration.

    .PARAMETER WhatIf
        Preview mode - shows what violations would be reported without persisting
        to Dataverse or triggering alerts. Always safe to run. (CMV-04)

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
        Include draft/unpublished agents (default: published only). (CMV-05)

    .PARAMETER IncludeCompliant
        Include compliant agents in output (default: violations only).

    .PARAMETER DataverseUrl
        Optional ELM Dataverse URL for zone classification lookup. (CMV-06)
        When provided with -PersistResults, also reads operational parameters
        from Dataverse environment variables and persists scan results.

    .PARAMETER DataverseToken
        Pre-obtained access token for Dataverse authentication. When provided
        with -DataverseUrl, uses this token instead of interactive auth.

    .PARAMETER PersistResults
        When specified with -DataverseUrl, writes validation summary to
        fsi_moderationvalidationhistory and individual violations to
        fsi_moderationviolations. Requires active Dataverse connection.

    .PARAMETER BaselinePath
        Path to moderation-baseline.json override.

    .PARAMETER Top
        Limit total agents processed (safety cap for large tenants).
        Default 0 means no limit.

    .EXAMPLE
        . ./Test-ContentModerationCompliance.ps1
        Test-ContentModerationCompliance -WhatIf

        Dry-run scan of all environments (default: published agents, violations only).

    .EXAMPLE
        . ./Test-ContentModerationCompliance.ps1
        Test-ContentModerationCompliance -IncludeEnvironments @("env-id-1", "env-id-2") -OutputFormat Json

        Scan specific environments with JSON output for evidence pipeline.

    .EXAMPLE
        . ./Test-ContentModerationCompliance.ps1
        Test-ContentModerationCompliance -IncludeCompliant -IncludeDrafts

        Full scan including compliant agents and drafts.

    .EXAMPLE
        . ./Test-ContentModerationCompliance.ps1
        Test-ContentModerationCompliance -ExcludeSandbox -ExcludeTrial -DataverseUrl "https://org.crm.dynamics.com"

        Production scan excluding sandbox/trial, using ELM for zone lookup.

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
        [string]$BaselinePath,

        [Parameter()]
        [int]$Top = 0
    )

    #region Script Initialization

    $ErrorActionPreference = 'Stop'
    $scriptRoot = $PSScriptRoot

    Write-Verbose "========================================="
    Write-Verbose "Content Moderation Governance Monitor v1.0.0"
    Write-Verbose "========================================="

    #endregion

    #region Import Dependencies

    # Dot-source companion scripts to load their functions
    $getSettingsScript = Join-Path $scriptRoot 'Get-AgentModerationSettings.ps1'
    $compareComplianceScript = Join-Path $scriptRoot 'Compare-ModerationCompliance.ps1'

    if (-not (Test-Path $getSettingsScript)) {
        throw "Required script not found: $getSettingsScript"
    }

    if (-not (Test-Path $compareComplianceScript)) {
        throw "Required script not found: $compareComplianceScript"
    }

    Write-Verbose "Loading Get-AgentModerationSettings from: $getSettingsScript"
    . $getSettingsScript

    Write-Verbose "Loading Compare-ModerationCompliance from: $compareComplianceScript"
    . $compareComplianceScript

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
    if ($BaselinePath) {
        Write-Verbose "  BaselinePath:       $BaselinePath"
    }

    #endregion

    #region Dataverse Integration

    $dataverseConnected = $false

    if ($DataverseUrl) {
        try {
            Import-Module "$scriptRoot\private\CMMClient.psm1" -Force

            if ($DataverseToken) {
                Connect-CMMDataverse -DataverseUrl $DataverseUrl -AccessToken $DataverseToken
            } else {
                Connect-CMMDataverse -DataverseUrl $DataverseUrl
            }

            $connection = Get-CMMConnection
            if ($connection.IsConnected) {
                $dataverseConnected = $true
                Write-Verbose "Connected to Dataverse: $DataverseUrl"

                # Read operational parameters from Dataverse env vars
                # Rule: explicit parameter values always override Dataverse values
                $dvGracePeriod = Get-CMMEnvironmentVariable -Name 'GracePeriodHours' -DefaultValue $null
                if (-not $PSBoundParameters.ContainsKey('GracePeriodHours') -and $null -ne $dvGracePeriod) {
                    $GracePeriodHours = [int]$dvGracePeriod
                    Write-Verbose "GracePeriodHours from Dataverse: $GracePeriodHours"
                }

                $dvIncludeDrafts = Get-CMMEnvironmentVariable -Name 'IncludeDrafts' -DefaultValue $null
                if (-not $PSBoundParameters.ContainsKey('IncludeDrafts') -and $null -ne $dvIncludeDrafts -and $dvIncludeDrafts -eq 'true') {
                    $IncludeDrafts = [switch]::Present
                    Write-Verbose "IncludeDrafts from Dataverse: true"
                }

                $dvIncludeSandbox = Get-CMMEnvironmentVariable -Name 'IncludeSandbox' -DefaultValue $null
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

    #region Build Parameters

    # Build parameter hashtable for Get-AgentModerationSettings
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

    # Build parameter hashtable for Compare-ModerationCompliance
    $compareParams = @{}

    if ($IncludeCompliant) {
        $compareParams['IncludeCompliant'] = $true
    }
    if ($BaselinePath) {
        $compareParams['BaselinePath'] = $BaselinePath
    }

    #endregion

    #region Data Collection

    Write-Verbose "Querying agent content moderation settings..."

    if ($PSCmdlet.ShouldProcess("All Power Platform environments", "Query agent content moderation settings")) {
        $agentSettings = Get-AgentModerationSettings @queryParams
    } else {
        # WhatIf mode - still collect data for display (read-only operation)
        $agentSettings = Get-AgentModerationSettings @queryParams
    }

    if (-not $agentSettings -or $agentSettings.Count -eq 0) {
        Write-Warning "No agents found matching the specified criteria."

        Write-Host "`n=== Content Moderation Compliance Scan ===" -ForegroundColor Cyan
        Write-Host "Environments scanned: 0"
        Write-Host "Agents scanned:       0"
        Write-Host "No agents found to evaluate." -ForegroundColor Yellow
        if ($WhatIfPreference) {
            Write-Host "`n[DRY RUN] Preview mode - no data persisted." -ForegroundColor Gray
        }
        Write-Host "==========================================`n" -ForegroundColor Cyan

        switch ($OutputFormat) {
            'Json' {
                return @{
                    metadata = @{
                        TotalAgentsScanned   = 0
                        TotalEnvironments    = 0
                        CompliantAgents      = 0
                        ViolationCount       = 0
                        CriticalCount        = 0
                        HighCount            = 0
                        MediumCount          = 0
                        WarningCount         = 0
                        ScanTimestamp        = (Get-Date -Format 'o')
                        DryRun               = $WhatIfPreference
                    }
                    results = @()
                } | ConvertTo-Json -Depth 5
            }
            'Object' { return @() }
            'Table'  { return }
        }
    }

    Write-Verbose "Found $($agentSettings.Count) agent(s) across environments"

    #endregion

    #region Compliance Evaluation

    Write-Verbose "Comparing agent moderation levels against zone baselines..."

    $complianceResults = $agentSettings | Compare-ModerationCompliance @compareParams

    # Ensure results is always an array
    if ($null -eq $complianceResults) {
        $complianceResults = @()
    } elseif ($complianceResults -isnot [System.Array]) {
        $complianceResults = @($complianceResults)
    }

    #endregion

    #region Calculate Summary Statistics

    # Count unique environments from agent settings
    $uniqueEnvironments = ($agentSettings | Select-Object -Property EnvironmentId -Unique).Count

    # Count compliant and non-compliant
    $compliantResults = @($complianceResults | Where-Object { $_.IsCompliant })
    $violationResults = @($complianceResults | Where-Object { -not $_.IsCompliant })

    # If IncludeCompliant is false, complianceResults only contains violations
    # Calculate compliant count from total minus violations
    $compliantAgentCount = if ($IncludeCompliant) {
        $compliantResults.Count
    } else {
        $agentSettings.Count - $complianceResults.Count
    }

    $violationAgentCount = if ($IncludeCompliant) {
        $violationResults.Count
    } else {
        $complianceResults.Count
    }

    # Count violations by severity
    $criticalCount = @($violationResults | Where-Object { $_.Severity -eq 'Critical' }).Count
    $highCount     = @($violationResults | Where-Object { $_.Severity -eq 'High' }).Count
    $mediumCount   = @($violationResults | Where-Object { $_.Severity -eq 'Medium' }).Count
    $warningCount  = @($violationResults | Where-Object { $_.Severity -eq 'Warning' }).Count

    $summary = [PSCustomObject]@{
        TotalAgentsScanned   = $agentSettings.Count
        TotalEnvironments    = $uniqueEnvironments
        CompliantAgents      = $compliantAgentCount
        ViolationCount       = $violationAgentCount
        CriticalCount        = $criticalCount
        HighCount            = $highCount
        MediumCount          = $mediumCount
        WarningCount         = $warningCount
        ScanTimestamp        = (Get-Date -Format 'o')
        DryRun               = $WhatIfPreference
    }

    # Determine overall status
    $overallStatus = 'Passed'
    if ($criticalCount -gt 0) {
        $overallStatus = 'Failed'
    } elseif ($highCount -gt 0) {
        $overallStatus = 'Failed'
    } elseif ($mediumCount -gt 0 -or $warningCount -gt 0) {
        $overallStatus = 'Warning'
    }

    #endregion

    #region Summary Banner

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  Content Moderation Compliance Scan" -ForegroundColor Cyan
    Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    # Overall status
    $statusColor = switch ($overallStatus) {
        'Failed'   { 'Red' }
        'Warning'  { 'Yellow' }
        'Passed'   { 'Green' }
        default    { 'White' }
    }
    Write-Host "Overall Status: " -NoNewline
    Write-Host $overallStatus -ForegroundColor $statusColor
    Write-Host ""

    Write-Host "Environments scanned: $($summary.TotalEnvironments)"
    Write-Host "Agents scanned:       $($summary.TotalAgentsScanned)"
    Write-Host "Compliant:            $($summary.CompliantAgents)" -ForegroundColor Green
    Write-Host "Violations:           $($summary.ViolationCount)" -ForegroundColor $(if ($summary.ViolationCount -gt 0) { 'Red' } else { 'Green' })

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
        $runId = [guid]::NewGuid().ToString()

        # Collect unique environment names for the summary
        $environmentNameList = ($agentSettings | Select-Object -Property EnvironmentDisplayName -Unique |
            ForEach-Object { $_.EnvironmentDisplayName }) -join ', '

        # Write validation summary
        $validationSummary = @{
            OverallStatus        = $overallStatus
            TotalAgents          = $agentSettings.Count
            CompliantCount       = $compliantAgentCount
            ViolationCount       = $violationAgentCount
            EnvironmentsScanned  = $environmentNameList
        }

        if ($PSCmdlet.ShouldProcess("Dataverse validation history", "Write scan results")) {
            try {
                Write-ModerationValidationHistory -ValidationResult $validationSummary -RunId $runId
                Write-Verbose "Validation history written with RunId: $runId"
            } catch {
                Write-Warning "Failed to write validation history: $($_.Exception.Message)"
            }
        }

        # Write individual violations
        foreach ($violation in $violationResults) {
            if ($PSCmdlet.ShouldProcess("$($violation.AgentName) in $($violation.EnvironmentDisplayName)", "Write violation")) {
                try {
                    $violationData = @{
                        EnvironmentId          = $violation.EnvironmentId
                        EnvironmentDisplayName = $violation.EnvironmentDisplayName
                        AgentId                = $violation.AgentId
                        AgentName              = $violation.AgentName
                        Zone                   = $violation.Zone
                        ExpectedLevel          = $violation.ExpectedModerationLevel
                        ActualLevel            = $violation.CurrentModerationLevel
                        Severity               = $violation.Severity
                        RegulatoryContext      = $violation.RegulatoryContext
                    }
                    Write-ModerationViolation -Violation $violationData -RunId $runId
                } catch {
                    Write-Warning "Failed to write violation for $($violation.AgentName): $($_.Exception.Message)"
                }
            }
        }

        Write-Host "Results persisted to Dataverse (RunId: $runId, Violations: $($violationResults.Count))" -ForegroundColor Green
    } elseif ($PersistResults -and -not $dataverseConnected) {
        Write-Warning "PersistResults requested but Dataverse not connected. Results not persisted."
    }

    #endregion

    #region Format Output

    # Build output results based on IncludeCompliant flag
    $outputResults = if ($IncludeCompliant) {
        $complianceResults
    } else {
        $violationResults
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
                        default    { 'Green' }
                    }

                    Write-Host ""
                    if ($agent.IsCompliant) {
                        Write-Host "  [OK] " -NoNewline -ForegroundColor Green
                    } else {
                        Write-Host "  [$($agent.Severity)] " -NoNewline -ForegroundColor $severityColor
                    }
                    Write-Host "$($agent.AgentName)" -ForegroundColor White

                    Write-Host "    Environment:  $($agent.EnvironmentDisplayName)" -ForegroundColor Gray
                    Write-Host "    Zone:         $($agent.Zone)" -ForegroundColor Gray
                    Write-Host "    Moderation:   $($agent.CurrentModerationLevel)" -NoNewline -ForegroundColor Gray
                    if (-not $agent.IsCompliant) {
                        Write-Host " (expected: $($agent.ExpectedModerationLevel))" -ForegroundColor $severityColor
                    } else {
                        Write-Host " (meets: $($agent.ExpectedModerationLevel))" -ForegroundColor Green
                    }
                    Write-Host "    Status:       $($agent.AgentStatus)" -ForegroundColor Gray
                    if ($agent.RegulatoryContext) {
                        Write-Host "    Regulatory:   $($agent.RegulatoryContext)" -ForegroundColor $severityColor
                    }
                }
                Write-Host ""
            } else {
                Write-Host "No violations found. All scanned agents are compliant." -ForegroundColor Green
                Write-Host ""
            }

            Write-Host "==========================================" -ForegroundColor Cyan
        }
        'Json' {
            @{
                metadata = @{
                    TotalAgentsScanned   = $summary.TotalAgentsScanned
                    TotalEnvironments    = $summary.TotalEnvironments
                    CompliantAgents      = $summary.CompliantAgents
                    ViolationCount       = $summary.ViolationCount
                    CriticalCount        = $summary.CriticalCount
                    HighCount            = $summary.HighCount
                    MediumCount          = $summary.MediumCount
                    WarningCount         = $summary.WarningCount
                    ScanTimestamp        = $summary.ScanTimestamp
                    DryRun               = $summary.DryRun
                    OverallStatus        = $overallStatus
                }
                results = @($outputResults | ForEach-Object {
                    @{
                        AgentId                = $_.AgentId
                        AgentName              = $_.AgentName
                        EnvironmentDisplayName = $_.EnvironmentDisplayName
                        Zone                   = $_.Zone
                        CurrentModerationLevel = $_.CurrentModerationLevel
                        ExpectedModerationLevel = $_.ExpectedModerationLevel
                        IsCompliant            = $_.IsCompliant
                        Severity               = $_.Severity
                        RegulatoryContext      = $_.RegulatoryContext
                        AgentStatus            = $_.AgentStatus
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
