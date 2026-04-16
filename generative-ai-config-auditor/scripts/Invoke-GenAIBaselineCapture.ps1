#Requires -Version 7.0

<#
.SYNOPSIS
    Captures live Copilot Studio agent generative AI configuration as baselines
    in Dataverse.

.DESCRIPTION
    Operator-initiated script that snapshots current agent generative AI settings
    from Power Platform environments and writes them to Dataverse as GACBaseline
    records.

    These baselines serve as the approved configuration that future drift detection
    (Start-GenAIConfigValidationRunbook) compares against. When validation results
    deviate from the baseline, alerting workflows trigger operator notifications.

    Key features:
    - Queries live agent GenAI settings via Get-AgentGenAISettings
    - Captures AzureOpenAIEnabled, OrchestrationMode, GenerativeAnswersNodeCount
      per agent
    - Deactivates existing active baselines per agent (single active baseline
      per agent)
    - Writes new GACBaseline records to Dataverse with fsi_isactive=true
    - Supports filtering by zone, environment GUID, or agent ID
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

.PARAMETER GracePeriodHours
    Exclude environments created within this many hours.
    Valid range: 0-168 (default: 48).

.PARAMETER CapturedBy
    Operator identifier stored with the baseline. Defaults to current user UPN.

.PARAMETER Interactive
    Use interactive browser-based authentication instead of certificate.
    Useful for manual baseline captures by operators.

.EXAMPLE
    .\Invoke-GenAIBaselineCapture.ps1 `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -CertificateThumbprint "ABCDEF123456" `
        -DataverseUrl "https://governance.crm.dynamics.com"

    Captures baselines for all agents using certificate authentication.

