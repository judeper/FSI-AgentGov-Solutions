#Requires -Version 7.0

<#
.SYNOPSIS
    Exports RAG source validation evidence from Dataverse with SHA-256 integrity hashing.

.DESCRIPTION
    Produces machine-readable compliance evidence packages containing validation
    results, knowledge source metadata, change records, and cryptographic integrity
    verification for the RAG Source Validator (RSV) solution.

    Each export generates:
    - JSON evidence file with metadata, sources, validation results, changes, and summary
    - SHA-256 hash companion file for tamper detection

    Evidence files support regulatory examination workflows by providing tamper-evident
    exports with full validation history, timestamps, and audit trail metadata.

    This script supports FSI-AgentGov Controls:
    - 2.16 (RAG Source Integrity) -- evidence of source validation
    - 1.7 (Audit Logging) -- exportable audit trail
    - 2.13 (Documentation) -- compliance documentation support

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).

.PARAMETER TenantId
    Microsoft Entra ID tenant ID for authentication.

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID for the legacy client-secret fallback.

.PARAMETER ClientSecret
    Client secret as SecureString for legacy development-only fallback.

.PARAMETER UseManagedIdentity
    Use Azure managed identity authentication. This is the recommended production path for Azure-hosted automation.

.PARAMETER ManagedIdentityClientId
    Optional user-assigned managed identity client ID. Defaults to RSV_MANAGED_IDENTITY_CLIENT_ID when set; omit for system-assigned managed identity.

.PARAMETER OutputDirectory
    Directory path for evidence files. Created if it does not exist.
    Default: ./evidence

.PARAMETER DaysBack
    Number of days of history to include. Default: 30.

.PARAMETER SourceType
    Filter by source type: All, SharePoint, Dataverse, AzureBlob, External, PublicWebsite, OneDrive, CopilotConnector, AzureAISearch, or CopilotStudioDocument.
    Default: All.

.PARAMETER Interactive
    Use interactive browser-based authentication for admin-workstation runs.

.EXAMPLE
    .\Export-ValidationEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -Interactive

    Exports all validation evidence from the past 30 days using interactive
    authentication. Generates JSON evidence file and SHA-256 hash.

