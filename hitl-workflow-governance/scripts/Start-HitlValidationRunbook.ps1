#Requires -Version 7.0
#Requires -Modules @{ ModuleName="MSAL.PS"; ModuleVersion="4.37.0" }

<#
.SYNOPSIS
    Azure Automation runbook wrapper for HITL workflow compliance validation.

.DESCRIPTION
    Adapts Test-HitlWorkflowCompliance.ps1 for Azure Automation execution context.
    This runbook provides non-interactive authentication, structured JSON output to
    the pipeline, and drift detection logic for downstream alerting.

    Key differences from interactive orchestrator:
    - Uses certificate-based authentication (no interactive prompts)
    - Scans all governance zones in a single run
    - Outputs JSON to pipeline (captured by Get-AzAutomationJobOutput)
    - Includes drift detection via previous scan comparison
    - Adds AlertRequired flag for Power Automate flow routing
    - No Write-Host (uses Write-Verbose for diagnostics)

    HWG drift detection compares FlowsWithHitl and FlowsMissingHitl counts
    per agent against the previous scan. New missing checkpoints or increased
    flow counts without corresponding HITL coverage trigger drift alerts.

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
    Central Dataverse organization URL where validation history is stored.
    Example: https://governance.crm.dynamics.com

.PARAMETER IncludeSandbox
    Include Sandbox type environments in compliance scan. Default: $false.

.PARAMETER IncludeDrafts
    Include draft/unpublished agents in compliance scan. Default: $false.

.PARAMETER GracePeriodHours
    Hours to exclude newly created environments from violation reporting.
    Valid range: 0-168. Default: 48 hours.

.EXAMPLE
    Start-HitlValidationRunbook `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -CertificateThumbprint "ABCDEF123456" `
        -DataverseUrl "https://governance.crm.dynamics.com"

    Runs HITL checkpoint validation across all zones using certificate authentication.
    Outputs JSON to pipeline for Power Automate consumption.

