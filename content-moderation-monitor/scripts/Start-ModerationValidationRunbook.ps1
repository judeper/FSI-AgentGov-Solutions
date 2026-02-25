#Requires -Version 7.1
#Requires -Modules @{ ModuleName="MSAL.PS"; ModuleVersion="4.37.0" }

<#
.SYNOPSIS
    Azure Automation runbook wrapper for content moderation compliance validation.

.DESCRIPTION
    Adapts Test-ContentModerationCompliance.ps1 for Azure Automation execution context.
    This runbook provides non-interactive authentication, structured JSON output to
    the pipeline, and per-agent drift detection logic for downstream alerting.

    Key differences from interactive orchestrator:
    - Uses certificate-based authentication (no interactive prompts)
    - Scans all governance zones in a single run
    - Outputs JSON to pipeline (captured by Get-AzAutomationJobOutput)
    - Includes per-agent drift detection via Dataverse baseline comparison
    - Adds AlertRequired flag for Power Automate flow routing
    - No Write-Host (uses Write-Verbose for diagnostics)

    Key difference from AAM (v6): CMM drift detection operates at the agent level
    (50-500 agents) rather than the environment level (10-50 environments). This
    uses a batch baseline query optimization — a single OData request for all active
    baselines with in-memory hashtable lookups — rather than per-entity queries.

    Output structure enables Power Automate HTTP webhook actions to parse validation
    results and route alerts based on severity and drift status.

.PARAMETER TenantId
    Azure AD tenant ID for authentication.

.PARAMETER ClientId
    Azure AD application (client) ID for certificate-based authentication.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication. Certificate must be
    uploaded to the Azure Automation account.

.PARAMETER DataverseUrl
    Central Dataverse organization URL where validation history and baselines are stored.
    Example: https://governance.crm.dynamics.com

.PARAMETER ExcludeSandbox
    Exclude Sandbox type environments from compliance scan. Default: $false.

.PARAMETER ExcludeTrial
    Exclude Trial type environments from compliance scan. Default: $false.

.PARAMETER GracePeriodHours
    Hours to exclude newly created environments from violation reporting.
    Valid range: 0-168. Default: 48 hours.

.EXAMPLE
    Start-ModerationValidationRunbook `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -CertificateThumbprint "ABCDEF123456" `
        -DataverseUrl "https://governance.crm.dynamics.com"

    Runs content moderation validation across all zones using certificate authentication.
    Outputs JSON to pipeline for Power Automate consumption.

