#Requires -Version 7.4

<#
.SYNOPSIS
    Standalone runbook for agent access compliance validation across governance zones.

.DESCRIPTION
    Runs Test-AgentAccessCompliance logic in a non-interactive, pipeline-friendly form
    suitable for scheduled local execution (pwsh 7.4 via Windows Task Scheduler or cron).
    Provides modern-auth token acquisition, structured JSON output to the pipeline, and
    per-environment drift detection for downstream alerting.

    Deferred Azure Automation (lab model): for the lab this runbook runs standalone on a
    workstation or build agent — no Azure subscription, Automation Account, premium
    connector, or always-on service principal is required. The daily Power Automate flow
    is reduced to a Recurrence trigger plus a Dataverse read of the validation-history and
    violation tables this runbook writes. Promoting to Azure Automation later is a
    packaging step, not a code change.

    Key characteristics:
    - Modern OAuth 2.0 authentication via Get-AAMAccessToken (device-code or service
      principal secret); the archived MSAL.PS module is no longer used
    - Scans all governance zones in a single run (no -Zone parameter)
    - Outputs JSON to the pipeline (capturable by any scheduler or the calling flow)
    - Includes per-environment drift detection via Dataverse baseline comparison
    - Adds AlertRequired flag for Power Automate flow routing
    - No Write-Host (uses Write-Verbose for diagnostics)

    Output structure enables Power Automate to parse validation results and route alerts
    based on severity and drift status.

.PARAMETER TenantId
    Microsoft Entra ID tenant ID for authentication.

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID. Required for both -Interactive
    (public-client app) and service-principal (client-secret) authentication.

.PARAMETER Interactive
    Use device-code authentication. The user copies a one-time code into
    https://microsoft.com/devicelogin from any browser. Recommended for local lab runs.

.PARAMETER ClientSecret
    Service-principal client secret (SecureString) for unattended runs. Dev-only legacy
    fallback; production should use a managed identity. Used when -Interactive is omitted.

.PARAMETER CertificateThumbprint
    [DEPRECATED] Certificate-thumbprint authentication required the archived MSAL.PS
    module. Passing this parameter now throws a terminating error. Use -Interactive or
    -ClientSecret instead.

.PARAMETER DataverseUrl
    Central Dataverse organization URL where validation history and baselines are stored.
    Example: https://governance.crm.dynamics.com

.PARAMETER ExcludeSandbox
    Exclude Sandbox type environments from compliance scan. Default: $true.

.PARAMETER ExcludeTrial
    Exclude Trial type environments from compliance scan. Default: $true.

.PARAMETER GracePeriodHours
    Hours to exclude newly created environments from violation reporting.
    Valid range: 0-168. Default: 48 hours.

