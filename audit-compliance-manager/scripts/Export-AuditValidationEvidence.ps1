#Requires -Version 7.0

<#
.SYNOPSIS
    Exports audit validation evidence from Dataverse to JSON with SHA-256 integrity hashing.

.DESCRIPTION
    Produces machine-readable compliance evidence packages containing validation
    results, summary statistics, and cryptographic integrity verification.

    Each export generates:
    - JSON evidence file with metadata, summary, and complete validation results
    - SHA-256 hash companion file for integrity verification

    Evidence files support regulatory examination workflows (FINRA, SEC, GLBA)
    by providing tamper-evident exports with full validation history, timestamps,
    and audit trail metadata.

    This script supports FSI-AgentGov Control 1.7 evidence collection requirements
    (EVID-01, EVID-02, EVID-04).

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).

.PARAMETER TenantId
    Azure AD tenant ID. Required for authentication.

.PARAMETER Scope
    Evidence export scope: Tenant-level or Environment-level validations.

.PARAMETER OutputDirectory
    Directory path for evidence files. Created if it doesn't exist.

.PARAMETER RunId
    Optional GUID to export results from a specific validation run only.

.PARAMETER FromDate
    Start of date range filter (inclusive). Defaults to 30 days ago.

.PARAMETER ToDate
    End of date range filter (inclusive). Defaults to current timestamp.

.PARAMETER Interactive
    Use interactive browser-based authentication instead of service principal.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication.

.PARAMETER ClientId
    Azure AD application (client) ID for service principal authentication.

.EXAMPLE
    .\Export-AuditValidationEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -Scope "Tenant" `
        -OutputDirectory ".\evidence" `
        -Interactive

    Exports all tenant-level validation results from the past 30 days using
    interactive authentication. Generates JSON evidence file and SHA-256 hash.

.EXAMPLE
    .\Export-AuditValidationEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -Scope "Environment" `
        -OutputDirectory "C:\compliance\evidence" `
        -FromDate (Get-Date).AddDays(-90) `
        -ToDate (Get-Date) `
        -ClientId "12345..." `
        -CertificateThumbprint "ABCDEF..."

    Exports 90 days of environment-level validations using service principal
    authentication. Suitable for scheduled automation via Azure Automation.

.EXAMPLE
    .\Export-AuditValidationEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -Scope "Tenant" `
        -OutputDirectory ".\evidence" `
        -RunId "12345-guid" `
        -Interactive

    Exports results for a specific validation run only.

.OUTPUTS
    PSCustomObject with properties:
    - EvidenceFile: Full path to JSON evidence file
    - HashFile: Full path to SHA-256 companion file
    - SHA256: Hash value (64 hex characters)
    - RecordCount: Number of validation records in export
    - GeneratedAt: ISO 8601 timestamp of export generation

.NOTES
    Version: 1.0.0
    Requires:
    - PowerShell 7.0 or later
    - MSAL.PS module for Dataverse authentication
    - Dataverse schema deployed (fsi_auditvalidationhistories table)

    Evidence file naming convention:
    - {Scope}-validation-{yyyyMMdd-HHmmss}.json
    - Example: Tenant-validation-20260206-143022.json

    SHA-256 companion file format:
    - {hash}  {filename}  (two spaces, standard checksum format)
    - Verifiable via Test-EvidenceIntegrity or standard tools (shasum, certutil)

    JSON evidence schema:
    - metadata: Export context (timestamp, scope, date range, org URL, version)
    - summary: Aggregate statistics (overall status, pass/fail counts)
    - validations: Complete array of validation result objects

    Overall status computation uses severity priority:
    Error > Failed > GracePeriod > Warning > Passed
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Tenant", "Environment")]
    [string]$Scope,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $false)]
    [string]$RunId,

    [Parameter(Mandatory = $false)]
    [datetime]$FromDate = (Get-Date).AddDays(-30),

    [Parameter(Mandatory = $false)]
    [datetime]$ToDate = (Get-Date),

    [Parameter(Mandatory = $false)]
    [switch]$Interactive,

    [Parameter(Mandatory = $false)]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [string]$ClientId
)

$ErrorActionPreference = "Stop"

#region Initialization

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Audit Validation Evidence Export               ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  FSI-AgentGov Control 1.7 Evidence Collection   ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Dot-source required helper scripts
$scriptRoot = $PSScriptRoot
try {
    . "$scriptRoot/private/Connect-PowerPlatform.ps1"
    . "$scriptRoot/private/Get-ValidationResults.ps1"
}
catch {
    Write-Error "Failed to load helper scripts: $($_.Exception.Message)"
    throw
}

