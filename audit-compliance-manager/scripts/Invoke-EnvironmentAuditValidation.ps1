#Requires -Version 7.2
#Requires -Modules @{ ModuleName="Microsoft.PowerApps.Administration.PowerShell"; ModuleVersion="2.0.180" }

<#
.SYNOPSIS
    Orchestrates environment-level audit configuration validation for Power Platform environments.

.DESCRIPTION
    Executes comprehensive environment-level audit validation across all Power Platform
    environments in the tenant. This orchestrator:

    1. Discovers all environments via Invoke-EnvironmentDiscovery
    2. For each environment in the validation set:
       - Validates Dataverse audit enablement (Test-EnvironmentAudit)
       - Validates retention period against zone thresholds (Test-EnvironmentRetention)
    3. Stores all validation results in Dataverse with correlated RunId
    4. Displays color-coded console report
    5. Optionally exports full results to JSON file

    Each environment is validated in isolation (try-catch per environment). Failures
    in one environment do not prevent validation of others, allowing administrators
    to see the complete compliance picture across all environments.

    Results are written to the Dataverse fsi_auditvalidationhistory table for
    immutable audit evidence and compliance reporting.

    This script supports FSI-AgentGov Control 1.7 (Audit Trail Enablement) by
    verifying per-environment audit configuration and retention compliance.

.PARAMETER TenantId
    Microsoft Entra ID tenant ID. Required for authentication.

.PARAMETER DataverseUrl
    Central Dataverse organization URL where the environment registryand validation
    history tables are stored. This is typically a dedicated governance environment.
    Example: https://governance.crm.dynamics.com

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID for service principal authentication. Optional
    when using interactive authentication.

.PARAMETER ClientSecret
    Legacy dev-only client secret for service principal authentication. Prefer certificate-based auth or managed identity where supported. Must be provided as SecureString.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication (preferred over
    legacy dev-only client secret fallback).

.PARAMETER Interactive
    Use interactive device code or browser-based authentication instead of service
    principal authentication.

.PARAMETER IncludeTrialDev
    Override to include Trial and Developer environments in validation. By default,
    these are excluded unless the environment registry has fsi_overrideinclude set
    to true for a specific environment.

.PARAMETER GracePeriodHours
    Hours after audit enablement to allow before treating absence as failure. Default: 24.
    Passed to Test-EnvironmentAudit for grace period evaluation.

.PARAMETER OutputPath
    Optional path to write full validation results as JSON file. If omitted, results
    only display to console.

.PARAMETER SkipDiscovery
    Skip the discovery phase and use existing environment registry data. Useful for
    faster repeat validations when environment list has not changed. Default: false.

.EXAMPLE
    Invoke-EnvironmentAuditValidation `
        -TenantId "contoso.onmicrosoft.com" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -Interactive

    Runs full environment discovery and validation using interactive authentication.
    Results are displayed to console and stored in Dataverse.

.EXAMPLE
    Invoke-EnvironmentAuditValidation `
        -TenantId "contoso.onmicrosoft.com" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -Interactive `
        -OutputPath ".\environment-validation-results.json" `
        -SkipDiscovery

    Runs validation without re-discovering environments (uses existing registry).
    Exports results to JSON file for downstream processing.

