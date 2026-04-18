#Requires -Version 7.0
#Requires -Modules MSAL.PS

<#
.SYNOPSIS
    Exports Message Center Monitor evidence from Dataverse to JSON with SHA-256 integrity hashing.

.DESCRIPTION
    Produces machine-readable compliance evidence packages containing Message Center
    posts, assessment status, and cryptographic integrity verification for the
    Message Center Monitor (MCM) solution.

    Each export generates:
    - JSON evidence file with metadata, summary, and message records
    - SHA-256 hash companion file for integrity verification

    Evidence files support regulatory examination workflows by providing tamper-evident
    exports with full assessment history and timestamps.

    Supports Controls 2.3 (Change Management) and 2.10 (Platform Change Monitoring)
    from the FSI Agent Governance Framework.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).

.PARAMETER TenantId
    Microsoft Entra ID tenant ID.

.PARAMETER OutputDirectory
    Directory path for evidence files. Created if it does not exist.
    Default: ./evidence

.PARAMETER FromDate
    Start of date range filter (inclusive). Defaults to 30 days ago.

.PARAMETER ToDate
    End of date range filter (inclusive). Defaults to current timestamp.

.PARAMETER Interactive
    Use interactive browser-based authentication instead of service principal.

.PARAMETER ClientId
    Application (client) ID for service principal authentication.

.EXAMPLE
    .\Export-MessageCenterEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -Interactive

    Exports all Message Center records from the past 30 days using interactive
    authentication. Generates JSON evidence file and SHA-256 hash.

.EXAMPLE
    $secret = ConvertTo-SecureString "mySecret" -AsPlainText -Force
    .\Export-MessageCenterEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345678-abcd-efgh-ijkl-123456789012" `
        -OutputDirectory "C:\compliance\evidence" `
        -FromDate (Get-Date).AddDays(-90) `
        -ToDate (Get-Date)

    Exports 90 days of Message Center evidence using service principal authentication.

.OUTPUTS
    PSCustomObject with properties:
    - EvidenceFile: Full path to JSON evidence file
    - HashFile: Full path to SHA-256 companion file
    - SHA256: Hash value (64 hex characters)
    - RecordCount: Number of message records in export
    - GeneratedAt: ISO 8601 timestamp of export generation

.NOTES
    Version: 1.0.0
    Requires:
    - PowerShell 7.0 or later
    - MSAL.PS module
    - Dataverse fsi_messagecenterlog table deployed

    Evidence file naming convention:
    - mcm-evidence-{yyyyMMdd-HHmmss}.json
    - Example: mcm-evidence-20260209-143022.json

    SHA-256 companion file format:
    - {hash}  {filename}  (two spaces, standard checksum format)
    - Verifiable via Test-EvidenceIntegrity or standard tools (shasum, certutil)

    Regulatory context:
    Hash verification aids in meeting evidence integrity requirements for:
    - FINRA Rule 4511(a) (audit trail accuracy)
    - SEC Rule 17a-4 (record integrity)
    - SOX Section 302 / SOX Section 404 (internal control verification)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory = './evidence',

    [Parameter(Mandatory = $false)]
    [datetime]$FromDate = (Get-Date).AddDays(-30),

    [Parameter(Mandatory = $false)]
    [datetime]$ToDate = (Get-Date),

    [Parameter(Mandatory = $false)]
    [switch]$Interactive,

    [Parameter(Mandatory = $false)]
    [string]$ClientId
)

$ErrorActionPreference = "Stop"

#region Banner

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Message Center Evidence Export                   ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  FSI-AgentGov Message Center Monitor             ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

#endregion

#region Ensure Output Directory

