<#
.SYNOPSIS
    Exports baseline agent inventory for MRM team review.

.DESCRIPTION
    Queries fsi_agentinventory (from agent-registry-automation) and cross-checks
    against fsi_modelinventory to identify agents pending MRM onboarding.
    Authentication uses System-Assigned Managed Identity only.

    Run this script BEFORE setting IsMRMAutomationEnabled to "true" to give the
    MRM team a preview of the agent population that will be automatically
    submitted for risk scoring.

.PARAMETER DataverseEnvironmentUrl
    Target Dataverse environment URL (e.g., https://contoso.crm.dynamics.com).

.PARAMETER OutputPath
    Directory path for the baseline JSON report output.

.EXAMPLE
    .\Deploy-MRM-Baseline.ps1 -DataverseEnvironmentUrl "https://contoso.crm.dynamics.com" -OutputPath "C:\Reports"
#>

#Requires -Modules Az.Accounts

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DataverseEnvironmentUrl,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Authenticate via Managed Identity
Connect-AzAccount -Identity

$ppToken = (Get-AzAccessToken -ResourceUrl "https://api.powerplatform.com").Token
$dvToken = (Get-AzAccessToken -ResourceUrl $DataverseEnvironmentUrl).Token

$ppHeaders = @{ Authorization = "Bearer $ppToken"; "Content-Type" = "application/json" }
$dvHeaders = @{ Authorization = "Bearer $dvToken"; "Content-Type" = "application/json" }

Write-Host "Retrieving registered agents from fsi_agentinventory..." -ForegroundColor Cyan
Write-Warning "DELIVERY-CHECKLIST ITEM: Confirm entity set name 'fsi_agentinventories' matches deployed table before running."

# Query agent inventory from agent-registry-automation
$agentEntitySet = "fsi_agentinventories"
$agentQuery = "$DataverseEnvironmentUrl/api/data/v9.2/$agentEntitySet" +
              "?`$filter=fsi_registrationstatus eq 'Registered'" +
              "&`$select=fsi_agentid,fsi_agentname,fsi_environmentid," +
              "fsi_ownerupn,fsi_governancezone,fsi_lastactivitydate"

try {
    $agents = (Invoke-RestMethod -Uri $agentQuery -Headers $dvHeaders).value
    Write-Host "Found $($agents.Count) registered agents." -ForegroundColor Green
}
catch {
    Write-Error "Failed to query agent inventory from $agentEntitySet. Error: $_"
    Write-Warning "Verify the entity set name and that agent-registry-automation is deployed in this environment."
    exit 1
}

# Check which agents are already in MRM inventory
$mrmEntitySet = "fsi_modelinventories"
$mrmQuery = "$DataverseEnvironmentUrl/api/data/v9.2/$mrmEntitySet" +
            "?`$select=fsi_agentid,fsi_mrmstatus,fsi_mrmtier"
try {
    $existingMRM = (Invoke-RestMethod -Uri $mrmQuery -Headers $dvHeaders).value
    $existingIds = $existingMRM | Select-Object -ExpandProperty fsi_agentid
}
catch {
    Write-Warning "Could not query MRM inventory from $mrmEntitySet. Error: $_"
    Write-Warning "Assuming all agents are new. Confirm entity set name in DELIVERY-CHECKLIST.md."
    $existingIds = @()
}

$newAgents = $agents | Where-Object { $_.fsi_agentid -notin $existingIds }

Write-Host "=== BASELINE SUMMARY ===" -ForegroundColor Cyan
Write-Host "Total registered agents:     $($agents.Count)"
Write-Host "Already in MRM inventory:    $($existingIds.Count)" -ForegroundColor Green
Write-Host "Pending MRM entry:           $($newAgents.Count)" `
    -ForegroundColor $(if ($newAgents.Count -gt 0) { "Yellow" } else { "Green" })

# Export baseline report
$baseline = @{
    RunDate           = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    AuthMethod        = "Managed Identity"
    TotalRegistered   = $agents.Count
    AlreadyInMRM      = $existingIds.Count
    PendingMRMEntry   = $newAgents.Count
    AgentEntitySet    = $agentEntitySet
    MRMEntitySet      = $mrmEntitySet
    PendingAgentList  = $newAgents | Select-Object fsi_agentname,
                                                    fsi_agentid,
                                                    fsi_environmentid,
                                                    fsi_ownerupn,
                                                    fsi_governancezone
}

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$outputFile = Join-Path $OutputPath "mrm-baseline-$(Get-Date -Format 'yyyyMMdd').json"
$baseline | ConvertTo-Json -Depth 5 | Out-File $outputFile

Write-Host "Baseline exported to: $outputFile" -ForegroundColor Green
Write-Host "Share with MRM team for review before setting IsMRMAutomationEnabled = 'true'." -ForegroundColor Yellow
