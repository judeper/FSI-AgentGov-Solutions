<#
.SYNOPSIS
    Generates an examiner-facing MRM compliance posture report.

.DESCRIPTION
    Queries Dataverse for model inventory status, validation coverage, open
    findings, and monitoring alerts to produce a compliance summary suitable
    for regulatory examination.

    Authentication uses System-Assigned Managed Identity only.

    IMPORTANT: OptionSet integer values are deployment-dependent. Confirm all
    values against the deployed solution XML and update the parameters before
    running in production. Document confirmed values in DELIVERY-CHECKLIST.md.

.PARAMETER DataverseEnvironmentUrl
    Target Dataverse environment URL (e.g., https://contoso.crm.dynamics.com).

.PARAMETER ValidationStatusValidated
    OptionSet integer value for fsi_validationstatus = Validated.
    Default: 100000006 (per create_mrm_dataverse_schema.py).

.PARAMETER FindingSeverityCritical
    OptionSet integer value for fsi_severity = Critical.
    Default: 100000001 (per create_mrm_dataverse_schema.py).

.PARAMETER FindingStatusClosed
    OptionSet integer value for fsi_remediationstatus = Closed.
    Default: 100000004 (per create_mrm_dataverse_schema.py).

.PARAMETER MRMTierTier1
    OptionSet integer value for fsi_mrmtier = Tier 1.
    Default: 100000001 (per create_mrm_dataverse_schema.py).

.EXAMPLE
    .\Test-MRMCompliance.ps1 -DataverseEnvironmentUrl "https://contoso.crm.dynamics.com"

.EXAMPLE
    .\Test-MRMCompliance.ps1 -DataverseEnvironmentUrl "https://contoso.crm.dynamics.com" -ValidationStatusValidated 6 -FindingSeverityCritical 1
#>

#Requires -Modules Az.Accounts

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DataverseEnvironmentUrl,

    [Parameter(Mandatory = $false)]
    [int]$ValidationStatusValidated = 100000006,

    [Parameter(Mandatory = $false)]
    [int]$FindingSeverityCritical = 100000001,

    [Parameter(Mandatory = $false)]
    [int]$FindingStatusClosed = 100000004,

    [Parameter(Mandatory = $false)]
    [int]$MRMTierTier1 = 100000001
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

Connect-AzAccount -Identity
# Az.Accounts 5.0.0+ returns the token as a SecureString by default; request it
# explicitly and convert for the Authorization header so this works on both the
# legacy (plain String) and current (SecureString) module versions.
# Ref: https://learn.microsoft.com/powershell/azure/protect-secrets
$secureToken = (Get-AzAccessToken -ResourceUrl $DataverseEnvironmentUrl -AsSecureString).Token
$dvToken = [System.Net.NetworkCredential]::new('', $secureToken).Password
$dvHeaders = @{ Authorization = "Bearer $dvToken"; "Content-Type" = "application/json" }

# OptionSet dependency warning
Write-Warning "=========================================================="
Write-Warning "OPTIONSET VALUES ARE DEPLOYMENT-DEPENDENT."
Write-Warning "Current parameters: Validated=$ValidationStatusValidated, Critical=$FindingSeverityCritical, Closed=$FindingStatusClosed, Tier1=$MRMTierTier1"
Write-Warning "Confirm these values against deployed solution XML BEFORE trusting report output."
Write-Warning "Document confirmed values in DELIVERY-CHECKLIST.md."
Write-Warning "=========================================================="

Write-Host "=== MRM COMPLIANCE POSTURE REPORT ===" -ForegroundColor Cyan
Write-Host "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Cyan

function Get-DVRecords {
    param(
        [string]$Uri,
        [string]$Description
    )
    try {
        return (Invoke-RestMethod -Uri $Uri -Headers $dvHeaders).value
    }
    catch {
        Write-Warning "Query failed [$Description]: $Uri — $_"
        Write-Warning "Confirm entity set name against deployed table in DELIVERY-CHECKLIST.md."
        return @()
    }
}

$baseUrl = "$DataverseEnvironmentUrl/api/data/v9.2"

# Total inventory
$allModels = Get-DVRecords `
    "$baseUrl/fsi_modelinventories?`$select=fsi_agentid,fsi_mrmtier,fsi_currentriskrating,fsi_validationstatus,fsi_nextvalidationdue,fsi_modelid" `
    "All model inventory records"
Write-Host "`nTotal agents in MRM inventory: $($allModels.Count)"

# Agents not in Validated status
$notValidated = $allModels | Where-Object { $_.fsi_validationstatus -ne $ValidationStatusValidated }
Write-Host "Agents not in Validated status: $($notValidated.Count)" `
    -ForegroundColor $(if ($notValidated.Count -gt 0) { "Yellow" } else { "Green" })

# Tier 1 agents not validated
$tier1 = $allModels | Where-Object { $_.fsi_mrmtier -eq $MRMTierTier1 }
$tier1NotValidated = $tier1 | Where-Object { $_.fsi_validationstatus -ne $ValidationStatusValidated }
Write-Host "Tier 1 (Full MRM) agents not validated: $($tier1NotValidated.Count)" `
    -ForegroundColor $(if ($tier1NotValidated.Count -gt 0) { "Red" } else { "Green" })

# Agents with overdue validation
$overdueModels = $allModels | Where-Object {
    $null -ne $_.fsi_nextvalidationdue -and
    [DateTime]$_.fsi_nextvalidationdue -lt (Get-Date) -and
    $_.fsi_validationstatus -eq $ValidationStatusValidated
}
Write-Host "Agents with overdue validation: $($overdueModels.Count)" `
    -ForegroundColor $(if ($overdueModels.Count -gt 0) { "Red" } else { "Green" })

# Open Critical findings
$criticalFindings = Get-DVRecords `
    "$baseUrl/fsi_validationfindings?`$filter=fsi_severity eq $FindingSeverityCritical and fsi_remediationstatus ne $FindingStatusClosed&`$select=fsi_findingid,fsi_findingcategory" `
    "Open Critical findings"
Write-Host "Open Critical validation findings: $($criticalFindings.Count)" `
    -ForegroundColor $(if ($criticalFindings.Count -gt 0) { "Red" } else { "Green" })

# Monitoring alerts this week
$weekStart = (Get-Date).AddDays(-7).ToString("yyyy-MM-ddTHH:mm:ss")
$alerts = Get-DVRecords `
    "$baseUrl/fsi_monitoringrecords?`$filter=fsi_thresholdbreachflag eq true and fsi_monitoringdate ge $weekStart" `
    "Monitoring threshold breaches last 7 days"
Write-Host "Threshold breach alerts (last 7 days): $($alerts.Count)" `
    -ForegroundColor $(if ($alerts.Count -gt 0) { "Yellow" } else { "Green" })

# Active validation cycles with SLA breaches
$slaBreaches = Get-DVRecords `
    "$baseUrl/fsi_validationcycles?`$filter=fsi_slabreachflag eq true&`$select=fsi_cycleid,fsi_slabreachdetails" `
    "Validation cycles with SLA breaches"
Write-Host "Validation cycles with SLA breaches: $($slaBreaches.Count)" `
    -ForegroundColor $(if ($slaBreaches.Count -gt 0) { "Red" } else { "Green" })

# Export summary
$summary = @{
    RunDate                    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    AuthMethod                 = "Managed Identity"
    OptionSetValuesUsed        = @{
        ValidationStatusValidated = $ValidationStatusValidated
        FindingSeverityCritical   = $FindingSeverityCritical
        FindingStatusClosed       = $FindingStatusClosed
        MRMTierTier1              = $MRMTierTier1
        ConfirmationRequired      = "Verify all values against deployed solution XML before trusting report"
    }
    TotalInInventory           = $allModels.Count
    NotValidated               = $notValidated.Count
    Tier1NotValidated          = $tier1NotValidated.Count
    OverdueValidations         = $overdueModels.Count
    OpenCriticalFindings       = $criticalFindings.Count
    ThresholdBreachesThisWeek  = $alerts.Count
    SLABreachCycles            = $slaBreaches.Count
    OverallStatus              = if ($tier1NotValidated.Count -eq 0 -and
                                     $overdueModels.Count -eq 0 -and
                                     $criticalFindings.Count -eq 0) {
                                     "COMPLIANT" } else { "REQUIRES ATTENTION" }
}

$outputFile = ".\mrm-compliance-$(Get-Date -Format 'yyyyMMdd').json"
$summary | ConvertTo-Json -Depth 4 | Out-File $outputFile
Write-Host "`nCompliance report exported to: $outputFile" -ForegroundColor Green
