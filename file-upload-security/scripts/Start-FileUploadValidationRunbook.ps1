#Requires -Version 7.0
#Requires -Modules @{ ModuleName="MSAL.PS"; ModuleVersion="4.37.0" }

<#
.SYNOPSIS
    Azure Automation runbook wrapper for file upload compliance validation.

.DESCRIPTION
    Adapts Test-FileUploadCompliance.ps1 for Azure Automation execution context.
    This runbook provides non-interactive authentication, structured JSON output to
    the pipeline, and per-agent drift detection logic for downstream alerting.

    Key differences from interactive orchestrator:
    - Uses certificate-based authentication (no interactive prompts)
    - Scans all governance zones in a single run
    - Outputs JSON to pipeline (captured by Get-AzAutomationJobOutput)
    - Includes per-agent drift detection via Dataverse baseline comparison
    - Adds AlertRequired flag for Power Automate flow routing
    - No Write-Host (uses Write-Verbose for diagnostics)

    Key difference from CMM (v7): FUS drift detection operates on binary
    file upload status (enabled/disabled) rather than multi-level moderation.
    Drift direction: Disabled→Enabled = Weakened, Enabled→Disabled = Strengthened.

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
    Start-FileUploadValidationRunbook `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -CertificateThumbprint "ABCDEF123456" `
        -DataverseUrl "https://governance.crm.dynamics.com"

    Runs file upload validation across all zones using certificate authentication.
    Outputs JSON to pipeline for Power Automate consumption.

.OUTPUTS
    JSON object with properties:
    - RunType: "FileUploadValidation"
    - Timestamp: ISO 8601 UTC timestamp
    - TotalAgents: Count of scanned agents
    - TotalEnvironments: Count of scanned environments
    - FileUploadEnabledCount: Count of agents with file upload enabled
    - OverallStatus: Passed | Warning | Failed | Error
    - Reason: Summary explanation
    - ZoneSummary: Hashtable with Zone1/Zone2/Zone3 sub-objects { Total, Compliant, Violations }
    - Violations: Array of violation details with ViolationType, FileUploadExpected/Actual
    - Drift: Object with HasDrift, IsFirstRun, DriftedAgents, Details
    - AlertRequired: Boolean flag for flow routing
    - AlertSeverity: Status value for alert priority

.NOTES
    Version: 1.0.0
    Part of FSI Agent Governance Framework - File Upload Security Configurator
    Control: 1.14 - Data Minimization and Agent Scope Control

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

function Get-FileUploadDriftDirection {
    <#
    .SYNOPSIS
        Classifies drift direction for a file upload status change.
    .DESCRIPTION
        Compares baseline and current file upload enabled status.
        Disabled→Enabled = Weakened (agent now accepts files without prior approval)
        Enabled→Disabled = Strengthened (agent file uploads were restricted)
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [bool]$BaselineEnabled,

        [Parameter(Mandatory)]
        [bool]$CurrentEnabled
    )

    if ($BaselineEnabled -eq $CurrentEnabled) {
        return 'Unchanged'
    }

    if (-not $BaselineEnabled -and $CurrentEnabled) {
        return 'Weakened'
    }

    return 'Strengthened'
}

#endregion

