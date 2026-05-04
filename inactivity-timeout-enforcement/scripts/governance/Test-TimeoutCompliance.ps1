#Requires -Version 7.0

<#
.SYNOPSIS
    Orchestrates inactivity timeout compliance scan and produces a summary report.

.DESCRIPTION
    Test orchestrator for the Inactivity Timeout Enforcement (ITE) solution.
    Invokes Invoke-TimeoutComplianceScan to retrieve per-environment compliance
    results, then computes aggregate statistics and an overall pass/warning/fail
    status across all scanned environments.

    Summary includes:
    - Total environments scanned
    - Compliant, non-compliant, and unknown counts (overall and per zone)
    - Overall status: Passed (all compliant), Warning (unknowns only), Failed (any non-compliant)

    Optionally persists results to Dataverse when -PersistResults is specified
    with a -DataverseUrl.

    This script supports Controls 2.22 (Inactivity Timeout), 1.23 (Session Security),
    and 3.7/3.8 (Monitoring) of the FSI Agent Governance Framework.

.PARAMETER OutputFormat
    Output format for the compliance report: Table (default), JSON, or Object.

.PARAMETER ExcludeSandbox
    Exclude sandbox environments from the scan. Default: $false; sandboxes are included unless this switch is specified.

.PARAMETER IncludeCompliant
    Include compliant environments in the detailed output (default: violations only
    in table output).

.PARAMETER TenantId
    Microsoft Entra ID tenant GUID. Defaults to $env:AZURE_TENANT_ID.

.PARAMETER ClientId
    Application/client ID for user-assigned managed identity or legacy client-secret fallback. Defaults to $env:AZURE_CLIENT_ID.

.PARAMETER ClientSecret
    Legacy dev-only client secret. Prefer managed identity for automation.

.PARAMETER UseManagedIdentity
    Prefer Azure managed identity for token acquisition.

.PARAMETER ManagedIdentityClientId
    Optional user-assigned managed identity client ID. Defaults to $env:AZURE_CLIENT_ID when present.

.PARAMETER BapApiBaseUrl
    Base URL for the Business Application Platform Admin API.

.PARAMETER DataverseUrl
    Dataverse organization URL. Required when -PersistResults is specified.

.PARAMETER PersistResults
    When specified, passes -DataverseUrl through to Invoke-TimeoutComplianceScan
    for Dataverse persistence of compliance records.

.OUTPUTS
    PSCustomObject with properties:
    - OverallStatus (string): Passed, Warning, or Failed
    - TotalEnvironments (int)
    - CompliantCount (int)
    - NonCompliantCount (int)
    - UnknownCount (int)
    - ByZone (PSCustomObject): Per-zone breakdown
    - Results (PSCustomObject[]): Individual environment results
    - RunId (string)
    - Timestamp (string)

.EXAMPLE
    .\Test-TimeoutCompliance.ps1

    Runs a full compliance scan and displays a summary table. Returns overall
    pass/fail status.

.EXAMPLE
    .\Test-TimeoutCompliance.ps1 -OutputFormat JSON -IncludeCompliant

    JSON output including compliant environments for evidence export.

