#Requires -Version 7.0

<#
.SYNOPSIS
    Exports session security validation evidence from Dataverse to JSON with SHA-256 integrity hashing.

.DESCRIPTION
    Produces machine-readable compliance evidence packages containing session security
    validation results, summary statistics, and cryptographic integrity verification.

    Each export generates:
    - JSON evidence file with metadata, summary, and complete validation results
    - SHA-256 hash companion file for integrity verification

    Evidence files support regulatory examination workflows (FINRA, SEC, GLBA)
    by providing tamper-evident exports with full validation history, timestamps,
    and audit trail metadata.

    This script supports FSI-AgentGov Control 1.23 evidence collection requirements
    for session security and step-up authentication compliance.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com). Required.

.PARAMETER TenantId
    Azure AD tenant ID. Required for authentication.

.PARAMETER Zone
    Governance zone filter. Valid values: 'All', '1', '2', '3'. Defaults to 'All'.
    - Zone 1 (Personal Productivity): 8-hour sign-in frequency, standard MFA
    - Zone 2 (Team Collaboration): 4-hour sign-in frequency, passwordless MFA
    - Zone 3 (Enterprise Managed): 1-hour sign-in frequency, phishing-resistant MFA

.PARAMETER OutputDirectory
    Directory path for evidence files. Created if it doesn't exist. Required.

.PARAMETER FromDate
    Start of date range filter (inclusive). Defaults to 30 days ago.

.PARAMETER ToDate
    End of date range filter (inclusive). Defaults to current timestamp.

.PARAMETER RunId
    Optional string to export results from a specific validation run only.

.PARAMETER Interactive
    Use interactive browser-based authentication instead of service principal.

.PARAMETER ClientId
    Azure AD application (client) ID for service principal authentication.

.PARAMETER ClientSecret
    Client secret for service principal authentication. Must be a SecureString.

.EXAMPLE
    .\Export-SessionSecurityEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -Zone "All" `
        -OutputDirectory ".\evidence" `
        -Interactive

    Exports all session security validation results from the past 30 days using
    interactive authentication. Generates JSON evidence file and SHA-256 hash.

.EXAMPLE
    .\Export-SessionSecurityEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -Zone "3" `
        -OutputDirectory "C:\compliance\evidence" `
        -FromDate (Get-Date).AddDays(-90) `
        -ToDate (Get-Date) `
        -Interactive

    Exports 90 days of Zone 3 (Enterprise Managed) validation results.
    Suitable for quarterly compliance reviews.

.EXAMPLE
    $secret = ConvertTo-SecureString "client-secret" -AsPlainText -Force
    .\Export-SessionSecurityEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -Zone "All" `
        -OutputDirectory ".\evidence" `
        -ClientId "12345-guid" `
        -ClientSecret $secret

    Exports evidence using service principal authentication.
    Suitable for scheduled automation via Azure Automation.

.EXAMPLE
    .\Export-SessionSecurityEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -Zone "2" `
        -OutputDirectory ".\evidence" `
        -RunId "run-20260209-143022" `
        -Interactive

    Exports results for a specific validation run in Zone 2 only.

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
    - MSAL.PS module for Dataverse authentication (or pre-acquired token)
    - Dataverse schema deployed (fsi_validationhistories table)

    Evidence file naming convention:
    - session-security-evidence-{zone}-{yyyyMMdd-HHmmss}.json
    - Example: session-security-evidence-Zone3-20260209-143022.json

    SHA-256 companion file format:
    - {hash}  {filename}  (two spaces, standard checksum format)
    - Verifiable via Test-EvidenceIntegrity or standard tools (shasum, certutil)

    JSON evidence schema:
    - metadata: Export context (timestamp, zone, date range, org URL, version)
    - summary: Aggregate statistics (overall status, pass/fail counts)
    - validations: Complete array of validation result objects

    Overall status computation uses severity priority:
    Error > Failed > GracePeriod > Warning > Passed

    Regulatory context:
    This evidence export supports compliance requirements for:
    - FINRA Rule 4511 (Authorized Access to Financial Records)
    - SEC Rule 17a-4 (Record Integrity)
    - GLBA 501(b) (User Identity Verification)
    - SOX 302/404 (Transaction-Level Authentication Controls)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [ValidateSet("All", "1", "2", "3")]
    [string]$Zone = "All",

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $false)]
    [datetime]$FromDate = (Get-Date).AddDays(-30),

    [Parameter(Mandatory = $false)]
    [datetime]$ToDate = (Get-Date),

    [Parameter(Mandatory = $false)]
    [string]$RunId,

    [Parameter(Mandatory = $false)]
    [switch]$Interactive,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [SecureString]$ClientSecret
)

$ErrorActionPreference = "Stop"