.EXAMPLE
    $secret = ConvertTo-SecureString "client-secret" -AsPlainText -Force
    Invoke-EnvironmentAuditValidation `
        -TenantId "contoso.onmicrosoft.com" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -ClientId "12345..." `
        -ClientSecret $secret `
        -IncludeTrialDev

    Runs validation using service principal authentication and includes Trial/Developer
    environments in the validation set.

.OUTPUTS
    PSCustomObject with orchestration results:
    - RunId: GUID linking all validation records
    - Timestamp: ISO 8601 UTC timestamp
    - TotalEnvironments: Count of environments validated
    - PerEnvironmentResults: Array of per-environment validation results
    - OverallStatus: Passed | Failed | Warning | Error
    - NewEnvironments: Array of newly discovered environment names (if discovery ran)
    - SkippedUnclassified: Array of Unclassified environment names (need zone assignment)
    - SkippedTrialDev: Array of Trial/Developer environment names (excluded by policy)

.NOTES
    Version: 1.0.2
    Requires:
    - Microsoft.PowerApps.Administration.PowerShell module v2.0 or later
    - PowerShell 7.0 or later
    - Power Platform Admin or Entra Global Admin role
    - System Administrator role in central Dataverse environment

    Performance considerations:
    - Full validation (with discovery) takes 2-5 minutes depending on environment count
    - Use -SkipDiscovery for faster repeat validations (~30-60 seconds)
    - Each environment is validated sequentially with independent error handling

    Regulatory context:
    This orchestrator supports compliance with:
    - FINRA Rule 4511 (audit trail retention)
    - FINRA Rule 25-07 (AI agent communications supervision)
    - SEC Rule 17a-4 (2-year minimum retention for broker-dealer communications)
    - GLBA 501(b) (audit logging requirements)
    - SOX Section 302/404 (internal controls)
#>

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory = $false)]
    [string]$ClientId,

    [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory = $false)]
    [SecureString]$ClientSecret,

    [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory = $false)]
    [string]$CertificateThumbprint,

    [Parameter(ParameterSetName = 'Interactive', Mandatory = $false)]
    [switch]$Interactive,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeTrialDev,

    [Parameter(Mandatory = $false)]
    [int]$GracePeriodHours = 24,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [switch]$SkipDiscovery
)

$ErrorActionPreference = "Stop"

#region Initialization

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Environment Audit Configuration Validation      ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  FSI-AgentGov Control 1.7                        ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Dot-source required scripts
$scriptRoot = $PSScriptRoot
$dotSourceSafeVars = @{
    TenantId              = $TenantId
    DataverseUrl          = $DataverseUrl
    ClientId              = $ClientId
    ClientSecret          = $ClientSecret
    CertificateThumbprint = $CertificateThumbprint
    Interactive           = $Interactive
    IncludeTrialDev       = $IncludeTrialDev
    GracePeriodHours      = $GracePeriodHours
    OutputPath            = $OutputPath
    SkipDiscovery         = $SkipDiscovery
}
$privatePath = Join-Path $PSScriptRoot 'private'
$requiredHelpers = @(
    'Connect-PowerPlatform.ps1',
    'Write-ValidationResult.ps1'
)
foreach ($helper in $requiredHelpers) {
    $helperPath = Join-Path $privatePath $helper
    if (-not (Test-Path $helperPath)) {
        throw "Required helper script not found: $helperPath. Ensure the solution is installed correctly."
    }
    . $helperPath
}

$requiredScripts = @(
    'Test-EnvironmentAudit.ps1',
    'Test-EnvironmentRetention.ps1'
)
foreach ($script in $requiredScripts) {
    $scriptPath = Join-Path $PSScriptRoot $script
    if (-not (Test-Path $scriptPath)) {
        throw "Required script not found: $scriptPath. Ensure the solution is installed correctly."
    }
    . $scriptPath
}
foreach ($name in $dotSourceSafeVars.Keys) {
    Set-Variable -Name $name -Value $dotSourceSafeVars[$name] -Scope Local
}

# Generate RunId for correlated validation records after helper/validator dot-sourcing.
$runId = [Guid]::NewGuid()
$timestamp = Get-Date -AsUTC -Format "o"

Write-Host "Run ID:    $runId" -ForegroundColor Cyan
Write-Host "Timestamp: $timestamp" -ForegroundColor Cyan
Write-Host ""

# Build authentication parameter hashtable
$authParams = @{
    TenantId = $TenantId
}
if ($Interactive) {
    $authParams.Interactive = $true
}
if ($ClientId) {
    $authParams.ClientId = $ClientId
}
if ($ClientSecret) {
    $authParams.ClientSecret = $ClientSecret
}
if ($CertificateThumbprint) {
    $authParams.CertificateThumbprint = $CertificateThumbprint
}

# Initialize results object
$results = [PSCustomObject]@{
    RunId                 = $runId
    Timestamp             = $timestamp
    TotalEnvironments     = 0
    PerEnvironmentResults = @()
    OverallStatus         = "Unknown"
    NewEnvironments       = @()
    SkippedUnclassified   = @()
    SkippedTrialDev       = @()
}

#endregion

#region Authentication

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Authenticating to Power Platform and Dataverse   " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

try {
    $authResult = Connect-PowerPlatform @authParams -DataverseUrl $DataverseUrl
    $centralDataverseToken = $authResult.DataverseAccessToken

    Write-Host "✓ Authentication successful" -ForegroundColor Green
    Write-Host "  Power Platform Admin API: Connected" -ForegroundColor Gray
    Write-Host "  Central Dataverse:        $DataverseUrl" -ForegroundColor Gray
    Write-Host ""
}
catch {
    Write-Error "Authentication failed: $($_.Exception.Message)"
    throw
}

#endregion

#region Discovery Phase

$validationSet = @()

if (-not $SkipDiscovery) {
    Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Phase 1: Environment Discovery                    " -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    try {
        $discoveryParams = @{
            TenantId      = $TenantId
            DataverseUrl  = $DataverseUrl
        }
        if ($Interactive) { $discoveryParams.Interactive = $true }
        if ($ClientId) { $discoveryParams.ClientId = $ClientId }
        if ($ClientSecret) { $discoveryParams.ClientSecret = $ClientSecret }
        if ($CertificateThumbprint) { $discoveryParams.CertificateThumbprint = $CertificateThumbprint }
        if ($IncludeTrialDev) { $discoveryParams.IncludeTrialDev = $true }

        $discoveryResult = & "$scriptRoot\Invoke-EnvironmentDiscovery.ps1" @discoveryParams

        $results.NewEnvironments = $discoveryResult.NewEnvironments
        $results.SkippedUnclassified = $discoveryResult.SkippedUnclassified
        $results.SkippedTrialDev = $discoveryResult.SkippedTrialDev
        $validationSet = $discoveryResult.ValidationSet

        Write-Host ""
        Write-Host "Discovery Summary:" -ForegroundColor Cyan
        Write-Host "  Total discovered:       $($discoveryResult.TotalDiscovered)" -ForegroundColor Gray
        Write-Host "  New environments:       $($discoveryResult.NewEnvironments.Count)" -ForegroundColor Gray
        Write-Host "  Inactivated:            $($discoveryResult.InactivatedEnvironments.Count)" -ForegroundColor Gray
        Write-Host "  Skipped (unclassified): $($discoveryResult.SkippedUnclassified.Count)" -ForegroundColor Yellow
        Write-Host "  Skipped (Trial/Dev):    $($discoveryResult.SkippedTrialDev.Count)" -ForegroundColor Yellow
        Write-Host "  → Validation set:       $($validationSet.Count)" -ForegroundColor Green
        Write-Host ""

        if ($validationSet.Count -eq 0) {
            Write-Warning "No environments in validation set. Discovery complete but no environments to validate."
            Write-Host ""
            Write-Host "Possible reasons:" -ForegroundColor Yellow
            Write-Host "  - All environments are Unclassified (assign zones in registry)" -ForegroundColor Yellow
            Write-Host "  - All environments are Trial/Developer (use -IncludeTrialDev to override)" -ForegroundColor Yellow
            Write-Host ""
            return $results
        }
    }
    catch {
        Write-Error "Environment discovery failed: $($_.Exception.Message)"
        throw
    }
}
else {
    Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  Phase 1: Loading Existing Registry (Discovery Skipped)" -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    try {
        # Query registry for active, classified environments
        $registryFilter = "fsi_status eq 1 and fsi_zone ne 100000000"  # Active and not Unclassified

        if (-not $IncludeTrialDev) {
            # Exclude Trial (100000003) and Developer (100000002) unless override
            $registryFilter += " and (fsi_overrideinclude eq true or (fsi_environmenttype ne 100000002 and fsi_environmenttype ne 100000003))"
        }

        $registryUrl = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2/fsi_environmentregistries?`$filter=$registryFilter&`$select=fsi_environmentid,fsi_name,fsi_environmenturl,fsi_zone,fsi_environmenttype"

        $headers = @{
            "Authorization"    = "Bearer $centralDataverseToken"
            "Accept"           = "application/json"
            "OData-MaxVersion" = "4.0"
            "OData-Version"    = "4.0"
        }

        $registryResponse = Invoke-RestMethod -Uri $registryUrl -Method Get -Headers $headers -ErrorAction Stop

        foreach ($env in $registryResponse.value) {
            $validationSet += @{
                EnvironmentId   = $env.fsi_environmentid
                EnvironmentName = $env.fsi_name
                EnvironmentUrl  = $env.fsi_environmenturl
                Zone            = switch ($env.fsi_zone) {
                    100000001 { "Zone1" }
                    100000002 { "Zone2" }
                    100000003 { "Zone3" }
                    default { "Unclassified" }
                }
                EnvironmentType = $env.fsi_environmenttype
            }
        }

        Write-Host "✓ Loaded $($validationSet.Count) environments from registry" -ForegroundColor Green
        Write-Host ""

        if ($validationSet.Count -eq 0) {
            Write-Warning "No environments found in registry matching criteria."
            return $results
        }
    }
    catch {
        Write-Error "Failed to load environment registry: $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Validation Phase

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  Phase 2: Per-Environment Validation              " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

$results.TotalEnvironments = $validationSet.Count
$envCounter = 0

foreach ($env in $validationSet) {
    $envCounter++
    $envName = $env.EnvironmentName
    $envUrl = $env.EnvironmentUrl
    $envZone = $env.Zone
    $envId = $env.EnvironmentId

    Write-Host "[$envCounter/$($validationSet.Count)] Validating: $envName ($envZone)" -ForegroundColor Cyan

    $envResult = [PSCustomObject]@{
        EnvironmentId   = $envId
        EnvironmentName = $envName
        Zone            = $envZone
        AuditStatus     = "Unknown"
        RetentionStatus = "Unknown"
        OverallStatus   = "Unknown"
        AuditResult     = $null
        RetentionResult = $null
    }

    # Acquire Dataverse token for this specific environment
    $envToken = $null
    try {
        Write-Verbose "Acquiring Dataverse token for $envUrl"
        # Re-use Connect-PowerPlatform but target specific environment URL
        $envAuthParams = $authParams.Clone()
        $envAuthParams.DataverseUrl = $envUrl
        $envAuth = Connect-PowerPlatform @envAuthParams
        $envToken = $envAuth.DataverseAccessToken
    }
    catch {
        Write-Warning "  ✗ Failed to acquire token for $($envName): $($_.Exception.Message)"
        $envResult.OverallStatus = "Error"
        $envResult.AuditStatus = "Error"
        $envResult.RetentionStatus = "Error"
        $results.PerEnvironmentResults += $envResult
        continue
    }

    # Validate audit enablement
    try {
        $auditParams = @{
            EnvironmentUrl    = $envUrl
            AccessToken       = $envToken
            EnvironmentName   = $envName
            GracePeriodHours  = $GracePeriodHours
        }
        $auditResult = Test-EnvironmentAudit @auditParams
        $envResult.AuditResult = $auditResult
        $envResult.AuditStatus = $auditResult.OverallStatus

        # Write to Dataverse validation history
        $writeParams = @{
            DataverseUrl    = $DataverseUrl
            AccessToken     = $centralDataverseToken
            RunId           = $runId
            Scope           = "Environment"
            Severity        = $auditResult.OverallStatus
            ValidationType  = "EnvironmentAudit"
            RawValue        = $auditResult.RawValue
            Reason          = $auditResult.Reason
            Zone            = $envZone
            EnvironmentId   = $envId
            EnvironmentName = $envName
            RemediationHint = $auditResult.RemediationHint
        }
        Write-ValidationResult @writeParams

        Write-Verbose "  Audit: $($auditResult.OverallStatus)"
    }
    catch {
        Write-Warning "  ✗ Audit validation failed: $($_.Exception.Message)"
        $envResult.AuditStatus = "Error"
    }

    # Validate retention period
    try {
        $retentionParams = @{
            EnvironmentUrl      = $envUrl
            AccessToken         = $envToken
            DataverseUrl        = $DataverseUrl
            CentralAccessToken  = $centralDataverseToken
            Zone                = $envZone
            EnvironmentName     = $envName
        }
        $retentionResult = Test-EnvironmentRetention @retentionParams
        $envResult.RetentionResult = $retentionResult
        $envResult.RetentionStatus = $retentionResult.OverallStatus

        # Write to Dataverse validation history
        $writeParams = @{
            DataverseUrl    = $DataverseUrl
            AccessToken     = $centralDataverseToken
            RunId           = $runId
            Scope           = "Environment"
            Severity        = $retentionResult.OverallStatus
            ValidationType  = "EnvironmentRetention"
            RawValue        = $retentionResult.RawValue
            Reason          = $retentionResult.Reason
            Zone            = $envZone
            EnvironmentId   = $envId
            EnvironmentName = $envName
            RemediationHint = $retentionResult.RemediationHint
        }
        Write-ValidationResult @writeParams

        Write-Verbose "  Retention: $($retentionResult.OverallStatus)"
    }
    catch {
        Write-Warning "  ✗ Retention validation failed: $($_.Exception.Message)"
        $envResult.RetentionStatus = "Error"
    }

    # Compute per-environment overall status
    $statuses = @($envResult.AuditStatus, $envResult.RetentionStatus)
    if ($statuses -contains "Error" -or $statuses -contains "Failed") {
        $envResult.OverallStatus = "Failed"
    }
    elseif ($statuses -contains "Warning" -or $statuses -contains "GracePeriod") {
        $envResult.OverallStatus = "Warning"
    }
    elseif ($statuses -match "Passed") {
        $envResult.OverallStatus = "Passed"
    }
    else {
        $envResult.OverallStatus = "Unknown"
    }

    # Write per-environment orchestrator record
    try {
        $orchParams = @{
            DataverseUrl    = $DataverseUrl
            AccessToken     = $centralDataverseToken
            RunId           = $runId
            Scope           = "Environment"
            Severity        = $envResult.OverallStatus
            ValidationType  = "Orchestrator"
            RawValue        = "Audit=$($envResult.AuditStatus),Retention=$($envResult.RetentionStatus)"
            Reason          = "Per-environment validation orchestrator result"
            Zone            = $envZone
            EnvironmentId   = $envId
            EnvironmentName = $envName
            CheckCount      = 2
        }
        Write-ValidationResult @orchParams
    }
    catch {
        Write-Warning "  ✗ Failed to write orchestrator record: $($_.Exception.Message)"
    }

    # Update fsi_lastvalidated in registry
    try {
        $registryUpdateUrl = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2/fsi_environmentregistries?`$filter=fsi_environmentid eq '$envId'"
        $headers = @{
            "Authorization"    = "Bearer $centralDataverseToken"
            "Accept"           = "application/json"
            "OData-MaxVersion" = "4.0"
            "OData-Version"    = "4.0"
        }
        $registryLookup = Invoke-RestMethod -Uri $registryUpdateUrl -Method Get -Headers $headers -ErrorAction Stop

        if ($registryLookup.value -and $registryLookup.value.Count -gt 0) {
            $registryRecordId = $registryLookup.value[0].fsi_environmentregistryid
            $patchUrl = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2/fsi_environmentregistries($registryRecordId)"

            $patchBody = @{
                fsi_lastvalidated = (Get-Date -AsUTC -Format "o")
            } | ConvertTo-Json

            $patchHeaders = @{
                "Authorization"    = "Bearer $centralDataverseToken"
                "Content-Type"     = "application/json"
                "OData-MaxVersion" = "4.0"
                "OData-Version"    = "4.0"
            }

            Invoke-RestMethod -Uri $patchUrl -Method Patch -Headers $patchHeaders -Body $patchBody -ErrorAction Stop | Out-Null
            Write-Verbose "  Updated fsi_lastvalidated in registry"
        }
    }
    catch {
        Write-Warning "  ✗ Failed to update registry last validated timestamp: $($_.Exception.Message)"
    }

    $results.PerEnvironmentResults += $envResult

    # Console status indicator
    $statusColor = switch ($envResult.OverallStatus) {
        "Passed"  { "Green" }
        "Failed"  { "Red" }
        "Warning" { "Yellow" }
        "GracePeriod" { "Yellow" }
        default   { "Gray" }
    }
    Write-Host "  ✓ Complete: Audit=$($envResult.AuditStatus) | Retention=$($envResult.RetentionStatus) | Overall=$($envResult.OverallStatus)" -ForegroundColor $statusColor
    Write-Host ""
}

