#Requires -Version 7.4

<#
.SYNOPSIS
    Captures file upload security baselines for Copilot Studio agents.

.DESCRIPTION
    Connects to Dataverse and records the current file upload configuration
    (enabled/disabled) and content moderation level for each agent. These
    baselines are the approved-state reference used by Compare-FileUploadCompliance
    to detect drift.

    Supports filtering by zone, environment, or specific agents. Runs in
    dry-run mode by default to preview changes before committing.

.PARAMETER TenantId
    Microsoft Entra ID tenant ID.

.PARAMETER ClientId
    Service principal application (client) ID for non-interactive auth.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication.

.PARAMETER ClientSecret
    Client secret for service principal authentication.

.PARAMETER DataverseUrl
    Dataverse environment URL (e.g., https://org.crm.dynamics.com).

.PARAMETER Zone
    Filter baseline capture to specific zone(s): Zone1, Zone2, Zone3.

.PARAMETER EnvironmentFilter
    Filter to specific environment name pattern (supports wildcards).

.PARAMETER AgentFilter
    Filter to specific agent name pattern (supports wildcards).

.PARAMETER OverwriteExisting
    When set, overwrites existing baseline records for matched agents.
    Default behavior skips agents that already have baselines.

.PARAMETER DryRun
    Preview what would be captured without writing to Dataverse.

.PARAMETER OutputFormat
    Output format for results: Table, JSON, CSV. Default: Table.

.EXAMPLE
    .\Invoke-FileUploadBaselineCapture.ps1 -TenantId $tid -DataverseUrl $url -DryRun
    Preview baseline capture for all environments.

.EXAMPLE
    .\Invoke-FileUploadBaselineCapture.ps1 -TenantId $tid -DataverseUrl $url -Zone Zone3
    Capture baselines for Zone 3 (Enterprise) agents only.

.EXAMPLE
    .\Invoke-FileUploadBaselineCapture.ps1 -TenantId $tid -DataverseUrl $url -OverwriteExisting
    Refresh all baselines, overwriting previous records.

.NOTES
    Part of FSI Agent Governance Framework - File Upload Security Configurator
    Control: 1.14 - Data Minimization and Agent Scope Control
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter()]
    [string]$ClientId,

    [Parameter()]
    [string]$CertificateThumbprint,

    [Parameter()]
    # legacy: dev-only -- replace with managed identity in production
    [string]$ClientSecret,  # Prefer FUS_CLIENT_SECRET env var over CLI arg to avoid exposure in process tables

    [Parameter()]
    [string]$DataverseUrl,

    [Parameter()]
    [ValidateSet('Zone1', 'Zone2', 'Zone3')]
    [string[]]$Zone,

    [Parameter()]
    [string]$EnvironmentFilter = '*',

    [Parameter()]
    [string]$AgentFilter = '*',

    [Parameter()]
    [switch]$OverwriteExisting,

    [Parameter()]
    [switch]$DryRun,

    [Parameter()]
    [ValidateSet('Table', 'JSON', 'CSV')]
    [string]$OutputFormat = 'Table'
)

$ErrorActionPreference = 'Stop'

# ── Load Dependencies ─────────────────────────────────────────────
$privatePath = Join-Path $PSScriptRoot 'private'

. (Join-Path $privatePath 'Test-ParameterValidation.ps1')
. (Join-Path $privatePath 'Get-ZoneClassification.ps1')

Import-Module (Join-Path $privatePath 'FUSClient.psm1') -Force

# ── Banner ────────────────────────────────────────────────────────
$banner = @"

╔══════════════════════════════════════════════════════════════╗
║  File Upload Security -- Baseline Capture                     ║
╚══════════════════════════════════════════════════════════════╝
  Tenant:      $TenantId
  Dataverse:   $DataverseUrl
  Zone Filter: $(if ($Zone) { $Zone -join ', ' } else { 'All' })
  Env Filter:  $EnvironmentFilter
  Agent Filter:$AgentFilter
  Overwrite:   $OverwriteExisting
  Dry Run:     $DryRun

"@
Write-Host $banner

