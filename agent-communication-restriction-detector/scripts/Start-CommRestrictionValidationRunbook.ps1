#Requires -Version 7.0
#Requires -Modules @{ ModuleName="MSAL.PS"; ModuleVersion="4.37.0" }

<#
.SYNOPSIS
    Azure Automation runbook wrapper for communication restriction compliance
    validation.

.DESCRIPTION
    Adapts Test-CommRestrictionCompliance.ps1 for Azure Automation execution context.
    This runbook provides non-interactive authentication, structured JSON output to
    the pipeline, and skill registration drift detection logic for downstream alerting.

    Key differences from interactive orchestrator:
    - Uses certificate-based authentication (no interactive prompts)
    - Scans all governance zones in a single run
    - Outputs JSON to pipeline (captured by Get-AzAutomationJobOutput)
    - Includes drift detection via Dataverse skill registration comparison
    - Adds AlertRequired flag for Power Automate flow routing
    - No Write-Host (uses Write-Verbose for diagnostics)

    ACRD drift detection operates at the skill registration level and compares
    current agent-to-agent communication routes against the previous scan's
    snapshot stored in fsi_commscanruns.fsi_summaryjson. It classifies drift by
    direction (Weakened, Strengthened, Changed) based on zone rank changes for
    three drift types: NewRoute, RemovedRoute, and TargetZoneChanged.

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
    Central Dataverse organization URL where scan history and skill registrations
    are stored. Example: https://governance.crm.dynamics.com

.PARAMETER IncludeSandbox
    Include Sandbox type environments in compliance scan. Default: $false.

.PARAMETER IncludeDrafts
    Include draft/unpublished agents in compliance scan. Default: $false.

.PARAMETER GracePeriodHours
    Hours to exclude newly created environments from violation reporting.
    Valid range: 0-168. Default: 48 hours.

.EXAMPLE
    Start-CommRestrictionValidationRunbook `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -CertificateThumbprint "ABCDEF123456" `
        -DataverseUrl "https://governance.crm.dynamics.com"

    Runs communication restriction validation across all zones using certificate
    authentication. Outputs JSON to pipeline for Power Automate consumption.