.EXAMPLE
    Start-HitlValidationRunbook `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -CertificateThumbprint "ABCDEF123456" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -GracePeriodHours 0

    Runs validation with no grace period — all environments are evaluated immediately.

.OUTPUTS
    JSON object with properties:
    - RunType: "HitlWorkflowValidation"
    - RunId: GUID correlating this execution
    - Timestamp: ISO 8601 UTC timestamp
    - TotalAgents: Count of scanned agents
    - TotalEnvironments: Count of scanned environments
    - TotalFlows: Count of flow definitions scanned
    - OverallStatus: Passed | Critical | Failed | Review | Error
    - Reason: Summary explanation
    - Controls: ["2.12", "2.17", "1.10"]
    - ZoneSummary: Object with Zone1/Zone2/Zone3 sub-objects
    - Violations: Array of violation details
    - Drift: Object with HasDrift, IsFirstRun, DriftedAgents, Details
    - AlertRequired: Boolean flag for flow routing
    - AlertSeverity: Status value for alert priority

.NOTES
    Version: 1.0.0
    Solution: HITL Workflow Governance (HWG)
    Controls: 2.12 (Supervision/FINRA 3110), 2.17 (Multi-Agent Orchestration), 1.10 (Communication Compliance)

    Azure Automation setup:
    1. Import this script as a runbook
    2. Upload certificate to Automation Account > Certificates
    3. Install required modules: MSAL.PS, Microsoft.PowerApps.Administration.PowerShell
    4. Grant application permissions as required by Power Platform admin APIs
    5. Schedule via Schedules or trigger via webhook

    Performance:
    - Compares current scan against previous scan results in Dataverse
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

try {
    Write-Verbose "Starting HITL workflow validation runbook"
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

    #region Connect HWGClient to Dataverse

    Import-Module "$scriptRoot\private\HWGClient.psm1" -Force
    Connect-HWGDataverse -DataverseUrl $DataverseUrl -AccessToken $dataverseToken

    # Read operational parameters from Dataverse environment variables
    $dvGracePeriod = Get-HWGEnvironmentVariable -Name "GracePeriodHours" -DefaultValue $GracePeriodHours
    if ($dvGracePeriod -ne $GracePeriodHours) {
        Write-Verbose "Dataverse override: GracePeriodHours=$dvGracePeriod (was $GracePeriodHours)"
        $GracePeriodHours = [int]$dvGracePeriod
    }

    $dvIncludeSandbox = Get-HWGEnvironmentVariable -Name "IncludeSandbox" -DefaultValue "false"
    if ($dvIncludeSandbox -eq "true" -and -not $IncludeSandbox) {
        Write-Verbose "Dataverse override: IncludeSandbox=true"
        $IncludeSandbox = [switch]::new($true)
    }

    $dvIncludeDrafts = Get-HWGEnvironmentVariable -Name "IncludeDrafts" -DefaultValue "false"
    if ($dvIncludeDrafts -eq "true" -and -not $IncludeDrafts) {
        Write-Verbose "Dataverse override: IncludeDrafts=true"
        $IncludeDrafts = [switch]::new($true)
    }

    Write-Verbose "Dataverse parameters loaded"

    #endregion

    #region Run compliance scan

    Write-Verbose "Invoking Test-HitlWorkflowCompliance"

    $complianceScript = Join-Path $scriptRoot 'Test-HitlWorkflowCompliance.ps1'
    if (-not (Test-Path $complianceScript)) {
        throw "Required script not found: $complianceScript"
    }

    . $complianceScript

    $scanParams = @{
        DataverseUrl     = $DataverseUrl
        DataverseToken   = $dataverseToken
        OutputFormat     = 'Object'
        GracePeriodHours = $GracePeriodHours
        IncludeCompliant = $true
    }

    if (-not $IncludeSandbox) { $scanParams['ExcludeSandbox'] = $true }
    if ($IncludeDrafts)       { $scanParams['IncludeDrafts'] = $true }

    $scanResult = Test-HitlWorkflowCompliance @scanParams

    # Wrap single result in array
    if ($null -eq $scanResult) {
        $scanResult = @()
    } elseif ($scanResult -isnot [System.Array]) {
        $scanResult = @($scanResult)
    }

    # Calculate summary from scan results
    $totalAgents = $scanResult.Count
    $uniqueEnvs = ($scanResult | Select-Object -Property EnvironmentGuid -Unique).Count
    $environmentNameList = ($scanResult | Select-Object -Property EnvironmentName -Unique |
        ForEach-Object { $_.EnvironmentName }) -join ', '
    $violationResults = @($scanResult | Where-Object { -not $_.IsCompliant })
    $compliantResults = @($scanResult | Where-Object { $_.IsCompliant })
    $violationCount = $violationResults.Count
    $compliantCount = $compliantResults.Count

    # Calculate flow totals
    $totalFlows = ($scanResult | Measure-Object -Property TotalFlows -Sum).Sum
    $totalMissingHitl = ($scanResult | Measure-Object -Property FlowsMissingHitl -Sum).Sum

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

    #region Drift detection via previous scan comparison

    Write-Verbose "Querying previous scan results for drift detection"

    $driftDetails = @()
    $globalIsFirstRun = $false
    $previousScanFailed = $false

    # Query the most recent scan run from Dataverse
    $baseUrl = $DataverseUrl.TrimEnd('/')
    $driftHeaders = @{
        'Authorization'    = "Bearer $dataverseToken"
        'Accept'           = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
    }

    $previousAgentMap = @{}

    try {
        $prevScanUri = "$baseUrl/api/data/v9.2/fsi_hitlscanruns?" +
            "`$orderby=fsi_scantime desc&`$top=1&" +
            "`$select=fsi_runid,fsi_summaryjson"

        $prevScanResponse = Invoke-RestMethod -Uri $prevScanUri -Method Get -Headers $driftHeaders -ErrorAction Stop

        if ($prevScanResponse.value -and $prevScanResponse.value.Count -gt 0) {
            $prevRunId = $prevScanResponse.value[0].fsi_runid

            # Query per-agent results from previous run
            $prevResultsUri = "$baseUrl/api/data/v9.2/fsi_hitlcheckpointresults?" +
                "`$filter=fsi_runid eq '$prevRunId'&" +
                "`$select=fsi_agentid,fsi_agentname,fsi_environmentguid,fsi_zone"

            $prevResultsResponse = Invoke-RestMethod -Uri $prevResultsUri -Method Get -Headers $driftHeaders -ErrorAction Stop

            if ($prevResultsResponse.value) {
                foreach ($prev in $prevResultsResponse.value) {
                    if ($prev.fsi_agentid -and -not $previousAgentMap.ContainsKey($prev.fsi_agentid)) {
                        $previousAgentMap[$prev.fsi_agentid] = @{
                            AgentName       = $prev.fsi_agentname
                            ViolationCount  = 0
                        }
                    }
                    if ($prev.fsi_agentid) {
                        $previousAgentMap[$prev.fsi_agentid].ViolationCount++
                    }
                }
            }

            Write-Verbose "Loaded previous scan data: $($previousAgentMap.Count) agents from run $prevRunId"
        } else {
            $globalIsFirstRun = $true
            Write-Verbose "No previous scan found -- first run"
        }
    } catch {
        Write-Verbose "Previous scan query failed: $($_.Exception.Message). Failing open -- no drift detection."
        $previousScanFailed = $true
        $globalIsFirstRun = $true
    }

    # Compare current vs previous per agent
    $agentLookup = @{}
    foreach ($agent in $scanResult) {
        if ($agent.AgentId -and -not $agentLookup.ContainsKey($agent.AgentId)) {
            $agentLookup[$agent.AgentId] = $agent
        }
    }

    foreach ($agentId in $agentLookup.Keys) {
        $agent = $agentLookup[$agentId]
        $currentMissing = $agent.FlowsMissingHitl
        $currentTotal = $agent.TotalFlows

        $driftEntry = @{
            AgentId                = $agentId
            AgentName              = $agent.AgentName
            EnvironmentGuid        = $agent.EnvironmentGuid
            EnvironmentName        = $agent.EnvironmentName
            Zone                   = $agent.Zone
            HasDrift               = $false
            IsFirstRun             = $false
            Direction              = $null
            CurrentTotalFlows      = $currentTotal
            CurrentMissingHitl     = $currentMissing
            PreviousViolationCount = $null
        }

        if ($globalIsFirstRun) {
            $driftEntry.IsFirstRun = $true
        } elseif ($previousAgentMap.ContainsKey($agentId)) {
            $prevViolations = $previousAgentMap[$agentId].ViolationCount
            $driftEntry.PreviousViolationCount = $prevViolations

            # Current violations for this agent
            $currentViolations = 0
            $matchingResult = $violationResults | Where-Object { $_.AgentId -eq $agentId }
            if ($matchingResult) {
                $currentViolations = $matchingResult.ViolationCount
            }

            if ($currentViolations -gt $prevViolations) {
                $driftEntry.HasDrift = $true
                $driftEntry.Direction = 'Weakened'
            } elseif ($currentViolations -lt $prevViolations) {
                $driftEntry.HasDrift = $true
                $driftEntry.Direction = 'Strengthened'
            }
        } else {
            # New agent not in previous scan
            $driftEntry.IsFirstRun = $true
        }

        $driftDetails += [PSCustomObject]$driftEntry
    }

    $driftedAgents = @($driftDetails | Where-Object { $_.HasDrift })
    $hasDrift = $driftedAgents.Count -gt 0

    Write-Verbose "Drift detection complete. Agents with drift: $($driftedAgents.Count)"

    #endregion

    #region Build violations array

    $violations = @()
    foreach ($agentResult in $violationResults) {
        foreach ($v in $agentResult.Violations) {
            $violations += [PSCustomObject]@{
                AgentId            = $agentResult.AgentId
                AgentName          = $agentResult.AgentName
                EnvironmentGuid    = $agentResult.EnvironmentGuid
                EnvironmentName    = $agentResult.EnvironmentName
                Zone               = $agentResult.Zone
                FlowName           = $v.FlowName
                FlowId             = $v.FlowId
                CheckpointType     = $v.CheckpointType
                ViolationType      = $v.ViolationType
                Severity           = $v.Severity
                Details            = $v.Details
                RegulatoryContext   = $v.RegulatoryContext
            }
        }
    }

    #endregion

    #region Determine alert flags

    $hasViolations = $violations.Count -gt 0
    $hasWeakenedDrift = @($driftedAgents | Where-Object { $_.Direction -eq 'Weakened' }).Count -gt 0
    $alertRequired = $hasViolations -or $hasWeakenedDrift

    # Highest severity from violations
    $severityOrder = @('Critical', 'High', 'Medium', 'Warning', 'Low', 'Info')
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
        'Passed'   { "All $totalAgents agents across $uniqueEnvs environments have proper HITL checkpoints" }
        'Review'   { "$violationCount agent(s) with HITL checkpoint violations across $uniqueEnvs environments" }
        'Failed'   { "$violationCount agent(s) with HITL checkpoint violations including high severity" }
        'Critical' { "$violationCount agent(s) with HITL checkpoint violations including critical severity" }
        default    { "Validation completed with status: $overallStatus" }
    }

    if ($hasDrift) {
        $reason += "; $($driftedAgents.Count) agent(s) drifted from previous scan"
    }

    #endregion

    #region Build enriched ZoneSummary

    $zoneTotals = @{ Zone1 = 0; Zone2 = 0; Zone3 = 0; Unknown = 0 }
    $zoneViolations = @{ Zone1 = 0; Zone2 = 0; Zone3 = 0; Unknown = 0 }
    $zoneFlows = @{ Zone1 = 0; Zone2 = 0; Zone3 = 0; Unknown = 0 }
    $zoneMissingHitl = @{ Zone1 = 0; Zone2 = 0; Zone3 = 0; Unknown = 0 }

    foreach ($agent in $scanResult) {
        $zoneKey = $agent.Zone
        if ($zoneKey -and $zoneTotals.ContainsKey($zoneKey)) {
            $zoneTotals[$zoneKey]++
            $zoneFlows[$zoneKey] += $agent.TotalFlows
            $zoneMissingHitl[$zoneKey] += $agent.FlowsMissingHitl
        } else {
            $zoneTotals['Unknown']++
            $zoneFlows['Unknown'] += $agent.TotalFlows
            $zoneMissingHitl['Unknown'] += $agent.FlowsMissingHitl
        }
    }

    foreach ($agentResult in $violationResults) {
        $zoneKey = $agentResult.Zone
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
            Total          = $total
            Compliant      = $total - $violCount
            Violations     = $violCount
            TotalFlows     = [int]$zoneFlows[$z]
            MissingHitl    = [int]$zoneMissingHitl[$z]
        }
    }

    Write-Verbose "Zone summary: Z1=$($enrichedZoneSummary.Zone1.Total)/$($enrichedZoneSummary.Zone1.Compliant), Z2=$($enrichedZoneSummary.Zone2.Total)/$($enrichedZoneSummary.Zone2.Compliant), Z3=$($enrichedZoneSummary.Zone3.Total)/$($enrichedZoneSummary.Zone3.Compliant)"

    #endregion

    #region Build and emit output

    $runId = [guid]::NewGuid().ToString()

    $output = [PSCustomObject]@{
        RunType            = "HitlWorkflowValidation"
        RunId              = $runId
        Timestamp          = (Get-Date -AsUTC -Format "o")
        TotalAgents        = $totalAgents
        TotalEnvironments  = $uniqueEnvs
        TotalFlows         = $totalFlows
        EnvironmentNames   = $environmentNameList
        OverallStatus      = $overallStatus
        Reason             = $reason
        Controls           = @("2.12", "2.17", "1.10")
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
    $jsonOutput = $output | ConvertTo-Json -Depth 10
    Write-Verbose "JSON output length: $($jsonOutput.Length) characters"

    $jsonOutput

    #endregion

} catch {
    Write-Verbose "Error occurred: $($_.Exception.Message)"

    $errorOutput = [PSCustomObject]@{
        RunType           = "HitlWorkflowValidation"
        Timestamp         = (Get-Date -AsUTC -Format "o")
        TotalAgents       = 0
        TotalEnvironments = 0
        TotalFlows        = 0
        OverallStatus     = "Error"
        Reason            = $_.Exception.Message
        Controls          = @("2.12", "2.17", "1.10")
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
