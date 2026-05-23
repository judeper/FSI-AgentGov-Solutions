#Requires -Version 7.4

<#
.SYNOPSIS
    Exports file upload compliance evidence from Dataverse for regulatory review.

.DESCRIPTION
    Queries Dataverse for file upload validation history, violations, and baselines,
    then packages results into a JSON evidence file with SHA-256 integrity hash.

    Supports SEC 17a-4(f) compliance by providing tamper-evident evidence packages
    with cryptographic integrity verification.

    IMPORTANT: The SHA-256 hash file provides integrity detection but does not offer
    tamper-proof protection. An actor with filesystem access can modify the evidence and regenerate
    the hash. For full SEC 17a-4(f) compliance, store evidence files on immutable/WORM
    storage or apply a detached CMS/PKCS#7 digital signature.

.PARAMETER TenantId
    Microsoft Entra ID tenant ID.

.PARAMETER ClientId
    Service principal application (client) ID.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication.

.PARAMETER DataverseUrl
    Dataverse environment URL.

.PARAMETER OutputPath
    Directory for evidence files. Default: current directory.

.PARAMETER Zone
    Filter to specific zone(s): Zone1, Zone2, Zone3.

.PARAMETER StartDate
    Start date for evidence range (inclusive).

.PARAMETER EndDate
    End date for evidence range (inclusive).

.PARAMETER RunId
    Filter to specific validation run ID.

.PARAMETER IncludeBaselines
    Include baseline records in evidence package.

.PARAMETER Interactive
    Use interactive browser authentication.

.EXAMPLE
    .\Export-FileUploadEvidence.ps1 -TenantId $tid -DataverseUrl $url -Interactive
    Export all evidence interactively.

.EXAMPLE
    .\Export-FileUploadEvidence.ps1 -TenantId $tid -DataverseUrl $url -StartDate "2026-01-01" -EndDate "2026-03-31"
    Export evidence for Q1 2026.

.NOTES
    Part of FSI Agent Governance Framework - File Upload Security Configurator
    Control: 1.14 - Data Minimization and Agent Scope Control
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter()]
    [string]$ClientId,

    [Parameter()]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory)]
    [string]$DataverseUrl,

    [Parameter()]
    [string]$OutputPath = '.',

    [Parameter()]
    [ValidateSet('Zone1', 'Zone2', 'Zone3')]
    [string[]]$Zone,

    [Parameter()]
    [datetime]$StartDate,

    [Parameter()]
    [datetime]$EndDate,

    [Parameter()]
    [string]$RunId,

    [switch]$IncludeBaselines,

    [switch]$Interactive
)

$ErrorActionPreference = 'Stop'

# ── Load Dependencies ─────────────────────────────────────────────
$scriptRoot = $PSScriptRoot

Import-Module MSAL.PS -ErrorAction Stop
Import-Module (Join-Path $scriptRoot 'private' 'FUSClient.psm1') -Force