.EXAMPLE
    .\Export-ValidationEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -UseManagedIdentity `
        -OutputDirectory "C:\compliance\evidence" `
        -DaysBack 90 `
        -SourceType SharePoint

    Exports 90 days of SharePoint source validation evidence using Azure managed identity for scheduled automation.

.OUTPUTS
    PSCustomObject with properties:
    - EvidenceFile: Full path to JSON evidence file
    - HashFile: Full path to SHA-256 companion file
    - SHA256: Hash value (64 hex characters)
    - SourceCount: Number of knowledge source records
    - ValidationCount: Number of validation result records
    - ChangeCount: Number of source change records
    - GeneratedAt: ISO 8601 timestamp of export generation

.NOTES
    Version: 1.0.0
    Requires:
    - PowerShell 7.0 or later
    - MSAL.PS module for interactive authentication
    - RSV Dataverse schema deployed (fsi_knowledgesources, fsi_validationresults,
      fsi_sourcechanges tables)

    Evidence file naming convention:
    - rsv-evidence-{yyyyMMdd-HHmmss}.json
    - Example: rsv-evidence-20260315-143022.json

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

    # legacy: dev-only - replace with managed identity in production.
    [Parameter(Mandatory = $false)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [string]$OutputDirectory = './evidence',

    [Parameter(Mandatory = $false)]
    [int]$DaysBack = 30,

    [Parameter(Mandatory = $false)]
    [ValidateSet('All', 'SharePoint', 'Dataverse', 'AzureBlob', 'External', 'PublicWebsite', 'OneDrive', 'CopilotConnector', 'AzureAISearch', 'CopilotStudioDocument')]
    [string]$SourceType = 'All',

    [Parameter(Mandatory = $false)]
    [ValidateSet('https://login.microsoftonline.com','https://login.microsoftonline.us','https://login.chinacloudapi.cn')]
    [string]$AuthBaseUrl = 'https://login.microsoftonline.com',

    [Parameter(Mandatory = $false)]
    [switch]$Interactive,

    [Parameter(Mandatory = $false)]
    [switch]$UseManagedIdentity,

    [Parameter(Mandatory = $false)]
    [string]$ManagedIdentityClientId = $env:RSV_MANAGED_IDENTITY_CLIENT_ID
)

$ErrorActionPreference = "Stop"

#region Initialization

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  RAG Source Validation Evidence Export            ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  FSI-AgentGov RAG Source Validator                ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Validate Dataverse URL to prevent token exfiltration
if ($DataverseUrl -notmatch '^https://[a-z0-9\-]+\.(crm[0-9]*\.dynamics\.com|crm\.microsoftdynamics\.us|crm\.appsplatform\.us|crm\.dynamics\.cn)/?$') {
    throw "Invalid DataverseUrl '$DataverseUrl'. Expected a Dataverse environment URL (e.g., https://contoso.crm.dynamics.com)."
}
$DataverseUrl = $DataverseUrl.TrimEnd('/')

# Ensure output directory exists
if (-not (Test-Path -Path $OutputDirectory)) {
    Write-Host "Creating output directory: $OutputDirectory" -ForegroundColor Cyan
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

#endregion

#region Authentication

Write-Host "Authenticating to Dataverse..." -ForegroundColor Cyan

$dataverseResource = $DataverseUrl
$dataverseScope = "$DataverseUrl/.default"

function Get-ManagedIdentityAccessToken {
    param([string]$Resource)

    $encodedResource = [System.Uri]::EscapeDataString($Resource)
    $headers = @{ Metadata = "true" }

    if ($env:IDENTITY_ENDPOINT -and $env:IDENTITY_HEADER) {
        $tokenUrl = "$($env:IDENTITY_ENDPOINT)?api-version=2019-08-01&resource=$encodedResource"
        $headers["X-IDENTITY-HEADER"] = $env:IDENTITY_HEADER
    } elseif ($env:MSI_ENDPOINT -and $env:MSI_SECRET) {
        $tokenUrl = "$($env:MSI_ENDPOINT)?api-version=2017-09-01&resource=$encodedResource"
        $headers = @{ Secret = $env:MSI_SECRET }
    } else {
        $tokenUrl = "http://169.254.169.254/metadata/identity/oauth2/token?api-version=2018-02-01&resource=$encodedResource"
    }

    if ($ManagedIdentityClientId) {
        $encodedClientId = [System.Uri]::EscapeDataString($ManagedIdentityClientId)
        $tokenUrl = "$tokenUrl&client_id=$encodedClientId"
    }

    try {
        $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Headers $headers -Method Get -TimeoutSec 10 -MaximumRetryCount 2 -RetryIntervalSec 2
        return $tokenResponse.access_token
    }
    catch {
        throw "Managed identity authentication failed for Dataverse. Run in an Azure host with managed identity enabled, use -Interactive for admin workstations, or use the legacy dev-only client-secret fallback. $($_.Exception.Message)"
    }
}

$useManagedIdentityAuth = $UseManagedIdentity -or (-not $Interactive -and $null -eq $ClientSecret)

if ($useManagedIdentityAuth) {
    $accessToken = Get-ManagedIdentityAccessToken -Resource $dataverseResource
}
elseif ($Interactive) {
    try {
        if (-not (Get-Module -ListAvailable -Name MSAL.PS)) {
            throw "MSAL.PS module is required for interactive authentication. Install with: Install-Module MSAL.PS -Scope CurrentUser"
        }
        Import-Module MSAL.PS -ErrorAction Stop

        $msalParams = @{
            Scopes      = @($dataverseScope)
            Interactive = $true
        }
        if ($TenantId) { $msalParams.TenantId = $TenantId }
        if ($ClientId) { $msalParams.ClientId = $ClientId }

        $authResult = Get-MsalToken @msalParams
        $accessToken = $authResult.AccessToken
    }
    catch {
        Write-Error "Interactive authentication failed: $($_.Exception.Message)"
        throw
    }
}
else {
    # legacy: dev-only - replace with managed identity in production.
    if (-not $TenantId) {
        throw "TenantId is required for legacy client-secret authentication. Use -UseManagedIdentity for Azure-hosted automation or -Interactive for browser-based auth."
    }
    if (-not $ClientId) {
        throw "ClientId is required for legacy client-secret authentication. Use -UseManagedIdentity for Azure-hosted automation or -Interactive for browser-based auth."
    }
    if ($null -eq $ClientSecret) {
        throw "ClientSecret is required for legacy client-secret authentication. Use -UseManagedIdentity for Azure-hosted automation or -Interactive for browser-based auth."
    }

    $clientSecretPlain = [System.Net.NetworkCredential]::new('', $ClientSecret).Password

    $tokenBody = @{
        client_id     = $ClientId
        client_secret = $clientSecretPlain
        scope         = $dataverseScope
        grant_type    = "client_credentials"
    }
    $tokenUrl = "$AuthBaseUrl/$TenantId/oauth2/v2.0/token"

    try {
        $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $tokenBody `
            -ContentType "application/x-www-form-urlencoded" -MaximumRetryCount 3 -RetryIntervalSec 5
        $accessToken = $tokenResponse.access_token
    }
    catch {
        Write-Error "Legacy client-secret authentication failed: $($_.Exception.Message)"
        throw
    }
}

