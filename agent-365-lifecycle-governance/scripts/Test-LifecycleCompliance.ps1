#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    Validates Agent 365 lifecycle compliance status.

.DESCRIPTION
    Checks sponsor coverage in Entra, queries Dataverse for overdue access reviews
    and inactive agents, and exports a compliance summary. Designed for Azure
    Automation Runbook execution using System-Assigned Managed Identity.

    This script supports the FSI Agent Governance Framework and helps meet
    FINRA 3110 supervision and SOX 302 access control requirements.

.PARAMETER DataverseEnvironmentUrl
    The Dataverse environment URL (e.g., https://org.crm.dynamics.com).

.PARAMETER DryRun
    Preview compliance results without writing the report file.

.EXAMPLE
    .\Test-LifecycleCompliance.ps1 -DataverseEnvironmentUrl "https://org.crm.dynamics.com"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [ValidateNotNullOrEmpty()]
    [string]$DataverseEnvironmentUrl,

    [switch]$DryRun
)

try {
    Connect-AzAccount -Identity -ErrorAction Stop | Out-Null
    # Normalize Dataverse URL — Dataverse OAuth audience requires trailing slash
    $dvBase = $DataverseEnvironmentUrl.TrimEnd('/')
    $dvResource = "$dvBase/"

    $tokenParams = @{ ErrorAction = 'Stop' }
    if ((Get-Command Get-AzAccessToken).Parameters.ContainsKey('AsSecureString')) {
        $tokenParams['AsSecureString'] = $false
    }
    $graphToken = (Get-AzAccessToken @tokenParams -ResourceUrl "https://graph.microsoft.com").Token
    $dvToken    = (Get-AzAccessToken @tokenParams -ResourceUrl $dvResource).Token

    foreach ($t in @('graphToken','dvToken')) {
        $val = Get-Variable -Name $t -ValueOnly
        if ($val -is [System.Security.SecureString]) {
            $plain = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($val))
            Set-Variable -Name $t -Value $plain
        }
    }
} catch {
    Write-Error "Authentication failed. This script requires Azure Automation with a System-Assigned Managed Identity. Ensure the identity has Directory.Read.All and Dataverse access. Error: $($_.Exception.Message)"
    exit 1
}

$graphHeaders = @{ Authorization = "Bearer $graphToken"; "Content-Type" = "application/json" }
$dvHeaders    = @{ Authorization = "Bearer $dvToken";    "Content-Type" = "application/json" }
$queryErrors  = $false

# Query Entra registry
# NOTE: Agent 365 reached GA on May 1, 2026 for OBO agents.
# The /beta/agentRegistry endpoint may now have a v1.0 equivalent.
# Test with v1.0 in your tenant before migrating.
# Autonomous agents with full Entra identities remain in Frontier preview.
try {
    $next = "https://graph.microsoft.com/beta/agentRegistry/agents"
    $registryAgents = @()
    do {
        $resp = Invoke-RestMethod -Uri $next -Headers $graphHeaders -ErrorAction Stop
        if ($resp.value) { $registryAgents += $resp.value }
        $next = $resp.'@odata.nextLink'
    } while ($next)
} catch {
    Write-Error "Failed to query Agent Registry. Verify Agent 365 is enabled and managed identity has Directory.Read.All. Error: $($_.Exception.Message)"
    exit 1
}
if (-not $registryAgents) { $registryAgents = @() }

$noSponsor = $registryAgents | Where-Object {
    -not $_.sponsor -or ($_.sponsor | Measure-Object).Count -eq 0
}
Write-Host "=== SPONSOR COVERAGE ===" -ForegroundColor Cyan
Write-Host "Total registered agents:  $($registryAgents.Count)"
Write-Host "Agents without sponsors:  $($noSponsor.Count)" `
    -ForegroundColor $(if ($noSponsor.Count -gt 0) { "Red" } else { "Green" })

# Query Dataverse for overdue access reviews
# fsi_ALG_accessreviewstatus option set: Not Started=100000000, In Progress=100000001, Completed=100000002, Overdue=100000003
$overdueValue = 100000003
$entitySetName = "fsi_accessreviews"

$reviewQuery = "$dvBase/api/data/v9.2/$entitySetName" +
               "?`$filter=fsi_reviewstatus eq $overdueValue"

try {
    $overdueReviews = (Invoke-RestMethod -Uri $reviewQuery -Headers $dvHeaders).value
    Write-Host "`n=== ACCESS REVIEW COMPLIANCE ===" -ForegroundColor Cyan
    Write-Host "Overdue access reviews: $($overdueReviews.Count)" `
        -ForegroundColor $(if ($overdueReviews.Count -gt 0) { "Red" } else { "Green" })
} catch {
    Write-Warning "Could not query access reviews: $_"
    Write-Warning "Verify entity set name and choice field integer values in DELIVERY-CHECKLIST.md"
    $overdueReviews = @()
    $queryErrors = $true
}

# Query Dataverse for inactive agents
# fsi_ALG_lifecyclestage option set: ... Inactive=100000003
$inactiveValue = 100000003
$inactiveQuery = "$dvBase/api/data/v9.2/fsi_agentlifecyclerecords" +
                 "?`$filter=fsi_lifecyclestage eq $inactiveValue"
try {
    $inactiveAgents = (Invoke-RestMethod -Uri $inactiveQuery -Headers $dvHeaders).value
    Write-Host "`n=== INACTIVITY COMPLIANCE ===" -ForegroundColor Cyan
    Write-Host "Agents in Inactive state: $($inactiveAgents.Count)" `
        -ForegroundColor $(if ($inactiveAgents.Count -gt 0) { "Yellow" } else { "Green" })
} catch {
    Write-Warning "Could not query inactive agents: $_"
    $inactiveAgents = @()
    $queryErrors = $true
}

# Export compliance summary
$summary = @{
    RunDate           = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    AuthMethod        = "Managed Identity"
    TotalAgents       = $registryAgents.Count
    UnsponsoredAgents = $noSponsor.Count
    OverdueReviews    = $overdueReviews.Count
    InactiveAgents    = $inactiveAgents.Count
    ComplianceStatus  = if ($queryErrors) {
                            "UNKNOWN - Query errors occurred"
                        } elseif ($noSponsor.Count -eq 0 -and $overdueReviews.Count -eq 0 -and $inactiveAgents.Count -eq 0) {
                            "COMPLIANT" } else { "NON-COMPLIANT" }
}
if (-not $DryRun) {
    $summary | ConvertTo-Json -Depth 3 |
        Out-File ".\lifecycle-compliance-$(Get-Date -Format 'yyyyMMdd').json"
    Write-Host "`nCompliance report exported." -ForegroundColor Green
} else {
    Write-Host "[DRY RUN] Would write compliance report with status: $($summary.ComplianceStatus)" -ForegroundColor Yellow
    $summary | ConvertTo-Json -Depth 3 | Write-Host
}

exit 0