.EXAMPLE
    .\Invoke-GenAIBaselineCapture.ps1 `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -Interactive -Zone 3

    Captures baselines for Zone 3 agents only using interactive authentication.

.EXAMPLE
    .\Invoke-GenAIBaselineCapture.ps1 `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345-app-id" `
        -DataverseUrl "https://governance.crm.dynamics.com" `
        -Interactive -WhatIf

    Preview mode -- shows what would be captured without writing to Dataverse.

.OUTPUTS
    JSON object with properties:
    - CapturedOn: ISO 8601 UTC timestamp
    - CapturedBy: Operator identity
    - TotalCaptured: Count of baselines written
    - ZoneBreakdown: Hashtable with per-zone counts
    - Agents: Array of captured agent summaries

.NOTES
    Version: 1.0.0
    Solution: Generative AI Config Auditor (GAC)
    Control: 2.24 (Agent Feature Enablement Governance)

    Requires:
    - Microsoft.PowerApps.Administration.PowerShell module
    - MSAL.PS module v4.37.0 or later (for Dataverse token)
    - PowerShell 7.0 or later
    - Power Platform admin permissions

    Baseline management:
    - Only one active baseline per agent at any time
    - Previous active baselines are automatically deactivated (fsi_isactive=false)
    - Deactivated baselines remain in Dataverse for historical audit
    - Use WhatIf to preview before committing

    This script is typically invoked manually by operators after reviewing or
    approving agent generative AI settings. It captures the "known good" state
    that automated validation compares against.
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
    [ValidateRange(0, 168)]
    [int]$GracePeriodHours = 48,

    [Parameter()]
    [string]$CapturedBy,

    [switch]$Interactive
)

$ErrorActionPreference = "Stop"

try {
    Write-Verbose "Starting generative AI config baseline capture"
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
            $CapturedBy = $env:USER
            if (-not $CapturedBy) {
                $CapturedBy = "Operator"
            }
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

    #region Connect GACClient to Dataverse

    Import-Module "$scriptRoot\private\GACClient.psm1" -Force
    Connect-GACDataverse -DataverseUrl $DataverseUrl -AccessToken $dataverseToken
    Write-Verbose "GACClient connected to Dataverse"

    #endregion

    #region Query current agent GenAI settings

    Write-Verbose "Querying agent generative AI settings..."

    $getSettingsScript = Join-Path $scriptRoot 'Get-AgentGenAISettings.ps1'
    if (-not (Test-Path $getSettingsScript)) {
        throw "Required script not found: $getSettingsScript"
    }

    # Dot-source to load the function
    . $getSettingsScript

    $queryParams = @{
        GracePeriodHours = $GracePeriodHours
    }

    if ($ExcludeSandbox) {
        $queryParams['ExcludeSandbox'] = $true
    }
    if ($IncludeDrafts) {
        $queryParams['IncludeDrafts'] = $true
    }
    if ($DataverseUrl) {
        $queryParams['DataverseUrl'] = $DataverseUrl
    }

    $agentSettings = Get-AgentGenAISettings @queryParams

    if (-not $agentSettings -or @($agentSettings).Count -eq 0) {
        Write-Warning "No agents found. Nothing to capture."

        $emptyResult = [PSCustomObject]@{
            CapturedOn    = (Get-Date).ToUniversalTime().ToString('o')
            CapturedBy    = $CapturedBy
            TotalCaptured = 0
            ZoneBreakdown = @{ Zone1 = 0; Zone2 = 0; Zone3 = 0; Unknown = 0 }
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
            CapturedOn    = (Get-Date).ToUniversalTime().ToString('o')
            CapturedBy    = $CapturedBy
            TotalCaptured = 0
            ZoneBreakdown = @{ Zone1 = 0; Zone2 = 0; Zone3 = 0; Unknown = 0 }
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
            Write-Verbose "    ID:              $($agent.AgentId)"
            Write-Verbose "    Environment:     $($agent.EnvironmentDisplayName)"
            Write-Verbose "    Zone:            $($agent.Zone)"
            Write-Verbose "    AOAI Enabled:    $($agent.AzureOpenAIEnabled)"
            Write-Verbose "    Orchestration:   $($agent.OrchestrationMode)"
            Write-Verbose "    Gen Answers:     $($agent.GenerativeAnswersNodeCount)"
        }

        Write-Verbose "No changes written (WhatIf mode)"
    }

    #endregion

    #region Capture baselines per agent

    Write-Verbose "Capturing baselines for $($agentSettings.Count) agent(s)..."

    $capturedAgents = @()
    $zoneBreakdown = @{ Zone1 = 0; Zone2 = 0; Zone3 = 0; Unknown = 0 }

    foreach ($agent in $agentSettings) {
        $envId = $agent.EnvironmentId
        $envName = $agent.EnvironmentDisplayName
        $agentZone = $agent.Zone

        Write-Verbose "Capturing baseline for: $($agent.AgentName) in $envName ($agentZone)"

        # Build raw JSON for audit trail
        $rawJson = @{
            AgentId                    = $agent.AgentId
            AgentName                  = $agent.AgentName
            AzureOpenAIEnabled         = $agent.AzureOpenAIEnabled
            OrchestrationMode          = $agent.OrchestrationMode
            KnowledgeSourceCount       = $agent.KnowledgeSourceCount
            GenerativeAnswersNodeCount = $agent.GenerativeAnswersNodeCount
            AoaiConnectionId           = $agent.AoaiConnectionId
            AgentStatus                = $agent.AgentStatus
            EnvironmentId              = $envId
            EnvironmentDisplayName     = $envName
            EnvironmentType            = $agent.EnvironmentType
            Zone                       = $agentZone
            LastPublished              = $agent.LastPublished
            RetrievedAt                = $agent.RetrievedAt
        } | ConvertTo-Json -Compress

        $saveResult = Save-GACBaseline `
            -EnvironmentGuid $envId `
            -EnvironmentName $envName `
            -Zone $agentZone `
            -AgentId $agent.AgentId `
            -AgentName $agent.AgentName `
            -AzureOpenAIEnabled $agent.AzureOpenAIEnabled `
            -OrchestrationMode $agent.OrchestrationMode `
            -GenerativeAnswersNodeCount $agent.GenerativeAnswersNodeCount `
            -CapturedBy $CapturedBy `
            -RawJson $rawJson

        if ($null -ne $saveResult) {
            Write-Verbose "Baseline captured for $($agent.AgentName) in $envName ($agentZone)"
        } else {
            Write-Warning "Baseline save returned null for $($agent.AgentName)"
        }

        $capturedAgents += [PSCustomObject]@{
            AgentId                    = $agent.AgentId
            AgentName                  = $agent.AgentName
            EnvironmentName            = $envName
            Zone                       = $agentZone
            AzureOpenAIEnabled         = $agent.AzureOpenAIEnabled
            OrchestrationMode          = $agent.OrchestrationMode
            GenerativeAnswersNodeCount = $agent.GenerativeAnswersNodeCount
        }

        # Update zone breakdown
        if ($zoneBreakdown.ContainsKey($agentZone)) {
            $zoneBreakdown[$agentZone]++
        } else {
            $zoneBreakdown['Unknown']++
        }
    }

    Write-Verbose "Baseline capture complete. Total captured: $($capturedAgents.Count)"

    #endregion

    #region Build and emit output

    $result = [PSCustomObject]@{
        CapturedOn    = (Get-Date).ToUniversalTime().ToString('o')
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