Write-Host "Authentication successful." -ForegroundColor Green
Write-Host ""

$headers = @{
    "Authorization"    = "Bearer $accessToken"
    "Content-Type"     = "application/json"
    "OData-MaxVersion" = "4.0"
    "OData-Version"    = "4.0"
}

#endregion

#region Helper: Paginated Query

function Invoke-DataverseQuery {
    param([string]$Uri, [hashtable]$Headers)

    $results = [System.Collections.Generic.List[object]]::new()
    $nextLink = $Uri
    while ($nextLink) {
        $response = Invoke-RestMethod -Uri $nextLink -Headers $Headers -Method Get `
            -MaximumRetryCount 3 -RetryIntervalSec 5
        if ($response.value) {
            $results.AddRange([object[]]$response.value)
        }
        $nextLink = $response.'@odata.nextLink'
    }
    return $results
}

#endregion

#region Query Validation Results

$fromDate = (Get-Date).AddDays(-$DaysBack).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

Write-Host "Querying validation results..." -ForegroundColor Cyan
Write-Host "  Days Back:    $DaysBack (since $fromDate)" -ForegroundColor Cyan
Write-Host "  Source Type:  $SourceType" -ForegroundColor Cyan
Write-Host ""

$validationFilter = "fsi_validationtime ge $fromDate"
$validationSelect = "fsi_validationresultid,fsi_validationtime,fsi_result,fsi_previoushash,fsi_currenthash,fsi_hashchanged,fsi_changedetails,fsi_validationtype,fsi_duration,fsi_errordetails,createdon,_fsi_knowledgesourceid_value"
$validationUri = "$DataverseUrl/api/data/v9.2/fsi_validationresults?`$select=$validationSelect&`$filter=$validationFilter&`$orderby=fsi_validationtime desc"

$validationResults = Invoke-DataverseQuery -Uri $validationUri -Headers $headers
Write-Host "Retrieved $($validationResults.Count) validation records" -ForegroundColor Green

#endregion

#region Query Knowledge Sources

Write-Host "Querying knowledge sources..." -ForegroundColor Cyan

# Build source type OData filter
$sourceTypeFilter = switch ($SourceType) {
    'SharePoint'             { " and (fsi_sourcetype eq 1 or fsi_sourcetype eq 2 or fsi_sourcetype eq 3)" }
    'Dataverse'              { " and fsi_sourcetype eq 4" }
    'AzureBlob'              { " and (fsi_sourcetype eq 5 or fsi_sourcetype eq 6)" }
    'External'               { " and (fsi_sourcetype eq 7 or fsi_sourcetype eq 8 or fsi_sourcetype eq 9 or fsi_sourcetype eq 11 or fsi_sourcetype eq 12)" }
    'PublicWebsite'          { " and fsi_sourcetype eq 9" }
    'OneDrive'               { " and fsi_sourcetype eq 10" }
    'CopilotConnector'       { " and fsi_sourcetype eq 11" }
    'AzureAISearch'          { " and fsi_sourcetype eq 12" }
    'CopilotStudioDocument'  { " and fsi_sourcetype eq 13" }
    default                  { "" }
}

$sourceSelect = "fsi_knowledgesourceid,fsi_sourcename,fsi_sourcetype,fsi_sourceuri,fsi_agentid,fsi_description,fsi_currenthash,fsi_baselinehash,fsi_status,fsi_lastvalidated,fsi_validationfrequency,fsi_alertonchange,fsi_freshnessthreshold,fsi_lastmodified"
$sourceFilter = "fsi_status ne 5$sourceTypeFilter"  # Exclude archived
$sourceUri = "$DataverseUrl/api/data/v9.2/fsi_knowledgesources?`$select=$sourceSelect&`$filter=$sourceFilter"

$knowledgeSources = Invoke-DataverseQuery -Uri $sourceUri -Headers $headers
Write-Host "Retrieved $($knowledgeSources.Count) knowledge source records" -ForegroundColor Green

#endregion

#region Query Source Changes

Write-Host "Querying source changes..." -ForegroundColor Cyan

$changeFilter = "fsi_detectedon ge $fromDate"
$changeSelect = "fsi_sourcechangeid,fsi_changetype,fsi_detectedon,fsi_previousvalue,fsi_newvalue,fsi_changedby,fsi_reviewed,fsi_approved,createdon,_fsi_knowledgesourceid_value"
$changeUri = "$DataverseUrl/api/data/v9.2/fsi_sourcechanges?`$select=$changeSelect&`$filter=$changeFilter&`$orderby=fsi_detectedon desc"

$sourceChanges = Invoke-DataverseQuery -Uri $changeUri -Headers $headers
Write-Host "Retrieved $($sourceChanges.Count) source change records" -ForegroundColor Green
Write-Host ""

#endregion

#region Build Evidence JSON

Write-Host "Building evidence package..." -ForegroundColor Cyan

# Source type label mapping
$sourceTypeLabels = @{
    1 = "SharePoint Document Library"
    2 = "SharePoint List"
    3 = "SharePoint Page"
    4 = "Dataverse Table"
    5 = "Azure Blob Container"
    6 = "Azure Blob File"
    7 = "External API"
    8 = "Database Query"
    9 = "Public Website"
    10 = "OneDrive File or Folder"
    11 = "Microsoft 365 Copilot Connector External Item"
    12 = "Azure AI Search Index"
    13 = "Copilot Studio Uploaded Document"
}

$statusLabels = @{
    1 = "Active"
    2 = "Pending Validation"
    3 = "Validation Failed"
    4 = "Stale"
    5 = "Archived"
}

$resultLabels = @{
    1 = "Passed"
    2 = "Failed - Hash Mismatch"
    3 = "Failed - Schema Drift"
    4 = "Failed - Stale Content"
    5 = "Failed - Source Unavailable"
    6 = "Failed - Unexpected Error"
    7 = "Skipped - Not Implemented"
    8 = "Skipped - Unsupported Type"
}

# Convert sources to readable format
$sourcesReadable = $knowledgeSources | ForEach-Object {
    [PSCustomObject]@{
        knowledgeSourceId   = $_.fsi_knowledgesourceid
        name                = $_.fsi_sourcename
        sourceType          = $sourceTypeLabels[[int]$_.fsi_sourcetype]
        sourceTypeValue     = $_.fsi_sourcetype
        sourceUri           = $_.fsi_sourceuri
        agentId             = $_.fsi_agentid
        status              = $statusLabels[[int]$_.fsi_status]
        statusValue         = $_.fsi_status
        currentHash         = $_.fsi_currenthash
        baselineHash        = $_.fsi_baselinehash
        lastValidated       = $_.fsi_lastvalidated
        freshnessThreshold  = $_.fsi_freshnessthreshold
        lastModified        = $_.fsi_lastmodified
    }
}

# Convert validations to readable format
$validationsReadable = $validationResults | ForEach-Object {
    [PSCustomObject]@{
        validationResultId  = $_.fsi_validationresultid
        knowledgeSourceId   = $_._fsi_knowledgesourceid_value
        validationTime      = $_.fsi_validationtime
        result              = $resultLabels[[int]$_.fsi_result]
        resultValue         = $_.fsi_result
        previousHash        = $_.fsi_previoushash
        currentHash         = $_.fsi_currenthash
        hashChanged         = $_.fsi_hashchanged
        changeDetails       = $_.fsi_changedetails
        validationType      = $_.fsi_validationtype
        durationMs          = $_.fsi_duration
        errorDetails        = $_.fsi_errordetails
    }
}

# Convert changes to readable format
$changesReadable = $sourceChanges | ForEach-Object {
    [PSCustomObject]@{
        sourceChangeId      = $_.fsi_sourcechangeid
        knowledgeSourceId   = $_._fsi_knowledgesourceid_value
        changeType          = $_.fsi_changetype
        detectedOn          = $_.fsi_detectedon
        previousValue       = $_.fsi_previousvalue
        newValue            = $_.fsi_newvalue
        changedBy           = $_.fsi_changedby
        reviewed            = $_.fsi_reviewed
        approved            = $_.fsi_approved
    }
}

# Compute summary statistics
$totalSources = $sourcesReadable.Count
$activeSources = @($sourcesReadable | Where-Object { $_.statusValue -eq 1 }).Count
$failedSources = @($sourcesReadable | Where-Object { $_.statusValue -eq 3 }).Count
$staleSources = @($sourcesReadable | Where-Object { $_.statusValue -eq 4 }).Count

$totalValidations = $validationsReadable.Count
$passedValidations = @($validationsReadable | Where-Object { $_.resultValue -eq 1 }).Count
$failedValidations = @($validationsReadable | Where-Object { $_.resultValue -ge 2 -and $_.resultValue -le 6 }).Count
$hashMismatches = @($validationsReadable | Where-Object { $_.resultValue -eq 2 }).Count

$totalChanges = $changesReadable.Count
$unreviewedChanges = @($changesReadable | Where-Object { $_.reviewed -eq $false }).Count

# Determine overall status
$overallStatus = "Healthy"
if ($failedSources -gt 0 -or $hashMismatches -gt 0) {
    $overallStatus = "Critical"
}
elseif ($staleSources -gt 0 -or $unreviewedChanges -gt 0) {
    $overallStatus = "Warning"
}
elseif ($totalSources -eq 0) {
    $overallStatus = "NoData"
}

$exportTimestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# Build evidence object
$evidence = [PSCustomObject]@{
    metadata = [PSCustomObject]@{
        exportedAt      = $exportTimestamp
        solution        = "RAG Source Validator"
        solutionVersion = "1.3.1"
        daysBack        = $DaysBack
        fromDate        = $fromDate
        sourceTypeFilter = $SourceType
        exportVersion   = "1.0.0"
        sourceCount     = $totalSources
        validationCount = $totalValidations
        changeCount     = $totalChanges
        organizationUrl = $DataverseUrl
    }
    summary = [PSCustomObject]@{
        overallStatus       = $overallStatus
        totalSources        = $totalSources
        activeSources       = $activeSources
        failedSources       = $failedSources
        staleSources        = $staleSources
        totalValidations    = $totalValidations
        passedValidations   = $passedValidations
        failedValidations   = $failedValidations
        hashMismatches      = $hashMismatches
        totalChanges        = $totalChanges
        unreviewedChanges   = $unreviewedChanges
    }
    sources     = @($sourcesReadable)
    validations = @($validationsReadable)
    changes     = @($changesReadable)
}

#endregion

#region Write JSON Evidence File

$fileTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$fileName = "rsv-evidence-$fileTimestamp.json"
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
Write-Host ("║ Sources:        {0,-33}║" -f $totalSources) -ForegroundColor Cyan
Write-Host ("║ Validations:    {0,-33}║" -f $totalValidations) -ForegroundColor Cyan
Write-Host ("║ Changes:        {0,-33}║" -f $totalChanges) -ForegroundColor Cyan
Write-Host ("║ Overall Status: {0,-33}║" -f $overallStatus) -ForegroundColor Cyan
Write-Host ("║ SHA-256:        {0,-33}║" -f $hashValue.Substring(0, 33)) -ForegroundColor Cyan
Write-Host ("║                 {0,-33}║" -f $hashValue.Substring(33)) -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Evidence files ready for compliance verification." -ForegroundColor Green
Write-Host "Verify with: .\Test-EvidenceIntegrity.ps1 -EvidenceFilePath '$evidenceFilePath'" -ForegroundColor Gray
Write-Host ""

#endregion

#region Return Result Object

return [PSCustomObject]@{
    EvidenceFile    = $evidenceFilePath
    HashFile        = $hashFilePath
    SHA256          = $hashValue
    SourceCount     = $totalSources
    ValidationCount = $totalValidations
    ChangeCount     = $totalChanges
    GeneratedAt     = $exportTimestamp
}

#endregion
