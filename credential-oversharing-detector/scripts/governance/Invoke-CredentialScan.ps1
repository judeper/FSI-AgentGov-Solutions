#Requires -Version 7.0
#Requires -Modules Az.Accounts, Microsoft.PowerApps.Administration.PowerShell

<#
.SYNOPSIS
    Scans Power Platform environments for agent credential oversharing violations.

.DESCRIPTION
    Main credential scope scanning script for the Credential Oversharing Detector
    (COD) solution. Enumerates Power Platform environments and their Copilot Studio
    agents, extracts connector configurations and OAuth scopes, and evaluates them
    against zone-based credential governance policies.

    Detects six violation types:
    - OverprivilegedConnector: Agent uses a connector with permissions exceeding
      its declared operating scope
    - ExcessiveOAuthScope: Agent connector requests more OAuth scopes than zone
      policy allows
    - UnauthorizedServiceAccount: Agent uses a service account not approved for
      its zone
    - CrossEnvironmentCredential: Credentials shared across multiple environments
      violating isolation policy
    - SharedCredentialMisuse: Multiple agents share the same credential when
      individual credentials are required by zone policy
    - StaleCredentialAccess: Agent uses credentials exceeding the maximum age
      defined by zone policy

    Results can be persisted to Dataverse for dashboard reporting and evidence
    collection. This script supports FSI-AgentGov credential governance controls.

.PARAMETER TenantId
    Microsoft Entra ID tenant GUID. Defaults to $env:AZURE_TENANT_ID.

.PARAMETER ClientId
    Application (client) ID for service principal authentication.
    Defaults to $env:AZURE_CLIENT_ID.

.PARAMETER ClientSecret
    Client secret as SecureString for service principal authentication.
    Defaults to $env:AZURE_CLIENT_SECRET (converted to SecureString).

.PARAMETER EnvironmentFilter
    Optional array of specific environment IDs to scan. If omitted, all
    environments are scanned.

.PARAMETER ExcludeSandbox
    Exclude sandbox-type environments from the scan. Enabled by default.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).
    When provided, scan results are persisted to fsi_credentialscans and
    fsi_credentialviolations tables.

.PARAMETER OutputFormat
    Output format: Table (default), JSON, or Object.
    - Table: Formatted table with color-coded severity
    - JSON: Machine-readable JSON for evidence export pipeline
    - Object: Raw PSCustomObject for pipeline consumption

.PARAMETER MaxOAuthScopeThreshold
    Maximum number of OAuth scopes permitted before flagging as excessive.
    Used as a fallback when zone policy is not available. Default: 10.

.PARAMETER IncludeCompliant
    Include compliant agents in output. Default: violations only.

.EXAMPLE
    .\Invoke-CredentialScan.ps1 -OutputFormat Table

    Scans all non-sandbox environments using environment variable credentials
    and displays violations in table format.

.EXAMPLE
    .\Invoke-CredentialScan.ps1 -EnvironmentFilter @("env-id-1","env-id-2") `
        -DataverseUrl "https://org.crm.dynamics.com" -OutputFormat JSON

    Scans specific environments and persists results to Dataverse with JSON output.

.EXAMPLE
    .\Invoke-CredentialScan.ps1 -ExcludeSandbox:$false -IncludeCompliant `
        -MaxOAuthScopeThreshold 5

    Scans all environments including sandboxes with a stricter scope threshold,
    including compliant agents in output.

.OUTPUTS
    PSCustomObject with properties:
    - ScanRunId: GUID identifying this scan run
    - ScanTimestamp: ISO 8601 UTC timestamp
    - TotalEnvironments: Number of environments scanned
    - TotalAgents: Number of agents evaluated
    - TotalViolations: Number of violations detected
    - ViolationsBySeverity: Hashtable of severity counts
    - Violations: Array of violation detail objects

.NOTES
    Version: 1.0.0
    Solution: Credential Oversharing Detector (COD)
    Controls: 1.11, 1.18, 3.8
    Regulations: FINRA Rule 4511, SEC 17a-4, SOX 302/404, GLBA 501(b), OCC 2011-12

    Part of FSI Agent Governance Framework
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter()]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter()]
    [SecureString]$ClientSecret,

    [Parameter()]
    [string[]]$EnvironmentFilter,

    [Parameter()]
    [switch]$ExcludeSandbox = $true,

    [Parameter()]
    [string]$DataverseUrl,

    [Parameter()]
    [ValidateSet('Table', 'JSON', 'Object')]
    [string]$OutputFormat = 'Table',

    [Parameter()]
    [ValidateRange(1, 100)]
    [int]$MaxOAuthScopeThreshold = 10,

    [Parameter()]
    [switch]$IncludeCompliant
)

