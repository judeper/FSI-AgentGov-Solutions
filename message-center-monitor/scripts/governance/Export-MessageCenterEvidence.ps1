#Requires -Version 7.0
#Requires -Modules MSAL.PS

<#
.SYNOPSIS
    Exports Message Center Monitor records from Dataverse to JSON with SHA-256 integrity hashing.

.DESCRIPTION
    Internal evidence integrity for change-tracking workflows. Generates
    machine-readable JSON artifacts with SHA-256 hashing for archival or
    audit-trail purposes (operational, not regulatory).

    Each export generates:
    - JSON file containing metadata, summary, and message records
    - SHA-256 companion file for tamper-evident integrity verification

    Supports Control 2.3 (Change Management and Release Planning) from the FSI Agent
    Governance Framework.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).

.PARAMETER TenantId
    Microsoft Entra ID tenant ID. Required for Interactive, DeviceCode, and
    ClientSecret auth modes.

.PARAMETER OutputDirectory
    Directory path for evidence files. Created if it does not exist.
    Default: ./evidence

.PARAMETER FromDate
    Start of date range filter (inclusive). Defaults to 30 days ago.

.PARAMETER ToDate
    End of date range filter (inclusive). Defaults to current timestamp.

.PARAMETER AuthMode
    Authentication mode. ManagedIdentity (default), WorkloadIdentity, Interactive,
    DeviceCode, or ClientSecret. ManagedIdentity requires MSAL.PS 4.37 or later.

.PARAMETER ClientId
    Application (client) ID. Required for Interactive, DeviceCode, and
    ClientSecret auth modes.

.PARAMETER ClientSecret
    Client secret as a SecureString. Required only when -AuthMode ClientSecret.
    legacy: dev-only — replace with managed identity in production.

.PARAMETER Quiet
    Suppress informational banner output.

.EXAMPLE
    .\Export-MessageCenterEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -AuthMode ManagedIdentity

    Recommended: exports the past 30 days using the host's managed identity.

.EXAMPLE
    .\Export-MessageCenterEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345678-abcd-efgh-ijkl-123456789012" `
        -AuthMode DeviceCode

    Admin-workstation export with device-code auth.

.EXAMPLE
    $secret = ConvertTo-SecureString "mySecret" -AsPlainText -Force
    .\Export-MessageCenterEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -ClientId "12345678-abcd-efgh-ijkl-123456789012" `
        -ClientSecret $secret `
        -AuthMode ClientSecret `
        -OutputDirectory "C:\evidence" `
        -FromDate (Get-Date).AddDays(-90) `
        -ToDate (Get-Date)

    (dev only) Exports 90 days of records using a client secret.

.OUTPUTS
    PSCustomObject with properties:
    - EvidenceFile: Full path to JSON evidence file
    - HashFile: Full path to SHA-256 companion file
    - SHA256: Hash value (64 hex characters)
    - RecordCount: Number of message records in export
    - GeneratedAt: ISO 8601 timestamp of export generation

.NOTES
    Version: 2.5.1
    Requires:
    - PowerShell 7.0 or later
    - MSAL.PS module (4.37+ for ManagedIdentity)
    - Dataverse fsi_messagecenterlog table deployed

    Evidence file naming convention:
    - mcm-evidence-{yyyyMMdd-HHmmss}.json
    - Example: mcm-evidence-20260209-143022.json

    SHA-256 companion file format:
    - {hash}  {filename}  (two spaces, standard checksum format)
    - Verifiable via Test-EvidenceIntegrity.ps1, sha256sum, or certutil
    - Files written as UTF-8 without BOM so sha256sum -c works on Linux/macOS.
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
    [ValidateSet('ManagedIdentity', 'WorkloadIdentity', 'Interactive', 'DeviceCode', 'ClientSecret')]
    [string]$AuthMode = 'ManagedIdentity',

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [switch]$Quiet
)

. "$PSScriptRoot\_Common.ps1"

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

#region Banner

if (-not $Quiet) {
    Write-Information "Message Center Evidence Export — FSI-AgentGov Message Center Monitor" -InformationAction Continue
}

#endregion

#region Ensure Output Directory

if (-not (Test-Path -Path $OutputDirectory)) {
    if (-not $Quiet) { Write-Information "Creating output directory: $OutputDirectory" -InformationAction Continue }
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

#endregion

#region Authentication

if (-not $Quiet) { Write-Information "Authenticating to Dataverse (mode: $AuthMode)..." -InformationAction Continue }

if ($AuthMode -in @('Interactive', 'DeviceCode', 'ClientSecret')) {
    if (-not $TenantId) {
        throw "TenantId is required for -AuthMode $AuthMode."
    }
    if (-not $ClientId) {
        throw "ClientId is required for -AuthMode $AuthMode."
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

#region Query Dataverse Records

$fromDateStr = Format-McmODataDate $FromDate
$toDateStr   = Format-McmODataDate $ToDate

if (-not $Quiet) {
    Write-Information "Querying Message Center records..." -InformationAction Continue
    Write-Information "  From Date: $($FromDate.ToString('yyyy-MM-dd HH:mm:ss'))" -InformationAction Continue
    Write-Information "  To Date:   $($ToDate.ToString('yyyy-MM-dd HH:mm:ss'))" -InformationAction Continue
}

# fsi_assessedby is a String column (StringAttributeMetadata, MaxLength 200) — NOT a Lookup.
# Never use _fsi_assessedby_value OData syntax on it; that returns 400 Bad Request.
# See message-center-monitor/.ralph-config.json for the column-type contract.
$selectFields = "fsi_messagecenterid,fsi_title,fsi_category,fsi_severity,fsi_services,fsi_startdatetime,fsi_enddatetime,fsi_lastmodifieddatetime,fsi_actionrequiredbydatetime,fsi_ismajorchange,fsi_body,fsi_tags,fsi_hasattachments,fsi_assessmentstatus,fsi_assessment,fsi_impactsagents,fsi_assessedby,fsi_assesseddate,fsi_actionstaken,fsi_notifiedon"
$filter = "fsi_startdatetime ge $fromDateStr and fsi_startdatetime le $toDateStr"
$queryUrl = "$dvBaseUrl/fsi_messagecenterlogs?`$select=$selectFields&`$filter=$filter&`$orderby=fsi_startdatetime desc"

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
    # StrictMode Latest throws on missing property dot-access; Dataverse omits
    # @odata.nextLink on the final page. Probe via PSObject.Properties first.
    $pageUrl = if ($response.PSObject.Properties['@odata.nextLink']) { $response.'@odata.nextLink' } else { $null }
}

