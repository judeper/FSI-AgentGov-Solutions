#Requires -Version 7.0

<#
.SYNOPSIS
    Thin wrapper around deploy.ps1 that reads lab/config.local.json for tenant-specific values.

.DESCRIPTION
    Loads agent-intake/lab/config.local.json (gitignored, per-developer) and invokes
    ../scripts/deploy.ps1 with values from the config file. Switches PAC CLI to the
    target environment first if a pac profile name is configured.

.PARAMETER Teardown
    Passed through to deploy.ps1.

.PARAMETER SeedTestData
    Override the seedTestData value in config.local.json.

.PARAMETER NoSeedTestData
    Force seedTestData off, overriding config.local.json.

.PARAMETER SkipSmoke
    Override skipSmoke.

.PARAMETER DryRun
    Passed through to deploy.ps1.

.PARAMETER ConfigPath
    Path to config.local.json. Defaults to lab/config.local.json relative to this script.

.EXAMPLE
    ./Invoke-Deploy.ps1

.EXAMPLE
    ./Invoke-Deploy.ps1 -Teardown

.EXAMPLE
    ./Invoke-Deploy.ps1 -DryRun -NoSeedTestData
#>
[CmdletBinding()]
param(
    [switch]$Teardown,
    [switch]$SeedTestData,
    [switch]$NoSeedTestData,
    [switch]$SkipSmoke,
    [switch]$DryRun,
    [string]$ConfigPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

if (-not $ConfigPath) {
    $ConfigPath = Join-Path -Path $PSScriptRoot -ChildPath 'config.local.json'
}

if (-not (Test-Path -Path $ConfigPath)) {
    $examplePath = Join-Path -Path $PSScriptRoot -ChildPath 'config.example.json'
    Write-Error @"
config.local.json not found at: $ConfigPath

To create one:
    Copy-Item '$examplePath' '$ConfigPath'
    # Then edit config.local.json with your lab tenant values.

See lab/README.md for details.
"@
    exit 1
}

Write-Information "Loading lab config from: $ConfigPath"
$config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json

$envUrl = $config.environment.url
if ([string]::IsNullOrWhiteSpace($envUrl)) {
    Write-Error "environment.url is empty in $ConfigPath"
    exit 1
}

# Tenant cross-check (P2): warn if the active az session is signed into a different
# tenant than the one the lab config targets. Non-fatal — the wrapper continues so a
# dry-run still works without az login.
$configTenantId = $null
if ($config.environment.PSObject.Properties.Name -contains 'tenantId') {
    $configTenantId = [string]$config.environment.tenantId
}
if (-not [string]::IsNullOrWhiteSpace($configTenantId) -and $configTenantId -notmatch '^0{8}-0{4}-0{4}-0{4}-0{12}$') {
    $azCmd = Get-Command -Name 'az' -ErrorAction SilentlyContinue
    if ($null -ne $azCmd) {
        $azTenantId = & $azCmd.Source account show --query tenantId -o tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($azTenantId)) {
            $azTenantId = $azTenantId.Trim()
            if ($azTenantId -ne $configTenantId) {
                Write-Warning ("Tenant mismatch: az session tenant '$azTenantId' differs from config.environment.tenantId '$configTenantId'. " +
                    "Run 'az login --tenant $configTenantId' before a live deploy, or this run will operate against the wrong tenant.")
            }
        }
    }
}

if ($config.pac -and -not [string]::IsNullOrWhiteSpace($config.pac.profileName)) {
    $pacProfile = $config.pac.profileName
    Write-Information "Selecting pac auth profile: $pacProfile"
    pac auth select --name $pacProfile | Out-Null
}

if ($config.environment.environmentId) {
    Write-Information "Pointing pac to environment $($config.environment.environmentId) ($($config.environment.name))"
    pac org select --environment $config.environment.environmentId | Out-Null
}

if ($config.purview -and -not [string]::IsNullOrWhiteSpace($config.purview.operatorUpn) -and $config.purview.operatorUpn -notlike '*<tenant>*') {
    $env:AGENT_INTAKE_PURVIEW_ADMIN_UPN = [string]$config.purview.operatorUpn
    Write-Information "Set AGENT_INTAKE_PURVIEW_ADMIN_UPN from config: $($env:AGENT_INTAKE_PURVIEW_ADMIN_UPN)"
}

$deployScript = Join-Path -Path (Split-Path -Parent $PSScriptRoot) -ChildPath 'scripts\deploy.ps1'
if (-not (Test-Path -Path $deployScript)) {
    Write-Error "deploy.ps1 not found at: $deployScript"
    exit 1
}

$deployArgs = @{
    EnvironmentUrl = $envUrl
}

if ($config.auth -and $config.auth.mode) {
    $deployArgs.AuthMode = $config.auth.mode
}

if ($config.environment.environmentId) {
    $deployArgs.EnvironmentId = $config.environment.environmentId
}

if ($config.billing -and -not [string]::IsNullOrWhiteSpace($config.billing.policyId)) {
    $deployArgs.BillingPolicyId = $config.billing.policyId
}

if ($config.billing -and -not [string]::IsNullOrWhiteSpace($config.billing.allowedEnvironmentType)) {
    $deployArgs.AllowedEnvironmentType = $config.billing.allowedEnvironmentType
}

$shouldSeed = if ($PSBoundParameters.ContainsKey('SeedTestData')) {
    [bool]$SeedTestData
} elseif ($PSBoundParameters.ContainsKey('NoSeedTestData')) {
    -not [bool]$NoSeedTestData
} elseif ($config.deploy -and $config.deploy.PSObject.Properties.Name -contains 'seedTestData') {
    [bool]$config.deploy.seedTestData
} else {
    $false
}
if ($shouldSeed) { $deployArgs.SeedTestData = $true }

$shouldSkipSmoke = if ($PSBoundParameters.ContainsKey('SkipSmoke')) {
    [bool]$SkipSmoke
} elseif ($config.deploy -and $config.deploy.PSObject.Properties.Name -contains 'skipSmoke') {
    [bool]$config.deploy.skipSmoke
} else {
    $false
}
if ($shouldSkipSmoke) { $deployArgs.SkipSmoke = $true }

if ($Teardown) { $deployArgs.Teardown = $true }
if ($DryRun)   { $deployArgs.DryRun   = $true }

$runtimeRoot = Join-Path -Path $PSScriptRoot -ChildPath '.deploy-runtime'
if (-not (Test-Path -Path $runtimeRoot)) {
    New-Item -ItemType Directory -Path $runtimeRoot -Force | Out-Null
}
$stamp = (Get-Date -AsUTC).ToString('yyyyMMddTHHmmssZ')
$deployArgs.LogPath = Join-Path -Path $runtimeRoot -ChildPath "agent-intake-deploy-$stamp.log"

Write-Information ''
Write-Information '=== Invoking deploy.ps1 with parameters ==='
$deployArgs.GetEnumerator() | Sort-Object Key | ForEach-Object {
    Write-Information ("  -{0,-16} {1}" -f $_.Key, $_.Value)
}
Write-Information ''

& $deployScript @deployArgs
exit $LASTEXITCODE
