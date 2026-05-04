#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    Deploys baseline configuration for Agent 365 Lifecycle Governance.

.DESCRIPTION
    Queries the Microsoft Agent 365 agent registry for all agent instances, identifies those without
    owners, and exports a baseline report. Designed for Azure Automation
    Runbook execution using System-Assigned Managed Identity.

    This script supports the FSI Agent Governance Framework and helps meet
    OCC 2011-12, FINRA 3110, and SOX 302 requirements for agent lifecycle management.

.PARAMETER DataverseEnvironmentUrl
    Optional. The Dataverse environment URL (e.g., https://org.crm.dynamics.com).
    Reserved for future Dataverse schema validation during baseline deployment.
    Currently logged for traceability only — no Dataverse calls are made by this script.

.PARAMETER DefaultSponsorUPN
    Fallback sponsor UPN for agents without identified owners.

.PARAMETER DryRun
    Preview baseline results without writing the report file.

.EXAMPLE
    .\Deploy-LifecycleGovernance-Baseline.ps1 -DefaultSponsorUPN "governance@example.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$false)]
    [string]$DataverseEnvironmentUrl,

    [Parameter(Mandatory=$true)]
    [ValidatePattern('^[^@]+@[^@]+\.[^@]+$')]
    [string]$DefaultSponsorUPN,

    [switch]$DryRun
)

# Authenticate via Managed Identity
# NOTE: In Az.Accounts 5.x+, Get-AzAccessToken returns .Token as SecureString by default.
# We pass -AsSecureString:$false to keep returning a plain-text string for use in Bearer headers.
# If pinning to Az.Accounts <5, the -AsSecureString parameter does not exist and the call still
# returns a plain string — the conditional below handles both shapes.
try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    $tokenParams = @{ ResourceUrl = "https://graph.microsoft.com"; ErrorAction = 'Stop' }
    if ((Get-Command Get-AzAccessToken).Parameters.ContainsKey('AsSecureString')) {
        $tokenParams['AsSecureString'] = $false
    }
    $graphToken = (Get-AzAccessToken @tokenParams).Token
    if ($graphToken -is [System.Security.SecureString]) {
        $graphToken = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($graphToken))
    }
} catch {
    Write-Error "Authentication failed. This script requires Azure Automation with a System-Assigned Managed Identity. Ensure the identity has AgentInstance.Read.All (or AgentInstance.ReadWrite.All where updates are needed) and Dataverse access. Error: $($_.Exception.Message)"
    exit 1
}

$graphHeaders = @{ Authorization = "Bearer $graphToken"; "Content-Type" = "application/json" }

Write-Host "Querying Microsoft Agent 365 agent registry for all agent instances..." -ForegroundColor Cyan

# Retrieve all agent instances — filter client-side for instances without owners
# Server-side ownerIds filter syntax must be validated in a test tenant
# NOTE: Agent 365 reached GA on May 1, 2026 for OBO agents.
# Microsoft Learn currently documents Agent Registry APIs under Graph beta and includes
# May 2026 convergence notices for Agent 365-powered APIs. Validate this endpoint
# in a non-production tenant before enabling lifecycle flows.
try {
    $next = "https://graph.microsoft.com/beta/agentRegistry/agentInstances"
    $registryAgents = @()
    do {
        $resp = Invoke-RestMethod -Uri $next -Headers $graphHeaders -ErrorAction Stop
        if ($resp.value) { $registryAgents += $resp.value }
        $next = $resp.'@odata.nextLink'
    } while ($next)
} catch {
    Write-Error "Failed to query Agent Registry. Verify Agent 365 is enabled and managed identity has AgentInstance.Read.All. Error: $($_.Exception.Message)"
    exit 1
}
if (-not $registryAgents) { $registryAgents = @() }
$agents = $registryAgents
Write-Host "Found $($agents.Count) agents in Microsoft Agent 365 agent registry." -ForegroundColor Green

# Client-side filter for agent instances without owners
$unsponsored = $agents | Where-Object {
    -not $_.ownerIds -or ($_.ownerIds | Measure-Object).Count -eq 0
}
Write-Host "Agent instances without owners: $($unsponsored.Count)" -ForegroundColor Yellow

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

# DataverseEnvironmentUrl is reserved for future Dataverse schema validation.
# When Dataverse validation is implemented, it will verify that the ALG tables
# and columns exist in the target environment before baseline population.
Write-Host "Dataverse environment (for future validation): $DataverseEnvironmentUrl" -ForegroundColor DarkGray
Write-Host "Review unsponsored agents and set IsAgent365LifecycleEnabled to 'true' to activate flows." -ForegroundColor Yellow
Write-Host "Confirm DefaultSponsorUPN environment variable is set to: $DefaultSponsorUPN" -ForegroundColor Cyan

exit 0