.EXAMPLE
    Start-AccessValidationRunbook `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -Interactive

    Runs access validation across all zones using device-code authentication.
    Outputs JSON to the pipeline for Power Automate consumption.

.EXAMPLE
    $secret = Read-Host -AsSecureString "Client secret"
    Start-AccessValidationRunbook `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -ClientSecret $secret `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -GracePeriodHours 0

    Runs validation unattended (service principal) with no grace period - all
    environments are evaluated immediately.

.OUTPUTS
    JSON object with properties:
    - RunType: "AccessValidation"
    - Timestamp: ISO 8601 UTC timestamp
    - TotalEnvironments: Count of scanned environments
    - OverallStatus: Passed | Warning | Failed | Error
    - Reason: Summary explanation
    - ZoneSummary: Hashtable with Zone1/Zone2/Zone3/Unknown counts
    - Violations: Array of violation details
    - Drift: Array of per-environment drift detection results
    - AlertRequired: Boolean flag for flow routing
    - AlertSeverity: Status value for alert priority

.NOTES
    Version: 1.2.0

    Local scheduled execution (lab default):
    1. Install PowerShell 7.4 and the Microsoft.PowerApps.Administration.PowerShell module
    2. Register a public-client app (for -Interactive) or a confidential app with a secret
    3. Grant the app the Power Platform admin and Dataverse permissions it needs
    4. Schedule via Windows Task Scheduler (pwsh -File ...) and capture the JSON output
    5. Point a Power Automate Recurrence flow at the Dataverse tables this runbook writes

    Deferring to Azure Automation later: import this script as a runbook, supply the same
    parameters via Automation variables, and schedule it there. No code change is required;
    only -CertificateThumbprint remains unsupported (use -ClientSecret or managed identity).

    Performance:
    - Typical scan across environments: 2-5 minutes depending on environment count
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$ClientId,

    [Parameter()]
    [switch]$Interactive,

    [Parameter()]
    [securestring]$ClientSecret,

    [Parameter()]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory)]
    [string]$DataverseUrl,

    [bool]$ExcludeSandbox = $true,

    [bool]$ExcludeTrial = $true,

    [ValidateRange(0, 168)]
    [int]$GracePeriodHours = 48
)

$ErrorActionPreference = "Stop"

#region Helper Functions

function Get-DriftDirection {
    <#
    .SYNOPSIS
        Classifies drift direction for a setting change.
    .DESCRIPTION
        Compares baseline and current values to determine if a change represents
        a weakened (more permissive), strengthened (more restrictive), or other change.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SettingName,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$BaselineValue,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$CurrentValue
    )

    # Restrictiveness orderings (most restrictive first)
    $sharingModeOrder = @{
        'ExcludeSharingToSecurityGroups' = 1
        'noLimit'                        = 2
    }
    # Viewer-cap categories (most restrictive first). Capped = a finite limit;
    # Uncapped = no limit (-1, 0, blank, or unset).
    $maxLimitOrder = @{
        'Capped'   = 1
        'Uncapped' = 2
    }

    switch ($SettingName) {
        'bot-limitSharingMode' {
            return Get-SharingDriftDirection -OrderMap $sharingModeOrder `
                -BaselineValue $BaselineValue -CurrentValue $CurrentValue
        }
        'bot-maxLimitUserSharing' {
            # Normalize the numeric viewer cap to a category before ranking:
            # any positive integer => Capped (restrictive); -1, 0, blank, or unset
            # => Uncapped (permissive).
            $blParsed = 0
            $curParsed = 0
            $blCat = if ([int]::TryParse(([string]$BaselineValue).Trim(), [ref]$blParsed) -and $blParsed -gt 0) { 'Capped' } else { 'Uncapped' }
            $curCat = if ([int]::TryParse(([string]$CurrentValue).Trim(), [ref]$curParsed) -and $curParsed -gt 0) { 'Capped' } else { 'Uncapped' }
            return Get-SharingDriftDirection -OrderMap $maxLimitOrder `
                -BaselineValue $blCat -CurrentValue $curCat
        }
        'bot-authoringSharingDisabled' {
            # true = more restrictive, false = more permissive
            if ($BaselineValue -eq 'True' -and $CurrentValue -eq 'False') {
                return 'Weakened'
            } elseif ($BaselineValue -eq 'False' -and $CurrentValue -eq 'True') {
                return 'Strengthened'
            }
            return 'Changed'
        }
        default {
            return 'Changed'
        }
    }
}

function Get-SharingDriftDirection {
    <#
    .SYNOPSIS
        Determines drift direction for sharing mode settings using an ordered map.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$OrderMap,

        [string]$BaselineValue,
        [string]$CurrentValue
    )

    $baselineRank = $OrderMap[$BaselineValue]
    $currentRank = $OrderMap[$CurrentValue]

    if ($null -eq $baselineRank -or $null -eq $currentRank) {
        return 'Changed'
    }

    if ($currentRank -gt $baselineRank) {
        return 'Weakened'
    } elseif ($currentRank -lt $baselineRank) {
        return 'Strengthened'
    }

    return 'Changed'
}

#endregion

try {
    Write-Verbose "Starting access validation runbook"
    Write-Verbose "TenantId: $TenantId"
    Write-Verbose "DataverseUrl: $DataverseUrl"

    $scriptRoot = $PSScriptRoot
    Write-Verbose "Script root: $scriptRoot"

    #region Authenticate and acquire Dataverse token

    # Import the AAMClient module first so its modern-auth helper (Get-AAMAccessToken)
    # is available. C2 remediation: the archived MSAL.PS module is no longer used.
    Import-Module "$scriptRoot\private\AAMClient.psm1" -Force

    if ($CertificateThumbprint) {
        throw "CertificateThumbprint authentication was removed (it required the archived MSAL.PS module). Use -Interactive for device-code flow, or -ClientSecret for service-principal authentication."
    }

    Write-Verbose "Acquiring Dataverse token via modern OAuth 2.0 (Get-AAMAccessToken)"
    $tokenParams = @{
        TenantId = $TenantId
        ClientId = $ClientId
        Resource = $DataverseUrl
    }
    if ($Interactive)  { $tokenParams['Interactive']  = $true }
    if ($ClientSecret) { $tokenParams['ClientSecret'] = $ClientSecret }
    $dataverseToken = Get-AAMAccessToken @tokenParams
    Write-Verbose "Dataverse token acquired"

    #endregion

    #region Connect AAMClient to Dataverse

    Connect-AAMDataverse -DataverseUrl $DataverseUrl -AccessToken $dataverseToken

    # Read operational parameters from Dataverse environment variables
    $dvGracePeriod = Get-AAMEnvironmentVariable -Name "GracePeriodHours" -DefaultValue $GracePeriodHours
    if ($dvGracePeriod -ne $GracePeriodHours) {
        Write-Verbose "Dataverse override: GracePeriodHours=$dvGracePeriod (was $GracePeriodHours)"
        $GracePeriodHours = [int]$dvGracePeriod
    }

    $dvIncludeSandbox = Get-AAMEnvironmentVariable -Name "IncludeSandbox" -DefaultValue "false"
    if ($dvIncludeSandbox -eq "true" -and $ExcludeSandbox) {
        Write-Verbose "Dataverse override: IncludeSandbox=true, overriding -ExcludeSandbox switch"
        $ExcludeSandbox = $false
    }

    $baselineMaxAgeDays = [int](Get-AAMEnvironmentVariable -Name "BaselineMaxAgeDays" -DefaultValue 30)
    Write-Verbose "BaselineMaxAgeDays: $baselineMaxAgeDays"

    Write-Verbose "Dataverse parameters loaded"

    #endregion

    #region Run compliance scan

    Write-Verbose "Invoking Test-AgentAccessCompliance"

    $complianceScript = Join-Path $scriptRoot 'Test-AgentAccessCompliance.ps1'
    if (-not (Test-Path $complianceScript)) {
        throw "Required script not found: $complianceScript"
    }

    $scanParams = @{
        PersistResults = $true
        DataverseUrl   = $DataverseUrl
        DataverseToken = $dataverseToken
        OutputFormat   = 'Object'
        GracePeriodHours = $GracePeriodHours
    }

    if ($ExcludeSandbox) { $scanParams['ExcludeSandbox'] = $true }
    if ($ExcludeTrial)   { $scanParams['ExcludeTrial'] = $true }

    $scanResult = & $complianceScript @scanParams

    Write-Verbose "Scan complete. Overall status: $($scanResult.OverallStatus)"
    Write-Verbose "Total environments: $($scanResult.Summary.TotalEnvironments)"

    #endregion

    #region Drift detection per environment

    Write-Verbose "Running per-environment drift detection against active baselines"

    # Query environment settings directly for drift detection (includes all environments
    # with BotLimitSharingMode, BotAuthoringSharingDisabled, BotMaxLimitUserSharing)
    $getSettingsScript = Join-Path $scriptRoot 'Get-EnvironmentAccessSettings.ps1'
    $envSettingsParams = @{ GracePeriodHours = $GracePeriodHours }
    if ($ExcludeSandbox) { $envSettingsParams['ExcludeSandbox'] = $true }
    if ($ExcludeTrial) { $envSettingsParams['ExcludeTrial'] = $true }
    # Pass Dataverse context so zone classification uses ELM lookup, not name-based fallback.
    if ($DataverseUrl)     { $envSettingsParams['DataverseUrl'] = $DataverseUrl }
    if ($dataverseToken)   { $envSettingsParams['AccessToken']  = $dataverseToken }
    $allEnvironments = & $getSettingsScript @envSettingsParams

    $driftResults = @()

    foreach ($env in $allEnvironments) {
        $envId = $env.EnvironmentId
        $envName = $env.EnvironmentDisplayName

        Write-Verbose "Checking drift for: $envName ($envId)"

        # H1: non-Managed environments expose none of the agent-sharing controls, so
        # there is no baseline to drift from. Skip drift evaluation and record the
        # environment as out-of-scope rather than emitting a spurious first-run entry.
        if ($env.Status -eq 'NotManaged') {
            Write-Verbose "Skipping drift for non-Managed environment: $envName"
            $driftResults += [PSCustomObject]@{
                EnvironmentId   = $envId
                EnvironmentName = $envName
                Zone            = $env.Zone
                HasDrift        = $false
                IsFirstRun      = $false
                IsStaleBaseline = $false
                Changes         = @()
                Direction       = $null
                Status          = 'ScopeOutOfBand'
            }
            continue
        }

        $driftEntry = @{
            EnvironmentId   = $envId
            EnvironmentName = $envName
            Zone            = $env.Zone
            HasDrift        = $false
            IsFirstRun      = $false
            IsStaleBaseline = $false
            Changes         = @()
            Direction       = $null
        }

        try {
            # NOTE: Per-environment baseline query (N+1 pattern). A batch approach
            # would reduce HTTP calls but requires careful pagination handling and
            # replicating per-environment $orderby=fsi_capturedat desc semantics.
            # Profile actual environment counts before optimizing.
            $baseline = Get-AAMActiveBaseline -EnvironmentId $envId

            if (-not $baseline -or $baseline.Count -eq 0) {
                # No baseline exists - first run for this environment
                Write-Verbose "No active baseline for $envName - first run"
                $driftEntry.IsFirstRun = $true
            } else {
                $bl = $baseline | Select-Object -First 1

                # Check for stale baseline
                if ($bl.fsi_capturedat) {
                    try {
                        $capturedAt = [datetime]$bl.fsi_capturedat
                        $ageInDays = ((Get-Date).ToUniversalTime() - $capturedAt).TotalDays
                        if ($ageInDays -gt $baselineMaxAgeDays) {
                            Write-Verbose "Stale baseline for ${envName}: $([math]::Round($ageInDays, 1)) days old (max: $baselineMaxAgeDays)"
                            $driftEntry.IsStaleBaseline = $true
                        }
                    } catch {
                        Write-Warning "Invalid captured_at timestamp for ${envName}: $($_.Exception.Message)"
                    }
                }

                # Compare 3 key settings
                # Normalize null to empty string so null-vs-'' from Dataverse vs API does not produce false drift
                $settingsToCheck = @(
                    @{
                        Name     = 'bot-limitSharingMode'
                        Baseline = if ($null -eq $bl.fsi_botlimitsharingmode) { '' } else { [string]$bl.fsi_botlimitsharingmode }
                        Current  = if ($null -eq $env.BotLimitSharingMode) { '' } else { [string]$env.BotLimitSharingMode }
                    },
                    @{
                        Name     = 'bot-authoringSharingDisabled'
                        Baseline = if ($null -eq $bl.fsi_botauthoringsharingdisabled) { '' } else { [string]$bl.fsi_botauthoringsharingdisabled }
                        Current  = if ($null -eq $env.BotAuthoringSharingDisabled) { '' } else { [string]$env.BotAuthoringSharingDisabled }
                    },
                    @{
                        Name     = 'bot-maxLimitUserSharing'
                        Baseline = if ($null -eq $bl.fsi_botmaxlimitusersharing) { '' } else { [string]$bl.fsi_botmaxlimitusersharing }
                        Current  = if ($null -eq $env.BotMaxLimitUserSharing) { '' } else { [string]$env.BotMaxLimitUserSharing }
                    }
                )

                foreach ($setting in $settingsToCheck) {
                    # H2: explicit case-insensitive comparison of baseline vs current.
                    if ($setting.Baseline -ine $setting.Current) {
                        $direction = Get-DriftDirection -SettingName $setting.Name `
                            -BaselineValue $setting.Baseline `
                            -CurrentValue $setting.Current

                        $driftEntry.HasDrift = $true
                        $driftEntry.Changes += [PSCustomObject]@{
                            Setting       = $setting.Name
                            BaselineValue = $setting.Baseline
                            CurrentValue  = $setting.Current
                            Direction     = $direction
                        }
                    }
                }

                # Overall drift direction: Weakened takes priority over Strengthened
                if ($driftEntry.Changes.Count -gt 0) {
                    if ($driftEntry.Changes.Direction -contains 'Weakened') {
                        $driftEntry.Direction = 'Weakened'
                    } elseif ($driftEntry.Changes.Direction -contains 'Strengthened') {
                        $driftEntry.Direction = 'Strengthened'
                    } else {
                        $driftEntry.Direction = 'Changed'
                    }
                }
            }
        } catch {
            # Fail open: on Dataverse query error, treat as first run (no drift)
            Write-Warning "Baseline query failed for $envName : $($_.Exception.Message). Failing open."
            $driftEntry.HasDrift = $false
            $driftEntry.IsFirstRun = $true
        }

        $driftResults += [PSCustomObject]$driftEntry
    }

    Write-Verbose "Drift detection complete. Environments with drift: $(($driftResults | Where-Object { $_.HasDrift }).Count)"

    #endregion

    #region Build violations array

    $violations = @()
    if ($scanResult.Environments) {
        foreach ($env in $scanResult.Environments) {
            if ($env.Violations) {
                foreach ($v in $env.Violations) {
                    $violations += [PSCustomObject]@{
                        EnvironmentId   = $env.EnvironmentId
                        EnvironmentName = $env.EnvironmentDisplayName
                        Zone            = $env.Zone
                        Setting         = $v.Setting
                        Expected        = $v.ExpectedValue
                        Actual          = $v.ActualValue
                        Severity        = $v.Severity
                        Regulatory      = $v.RegulatoryContext
                    }
                }
            }
        }
    }

    #endregion

    #region Determine alert flags

    $hasDrift = ($driftResults | Where-Object { $_.HasDrift }).Count -gt 0
    $hasStaleBaselines = ($driftResults | Where-Object { $_.IsStaleBaseline }).Count -gt 0
    $hasViolations = $violations.Count -gt 0
    $alertRequired = $hasViolations -or $hasDrift -or $hasStaleBaselines

    # Highest severity from violations (Critical > High > Warning > Info)
    $severityOrder = @('Critical', 'High', 'Warning', 'Info')
    $alertSeverity = $scanResult.OverallStatus

    if ($hasViolations) {
        foreach ($sev in $severityOrder) {
            if ($violations.Severity -contains $sev) {
                $alertSeverity = $sev
                break
            }
        }
    }

    # Build reason string
    $reason = switch ($scanResult.OverallStatus) {
        'Passed'  { "All $($scanResult.Summary.TotalEnvironments) environments compliant" }
        'Warning' { "$($scanResult.Summary.ViolationCount) violations detected across $($scanResult.Summary.TotalEnvironments) environments" }
        'Failed'  { "$($scanResult.Summary.CriticalViolations) critical violations detected" }
        'Review'  { "$($scanResult.Summary.ViolationCount) low-severity violations require review" }
        default   { "Validation completed with status: $($scanResult.OverallStatus)" }
    }

    if ($hasDrift) {
        $driftCount = ($driftResults | Where-Object { $_.HasDrift }).Count
        $reason += "; $driftCount environments drifted from baseline"
    }

    if ($hasStaleBaselines) {
        $staleCount = ($driftResults | Where-Object { $_.IsStaleBaseline }).Count
        $reason += "; $staleCount environments have stale baselines (>$baselineMaxAgeDays days)"
    }

    #endregion

    #region Build enriched ZoneSummary

    # The orchestrator produces simple integer counts per zone (Zone1=3, Zone2=5, etc.)
    # The flow Parse_Results schema expects objects: Zone1: { Total, Compliant, Violations }
    # Transform here so the flow and adaptive card can render per-zone detail.

    $zoneNonCompliant = @{ Zone1 = 0; Zone2 = 0; Zone3 = 0 }
    if ($scanResult.Environments) {
        foreach ($env in $scanResult.Environments) {
            $z = $env.Zone
            if ($z -and $zoneNonCompliant.ContainsKey($z)) {
                $zoneNonCompliant[$z]++
            }
        }
    }

    $enrichedZoneSummary = [ordered]@{}
    foreach ($z in @('Zone1', 'Zone2', 'Zone3')) {
        $total = 0
        if ($scanResult.ZoneSummary -and $scanResult.ZoneSummary.PSObject.Properties[$z]) {
            $total = [int]$scanResult.ZoneSummary.$z
        }
        $violationEnvCount = [int]$zoneNonCompliant[$z]

        $enrichedZoneSummary[$z] = [PSCustomObject]@{
            Total      = $total
            Compliant  = $total - $violationEnvCount
            Violations = $violationEnvCount
        }
    }

    Write-Verbose "Zone summary enriched: Z1=$($enrichedZoneSummary.Zone1.Total)/$($enrichedZoneSummary.Zone1.Compliant), Z2=$($enrichedZoneSummary.Zone2.Total)/$($enrichedZoneSummary.Zone2.Compliant), Z3=$($enrichedZoneSummary.Zone3.Total)/$($enrichedZoneSummary.Zone3.Compliant)"

    #endregion

    #region Build and emit output

    $output = [PSCustomObject]@{
        RunType           = "AccessValidation"
        Timestamp         = (Get-Date).ToUniversalTime().ToString("o")
        TotalEnvironments = $scanResult.Summary.TotalEnvironments
        OverallStatus     = $scanResult.OverallStatus
        Reason            = $reason
        ZoneSummary       = [PSCustomObject]$enrichedZoneSummary
        Violations        = $violations
        Drift             = $driftResults
        AlertRequired     = $alertRequired
        AlertSeverity     = $alertSeverity
    }

    Write-Verbose "Alert required: $($output.AlertRequired)"
    Write-Verbose "Alert severity: $($output.AlertSeverity)"

    # Convert to JSON and output to pipeline
    # This is the ONLY output - Azure Automation captures this as job output
    $jsonOutput = $output | ConvertTo-Json -Depth 10
    Write-Verbose "JSON output length: $($jsonOutput.Length) characters"

    $jsonOutput

    #endregion

} catch {
    Write-Verbose "Error occurred: $($_.Exception.Message)"

    $errorOutput = [PSCustomObject]@{
        RunType           = "AccessValidation"
        Timestamp         = (Get-Date).ToUniversalTime().ToString("o")
        TotalEnvironments = 0
        OverallStatus     = "Error"
        Reason            = $_.Exception.Message
        ZoneSummary       = [PSCustomObject]@{
            Zone1 = [PSCustomObject]@{ Total = 0; Compliant = 0; Violations = 0 }
            Zone2 = [PSCustomObject]@{ Total = 0; Compliant = 0; Violations = 0 }
            Zone3 = [PSCustomObject]@{ Total = 0; Compliant = 0; Violations = 0 }
        }
        Violations        = @()
        Drift             = @()
        AlertRequired     = $true
        AlertSeverity     = "Error"
    }

    $errorOutput | ConvertTo-Json -Depth 5
}
