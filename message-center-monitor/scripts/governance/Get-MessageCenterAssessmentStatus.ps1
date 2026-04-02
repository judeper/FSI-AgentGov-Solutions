#Requires -Version 7.0
#Requires -Modules MSAL.PS

<#
.SYNOPSIS
    Reports assessment status of tracked Message Center posts in Dataverse.

.DESCRIPTION
    Queries the fsi_messagecenterlog Dataverse table and produces a summary of
    assessment status across all tracked Message Center posts. Highlights posts
    with approaching action-required deadlines (within 7 days) that have not
    been assessed.

    Supports Controls 2.3 (Change Management) and 2.10 (Platform Change Monitoring)
    from the FSI Agent Governance Framework.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).

.PARAMETER TenantId
    Microsoft Entra ID tenant ID.

.PARAMETER ClientId
    Application (client) ID for service principal authentication.

.PARAMETER ClientSecret
    Client secret as a SecureString.

.PARAMETER Status
    Filter by assessment status. Default: All.

.PARAMETER DaysBack
    Number of days to look back from today. Default: 30.

.PARAMETER OutputFormat
    Output format for the report. Table, JSON, or Object.
    Default: Table.

.EXAMPLE
    $secret = ConvertTo-SecureString "mySecret" -AsPlainText -Force
    .\Get-MessageCenterAssessmentStatus.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345678-abcd-efgh-ijkl-123456789012" `
        -ClientSecret $secret `
        -Status NotAssessed

    Lists all Message Center posts that have not been assessed yet.

.EXAMPLE
    $secret = ConvertTo-SecureString "mySecret" -AsPlainText -Force
    .\Get-MessageCenterAssessmentStatus.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345678-abcd-efgh-ijkl-123456789012" `
        -ClientSecret $secret `
        -DaysBack 90 `
        -OutputFormat JSON

    Reports all assessment statuses from the past 90 days as JSON.

.OUTPUTS
    PSCustomObject with summary counts and an array of message records.

.NOTES
    Version: 1.0.0
    Requires:
    - PowerShell 7.0 or later
    - MSAL.PS module
    - Dataverse fsi_messagecenterlog table deployed

    Assessment status values:
    - 100000000 = NotAssessed
    - 100000001 = Reviewed
    - 100000002 = ImpactsAgents
    - 100000003 = NoImpact
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $true)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [ValidateSet('All', 'NotAssessed', 'Reviewed', 'ImpactsAgents', 'NoImpact')]
    [string]$Status = 'All',

    [Parameter(Mandatory = $false)]
    [int]$DaysBack = 30,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'JSON', 'Object')]
    [string]$OutputFormat = 'Table'
)

$ErrorActionPreference = "Stop"

#region Banner

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Message Center Assessment Status                ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  FSI-AgentGov Message Center Monitor             ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

#endregion

#region Assessment Status Mapping

$statusMap = @{
    'NotAssessed'  = 100000000
    'Reviewed'     = 100000001
    'ImpactsAgents' = 100000002
    'NoImpact'     = 100000003
}

$statusLabels = @{
    100000000 = 'Not Assessed'
    100000001 = 'Reviewed'
    100000002 = 'Impacts Agents'
    100000003 = 'No Impact'
}

#endregion

#region Authentication

Write-Host "Authenticating to Dataverse..." -ForegroundColor Cyan

Import-Module MSAL.PS -ErrorAction Stop

$dataverseScope = "$($DataverseUrl.TrimEnd('/'))/.default"

$msalParams = @{
    TenantId     = $TenantId
    ClientId     = $ClientId
    ClientSecret = $ClientSecret
    Scopes       = @($dataverseScope)
}

$authResult = Get-MsalToken @msalParams
$accessToken = $authResult.AccessToken

$dvHeaders = @{
    Authorization      = "Bearer $accessToken"
    'Content-Type'     = 'application/json'
    'OData-MaxVersion' = '4.0'
    'OData-Version'    = '4.0'
}

$dvBaseUrl = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"

Write-Host "Authentication successful." -ForegroundColor Green
Write-Host ""

#endregion

#region Build Query

$cutoffDate = (Get-Date).AddDays(-$DaysBack).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$selectFields = "fsi_messagecenterid,fsi_title,fsi_category,fsi_severity,fsi_assessmentstatus,fsi_startdatetime,fsi_lastmodifieddatetime,fsi_actionrequiredbydatetime,fsi_assessedby,fsi_assesseddate,fsi_ismajorchange"

$filterParts = @("fsi_startdatetime ge $cutoffDate")

