<#
.SYNOPSIS
    Creates a scope baseline for an AI agent.

.DESCRIPTION
    Captures the current data access scope for an agent by analyzing
    audit logs and connector configurations, then creates a scope definition.

.PARAMETER AgentId
    The Copilot Studio agent ID.

.PARAMETER Environment
    The Dataverse environment URL.

.PARAMETER Days
    Number of days of audit history to analyze (default: 30).

.EXAMPLE
    .\New-AgentBaseline.ps1 -AgentId "12345678-..." -Environment "https://contoso.crm.dynamics.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$AgentId,

    [Parameter(Mandatory = $true)]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [int]$Days = 30,

    [Parameter(Mandatory = $false)]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret = $env:AZURE_CLIENT_SECRET
)

$ErrorActionPreference = "Stop"

#region Helper Functions

function Get-AccessToken {
    param([string]$TenantId, [string]$ClientId, [string]$ClientSecret, [string]$Scope)

    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = $Scope
        grant_type    = "client_credentials"
    }

    $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
    return $response.access_token
}

function Get-AgentAuditEvents {
    param([string]$Token, [string]$AgentId, [int]$Days)

    $startDate = (Get-Date).AddDays(-$Days).ToString("yyyy-MM-ddTHH:mm:ssZ")
    $endDate = (Get-Date).ToString("yyyy-MM-ddTHH:mm:ssZ")

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
    }

    # Query Unified Audit Log for agent activities
    $uri = "https://graph.microsoft.com/v1.0/auditLogs/directoryAudits?`$filter=activityDateTime ge $startDate and activityDateTime le $endDate"

    $events = @()
    try {
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        $events = $response.value
    } catch {
        Write-Warning "Could not query audit logs: $($_.Exception.Message)"
    }

    return $events
}

function Analyze-ConnectorUsage {
    param([array]$Events, [string]$AgentId)

    $connectors = @()

    # Analyze events for connector patterns
    foreach ($event in $Events) {
        if ($event.targetResources) {
            foreach ($target in $event.targetResources) {
                if ($target.type -eq "Connector") {
                    $connectors += $target.displayName
                }
            }
        }
    }

    return $connectors | Select-Object -Unique
}

function Create-ScopeDefinition {
    param(
        [string]$Environment,
        [string]$Token,
        [hashtable]$Scope
    )

    $headers = @{
        "Authorization" = "Bearer $Token"
        "Content-Type"  = "application/json"
        "OData-MaxVersion" = "4.0"
        "OData-Version" = "4.0"
    }

    $uri = "$Environment/api/data/v9.2/fsi_agentscopes"
    $body = $Scope | ConvertTo-Json -Depth 5

    $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body $body
    return $response
}

#endregion

#region Main Script

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Agent Scope Baseline Generator" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

Write-Host "Agent ID: $AgentId"
Write-Host "Environment: $Environment"
Write-Host "Analysis Period: $Days days"
Write-Host ""

# Validate credentials
if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
    Write-Error "Missing credentials. Set environment variables: AZURE_TENANT_ID, AZURE_CLIENT_ID, AZURE_CLIENT_SECRET"
    exit 1
}

# Get tokens
Write-Host "Authenticating..." -ForegroundColor Gray
$graphToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "https://graph.microsoft.com/.default"
$dataverseToken = Get-AccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$Environment/.default"
Write-Host "  Authenticated successfully" -ForegroundColor Green

# Get agent audit events
Write-Host ""
Write-Host "Analyzing audit history..." -ForegroundColor Gray
$events = Get-AgentAuditEvents -Token $graphToken -AgentId $AgentId -Days $Days
Write-Host "  Found $($events.Count) audit events"

# Analyze connector usage
$connectors = Analyze-ConnectorUsage -Events $events -AgentId $AgentId
Write-Host "  Detected connectors: $($connectors -join ', ')"

# Build scope definition
Write-Host ""
Write-Host "Building scope definition..." -ForegroundColor Gray

$scopeDefinition = @{
    fsi_name = "Agent $AgentId Baseline"
    fsi_agentid = $AgentId
    fsi_zone = 2  # Default to Zone 2
    fsi_status = 1  # Draft
    fsi_purpose = "Auto-generated baseline - review and update purpose"
    fsi_allowedconnectors = ($connectors | ConvertTo-Json -Compress)
    fsi_allowedsites = "[]"
    fsi_allowedtables = "[]"
    fsi_allowedapis = "[]"
    fsi_lastvalidated = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

# Create scope in Dataverse
Write-Host ""
Write-Host "Creating scope definition in Dataverse..." -ForegroundColor Gray

try {
    $result = Create-ScopeDefinition -Environment $Environment -Token $dataverseToken -Scope $scopeDefinition
    Write-Host "  Scope created successfully" -ForegroundColor Green
    Write-Host "  Scope ID: $($result.fsi_agentscopeid)"
} catch {
    Write-Host "  Failed to create scope: $($_.Exception.Message)" -ForegroundColor Red
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Baseline Complete" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Next steps:"
Write-Host "1. Review the generated scope definition"
Write-Host "2. Add SharePoint sites, Dataverse tables, and external APIs"
Write-Host "3. Set the scope status to 'Active'"
Write-Host "4. Configure detection flows"

#endregion