if (-not $Quiet) {
    Write-Information "Retrieved $($allRecords.Count) records." -InformationAction Continue
}

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

# Convert records to readable format. fsi_assessedby is a plain String column
# (UPN of the user who recorded the assessment), so we read it directly.
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
        assessedBy            = $_.fsi_assessedby
        assessedDate          = $_.fsi_assesseddate
        actionsTaken          = $_.fsi_actionstaken
    }
}

# Compute summary statistics
$totalMessages = @($allRecords).Count
$notAssessedCount = @($allRecords | Where-Object { $_.fsi_assessmentstatus -eq 100000000 }).Count
$reviewedCount = @($allRecords | Where-Object { $_.fsi_assessmentstatus -eq 100000001 }).Count
$impactsCount = @($allRecords | Where-Object { $_.fsi_assessmentstatus -eq 100000002 }).Count
$noImpactCount = @($allRecords | Where-Object { $_.fsi_assessmentstatus -eq 100000003 }).Count
$highSeverityCount = @($allRecords | Where-Object { $_.fsi_severity -eq 100000000 }).Count
$criticalCount = @($allRecords | Where-Object { $_.fsi_severity -eq 100000002 }).Count

$exportTimestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$metadata = [PSCustomObject]@{
    exportedAt      = $exportTimestamp
    solution        = "Message Center Monitor"
    solutionVersion = "2.5.1"
    fromDate        = Format-McmODataDate $FromDate
    toDate          = Format-McmODataDate $ToDate
    exportVersion   = "1.1.0"
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

if (-not $Quiet) { Write-Information "Writing evidence file: $evidenceFilePath" -InformationAction Continue }

try {
    $jsonContent = $evidence | ConvertTo-Json -Depth 10
    # utf8NoBOM so sha256sum -c on Linux/macOS computes a matching digest.
    $jsonContent | Out-File -FilePath $evidenceFilePath -Encoding utf8NoBOM -Force
    if (-not $Quiet) { Write-Information "Evidence file written successfully." -InformationAction Continue }
}
catch {
    Write-Error "Failed to write evidence file: $($_.Exception.Message)"
    throw
}

#endregion

#region Generate SHA-256 Hash

if (-not $Quiet) { Write-Information "Generating SHA-256 integrity hash..." -InformationAction Continue }

try {
    $hashResult = Get-FileHash -Path $evidenceFilePath -Algorithm SHA256
    $hashValue = $hashResult.Hash

    # Write hash companion file in standard format: {hash}  {filename}
    $hashFileName = "$fileName.sha256"
    $hashFilePath = Join-Path -Path $OutputDirectory -ChildPath $hashFileName
    $hashContent = "$hashValue  $fileName"
    # utf8NoBOM so sha256sum -c parses cleanly on Linux/macOS.
    $hashContent | Out-File -FilePath $hashFilePath -Encoding utf8NoBOM -Force

    if (-not $Quiet) { Write-Information "SHA-256 hash file created: $hashFilePath" -InformationAction Continue }
}
catch {
    Write-Error "Failed to generate SHA-256 hash: $($_.Exception.Message)"
    throw
}

#endregion

#region Display Summary

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Green
Write-Host "║       Evidence Export Summary                    ║" -ForegroundColor Green
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Green
Write-Host ("║ Evidence File:  {0,-33}║" -f (Split-Path -Leaf $evidenceFilePath)) -ForegroundColor Green
Write-Host ("║ Hash File:      {0,-33}║" -f (Split-Path -Leaf $hashFilePath)) -ForegroundColor Green
Write-Host ("║ Total Messages: {0,-33}║" -f $totalMessages) -ForegroundColor Green
Write-Host ("║ Not Assessed:   {0,-33}║" -f $notAssessedCount) -ForegroundColor Green
Write-Host ("║ High Severity:  {0,-33}║" -f $highSeverityCount) -ForegroundColor Green
Write-Host ("║ Critical:       {0,-33}║" -f $criticalCount) -ForegroundColor Green
Write-Host ("║ SHA-256:        {0,-33}║" -f $hashValue.Substring(0, 33)) -ForegroundColor Green
Write-Host ("║                 {0,-33}║" -f $hashValue.Substring(33)) -ForegroundColor Green
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Green
Write-Host ""
Write-Host "Evidence files ready for archival or audit-trail use." -ForegroundColor Green
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