#endregion

#region Compute Overall Status

# Determine overall run status across all environments
$allStatuses = $results.PerEnvironmentResults | ForEach-Object { $_.OverallStatus }

if ($allStatuses -contains "Error" -or $allStatuses -contains "Failed") {
    $results.OverallStatus = "Failed"
}
elseif ($allStatuses -contains "Warning" -or $allStatuses -contains "GracePeriod") {
    $results.OverallStatus = "Warning"
}
elseif ($allStatuses -match "Passed" -and $allStatuses.Count -eq $results.TotalEnvironments) {
    $results.OverallStatus = "Passed"
}
else {
    $results.OverallStatus = "Unknown"
}

#endregion

#region Display Summary

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║    Environment Audit Validation Summary          ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan

# Run metadata
Write-Host ("║ Run ID:         {0,-33}║" -f $runId) -ForegroundColor Cyan
Write-Host ("║ Timestamp:      {0,-33}║" -f $timestamp) -ForegroundColor Cyan
Write-Host ("║ Environments:   {0,-33}║" -f "$($results.TotalEnvironments) validated") -ForegroundColor Cyan

# Overall status with color
$overallStatusLine = "║ Overall Status: "
Write-Host $overallStatusLine -NoNewline -ForegroundColor Cyan
$statusColor = switch ($results.OverallStatus) {
    "Passed"  { "Green" }
    "Failed"  { "Red" }
    "Warning" { "Yellow" }
    default   { "Gray" }
}
$statusText = ("{0,-33}║" -f $results.OverallStatus.ToUpper())
Write-Host $statusText -ForegroundColor $statusColor

Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan

