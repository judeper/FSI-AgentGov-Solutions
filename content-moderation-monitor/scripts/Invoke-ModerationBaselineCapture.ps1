#Requires -Version 5.1

<#
.SYNOPSIS
    Captures live Copilot Studio agent content moderation settings as baselines in Dataverse.

.DESCRIPTION
    Operator-initiated script that snapshots current agent content moderation levels
    from Power Platform environments and writes them to Dataverse as ModerationBaseline
    records.

    These baselines serve as the approved configuration that future drift detection
    (Start-ModerationValidationRunbook) compares against. When validation results deviate
    from the baseline, alerting workflows trigger operator notifications.

    Key features:
    - Queries live agent content moderation levels via Get-AgentModerationSettings
    - Captures ContentModerationLevel per agent (High, Medium, Low)
    - Deactivates existing active baselines per agent (single active baseline per agent)
    - Writes new ModerationBaseline records to Dataverse with fsi_is_active=true
    - Supports filtering by zone, environment GUID, or agent ID
    - Supports both interactive and certificate-based authentication
    - WhatIf mode for safe preview without writing to Dataverse

    Key difference from AAM (v6): CMM baselines operate at the agent level, not the
    environment level. Each agent has its own baseline record.

.PARAMETER TenantId
    Azure AD tenant ID. Required.

.PARAMETER ClientId
    Azure AD application (client) ID. Required.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication.
    Required unless -Interactive is specified.

.PARAMETER DataverseUrl
    Dataverse environment URL where baselines are stored. Required.
    Example: https://governance.crm.dynamics.com

.PARAMETER Zone
    Filter capture to a specific governance zone (1, 2, or 3).
    If omitted, captures baselines for all zones.
    Mutually exclusive with -EnvironmentGuid.

.PARAMETER EnvironmentGuid
    Capture baselines for agents in a single environment by its GUID.
    Mutually exclusive with -Zone.

.PARAMETER AgentId
    Capture baseline for a single agent by its ID.
    Can be combined with -EnvironmentGuid.

.PARAMETER ExcludeSandbox
    Exclude Sandbox type environments from capture. Default: $false.

.PARAMETER IncludeDrafts
    Include draft/unpublished agents. Default: $false.

.PARAMETER CapturedBy
    Operator identifier stored with the baseline. Defaults to current user UPN.

.PARAMETER Interactive
    Use interactive browser-based authentication instead of certificate.
    Useful for manual baseline captures by operators.

.EXAMPLE
    .\Invoke-ModerationBaselineCapture.ps1 `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -CertificateThumbprint "ABCDEF123456" `
        -DataverseUrl "https://governance.crm.dynamics.com"

    Captures baselines for all agents using certificate authentication.

.EXAMPLE
    .\Invoke-ModerationBaselineCapture.ps1 `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -Interactive -Zone 3

    Captures baselines for Zone 3 agents only using interactive authentication.

.EXAMPLE
    .\Invoke-ModerationBaselineCapture.ps1 `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -Interactive -AgentId "a1b2c3d4-e5f6-7890-abcd-ef1234567890"

    Captures baseline for a single agent using interactive authentication.

