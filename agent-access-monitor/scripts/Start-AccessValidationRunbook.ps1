#Requires -Version 7.1
#Requires -Modules @{ ModuleName="MSAL.PS"; ModuleVersion="4.37.0" }

<#
.SYNOPSIS
    Azure Automation runbook wrapper for agent access compliance validation.

.DESCRIPTION
    Adapts Test-AgentAccessCompliance.ps1 for Azure Automation execution context.
    This runbook provides non-interactive authentication, structured JSON output to
    the pipeline, and drift detection logic for downstream alerting.

    Key differences from interactive orchestrator:
    - Uses certificate-based authentication (no interactive prompts)
    - Scans all governance zones in a single run (no -Zone parameter)
    - Outputs JSON to pipeline (captured by Get-AzAutomationJobOutput)
    - Includes per-environment drift detection via Dataverse baseline comparison
    - Adds AlertRequired flag for Power Automate flow routing
    - No Write-Host (uses Write-Verbose for diagnostics)

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
        -CertificateThumbprint "ABCDEF123456" `
        -DataverseUrl "https://governance.crm.dynamics.com"

    Runs access validation across all zones using certificate authentication.
    Outputs JSON to pipeline for Power Automate consumption.

.EXAMPLE
    Start-AccessValidationRunbook `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -CertificateThumbprint "ABCDEF123456" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -GracePeriodHours 0

    Runs validation with no grace period - all environments are evaluated immediately.

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
    Version: 1.0.0

    Azure Automation setup:
    1. Import this script as a runbook
    2. Upload certificate to Automation Account > Certificates
    3. Install required modules: MSAL.PS, Microsoft.PowerApps.Administration.PowerShell
    4. Grant application permissions as required by Power Platform admin APIs
    5. Schedule via Schedules or trigger via webhook

    Performance:
    - Typical scan across environments: 2-5 minutes depending on environment count

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

    switch ($SettingName) {
        'bot-limitSharingMode' {
            return Get-SharingDriftDirection -OrderMap $sharingModeOrder `
                -BaselineValue $BaselineValue -CurrentValue $CurrentValue
        }
        'bot-publishedBotLimitSharingMode' {
            return Get-SharingDriftDirection -OrderMap $sharingModeOrder `
                -BaselineValue $BaselineValue -CurrentValue $CurrentValue
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

    #region Connect AAMClient to Dataverse

    Import-Module "$scriptRoot\private\AAMClient.psm1" -Force
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
    # with BotLimitSharingMode, BotAuthoringSharingDisabled, BotPublishedLimitSharingMode)
    $getSettingsScript = Join-Path $scriptRoot 'Get-EnvironmentAccessSettings.ps1'
    $envSettingsParams = @{ GracePeriodHours = $GracePeriodHours }
    if ($ExcludeSandbox) { $envSettingsParams['ExcludeSandbox'] = $true }
    if ($ExcludeTrial) { $envSettingsParams['ExcludeTrial'] = $true }
    $allEnvironments = & $getSettingsScript @envSettingsParams

    $driftResults = @()

    foreach ($env in $allEnvironments) {
        $envId = $env.EnvironmentId
        $envName = $env.EnvironmentDisplayName

        Write-Verbose "Checking drift for: $envName ($envId)"

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
            # replicating per-environment $orderby=fsi_captured_at desc semantics.
            # Profile actual environment counts before optimizing.
            $baseline = Get-AAMActiveBaseline -EnvironmentId $envId

            if (-not $baseline -or $baseline.Count -eq 0) {
                # No baseline exists - first run for this environment
                Write-Verbose "No active baseline for $envName - first run"
                $driftEntry.IsFirstRun = $true
            } else {
                $bl = $baseline | Select-Object -First 1

                # Check for stale baseline
                if ($bl.fsi_captured_at) {
                    $capturedAt = [datetime]$bl.fsi_captured_at
                    $ageInDays = ((Get-Date).ToUniversalTime() - $capturedAt).TotalDays
                    if ($ageInDays -gt $baselineMaxAgeDays) {
                        Write-Verbose "Stale baseline for ${envName}: $([math]::Round($ageInDays, 1)) days old (max: $baselineMaxAgeDays)"
                        $driftEntry.IsStaleBaseline = $true
                    }
                }

                # Compare 3 key settings
                # Normalize null to empty string so null-vs-'' from Dataverse vs API does not produce false drift
                $settingsToCheck = @(
                    @{
                        Name     = 'bot-limitSharingMode'
                        Baseline = if ($null -eq $bl.fsi_bot_limit_sharing_mode) { '' } else { [string]$bl.fsi_bot_limit_sharing_mode }
                        Current  = if ($null -eq $env.BotLimitSharingMode) { '' } else { [string]$env.BotLimitSharingMode }
                    },
                    @{
                        Name     = 'bot-authoringSharingDisabled'
                        Baseline = if ($null -eq $bl.fsi_bot_authoring_sharing_disabled) { '' } else { [string]$bl.fsi_bot_authoring_sharing_disabled }
                        Current  = if ($null -eq $env.BotAuthoringSharingDisabled) { '' } else { [string]$env.BotAuthoringSharingDisabled }
                    },
                    @{
                        Name     = 'bot-publishedBotLimitSharingMode'
                        Baseline = if ($null -eq $bl.fsi_bot_published_bot_limit_sharing_mode) { '' } else { [string]$bl.fsi_bot_published_bot_limit_sharing_mode }
                        Current  = if ($null -eq $env.BotPublishedLimitSharingMode) { '' } else { [string]$env.BotPublishedLimitSharingMode }
                    }
                )

                foreach ($setting in $settingsToCheck) {
                    if ($setting.Baseline -ne $setting.Current) {
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
        Timestamp         = (Get-Date -AsUTC -Format "o")
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
        Timestamp         = (Get-Date -AsUTC -Format "o")
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