$ErrorActionPreference = "Stop"

#region Helper: Get-AccessToken

function Get-AccessToken {
    <#
    .SYNOPSIS
        Acquires an OAuth access token using client credentials flow.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$ClientId,

        [Parameter(Mandatory)]
        [SecureString]$ClientSecret,

        [Parameter(Mandatory)]
        [string]$Resource
    )

    $tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $scope = "$($Resource.TrimEnd('/'))/.default"
    $plainSecret = $ClientSecret | ConvertFrom-SecureString -AsPlainText

    $body = @{
        grant_type    = "client_credentials"
        client_id     = $ClientId
        client_secret = $plainSecret
        scope         = $scope
    }

    try {
        $response = Invoke-RestMethod -Uri $tokenEndpoint -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
        return $response.access_token
    }
    catch {
        Write-Error "Failed to acquire access token for resource '$Resource': $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Initialization

Write-Host "`n[COD Credential Oversharing Scan]" -ForegroundColor Cyan
Write-Host "  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC' -AsUTC)" -ForegroundColor Gray

# Resolve ClientSecret from environment if not provided
if (-not $ClientSecret -and $env:AZURE_CLIENT_SECRET) {
    $ClientSecret = $env:AZURE_CLIENT_SECRET | ConvertTo-SecureString -AsPlainText -Force
}

# Validate required parameters
if (-not $TenantId) {
    throw "TenantId is required. Provide -TenantId or set `$env:AZURE_TENANT_ID."
}
if (-not $ClientId) {
    throw "ClientId is required. Provide -ClientId or set `$env:AZURE_CLIENT_ID."
}
if (-not $ClientSecret) {
    throw "ClientSecret is required. Provide -ClientSecret or set `$env:AZURE_CLIENT_SECRET."
}

$scanRunId = [guid]::NewGuid().ToString()
$scanTimestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

Write-Host "  Scan Run ID: $scanRunId" -ForegroundColor Gray
Write-Host "  Tenant: $TenantId" -ForegroundColor Gray

# Load zone policy helper
$policyScriptPath = Join-Path $PSScriptRoot "Get-ExpectedCredentialPolicy.ps1"
if (-not (Test-Path $policyScriptPath)) {
    Write-Warning "Get-ExpectedCredentialPolicy.ps1 not found at $policyScriptPath. Using default thresholds."
}

#endregion

#region Authentication

Write-Host "`n  Authenticating to Power Platform Admin API..." -ForegroundColor Cyan

$ppToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId `
    -ClientSecret $ClientSecret -Resource "https://api.powerplatform.com"

$ppHeaders = @{
    "Authorization" = "Bearer $ppToken"
    "Content-Type"  = "application/json"
}

# Acquire Dataverse token if persistence is requested
$dvHeaders = $null
if ($DataverseUrl) {
    Write-Host "  Authenticating to Dataverse..." -ForegroundColor Cyan
    $dvToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId `
        -ClientSecret $ClientSecret -Resource $DataverseUrl
    $dvHeaders = @{
        "Authorization"    = "Bearer $dvToken"
        "Content-Type"     = "application/json"
        "OData-Version"    = "4.0"
        "OData-MaxVersion" = "4.0"
        "Accept"           = "application/json"
        "Prefer"           = "odata.include-annotations=*,odata.maxpagesize=500"
    }
}

#endregion

#region Enumerate Environments

Write-Host "`n  Enumerating environments..." -ForegroundColor Cyan

$environments = Get-AdminPowerAppEnvironment
$envCount = 0
$agentCount = 0
$violations = [System.Collections.ArrayList]::new()
$compliantAgents = [System.Collections.ArrayList]::new()
$credentialRegistry = @{} # Track credential reuse across environments

if ($EnvironmentFilter) {
    $environments = $environments | Where-Object { $_.EnvironmentName -in $EnvironmentFilter }
}