# Per-environment summary table
Write-Host "║                                                  ║" -ForegroundColor Cyan
Write-Host "║  Environment Name            Zone   Audit  Ret. ║" -ForegroundColor Cyan
Write-Host "║  ────────────────────────────────────────────── ║" -ForegroundColor Cyan

foreach ($envResult in $results.PerEnvironmentResults) {
    $name = $envResult.EnvironmentName
    if ($name.Length -gt 25) { $name = $name.Substring(0, 22) + "..." }

    $zone = $envResult.Zone
    $audit = $envResult.AuditStatus.Substring(0, [Math]::Min(6, $envResult.AuditStatus.Length))
    $retention = $envResult.RetentionStatus.Substring(0, [Math]::Min(4, $envResult.RetentionStatus.Length))

    $line = "║  {0,-28} {1,-6} {2,-6} {3,-4} ║" -f $name, $zone, $audit, $retention
    $color = switch ($envResult.OverallStatus) {
        "Passed"  { "Green" }
        "Failed"  { "Red" }
        "Warning" { "Yellow" }
        "GracePeriod" { "Yellow" }
        default   { "Gray" }
    }
    Write-Host $line -ForegroundColor $color
}

Write-Host "║                                                  ║" -ForegroundColor Cyan

# Summary counts
$passedCount = ($results.PerEnvironmentResults | Where-Object { $_.OverallStatus -eq "Passed" }).Count
$failedCount = ($results.PerEnvironmentResults | Where-Object { $_.OverallStatus -eq "Failed" }).Count
$warningCount = ($results.PerEnvironmentResults | Where-Object { $_.OverallStatus -in @("Warning", "GracePeriod") }).Count

