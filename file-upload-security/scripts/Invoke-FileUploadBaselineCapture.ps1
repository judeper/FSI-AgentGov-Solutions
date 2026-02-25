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
    Azure AD tenant ID.

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
    [securestring]$ClientSecret,

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
║  File Upload Security — Baseline Capture                     ║
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
if (-not $DataverseUrl) {
    throw 'DataverseUrl is required. Provide via -DataverseUrl or environment variable.'
}

# ── Connect to Dataverse ──────────────────────────────────────────
Write-Host 'Step 1/3: Connecting to Dataverse...' -ForegroundColor Cyan

# Acquire access token for Dataverse
$accessToken = $null
if ($ClientId -and $CertificateThumbprint) {
    Import-Module MSAL.PS -ErrorAction Stop
    $cert = Get-Item "Cert:\LocalMachine\My\$CertificateThumbprint" -ErrorAction Stop
    $dataverseScope = "$($DataverseUrl.TrimEnd('/'))/.default"
    $tokenResult = Get-MsalToken -ClientId $ClientId -ClientCertificate $cert `
        -TenantId $TenantId -Scopes $dataverseScope -ErrorAction Stop
    $accessToken = $tokenResult.AccessToken
} elseif ($ClientId -and $ClientSecret) {
    Import-Module MSAL.PS -ErrorAction Stop
    $dataverseScope = "$($DataverseUrl.TrimEnd('/'))/.default"
    $tokenResult = Get-MsalToken -ClientId $ClientId -ClientSecret $ClientSecret `
        -TenantId $TenantId -Scopes $dataverseScope -ErrorAction Stop
    $accessToken = $tokenResult.AccessToken
}

Connect-FUSDataverse -DataverseUrl $DataverseUrl -AccessToken $accessToken

$fusConn = Get-FUSConnection
if (-not $fusConn.IsConnected) {
    throw 'Failed to connect to Dataverse. Verify credentials and URL.'
}

Write-Host "  Connected successfully.`n" -ForegroundColor Green

# ── Enumerate Agents ─────────────────────────────────────────────
Write-Host 'Step 2/3: Enumerating agents...' -ForegroundColor Cyan

$agents = Get-AgentBots -DataverseUrl $DataverseUrl -AccessToken $fusConn.AccessToken

# Derive environment info from DataverseUrl (all bots come from a single environment)
$envName = ([Uri]$DataverseUrl).Host.Split('.')[0]
$envId = $DataverseUrl

if ($EnvironmentFilter -ne '*' -and $envName -notlike $EnvironmentFilter) {
    Write-Host "  Environment '$envName' does not match filter '$EnvironmentFilter'. Skipping." -ForegroundColor Yellow
    return
}

if ($AgentFilter -ne '*') {
    $agents = $agents | Where-Object { $_.name -like $AgentFilter }
}

# Enrich with zone and file upload status
$enriched = foreach ($agent in $agents) {
    $zoneParams = @{
        EnvironmentId          = $envId
        EnvironmentDisplayName = $envName
    }
    if ($accessToken) { $zoneParams['AccessToken'] = $accessToken }
    if ($DataverseUrl) { $zoneParams['DataverseUrl'] = $DataverseUrl }
    $agentZone = Get-ZoneClassification @zoneParams
    $fileUploadEnabled = Get-BotFileUploadEnabled -Bot $agent
    $moderationLevel = Get-BotModerationLevel -Bot $agent

    [PSCustomObject]@{
        AgentId              = $agent.botid
        AgentName            = $agent.name
        EnvironmentId        = $envId
        EnvironmentName      = $envName
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
    $existing = Get-FileUploadBaseline -AgentId $agent.AgentId

    if ($existing -and -not $OverwriteExisting) {
        Write-Host "  SKIP: $($agent.AgentName) — baseline exists (captured $($existing[0].CapturedAt))" -ForegroundColor Yellow
        $skipped++
        $results += [PSCustomObject]@{
            AgentName   = $agent.AgentName
            Zone        = $agent.Zone
            Status      = 'Skipped'
            FileUpload  = $agent.FileUploadEnabled
            Moderation  = $agent.ContentModerationLevel
            CapturedOn  = if ($existing) { $existing[0].CapturedAt } else { $null }
        }
        continue
    }

    $baselineRecord = @{
        fsi_agent_id              = $agent.AgentId
        fsi_agent_name            = $agent.AgentName
        fsi_environment_id        = $agent.EnvironmentId
        fsi_environment_name      = $agent.EnvironmentName
        fsi_zone                  = switch ($agent.Zone) {
            'Zone 1' { 1 }
            'Zone 2' { 2 }
            'Zone 3' { 3 }
            default  { $null }
        }
        fsi_file_upload_enabled   = $agent.FileUploadEnabled
        fsi_content_moderation_level = $agent.ContentModerationLevel
        fsi_baseline_captured_on  = (Get-Date).ToUniversalTime().ToString('o')
        fsi_baseline_captured_by  = $env:USERNAME
    }

    if ($DryRun) {
        Write-Host "  DRY RUN: Would capture baseline for $($agent.AgentName) [Zone: $($agent.Zone), Upload: $($agent.FileUploadEnabled)]" -ForegroundColor DarkYellow
    }
    elseif ($PSCmdlet.ShouldProcess($agent.AgentName, 'Capture file upload baseline')) {
        Save-FUSBaseline `
            -EnvironmentGuid $agent.EnvironmentId `
            -EnvironmentName $agent.EnvironmentName `
            -Zone $agent.Zone `
            -AgentId $agent.AgentId `
            -AgentName $agent.AgentName `
            -FileUploadEnabled ([bool]$agent.FileUploadEnabled) `
            -ModerationLevel $agent.ContentModerationLevel `
            -CapturedBy $env:USERNAME
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
        $results | Format-Table -AutoSize | Out-Host
    }
    'JSON' {
        $results | ConvertTo-Json -Depth 5 | Out-Host
    }
    'CSV' {
        $results | ConvertTo-Csv -NoTypeInformation | Out-Host
    }
}

# Return results for pipeline use
$results
