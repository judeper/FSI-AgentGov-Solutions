#Requires -Version 7.1

<#
.SYNOPSIS
    Captures live Power Platform environment access settings as baselines in Dataverse.

.DESCRIPTION
    Operator-initiated script that snapshots current agent access governance settings
    from Power Platform environments and writes them to Dataverse as AccessBaseline records.

    These baselines serve as the approved configuration that future drift detection
    (Start-AccessValidationRunbook) compares against. When validation results deviate
    from the baseline, alerting workflows trigger operator notifications.

    Key features:
    - Queries live Power Platform environment access settings via Get-EnvironmentAccessSettings
    - Captures bot-limitSharingMode, bot-authoringSharingDisabled, bot-publishedBotLimitSharingMode
    - Deactivates existing active baselines per environment (single active baseline per environment)
    - Writes new AccessBaseline records to Dataverse with fsi_is_active=true
    - Supports filtering by zone or specific environment GUID
    - Supports both interactive and certificate-based authentication
    - WhatIf mode for safe preview without writing to Dataverse

.PARAMETER TenantId
    Microsoft Entra ID tenant ID. Required.

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID. Required.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication.
    Required unless -Interactive is specified.

.PARAMETER DataverseUrl
    Dataverse environment URL where baselines are stored. Required.
    Example: https://governance.crm.dynamics.com

.PARAMETER Zone
    Filter capture to a specific governance zone (1, 2, or 3).
    If omitted, captures baselines for all zones.

.PARAMETER EnvironmentGuid
    Capture baseline for a single environment by its GUID.
    Mutually exclusive with -Zone.

.PARAMETER ExcludeSandbox
    Exclude Sandbox type environments from capture. Default: $true.

.PARAMETER CapturedBy
    Operator identifier stored with the baseline. Defaults to current user UPN.

.PARAMETER Interactive
    Use interactive browser-based authentication instead of certificate.
    Useful for manual baseline captures by operators.

.EXAMPLE
    .\Invoke-AccessBaselineCapture.ps1 `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -CertificateThumbprint "ABCDEF123456" `
        -DataverseUrl "https://governance.crm.dynamics.com"

    Captures baselines for all environments using certificate authentication.

.EXAMPLE
    .\Invoke-AccessBaselineCapture.ps1 `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -Interactive -Zone 3

    Captures baselines for Zone 3 environments only using interactive authentication.

.EXAMPLE
    .\Invoke-AccessBaselineCapture.ps1 `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -Interactive -EnvironmentGuid "a1b2c3d4-e5f6-7890-abcd-ef1234567890"

    Captures baseline for a single environment using interactive authentication.