if ($ExcludeSandbox) {
    $environments = $environments | Where-Object {
        $_.Internal.properties.environmentSku -ne "Sandbox"
    }
}

Write-Host "  Environments to scan: $($environments.Count)" -ForegroundColor Gray

#endregion

#region Scan Loop

foreach ($env in $environments) {
    $envId = $env.EnvironmentName
    $envDisplayName = $env.DisplayName
    $envUrl = $env.Internal.properties.linkedEnvironmentMetadata.instanceUrl
    $envCount++

    Write-Host "  Scanning: $envDisplayName ($envId)" -ForegroundColor Gray

    # Determine zone classification for this environment
    $zone = "Unknown"
    if ($envUrl -and $dvHeaders) {
        try {
            $elmApiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"
            $zoneFilter = "fsi_environmentid eq '$envId'"
            $zoneResponse = Invoke-RestMethod -Uri "$elmApiBase/fsi_environments?`$filter=$zoneFilter&`$select=fsi_zoneclassification" `
                -Headers $dvHeaders -Method Get
            if ($zoneResponse.value -and $zoneResponse.value.Count -gt 0) {
                $zoneValue = $zoneResponse.value[0].fsi_zoneclassification
                $zone = switch ($zoneValue) {
                    0 { "Zone1" }
                    1 { "Zone2" }
                    2 { "Zone3" }
                    default { "Unknown" }
                }
            }
        }
        catch {
            Write-Host "    Warning: Could not resolve zone for $envDisplayName" -ForegroundColor Yellow
        }
    }

    # Load zone policy
    $policy = $null
    if (Test-Path $policyScriptPath) {
        try {
            $policy = & $policyScriptPath -Zone $zone
        }
        catch {
            Write-Host "    Warning: Could not load zone policy for $zone" -ForegroundColor Yellow
        }
    }
    $maxScopes = if ($policy) { $policy.MaxOAuthScopes } else { $MaxOAuthScopeThreshold }

    # Query Copilot Studio agents via Dataverse bot table
    if (-not $envUrl) {
        Write-Host "    Skipping: No Dataverse URL for environment" -ForegroundColor Yellow
        continue
    }

    $envApiBase = "$($envUrl.TrimEnd('/'))/api/data/v9.2"
    try {
        $envToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId `
            -ClientSecret $ClientSecret -Resource $envUrl
        $envHeaders = @{
            "Authorization"    = "Bearer $envToken"
            "Content-Type"     = "application/json"
            "OData-Version"    = "4.0"
            "OData-MaxVersion" = "4.0"
            "Accept"           = "application/json"
            "Prefer"           = "odata.include-annotations=*,odata.maxpagesize=500"
        }
    }
    catch {
        Write-Host "    Warning: Auth failed for $envDisplayName - $($_.Exception.Message)" -ForegroundColor Yellow
        continue
    }

    $botUrl = "$envApiBase/bots?`$select=botid,name,schemaname,configuration,accesscontrolpolicy"
    $agents = [System.Collections.ArrayList]::new()
    while ($botUrl) {
        try {
            $botResponse = Invoke-RestMethod -Uri $botUrl -Headers $envHeaders -Method Get
            foreach ($bot in $botResponse.value) {
                [void]$agents.Add($bot)
            }
            $botUrl = $botResponse.'@odata.nextLink'
        }
        catch {
            Write-Host "    Warning: Failed to query agents - $($_.Exception.Message)" -ForegroundColor Yellow
            $botUrl = $null
        }
    }

    Write-Host "    Agents found: $($agents.Count)" -ForegroundColor Gray

    foreach ($agent in $agents) {
        $agentCount++
        $agentId = $agent.botid
        $agentName = $agent.name
        $agentViolations = [System.Collections.ArrayList]::new()

        # Extract connector configuration from agent metadata
        $connectors = @()
        $oauthScopes = @()
        $servicePrincipalId = $null
        $credentialAge = $null
        $credentialId = $null

        try {
            $configJson = $null
            if ($agent.configuration) {
                $configJson = $agent.configuration | ConvertFrom-Json -ErrorAction SilentlyContinue
            }

            if ($configJson) {
                # Extract connector references
                if ($configJson.connectorConfigurations) {
                    foreach ($conn in $configJson.connectorConfigurations) {
                        $connectors += [PSCustomObject]@{
                            ConnectorId   = $conn.connectorId
                            ConnectorName = $conn.displayName
                            Scopes        = @($conn.oauthScopes)
                            ConnectionId  = $conn.connectionId
                        }
                        if ($conn.oauthScopes) {
                            $oauthScopes += @($conn.oauthScopes)
                        }
                        if ($conn.connectionId) {
                            $credentialId = $conn.connectionId
                        }
                    }
                }

                # Extract service principal association
                if ($configJson.servicePrincipalId) {
                    $servicePrincipalId = $configJson.servicePrincipalId
                }

                # Extract credential age from metadata
                if ($configJson.credentialCreatedDate) {
                    $credentialAge = ((Get-Date) - [datetime]$configJson.credentialCreatedDate).Days
                }
            }
        }
        catch {
            Write-Host "      Warning: Could not parse config for $agentName" -ForegroundColor Yellow
        }

        $totalScopes = ($oauthScopes | Select-Object -Unique).Count

        # --- Rule 1: OverprivilegedConnector ---
        foreach ($conn in $connectors) {
            if ($conn.Scopes.Count -gt $maxScopes) {
                $severity = if ($policy) { $policy.ViolationSeverities.OverprivilegedConnector } else { "High" }
                [void]$agentViolations.Add([PSCustomObject]@{
                    ScanRunId       = $scanRunId
                    AgentId         = $agentId
                    AgentName       = $agentName
                    EnvironmentId   = $envId
                    EnvironmentName = $envDisplayName
                    Zone            = $zone
                    ViolationType   = "OverprivilegedConnector"
                    Severity        = $severity
                    Description     = "Connector '$($conn.ConnectorName)' has $($conn.Scopes.Count) scopes (max: $maxScopes)"
                    DetectedAt      = $scanTimestamp
                    ConnectorId     = $conn.ConnectorId
                    ActualScopes    = $conn.Scopes.Count
                    AllowedScopes   = $maxScopes
                })
            }
        }

        # --- Rule 2: ExcessiveOAuthScope ---
        if ($totalScopes -gt $maxScopes) {
            $severity = if ($policy) { $policy.ViolationSeverities.ExcessiveOAuthScope } else { "Medium" }
            [void]$agentViolations.Add([PSCustomObject]@{
                ScanRunId       = $scanRunId
                AgentId         = $agentId
                AgentName       = $agentName
                EnvironmentId   = $envId
                EnvironmentName = $envDisplayName
                Zone            = $zone
                ViolationType   = "ExcessiveOAuthScope"
                Severity        = $severity
                Description     = "Agent has $totalScopes unique OAuth scopes across all connectors (max: $maxScopes)"
                DetectedAt      = $scanTimestamp
                ActualScopes    = $totalScopes
                AllowedScopes   = $maxScopes
            })
        }

        # --- Rule 3: UnauthorizedServiceAccount ---
        if ($policy -and $policy.RequireServicePrincipal -and -not $servicePrincipalId) {
            $severity = if ($policy) { $policy.ViolationSeverities.UnauthorizedServiceAccount } else { "High" }
            [void]$agentViolations.Add([PSCustomObject]@{
                ScanRunId       = $scanRunId
                AgentId         = $agentId
                AgentName       = $agentName
                EnvironmentId   = $envId
                EnvironmentName = $envDisplayName
                Zone            = $zone
                ViolationType   = "UnauthorizedServiceAccount"
                Severity        = $severity
                Description     = "Agent in $zone requires a service principal but none is configured"
                DetectedAt      = $scanTimestamp
            })
        }

        # --- Rule 4: CrossEnvironmentCredential ---
        if ($credentialId) {
            if ($credentialRegistry.ContainsKey($credentialId)) {
                $otherEnv = $credentialRegistry[$credentialId]
                if ($otherEnv.EnvironmentId -ne $envId) {
                    $allowCross = if ($policy) { $policy.AllowCrossEnvironment } else { $false }
                    if (-not $allowCross) {
                        $severity = if ($policy) { $policy.ViolationSeverities.CrossEnvironmentCredential } else { "High" }
                        [void]$agentViolations.Add([PSCustomObject]@{
                            ScanRunId         = $scanRunId
                            AgentId           = $agentId
                            AgentName         = $agentName
                            EnvironmentId     = $envId
                            EnvironmentName   = $envDisplayName
                            Zone              = $zone
                            ViolationType     = "CrossEnvironmentCredential"
                            Severity          = $severity
                            Description       = "Credential '$credentialId' is also used in environment '$($otherEnv.EnvironmentName)'"
                            DetectedAt        = $scanTimestamp
                            SharedCredentialId = $credentialId
                            OtherEnvironment  = $otherEnv.EnvironmentName
                        })
                    }
                }
            }
            else {
                $credentialRegistry[$credentialId] = @{
                    EnvironmentId   = $envId
                    EnvironmentName = $envDisplayName
                    AgentId         = $agentId
                    AgentName       = $agentName
                }
            }
        }

        # --- Rule 5: SharedCredentialMisuse ---
        if ($credentialId -and $policy -and -not $policy.AllowSharedCredentials) {
            $sharedAgents = $agents | Where-Object {
                $_.botid -ne $agentId -and
                $_.configuration -and
                ($_.configuration -match [regex]::Escape($credentialId))
            }
            if ($sharedAgents.Count -gt 0) {
                $severity = if ($policy) { $policy.ViolationSeverities.SharedCredentialMisuse } else { "Medium" }
                [void]$agentViolations.Add([PSCustomObject]@{
                    ScanRunId          = $scanRunId
                    AgentId            = $agentId
                    AgentName          = $agentName
                    EnvironmentId      = $envId
                    EnvironmentName    = $envDisplayName
                    Zone               = $zone
                    ViolationType      = "SharedCredentialMisuse"
                    Severity           = $severity
                    Description        = "Credential shared with $($sharedAgents.Count) other agent(s) in zone that requires individual credentials"
                    DetectedAt         = $scanTimestamp
                    SharedCredentialId = $credentialId
                    SharedWithCount    = $sharedAgents.Count
                })
            }
        }

        # --- Rule 6: StaleCredentialAccess ---
        if ($credentialAge -and $policy -and $credentialAge -gt $policy.MaxCredentialAgeDays) {
            $severity = if ($policy) { $policy.ViolationSeverities.StaleCredentialAccess } else { "Medium" }
            [void]$agentViolations.Add([PSCustomObject]@{
                ScanRunId       = $scanRunId
                AgentId         = $agentId
                AgentName       = $agentName
                EnvironmentId   = $envId
                EnvironmentName = $envDisplayName
                Zone            = $zone
                ViolationType   = "StaleCredentialAccess"
                Severity        = $severity
                Description     = "Credential age is $credentialAge days (max: $($policy.MaxCredentialAgeDays) days)"
                DetectedAt      = $scanTimestamp
                CredentialAgeDays     = $credentialAge
                MaxCredentialAgeDays  = $policy.MaxCredentialAgeDays
            })
        }

        # Track violations or compliant agents
        if ($agentViolations.Count -gt 0) {
            foreach ($v in $agentViolations) {
                [void]$violations.Add($v)
            }
        }
        elseif ($IncludeCompliant) {
            [void]$compliantAgents.Add([PSCustomObject]@{
                AgentId         = $agentId
                AgentName       = $agentName
                EnvironmentId   = $envId
                EnvironmentName = $envDisplayName
                Zone            = $zone
                Status          = "Compliant"
                TotalScopes     = $totalScopes
                ConnectorCount  = $connectors.Count
            })
        }
    }
}

#endregion

#region Persist to Dataverse

if ($DataverseUrl -and $dvHeaders) {
    Write-Host "`n  Persisting results to Dataverse..." -ForegroundColor Cyan

    $dvApiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"

    # Write scan record
    $scanRecord = @{
        fsi_name                = "COD-Scan-$scanRunId"
        fsi_scanrunid           = $scanRunId
        fsi_scantimestamp       = $scanTimestamp
        fsi_totalenvironments   = $envCount
        fsi_totalagents         = $agentCount
        fsi_totalviolations     = $violations.Count
        fsi_scanstatus          = if ($violations.Count -eq 0) { "Compliant" } else { "ViolationsDetected" }
    }

    try {
        Invoke-RestMethod -Uri "$dvApiBase/fsi_credentialscans" -Headers $dvHeaders `
            -Method Post -Body ($scanRecord | ConvertTo-Json -Depth 5)
        Write-Host "    Scan record persisted" -ForegroundColor Green
    }
    catch {
        Write-Host "    Warning: Failed to persist scan record - $($_.Exception.Message)" -ForegroundColor Yellow
    }

    # Write violation records
    foreach ($v in $violations) {
        $violationRecord = @{
            fsi_name            = "COD-$($v.ViolationType)-$($v.AgentId.Substring(0, [Math]::Min(8, $v.AgentId.Length)))"
            fsi_scanrunid       = $scanRunId
            fsi_agentid         = $v.AgentId
            fsi_agentname       = $v.AgentName
            fsi_environmentid   = $v.EnvironmentId
            fsi_environmentname = $v.EnvironmentName
            fsi_zone            = $v.Zone
            fsi_violationtype   = $v.ViolationType
            fsi_severity        = $v.Severity
            fsi_description     = $v.Description
            fsi_detectedat      = $v.DetectedAt
        }

        try {
            Invoke-RestMethod -Uri "$dvApiBase/fsi_credentialviolations" -Headers $dvHeaders `
                -Method Post -Body ($violationRecord | ConvertTo-Json -Depth 5)
        }
        catch {
            Write-Host "    Warning: Failed to persist violation - $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    if ($violations.Count -gt 0) {
        Write-Host "    $($violations.Count) violation(s) persisted" -ForegroundColor Green
    }
}

#endregion

#region Output Results

Write-Host "`n[Scan Results]" -ForegroundColor Cyan
Write-Host "  Environments scanned: $envCount"
Write-Host "  Agents scanned: $agentCount"
Write-Host "  Violations found: $($violations.Count)"

$severityCounts = @{
    Critical      = @($violations | Where-Object { $_.Severity -eq "Critical" }).Count
    High          = @($violations | Where-Object { $_.Severity -eq "High" }).Count
    Medium        = @($violations | Where-Object { $_.Severity -eq "Medium" }).Count
    Low           = @($violations | Where-Object { $_.Severity -eq "Low" }).Count
    Informational = @($violations | Where-Object { $_.Severity -eq "Informational" }).Count
}

if ($violations.Count -gt 0) {
    if ($severityCounts.Critical -gt 0) { Write-Host "    Critical: $($severityCounts.Critical)" -ForegroundColor Red }
    if ($severityCounts.High -gt 0) { Write-Host "    High: $($severityCounts.High)" -ForegroundColor Yellow }
    if ($severityCounts.Medium -gt 0) { Write-Host "    Medium: $($severityCounts.Medium)" -ForegroundColor White }
    if ($severityCounts.Low -gt 0) { Write-Host "    Low: $($severityCounts.Low)" -ForegroundColor Gray }
    if ($severityCounts.Informational -gt 0) { Write-Host "    Informational: $($severityCounts.Informational)" -ForegroundColor Gray }
}

$allResults = @($violations)
if ($IncludeCompliant) {
    $allResults += @($compliantAgents)
}

switch ($OutputFormat) {
    'Table' {
        if ($violations.Count -gt 0) {
            Write-Host ""
            $violations | Format-Table -Property AgentName, EnvironmentName, Zone, ViolationType, Severity, Description -AutoSize -Wrap
        }
        if ($IncludeCompliant -and $compliantAgents.Count -gt 0) {
            Write-Host "`n  Compliant Agents:" -ForegroundColor Green
            $compliantAgents | Format-Table -Property AgentName, EnvironmentName, Zone, Status, TotalScopes -AutoSize
        }
    }
    'JSON' {
        $jsonOutput = @{
            scanRunId  = $scanRunId
            timestamp  = $scanTimestamp
            summary    = @{
                environmentsScanned = $envCount
                agentsScanned       = $agentCount
                totalViolations     = $violations.Count
                severityCounts      = $severityCounts
            }
            violations = @($violations)
        }
        if ($IncludeCompliant) {
            $jsonOutput["compliantAgents"] = @($compliantAgents)
        }
        $jsonOutput | ConvertTo-Json -Depth 10
    }
    'Object' {
        $allResults
    }
}

Write-Host "`n  Scan: COMPLETE" -ForegroundColor Green

#endregion

#region Return Summary

return [PSCustomObject]@{
    ScanRunId          = $scanRunId
    ScanTimestamp      = $scanTimestamp
    TotalEnvironments  = $envCount
    TotalAgents        = $agentCount
    TotalViolations    = $violations.Count
    ViolationsBySeverity = $severityCounts
    Violations         = @($violations)
}

#endregion
