#Requires -Version 7.0

<#
.SYNOPSIS
    Applies recommended governance configuration to a Power Platform environment
    using pac admin set-governance-config.

.DESCRIPTION
    Configures Managed Environment governance settings for production environments.
    This script wraps pac admin set-governance-config with FSI-recommended defaults:
    - Solution checker enforcement mode (warn or block)
    - Disable unmanaged solution customizations
    - Enable deployment pipelines

    IMPORTANT: This script requires the Power Platform Admin role and PAC CLI
    authenticated to the target tenant.

    After applying configuration, the script verifies the settings using
    pac admin governance-config get (when available) and outputs the result.

.PARAMETER EnvironmentId
    Target Power Platform environment ID (GUID).

.PARAMETER SolutionCheckerMode
    Solution checker enforcement mode. 'warn' logs findings without blocking;
    'block' prevents import of solutions with critical findings.
    Default: warn

.PARAMETER DisableUnmanagedCustomizations
    If specified, disables unmanaged solution customizations in the environment.

.PARAMETER EnablePipelines
    If specified, enables deployment pipelines for the environment.

.PARAMETER DryRun
    If specified, prints the commands that would be executed without running them.

.EXAMPLE
    .\Set-GovernanceConfig.ps1 -EnvironmentId "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    .\Set-GovernanceConfig.ps1 -EnvironmentId "00000000-0000-0000-0000-000000000000" `
        -SolutionCheckerMode "block" -DisableUnmanagedCustomizations -EnablePipelines

.NOTES
    Prerequisites:
    - Power Platform CLI (pac) installed and authenticated
    - Power Platform Admin role

    Reference:
    - https://learn.microsoft.com/power-apps/maker/data-platform/use-powerapps-checker
    - https://learn.microsoft.com/power-platform/admin/managed-environment-overview
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$EnvironmentId,

    [Parameter(Mandatory = $false)]
    [ValidateSet("warn", "block")]
    [string]$SolutionCheckerMode = "warn",

    [Parameter(Mandatory = $false)]
    [switch]$DisableUnmanagedCustomizations,

    [Parameter(Mandatory = $false)]
    [switch]$EnablePipelines,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

# ── Validate PAC CLI ─────────────────────────────────────────────────────────

try {
    $null = Get-Command pac -ErrorAction Stop
}
catch {
    Write-Error "PAC CLI (pac) not found on PATH. Install from https://learn.microsoft.com/power-platform/developer/cli/introduction"
    return
}

# ── Build command arguments ──────────────────────────────────────────────────

$setArgs = @(
    "admin", "set-governance-config",
    "--environment", $EnvironmentId,
    "--solution-checker-mode", $SolutionCheckerMode
)

if ($DisableUnmanagedCustomizations) {
    $setArgs += "--disable-unmanaged-customizations"
}

if ($EnablePipelines) {
    $setArgs += "--enable-pipelines"
}

$cmdDisplay = "pac $($setArgs -join ' ')"

# ── Execute or preview ───────────────────────────────────────────────────────

if ($DryRun) {
    Write-Info "[DRY RUN] Would execute:"
    Write-Host "  $cmdDisplay"
    Write-Host ""
    Write-Info "[DRY RUN] Would then verify with:"
    Write-Host "  pac admin governance-config get --environment $EnvironmentId"
    return
}

Write-Info "Applying governance configuration..."
Write-Info "Command: $cmdDisplay"
Write-Host ""

$output = & pac @setArgs 2>&1
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Error "pac admin set-governance-config failed (exit $exitCode): $($output -join "`n")"
    return
}

Write-Host ($output -join "`n")
Write-Host ""

# ── Verify ───────────────────────────────────────────────────────────────────

Write-Info "Verifying applied configuration..."

$verifyArgs = @("admin", "governance-config", "get", "--environment", $EnvironmentId)
$verifyOutput = & pac @verifyArgs 2>&1
$verifyExit = $LASTEXITCODE

if ($verifyExit -ne 0) {
    Write-Host "[WARN] Verification command not available or failed (exit $verifyExit)." -ForegroundColor Yellow
    Write-Host "  Manually verify in Power Platform Admin Center:" -ForegroundColor Yellow
    Write-Host "  Environments > $EnvironmentId > Settings > Governance" -ForegroundColor Yellow
}
else {
    Write-Host ($verifyOutput -join "`n")
}

Write-Host ""
Write-Info "Governance configuration applied to environment $EnvironmentId"
Write-Info "  Solution checker mode: $SolutionCheckerMode"
if ($DisableUnmanagedCustomizations) { Write-Info "  Unmanaged customizations: disabled" }
if ($EnablePipelines) { Write-Info "  Deployment pipelines: enabled" }