.EXAMPLE
    .\Test-TimeoutCompliance.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -PersistResults `
        -OutputFormat Object

    Scan with Dataverse persistence, returning structured objects for pipeline use.

.NOTES
    Version: 1.1.1
    Solution: Inactivity Timeout Enforcement (ITE)
    Controls: 2.22 (Inactivity Timeout), 1.23 (Session Security), 3.7/3.8 (Monitoring)
    Regulations: GLBA Section 501(b), SOX Section 302/404, FINRA Rule 4511(a), NIST 800-53 AC-11/AC-12
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Table', 'JSON', 'Object')]
    [string]$OutputFormat = 'Table',

    [Parameter()]
    [switch]$ExcludeSandbox,

    [Parameter()]
    [switch]$IncludeCompliant,

    [Parameter()]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter()]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter()]
    [SecureString]$ClientSecret,

    [Parameter()]
    [switch]$UseManagedIdentity,

    [Parameter()]
    [string]$ManagedIdentityClientId = $env:AZURE_CLIENT_ID,

    [Parameter()]
    [string]$BapApiBaseUrl = 'https://api.bap.microsoft.com',

    [Parameter()]
    [string]$DataverseUrl,

    [Parameter()]
    [switch]$PersistResults
)

$ErrorActionPreference = 'Stop'
$scriptRoot = $PSScriptRoot

#region Import Scanner

$scannerScript = Join-Path $scriptRoot 'Invoke-TimeoutComplianceScan.ps1'
if (-not (Test-Path $scannerScript)) {
    throw "Required script not found: $scannerScript"
}

. $scannerScript

#endregion

#region Run Scan

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Inactivity Timeout Compliance Test              ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  FSI-AgentGov Inactivity Timeout Enforcement     ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$scanParams = @{
    ExcludeSandbox          = $ExcludeSandbox
    OutputFormat            = 'Object'
    TenantId                = $TenantId
    ClientId                = $ClientId
    BapApiBaseUrl           = $BapApiBaseUrl
    UseManagedIdentity      = $UseManagedIdentity
    ManagedIdentityClientId = $ManagedIdentityClientId
}

if ($ClientSecret) {
    $scanParams.ClientSecret = $ClientSecret
}

if ($PersistResults -and $DataverseUrl) {
    $scanParams.DataverseUrl = $DataverseUrl
}
elseif ($PersistResults -and -not $DataverseUrl) {
    Write-Warning "-PersistResults requires -DataverseUrl. Results will not be persisted."
}

try {
    $scanResults = Invoke-TimeoutComplianceScan @scanParams
}
catch {
    Write-Error "Compliance scan failed: $($_.Exception.Message)"
    throw
}

if (-not $scanResults) {
    $scanResults = @()
}

#endregion

#region Compute Summary

$totalEnvironments = $scanResults.Count
$compliantCount    = ($scanResults | Where-Object { $_.ComplianceStatus -eq 'Compliant' }).Count
$nonCompliantCount = ($scanResults | Where-Object { $_.ComplianceStatus -eq 'NonCompliant' }).Count
$unknownCount      = ($scanResults | Where-Object { $_.ComplianceStatus -eq 'Unknown' }).Count

# Determine overall status
$overallStatus = 'Passed'
if ($nonCompliantCount -gt 0) {
    $overallStatus = 'Failed'
}
elseif ($unknownCount -gt 0) {
    $overallStatus = 'Warning'
}
elseif ($totalEnvironments -eq 0) {
    $overallStatus = 'Warning'
}

# Per-zone breakdown
$zones = @('Zone1', 'Zone2', 'Zone3', 'Unknown')
$byZone = @{}
foreach ($z in $zones) {
    $zoneResults = $scanResults | Where-Object { $_.Zone -eq $z }
    $byZone[$z] = [PSCustomObject]@{
        Zone           = $z
        Total          = ($zoneResults | Measure-Object).Count
        Compliant      = ($zoneResults | Where-Object { $_.ComplianceStatus -eq 'Compliant' } | Measure-Object).Count
        NonCompliant   = ($zoneResults | Where-Object { $_.ComplianceStatus -eq 'NonCompliant' } | Measure-Object).Count
        Unknown        = ($zoneResults | Where-Object { $_.ComplianceStatus -eq 'Unknown' } | Measure-Object).Count
    }
}

$report = [PSCustomObject]@{
    OverallStatus      = $overallStatus
    TotalEnvironments  = $totalEnvironments
    CompliantCount     = $compliantCount
    NonCompliantCount  = $nonCompliantCount
    UnknownCount       = $unknownCount
    ByZone             = [PSCustomObject]$byZone
    Results            = $scanResults
    RunId              = if ($scanResults.Count -gt 0) { $scanResults[0].RunId } else { [guid]::NewGuid().ToString() }
    Timestamp          = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

#endregion

#region Display Report

$statusColor = switch ($overallStatus) {
    'Passed'  { 'Green' }
    'Warning' { 'Yellow' }
    'Failed'  { 'Red' }
    default   { 'White' }
}

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor $statusColor
Write-Host ("║  Overall Status: {0,-32}║" -f $overallStatus) -ForegroundColor $statusColor
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor $statusColor
Write-Host ("║  Total Environments:   {0,-26}║" -f $totalEnvironments) -ForegroundColor Cyan
Write-Host ("║  Compliant:            {0,-26}║" -f $compliantCount) -ForegroundColor Green
Write-Host ("║  Non-Compliant:        {0,-26}║" -f $nonCompliantCount) -ForegroundColor $(if ($nonCompliantCount -gt 0) { 'Red' } else { 'Green' })
Write-Host ("║  Unknown:              {0,-26}║" -f $unknownCount) -ForegroundColor $(if ($unknownCount -gt 0) { 'Yellow' } else { 'Green' })
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor $statusColor
Write-Host "║  By Zone:                                        ║" -ForegroundColor Cyan

foreach ($z in $zones) {
    $zs = $byZone[$z]
    if ($zs.Total -gt 0) {
        Write-Host ("║    {0,-8} C:{1} NC:{2} U:{3}{4}║" -f $z, $zs.Compliant, $zs.NonCompliant, $zs.Unknown, (' ' * (28 - "$z".Length - "C:$($zs.Compliant) NC:$($zs.NonCompliant) U:$($zs.Unknown)".Length))) -ForegroundColor Cyan
    }
}

Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor $statusColor
Write-Host ""

# Detail output
switch ($OutputFormat) {
    'JSON' {
        return ($report | ConvertTo-Json -Depth 10)
    }
    'Object' {
        return $report
    }
    default {
        $displayResults = $scanResults
        if (-not $IncludeCompliant) {
            $displayResults = $scanResults | Where-Object { $_.ComplianceStatus -ne 'Compliant' }
        }

        if ($displayResults -and ($displayResults | Measure-Object).Count -gt 0) {
            Write-Host "Environment Details:" -ForegroundColor Cyan
            $displayResults | Format-Table -Property EnvironmentName, Zone, TimeoutEnabled, TimeoutDurationMinutes, MaxAllowedMinutes, ComplianceStatus, Severity -AutoSize
        }
        else {
            if ($IncludeCompliant) {
                Write-Host "No environments found." -ForegroundColor Yellow
            }
            else {
                Write-Host "All environments are compliant. Use -IncludeCompliant to see all results." -ForegroundColor Green
            }
        }

        return $report
    }
}

#endregion