if ($Status -ne 'All') {
    $statusValue = $statusMap[$Status]
    $filterParts += "fsi_assessmentstatus eq $statusValue"
}

$filterStr = $filterParts -join ' and '
$queryUrl = "$dvBaseUrl/fsi_messagecenterlogs?`$select=$selectFields&`$filter=$filterStr&`$orderby=fsi_startdatetime desc"

#endregion

#region Fetch Records with Pagination

Write-Host "Querying assessment status (last $DaysBack days, filter: $Status)..." -ForegroundColor Cyan

$allRecords = [System.Collections.Generic.List[object]]::new()
$pageUrl = $queryUrl

while ($pageUrl) {
    $response = Invoke-RestMethod -Uri $pageUrl -Headers $dvHeaders -Method Get
    if ($response.value) {
        $allRecords.AddRange($response.value)
    }
    $pageUrl = $response.'@odata.nextLink'
}

Write-Host "Retrieved $($allRecords.Count) records." -ForegroundColor Green
Write-Host ""

#endregion

#region Compute Summary

$totalCount = $allRecords.Count
$notAssessedCount = ($allRecords | Where-Object { $_.fsi_assessmentstatus -eq 100000000 }).Count
$reviewedCount = ($allRecords | Where-Object { $_.fsi_assessmentstatus -eq 100000001 }).Count
$impactsCount = ($allRecords | Where-Object { $_.fsi_assessmentstatus -eq 100000002 }).Count
$noImpactCount = ($allRecords | Where-Object { $_.fsi_assessmentstatus -eq 100000003 }).Count

# Find messages with action-required deadlines approaching within 7 days
$now = Get-Date
$urgentThreshold = $now.AddDays(7)
$urgentMessages = $allRecords | Where-Object {
    $_.fsi_actionrequiredbydatetime -and
    ([datetime]$_.fsi_actionrequiredbydatetime -le $urgentThreshold) -and
    ([datetime]$_.fsi_actionrequiredbydatetime -ge $now) -and
    ($_.fsi_assessmentstatus -eq 100000000)
}

#endregion

#region Display Report

Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       Assessment Summary                         ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host ("║ Total Messages:   {0,-31}║" -f $totalCount) -ForegroundColor Cyan
Write-Host ("║ Not Assessed:     {0,-31}║" -f $notAssessedCount) -ForegroundColor Cyan
Write-Host ("║ Reviewed:         {0,-31}║" -f $reviewedCount) -ForegroundColor Cyan
Write-Host ("║ Impacts Agents:   {0,-31}║" -f $impactsCount) -ForegroundColor Cyan
Write-Host ("║ No Impact:        {0,-31}║" -f $noImpactCount) -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if ($urgentMessages -and $urgentMessages.Count -gt 0) {
    Write-Host "⚠  URGENT: $($urgentMessages.Count) unassessed message(s) with action-required deadline within 7 days:" -ForegroundColor Yellow
    Write-Host ""
    foreach ($um in $urgentMessages) {
        $deadline = ([datetime]$um.fsi_actionrequiredbydatetime).ToString("yyyy-MM-dd")
        Write-Host "  • [$($um.fsi_messagecenterid)] $($um.fsi_title)" -ForegroundColor Yellow
        Write-Host "    Action required by: $deadline" -ForegroundColor Yellow
    }
    Write-Host ""
}

# Build readable records for output
$outputRecords = $allRecords | ForEach-Object {
    [PSCustomObject]@{
        MessageId       = $_.fsi_messagecenterid
        Title           = $_.fsi_title
        Severity        = $_.fsi_severity
        Status          = if ($statusLabels.ContainsKey($_.fsi_assessmentstatus)) { $statusLabels[$_.fsi_assessmentstatus] } else { 'Unknown' }
        StartDate       = $_.fsi_startdatetime
        ActionRequired  = $_.fsi_actionrequiredbydatetime
        IsMajorChange   = $_.fsi_ismajorchange
    }
}

$result = [PSCustomObject]@{
    TotalMessages  = $totalCount
    NotAssessed    = $notAssessedCount
    Reviewed       = $reviewedCount
    ImpactsAgents  = $impactsCount
    NoImpact       = $noImpactCount
    UrgentCount    = if ($urgentMessages) { $urgentMessages.Count } else { 0 }
    Messages       = @($outputRecords)
    QueryTimestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
}

switch ($OutputFormat) {
    'Table' {
        $outputRecords | Format-Table -AutoSize -Property MessageId, Title, Severity, Status, ActionRequired, IsMajorChange
    }
    'JSON' {
        $result | ConvertTo-Json -Depth 5
    }
    'Object' {
        return $result
    }
}

#endregion
