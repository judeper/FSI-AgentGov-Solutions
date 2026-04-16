#Requires -Version 7.0
#Requires -Modules Az.Accounts, Microsoft.PowerApps.Administration.PowerShell

<#
.SYNOPSIS
    Extracts per-agent connector authorizations and OAuth scope details.

.DESCRIPTION
    Queries a Power Platform environment's Dataverse for Copilot Studio agents
    and extracts detailed connector configurations including OAuth scopes,
    service principal associations, credential age, and cross-environment
    credential usage indicators.

    This script provides granular visibility into what credentials and
    permissions each agent holds, supporting least-privilege reviews and
    credential governance audits.

    For each agent, the script returns:
    - Connected connectors with their OAuth scope lists
    - Service principal associations (app registration IDs)
    - Credential age and last rotation date
    - Cross-environment credential usage indicators
    - Connection reference metadata

.PARAMETER TenantId
    Microsoft Entra ID tenant GUID. Defaults to $env:AZURE_TENANT_ID.

.PARAMETER ClientId
    Application (client) ID for service principal authentication.
    Defaults to $env:AZURE_CLIENT_ID.

.PARAMETER ClientSecret
    Client secret as SecureString for service principal authentication.
    Defaults to $env:AZURE_CLIENT_SECRET (converted to SecureString).

.PARAMETER EnvironmentId
    Power Platform environment ID to query. Required.

.PARAMETER AgentId
    Optional agent (bot) GUID to query a single agent. If omitted,
    all agents in the environment are returned.

.PARAMETER OutputFormat
    Output format: Table (default), JSON, or Object.
    - Table: Formatted table for interactive review
    - JSON: Machine-readable JSON for pipeline consumption
    - Object: Raw PSCustomObject array

.EXAMPLE
    .\Get-AgentConnectorScope.ps1 -EnvironmentId "env-guid-here"

    Lists all agents and their connector scopes in the specified environment.

.EXAMPLE
    .\Get-AgentConnectorScope.ps1 -EnvironmentId "env-guid" -AgentId "bot-guid" -OutputFormat JSON

    Returns detailed connector scope information for a single agent as JSON.

.EXAMPLE
    .\Get-AgentConnectorScope.ps1 -EnvironmentId "env-guid" -OutputFormat Object |
        Where-Object { $_.TotalScopes -gt 10 }

    Filters agents with more than 10 OAuth scopes for review.

.OUTPUTS
    PSCustomObject[] with properties per agent:
    - AgentId: Bot GUID
    - AgentName: Display name
    - EnvironmentId: Environment GUID
    - Connectors: Array of connector details (Id, Name, Scopes, ConnectionId)
    - TotalScopes: Count of unique OAuth scopes
    - ServicePrincipalId: Associated app registration (if any)
    - CredentialAgeDays: Age of oldest credential in days
    - LastRotationDate: Most recent credential rotation timestamp
    - CrossEnvironmentUsage: Boolean indicating cross-env credential sharing
    - ConnectionReferences: Array of connection reference metadata

.NOTES
    Version: 1.0.1
    Solution: Credential Oversharing Detector (COD)
    Controls: 1.14, 1.4, 1.18
    Regulations: FINRA Rule 4511, SEC 17a-4, SOX 302/404, GLBA 501(b)

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

    [Parameter(Mandatory = $true)]
    [string]$EnvironmentId,

    [Parameter()]
    [string]$AgentId,

    [Parameter()]
    [ValidateSet('Table', 'JSON', 'Object')]
    [string]$OutputFormat = 'Table'
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

Write-Host "`n[COD Agent Connector Scope Query]" -ForegroundColor Cyan
Write-Host "  Environment: $EnvironmentId" -ForegroundColor Gray
if ($AgentId) {
    Write-Host "  Agent Filter: $AgentId" -ForegroundColor Gray
}