# ── Authenticate ──────────────────────────────────────────────────
try {

Write-Host 'Authenticating to Dataverse...' -ForegroundColor Cyan

$dataverseScope = "$($DataverseUrl.TrimEnd('/'))/.default"

if ($Interactive) {
    if (-not $ClientId) {
        throw 'ClientId is required for interactive authentication. Provide via -ClientId parameter.'
    }
    $tokenResult = Get-MsalToken `
        -ClientId $ClientId `
        -TenantId $TenantId `
        -Scopes $dataverseScope `
        -Interactive `
        -ErrorAction Stop
} else {
    if (-not $CertificateThumbprint) {
        throw 'CertificateThumbprint required for non-interactive auth. Use -Interactive for browser auth.'
    }
    $cert = Get-Item "Cert:\CurrentUser\My\$CertificateThumbprint" -ErrorAction Stop
    $tokenResult = Get-MsalToken `
        -ClientId $ClientId `
        -ClientCertificate $cert `
        -TenantId $TenantId `
        -Scopes $dataverseScope `
        -ErrorAction Stop
}

Connect-FUSDataverse -DataverseUrl $DataverseUrl -AccessToken $tokenResult.AccessToken

Write-Host '  Connected.' -ForegroundColor Green

# ── Build OData Filters ──────────────────────────────────────────
$filters = @()

if ($StartDate) {
    $filters += "fsi_validationtime ge $($StartDate.ToUniversalTime().ToString('o'))"
}
if ($EndDate) {
    $filters += "fsi_validationtime le $($EndDate.ToUniversalTime().ToString('o'))"
}
if ($RunId) {
    $safeRunId = $RunId -replace "'", "''"
    $filters += "fsi_runid eq '$safeRunId'"
}

$filterString = if ($filters.Count -gt 0) { $filters -join ' and ' } else { '' }

# ── Query Validation History ─────────────────────────────────────
Write-Host 'Querying validation history...' -ForegroundColor Cyan

$connection = Get-FUSConnection
$headers = @{
    'Authorization' = "Bearer $($connection.AccessToken)"
    'Content-Type'  = 'application/json'
    'Accept'        = 'application/json'
    'OData-MaxVersion' = '4.0'
    'OData-Version' = '4.0'
}

$baseUrl = "$($connection.DataverseUrl)/api/data/v9.2"

$historyUrl = "$baseUrl/fsi_fileuploadvalidationhistories"
if ($filterString) {
    $historyUrl += "?`$filter=$filterString"
}

$historyRecords = @()
$nextLink = $historyUrl

while ($nextLink) {
    $historyResponse = Invoke-DataverseRequest -Uri $nextLink -Headers $headers -Method Get
    $historyRecords += $historyResponse.value
    $nextLink = $historyResponse.'@odata.nextLink'
}
$validations = $historyRecords
Write-Host "  Found $($validations.Count) validation record(s)." -ForegroundColor Green

# ── Query Violations ─────────────────────────────────────────────
Write-Host 'Querying violations...' -ForegroundColor Cyan

$violationFilters = @()
if ($StartDate) {
    $violationFilters += "fsi_detectedon ge $($StartDate.ToUniversalTime().ToString('o'))"
}
if ($EndDate) {
    $violationFilters += "fsi_detectedon le $($EndDate.ToUniversalTime().ToString('o'))"
}
if ($RunId) {
    $safeRunId = $RunId -replace "'", "''"
    $violationFilters += "fsi_runid eq '$safeRunId'"
}

$violationFilterString = if ($violationFilters.Count -gt 0) { $violationFilters -join ' and ' } else { '' }

$violationUrl = "$baseUrl/fsi_fileuploadviolations"
if ($violationFilterString) {
    $violationUrl += "?`$filter=$violationFilterString"
}

$violationRecords = @()
$nextViolationLink = $violationUrl

while ($nextViolationLink) {
    $violationResponse = Invoke-DataverseRequest -Uri $nextViolationLink -Headers $headers -Method Get
    $violationRecords += $violationResponse.value
    $nextViolationLink = $violationResponse.'@odata.nextLink'
}
$violations = $violationRecords
Write-Host "  Found $($violations.Count) violation(s)." -ForegroundColor Green

# ── Query Baselines (Optional) ───────────────────────────────────
$baselines = @()
if ($IncludeBaselines) {
    Write-Host 'Querying baselines...' -ForegroundColor Cyan
    $baselineUrl = "$baseUrl/fsi_fileuploadbaselines"
    $baselineRecords = @()
    $nextBaselineLink = $baselineUrl

    while ($nextBaselineLink) {
        $baselineResponse = Invoke-DataverseRequest -Uri $nextBaselineLink -Headers $headers -Method Get
        $baselineRecords += $baselineResponse.value
        $nextBaselineLink = $baselineResponse.'@odata.nextLink'
    }
    $baselines = $baselineRecords
    Write-Host "  Found $($baselines.Count) baseline(s)." -ForegroundColor Green
}

# ── Apply Zone Filter ────────────────────────────────────────────
if ($Zone) {
    $zoneMap = @{ 'Zone1' = 100000000; 'Zone2' = 100000001; 'Zone3' = 100000002 }
    $zoneValues = $Zone | ForEach-Object { $zoneMap[$_] }
    $violations = $violations | Where-Object { $_.fsi_zone -in $zoneValues }
    if ($IncludeBaselines) {
        $baselines = $baselines | Where-Object { $_.fsi_zone -in $zoneValues }
    }
}

# ── Build Evidence Package ───────────────────────────────────────
Write-Host 'Building evidence package...' -ForegroundColor Cyan

$timestamp = Get-Date -AsUTC -Format 'o'
$evidenceId = [guid]::NewGuid().ToString()

$evidencePackage = [ordered]@{
    metadata = [ordered]@{
        evidenceId     = $evidenceId
        generatedAt    = $timestamp
        generatedBy    = $env:USERNAME
        solution       = 'File Upload Security Configurator'
        solutionVersion = '1.1.2'
        control        = '1.14 - Data Minimization and Agent Scope Control'
        framework      = 'FSI Agent Governance Framework'
        tenantId       = $TenantId
        dataverseUrl   = $DataverseUrl
        filters        = [ordered]@{
            zone      = if ($Zone) { $Zone -join ', ' } else { 'All' }
            startDate = if ($StartDate) { $StartDate.ToString('o') } else { $null }
            endDate   = if ($EndDate) { $EndDate.ToString('o') } else { $null }
            runId     = $RunId
        }
    }
    summary = [ordered]@{
        validationCount  = $validations.Count
        violationCount   = $violations.Count
        baselineCount    = $baselines.Count
        dateRange        = [ordered]@{
            earliest = ($validations | Sort-Object fsi_validationtime | Select-Object -First 1).fsi_validationtime
            latest   = ($validations | Sort-Object fsi_validationtime -Descending | Select-Object -First 1).fsi_validationtime
        }
    }
    validations = $validations
    violations  = $violations
    baselines   = $baselines
}

# ── Write Evidence File ──────────────────────────────────────────
$fileName = "FUS-Evidence-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$($evidenceId.Substring(0,8)).json"
$filePath = Join-Path $OutputPath $fileName

if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$json = $evidencePackage | ConvertTo-Json -Depth 20
$json | Out-File -FilePath $filePath -Encoding utf8NoBOM

# ── Generate SHA-256 Hash ────────────────────────────────────────
$hashValue = (Get-FileHash -Path $filePath -Algorithm SHA256).Hash
$hashFile = "$filePath.sha256"
"$hashValue  $fileName" | Out-File -FilePath $hashFile -Encoding utf8NoBOM

# ── Output Summary ───────────────────────────────────────────────
$summary = @"

╔══════════════════════════════════════════════════════════════╗
║  Evidence Export Complete                                     ║
╠══════════════════════════════════════════════════════════════╣
║  Evidence File: $fileName
║  Hash File:     $($fileName).sha256
║  SHA-256:       $hashValue
║  Records:       $($validations.Count) validations, $($violations.Count) violations, $($baselines.Count) baselines
║  Generated:     $timestamp
╚══════════════════════════════════════════════════════════════╝
"@
Write-Host $summary -ForegroundColor Cyan

# Return result for pipeline use
[PSCustomObject]@{
    EvidenceFile   = $filePath
    HashFile       = $hashFile
    SHA256         = $hashValue
    RecordCount    = $validations.Count
    ViolationCount = $violations.Count
    BaselineCount  = $baselines.Count
    GeneratedAt    = $timestamp
}

} catch {
    Write-Host "`nERROR: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "  At: $($_.InvocationInfo.ScriptName):$($_.InvocationInfo.ScriptLineNumber)" -ForegroundColor Red
    throw
}
