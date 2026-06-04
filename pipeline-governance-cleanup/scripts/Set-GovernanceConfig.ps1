#Requires -Version 7.0

<#
.SYNOPSIS
    Applies recommended governance configuration to a Power Platform environment
    using pac admin set-governance-config.

.DESCRIPTION
    Configures Managed Environment governance settings for production environments.
    This script wraps `pac admin set-governance-config` with FSI-recommended defaults:
    - Managed Environment protection level (Standard enables Managed Environments)
    - Solution checker enforcement mode (none, warn, or block)

    IMPORTANT: This script requires the Power Platform Admin role and PAC CLI
    authenticated to the target tenant.

    Scope note: `pac admin set-governance-config` does not expose flags to disable
    unmanaged customizations or to enable deployment pipelines. Deployment pipelines
    are enabled by installing the Power Platform Pipelines app and configuring a host
    environment (see ../README.md Prerequisites and docs/portal-walkthrough.md). This
    script intentionally configures only the supported managed-environment and
    solution-checker settings.

    The `pac` CLI does not currently expose a governance-config read command, so the
    script directs the operator to verify the applied settings in the Power Platform
    Admin Center.

.PARAMETER EnvironmentId
    Target Power Platform environment ID (GUID).

.PARAMETER ProtectionLevel
    Managed Environment protection level. 'Standard' enables Managed Environments;
    'Basic' disables them. This maps to the required `--protection-level` parameter
    of `pac admin set-governance-config`. Default: Standard

.PARAMETER SolutionCheckerMode
    Solution checker enforcement mode. 'none' disables the checker; 'warn' logs
    findings without blocking; 'block' prevents import of solutions with critical
    findings. Default: warn

.PARAMETER DryRun
    If specified, prints the commands that would be executed without running them.

.EXAMPLE
    .\Set-GovernanceConfig.ps1 -EnvironmentId "00000000-0000-0000-0000-000000000000"

.EXAMPLE
    .\Set-GovernanceConfig.ps1 -EnvironmentId "00000000-0000-0000-0000-000000000000" `
        -ProtectionLevel "Standard" -SolutionCheckerMode "block"

.NOTES
    Prerequisites:
    - Power Platform CLI (pac) installed and authenticated
    - Power Platform Admin role

    Reference:
    - https://learn.microsoft.com/power-platform/developer/cli/reference/admin#pac-admin-set-governance-config
    - https://learn.microsoft.com/power-apps/maker/data-platform/use-powerapps-checker
    - https://learn.microsoft.com/power-platform/admin/managed-environment-overview
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$EnvironmentId,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Standard", "Basic")]
    [string]$ProtectionLevel = "Standard",

    [Parameter(Mandatory = $false)]
    [ValidateSet("none", "warn", "block")]
    [string]$SolutionCheckerMode = "warn",

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
    "--protection-level", $ProtectionLevel,
    "--solution-checker-mode", $SolutionCheckerMode
)

$cmdDisplay = "pac $($setArgs -join ' ')"

# ── Execute or preview ───────────────────────────────────────────────────────

if ($DryRun) {
    Write-Info "[DRY RUN] Would execute:"
    Write-Host "  $cmdDisplay"
    Write-Host ""
    Write-Info "[DRY RUN] Then verify in the Power Platform Admin Center:"
    Write-Host "  Environments > $EnvironmentId > Settings > Governance"
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
# The pac CLI does not currently expose a governance-config read command, so
# verification is a manual step in the Power Platform Admin Center.

Write-Host ""
Write-Info "Verify the applied configuration in the Power Platform Admin Center:"
Write-Host "  Environments > $EnvironmentId > Settings > Governance" -ForegroundColor Yellow

Write-Host ""
Write-Info "Governance configuration applied to environment $EnvironmentId"
Write-Info "  Protection level: $ProtectionLevel"
Write-Info "  Solution checker mode: $SolutionCheckerMode"