try {
    Write-Verbose "Starting file upload validation runbook"
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

    #region Connect FUSClient to Dataverse

    Import-Module "$scriptRoot\private\FUSClient.psm1" -Force
    Connect-FUSDataverse -DataverseUrl $DataverseUrl -AccessToken $dataverseToken

    # Read operational parameters from Dataverse environment variables
    $dvGracePeriod = Get-FUSEnvironmentVariable -Name "GracePeriodHours" -DefaultValue $GracePeriodHours
    if ($dvGracePeriod -ne $GracePeriodHours) {
        Write-Verbose "Dataverse override: GracePeriodHours=$dvGracePeriod (was $GracePeriodHours)"
        $GracePeriodHours = [int]$dvGracePeriod
    }

    $dvIncludeSandbox = Get-FUSEnvironmentVariable -Name "IncludeSandbox" -DefaultValue "false"
    if ($dvIncludeSandbox -eq "true" -and $ExcludeSandbox) {
        Write-Verbose "Dataverse override: IncludeSandbox=true, overriding -ExcludeSandbox switch"
        $ExcludeSandbox = [switch]::new($false)
    } elseif ($dvIncludeSandbox -eq "false" -and -not $ExcludeSandbox) {
        Write-Verbose "Dataverse override: IncludeSandbox=false, enabling -ExcludeSandbox"
        $ExcludeSandbox = [switch]::new($true)
    }

    $dvIncludeDrafts = Get-FUSEnvironmentVariable -Name "IncludeDrafts" -DefaultValue "false"
    $includeDrafts = $dvIncludeDrafts -eq "true"
    Write-Verbose "IncludeDrafts from Dataverse: $includeDrafts"

    Write-Verbose "Dataverse parameters loaded"

    #endregion

    #region Run compliance scan

    Write-Verbose "Invoking compliance pipeline (Get-AgentFileUploadSettings + Compare-FileUploadCompliance)"

    # Dot-source the sub-scripts that define the pipeline functions
    . (Join-Path $scriptRoot 'Get-AgentFileUploadSettings.ps1')
    . (Join-Path $scriptRoot 'Compare-FileUploadCompliance.ps1')

    $getParams = @{
        DataverseUrl     = $DataverseUrl
        GracePeriodHours = $GracePeriodHours
    }

    if ($ExcludeSandbox) { $getParams['ExcludeSandbox'] = $true }
    if ($ExcludeTrial)   { $getParams['ExcludeTrial'] = $true }
    if ($includeDrafts)  { $getParams['IncludeDrafts'] = $true }

    $agentSettings = Get-AgentFileUploadSettings @getParams
    $scanResult = if ($agentSettings) {
        Compare-FileUploadCompliance -AgentSettings $agentSettings -IncludeCompliant
    } else {
        @()
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
    $fileUploadEnabledCount = @($scanResult | Where-Object { $_.FileUploadEnabled -eq $true }).Count
    $violationResults = @($scanResult | Where-Object { -not $_.IsCompliant })
    $compliantResults = @($scanResult | Where-Object { $_.IsCompliant })
    $violationCount = $violationResults.Count

    # Determine overall status from violations
    $criticalCount = @($violationResults | Where-Object { $_.Severity -eq 'Critical' }).Count
    $highCount     = @($violationResults | Where-Object { $_.Severity -eq 'High' }).Count
    $mediumCount   = @($violationResults | Where-Object { $_.Severity -eq 'Medium' }).Count

    $overallStatus = 'Passed'
    if ($criticalCount -gt 0 -or $highCount -gt 0) {
        $overallStatus = 'Failed'
    } elseif ($mediumCount -gt 0 -or $violationCount -gt 0) {
        $overallStatus = 'Warning'
    }

    Write-Verbose "Scan complete. Overall status: $overallStatus"
    Write-Verbose "Total agents: $totalAgents, Environments: $uniqueEnvs, Violations: $violationCount, File Upload Enabled: $fileUploadEnabledCount"

    #endregion

    #region Batch-query active baselines for drift detection

    Write-Verbose "Batch-querying all active baselines for drift detection"

    $baselineMap = @{}
    $baselineQueryFailed = $false

    try {
        $allBaselines = Get-FileUploadBaseline -ActiveOnly

        if ($allBaselines) {
            foreach ($b in $allBaselines) {
                if ($b.AgentId) {
                    $baselineMap[$b.AgentId] = $b
                }
            }
        }

        Write-Verbose "Loaded $($baselineMap.Count) active baseline(s) into lookup hashtable"
    } catch {
        Write-Warning "Baseline query failed — treating as potential drift for safety"
        Write-Verbose "Baseline query error: $($_.Exception.Message)"
        $baselineQueryFailed = $true
        $AlertRequired = $true
    }

    #endregion

    #region Per-agent drift detection

    Write-Verbose "Running per-agent drift detection"

    $driftDetails = @()
    $globalIsFirstRun = $false

    if ($baselineQueryFailed -or $baselineMap.Count -eq 0) {
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
            AgentId            = $agentId
            AgentName          = $agent.AgentName
            EnvironmentId      = $agent.EnvironmentId
            EnvironmentName    = $agent.EnvironmentDisplayName
            Zone               = $agent.Zone
            HasDrift           = $false
            IsFirstRun         = $false
            Direction          = $null
            BaselineFileUpload = $null
            CurrentFileUpload  = [bool]$agent.FileUploadEnabled
        }

        if ($globalIsFirstRun) {
            $driftEntry.IsFirstRun = $true
        } elseif ($baselineMap.ContainsKey($agentId)) {
            $baseline = $baselineMap[$agentId]
            $baselineEnabled = [bool]$baseline.FileUploadEnabled
            $driftEntry.BaselineFileUpload = $baselineEnabled

            if ($agent.FileUploadEnabled -ne $baselineEnabled) {
                $direction = Get-FileUploadDriftDirection `
                    -BaselineEnabled $baselineEnabled `
                    -CurrentEnabled ([bool]$agent.FileUploadEnabled)

                $driftEntry.HasDrift = $true
                $driftEntry.Direction = $direction
            }
        } else {
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
    foreach ($v in $violationResults) {
        $violations += [PSCustomObject]@{
            AgentId                = $v.AgentId
            AgentName              = $v.AgentName
            EnvironmentId          = $v.EnvironmentId
            EnvironmentDisplayName = $v.EnvironmentDisplayName
            Zone                   = $v.Zone
            ViolationType          = $v.ViolationType
            ExpectedFileUpload     = $v.ExpectedFileUpload
            ActualFileUpload       = if ($null -eq $v.FileUploadEnabled) { 'Indeterminate' } elseif ($v.FileUploadEnabled) { 'Enabled' } else { 'Disabled' }
            ExpectedModeration     = $v.ExpectedModerationLevel
            ActualModeration       = $v.ContentModerationLevel
            Severity               = $v.Severity
            RegulatoryContext      = $v.RegulatoryContext
        }
    }

    #endregion

    #region Determine alert flags

    $hasViolations = $violations.Count -gt 0
    $hasWeakenedDrift = @($driftedAgents | Where-Object { $_.Direction -eq 'Weakened' }).Count -gt 0
    $alertRequired = $hasViolations -or $hasWeakenedDrift -or $baselineQueryFailed

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

    # Zone 3 weakened drift (file upload enabled in enterprise zone) escalates to Critical
    $zone3Weakened = @($driftedAgents | Where-Object { $_.Direction -eq 'Weakened' -and $_.Zone -match '3' })
    if ($zone3Weakened.Count -gt 0) {
        $alertSeverity = 'Critical'
    }

    # Build reason string
    $reason = switch ($overallStatus) {
        'Passed'  { "All $totalAgents agents across $uniqueEnvs environments compliant ($fileUploadEnabledCount with file upload enabled)" }
        'Warning' { "$violationCount violation(s) across $uniqueEnvs environments ($fileUploadEnabledCount agents with file upload enabled)" }
        'Failed'  { "$violationCount violation(s) including high/critical severity ($fileUploadEnabledCount agents with file upload enabled)" }
        default   { "Validation completed with status: $overallStatus" }
    }

    if ($hasDrift) {
        $reason += "; $($driftedAgents.Count) agent(s) drifted from baseline"
    }

    #endregion

    #region Build enriched ZoneSummary

    $zoneTotals = @{ 'Zone1' = 0; 'Zone2' = 0; 'Zone3' = 0 }
    $zoneViolations = @{ 'Zone1' = 0; 'Zone2' = 0; 'Zone3' = 0 }

    foreach ($agent in $scanResult) {
        $zoneKey = $agent.Zone -replace '\s', ''
        if ($zoneKey -and $zoneTotals.ContainsKey($zoneKey)) {
            $zoneTotals[$zoneKey]++
        }
    }

    foreach ($v in $violationResults) {
        $zoneKey = $v.Zone -replace '\s', ''
        if ($zoneKey -and $zoneViolations.ContainsKey($zoneKey)) {
            $zoneViolations[$zoneKey]++
        }
    }

    $enrichedZoneSummary = [ordered]@{}
    foreach ($z in @('Zone1', 'Zone2', 'Zone3')) {
        $total = [int]$zoneTotals[$z]
        $violCount = [int]$zoneViolations[$z]

        $enrichedZoneSummary[$z] = [PSCustomObject]@{
            Total      = $total
            Compliant  = $total - $violCount
            Violations = $violCount
        }
    }

    Write-Verbose "Zone summary: Z1=$($enrichedZoneSummary.'Zone1'.Total)/$($enrichedZoneSummary.'Zone1'.Compliant), Z2=$($enrichedZoneSummary.'Zone2'.Total)/$($enrichedZoneSummary.'Zone2'.Compliant), Z3=$($enrichedZoneSummary.'Zone3'.Total)/$($enrichedZoneSummary.'Zone3'.Compliant)"

    #endregion

    #region Build and emit output

    $output = [PSCustomObject]@{
        RunType                = "FileUploadValidation"
        Timestamp              = (Get-Date -AsUTC -Format "o")
        TotalAgents            = $totalAgents
        TotalEnvironments      = $uniqueEnvs
        FileUploadEnabledCount = $fileUploadEnabledCount
        OverallStatus          = $overallStatus
        Reason                 = $reason
        ZoneSummary            = [PSCustomObject]$enrichedZoneSummary
        Violations             = $violations
        Drift                  = [PSCustomObject]@{
            HasDrift      = $hasDrift
            IsFirstRun    = $globalIsFirstRun
            DriftedAgents = $driftedAgents.Count
            Details       = $driftDetails
        }
        AlertRequired     = $alertRequired
        AlertSeverity     = $alertSeverity
    }

    Write-Verbose "Alert required: $($output.AlertRequired)"
    Write-Verbose "Alert severity: $($output.AlertSeverity)"

    $jsonOutput = $output | ConvertTo-Json -Depth 10
    Write-Verbose "JSON output length: $($jsonOutput.Length) characters"

    # This is the ONLY output — Azure Automation captures this as job output
    $jsonOutput

    #endregion

} catch {
    Write-Verbose "Error occurred: $($_.Exception.Message)"

    $errorOutput = [PSCustomObject]@{
        RunType                = "FileUploadValidation"
        Timestamp              = (Get-Date -AsUTC -Format "o")
        TotalAgents            = 0
        TotalEnvironments      = 0
        FileUploadEnabledCount = 0
        OverallStatus          = "Error"
        Reason                 = $_.Exception.Message
        ZoneSummary            = [PSCustomObject]@{}
        Violations             = @()
        Drift                  = [PSCustomObject]@{
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
