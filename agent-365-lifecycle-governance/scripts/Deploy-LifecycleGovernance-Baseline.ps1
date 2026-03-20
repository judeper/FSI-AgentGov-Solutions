<#
.SYNOPSIS
    Deploys baseline configuration for Agent 365 Lifecycle Governance.

.DESCRIPTION
    Queries the Entra Agent Registry for all agents, identifies those without
    sponsors, and exports a baseline report. Designed for Azure Automation
    Runbook execution using System-Assigned Managed Identity.

    This script supports the FSI Agent Governance Framework and helps meet
    OCC 2011-12, FINRA 3110, and SOX 302 requirements for agent lifecycle management.

.PARAMETER DataverseEnvironmentUrl
    The Dataverse environment URL (e.g., https://org.crm.dynamics.com).

.PARAMETER DefaultSponsorUPN
    Fallback sponsor UPN for agents without identified owners.

.EXAMPLE
    .\Deploy-LifecycleGovernance-Baseline.ps1 -DataverseEnvironmentUrl "https://org.crm.dynamics.com" -DefaultSponsorUPN "governance@contoso.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$DataverseEnvironmentUrl,

    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[^@]+@[^@]+\.[^@]+$')]
    [string]$DefaultSponsorUPN
)

# Authenticate via Managed Identity
Connect-AzAccount -Identity

$graphToken = (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com").Token
$ppToken    = (Get-AzAccessToken -ResourceUrl "https://api.powerplatform.com").Token

$graphHeaders = @{ Authorization = "Bearer $graphToken"; "Content-Type" = "application/json" }
$ppHeaders    = @{ Authorization = "Bearer $ppToken";    "Content-Type" = "application/json" }

Write-Host "Querying Entra Agent Registry for all agents..." -ForegroundColor Cyan

# Retrieve all agents — filter client-side for unsponsored agents
# Server-side sponsor filter syntax must be validated in test tenant
$agentsResponse = Invoke-RestMethod `
    -Uri "https://graph.microsoft.com/beta/agentRegistry/agents" `
    -Headers $graphHeaders
$agents = $agentsResponse.value
Write-Host "Found $($agents.Count) agents in Entra Agent Registry." -ForegroundColor Green

# Client-side filter for agents without sponsors
$unsponsored = $agents | Where-Object {
    -not $_.sponsor -or ($_.sponsor | Measure-Object).Count -eq 0
}
Write-Host "Agents without sponsors: $($unsponsored.Count)" -ForegroundColor Yellow

# Export baseline report
$baseline = @{
    RunDate         = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    AuthMethod      = "Managed Identity"
    TotalAgents     = $agents.Count
    Unsponsored     = $unsponsored.Count
    UnsponsoredList = $unsponsored | Select-Object displayName, id
}
$baseline | ConvertTo-Json -Depth 5 |
    Out-File ".\lifecycle-baseline-$(Get-Date -Format 'yyyyMMdd').json"

Write-Host "Baseline exported." -ForegroundColor Green
Write-Host "Review unsponsored agents and set IsAgent365LifecycleEnabled to 'true' to activate flows." -ForegroundColor Yellow
Write-Host "Confirm DefaultSponsorUPN environment variable is set to: $DefaultSponsorUPN" -ForegroundColor Cyan