.EXAMPLE
    .\Invoke-AccessBaselineCapture.ps1 `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -Interactive -WhatIf

    Preview mode - shows what would be captured without writing to Dataverse.

.OUTPUTS
    JSON object with properties:
    - CapturedOn: ISO 8601 UTC timestamp
    - TotalCaptured: Count of baselines written
    - ZoneBreakdown: Hashtable with per-zone counts
    - Environments: Array of captured environment summaries

.NOTES
    Version: 1.0.0

    Requires:
    - Microsoft.PowerApps.Administration.PowerShell module
    - MSAL.PS module v4.37.0 or later (for Dataverse token)
    - PowerShell 7.1 or later
    - Power Platform admin permissions

    Baseline management:
    - Only one active baseline per environment at any time
    - Previous active baselines are automatically deactivated (fsi_is_active=false)
    - Deactivated baselines remain in Dataverse for historical audit
    - Use WhatIf to preview before committing

    This script is typically invoked manually by operators after deploying or
    updating Power Platform environment access settings. It captures the "known good"
    state that automated validation will compare against.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [string]$ClientId,

    [Parameter()]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory)]
    [string]$DataverseUrl,

    [Parameter()]
    [ValidateSet(1, 2, 3)]
    [int]$Zone,

    [Parameter()]
    [string]$EnvironmentGuid,

    [bool]$ExcludeSandbox = $true,

    [Parameter()]
    [string]$CapturedBy,

    [switch]$Interactive
)

$ErrorActionPreference = "Stop"

try {
    Write-Verbose "Starting access baseline capture"
    Write-Verbose "DataverseUrl: $DataverseUrl"

    $scriptRoot = $PSScriptRoot

    #region Parameter Validation

    if (-not $Interactive -and -not $CertificateThumbprint) {
        throw "CertificateThumbprint is required when -Interactive is not specified."
    }

    if ($Zone -and $EnvironmentGuid) {
        throw "-Zone and -EnvironmentGuid are mutually exclusive. Specify one or neither."
    }

    # Default CapturedBy to current user UPN
    if (-not $CapturedBy) {
        try {
            $CapturedBy = [System.Environment]::UserName
        } catch {
            $CapturedBy = "Operator"
        }
    }

    Write-Verbose "CapturedBy: $CapturedBy"

    #endregion

    #region Authenticate and acquire Dataverse token

    Write-Verbose "Acquiring Dataverse token..."

    Import-Module MSAL.PS -ErrorAction Stop

    if ($Interactive) {
        $tokenResult = Get-MsalToken `
            -ClientId $ClientId `
            -TenantId $TenantId `
            -Scopes "$($DataverseUrl.TrimEnd('/'))/.default" `
            -Interactive `
            -ErrorAction Stop
    } else {
        $cert = Get-Item "Cert:\CurrentUser\My\$CertificateThumbprint" -ErrorAction Stop
        $tokenResult = Get-MsalToken `
            -ClientId $ClientId `
            -ClientCertificate $cert `
            -TenantId $TenantId `
            -Scopes "$($DataverseUrl.TrimEnd('/'))/.default" `
            -ErrorAction Stop
    }

    $dataverseToken = $tokenResult.AccessToken
    Write-Verbose "Dataverse token acquired"

    #endregion

    #region Connect AAMClient to Dataverse

    Import-Module "$scriptRoot\private\AAMClient.psm1" -Force
    Connect-AAMDataverse -DataverseUrl $DataverseUrl -AccessToken $dataverseToken
    Write-Verbose "AAMClient connected to Dataverse"

    #endregion

    #region Query current environment access settings

    Write-Verbose "Querying Power Platform environment access settings..."

    $getSettingsScript = Join-Path $scriptRoot 'Get-EnvironmentAccessSettings.ps1'
    if (-not (Test-Path $getSettingsScript)) {
        throw "Required script not found: $getSettingsScript"
    }

    $settingsParams = @{}

    if ($ExcludeSandbox) {
        $settingsParams['ExcludeSandbox'] = $true
    }

    if ($DataverseUrl) {
        $settingsParams['DataverseUrl'] = $DataverseUrl
        $settingsParams['AccessToken'] = $dataverseToken
    }

    $environmentSettings = & $getSettingsScript @settingsParams

    if (-not $environmentSettings -or $environmentSettings.Count -eq 0) {
        Write-Warning "No environments found. Nothing to capture."

        $emptyResult = [PSCustomObject]@{
            CapturedOn    = (Get-Date -Format 'o')
            TotalCaptured = 0
            ZoneBreakdown = @{ Zone1 = 0; Zone2 = 0; Zone3 = 0; Unknown = 0 }
            Environments  = @()
        }

        $emptyResult | ConvertTo-Json -Depth 5
        return
    }

    Write-Verbose "Found $($environmentSettings.Count) environment(s)"

    #endregion

    #region Filter by Zone or EnvironmentGuid

    if ($Zone) {
        $zoneLabel = "Zone$Zone"
        $environmentSettings = $environmentSettings | Where-Object { $_.Zone -eq $zoneLabel }
        Write-Verbose "Filtered to Zone $Zone : $($environmentSettings.Count) environment(s)"
    }

    if ($EnvironmentGuid) {
        $environmentSettings = $environmentSettings | Where-Object { $_.EnvironmentId -eq $EnvironmentGuid }
        Write-Verbose "Filtered to EnvironmentGuid $EnvironmentGuid : $($environmentSettings.Count) environment(s)"
    }

    if (-not $environmentSettings -or @($environmentSettings).Count -eq 0) {
        Write-Warning "No environments match the specified filter criteria."

        $emptyResult = [PSCustomObject]@{
            CapturedOn    = (Get-Date -Format 'o')
            TotalCaptured = 0
            ZoneBreakdown = @{ Zone1 = 0; Zone2 = 0; Zone3 = 0; Unknown = 0 }
            Environments  = @()
        }

        $emptyResult | ConvertTo-Json -Depth 5
        return
    }

    #endregion

    #region WhatIf preview

    if ($WhatIfPreference) {
        Write-Host "`n=================================================" -ForegroundColor Cyan
        Write-Host "  BASELINE CAPTURE PREVIEW (WhatIf Mode)" -ForegroundColor Cyan
        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "Total environments to capture: $(@($environmentSettings).Count)" -ForegroundColor Cyan
        Write-Host "Captured by: $CapturedBy" -ForegroundColor Cyan
        Write-Host ""

        foreach ($env in $environmentSettings) {
            Write-Host "  Environment: $($env.EnvironmentDisplayName)" -ForegroundColor Yellow
            Write-Host "    ID:   $($env.EnvironmentId)" -ForegroundColor Gray
            Write-Host "    Zone: $($env.Zone)" -ForegroundColor Gray
            Write-Host "    bot-limitSharingMode:           $($env.BotLimitSharingMode)" -ForegroundColor Gray
            Write-Host "    bot-authoringSharingDisabled:    $($env.BotAuthoringSharingDisabled)" -ForegroundColor Gray
            Write-Host "    bot-publishedBotLimitSharingMode: $($env.BotPublishedLimitSharingMode)" -ForegroundColor Gray
            Write-Host ""
        }

        Write-Host "=================================================" -ForegroundColor Cyan
        Write-Host "No changes written (WhatIf mode)" -ForegroundColor Yellow
        Write-Host ""
        return
    }

    #endregion

    #region Capture baselines per environment

    Write-Verbose "Capturing baselines for $(@($environmentSettings).Count) environment(s)..."

    $capturedEnvironments = @()
    $zoneBreakdown = @{ Zone1 = 0; Zone2 = 0; Zone3 = 0; Unknown = 0 }

    foreach ($env in $environmentSettings) {
        $envId = $env.EnvironmentId
        $envName = $env.EnvironmentDisplayName
        $envZone = $env.Zone

        # Parse zone number from label (e.g., "Zone3" -> 3)
        $zoneNumber = 0
        if ($envZone -match 'Zone(\d+)') {
            $zoneNumber = [int]$Matches[1]
        }

        Write-Verbose "Capturing baseline for: $envName ($envId) - Zone $zoneNumber"

        # Build raw JSON for audit trail
        $rawJson = @{
            BotLimitSharingMode           = $env.BotLimitSharingMode
            BotAuthoringSharingDisabled    = $env.BotAuthoringSharingDisabled
            BotPublishedLimitSharingMode   = $env.BotPublishedLimitSharingMode
            EnvironmentType               = $env.EnvironmentType
            EnvironmentGroupId            = $env.EnvironmentGroupId
            EnvironmentGroupName          = $env.EnvironmentGroupName
        } | ConvertTo-Json -Compress

        # Determine boolean value for authoring sharing disabled
        $authoringSharingDisabled = $false
        if ($env.BotAuthoringSharingDisabled -eq $true -or $env.BotAuthoringSharingDisabled -eq 'True') {
            $authoringSharingDisabled = $true
        }

        $botLimitValue = if ($env.BotLimitSharingMode) { $env.BotLimitSharingMode } else { '' }
        $botPublishedValue = if ($env.BotPublishedLimitSharingMode) { $env.BotPublishedLimitSharingMode } else { '' }

        $saveResult = Save-AAMBaseline `
            -EnvironmentGuid $envId `
            -EnvironmentName $envName `
            -Zone $zoneNumber `
            -BotLimitSharingMode $botLimitValue `
            -BotAuthoringSharingDisabled $authoringSharingDisabled `
            -BotPublishedBotLimitSharingMode $botPublishedValue `
            -CapturedBy $CapturedBy `
            -RawJson $rawJson

        if ($null -ne $saveResult) {
            Write-Verbose "Baseline saved for $envName"
        } else {
            Write-Warning "Baseline save returned null for $envName"
        }

        $capturedEnvironments += [PSCustomObject]@{
            EnvironmentId   = $envId
            EnvironmentName = $envName
            Zone            = $envZone
            ZoneNumber      = $zoneNumber
        }

        # Update zone breakdown
        $zoneKey = if ($zoneBreakdown.ContainsKey($envZone)) { $envZone } else { 'Unknown' }
        $zoneBreakdown[$zoneKey]++
    }

    Write-Verbose "Baseline capture complete. Total captured: $($capturedEnvironments.Count)"

    #endregion

    #region Build and emit output

    $result = [PSCustomObject]@{
        CapturedOn    = (Get-Date -Format 'o')
        CapturedBy    = $CapturedBy
        TotalCaptured = $capturedEnvironments.Count
        ZoneBreakdown = $zoneBreakdown
        Environments  = $capturedEnvironments
    }

    $result | ConvertTo-Json -Depth 5

    #endregion

} catch {
    Write-Error "Baseline capture failed: $($_.Exception.Message)"
    throw
}