# Ensure output directory exists
if (-not (Test-Path -Path $OutputDirectory)) {
    Write-Host "Creating output directory: $OutputDirectory" -ForegroundColor Cyan
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

#endregion

#region Authentication

Write-Host "Authenticating to Dataverse..." -ForegroundColor Cyan

$authParams = @{
    TenantId     = $TenantId
    DataverseUrl = $DataverseUrl
}

if ($Interactive) {
    $authParams.Interactive = $true
}
else {
    if (-not $ClientId) {
        throw "ClientId is required for service principal authentication. Use -Interactive for browser-based auth."
    }
    if (-not $CertificateThumbprint) {
        throw "CertificateThumbprint is required for service principal authentication."
    }
    $authParams.ClientId = $ClientId
    $authParams.CertificateThumbprint = $CertificateThumbprint
}

try {
    $authResult = Connect-PowerPlatform @authParams

    if (-not $authResult.DataverseAccessToken) {
        throw "Failed to acquire Dataverse access token."
    }

    Write-Host "Authentication successful." -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Error "Authentication failed: $($_.Exception.Message)"
    throw
}

#endregion

#region Query Validation Results

Write-Host "Querying validation results..." -ForegroundColor Cyan
Write-Host "  Scope:      $Scope" -ForegroundColor Cyan
Write-Host "  From Date:  $($FromDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
Write-Host "  To Date:    $($ToDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
if ($RunId) {
    Write-Host "  Run ID:     $RunId" -ForegroundColor Cyan
}
Write-Host ""

$queryParams = @{
    DataverseUrl = $DataverseUrl
    AccessToken  = $authResult.DataverseAccessToken
    Scope        = $Scope
    FromDate     = $FromDate
    ToDate       = $ToDate
}

if ($RunId) {
    $queryParams.RunId = $RunId
}

try {
    $validations = Get-ValidationResults @queryParams

    Write-Host "Retrieved $($validations.Count) validation records" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Error "Failed to query validation results: $($_.Exception.Message)"
    throw
}

#endregion

#region Build Evidence JSON

Write-Host "Building evidence package..." -ForegroundColor Cyan

# Map option set numeric values back to string names for readability
$severityMap = @{
    100000000 = "Passed"
    100000001 = "Warning"
    100000002 = "GracePeriod"
    100000003 = "Failed"
    100000004 = "Error"
}

$scopeMap = @{
    100000000 = "Tenant"
    100000001 = "Environment"
}

$zoneMap = @{
    100000000 = "Unclassified"
    100000001 = "Zone1"
    100000002 = "Zone2"
    100000003 = "Zone3"
}

# Convert option set values to readable strings
$validationsReadable = $validations | ForEach-Object {
    [PSCustomObject]@{
        name             = $_.fsi_name
        runId            = $_.fsi_runid
        scope            = if ($scopeMap.ContainsKey($_.fsi_scope)) { $scopeMap[$_.fsi_scope] } else { $_.fsi_scope }
        environmentId    = $_.fsi_environmentid
        environmentName  = $_.fsi_environmentname
        zone             = if ($null -ne $_.fsi_zone -and $zoneMap.ContainsKey($_.fsi_zone)) { $zoneMap[$_.fsi_zone] } else { $_.fsi_zone }
        severity         = if ($severityMap.ContainsKey($_.fsi_severity)) { $severityMap[$_.fsi_severity] } else { $_.fsi_severity }
        validationType   = $_.fsi_validationtype
        rawValue         = $_.fsi_rawvalue
        reason           = $_.fsi_reason
        timestamp        = $_.fsi_timestamp
        remediationHint  = $_.fsi_remediationhint
        checkCount       = $_.fsi_checkcount
    }
}

# Compute summary statistics
$passedCount = ($validationsReadable | Where-Object { $_.severity -eq "Passed" }).Count
$failedCount = ($validationsReadable | Where-Object { $_.severity -in @("Failed", "Error") }).Count
$warningCount = ($validationsReadable | Where-Object { $_.severity -in @("Warning", "GracePeriod") }).Count

# Compute overall status using priority: Error > Failed > GracePeriod > Warning > Passed
$overallStatus = "Passed"
if ($validationsReadable.severity -contains "Error") {
    $overallStatus = "Error"
}
elseif ($validationsReadable.severity -contains "Failed") {
    $overallStatus = "Failed"
}
elseif ($validationsReadable.severity -contains "GracePeriod") {
    $overallStatus = "GracePeriod"
}
elseif ($validationsReadable.severity -contains "Warning") {
    $overallStatus = "Warning"
}

# Build metadata section
$exportTimestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$metadata = [PSCustomObject]@{
    exportedAt      = $exportTimestamp
    scope           = $Scope
    fromDate        = $FromDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    toDate          = $ToDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    runId           = if ($RunId) { $RunId } else { $null }
    exportVersion   = "1.0.0"
    recordCount     = $validationsReadable.Count
    organizationUrl = $DataverseUrl
}

# Build summary section
$summary = [PSCustomObject]@{
    overallStatus      = $overallStatus
    validationsRun     = $validationsReadable.Count
    validationsPassed  = $passedCount
    validationsFailed  = $failedCount
    validationsWarning = $warningCount
}

# Build complete evidence object
$evidence = [PSCustomObject]@{
    metadata    = $metadata
    summary     = $summary
    validations = $validationsReadable
}

#endregion

#region Write JSON Evidence File

# Generate filename with timestamp
$fileTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$fileName = "$Scope-validation-$fileTimestamp.json"
$evidenceFilePath = Join-Path -Path $OutputDirectory -ChildPath $fileName

Write-Host "Writing evidence file: $evidenceFilePath" -ForegroundColor Cyan

try {
    # CRITICAL: Use -Depth 10 to prevent nested object truncation
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
Write-Host ("║ Record Count:   {0,-33}║" -f $validationsReadable.Count) -ForegroundColor Cyan
Write-Host ("║ Overall Status: {0,-33}║" -f $overallStatus) -ForegroundColor Cyan
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
    RecordCount  = $validationsReadable.Count
    GeneratedAt  = $exportTimestamp
}

return $result

#endregion