Write-Host ("║ Passed:  {0,-41}║" -f "$passedCount environments") -ForegroundColor Green
Write-Host ("║ Failed:  {0,-41}║" -f "$failedCount environments") -ForegroundColor Red
Write-Host ("║ Warning: {0,-41}║" -f "$warningCount environments") -ForegroundColor Yellow

Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Display warnings for unclassified/excluded environments if any
if ($results.SkippedUnclassified.Count -gt 0) {
    Write-Host "⚠ Unclassified Environments (assign zones to enable validation):" -ForegroundColor Yellow
    foreach ($name in $results.SkippedUnclassified) {
        Write-Host "  - $name" -ForegroundColor Yellow
    }
    Write-Host ""
}

if ($results.SkippedTrialDev.Count -gt 0 -and -not $IncludeTrialDev) {
    Write-Host "⚠ Trial/Developer Environments (use -IncludeTrialDev to validate):" -ForegroundColor Yellow
    foreach ($name in $results.SkippedTrialDev) {
        Write-Host "  - $name" -ForegroundColor Yellow
    }
    Write-Host ""
}

if ($results.NewEnvironments.Count -gt 0) {
    Write-Host "ℹ New Environments Discovered (auto-registered as Unclassified):" -ForegroundColor Cyan
    foreach ($name in $results.NewEnvironments) {
        Write-Host "  - $name" -ForegroundColor Cyan
    }
    Write-Host ""
}

#endregion

#region Output

# Export to JSON if requested
if ($OutputPath) {
    try {
        $results | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding utf8
        Write-Host "✓ Results exported to: $OutputPath" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Warning "Failed to export results to JSON: $($_.Exception.Message)"
    }
}

# Return results object
return $results

#endregion
