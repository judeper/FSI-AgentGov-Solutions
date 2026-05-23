#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Az.Accounts'; ModuleVersion='2.17.0' }

<#
.SYNOPSIS
    Scans Managed Environments for bot-sharing baseline configuration deviations.

.DESCRIPTION
    Enumerates Power Platform Managed Environments and evaluates each environment's
    bot-sharing governance settings against the recommended baseline:

      - Bot sharing should NOT be unrestricted (accesscontrolpolicy != None)
      - Approval workflows should be configured for sharing requests
      - Sharing limits should be enforced per Copilot Studio admin controls

    Deviations are reported as structured JSON findings to support downstream
    compliance reporting and integration with the CTSG governance pipeline.

    This scanner complements the ASARD and UASD solutions by covering
    tenant-isolation-adjacent sharing posture at the Managed Environment level.

    Authentication follows the managed-identity-first pattern:
      1. System-assigned managed identity (default)
      2. User-assigned managed identity
      3. Workload identity federation (OIDC)
      4. Interactive / device-code
      5. Client secret (legacy: dev-only)

.PARAMETER TenantId
    Microsoft Entra ID tenant GUID. Defaults to $env:AZURE_TENANT_ID.

.PARAMETER ClientId
    Service principal application (client) ID for non-MI authentication.
    Defaults to $env:AZURE_CLIENT_ID.

.PARAMETER AuthMode
    Authentication mode. Valid values: ManagedIdentity (default), Interactive,
    ClientSecret. ManagedIdentity is recommended for production automation.

.PARAMETER EnvironmentFilter
    Optional list of environment display names or IDs to limit the scan scope.
    When omitted, all Managed Environments are scanned.

.PARAMETER OutputPath
    File path for the scan results JSON. Defaults to .\output\bot-sharing-baseline-{timestamp}.json.

.PARAMETER BaselinePolicy
    Expected bot-sharing access control policy. Default: 'Restricted'.
    Environments with a less restrictive policy generate a deviation finding.

.EXAMPLE
    .\Scan-ManagedEnvBotSharingBaseline.ps1
    Scans all Managed Environments using system-assigned managed identity.

.EXAMPLE
    .\Scan-ManagedEnvBotSharingBaseline.ps1 -AuthMode Interactive -EnvironmentFilter "Prod-*"
    Scans Managed Environments matching "Prod-*" using interactive authentication.

.NOTES
    FSI Agent Governance Framework - Cross-Tenant External Sharing Governance
    Supports compliance with FINRA 4511, GLBA 501(b), SOX 404.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter()]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter()]
    [ValidateSet('ManagedIdentity', 'Interactive', 'ClientSecret')]
    [string]$AuthMode = 'ManagedIdentity',

    [Parameter()]
    [string[]]$EnvironmentFilter,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [string]$BaselinePolicy = 'Restricted'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ── Helper: Get access token ──────────────────────────────────────────────
function Get-PlatformAccessToken {
    [CmdletBinding()]
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$AuthMode
    )

    $resource = 'https://service.powerapps.com/'

    switch ($AuthMode) {
        'ManagedIdentity' {
            Write-Verbose 'Acquiring token via system-assigned managed identity'
            $tokenResponse = Get-AzAccessToken -ResourceUrl $resource -AsSecureString
            return (ConvertFrom-SecureString -SecureString $tokenResponse.Token -AsPlainText)
        }
        'Interactive' {
            Write-Verbose 'Acquiring token via interactive authentication'
            $tokenResponse = Get-AzAccessToken -ResourceUrl $resource -TenantId $TenantId -AsSecureString
            return (ConvertFrom-SecureString -SecureString $tokenResponse.Token -AsPlainText)
        }
        'ClientSecret' {
            # legacy: dev-only — replace with managed identity in production
            Write-Warning 'ClientSecret auth is for development only. Use managed identity in production.'
            $secret = $env:AZURE_CLIENT_SECRET
            if (-not $secret) {
                throw 'AZURE_CLIENT_SECRET environment variable is required for ClientSecret auth mode.'
            }
            $body = @{
                grant_type    = 'client_credentials'
                client_id     = $ClientId
                client_secret = $secret
                resource      = $resource
            }
            $uri = "https://login.microsoftonline.com/$TenantId/oauth2/token"
            $response = Invoke-RestMethod -Uri $uri -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded'
            return $response.access_token
        }
    }
}

# ── Helper: Query Power Platform Admin API ────────────────────────────────
function Get-ManagedEnvironments {
    [CmdletBinding()]
    param(
        [string]$AccessToken,
        [string[]]$EnvironmentFilter
    )

    $apiVersion = '2021-04-01'
    $uri = "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=$apiVersion&`$expand=properties.governanceConfiguration"

    $headers = @{
        Authorization = "Bearer $AccessToken"
        Accept        = 'application/json'
    }

    Write-Verbose "Querying environments from $uri"
    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

    $environments = $response.value | Where-Object {
        $_.properties.governanceConfiguration.protectionLevel -eq 'Standard'  # Managed Environment
    }

    if ($EnvironmentFilter) {
        $environments = $environments | Where-Object {
            $env = $_
            $EnvironmentFilter | ForEach-Object {
                if ($env.properties.displayName -like $_  -or $env.name -eq $_) {
                    return $true
                }
            }
        }
    }

    return $environments
}

