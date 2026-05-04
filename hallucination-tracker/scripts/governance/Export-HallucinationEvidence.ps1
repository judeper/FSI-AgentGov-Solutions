#Requires -Version 7.0
#Requires -Modules MSAL.PS

<#
.SYNOPSIS
    Exports hallucination report evidence from Dataverse to JSON with SHA-256 integrity hashing.

.DESCRIPTION
    Produces machine-readable compliance evidence packages containing hallucination
    report data, summary statistics, and cryptographic integrity verification for
    the Hallucination Feedback Tracker solution.

    Each export generates:
    - JSON evidence file with metadata, summary stats, and report records
    - SHA-256 hash companion file for integrity verification

    Evidence files support regulatory examination workflows (FINRA, SEC, GLBA)
    by providing tamper-evident exports with full report history, timestamps,
    and audit trail metadata.

    This script supports FSI-AgentGov Controls:
    - 3.10 (Hallucination Feedback Loop) — evidence collection
    - 2.9 (Performance Monitoring) — quality metrics export
    - 2.12 (Supervision) — supervisor feedback audit trail

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).

.PARAMETER TenantId
    Microsoft Entra ID tenant ID for authentication.

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID for service principal authentication.

.PARAMETER ClientSecret
    Client secret for service principal authentication (legacy dev-only fallback; prefer managed identity or workload identity for production automation).

.PARAMETER OutputDirectory
    Directory path for evidence files. Created if it does not exist.
    Default: ./evidence

.PARAMETER DaysBack
    Number of days of history to export. Default: 90.

.PARAMETER Severity
    Optional severity filter: All, Low, Medium, High, or Critical.
    Default: All.

.PARAMETER OutputFormat
    Evidence output format. Currently only JSON is supported for evidence packages.
    Default: JSON.

.PARAMETER Interactive
    Use interactive browser-based authentication instead of service principal.

.EXAMPLE
    .\Export-HallucinationEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -Interactive

    Exports 90 days of hallucination reports using interactive authentication.
    Generates JSON evidence file and SHA-256 hash in ./evidence.

.EXAMPLE
    .\Export-HallucinationEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -DaysBack 180 `
        -Severity "Critical" `
        -OutputDirectory "C:\compliance\evidence" `
        -ClientId "12345..." `
        -ClientSecret (ConvertTo-SecureString "secret" -AsPlainText -Force)

    Exports 180 days of Critical-severity reports using service principal.

.OUTPUTS
    PSCustomObject with properties:
    - EvidenceFile: Full path to JSON evidence file
    - HashFile: Full path to SHA-256 companion file
    - SHA256: Hash value (64 hex characters)
    - RecordCount: Number of report records in export
    - GeneratedAt: ISO 8601 timestamp of export generation

.NOTES
    Version: 1.2.0
    Requires:
    - PowerShell 7.0 or later
    - MSAL.PS module for Dataverse authentication
    - Hallucination Tracker Dataverse schema deployed (fsi_hallucinationreports table)

    Evidence file naming convention:
    - ht-evidence-{yyyyMMdd-HHmmss}.json
    - Example: ht-evidence-20260402-143022.json

    SHA-256 companion file format:
    - {hash}  {filename}  (two spaces, standard checksum format)
    - Verifiable via Test-EvidenceIntegrity or standard tools (shasum, certutil)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory = './evidence',

    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 3650)]
    [int]$DaysBack = 90,

    [Parameter(Mandatory = $false)]
    [ValidateSet('All', 'Low', 'Medium', 'High', 'Critical')]
    [string]$Severity = 'All',

    [Parameter(Mandatory = $false)]
    [ValidateSet('JSON')]
    [string]$OutputFormat = 'JSON',

    [Parameter(Mandatory = $false)]
    [switch]$Interactive
)

$ErrorActionPreference = "Stop"

#region Option Set Mappings

$CategoryMap = @{
    100000000 = 'Factual Error'
    100000001 = 'Fabricated Data'
    100000002 = 'Citation Missing'
    100000003 = 'Outdated Info'
    100000004 = 'Confidence Overstatement'
}

$SeverityMap = @{
    100000000 = 'Low'
    100000001 = 'Medium'
    100000002 = 'High'
    100000003 = 'Critical'
}

$SourceMap = @{
    100000000 = 'User'
    100000001 = 'Supervisor'
    100000002 = 'Automated'
    100000003 = 'Customer'
    100000004 = 'Microsoft 365 Copilot'
}

# Reverse severity map for OData filter
$SeverityValueMap = @{
    'Low'      = 100000000
    'Medium'   = 100000001
    'High'     = 100000002
    'Critical' = 100000003
}

#endregion