#region Initialization

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Session Security Evidence Export               ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  FSI-AgentGov Control 1.23 Evidence Collection  ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Dot-source required helper scripts
$scriptRoot = $PSScriptRoot
try {
    . "$scriptRoot/private/Get-SSCValidationResults.ps1"
    Write-Verbose "Loaded Get-SSCValidationResults helper."
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

$accessToken = $null

if ($Interactive) {
    # Interactive browser-based authentication
    try {
        # Attempt to use MSAL.PS if available
        if (Get-Module -ListAvailable -Name MSAL.PS) {
            Import-Module MSAL.PS -ErrorAction Stop

            $msalParams = @{
                ClientId    = $ClientId
                TenantId    = $TenantId
                Scopes      = @("$DataverseUrl/.default")
                Interactive = $true
            }

            $authResult = Get-MsalToken @msalParams
            $accessToken = $authResult.AccessToken
            Write-Host "Interactive authentication successful." -ForegroundColor Green
        }
        else {
            # Fallback: Attempt to use existing Graph context
            Write-Warning "MSAL.PS module not found. Attempting to use existing authentication context."
            $context = Get-MgContext -ErrorAction SilentlyContinue
            if ($context -and $context.AccessToken) {
                $accessToken = $context.AccessToken
                Write-Host "Using existing authentication context." -ForegroundColor Green
            }
            else {
                throw "No authentication context available. Install MSAL.PS module: Install-Module MSAL.PS -Scope CurrentUser"
            }
        }
    }
    catch {
        Write-Error "Interactive authentication failed: $($_.Exception.Message)"
        throw
    }
}
else {
    # Service principal authentication with client secret
    if (-not $ClientId) {
        throw "ClientId is required for service principal authentication. Use -Interactive for browser-based auth."
    }
    if (-not $ClientSecret) {
        throw "ClientSecret is required for service principal authentication."
    }

    try {
        if (Get-Module -ListAvailable -Name MSAL.PS) {
            Import-Module MSAL.PS -ErrorAction Stop

            $msalParams = @{
                TenantId     = $TenantId
                ClientId     = $ClientId
                ClientSecret = $ClientSecret
                Scopes       = @("$DataverseUrl/.default")
            }

            $authResult = Get-MsalToken @msalParams
            $accessToken = $authResult.AccessToken
            Write-Host "Service principal authentication successful." -ForegroundColor Green
        }
        else {
            throw "MSAL.PS module required for service principal authentication. Install: Install-Module MSAL.PS -Scope CurrentUser"
        }
    }
    catch {
        Write-Error "Service principal authentication failed: $($_.Exception.Message)"
        throw
    }
}

if (-not $accessToken) {
    throw "Failed to acquire Dataverse access token."
}

Write-Host ""

#endregion

#region Query Validation Results

Write-Host "Querying validation results..." -ForegroundColor Cyan
Write-Host "  Zone:       $Zone" -ForegroundColor Cyan
Write-Host "  From Date:  $($FromDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
Write-Host "  To Date:    $($ToDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
if ($RunId) {
    Write-Host "  Run ID:     $RunId" -ForegroundColor Cyan
}
Write-Host ""

$queryParams = @{
    DataverseUrl = $DataverseUrl
    AccessToken  = $accessToken
    Zone         = $Zone
    FromDate     = $FromDate
    ToDate       = $ToDate
}

if ($RunId) {
    $queryParams.RunId = $RunId
}

try {
    $validations = Get-SSCValidationResults @queryParams

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

# Option set mappings for readable output
$severityMap = @{
    1 = "Passed"
    2 = "Warning"
    3 = "GracePeriod"
    4 = "Failed"
    5 = "Error"
}

$zoneMap = @{
    100000001 = "Zone1"
    100000002 = "Zone2"
    100000003 = "Zone3"
}

$validationTypeMap = @{
    1 = "SessionControls"
    2 = "AuthStrength"
    3 = "PIMSettings"
    4 = "BreakGlass"
    5 = "ConflictAudit"
    6 = "Orchestrator"
}

# Convert option set values to readable strings
$validationsReadable = $validations | ForEach-Object {
    [PSCustomObject]@{
        name              = $_.fsi_name
        runId             = $_.fsi_runid
        zone              = if ($_.fsi_zone -ne $null -and $zoneMap.ContainsKey($_.fsi_zone)) { $zoneMap[$_.fsi_zone] } else { $_.fsi_zone }
        severity          = if ($_.fsi_severity -ne $null -and $severityMap.ContainsKey($_.fsi_severity)) { $severityMap[$_.fsi_severity] } else { $_.fsi_severity }
        validationType    = if ($_.fsi_validationtype -ne $null -and $validationTypeMap.ContainsKey($_.fsi_validationtype)) { $validationTypeMap[$_.fsi_validationtype] } else { $_.fsi_validationtype }
        rawValue          = $_.fsi_rawvalue
        reason            = $_.fsi_reason
        remediationHint   = $_.fsi_remediationhint
        timestamp         = $_.fsi_timestamp
        checkCount        = $_.fsi_checkcount
        baselineId        = $_.fsi_baselineid
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

# Determine zone display name
$zoneDisplayName = switch ($Zone) {
    "1" { "Zone1" }
    "2" { "Zone2" }
    "3" { "Zone3" }
    default { "All" }
}

# Build metadata section
$exportTimestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$metadata = [PSCustomObject]@{
    exportedAt      = $exportTimestamp
    scope           = "SessionSecurity"
    zone            = $zoneDisplayName
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

# Generate filename with timestamp and zone
$fileTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$fileName = "session-security-evidence-$zoneDisplayName-$fileTimestamp.json"
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