# ── Validate Parameters ──────────────────────────────────────────
try {

if (-not $DataverseUrl) {
    throw 'DataverseUrl is required. Provide via -DataverseUrl or environment variable.'
}

# Resolve client secret from environment variable to avoid process table exposure
if (-not $ClientSecret -and $env:FUS_CLIENT_SECRET) {
    $ClientSecret = $env:FUS_CLIENT_SECRET
} elseif ($ClientSecret) {
    Write-Warning "ClientSecret passed via command line is visible in process tables. Use FUS_CLIENT_SECRET environment variable instead."
}

# ── Connect to Dataverse ──────────────────────────────────────────
Write-Host 'Step 1/3: Connecting to Dataverse...' -ForegroundColor Cyan

$connParams = @{ DataverseUrl = $DataverseUrl }

# Acquire access token via Connect-EnvironmentDataverse if credentials are provided
if ($ClientId -and ($CertificateThumbprint -or $ClientSecret)) {
    $credParams = @{ DataverseUrl = $DataverseUrl; TenantId = $TenantId }
    if ($ClientSecret) {
        $cred = [PSCredential]::new($ClientId, (ConvertTo-SecureString $ClientSecret -AsPlainText -Force))
        $credParams.Credential = $cred
        $accessToken = & (Join-Path $privatePath 'Connect-EnvironmentDataverse.ps1') @credParams
    } elseif ($CertificateThumbprint) {
        # Certificate auth via MSAL.PS (Connect-EnvironmentDataverse.ps1 only supports client secret)
        Import-Module MSAL.PS -ErrorAction Stop
        $dataverseScope = "$($DataverseUrl.TrimEnd('/'))/.default"
        $cert = Get-Item "Cert:\CurrentUser\My\$CertificateThumbprint" -ErrorAction Stop
        $tokenResult = Get-MsalToken `
            -ClientId $ClientId `
            -ClientCertificate $cert `
            -TenantId $TenantId `
            -Scopes $dataverseScope `
            -ErrorAction Stop
        $accessToken = $tokenResult.AccessToken
    }
    $connParams.AccessToken = $accessToken
}

Connect-FUSDataverse @connParams

$connection = Get-FUSConnection

if (-not $connection -or -not $connection.IsConnected) {
    throw 'Failed to connect to Dataverse. Verify credentials and URL.'
}

Write-Host "  Connected successfully.`n" -ForegroundColor Green

# ── Enumerate Agents ─────────────────────────────────────────────
Write-Host 'Step 2/3: Enumerating agents...' -ForegroundColor Cyan

$agents = Get-AgentBots -DataverseUrl $connection.DataverseUrl -AccessToken $connection.AccessToken

# Derive environment info from connection URL (single-environment mode)
$envOrgName = ([Uri]$connection.DataverseUrl).Host.Split('.')[0]

if ($EnvironmentFilter -ne '*') {
    if ($envOrgName -notlike $EnvironmentFilter) {
        Write-Host "  Environment '$envOrgName' does not match filter '$EnvironmentFilter'. No agents to process." -ForegroundColor Yellow
        $agents = @()
    }
}

if ($AgentFilter -ne '*') {
    $agents = $agents | Where-Object { $_.name -like $AgentFilter }
}

# Enrich with zone and file upload status
$enriched = foreach ($agent in $agents) {
    $agentZone = Get-ZoneClassification -EnvironmentId $envOrgName -EnvironmentDisplayName $envOrgName
    $fileUploadEnabled = Get-BotFileUploadEnabled -Bot $agent
    $moderationLevel = Get-BotModerationLevel -Bot $agent

    [PSCustomObject]@{
        AgentId              = $agent.botid
        AgentName            = $agent.name
        EnvironmentId        = $envOrgName
        EnvironmentName      = $envOrgName
        Zone                 = $agentZone
        FileUploadEnabled    = $fileUploadEnabled
        ContentModerationLevel = $moderationLevel
    }
}

# Apply zone filter
if ($Zone) {
    $zoneMap = @{ 'Zone1' = 'Zone 1'; 'Zone2' = 'Zone 2'; 'Zone3' = 'Zone 3' }
    $zoneValues = $Zone | ForEach-Object { $zoneMap[$_] }
    $enriched = $enriched | Where-Object { $_.Zone -in $zoneValues }
}

Write-Host "  Found $($enriched.Count) agents matching filters.`n" -ForegroundColor Green

if ($enriched.Count -eq 0) {
    Write-Host 'No agents found matching the specified filters. Exiting.' -ForegroundColor Yellow
    return
}

# ── Capture Baselines ────────────────────────────────────────────
Write-Host 'Step 3/3: Capturing baselines...' -ForegroundColor Cyan

$captured = 0
$skipped = 0
$results = @()

foreach ($agent in $enriched) {
    # Check existing baseline
    $existing = Get-FileUploadBaseline -AgentId $agent.AgentId | Select-Object -First 1

    if ($existing -and -not $OverwriteExisting) {
        Write-Host "  SKIP: $($agent.AgentName) -- baseline exists (captured $($existing.CapturedAt))" -ForegroundColor Yellow
        $skipped++
        $results += [PSCustomObject]@{
            AgentName   = $agent.AgentName
            Zone        = $agent.Zone
            Status      = 'Skipped'
            FileUpload  = $agent.FileUploadEnabled
            Moderation  = $agent.ContentModerationLevel
            CapturedOn  = $existing.CapturedAt
        }
        continue
    }

    $baselineRecord = @{
        EnvironmentGuid         = $agent.EnvironmentId
        EnvironmentName         = $agent.EnvironmentName
        Zone                    = switch ($agent.Zone) {
            'Zone 1' { 'Zone 1' }
            'Zone 2' { 'Zone 2' }
            'Zone 3' { 'Zone 3' }
            default  { $agent.Zone }
        }
        AgentId                 = $agent.AgentId
        AgentName               = $agent.AgentName
        FileUploadEnabled       = [bool]$agent.FileUploadEnabled
        ModerationLevel         = $agent.ContentModerationLevel
        CapturedBy              = $env:USERNAME
    }

    if ($DryRun) {
        Write-Host "  DRY RUN: Would capture baseline for $($agent.AgentName) [Zone: $($agent.Zone), Upload: $($agent.FileUploadEnabled)]" -ForegroundColor DarkYellow
    }
    elseif ($PSCmdlet.ShouldProcess($agent.AgentName, 'Capture file upload baseline')) {
        Save-FUSBaseline @baselineRecord
        Write-Host "  CAPTURED: $($agent.AgentName) [Zone: $($agent.Zone), Upload: $($agent.FileUploadEnabled)]" -ForegroundColor Green
    }

    $captured++
    $results += [PSCustomObject]@{
        AgentName   = $agent.AgentName
        Zone        = $agent.Zone
        Status      = if ($DryRun) { 'Dry Run' } else { 'Captured' }
        FileUpload  = $agent.FileUploadEnabled
        Moderation  = $agent.ContentModerationLevel
        CapturedOn  = (Get-Date).ToString('yyyy-MM-dd HH:mm:ss')
    }
}

# ── Output Results ────────────────────────────────────────────────
Write-Host "`n" -NoNewline

$summaryBanner = @"

╔══════════════════════════════════════════════════════════════╗
║  Baseline Capture Summary                                    ║
╠══════════════════════════════════════════════════════════════╣
║  Total Agents:  $($enriched.Count.ToString().PadLeft(6))                                       ║
║  Captured:      $($captured.ToString().PadLeft(6))                                       ║
║  Skipped:       $($skipped.ToString().PadLeft(6))                                       ║
║  Mode:          $(if ($DryRun) { 'DRY RUN' } else { 'LIVE   ' })                                      ║
╚══════════════════════════════════════════════════════════════╝
"@
Write-Host $summaryBanner -ForegroundColor Cyan

switch ($OutputFormat) {
    'Table' {
        $results | Format-Table -AutoSize
    }
    'JSON' {
        $results | ConvertTo-Json -Depth 5
    }
    'CSV' {
        $results | ConvertTo-Csv -NoTypeInformation
    }
}

# Return results for pipeline use
$results

} catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  At: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    throw
}