#region Initialization

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Hallucination Evidence Export                   ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  FSI-AgentGov Hallucination Feedback Tracker     ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path -Path $OutputDirectory)) {
    Write-Host "Creating output directory: $OutputDirectory" -ForegroundColor Cyan
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

#endregion

#region Authentication

Write-Host "Authenticating to Dataverse..." -ForegroundColor Cyan

$dataverseScope = "$($DataverseUrl.TrimEnd('/'))/.default"

if ($Interactive) {
    try {
        if (-not (Get-Module -ListAvailable -Name MSAL.PS)) {
            throw "MSAL.PS module is required for authentication. Install with: Install-Module MSAL.PS -Scope CurrentUser"
        }
        Import-Module MSAL.PS -ErrorAction Stop

        $msalParams = @{
            TenantId    = $TenantId
            Scopes      = @($dataverseScope)
            Interactive = $true
        }

        if ($ClientId) {
            $msalParams.ClientId = $ClientId
        }

        $authResult = Get-MsalToken @msalParams
        $accessToken = $authResult.AccessToken
    }
    catch {
        Write-Error "Interactive authentication failed: $($_.Exception.Message)"
        throw
    }
}
else {
    if (-not $ClientId) {
        throw "ClientId is required for service principal authentication. Use -Interactive for browser-based auth."
    }
    if (-not $ClientSecret) {
        throw "ClientSecret is required for legacy service principal authentication. Prefer managed identity or workload identity for production automation."
    }
    if (-not $TenantId) {
        throw "TenantId is required for service principal authentication."
    }

    Write-Warning "Client-secret service principal authentication is a legacy dev-only fallback. Prefer managed identity or workload identity for production automation."

    try {
        if (-not (Get-Module -ListAvailable -Name MSAL.PS)) {
            throw "MSAL.PS module is required for authentication. Install with: Install-Module MSAL.PS -Scope CurrentUser"
        }
        Import-Module MSAL.PS -ErrorAction Stop

        $authResult = Get-MsalToken `
            -TenantId $TenantId `
            -ClientId $ClientId `
            -ClientSecret $ClientSecret `
            -Scopes @($dataverseScope)

        $accessToken = $authResult.AccessToken
    }
    catch {
        Write-Error "Service principal authentication failed: $($_.Exception.Message)"
        throw
    }
}

Write-Host "Authentication successful." -ForegroundColor Green
Write-Host ""

#endregion

#region Query Hallucination Reports

Write-Host "Querying hallucination reports..." -ForegroundColor Cyan

$fromDate = (Get-Date).AddDays(-$DaysBack).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

Write-Host "  Days Back:    $DaysBack" -ForegroundColor Cyan
Write-Host "  From Date:    $fromDate" -ForegroundColor Cyan
Write-Host "  Severity:     $Severity" -ForegroundColor Cyan
Write-Host ""

$apiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"
$headers = @{
    Authorization  = "Bearer $accessToken"
    Accept         = "application/json"
    "OData-Version" = "4.0"
    Prefer         = "odata.maxpagesize=5000"
}

# Build OData filter
$filterParts = @("createdon ge $fromDate")

if ($Severity -ne 'All') {
    $severityValue = $SeverityValueMap[$Severity]
    $filterParts += "fsi_severity eq $severityValue"
}

$filter = $filterParts -join ' and '
$select = "fsi_hallucinationreportid,fsi_category,fsi_severity,fsi_agentid,fsi_description,fsi_source,fsi_reportname,fsi_conversationid,fsi_userquery,fsi_agentresponse,fsi_topicname,fsi_topicid,fsi_channelid,fsi_feedbackcomment,fsi_groundednessdetected,fsi_isresolved,fsi_resolvedby,fsi_resolvedat,fsi_reportedat,createdon,modifiedon"

$queryUrl = "$apiBase/fsi_hallucinationreports?`$select=$select&`$filter=$filter&`$orderby=createdon desc"

$allReports = @()

try {
    $nextLink = $queryUrl

    while ($nextLink) {
        $response = Invoke-RestMethod -Uri $nextLink -Headers $headers -Method Get
        $allReports += $response.value
        $nextLink = $response.'@odata.nextLink'
    }

    Write-Host "Retrieved $($allReports.Count) hallucination report(s)" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Error "Failed to query hallucination reports: $($_.Exception.Message)"
    throw
}

#endregion

#region Compute Summary Statistics

Write-Host "Computing summary statistics..." -ForegroundColor Cyan

# Map records to readable format
$reportsReadable = $allReports | ForEach-Object {
    [PSCustomObject]@{
        reportId    = $_.fsi_hallucinationreportid
        reportName  = $_.fsi_reportname
        category    = if ($null -ne $_.fsi_category) { $CategoryMap[[int]$_.fsi_category] } else { 'Unknown' }
        severity    = if ($null -ne $_.fsi_severity) { $SeverityMap[[int]$_.fsi_severity] } else { 'Unknown' }
        agentId     = $_.fsi_agentid
        description = $_.fsi_description
        source      = if ($null -ne $_.fsi_source) { $SourceMap[[int]$_.fsi_source] } else { 'Unknown' }
        conversationId = $_.fsi_conversationid
        topicName   = $_.fsi_topicname
        topicId     = $_.fsi_topicid
        channelId   = $_.fsi_channelid
        feedbackComment = $_.fsi_feedbackcomment
        groundednessDetected = $_.fsi_groundednessdetected
        reportedAt  = $_.fsi_reportedat
        createdOn   = $_.createdon
        modifiedOn  = $_.modifiedon
    }
}

$totalReports = $reportsReadable.Count

# By category
$byCategory = @{}
foreach ($report in $reportsReadable) {
    $cat = $report.category
    if (-not $byCategory.ContainsKey($cat)) { $byCategory[$cat] = 0 }
    $byCategory[$cat]++
}

# By severity
$bySeverity = @{}
foreach ($report in $reportsReadable) {
    $sev = $report.severity
    if (-not $bySeverity.ContainsKey($sev)) { $bySeverity[$sev] = 0 }
    $bySeverity[$sev]++
}

# By source
$bySource = @{}
foreach ($report in $reportsReadable) {
    $src = $report.source
    if (-not $bySource.ContainsKey($src)) { $bySource[$src] = 0 }
    $bySource[$src]++
}

# By agent
$byAgent = @{}
foreach ($report in $reportsReadable) {
    $agent = if ($report.agentId) { $report.agentId } else { '(unspecified)' }
    if (-not $byAgent.ContainsKey($agent)) { $byAgent[$agent] = 0 }
    $byAgent[$agent]++
}

Write-Host "Summary computed." -ForegroundColor Green
Write-Host ""

#endregion

#region Build Evidence JSON

Write-Host "Building evidence package..." -ForegroundColor Cyan

$exportTimestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$metadata = [PSCustomObject]@{
    exportedAt      = $exportTimestamp
    solution        = "Hallucination Feedback Tracker"
    solutionVersion = "1.2.0"
    fromDate        = $fromDate
    daysBack        = $DaysBack
    severityFilter  = $Severity
    exportVersion   = "1.0.0"
    recordCount     = $totalReports
    organizationUrl = $DataverseUrl
}

$summary = [PSCustomObject]@{
    totalReports = $totalReports
    byCategory   = $byCategory
    bySeverity   = $bySeverity
    bySource     = $bySource
    byAgent      = $byAgent
}

$evidence = [PSCustomObject]@{
    metadata = $metadata
    summary  = $summary
    reports  = @($reportsReadable)
}

#endregion

#region Write JSON Evidence File

$fileTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$fileName = "ht-evidence-$fileTimestamp.json"
$evidenceFilePath = Join-Path -Path $OutputDirectory -ChildPath $fileName

Write-Host "Writing evidence file: $evidenceFilePath" -ForegroundColor Cyan

try {
    $jsonContent = $evidence | ConvertTo-Json -Depth 10
    $jsonContent | Out-File -FilePath $evidenceFilePath -Encoding utf8 -Force

    Write-Host "Evidence file written successfully." -ForegroundColor Green
}
catch {
    Write-Error "Failed to write evidence file: $($_.Exception.Message)"
    throw
}

#endregion

#region Generate SHA-256 Hash

Write-Host "Generating SHA-256 integrity hash..." -ForegroundColor Cyan

try {
    $hashResult = Get-FileHash -Path $evidenceFilePath -Algorithm SHA256
    $hashValue = $hashResult.Hash

    # Write hash companion file in standard format: {hash}  {filename}
    $hashFileName = "$fileName.sha256"
    $hashFilePath = Join-Path -Path $OutputDirectory -ChildPath $hashFileName
    $hashContent = "$hashValue  $fileName"
    $hashContent | Out-File -FilePath $hashFilePath -Encoding utf8 -Force

    Write-Host "SHA-256 hash file created: $hashFilePath" -ForegroundColor Green
}
catch {
    Write-Error "Failed to generate SHA-256 hash: $($_.Exception.Message)"
    throw
}

#endregion

#region Display Summary

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       Evidence Export Summary                    ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host ("║ Evidence File:  {0,-33}║" -f (Split-Path -Leaf $evidenceFilePath)) -ForegroundColor Cyan
Write-Host ("║ Hash File:      {0,-33}║" -f (Split-Path -Leaf $hashFilePath)) -ForegroundColor Cyan
Write-Host ("║ Total Reports:  {0,-33}║" -f $totalReports) -ForegroundColor Cyan
Write-Host ("║ Date Range:     {0,-33}║" -f "$DaysBack days") -ForegroundColor Cyan
Write-Host ("║ Severity:       {0,-33}║" -f $Severity) -ForegroundColor Cyan
Write-Host ("║ SHA-256:        {0,-33}║" -f $hashValue.Substring(0, 33)) -ForegroundColor Cyan
Write-Host ("║                 {0,-33}║" -f $hashValue.Substring(33)) -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Evidence files ready for compliance verification." -ForegroundColor Green
Write-Host ""

#endregion

#region Return Result Object

$result = [PSCustomObject]@{
    EvidenceFile = $evidenceFilePath
    HashFile     = $hashFilePath
    SHA256       = $hashValue
    RecordCount  = $totalReports
    GeneratedAt  = $exportTimestamp
}

return $result

#endregion
