#Requires -Modules Az.Accounts

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
    [string]$DefaultSponsorUPN,

    [switch]$DryRun
)

# Authenticate via Managed Identity
try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    $graphToken = (Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com" -ErrorAction Stop).Token
    # Reserved for future use — Power Platform Admin API token for PPAC operations
    $ppToken    = (Get-AzAccessToken -ResourceUrl "https://api.powerplatform.com" -ErrorAction Stop).Token
} catch {
    Write-Error "Authentication failed. This script requires Azure Automation with a System-Assigned Managed Identity. Ensure the identity has Directory.Read.All and Dataverse access. Error: $($_.Exception.Message)"
    exit 1
}

$graphHeaders = @{ Authorization = "Bearer $graphToken"; "Content-Type" = "application/json" }
$ppHeaders    = @{ Authorization = "Bearer $ppToken";    "Content-Type" = "application/json" }

Write-Host "Querying Entra Agent Registry for all agents..." -ForegroundColor Cyan

# Retrieve all agents — filter client-side for unsponsored agents
# Server-side sponsor filter syntax must be validated in test tenant
# NOTE: Agent 365 reached GA on May 1, 2026 for OBO agents.
# The /beta/agentRegistry endpoint may now have a v1.0 equivalent.
# Test with v1.0 in your tenant before migrating.
# Autonomous agents with full Entra identities remain in Frontier preview.
try {
    $registryAgents = (Invoke-RestMethod -Uri "https://graph.microsoft.com/beta/agentRegistry/agents" -Headers $graphHeaders -ErrorAction Stop).value
} catch {
    Write-Error "Failed to query Agent Registry. Verify Agent 365 is enabled and managed identity has Directory.Read.All. Error: $($_.Exception.Message)"
    exit 1
}
if (-not $registryAgents) { $registryAgents = @() }
$agents = $registryAgents
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
if (-not $DryRun) {
    $baseline | ConvertTo-Json -Depth 5 |
        Out-File ".\lifecycle-baseline-$(Get-Date -Format 'yyyyMMdd').json"
    Write-Host "Baseline exported." -ForegroundColor Green
} else {
    Write-Host "[DRY RUN] Would write baseline report for $($agents.Count) agents ($($unsponsored.Count) unsponsored)." -ForegroundColor Yellow
    $baseline | ConvertTo-Json -Depth 5 | Write-Host
}

Write-Host "Review unsponsored agents and set IsAgent365LifecycleEnabled to 'true' to activate flows." -ForegroundColor Yellow
Write-Host "Confirm DefaultSponsorUPN environment variable is set to: $DefaultSponsorUPN" -ForegroundColor Cyan

exit 0