# ── Helper: Evaluate baseline compliance ──────────────────────────────────
function Test-BotSharingBaseline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSObject]$Environment,
        [string]$ExpectedPolicy
    )

    $findings = [System.Collections.Generic.List[PSObject]]::new()
    $envName = $Environment.properties.displayName
    $envId = $Environment.name
    $govConfig = $Environment.properties.governanceConfiguration

    # Check 1: Bot sharing access control policy
    $botSharing = $govConfig.settings.extendedSettings.botSharingAccessControl
    if (-not $botSharing -or $botSharing -ne $ExpectedPolicy) {
        $findings.Add([PSCustomObject]@{
            FindingType   = 'BOT_SHARING_UNRESTRICTED'
            Severity      = 'High'
            EnvironmentId = $envId
            Environment   = $envName
            Expected      = $ExpectedPolicy
            Actual        = if ($botSharing) { $botSharing } else { 'NotConfigured' }
            Description   = "Bot sharing access control is not set to '$ExpectedPolicy'. " +
                            'Unrestricted bot sharing may expose agents to unauthorized cross-tenant access.'
            Remediation   = "Set bot sharing access control to '$ExpectedPolicy' in the Managed Environment settings."
        })
    }

    # Check 2: Sharing approval workflow
    $sharingApproval = $govConfig.settings.extendedSettings.botSharingSharingApproval
    if (-not $sharingApproval -or $sharingApproval -ne 'Required') {
        $findings.Add([PSCustomObject]@{
            FindingType   = 'BOT_SHARING_APPROVAL_MISSING'
            Severity      = 'Medium'
            EnvironmentId = $envId
            Environment   = $envName
            Expected      = 'Required'
            Actual        = if ($sharingApproval) { $sharingApproval } else { 'NotConfigured' }
            Description   = 'Bot sharing approval workflow is not configured. ' +
                            'Agents can be shared without governance review.'
            Remediation   = 'Enable the bot sharing approval workflow in Managed Environment settings.'
        })
    }

    # Check 3: Sharing limits
    $sharingLimit = $govConfig.settings.extendedSettings.botSharingMaxShareLimit
    if (-not $sharingLimit -or [int]$sharingLimit -le 0) {
        $findings.Add([PSCustomObject]@{
            FindingType   = 'BOT_SHARING_LIMIT_MISSING'
            Severity      = 'Low'
            EnvironmentId = $envId
            Environment   = $envName
            Expected      = 'PositiveInteger'
            Actual        = if ($sharingLimit) { $sharingLimit } else { 'NotConfigured' }
            Description   = 'No bot sharing limit is configured. ' +
                            'Agents may be shared with an unbounded number of principals.'
            Remediation   = 'Configure a bot sharing limit in Managed Environment settings.'
        })
    }

    return @{
        EnvironmentId   = $envId
        EnvironmentName = $envName
        IsCompliant     = ($findings.Count -eq 0)
        FindingCount    = $findings.Count
        Findings        = $findings
        BotSharingConfig = @{
            AccessControl   = if ($botSharing) { $botSharing } else { $null }
            SharingApproval = if ($sharingApproval) { $sharingApproval } else { $null }
            MaxShareLimit   = if ($sharingLimit) { $sharingLimit } else { $null }
        }
    }
}

# ── Main ──────────────────────────────────────────────────────────────────

$timestamp = Get-Date -Format 'yyyy-MM-ddTHH-mm-ss'

if (-not $OutputPath) {
    $outputDir = Join-Path $PSScriptRoot '..' '..' 'output'
    if (-not (Test-Path $outputDir)) {
        New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
    }
    $OutputPath = Join-Path $outputDir "bot-sharing-baseline-$timestamp.json"
}

Write-Host "=== Managed Environment Bot Sharing Baseline Scanner ===" -ForegroundColor Cyan
Write-Host "Timestamp: $timestamp"
Write-Host "Auth mode: $AuthMode"
Write-Host "Baseline policy: $BaselinePolicy"

# Authenticate
$accessToken = Get-PlatformAccessToken -TenantId $TenantId -ClientId $ClientId -AuthMode $AuthMode

# Enumerate Managed Environments
$managedEnvs = Get-ManagedEnvironments -AccessToken $accessToken -EnvironmentFilter $EnvironmentFilter
Write-Host "Managed Environments found: $($managedEnvs.Count)"

if (-not $managedEnvs -or $managedEnvs.Count -eq 0) {
    Write-Warning 'No Managed Environments found matching the filter criteria.'
    $report = @{
        scanTimestamp   = $timestamp
        baselinePolicy  = $BaselinePolicy
        environmentCount = 0
        compliantCount  = 0
        nonCompliantCount = 0
        totalFindings   = 0
        results         = @()
    }
} else {
    # Evaluate each environment
    $results = [System.Collections.Generic.List[PSObject]]::new()
    foreach ($env in $managedEnvs) {
        $envName = $env.properties.displayName
        Write-Host "  Scanning: $envName" -ForegroundColor Yellow
        $result = Test-BotSharingBaseline -Environment $env -ExpectedPolicy $BaselinePolicy
        $results.Add($result)

        if ($result.IsCompliant) {
            Write-Host "    Status: Compliant" -ForegroundColor Green
        } else {
            Write-Host "    Status: Non-Compliant ($($result.FindingCount) finding(s))" -ForegroundColor Red
        }
    }

    $compliant = ($results | Where-Object { $_.IsCompliant }).Count
    $nonCompliant = ($results | Where-Object { -not $_.IsCompliant }).Count
    $totalFindings = ($results | Measure-Object -Property FindingCount -Sum).Sum

    $report = @{
        scanTimestamp    = $timestamp
        baselinePolicy   = $BaselinePolicy
        environmentCount = $managedEnvs.Count
        compliantCount   = $compliant
        nonCompliantCount = $nonCompliant
        totalFindings    = $totalFindings
        results          = $results
    }
}

# Write output
$report | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding utf8
Write-Host "`nResults written to: $OutputPath" -ForegroundColor Cyan
Write-Host "Summary: $($report.compliantCount) compliant, $($report.nonCompliantCount) non-compliant, $($report.totalFindings) total findings"