.EXAMPLE
    .\Invoke-ModerationBaselineCapture.ps1 `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -Interactive -WhatIf

    Preview mode — shows what would be captured without writing to Dataverse.

.OUTPUTS
    JSON object with properties:
    - CapturedOn: ISO 8601 UTC timestamp
    - CapturedBy: Operator identity
    - TotalCaptured: Count of baselines written
    - ZoneBreakdown: Hashtable with per-zone counts
    - Agents: Array of captured agent summaries

.NOTES
    Version: 1.0.0

    Requires:
    - Microsoft.PowerApps.Administration.PowerShell module
    - MSAL.PS module v4.37.0 or later (for Dataverse token)
    - PowerShell 5.1 or later
    - Power Platform admin permissions

    Baseline management:
    - Only one active baseline per agent at any time
    - Previous active baselines are automatically deactivated (fsi_is_active=false)
    - Deactivated baselines remain in Dataverse for historical audit
    - Use WhatIf to preview before committing

    This script is typically invoked manually by operators after reviewing or
    approving agent content moderation settings. It captures the "known good"
    state that automated validation compares against.
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

    [Parameter()]
    [string]$AgentId,

    [switch]$ExcludeSandbox,

    [switch]$IncludeDrafts,

    [Parameter()]
    [string]$CapturedBy,

    [switch]$Interactive
)

$ErrorActionPreference = "Stop"

try {
    Write-Verbose "Starting moderation baseline capture"
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
            $CapturedBy = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
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

    #region Connect CMMClient to Dataverse

    Import-Module "$scriptRoot\private\CMMClient.psm1" -Force
    Connect-CMMDataverse -DataverseUrl $DataverseUrl -AccessToken $dataverseToken
    Write-Verbose "CMMClient connected to Dataverse"

    #endregion

    #region Query current agent moderation settings

    Write-Verbose "Querying agent content moderation settings..."

    $getSettingsScript = Join-Path $scriptRoot 'Get-AgentModerationSettings.ps1'
    if (-not (Test-Path $getSettingsScript)) {
        throw "Required script not found: $getSettingsScript"
    }

    # Dot-source to load the function
    . $getSettingsScript

    $queryParams = @{}

    if ($ExcludeSandbox) {
        $queryParams['ExcludeSandbox'] = $true
    }
    if ($IncludeDrafts) {
        $queryParams['IncludeDrafts'] = $true
    }
    if ($DataverseUrl) {
        $queryParams['DataverseUrl'] = $DataverseUrl
    }

    $agentSettings = Get-AgentModerationSettings @queryParams

    if (-not $agentSettings -or @($agentSettings).Count -eq 0) {
        Write-Warning "No agents found. Nothing to capture."

        $emptyResult = [PSCustomObject]@{
            CapturedOn    = (Get-Date -Format 'o')
            CapturedBy    = $CapturedBy
            TotalCaptured = 0
            ZoneBreakdown = @{ Zone1 = 0; Zone2 = 0; Zone3 = 0 }
            Agents        = @()
        }

        $emptyResult | ConvertTo-Json -Depth 5
        return
    }

    Write-Verbose "Found $(@($agentSettings).Count) agent(s)"

    #endregion

    #region Apply filters

    if ($Zone) {
        $zoneLabel = "Zone$Zone"
        $agentSettings = @($agentSettings | Where-Object { $_.Zone -eq $zoneLabel })
        Write-Verbose "Filtered to Zone $Zone : $($agentSettings.Count) agent(s)"
    }

    if ($EnvironmentGuid) {
        $agentSettings = @($agentSettings | Where-Object { $_.EnvironmentId -eq $EnvironmentGuid })
        Write-Verbose "Filtered to EnvironmentGuid $EnvironmentGuid : $($agentSettings.Count) agent(s)"
    }

    if ($AgentId) {
        $agentSettings = @($agentSettings | Where-Object { $_.AgentId -eq $AgentId })
        Write-Verbose "Filtered to AgentId $AgentId : $($agentSettings.Count) agent(s)"
    }

    if ($agentSettings.Count -eq 0) {
        Write-Warning "No agents match the specified filter criteria."

        $emptyResult = [PSCustomObject]@{
            CapturedOn    = (Get-Date -Format 'o')
            CapturedBy    = $CapturedBy
            TotalCaptured = 0
            ZoneBreakdown = @{ Zone1 = 0; Zone2 = 0; Zone3 = 0 }
            Agents        = @()
        }

        $emptyResult | ConvertTo-Json -Depth 5
        return
    }

    #endregion

    #region WhatIf preview

    if ($WhatIfPreference) {
        Write-Verbose "WhatIf mode - previewing baseline capture"
        Write-Verbose "Total agents to capture: $($agentSettings.Count)"
        Write-Verbose "Captured by: $CapturedBy"

        foreach ($agent in $agentSettings) {
            Write-Verbose "  Agent: $($agent.AgentName)"
            Write-Verbose "    ID:           $($agent.AgentId)"
            Write-Verbose "    Environment:  $($agent.EnvironmentDisplayName)"
            Write-Verbose "    Zone:         $($agent.Zone)"
            Write-Verbose "    Moderation:   $($agent.ContentModerationLevel)"
        }

        Write-Verbose "No changes written (WhatIf mode)"
    }

    #endregion

    #region Capture baselines per agent

    Write-Verbose "Capturing baselines for $($agentSettings.Count) agent(s)..."

    $capturedAgents = @()
    $zoneBreakdown = @{ Zone1 = 0; Zone2 = 0; Zone3 = 0 }

    foreach ($agent in $agentSettings) {
        $envId = $agent.EnvironmentId
        $envName = $agent.EnvironmentDisplayName
        $agentZone = $agent.Zone

        Write-Verbose "Capturing baseline for: $($agent.AgentName) in $envName ($agentZone)"

        # Build raw JSON for audit trail
        $rawJson = @{
            AgentId                = $agent.AgentId
            AgentName              = $agent.AgentName
            ContentModerationLevel = $agent.ContentModerationLevel
            AgentStatus            = $agent.AgentStatus
            EnvironmentId          = $envId
            EnvironmentDisplayName = $envName
            EnvironmentType        = $agent.EnvironmentType
            Zone                   = $agentZone
            LastPublished          = $agent.LastPublished
            RetrievedAt            = $agent.RetrievedAt
        } | ConvertTo-Json -Compress

        $saveResult = Save-CMMBaseline `
            -EnvironmentGuid $envId `
            -EnvironmentName $envName `
            -Zone $agentZone `
            -AgentId $agent.AgentId `
            -AgentName $agent.AgentName `
            -ModerationLevel $agent.ContentModerationLevel `
            -CapturedBy $CapturedBy `
            -RawJson $rawJson

        if ($null -ne $saveResult) {
            Write-Verbose "Baseline captured for $($agent.AgentName) in $envName ($agentZone)"
        } else {
            Write-Warning "Baseline save returned null for $($agent.AgentName)"
        }

        $capturedAgents += [PSCustomObject]@{
            AgentId          = $agent.AgentId
            AgentName        = $agent.AgentName
            EnvironmentName  = $envName
            Zone             = $agentZone
            ModerationLevel  = $agent.ContentModerationLevel
        }

        # Update zone breakdown
        $zoneKey = if ($zoneBreakdown.ContainsKey($agentZone)) { $agentZone } else { 'Zone1' }
        $zoneBreakdown[$zoneKey]++
    }

    Write-Verbose "Baseline capture complete. Total captured: $($capturedAgents.Count)"

    #endregion

    #region Build and emit output

    $result = [PSCustomObject]@{
        CapturedOn    = (Get-Date -Format 'o')
        CapturedBy    = $CapturedBy
        TotalCaptured = $capturedAgents.Count
        ZoneBreakdown = $zoneBreakdown
        Agents        = $capturedAgents
    }

    $result | ConvertTo-Json -Depth 5

    #endregion

} catch {
    Write-Error "Baseline capture failed: $($_.Exception.Message)"
    throw
}
