<#
.SYNOPSIS
    Validates action confirmation configuration for all Copilot Studio agents
    against zone-specific governance requirements.

.DESCRIPTION
    Orchestrates a full action confirmation compliance scan:
    1. Enumerates Power Platform environments
    2. Queries each environment's Dataverse for Copilot Studio agents
    3. Retrieves action invocation settings per agent
    4. Validates each action's confirmation status against zone policies
    5. Reports violations with severity classification and regulatory context

    This is the primary validation script for the Action Confirmation Auditor
    (ACA) solution. It validates per-agent action confirmation posture against
    zone-based governance policies defined by Control 2.12.

    Combines Get-AgentActionSettings and zone policy evaluation into a single
    validation workflow with dry-run mode, multiple output formats, summary
    statistics, and environment/agent filtering.

.NOTES
    File: Test-ActionConfirmationCompliance.ps1
    Version: 1.1.0
    Solution: Action Confirmation Auditor (ACA)
    Control: 2.12 (Human-in-the-Loop checkpoints for AI agent actions); supports 1.10 (Communication Compliance / FINRA 3110 supervision)
    Regulations: FINRA 3110, GLBA 501(b), SOX 404

    Part of FSI Agent Governance Framework
#>

#Requires -Version 5.1
#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

function Test-ActionConfirmationCompliance {
    <#
    .SYNOPSIS
        Validates action confirmation configuration for all Copilot Studio agents
        against zone-specific governance requirements.

    .DESCRIPTION
        Orchestrates a full action confirmation compliance scan across Power Platform
        environments. For each agent's actions, applies zone-specific confirmation
        policies and reports violations with appropriate severity.

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
        Include compliant agents in output (default: violations only).

    .PARAMETER DataverseUrl
        Optional ELM Dataverse URL for zone classification lookup.
        When provided with -PersistResults, also reads operational parameters
        from Dataverse environment variables and persists scan results.

    .PARAMETER DataverseToken
        Pre-obtained access token for Dataverse authentication.

    .PARAMETER PersistResults
        When specified with -DataverseUrl, writes validation summary to
        fsi_actionscanrun and individual violations to
        fsi_actionauditresults. Requires active Dataverse connection.

    .PARAMETER Top
        Limit total agents processed (safety cap for large tenants).
        Default 0 means no limit.

    .EXAMPLE
        . ./Test-ActionConfirmationCompliance.ps1
        Test-ActionConfirmationCompliance -WhatIf

        Dry-run scan of all environments (default: published agents, violations only).

    .EXAMPLE
        . ./Test-ActionConfirmationCompliance.ps1
        Test-ActionConfirmationCompliance -IncludeEnvironments @("env-id-1") -OutputFormat Json

        Scan specific environments with JSON output for evidence pipeline.

    .EXAMPLE
        . ./Test-ActionConfirmationCompliance.ps1
        Test-ActionConfirmationCompliance -IncludeCompliant -IncludeDrafts

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
        [switch]$PersistResults,

        [Parameter()]
        [int]$Top = 0
    )

    #region Script Initialization

    $ErrorActionPreference = 'Stop'
    $scriptRoot = $PSScriptRoot
    $runId = [guid]::NewGuid().ToString()

    Write-Verbose "========================================="
    Write-Verbose "Action Confirmation Auditor v1.1.0"
    Write-Verbose "RunId: $runId"
    Write-Verbose "========================================="

    #endregion

    #region Import Dependencies

    # Dot-source companion script to load Get-AgentActionSettings function
    $getSettingsScript = Join-Path $scriptRoot 'Get-AgentActionSettings.ps1'

    if (-not (Test-Path $getSettingsScript)) {
        throw "Required script not found: $getSettingsScript"
    }

    Write-Verbose "Loading Get-AgentActionSettings from: $getSettingsScript"
    . $getSettingsScript

    #endregion

    #region Action Category Classification Helper

    function Get-ActionCategory {
        <#
        .SYNOPSIS
            Classifies an action into a risk category based on type and HTTP method.
        .OUTPUTS
            String - One of: Write, Delete, Read, ExternalTransfer, Execute
        #>
        param(
            [Parameter(Mandatory)]
            [PSCustomObject]$Action
        )

        $actionType = $Action.ActionType
        $httpMethod = $Action.HttpMethod
        $actionName = if ($Action.ActionName) { $Action.ActionName.ToLower() } else { '' }
        $connectorName = if ($Action.ConnectorName) { $Action.ConnectorName.ToLower() } else { '' }

        # Delete detection
        if ($httpMethod -eq 'DELETE') { return 'Delete' }
        if ($actionName -match '(delete|remove|destroy|purge)') { return 'Delete' }

        # External transfer detection
        $externalConnectors = @('smtp', 'email', 'sharepoint', 'onedrive', 'blob', 'azureblob',
                                'outlook', 'sendgrid', 'teams', 'office365')
        foreach ($ec in $externalConnectors) {
            if ($connectorName -match $ec) { return 'ExternalTransfer' }
        }
        if ($actionName -match '(send|email|upload|export|transfer|share|post\s*to)') { return 'ExternalTransfer' }

        # Write detection
        if ($httpMethod -in @('POST', 'PUT', 'PATCH')) { return 'Write' }
        if ($actionName -match '(create|update|modify|set|add|insert|write|submit|approve|assign)') { return 'Write' }
        if ($actionType -eq 'CloudFlowAction' -and $actionName -match '(create|update)') { return 'Write' }

        # Read detection
        if ($httpMethod -eq 'GET') { return 'Read' }
        if ($actionName -match '(get|list|read|fetch|query|search|retrieve|lookup|find)') { return 'Read' }
        if ($actionType -eq 'ConnectorAction' -and $actionName -match '(get|list|read)') { return 'Read' }

        # Default: Execute (general-purpose action)
        return 'Execute'
    }

    function Get-ActionSeverity {
        <#
        .SYNOPSIS
            Determines violation severity based on zone policy and action category.
        #>
        param(
            [Parameter(Mandatory)]
            [PSCustomObject]$Policy,

            [Parameter(Mandatory)]
            [string]$ActionCategory
        )

        switch ($ActionCategory) {
            'Write'            { return $Policy.WriteDeleteSeverity }
            'Delete'           { return $Policy.WriteDeleteSeverity }
            'ExternalTransfer' { return $Policy.ExternalTransferSeverity }
            'Read'             { return $Policy.ReadSeverity }
            default            { return $Policy.DefaultSeverity }
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
            Import-Module "$scriptRoot\private\ACAClient.psm1" -Force

            if ($DataverseToken) {
                Connect-ACADataverse -DataverseUrl $DataverseUrl -AccessToken $DataverseToken
            } else {
                Connect-ACADataverse -DataverseUrl $DataverseUrl
            }

            $connection = Get-ACAConnection
            if ($connection.IsConnected) {
                $dataverseConnected = $true
                Write-Verbose "Connected to Dataverse: $DataverseUrl"

                # Read operational parameters from Dataverse env vars
                $dvGracePeriod = Get-ACAEnvironmentVariable -Name 'GracePeriodHours' -DefaultValue $null
                if (-not $PSBoundParameters.ContainsKey('GracePeriodHours') -and $null -ne $dvGracePeriod) {
                    $GracePeriodHours = [int]$dvGracePeriod
                    Write-Verbose "GracePeriodHours from Dataverse: $GracePeriodHours"
                }

                $dvIncludeDrafts = Get-ACAEnvironmentVariable -Name 'IncludeDrafts' -DefaultValue $null
                if (-not $PSBoundParameters.ContainsKey('IncludeDrafts') -and $null -ne $dvIncludeDrafts -and $dvIncludeDrafts -eq 'true') {
                    $IncludeDrafts = [switch]::Present
                    Write-Verbose "IncludeDrafts from Dataverse: true"
                }

                $dvIncludeSandbox = Get-ACAEnvironmentVariable -Name 'IncludeSandbox' -DefaultValue $null
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

    # Build parameter hashtable for Get-AgentActionSettings
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

    Write-Verbose "Querying agent action settings..."

    if ($PSCmdlet.ShouldProcess("All Power Platform environments", "Query agent action settings")) {
        $agentSettings = Get-AgentActionSettings @queryParams
    } else {
        # WhatIf mode - still collect data for display (read-only operation)
        $agentSettings = Get-AgentActionSettings @queryParams
    }

    if (-not $agentSettings -or $agentSettings.Count -eq 0) {
        Write-Warning "No agents found matching the specified criteria."

        Write-Host "`n=== Action Confirmation Compliance Scan ===" -ForegroundColor Cyan
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
                        RunId                = $runId
                        TotalAgentsScanned   = 0
                        TotalEnvironments    = 0
                        TotalActions         = 0
                        ActionsWithConfirm   = 0
                        ActionsMissingConfirm = 0
                        ViolationCount       = 0
                        CriticalCount        = 0
                        HighCount            = 0
                        MediumCount          = 0
                        WarningCount         = 0
                        ScanTimestamp        = (Get-Date).ToUniversalTime().ToString('o')
                        DryRun               = $WhatIfPreference
                        Control              = '2.12'
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

    Write-Verbose "Evaluating action confirmation compliance against zone policies..."

    $complianceResults = [System.Collections.Generic.List[PSCustomObject]]::new()
    $privateRoot = Join-Path $scriptRoot 'private'

    # Load exception records if Dataverse is connected
    $exceptions = @{}
    if ($dataverseConnected) {
        try {
            $exceptionRecords = Get-ActionConfirmationExceptions
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

    foreach ($agent in $agentSettings) {
        # Get zone policy for this agent's environment
        $policy = & (Join-Path $privateRoot 'Get-ExpectedConfirmationPolicy.ps1') -Zone $agent.Zone

        $agentViolations = @()
        $agentIsCompliant = $true

        foreach ($action in $agent.Actions) {
            # Skip actions with confirmed status
            if ($action.ConfirmationStatus -eq 'Present') { continue }

            # Classify action category
            $category = Get-ActionCategory -Action $action

            # Check if this action category requires confirmation in this zone
            $requiresConfirm = $false
            if ($policy.AdvisoryOnly) {
                # Zone is advisory-only -- include as warning but not violation
                $requiresConfirm = $false
            } elseif ($policy.RequiresConfirmation -contains $category -or
                      $policy.RequiresConfirmation -contains 'Execute') {
                $requiresConfirm = $true
            }

            # Check for exceptions (must be active, unexpired, and match zone)
            $exceptionKey = "$($agent.AgentId)|$($action.ActionName)"
            if ($exceptions.ContainsKey($exceptionKey)) {
                $exc = $exceptions[$exceptionKey]
                $isActive = $exc.IsActive -eq $true
                $isUnexpired = -not $exc.ExpiresAt -or ([datetime]$exc.ExpiresAt -gt (Get-Date).ToUniversalTime())
                $zoneMatches = -not $exc.Zone -or $exc.Zone -eq $agent.Zone
                if ($isActive -and $isUnexpired -and $zoneMatches) {
                    Write-Verbose "Exception found for $($agent.AgentName) action $($action.ActionName)"
                    continue
                }
            }

            # Determine severity
            $severity = Get-ActionSeverity -Policy $policy -ActionCategory $category

            if ($requiresConfirm -and $action.ConfirmationStatus -in @('Missing', 'Partial', 'UnableToDetermine')) {
                $agentIsCompliant = $false
                $agentViolations += [PSCustomObject]@{
                    ActionName         = $action.ActionName
                    ActionType         = $action.ActionType
                    ActionCategory     = $category
                    ConnectorName      = $action.ConnectorName
                    HttpMethod         = $action.HttpMethod
                    ConfirmationStatus = $action.ConfirmationStatus
                    TopicName          = $action.TopicName
                    Severity           = $severity
                    ViolationType      = "MissingConfirmation_$category"
                }
            } elseif ($policy.AdvisoryOnly -and $action.ConfirmationStatus -in @('Missing', 'Partial')) {
                # Advisory: include as warning for visibility
                $agentViolations += [PSCustomObject]@{
                    ActionName         = $action.ActionName
                    ActionType         = $action.ActionType
                    ActionCategory     = $category
                    ConnectorName      = $action.ConnectorName
                    HttpMethod         = $action.HttpMethod
                    ConfirmationStatus = $action.ConfirmationStatus
                    TopicName          = $action.TopicName
                    Severity           = 'Warning'
                    ViolationType      = "AdvisoryMissingConfirmation_$category"
                }
            }
        }

        # Build compliance result for this agent
        if (-not $agentIsCompliant -or $IncludeCompliant) {
            $complianceResults.Add([PSCustomObject]@{
                EnvironmentId              = $agent.EnvironmentId
                EnvironmentDisplayName     = $agent.EnvironmentDisplayName
                EnvironmentType            = $agent.EnvironmentType
                Zone                       = $agent.Zone
                AgentId                    = $agent.AgentId
                AgentName                  = $agent.AgentName
                AgentStatus                = $agent.AgentStatus
                TotalActions               = $agent.TotalActions
                ActionsWithConfirmation    = $agent.ActionsWithConfirmation
                ActionsMissingConfirmation = $agent.ActionsMissingConfirmation
                IsCompliant                = $agentIsCompliant
                Violations                 = $agentViolations
                ViolationCount             = $agentViolations.Count
                Severity                   = if ($agentViolations.Count -gt 0) {
                    # Use highest severity from violations
                    $sevOrder = @('Critical', 'High', 'Medium', 'Low', 'Warning')
                    $highestSev = 'Warning'
                    foreach ($s in $sevOrder) {
                        if ($agentViolations.Severity -contains $s) { $highestSev = $s; break }
                    }
                    $highestSev
                } else { 'None' }
                RegulatoryContext           = $policy.RegulatoryContext
                DataverseUrl               = $agent.DataverseUrl
                LastPublished              = $agent.LastPublished
            })
        }
    }

    #endregion

    #region Calculate Summary Statistics

    $uniqueEnvironments = ($agentSettings | Select-Object -Property EnvironmentId -Unique).Count
    $totalActions = ($agentSettings | Measure-Object -Property TotalActions -Sum).Sum
    $totalWithConfirm = ($agentSettings | Measure-Object -Property ActionsWithConfirmation -Sum).Sum
    $totalMissingConfirm = ($agentSettings | Measure-Object -Property ActionsMissingConfirmation -Sum).Sum

    $compliantResults = @($complianceResults | Where-Object { $_.IsCompliant })
    $violationResults = @($complianceResults | Where-Object { -not $_.IsCompliant })

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

    $criticalCount = @($violationResults | Where-Object { $_.Severity -eq 'Critical' }).Count
    $highCount     = @($violationResults | Where-Object { $_.Severity -eq 'High' }).Count
    $mediumCount   = @($violationResults | Where-Object { $_.Severity -eq 'Medium' }).Count
    $warningCount  = @($violationResults | Where-Object { $_.Severity -eq 'Warning' }).Count

    $summary = [PSCustomObject]@{
        RunId                 = $runId
        TotalAgentsScanned    = $agentSettings.Count
        TotalEnvironments     = $uniqueEnvironments
        TotalActions          = $totalActions
        ActionsWithConfirm    = $totalWithConfirm
        ActionsMissingConfirm = $totalMissingConfirm
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
        $overallStatus = 'Warning'
    }

    #endregion

    #region Summary Banner

    Write-Host ""
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host "  Action Confirmation Compliance Scan" -ForegroundColor Cyan
    Write-Host "  Control 2.12 - Human-in-the-Loop Checkpoints" -ForegroundColor Gray
    Write-Host "  $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') UTC" -ForegroundColor Gray
    Write-Host "  RunId: $runId" -ForegroundColor Gray
    Write-Host "==========================================" -ForegroundColor Cyan
    Write-Host ""

    # Overall status
    $statusColor = switch ($overallStatus) {
        'Critical' { 'Red' }
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
    Write-Host "Total actions:        $($summary.TotalActions)"
    Write-Host "  With confirmation:  $($summary.ActionsWithConfirm)" -ForegroundColor Green
    Write-Host "  Missing confirm:    $($summary.ActionsMissingConfirm)" -ForegroundColor $(if ($summary.ActionsMissingConfirm -gt 0) { 'Yellow' } else { 'Green' })
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
        $environmentNameList = ($agentSettings | Select-Object -Property EnvironmentDisplayName -Unique |
            ForEach-Object { $_.EnvironmentDisplayName }) -join ', '

        $validationSummary = @{
            OverallStatus               = $overallStatus
            TotalAgents                 = $agentSettings.Count
            TotalActions                = $totalActions
            ActionsWithConfirmation     = $totalWithConfirm
            ActionsMissingConfirmation  = $totalMissingConfirm
            ViolationCount              = $violationAgentCount
            EnvironmentsScanned         = $environmentNameList
        }

        if ($PSCmdlet.ShouldProcess("Dataverse validation history", "Write scan results")) {
            try {
                Write-ACAValidationHistory -ValidationResult $validationSummary -RunId $runId
                Write-Verbose "Validation history written with RunId: $runId"
            } catch {
                Write-Warning "Failed to write validation history: $($_.Exception.Message)"
            }
        }

        # Write individual violations
        foreach ($agentResult in $violationResults) {
            foreach ($violation in $agentResult.Violations) {
                if ($PSCmdlet.ShouldProcess("$($agentResult.AgentName) action $($violation.ActionName)", "Write violation")) {
                    try {
                        $violationData = @{
                            EnvironmentId          = $agentResult.EnvironmentId
                            EnvironmentDisplayName = $agentResult.EnvironmentDisplayName
                            AgentId                = $agentResult.AgentId
                            AgentName              = $agentResult.AgentName
                            Zone                   = $agentResult.Zone
                            ActionName             = $violation.ActionName
                            ActionType             = $violation.ActionType
                            ActionCategory         = $violation.ActionCategory
                            ConfirmationStatus     = $violation.ConfirmationStatus
                            ViolationType          = $violation.ViolationType
                            Severity               = $violation.Severity
                            TopicName              = $violation.TopicName
                            RegulatoryContext       = $agentResult.RegulatoryContext
                        }
                        Write-ACAViolation -Violation $violationData -RunId $runId
                    } catch {
                        Write-Warning "Failed to write violation for $($agentResult.AgentName): $($_.Exception.Message)"
                    }
                }
            }
        }

        Write-Output "Results persisted to Dataverse (RunId: $runId, Violations: $($violationResults.Count))"
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

                    Write-Host "    Environment:      $($agent.EnvironmentDisplayName)" -ForegroundColor Gray
                    Write-Host "    Zone:             $($agent.Zone)" -ForegroundColor Gray
                    Write-Host "    Total Actions:    $($agent.TotalActions)" -ForegroundColor Gray
                    Write-Host "    With Confirm:     $($agent.ActionsWithConfirmation)" -ForegroundColor Gray
                    Write-Host "    Missing Confirm:  $($agent.ActionsMissingConfirmation)" -ForegroundColor Gray
                    Write-Host "    Status:           $($agent.AgentStatus)" -ForegroundColor Gray

                    if (-not $agent.IsCompliant -and $agent.Violations) {
                        foreach ($v in $agent.Violations) {
                            $vColor = switch ($v.Severity) {
                                'Critical' { 'DarkRed' }
                                'High'     { 'Red' }
                                'Medium'   { 'Yellow' }
                                default    { 'DarkYellow' }
                            }
                            Write-Host "    Violation:        $($v.ViolationType) - $($v.ActionName) ($($v.ConfirmationStatus))" -ForegroundColor $vColor
                        }
                        if ($agent.RegulatoryContext) {
                            Write-Host "    Regulatory:       $($agent.RegulatoryContext)" -ForegroundColor $severityColor
                        }
                    }
                }
                Write-Host ""
            } else {
                Write-Host "No violations found. All scanned agents have proper action confirmations." -ForegroundColor Green
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
                    TotalActions          = $summary.TotalActions
                    ActionsWithConfirm    = $summary.ActionsWithConfirm
                    ActionsMissingConfirm = $summary.ActionsMissingConfirm
                    CompliantAgents       = $summary.CompliantAgents
                    ViolationCount        = $summary.ViolationCount
                    CriticalCount         = $summary.CriticalCount
                    HighCount             = $summary.HighCount
                    MediumCount           = $summary.MediumCount
                    WarningCount          = $summary.WarningCount
                    ScanTimestamp         = $summary.ScanTimestamp
                    DryRun                = $summary.DryRun
                    OverallStatus         = $overallStatus
                    Control               = '2.12'
                }
                results = @($outputResults | ForEach-Object {
                    @{
                        AgentId                    = $_.AgentId
                        AgentName                  = $_.AgentName
                        EnvironmentDisplayName     = $_.EnvironmentDisplayName
                        Zone                       = $_.Zone
                        TotalActions               = $_.TotalActions
                        ActionsWithConfirmation    = $_.ActionsWithConfirmation
                        ActionsMissingConfirmation = $_.ActionsMissingConfirmation
                        IsCompliant                = $_.IsCompliant
                        Severity                   = $_.Severity
                        ViolationCount             = $_.ViolationCount
                        Violations                 = @($_.Violations | ForEach-Object {
                            @{
                                ActionName         = $_.ActionName
                                ActionType         = $_.ActionType
                                ActionCategory     = $_.ActionCategory
                                ConfirmationStatus = $_.ConfirmationStatus
                                ViolationType      = $_.ViolationType
                                Severity           = $_.Severity
                                TopicName          = $_.TopicName
                            }
                        })
                        RegulatoryContext           = $_.RegulatoryContext
                        AgentStatus                = $_.AgentStatus
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