# Resolve ClientSecret from environment if not provided
if (-not $ClientSecret -and $env:AZURE_CLIENT_SECRET) {
    $ClientSecret = $env:AZURE_CLIENT_SECRET | ConvertTo-SecureString -AsPlainText -Force
}

if (-not $TenantId) { throw "TenantId is required. Provide -TenantId or set `$env:AZURE_TENANT_ID." }
if (-not $ClientId) { throw "ClientId is required. Provide -ClientId or set `$env:AZURE_CLIENT_ID." }
if (-not $ClientSecret) { throw "ClientSecret is required. Provide -ClientSecret or set `$env:AZURE_CLIENT_SECRET." }

#endregion

#region Resolve Environment URL

Write-Host "  Resolving environment Dataverse URL..." -ForegroundColor Cyan

$ppToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId `
    -ClientSecret $ClientSecret -Resource "https://api.powerplatform.com"

$ppHeaders = @{
    "Authorization" = "Bearer $ppToken"
    "Content-Type"  = "application/json"
}

$environments = Get-AdminPowerAppEnvironment
$targetEnv = $environments | Where-Object { $_.EnvironmentName -eq $EnvironmentId }

if (-not $targetEnv) {
    throw "Environment '$EnvironmentId' not found. Verify the environment ID."
}

$envUrl = $targetEnv.Internal.properties.linkedEnvironmentMetadata.instanceUrl
if (-not $envUrl) {
    throw "No Dataverse URL found for environment '$EnvironmentId'. Environment may not have Dataverse provisioned."
}

Write-Host "  Dataverse URL: $envUrl" -ForegroundColor Gray

#endregion

#region Query Agents

Write-Host "  Querying agents..." -ForegroundColor Cyan

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

$envApiBase = "$($envUrl.TrimEnd('/'))/api/data/v9.2"

$botSelect = "botid,name,schemaname,configuration,accesscontrolpolicy,publishedon,modifiedon"
$botUrl = "$envApiBase/bots?`$select=$botSelect"

if ($AgentId) {
    $botUrl += "&`$filter=botid eq '$AgentId'"
}

$agents = [System.Collections.ArrayList]::new()
while ($botUrl) {
    try {
        $response = Invoke-RestMethod -Uri $botUrl -Headers $envHeaders -Method Get
        foreach ($bot in $response.value) {
            [void]$agents.Add($bot)
        }
        $botUrl = $response.'@odata.nextLink'
    }
    catch {
        Write-Error "Failed to query agents: $($_.Exception.Message)"
        throw
    }
}

Write-Host "  Agents found: $($agents.Count)" -ForegroundColor Gray

#endregion

#region Extract Connector Scopes

Write-Host "  Extracting connector scope details..." -ForegroundColor Cyan

# Query connection references for the environment
$connRefUrl = "$envApiBase/connectionreferences?`$select=connectionreferenceid,connectionreferencelogicalname,connectorid,connectionid,iscustomizable"
$connectionRefs = [System.Collections.ArrayList]::new()
$connRefNextUrl = $connRefUrl
while ($connRefNextUrl) {
    try {
        $connRefResponse = Invoke-RestMethod -Uri $connRefNextUrl -Headers $envHeaders -Method Get
        foreach ($ref in $connRefResponse.value) {
            [void]$connectionRefs.Add($ref)
        }
        $connRefNextUrl = $connRefResponse.'@odata.nextLink'
    }
    catch {
        Write-Host "  Warning: Could not query connection references - $($_.Exception.Message)" -ForegroundColor Yellow
        $connRefNextUrl = $null
    }
}

$results = [System.Collections.ArrayList]::new()

