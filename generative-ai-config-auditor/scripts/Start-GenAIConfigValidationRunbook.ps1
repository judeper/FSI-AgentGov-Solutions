#Requires -Version 7.4
#Requires -Modules @{ ModuleName="MSAL.PS"; ModuleVersion="4.37.0" }
#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

<#
.SYNOPSIS
    Azure Automation runbook wrapper for generative AI configuration compliance
    validation.

.DESCRIPTION
    Adapts Test-GenAIConfigCompliance.ps1 for Azure Automation execution context.
    This runbook provides non-interactive authentication, structured JSON output to
    the pipeline, and per-agent drift detection logic for downstream alerting.

    Key differences from interactive orchestrator:
    - Uses certificate-based authentication (no interactive prompts)
    - Scans all governance zones in a single run
    - Outputs JSON to pipeline (captured by Get-AzAutomationJobOutput)
    - Includes per-agent drift detection via Dataverse baseline comparison
    - Adds AlertRequired flag for Power Automate flow routing
    - No Write-Host (uses Write-Verbose for diagnostics)

    GAC drift detection operates at the agent level (50-500 agents) and compares
    AzureOpenAIEnabled, OrchestrationMode, and GenerativeAnswersNodeCount against
    baseline values. A batch baseline query optimization (single OData request for
    all active baselines with in-memory hashtable lookups) is used for efficiency.

    Output structure enables Power Automate HTTP webhook actions to parse validation
    results and route alerts based on severity and drift status.

.PARAMETER TenantId
    Microsoft Entra ID tenant ID for authentication.

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID for certificate-based authentication.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication. Certificate must be
    uploaded to the Azure Automation account.

.PARAMETER DataverseUrl
    Central Dataverse organization URL where validation history and baselines are stored.
    Example: https://governance.crm.dynamics.com

.PARAMETER IncludeSandbox
    Include Sandbox type environments in compliance scan. Default: $false.

.PARAMETER IncludeDrafts
    Include draft/unpublished agents in compliance scan. Default: $false.

.PARAMETER GracePeriodHours
    Hours to exclude newly created environments from violation reporting.
    Valid range: 0-168. Default: 48 hours.

.EXAMPLE
    Start-GenAIConfigValidationRunbook `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -CertificateThumbprint "ABCDEF123456" `
        -DataverseUrl "https://governance.crm.dynamics.com"

    Runs GenAI config validation across all zones using certificate authentication.
    Outputs JSON to pipeline for Power Automate consumption.

