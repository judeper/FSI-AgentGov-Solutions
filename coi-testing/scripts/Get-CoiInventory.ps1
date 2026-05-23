#Requires -Version 7.0

<#
.SYNOPSIS
    Enumerates Center of Influence (CoI) testing artifacts using Power Platform CLI.

.DESCRIPTION
    Uses PAC CLI to inventory solutions, environments, and connections used during
    CoI test cycles. Outputs structured JSON to coi-testing/output/ for downstream
    analysis and audit evidence.

    This script is a cross-check inventory tool — it does NOT execute tests.
    Use run_coi_tests.py for test execution.

    PAC CLI commands used:
      - pac solution list           (solutions in the connected environment)
      - pac admin list               (tenant environments)
      - pac connection list          (connections in the connected environment)

.PARAMETER OutputPath
    Directory for JSON output files. Defaults to ../output relative to the script.

.PARAMETER EnvironmentFilter
    Optional display-name substring to filter environments. When provided, only
    environments whose display name contains this value are included.

.PARAMETER IncludeConnections
    If specified, also enumerates connections via pac connection list.

.PARAMETER DryRun
    If specified, prints the PAC CLI commands that would be executed without
    running them.

.EXAMPLE
    .\Get-CoiInventory.ps1

.EXAMPLE
    .\Get-CoiInventory.ps1 -EnvironmentFilter "CoI" -IncludeConnections

.EXAMPLE
    .\Get-CoiInventory.ps1 -OutputPath "C:\reports\coi" -DryRun

.NOTES
    Prerequisites:
    - Power Platform CLI (pac) installed and authenticated
    - Power Platform Admin role for pac admin list
    - Run 'pac auth list' to verify current authentication context
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [string]$EnvironmentFilter,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeConnections,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helpers ──────────────────────────────────────────────────────────────────

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Cyan
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Test-PacInstalled {
    <#
    .SYNOPSIS
        Verify PAC CLI is available on PATH.
    #>
    try {
        $null = Get-Command pac -ErrorAction Stop
        return $true
    }
    catch {
        return $false
    }
}

function Invoke-PacCommand {
    <#
    .SYNOPSIS
        Execute a PAC CLI command and return parsed JSON output.

    .DESCRIPTION
        Accepts the PAC CLI argument list as a string array so individual
        arguments (e.g., a filter value containing spaces) are passed through
        to pac.exe verbatim. Earlier revisions accepted a single string and
        split on space, which silently broke any argument that legitimately
        contained whitespace.
    #>
    param(
        [Parameter(Mandatory)]
        [string[]]$Command,

        [Parameter(Mandatory)]
        [string]$Description,

        [switch]$DryRun
    )

    $commandDisplay = ($Command -join ' ')
    Write-Info "Running: pac $commandDisplay"

    if ($DryRun) {
        Write-Info "[DRY RUN] Would execute: pac $commandDisplay"
        return @()
    }

    try {
        $raw = & pac @Command 2>&1
        $exitCode = $LASTEXITCODE

        if ($exitCode -ne 0) {
            Write-Warn "$Description failed (exit code $exitCode): $($raw -join "`n")"
            return @()
        }

        # pac --json commands return JSON arrays; non-json returns text
        $text = $raw -join "`n"
        if ($text.Trim().StartsWith('[') -or $text.Trim().StartsWith('{')) {
            return ($text | ConvertFrom-Json)
        }

        # Return raw text lines for non-JSON output
        return @($raw | Where-Object { $_ -and $_.Trim() })
    }
    catch {
        Write-Warn "$Description error: $_"
        return @()
    }
}

# ── Main ─────────────────────────────────────────────────────────────────────

function Main {
    # Validate PAC CLI
    if (-not (Test-PacInstalled)) {
        Write-Error "PAC CLI (pac) not found on PATH. Install from https://learn.microsoft.com/power-platform/developer/cli/introduction"
        return
    }

    # Resolve output path
    if (-not $OutputPath) {
        $OutputPath = Join-Path $PSScriptRoot '..' 'output'
    }
    $OutputPath = [System.IO.Path]::GetFullPath($OutputPath)

    if (-not $DryRun) {
        if (-not (Test-Path $OutputPath)) {
            New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
            Write-Info "Created output directory: $OutputPath"
        }
    }

    $timestamp = Get-Date -Format 'yyyy-MM-ddTHH-mm-ss'
    $inventory = @{
        metadata = @{
            generatedAt   = (Get-Date -Format 'o')
            generatedBy   = 'Get-CoiInventory.ps1'
            filter        = if ($EnvironmentFilter) { $EnvironmentFilter } else { $null }
            isDryRun      = [bool]$DryRun
        }
        environments = @()
        solutions    = @()
        connections  = @()
    }

    # ── Environments ─────────────────────────────────────────────────────
    Write-Info 'Enumerating environments...'
    $envs = Invoke-PacCommand -Command @('admin','list','--json') -Description 'Environment list' -DryRun:$DryRun

    if ($EnvironmentFilter -and $envs.Count -gt 0) {
        $envs = @($envs | Where-Object {
            ($_.DisplayName -and $_.DisplayName -like "*$EnvironmentFilter*") -or
            ($_.EnvironmentName -and $_.EnvironmentName -like "*$EnvironmentFilter*")
        })
        Write-Info "Filtered to $($envs.Count) environment(s) matching '$EnvironmentFilter'"
    }

    $inventory.environments = @($envs)
    Write-Info "Found $($envs.Count) environment(s)"

    # ── Solutions ────────────────────────────────────────────────────────
    Write-Info 'Enumerating solutions in connected environment...'
    $solutions = Invoke-PacCommand -Command @('solution','list','--json') -Description 'Solution list' -DryRun:$DryRun
    $inventory.solutions = @($solutions)
    Write-Info "Found $($solutions.Count) solution(s)"

    # ── Connections (optional) ───────────────────────────────────────────
    if ($IncludeConnections) {
        Write-Info 'Enumerating connections...'
        $connections = Invoke-PacCommand -Command @('connection','list','--json') -Description 'Connection list' -DryRun:$DryRun
        $inventory.connections = @($connections)
        Write-Info "Found $($connections.Count) connection(s)"
    }

    # ── Output ───────────────────────────────────────────────────────────
    if ($DryRun) {
        Write-Info '[DRY RUN] Would write inventory JSON to output directory'
        $inventory | ConvertTo-Json -Depth 10 | Write-Output
        return
    }

    $outFile = Join-Path $OutputPath "coi-inventory-$timestamp.json"
    $inventory | ConvertTo-Json -Depth 10 | Set-Content -Path $outFile -Encoding utf8
    Write-Info "Inventory written to: $outFile"

    # Summary
    Write-Host ''
    Write-Host '── CoI Inventory Summary ──' -ForegroundColor Green
    Write-Host "  Environments : $($inventory.environments.Count)"
    Write-Host "  Solutions    : $($inventory.solutions.Count)"
    if ($IncludeConnections) {
        Write-Host "  Connections  : $($inventory.connections.Count)"
    }
    Write-Host "  Output       : $outFile"
}

Main
