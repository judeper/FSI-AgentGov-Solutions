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

    Supports Control 2.3 (Change Management) from the FSI Agent Governance Framework.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).

.PARAMETER TenantId
    Microsoft Entra ID tenant ID.

.PARAMETER ClientId
    Application (client) ID for service principal authentication.

.PARAMETER ClientSecret
    Client secret as a SecureString. Required only when -AuthMode ClientSecret.
    legacy: dev-only — replace with managed identity in production.

.PARAMETER AuthMode
    Authentication mode. ManagedIdentity (default), WorkloadIdentity, Interactive,
    DeviceCode, or ClientSecret. ManagedIdentity requires MSAL.PS 4.37 or later.

.PARAMETER Status
    Filter by assessment status. Default: All.

.PARAMETER DaysBack
    Number of days to look back from today. Default: 30. Range: 1-365.

.PARAMETER OutputFormat
    Output format for the report. Table, JSON, or Object.
    Default: Table.

.EXAMPLE
    .\Get-MessageCenterAssessmentStatus.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -AuthMode ManagedIdentity `
        -Status NotAssessed

    Recommended: lists unassessed posts using the host's managed identity.

.EXAMPLE
    $secret = ConvertTo-SecureString "mySecret" -AsPlainText -Force
    .\Get-MessageCenterAssessmentStatus.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345678-abcd-efgh-ijkl-123456789012" `
        -ClientSecret $secret `
        -AuthMode ClientSecret `
        -DaysBack 90 `
        -OutputFormat JSON

    (dev only) Reports 90 days of assessment status as JSON.

.OUTPUTS
    PSCustomObject with summary counts and an array of message records.

.NOTES
    Version: 2.5.1
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
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter(Mandatory = $false)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [ValidateSet('ManagedIdentity', 'WorkloadIdentity', 'Interactive', 'DeviceCode', 'ClientSecret')]
    [string]$AuthMode = 'ManagedIdentity',

    [Parameter(Mandatory = $false)]
    [ValidateSet('All', 'NotAssessed', 'Reviewed', 'ImpactsAgents', 'NoImpact')]
    [string]$Status = 'All',

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 365)]
    [int]$DaysBack = 30,

    [Parameter(Mandatory = $false)]
    [ValidateSet('Table', 'JSON', 'Object')]
    [string]$OutputFormat = 'Table',

    [Parameter(Mandatory = $false)]
    [switch]$Quiet
)

. "$PSScriptRoot\_Common.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region Banner

if (-not $Quiet) {
    Write-Information "Message Center Assessment Status — FSI-AgentGov Message Center Monitor" -InformationAction Continue
}

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

# Severity option-set labels (mirror of Export-MessageCenterEvidence.ps1).
$severityLabels = @{
    100000000 = 'High'
    100000001 = 'Normal'
    100000002 = 'Critical'
}

#endregion

#region Authentication

if (-not $Quiet) { Write-Information "Authenticating to Dataverse (mode: $AuthMode)..." -InformationAction Continue }

if ($AuthMode -in @('Interactive', 'DeviceCode', 'ClientSecret')) {
    if (-not $TenantId) {
        throw "TenantId is required for -AuthMode $AuthMode. Pass -TenantId or set AZURE_TENANT_ID environment variable."
    }
    if (-not $ClientId) {
        throw "ClientId is required for -AuthMode $AuthMode. Pass -ClientId or set AZURE_CLIENT_ID environment variable."
    }
}
if ($AuthMode -eq 'ClientSecret' -and -not $ClientSecret) {
    throw "ClientSecret is required when -AuthMode ClientSecret. Use -AuthMode ManagedIdentity for production."
}

$dataverseScope = "$($DataverseUrl.TrimEnd('/'))/.default"

# Lookup display names are surfaced via FormattedValue annotations.
$dvHeaders = Get-McmDvHeaders -AuthMode $AuthMode -Scope $dataverseScope `
    -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret `
    -ExtraHeaders @{
        Prefer = 'odata.maxpagesize=500,odata.include-annotations="OData.Community.Display.V1.FormattedValue"'
    }

$dvBaseUrl = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"

if (-not $Quiet) { Write-Information "Authentication successful." -InformationAction Continue }

#endregion

#region Build Query

$cutoffDate = Format-McmODataDate ((Get-Date).AddDays(-$DaysBack))
# fsi_assessedby is a Lookup; reference its raw value and request FormattedValue
# annotations (set in Authentication header) to surface the display name.
$selectFields = "fsi_messagecenterid,fsi_title,fsi_category,fsi_severity,fsi_assessmentstatus,fsi_startdatetime,fsi_lastmodifieddatetime,fsi_actionrequiredbydatetime,_fsi_assessedby_value,fsi_assesseddate,fsi_ismajorchange"

$filterParts = @("fsi_startdatetime ge $cutoffDate")

if ($Status -ne 'All') {
    $statusValue = $statusMap[$Status]
    $filterParts += "fsi_assessmentstatus eq $statusValue"
}

$filterStr = $filterParts -join ' and '
$queryUrl = "$dvBaseUrl/fsi_messagecenterlogs?`$select=$selectFields&`$filter=$filterStr&`$orderby=fsi_startdatetime desc"

#endregion

#region Fetch Records with Pagination

if (-not $Quiet) {
    Write-Information "Querying assessment status (last $DaysBack days, filter: $Status)..." -InformationAction Continue
}

$allRecords = [System.Collections.Generic.List[object]]::new()
$pageUrl = $queryUrl
$pageCount = 0

while ($pageUrl) {
    $pageCount++
    Write-Verbose "Page $pageCount"
    if ($pageCount -gt 1000) {
        throw "Pagination exceeded 1000 pages — possible infinite loop"
    }
    try {
        $response = Invoke-McmRest -Uri $pageUrl -Headers $dvHeaders -Method Get
    }
    catch {
        Write-Error "Dataverse pagination failed at page $pageCount : $($_.Exception.Message)"
        exit 1
    }
    if ($response.value) {
        $allRecords.AddRange($response.value)
    }
    $pageUrl = $response.'@odata.nextLink'
}

if (-not $Quiet) {
    Write-Information "Retrieved $($allRecords.Count) records." -InformationAction Continue
}

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
    $sevValue = $null
    try { if ($null -ne $_.fsi_severity) { $sevValue = [int]$_.fsi_severity } } catch {}
    [PSCustomObject]@{
        MessageId       = $_.fsi_messagecenterid
        Title           = $_.fsi_title
        Severity        = if ($null -ne $sevValue -and $severityLabels.ContainsKey($sevValue)) { $severityLabels[$sevValue] } else { $sevValue }
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