.EXAMPLE
    Start-GenAIConfigValidationRunbook `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -CertificateThumbprint "ABCDEF123456" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -GracePeriodHours 0

    Runs validation with no grace period -- all environments are evaluated immediately.

.OUTPUTS
    JSON object with properties:
    - RunType: "GenAIConfigValidation"
    - RunId: GUID correlating this execution
    - Timestamp: ISO 8601 UTC timestamp
    - TotalAgents: Count of scanned agents
    - TotalEnvironments: Count of scanned environments
    - OverallStatus: Passed | Critical | Failed | Review | Error
    - Reason: Summary explanation
    - ZoneSummary: Object with Zone1/Zone2/Zone3 sub-objects { Total, Compliant, Violations }
    - Violations: Array of violation details
    - Drift: Object with HasDrift, IsFirstRun, DriftedAgents, Details
    - AlertRequired: Boolean flag for flow routing
    - AlertSeverity: Status value for alert priority

.NOTES
    Version: 1.0.0
    Solution: Generative AI Config Auditor (GAC)
    Control: 2.24 (Agent Feature Enablement Governance)

    Azure Automation setup:
    1. Import this script as a runbook
    2. Upload certificate to Automation Account > Certificates
    3. Install required modules: MSAL.PS, Microsoft.PowerApps.Administration.PowerShell
    4. Grant application permissions as required by Power Platform admin APIs
    5. Schedule via Schedules or trigger via webhook

    Performance:
    - Batch-queries all active baselines in a single OData request
    - In-memory hashtable for O(1) per-agent drift lookups
    - Typical scan: 2-8 minutes depending on agent count

    This script is designed to run as an Azure Automation runbook. Import into
    Azure Automation Account and configure with certificate-based authentication.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$ClientId,

    [Parameter(Mandatory)]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory)]
    [string]$DataverseUrl,

    [switch]$IncludeSandbox,

    [switch]$IncludeDrafts,

    [ValidateRange(0, 168)]
    [int]$GracePeriodHours = 48
)

$ErrorActionPreference = "Stop"

#region Helper Functions

function Get-GenAIConfigDriftDirection {
    <#
    .SYNOPSIS
        Classifies drift direction for a generative AI configuration change.
    .DESCRIPTION
        Compares baseline and current configuration values across multiple
        dimensions (AOAI enabled, orchestration mode, generative answers).
        Returns an overall drift direction and a list of changed fields.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Baseline,

        [Parameter(Mandatory)]
        [PSCustomObject]$Current
    )

    $changes = @()
    $hasWeakened = $false
    $hasStrengthened = $false

    # Check AOAI enabled drift
    if ($Baseline.AzureOpenAIEnabled -ne $Current.AzureOpenAIEnabled) {
        $direction = if ($Current.AzureOpenAIEnabled -eq 'Yes' -and $Baseline.AzureOpenAIEnabled -ne 'Yes') {
            'Enabled'
        } elseif ($Current.AzureOpenAIEnabled -ne 'Yes' -and $Baseline.AzureOpenAIEnabled -eq 'Yes') {
            'Disabled'
        } else {
            'Changed'
        }

        $changes += [PSCustomObject]@{
            Field     = 'AzureOpenAIEnabled'
            Baseline  = $Baseline.AzureOpenAIEnabled
            Current   = $Current.AzureOpenAIEnabled
            Direction = $direction
        }

        # Enabling AOAI without baseline = weakening security posture
        if ($direction -eq 'Enabled') { $hasWeakened = $true }
        if ($direction -eq 'Disabled') { $hasStrengthened = $true }
    }

    # Check orchestration mode drift
    if ($Baseline.OrchestrationMode -ne $Current.OrchestrationMode) {
        # Generative/Unified is more permissive than Classic
        $modeRank = @{
            'Classic'    = 1
            'Generative' = 2
            'Unified'    = 3
        }

        $baseRank = $modeRank[$Baseline.OrchestrationMode]
        $currRank = $modeRank[$Current.OrchestrationMode]

        $direction = if ($null -ne $baseRank -and $null -ne $currRank) {
            if ($currRank -gt $baseRank) { 'Weakened' } elseif ($currRank -lt $baseRank) { 'Strengthened' } else { 'Changed' }
        } else {
            'Changed'
        }

        $changes += [PSCustomObject]@{
            Field     = 'OrchestrationMode'
            Baseline  = $Baseline.OrchestrationMode
            Current   = $Current.OrchestrationMode
            Direction = $direction
        }

        if ($direction -eq 'Weakened') { $hasWeakened = $true }
        if ($direction -eq 'Strengthened') { $hasStrengthened = $true }
    }

    # Check generative answers node count drift
    $baselineGenCount = [int]$Baseline.GenerativeAnswersNodeCount
    $currentGenCount = [int]$Current.GenerativeAnswersNodeCount

    if ($baselineGenCount -ne $currentGenCount) {
        $direction = if ($currentGenCount -gt $baselineGenCount) { 'Increased' } else { 'Decreased' }

        $changes += [PSCustomObject]@{
            Field     = 'GenerativeAnswersNodeCount'
            Baseline  = $baselineGenCount
            Current   = $currentGenCount
            Direction = $direction
        }

        if ($direction -eq 'Increased') { $hasWeakened = $true }
        if ($direction -eq 'Decreased') { $hasStrengthened = $true }
    }

    # Check Allow ungrounded responses / AI general knowledge drift (Yes/No comparison; Yes-after-No is Weakened)
    if ($null -ne $Baseline.ModelKnowledgeEnabled -and $null -ne $Current.ModelKnowledgeEnabled -and
        $Baseline.ModelKnowledgeEnabled -ne $Current.ModelKnowledgeEnabled) {
        $direction = if ($Current.ModelKnowledgeEnabled -eq 'Yes') { 'Weakened' } else { 'Strengthened' }
        $changes += [PSCustomObject]@{
            Field     = 'ModelKnowledgeEnabled'
            Baseline  = $Baseline.ModelKnowledgeEnabled
            Current   = $Current.ModelKnowledgeEnabled
            Direction = $direction
        }
        if ($direction -eq 'Weakened') { $hasWeakened = $true } else { $hasStrengthened = $true }
    }

    # Check Work IQ / semantic search drift
    if ($null -ne $Baseline.SemanticSearchEnabled -and $null -ne $Current.SemanticSearchEnabled -and
        $Baseline.SemanticSearchEnabled -ne $Current.SemanticSearchEnabled) {
        $direction = if ($Current.SemanticSearchEnabled -eq 'Yes') { 'Weakened' } else { 'Strengthened' }
        $changes += [PSCustomObject]@{
            Field     = 'SemanticSearchEnabled'
            Baseline  = $Baseline.SemanticSearchEnabled
            Current   = $Current.SemanticSearchEnabled
            Direction = $direction
        }
        if ($direction -eq 'Weakened') { $hasWeakened = $true } else { $hasStrengthened = $true }
    }

    # Overall direction
    $overallDirection = if ($hasWeakened -and $hasStrengthened) {
        'Mixed'
    } elseif ($hasWeakened) {
        'Weakened'
    } elseif ($hasStrengthened) {
        'Strengthened'
    } elseif ($changes.Count -gt 0) {
        'Changed'
    } else {
        'Unchanged'
    }

    return [PSCustomObject]@{
        Direction = $overallDirection
        Changes   = $changes
    }
}

#endregion

try {
    Write-Verbose "Starting generative AI configuration validation runbook"
    Write-Verbose "TenantId: $TenantId"
    Write-Verbose "DataverseUrl: $DataverseUrl"

    $scriptRoot = $PSScriptRoot
    Write-Verbose "Script root: $scriptRoot"

    #region Authenticate and acquire Dataverse token

    Write-Verbose "Acquiring Dataverse token via certificate authentication"

    Import-Module MSAL.PS -ErrorAction Stop

    $cert = Get-Item "Cert:\LocalMachine\My\$CertificateThumbprint" -ErrorAction Stop
    Write-Verbose "Certificate found: $($cert.Subject)"

    $dataverseScope = "$($DataverseUrl.TrimEnd('/'))/.default"
    $tokenResult = Get-MsalToken `
        -ClientId $ClientId `
        -ClientCertificate $cert `
        -TenantId $TenantId `
        -Scopes $dataverseScope `
        -ErrorAction Stop

    $dataverseToken = $tokenResult.AccessToken
    Write-Verbose "Dataverse token acquired"

    #endregion

    #region Connect GACClient to Dataverse

    Import-Module "$scriptRoot\private\GACClient.psm1" -Force
    Connect-GACDataverse -DataverseUrl $DataverseUrl -AccessToken $dataverseToken

    # Read operational parameters from Dataverse environment variables
    $dvGracePeriod = Get-GACEnvironmentVariable -Name "GracePeriodHours" -DefaultValue $GracePeriodHours
    if ($dvGracePeriod -ne $GracePeriodHours) {
        Write-Verbose "Dataverse override: GracePeriodHours=$dvGracePeriod (was $GracePeriodHours)"
        $GracePeriodHours = [int]$dvGracePeriod
    }

    $dvIncludeSandbox = Get-GACEnvironmentVariable -Name "IncludeSandbox" -DefaultValue "false"
    if ($dvIncludeSandbox -eq "true" -and -not $IncludeSandbox) {
        Write-Verbose "Dataverse override: IncludeSandbox=true"
        $IncludeSandbox = [switch]::new($true)
    }

    $dvIncludeDrafts = Get-GACEnvironmentVariable -Name "IncludeDrafts" -DefaultValue "false"
    if ($dvIncludeDrafts -eq "true" -and -not $IncludeDrafts) {
        Write-Verbose "Dataverse override: IncludeDrafts=true"
        $IncludeDrafts = [switch]::new($true)
    }

    Write-Verbose "Dataverse parameters loaded"

    #endregion

    #region Run compliance scan

    Write-Verbose "Invoking Test-GenAIConfigCompliance"

    $complianceScript = Join-Path $scriptRoot 'Test-GenAIConfigCompliance.ps1'
    if (-not (Test-Path $complianceScript)) {
        throw "Required script not found: $complianceScript"
    }

    # Dot-source the script to load the function
    . $complianceScript

    # Note: PersistResults is intentionally NOT set here. The Power Automate
    # flow's Write_Validation_History action handles Dataverse persistence
    # to avoid duplicate history records with uncorrelated run_ids.
    $scanParams = @{
        DataverseUrl     = $DataverseUrl
        DataverseToken   = $dataverseToken
        OutputFormat     = 'Object'
        GracePeriodHours = $GracePeriodHours
        IncludeCompliant = $true
    }

    if (-not $IncludeSandbox) { $scanParams['ExcludeSandbox'] = $true }
    if ($IncludeDrafts)       { $scanParams['IncludeDrafts'] = $true }

    try {
        $scanResult = Test-GenAIConfigCompliance @scanParams
    } catch {
        # Fail-closed: if the scan throws (auth failure, empty result without -AllowEmptyResultSet,
        # Dataverse outage), record a Critical AuditControlBypass run and surface it.
        Write-Warning "Test-GenAIConfigCompliance failed: $($_.Exception.Message). Recording fail-closed AuditControlBypass run."
        return [PSCustomObject]@{
            RunId             = [guid]::NewGuid().ToString()
            OverallStatus     = 'Error'
            AlertRequired     = $true
            AlertSeverity     = 'Critical'
            ViolationType     = 'AuditControlBypass'
            ErrorMessage      = $_.Exception.Message
            TotalAgents       = 0
            EnvironmentsScanned = 0
            ViolationCount    = 0
            CompliantCount    = 0
            CriticalCount     = 1
            HighCount         = 0
            MediumCount       = 0
            ScanTimestamp     = (Get-Date).ToUniversalTime().ToString('o')
            RegulatoryContext = 'Supports supervisory expectations under FINRA Rule 3110(a)(1) — scan execution failure recorded for audit traceability'
        }
    }

    # Wrap single result in array
    if ($null -eq $scanResult) {
        $scanResult = @()
    } elseif ($scanResult -isnot [System.Array]) {
        $scanResult = @($scanResult)
    }

    # Calculate summary from scan results
    $totalAgents = $scanResult.Count
    $uniqueEnvs = ($scanResult | Select-Object -Property EnvironmentId -Unique).Count
    $environmentNameList = ($scanResult | Select-Object -Property EnvironmentDisplayName -Unique |
        ForEach-Object { $_.EnvironmentDisplayName }) -join ', '
    $violationResults = @($scanResult | Where-Object { -not $_.IsCompliant })
    $compliantResults = @($scanResult | Where-Object { $_.IsCompliant })
    $violationCount = $violationResults.Count
    $compliantCount = $compliantResults.Count

    # Determine overall status from violations
    $criticalCount = @($violationResults | Where-Object { $_.Severity -eq 'Critical' }).Count
    $highCount     = @($violationResults | Where-Object { $_.Severity -eq 'High' }).Count
    $mediumCount   = @($violationResults | Where-Object { $_.Severity -eq 'Medium' }).Count

    $overallStatus = 'Passed'
    if ($criticalCount -gt 0) {
        $overallStatus = 'Critical'
    } elseif ($highCount -gt 0) {
        $overallStatus = 'Failed'
    } elseif ($mediumCount -gt 0 -or $violationCount -gt 0) {
        $overallStatus = 'Review'
    }

    Write-Verbose "Scan complete. Overall status: $overallStatus"
    Write-Verbose "Total agents: $totalAgents, Environments: $uniqueEnvs, Violations: $violationCount"

    #endregion

    #region Batch-query active baselines for drift detection

    Write-Verbose "Batch-querying all active baselines for drift detection"

    $baselineMap = @{}
    $baselineQueryFailed = $false

    try {
        $allBaselines = Get-GACBaseline -ActiveOnly

        if ($allBaselines) {
            foreach ($b in $allBaselines) {
                if ($b.AgentId) {
                    $baselineMap[$b.AgentId] = $b
                }
            }
        }

        Write-Verbose "Loaded $($baselineMap.Count) active baseline(s) into lookup hashtable"
    } catch {
        # Fail open: on Dataverse query error, treat as first run
        Write-Verbose "Baseline query failed: $($_.Exception.Message). Failing open -- no drift detection."
        $baselineQueryFailed = $true
    }

    #endregion

    #region Per-agent drift detection

    Write-Verbose "Running per-agent drift detection"

    $driftDetails = @()
    $globalIsFirstRun = $false

    if ($baselineQueryFailed) {
        $globalIsFirstRun = $true
    } elseif ($baselineMap.Count -eq 0) {
        $globalIsFirstRun = $true
        Write-Verbose "No active baselines found -- first run for all agents"
    }

    # Build unique agent list from scan results
    $agentLookup = @{}
    foreach ($agent in $scanResult) {
        if ($agent.AgentId -and -not $agentLookup.ContainsKey($agent.AgentId)) {
            $agentLookup[$agent.AgentId] = $agent
        }
    }

    foreach ($agentId in $agentLookup.Keys) {
        $agent = $agentLookup[$agentId]

        $driftEntry = @{
            AgentId                    = $agentId
            AgentName                  = $agent.AgentName
            EnvironmentId              = $agent.EnvironmentId
            EnvironmentName            = $agent.EnvironmentDisplayName
            Zone                       = $agent.Zone
            HasDrift                   = $false
            IsFirstRun                 = $false
            Direction                  = $null
            Changes                    = @()
            BaselineAoai               = $null
            BaselineOrchestration      = $null
            BaselineGenAnswers         = $null
            CurrentAoai                = $agent.AzureOpenAIEnabled
            CurrentOrchestration       = $agent.OrchestrationMode
            CurrentGenAnswers          = $agent.GenerativeAnswersNodeCount
        }

        if ($globalIsFirstRun) {
            $driftEntry.IsFirstRun = $true
        } elseif ($baselineMap.ContainsKey($agentId)) {
            $baseline = $baselineMap[$agentId]
            $driftEntry.BaselineAoai = $baseline.AzureOpenAIEnabled
            $driftEntry.BaselineOrchestration = $baseline.OrchestrationMode
            $driftEntry.BaselineGenAnswers = $baseline.GenerativeAnswersNodeCount

            # Build comparison objects (include all five fields tracked by
            # Get-GenAIConfigDriftDirection so Rules 5/6 — Allow ungrounded
            # responses and Work IQ — actually surface in runbook drift).
            $baselineObj = [PSCustomObject]@{
                AzureOpenAIEnabled         = $baseline.AzureOpenAIEnabled
                OrchestrationMode          = $baseline.OrchestrationMode
                GenerativeAnswersNodeCount = $baseline.GenerativeAnswersNodeCount
                ModelKnowledgeEnabled      = $baseline.ModelKnowledgeEnabled
                SemanticSearchEnabled      = $baseline.SemanticSearchEnabled
            }
            $currentObj = [PSCustomObject]@{
                AzureOpenAIEnabled         = $agent.AzureOpenAIEnabled
                OrchestrationMode          = $agent.OrchestrationMode
                GenerativeAnswersNodeCount = $agent.GenerativeAnswersNodeCount
                ModelKnowledgeEnabled      = $agent.ModelKnowledgeEnabled
                SemanticSearchEnabled      = $agent.SemanticSearchEnabled
            }

            $driftResult = Get-GenAIConfigDriftDirection -Baseline $baselineObj -Current $currentObj

            if ($driftResult.Direction -ne 'Unchanged') {
                $driftEntry.HasDrift = $true
                $driftEntry.Direction = $driftResult.Direction
                $driftEntry.Changes = $driftResult.Changes
            }
        } else {
            # Agent not in baseline -- first run for this agent
            $driftEntry.IsFirstRun = $true
        }

        $driftDetails += [PSCustomObject]$driftEntry
    }

    $driftedAgents = @($driftDetails | Where-Object { $_.HasDrift })
    $hasDrift = $driftedAgents.Count -gt 0
    $hasAnyFirstRun = @($driftDetails | Where-Object { $_.IsFirstRun }).Count -gt 0

    Write-Verbose "Drift detection complete. Agents with drift: $($driftedAgents.Count)"

    #endregion

    #region Build violations array

    $violations = @()
    foreach ($v in $violationResults) {
        $violations += [PSCustomObject]@{
            AgentId                    = $v.AgentId
            AgentName                  = $v.AgentName
            EnvironmentId              = $v.EnvironmentId
            EnvironmentName            = $v.EnvironmentDisplayName
            Zone                       = $v.Zone
            ViolationType              = $v.ViolationType
            AzureOpenAIEnabled         = $v.AzureOpenAIEnabled
            OrchestrationMode          = $v.OrchestrationMode
            GenerativeAnswersNodeCount = $v.GenerativeAnswersNodeCount
            Severity                   = $v.Severity
            RegulatoryContext          = $v.RegulatoryContext
        }
    }

    #endregion

    #region Determine alert flags

    $hasViolations = $violations.Count -gt 0
    $hasWeakenedDrift = @($driftedAgents | Where-Object { $_.Direction -eq 'Weakened' -or $_.Direction -eq 'Mixed' }).Count -gt 0
    $alertRequired = $hasViolations -or $hasWeakenedDrift

    # Highest severity from violations (Critical > High > Medium > Warning > Info)
    $severityOrder = @('Critical', 'High', 'Medium', 'Warning', 'Info')
    $alertSeverity = $overallStatus

    if ($hasViolations) {
        foreach ($sev in $severityOrder) {
            if ($violations.Severity -contains $sev) {
                $alertSeverity = $sev
                break
            }
        }
    }

    # Zone 3 weakened drift escalates to Critical
    $zone3Weakened = @($driftedAgents | Where-Object { ($_.Direction -eq 'Weakened' -or $_.Direction -eq 'Mixed') -and $_.Zone -match '3' })
    if ($zone3Weakened.Count -gt 0) {
        $alertSeverity = 'Critical'
    }

    # Build reason string
    $reason = switch ($overallStatus) {
        'Passed'   { "All $totalAgents agents across $uniqueEnvs environments compliant with GenAI policies" }
        'Review'   { "$violationCount GenAI config violation(s) detected across $uniqueEnvs environments" }
        'Failed'   { "$violationCount GenAI config violation(s) detected including high severity" }
        'Critical' { "$violationCount GenAI config violation(s) detected including critical severity" }
        default    { "Validation completed with status: $overallStatus" }
    }

    if ($hasDrift) {
        $reason += "; $($driftedAgents.Count) agent(s) drifted from baseline"
    }

    #endregion

    #region Build enriched ZoneSummary

    # Count agents per zone from scan results
    $zoneTotals = @{ Zone1 = 0; Zone2 = 0; Zone3 = 0; Unknown = 0 }
    $zoneViolations = @{ Zone1 = 0; Zone2 = 0; Zone3 = 0; Unknown = 0 }

    foreach ($agent in $scanResult) {
        $zoneKey = $agent.Zone
        if ($zoneKey -and $zoneTotals.ContainsKey($zoneKey)) {
            $zoneTotals[$zoneKey]++
        } else {
            $zoneTotals['Unknown']++
        }
    }

    foreach ($v in $violationResults) {
        $zoneKey = $v.Zone
        if ($zoneKey -and $zoneViolations.ContainsKey($zoneKey)) {
            $zoneViolations[$zoneKey]++
        } else {
            $zoneViolations['Unknown']++
        }
    }

    $enrichedZoneSummary = [ordered]@{}
    foreach ($z in @('Zone1', 'Zone2', 'Zone3', 'Unknown')) {
        $total = [int]$zoneTotals[$z]
        $violCount = [int]$zoneViolations[$z]

        $enrichedZoneSummary[$z] = [PSCustomObject]@{
            Total      = $total
            Compliant  = $total - $violCount
            Violations = $violCount
        }
    }

    Write-Verbose "Zone summary: Z1=$($enrichedZoneSummary.Zone1.Total)/$($enrichedZoneSummary.Zone1.Compliant), Z2=$($enrichedZoneSummary.Zone2.Total)/$($enrichedZoneSummary.Zone2.Compliant), Z3=$($enrichedZoneSummary.Zone3.Total)/$($enrichedZoneSummary.Zone3.Compliant)"

    #endregion

    #region Build and emit output

    $runId = [guid]::NewGuid().ToString()

    $output = [PSCustomObject]@{
        RunType            = "GenAIConfigValidation"
        RunId              = $runId
        Timestamp          = ((Get-Date).ToUniversalTime().ToString("o"))
        TotalAgents        = $totalAgents
        TotalEnvironments  = $uniqueEnvs
        EnvironmentNames   = $environmentNameList
        OverallStatus      = $overallStatus
        Reason             = $reason
        Control            = "2.24"
        ZoneSummary        = [PSCustomObject]$enrichedZoneSummary
        Violations         = $violations
        Drift              = [PSCustomObject]@{
            HasDrift      = $hasDrift
            IsFirstRun    = $globalIsFirstRun
            DriftedAgents = $driftedAgents.Count
            Details       = $driftDetails
        }
        AlertRequired      = $alertRequired
        AlertSeverity      = $alertSeverity
    }

    Write-Verbose "Alert required: $($output.AlertRequired)"
    Write-Verbose "Alert severity: $($output.AlertSeverity)"

    # Convert to JSON and output to pipeline
    # This is the ONLY output -- Azure Automation captures this as job output
    $jsonOutput = $output | ConvertTo-Json -Depth 10
    Write-Verbose "JSON output length: $($jsonOutput.Length) characters"

    $jsonOutput

    #endregion

} catch {
    Write-Verbose "Error occurred: $($_.Exception.Message)"

    $errorOutput = [PSCustomObject]@{
        RunType           = "GenAIConfigValidation"
        Timestamp         = ((Get-Date).ToUniversalTime().ToString("o"))
        TotalAgents       = 0
        TotalEnvironments = 0
        OverallStatus     = "Error"
        Reason            = $_.Exception.Message
        Control           = "2.24"
        ZoneSummary       = [PSCustomObject]@{}
        Violations        = @()
        Drift             = [PSCustomObject]@{
            HasDrift      = $false
            IsFirstRun    = $false
            DriftedAgents = 0
            Details       = @()
        }
        AlertRequired     = $true
        AlertSeverity     = "Error"
    }

    $errorOutput | ConvertTo-Json -Depth 10
}