.EXAMPLE
    Start-CommRestrictionValidationRunbook `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -CertificateThumbprint "ABCDEF123456" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -GracePeriodHours 0

    Runs validation with no grace period -- all environments are evaluated immediately.

.OUTPUTS
    JSON object with properties:
    - RunType: "CommRestrictionValidation"
    - RunId: GUID correlating this execution
    - Timestamp: ISO 8601 UTC timestamp
    - TotalSkills: Count of scanned skill registrations
    - TotalAgents: Count of unique agents
    - TotalEnvironments: Count of scanned environments
    - EnvironmentNames: Comma-separated environment display names
    - OverallStatus: Passed | Critical | Failed | Review | Error
    - Reason: Summary explanation
    - Control: "2.17"
    - ZoneSummary: Object with Zone1/Zone2/Zone3/Unknown sub-objects { Total, Compliant, Violations }
    - Violations: Array of violation details
    - Drift: Object with HasDrift, IsFirstRun, DriftedRoutes, Details
    - AlertRequired: Boolean flag for flow routing
    - AlertSeverity: Status value for alert priority

.NOTES
    Version: 1.0.0
    Solution: Agent Communication Restriction Detector (ACRD)
    Control: 2.17 (Multi-Agent Orchestration Limits)

    Azure Automation setup:
    1. Import this script as a runbook
    2. Upload certificate to Automation Account > Certificates
    3. Install required modules: MSAL.PS, Microsoft.PowerApps.Administration.PowerShell
    4. Grant application permissions as required by Power Platform admin APIs
    5. Schedule via Schedules or trigger via webhook

    Performance:
    - Batch-queries previous scan summary in a single OData request
    - In-memory hashtable for O(1) per-skill drift lookups
    - Typical scan: 2-8 minutes depending on agent and skill count

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

function Get-CommRouteDriftDirection {
    <#
    .SYNOPSIS
        Classifies drift direction for a skill registration route change.
    .DESCRIPTION
        Compares a skill registration's previous and current target zone to
        determine whether the change weakens, strengthens, or merely changes
        the communication posture. Zone rank: Zone1=1, Zone2=2, Zone3=3.
        Higher zone number = more restricted environment.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateSet('NewRoute', 'RemovedRoute', 'TargetZoneChanged')]
        [string]$DriftType,

        [Parameter()]
        [string]$PreviousTargetZone,

        [Parameter()]
        [string]$CurrentTargetZone,

        [Parameter()]
        [string]$SourceZone
    )

    $zoneRank = @{
        'Zone1'   = 1
        'Zone2'   = 2
        'Zone3'   = 3
        'Unknown' = 0
    }

    switch ($DriftType) {
        'NewRoute' {
            # New route to a higher-ranked zone (more restricted) = weakened posture
            # because the calling agent now reaches into a higher security zone
            $currentRank = if ($CurrentTargetZone -and $zoneRank.ContainsKey($CurrentTargetZone)) {
                $zoneRank[$CurrentTargetZone]
            } else { 0 }
            $sourceRank = if ($SourceZone -and $zoneRank.ContainsKey($SourceZone)) {
                $zoneRank[$SourceZone]
            } else { 0 }

            if ($currentRank -gt $sourceRank) {
                return 'Weakened'
            }
            return 'Changed'
        }
        'RemovedRoute' {
            # Removing a route = strengthened posture (fewer communication paths)
            return 'Strengthened'
        }
        'TargetZoneChanged' {
            $prevRank = if ($PreviousTargetZone -and $zoneRank.ContainsKey($PreviousTargetZone)) {
                $zoneRank[$PreviousTargetZone]
            } else { 0 }
            $currRank = if ($CurrentTargetZone -and $zoneRank.ContainsKey($CurrentTargetZone)) {
                $zoneRank[$CurrentTargetZone]
            } else { 0 }

            if ($currRank -gt $prevRank) {
                return 'Weakened'
            } elseif ($currRank -lt $prevRank) {
                return 'Strengthened'
            }
            return 'Changed'
        }
    }

    return 'Changed'
}

#endregion

try {
    Write-Verbose "Starting communication restriction validation runbook"
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

    #region Connect ACRDClient to Dataverse

    Import-Module "$scriptRoot\private\ACRDClient.psm1" -Force
    Connect-ACRDDataverse -DataverseUrl $DataverseUrl -AccessToken $dataverseToken

    # Read operational parameters from Dataverse environment variables
    $dvGracePeriod = Get-ACRDEnvironmentVariable -Name "GracePeriodHours" -DefaultValue $GracePeriodHours
    if ($dvGracePeriod -ne $GracePeriodHours) {
        Write-Verbose "Dataverse override: GracePeriodHours=$dvGracePeriod (was $GracePeriodHours)"
        $GracePeriodHours = [int]$dvGracePeriod
    }

    $dvIncludeSandbox = Get-ACRDEnvironmentVariable -Name "IncludeSandbox" -DefaultValue "false"
    if ($dvIncludeSandbox -eq "true" -and -not $IncludeSandbox) {
        Write-Verbose "Dataverse override: IncludeSandbox=true"
        $IncludeSandbox = [switch]::new($true)
    }

    $dvIncludeDrafts = Get-ACRDEnvironmentVariable -Name "IncludeDrafts" -DefaultValue "false"
    if ($dvIncludeDrafts -eq "true" -and -not $IncludeDrafts) {
        Write-Verbose "Dataverse override: IncludeDrafts=true"
        $IncludeDrafts = [switch]::new($true)
    }

    Write-Verbose "Dataverse parameters loaded"

    #endregion

    #region Run compliance scan

    Write-Verbose "Invoking Test-CommRestrictionCompliance"

    $complianceScript = Join-Path $scriptRoot 'Test-CommRestrictionCompliance.ps1'
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

    $scanResult = Test-CommRestrictionCompliance @scanParams

    # Wrap single result in array
    if ($null -eq $scanResult) {
        $scanResult = @()
    } elseif ($scanResult -isnot [System.Array]) {
        $scanResult = @($scanResult)
    }

    # Calculate summary from scan results
    $totalSkills = $scanResult.Count
    $uniqueAgents = @($scanResult | Select-Object -Property CallingAgentId -Unique).Count
    $uniqueEnvs = @($scanResult | Select-Object -Property EnvironmentId -Unique).Count
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
    Write-Verbose "Total skills: $totalSkills, Agents: $uniqueAgents, Environments: $uniqueEnvs, Violations: $violationCount"

    #endregion

    #region Drift detection via previous scan comparison

    Write-Verbose "Querying previous scan run for drift detection"

    $driftDetails = @()
    $globalIsFirstRun = $false
    $previousSkillMap = @{}
    $lastScanQueryFailed = $false

    try {
        $lastScan = Get-ACRDLastScan -Top 1

        if ($lastScan) {
            Write-Verbose "Found previous scan: $($lastScan.Name) at $($lastScan.Timestamp)"

            # Parse previous scan's summaryJson to extract skill registration snapshot
            if ($lastScan.SummaryJson) {
                try {
                    $previousSummary = $lastScan.SummaryJson | ConvertFrom-Json -ErrorAction Stop

                    # The summaryJson contains a SkillSnapshot array from the previous run
                    # Each entry has: AgentId, AgentName, SkillName, TargetAgentId,
                    # TargetAgentName, SourceZone, TargetZone, EnvironmentId, EnvironmentName
                    if ($previousSummary.SkillSnapshot) {
                        foreach ($snap in $previousSummary.SkillSnapshot) {
                            # Key: CallingAgentId->TargetAgentId::SkillName (unique per route)
                            $snapKey = "$($snap.AgentId)->$($snap.TargetAgentId)::$($snap.SkillName)"
                            $previousSkillMap[$snapKey] = $snap
                        }
                        Write-Verbose "Loaded $($previousSkillMap.Count) skill route(s) from previous scan snapshot"
                    } else {
                        Write-Verbose "Previous scan summaryJson has no SkillSnapshot -- treating as first run"
                        $globalIsFirstRun = $true
                    }
                } catch {
                    Write-Verbose "Failed to parse previous scan summaryJson: $($_.Exception.Message). Treating as first run."
                    $globalIsFirstRun = $true
                }
            } else {
                Write-Verbose "Previous scan has no summaryJson -- treating as first run"
                $globalIsFirstRun = $true
            }
        } else {
            $globalIsFirstRun = $true
            Write-Verbose "No previous scan found -- first run, no drift detection"
        }
    } catch {
        # Fail open: on Dataverse query error, treat as first run
        Write-Verbose "Last scan query failed: $($_.Exception.Message). Failing open -- no drift detection."
        $lastScanQueryFailed = $true
        $globalIsFirstRun = $true
    }

    #endregion

    #region Compare current routes against previous snapshot

    Write-Verbose "Running skill registration drift detection"

    # Build current skill route map
    $currentSkillMap = @{}
    foreach ($skill in $scanResult) {
        $key = "$($skill.CallingAgentId)->$($skill.TargetAgentId)::$($skill.SkillName)"
        $currentSkillMap[$key] = $skill
    }

    if (-not $globalIsFirstRun -and -not $lastScanQueryFailed) {
        # Detect new routes (in current but not in previous)
        foreach ($key in $currentSkillMap.Keys) {
            if (-not $previousSkillMap.ContainsKey($key)) {
                $current = $currentSkillMap[$key]
                $direction = Get-CommRouteDriftDirection `
                    -DriftType 'NewRoute' `
                    -CurrentTargetZone $current.TargetZone `
                    -SourceZone $current.SourceZone

                $driftDetails += [PSCustomObject]@{
                    DriftType       = 'NewRoute'
                    RouteKey        = $key
                    AgentId         = $current.CallingAgentId
                    AgentName       = $current.CallingAgentName
                    SkillName       = $current.SkillName
                    TargetAgentId   = $current.TargetAgentId
                    TargetAgentName = $current.TargetAgentName
                    SourceZone      = $current.SourceZone
                    PreviousTarget  = $null
                    CurrentTarget   = $current.TargetZone
                    Direction       = $direction
                    EnvironmentId   = $current.EnvironmentId
                    EnvironmentName = $current.EnvironmentDisplayName
                }
            }
        }

        # Detect removed routes (in previous but not in current)
        foreach ($key in $previousSkillMap.Keys) {
            if (-not $currentSkillMap.ContainsKey($key)) {
                $previous = $previousSkillMap[$key]
                $direction = Get-CommRouteDriftDirection -DriftType 'RemovedRoute'

                $driftDetails += [PSCustomObject]@{
                    DriftType       = 'RemovedRoute'
                    RouteKey        = $key
                    AgentId         = $previous.AgentId
                    AgentName       = $previous.AgentName
                    SkillName       = $previous.SkillName
                    TargetAgentId   = $previous.TargetAgentId
                    TargetAgentName = $previous.TargetAgentName
                    SourceZone      = $previous.SourceZone
                    PreviousTarget  = $previous.TargetZone
                    CurrentTarget   = $null
                    Direction       = $direction
                    EnvironmentId   = $previous.EnvironmentId
                    EnvironmentName = $previous.EnvironmentName
                }
            }
        }

        # Detect target zone changes (same route key but different target zone)
        foreach ($key in $currentSkillMap.Keys) {
            if ($previousSkillMap.ContainsKey($key)) {
                $current = $currentSkillMap[$key]
                $previous = $previousSkillMap[$key]

                if ($current.TargetZone -ne $previous.TargetZone) {
                    $direction = Get-CommRouteDriftDirection `
                        -DriftType 'TargetZoneChanged' `
                        -PreviousTargetZone $previous.TargetZone `
                        -CurrentTargetZone $current.TargetZone

                    $driftDetails += [PSCustomObject]@{
                        DriftType       = 'TargetZoneChanged'
                        RouteKey        = $key
                        AgentId         = $current.CallingAgentId
                        AgentName       = $current.CallingAgentName
                        SkillName       = $current.SkillName
                        TargetAgentId   = $current.TargetAgentId
                        TargetAgentName = $current.TargetAgentName
                        SourceZone      = $current.SourceZone
                        PreviousTarget  = $previous.TargetZone
                        CurrentTarget   = $current.TargetZone
                        Direction       = $direction
                        EnvironmentId   = $current.EnvironmentId
                        EnvironmentName = $current.EnvironmentDisplayName
                    }
                }
            }
        }
    }

    $driftedRoutes = @($driftDetails | Where-Object { $_.Direction -ne 'Unchanged' })
    $hasDrift = $driftedRoutes.Count -gt 0

    Write-Verbose "Drift detection complete. Routes with drift: $($driftedRoutes.Count)"

    #endregion

    #region Build violations array

    $violations = @()
    foreach ($v in $violationResults) {
        $violations += [PSCustomObject]@{
            CallingAgentId      = $v.CallingAgentId
            CallingAgentName    = $v.CallingAgentName
            TargetAgentId       = $v.TargetAgentId
            TargetAgentName     = $v.TargetAgentName
            SkillName           = $v.SkillName
            EnvironmentId       = $v.EnvironmentId
            EnvironmentName     = $v.EnvironmentDisplayName
            SourceZone          = $v.SourceZone
            TargetZone          = $v.TargetZone
            ViolationType       = $v.ViolationType
            Severity            = $v.Severity
            RegulatoryContext    = $v.RegulatoryContext
            IsCrossEnvironment  = $v.IsCrossEnvironment
            IsCrossTenant       = $v.IsCrossTenant
        }
    }

    #endregion

    #region Determine alert flags

    $hasViolations = $violations.Count -gt 0
    $hasWeakenedDrift = @($driftedRoutes | Where-Object { $_.Direction -eq 'Weakened' }).Count -gt 0
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
    $zone3Weakened = @($driftedRoutes | Where-Object {
        $_.Direction -eq 'Weakened' -and ($_.SourceZone -match '3' -or $_.CurrentTarget -match '3')
    })
    if ($zone3Weakened.Count -gt 0) {
        $alertSeverity = 'Critical'
    }

    # Build reason string
    $reason = switch ($overallStatus) {
        'Passed'   { "All $totalSkills skill registrations across $uniqueEnvs environments compliant with communication policies" }
        'Review'   { "$violationCount communication violation(s) detected across $uniqueEnvs environments" }
        'Failed'   { "$violationCount communication violation(s) detected including high severity" }
        'Critical' { "$violationCount communication violation(s) detected including critical severity" }
        default    { "Validation completed with status: $overallStatus" }
    }

    if ($hasDrift) {
        $reason += "; $($driftedRoutes.Count) route(s) drifted from previous scan"
    }

    #endregion

    #region Build enriched ZoneSummary

    # Count skill registrations per zone from scan results (using SourceZone of the calling agent)
    $zoneTotals = @{ Zone1 = 0; Zone2 = 0; Zone3 = 0; Unknown = 0 }
    $zoneViolations = @{ Zone1 = 0; Zone2 = 0; Zone3 = 0; Unknown = 0 }

    foreach ($skill in $scanResult) {
        $zoneKey = $skill.SourceZone
        if ($zoneKey -and $zoneTotals.ContainsKey($zoneKey)) {
            $zoneTotals[$zoneKey]++
        } else {
            $zoneTotals['Unknown']++
        }
    }

    foreach ($v in $violationResults) {
        $zoneKey = $v.SourceZone
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
        RunType            = "CommRestrictionValidation"
        RunId              = $runId
        Timestamp          = (Get-Date -AsUTC -Format "o")
        TotalSkills        = $totalSkills
        TotalAgents        = $uniqueAgents
        TotalEnvironments  = $uniqueEnvs
        EnvironmentNames   = $environmentNameList
        OverallStatus      = $overallStatus
        Reason             = $reason
        Control            = "2.17"
        ZoneSummary        = [PSCustomObject]$enrichedZoneSummary
        Violations         = $violations
        Drift              = [PSCustomObject]@{
            HasDrift      = $hasDrift
            IsFirstRun    = $globalIsFirstRun
            DriftedRoutes = $driftedRoutes.Count
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
        RunType           = "CommRestrictionValidation"
        Timestamp         = (Get-Date -AsUTC -Format "o")
        TotalSkills       = 0
        TotalAgents       = 0
        TotalEnvironments = 0
        EnvironmentNames  = ""
        OverallStatus     = "Error"
        Reason            = $_.Exception.Message
        Control           = "2.17"
        ZoneSummary       = [PSCustomObject]@{}
        Violations        = @()
        Drift             = [PSCustomObject]@{
            HasDrift      = $false
            IsFirstRun    = $false
            DriftedRoutes = 0
            Details       = @()
        }
        AlertRequired     = $true
        AlertSeverity     = "Error"
    }

    $errorOutput | ConvertTo-Json -Depth 10
}