foreach ($agent in $agents) {
    $agentId = $agent.botid
    $agentName = $agent.name

    $connectors = [System.Collections.ArrayList]::new()
    $allScopes = [System.Collections.ArrayList]::new()
    $servicePrincipalId = $null
    $credentialAgeDays = $null
    $lastRotationDate = $null
    $crossEnvUsage = $false
    $agentConnRefs = [System.Collections.ArrayList]::new()

    # Parse agent configuration
    try {
        $configJson = $null
        if ($agent.configuration) {
            $configJson = $agent.configuration | ConvertFrom-Json -ErrorAction SilentlyContinue
        }

        if ($configJson) {
            # Extract connector details
            if ($configJson.connectorConfigurations) {
                foreach ($conn in $configJson.connectorConfigurations) {
                    $connDetail = [PSCustomObject]@{
                        ConnectorId   = $conn.connectorId
                        ConnectorName = $conn.displayName
                        Scopes        = @(if ($conn.oauthScopes) { $conn.oauthScopes } else { @() })
                        ConnectionId  = $conn.connectionId
                        ScopeCount    = if ($conn.oauthScopes) { $conn.oauthScopes.Count } else { 0 }
                    }
                    [void]$connectors.Add($connDetail)

                    if ($conn.oauthScopes) {
                        foreach ($scope in $conn.oauthScopes) {
                            if ($scope -notin $allScopes) {
                                [void]$allScopes.Add($scope)
                            }
                        }
                    }

                    # Match connection references
                    if ($conn.connectionId) {
                        $matchedRef = $connectionRefs | Where-Object { $_.connectionid -eq $conn.connectionId }
                        if ($matchedRef) {
                            [void]$agentConnRefs.Add($matchedRef)
                        }
                    }
                }
            }

            # Service principal
            if ($configJson.servicePrincipalId) {
                $servicePrincipalId = $configJson.servicePrincipalId
            }

            # Credential age
            if ($configJson.credentialCreatedDate) {
                $createdDate = [datetime]$configJson.credentialCreatedDate
                $credentialAgeDays = ((Get-Date) - $createdDate).Days
            }

            # Last rotation
            if ($configJson.credentialLastRotated) {
                $lastRotationDate = $configJson.credentialLastRotated
            }

            # Cross-environment indicator
            if ($configJson.crossEnvironmentCredentials) {
                $crossEnvUsage = $true
            }
        }
    }
    catch {
        Write-Host "    Warning: Could not parse config for $agentName - $($_.Exception.Message)" -ForegroundColor Yellow
    }

    $agentResult = [PSCustomObject]@{
        AgentId              = $agentId
        AgentName            = $agentName
        EnvironmentId        = $EnvironmentId
        Connectors           = @($connectors)
        TotalScopes          = $allScopes.Count
        UniqueScopes         = @($allScopes)
        ServicePrincipalId   = $servicePrincipalId
        CredentialAgeDays    = $credentialAgeDays
        LastRotationDate     = $lastRotationDate
        CrossEnvironmentUsage = $crossEnvUsage
        ConnectionReferences = @($agentConnRefs)
        ConnectorCount       = $connectors.Count
    }

    [void]$results.Add($agentResult)
}

#endregion

#region Output

Write-Host "`n[Results]" -ForegroundColor Cyan
Write-Host "  Agents analyzed: $($results.Count)"

switch ($OutputFormat) {
    'Table' {
        if ($results.Count -gt 0) {
            $results | Format-Table -Property AgentName, ConnectorCount, TotalScopes, ServicePrincipalId, CredentialAgeDays, CrossEnvironmentUsage -AutoSize -Wrap

            # Detail view for connector scopes
            foreach ($r in $results) {
                if ($r.Connectors.Count -gt 0) {
                    Write-Host "  Agent: $($r.AgentName)" -ForegroundColor Cyan
                    $r.Connectors | Format-Table -Property ConnectorName, ScopeCount, ConnectorId, ConnectionId -AutoSize
                }
            }
        }
        else {
            Write-Host "  No agents found." -ForegroundColor Yellow
        }
    }
    'JSON' {
        $results | ConvertTo-Json -Depth 10
    }
    'Object' {
        $results
    }
}

Write-Host "`n  Query: COMPLETE" -ForegroundColor Green

return @($results)

#endregion