if (-not (Test-Path -Path $OutputDirectory)) {
    Write-Host "Creating output directory: $OutputDirectory" -ForegroundColor Cyan
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

#endregion

#region Authentication

Write-Host "Authenticating to Dataverse..." -ForegroundColor Cyan

Import-Module MSAL.PS -ErrorAction Stop

$dataverseScope = "$($DataverseUrl.TrimEnd('/'))/.default"

if ($Interactive) {
    $msalParams = @{
        TenantId    = $TenantId
        Scopes      = @($dataverseScope)
        Interactive = $true
    }
    if ($ClientId) {
        $msalParams.ClientId = $ClientId
    }
    $authResult = Get-MsalToken @msalParams
}
else {
    if (-not $ClientId) {
        throw "ClientId is required for service principal authentication. Use -Interactive for browser-based auth."
    }

    # Prompt for client secret when not using interactive auth
    $clientSecret = Read-Host -AsSecureString -Prompt "Enter Client Secret"

    $authResult = Get-MsalToken `
        -TenantId $TenantId `
        -ClientId $ClientId `
        -ClientSecret $clientSecret `
        -Scopes @($dataverseScope)
}

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

#region Query Dataverse Records

$fromDateStr = $FromDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$toDateStr = $ToDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

Write-Host "Querying Message Center records..." -ForegroundColor Cyan
Write-Host "  From Date: $($FromDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
Write-Host "  To Date:   $($ToDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
Write-Host ""

$selectFields = "fsi_messagecenterid,fsi_title,fsi_category,fsi_severity,fsi_services,fsi_startdatetime,fsi_enddatetime,fsi_lastmodifieddatetime,fsi_actionrequiredbydatetime,fsi_ismajorchange,fsi_body,fsi_tags,fsi_hasattachments,fsi_assessmentstatus,fsi_assessment,fsi_impactsagents,fsi_assesseddate,fsi_actionstaken,fsi_notifiedon"
$filter = "fsi_startdatetime ge $fromDateStr and fsi_startdatetime le $toDateStr"
$queryUrl = "$dvBaseUrl/fsi_messagecenterlogs?`$select=$selectFields&`$filter=$filter&`$orderby=fsi_startdatetime desc"

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

#region Build Evidence JSON

Write-Host "Building evidence package..." -ForegroundColor Cyan

# Status label mapping
$statusLabels = @{
    100000000 = 'NotAssessed'
    100000001 = 'Reviewed'
    100000002 = 'ImpactsAgents'
    100000003 = 'NoImpact'
}

$categoryLabels = @{
    100000000 = 'Feature'
    100000001 = 'Admin'
    100000002 = 'Security'
}

$severityLabels = @{
    100000000 = 'High'
    100000001 = 'Normal'
    100000002 = 'Critical'
}

# Convert records to readable format
$messagesReadable = $allRecords | ForEach-Object {
    [PSCustomObject]@{
        messageCenterId       = $_.fsi_messagecenterid
        title                 = $_.fsi_title
        category              = if ($categoryLabels.ContainsKey($_.fsi_category)) { $categoryLabels[$_.fsi_category] } else { $_.fsi_category }
        severity              = if ($severityLabels.ContainsKey($_.fsi_severity)) { $severityLabels[$_.fsi_severity] } else { $_.fsi_severity }
        services              = $_.fsi_services
        startDateTime         = $_.fsi_startdatetime
        endDateTime           = $_.fsi_enddatetime
        lastModifiedDateTime  = $_.fsi_lastmodifieddatetime
        actionRequiredBy      = $_.fsi_actionrequiredbydatetime
        isMajorChange         = $_.fsi_ismajorchange
        tags                  = $_.fsi_tags
        hasAttachments        = $_.fsi_hasattachments
        assessmentStatus      = if ($statusLabels.ContainsKey($_.fsi_assessmentstatus)) { $statusLabels[$_.fsi_assessmentstatus] } else { $_.fsi_assessmentstatus }
        assessment            = $_.fsi_assessment
        impactsAgents         = $_.fsi_impactsagents
        assessedDate          = $_.fsi_assesseddate
        actionsTaken          = $_.fsi_actionstaken
    }
}

# Compute summary statistics
$totalMessages = $allRecords.Count
$notAssessedCount = ($allRecords | Where-Object { $_.fsi_assessmentstatus -eq 100000000 }).Count
$reviewedCount = ($allRecords | Where-Object { $_.fsi_assessmentstatus -eq 100000001 }).Count
$impactsCount = ($allRecords | Where-Object { $_.fsi_assessmentstatus -eq 100000002 }).Count
$noImpactCount = ($allRecords | Where-Object { $_.fsi_assessmentstatus -eq 100000003 }).Count
$highSeverityCount = ($allRecords | Where-Object { $_.fsi_severity -eq 100000000 }).Count
$criticalCount = ($allRecords | Where-Object { $_.fsi_severity -eq 100000002 }).Count

$exportTimestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$metadata = [PSCustomObject]@{
    exportedAt      = $exportTimestamp
    solution        = "Message Center Monitor"
    solutionVersion = "2.2.0"
    fromDate        = $FromDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    toDate          = $ToDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    exportVersion   = "1.0.0"
    recordCount     = $totalMessages
    organizationUrl = $DataverseUrl
}

$summary = [PSCustomObject]@{
    totalMessages      = $totalMessages
    notAssessed        = $notAssessedCount
    reviewed           = $reviewedCount
    impactsAgents      = $impactsCount
    noImpact           = $noImpactCount
    highSeverity       = $highSeverityCount
    critical           = $criticalCount
}

$evidence = [PSCustomObject]@{
    metadata = $metadata
    summary  = $summary
    messages = @($messagesReadable)
}

#endregion

#region Write JSON Evidence File

$fileTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$fileName = "mcm-evidence-$fileTimestamp.json"
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
Write-Host ("║ Total Messages: {0,-33}║" -f $totalMessages) -ForegroundColor Cyan
Write-Host ("║ Not Assessed:   {0,-33}║" -f $notAssessedCount) -ForegroundColor Cyan
Write-Host ("║ High Severity:  {0,-33}║" -f $highSeverityCount) -ForegroundColor Cyan
Write-Host ("║ Critical:       {0,-33}║" -f $criticalCount) -ForegroundColor Cyan
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
    RecordCount  = $totalMessages
    GeneratedAt  = $exportTimestamp
}

return $result

#endregion