.EXAMPLE
    Start-ModerationValidationRunbook `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -CertificateThumbprint "ABCDEF123456" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -GracePeriodHours 0

    Runs validation with no grace period — all environments are evaluated immediately.

.OUTPUTS
    JSON object with properties:
    - RunType: "ModerationValidation"
    - RunId: GUID string for run correlation
    - Timestamp: ISO 8601 UTC timestamp
    - TotalAgents: Count of scanned agents
    - TotalEnvironments: Count of scanned environments
    - EnvironmentNames: Comma-separated string of scanned environment display names
    - OverallStatus: Passed | Critical | Failed | Review | Error
    - Reason: Summary explanation
    - ZoneSummary: Hashtable with Zone1/Zone2/Zone3/Unknown sub-objects { Total, Compliant, Violations }
    - Violations: Array of violation details
    - Drift: Object with HasDrift, IsFirstRun, DriftedAgents, Details
    - AlertRequired: Boolean flag for flow routing
    - AlertSeverity: Status value for alert priority

.NOTES
    Version: 1.0.1

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

    [switch]$ExcludeSandbox,

    [switch]$ExcludeTrial,

    [ValidateRange(0, 168)]
    [int]$GracePeriodHours = 48
)

$ErrorActionPreference = "Stop"

#region Helper Functions

function Get-ModerationDriftDirection {
    <#
    .SYNOPSIS
        Classifies drift direction for a moderation level change.
    .DESCRIPTION
        Compares baseline and current moderation levels using a restrictiveness ranking.
        High (rank 1) is most restrictive, Low (rank 3) is least restrictive.
        A higher rank number means less restrictive (weakened).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BaselineLevel,

        [Parameter(Mandatory)]
        [string]$CurrentLevel
    )

    $rankMap = @{
        'High'   = 1
        'Medium' = 2
        'Low'    = 3
    }

    $baselineRank = $rankMap[$BaselineLevel]
    $currentRank = $rankMap[$CurrentLevel]

    if ($null -eq $baselineRank -or $null -eq $currentRank) {
        return 'Changed'
    }

    if ($currentRank -gt $baselineRank) {
        return 'Weakened'
    } elseif ($currentRank -lt $baselineRank) {
        return 'Strengthened'
    }

    return 'Unchanged'
}

#endregion

try {
    Write-Verbose "Starting content moderation validation runbook"
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

    #region Connect CMMClient to Dataverse

    Import-Module "$scriptRoot\private\CMMClient.psm1" -Force
    Connect-CMMDataverse -DataverseUrl $DataverseUrl -AccessToken $dataverseToken

    # Read operational parameters from Dataverse environment variables
    $dvGracePeriod = Get-CMMEnvironmentVariable -Name "GracePeriodHours" -DefaultValue $GracePeriodHours
    if ($dvGracePeriod -ne $GracePeriodHours) {
        Write-Verbose "Dataverse override: GracePeriodHours=$dvGracePeriod (was $GracePeriodHours)"
        $GracePeriodHours = [int]$dvGracePeriod
    }

    $dvIncludeSandbox = Get-CMMEnvironmentVariable -Name "IncludeSandbox" -DefaultValue "false"
    if ($dvIncludeSandbox -eq "true" -and $ExcludeSandbox) {
        Write-Verbose "Dataverse override: IncludeSandbox=true, overriding -ExcludeSandbox switch"
        $ExcludeSandbox = [switch]::new($false)
    }

    $dvIncludeDrafts = Get-CMMEnvironmentVariable -Name "IncludeDrafts" -DefaultValue "false"
    $includeDrafts = $dvIncludeDrafts -eq "true"
    Write-Verbose "IncludeDrafts from Dataverse: $includeDrafts"

    Write-Verbose "Dataverse parameters loaded"

    #endregion

    #region Run compliance scan

    Write-Verbose "Invoking Test-ContentModerationCompliance"

    $complianceScript = Join-Path $scriptRoot 'Test-ContentModerationCompliance.ps1'
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

    if ($ExcludeSandbox) { $scanParams['ExcludeSandbox'] = $true }
    if ($ExcludeTrial)   { $scanParams['ExcludeTrial'] = $true }
    if ($includeDrafts)  { $scanParams['IncludeDrafts'] = $true }

    $scanResult = Test-ContentModerationCompliance @scanParams

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
        $allBaselines = Get-ModerationBaseline -ActiveOnly

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
        Write-Verbose "Baseline query failed: $($_.Exception.Message). Failing open — no drift detection."
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
        Write-Verbose "No active baselines found — first run for all agents"
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
            AgentId         = $agentId
            AgentName       = $agent.AgentName
            EnvironmentId   = $agent.EnvironmentId
            EnvironmentName = $agent.EnvironmentDisplayName
            Zone            = $agent.Zone
            HasDrift        = $false
            IsFirstRun      = $false
            Direction       = $null
            BaselineLevel   = $null
            CurrentLevel    = $agent.CurrentModerationLevel
        }

        if ($globalIsFirstRun) {
            $driftEntry.IsFirstRun = $true
        } elseif ($baselineMap.ContainsKey($agentId)) {
            $baseline = $baselineMap[$agentId]
            $driftEntry.BaselineLevel = $baseline.ModerationLevel

            if ($agent.CurrentModerationLevel -ne $baseline.ModerationLevel) {
                $direction = Get-ModerationDriftDirection `
                    -BaselineLevel $baseline.ModerationLevel `
                    -CurrentLevel $agent.CurrentModerationLevel

                $driftEntry.HasDrift = $true
                $driftEntry.Direction = $direction
            }
        } else {
            # Agent not in baseline — first run for this agent
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
            AgentId                = $v.AgentId
            AgentName              = $v.AgentName
            EnvironmentId          = $v.EnvironmentId
            EnvironmentName        = $v.EnvironmentDisplayName
            Zone                   = $v.Zone
            ExpectedModerationLevel = $v.ExpectedModerationLevel
            ActualModerationLevel  = $v.CurrentModerationLevel
            Severity               = $v.Severity
            RegulatoryContext      = $v.RegulatoryContext
        }
    }

    #endregion

    #region Determine alert flags

    $hasViolations = $violations.Count -gt 0
    $hasWeakenedDrift = @($driftedAgents | Where-Object { $_.Direction -eq 'Weakened' }).Count -gt 0
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
    $zone3Weakened = @($driftedAgents | Where-Object { $_.Direction -eq 'Weakened' -and $_.Zone -match '3' })
    if ($zone3Weakened.Count -gt 0) {
        $alertSeverity = 'Critical'
    }

    # Build reason string
    $reason = switch ($overallStatus) {
        'Passed'   { "All $totalAgents agents across $uniqueEnvs environments compliant" }
        'Review'   { "$violationCount violation(s) detected across $uniqueEnvs environments" }
        'Failed'   { "$violationCount violation(s) detected including high severity" }
        'Critical' { "$violationCount violation(s) detected including critical severity" }
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
        RunType            = "ModerationValidation"
        RunId              = $runId
        Timestamp          = (Get-Date -AsUTC -Format "o")
        TotalAgents        = $totalAgents
        TotalEnvironments  = $uniqueEnvs
        EnvironmentNames   = $environmentNameList
        OverallStatus      = $overallStatus
        Reason             = $reason
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
    # This is the ONLY output — Azure Automation captures this as job output
    $jsonOutput = $output | ConvertTo-Json -Depth 10
    Write-Verbose "JSON output length: $($jsonOutput.Length) characters"

    $jsonOutput

    #endregion

} catch {
    Write-Verbose "Error occurred: $($_.Exception.Message)"

    $errorOutput = [PSCustomObject]@{
        RunType           = "ModerationValidation"
        RunId             = [guid]::NewGuid().ToString()
        Timestamp         = (Get-Date -AsUTC -Format "o")
        TotalAgents       = 0
        TotalEnvironments = 0
        EnvironmentNames  = ""
        OverallStatus     = "Error"
        Reason            = $_.Exception.Message
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
