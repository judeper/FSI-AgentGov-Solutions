#Requires -Version 7.0

<#
.SYNOPSIS
    Exports action confirmation compliance evidence from Dataverse to JSON
    with SHA-256 integrity hashing.

.DESCRIPTION
    Produces machine-readable compliance evidence packages containing validation
    results, violation details, optional exception records, and cryptographic
    integrity verification for the Action Confirmation Auditor (ACA) solution.

    Each export generates:
    - JSON evidence file with metadata, summary, validations, violations,
      and exceptions
    - SHA-256 hash companion file for integrity verification

    Evidence files support regulatory examination workflows (FINRA, SEC, GLBA)
    by providing tamper-evident exports with full validation history, timestamps,
    and audit trail metadata.

    ACA operates at the action level within agents: violation records include
    per-action detail (fsi_actionname, fsi_actiontype, fsi_confirmationstatus)
    for action confirmation governance. This script supports FSI-AgentGov
    Control 1.23 (Step-Up Authentication for Agent Operations) evidence
    collection requirements.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).

.PARAMETER TenantId
    Microsoft Entra ID tenant ID. Required for authentication.

.PARAMETER OutputDirectory
    Directory path for evidence files. Created if it does not exist.

.PARAMETER Zone
    Optional zone filter for violation records: All, 1, 2, or 3.
    Validation history is always included regardless of zone filter.
    Default: All.

.PARAMETER RunId
    Optional GUID to export results from a specific validation run only.

.PARAMETER FromDate
    Start of date range filter (inclusive). Defaults to 30 days ago.

.PARAMETER ToDate
    End of date range filter (inclusive). Defaults to current timestamp.

.PARAMETER IncludeExceptions
    When specified, includes active action confirmation exception records from
    fsi_actionconfirmationexceptions in the evidence export.

.PARAMETER Interactive
    Use interactive browser-based authentication instead of service principal.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication.

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID for service principal authentication.

.EXAMPLE
    .\Export-ActionAuditEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -OutputDirectory ".\evidence" `
        -Interactive

    Exports all validation results and violations from the past 30 days using
    interactive authentication. Generates JSON evidence file and SHA-256 hash.

.EXAMPLE
    .\Export-ActionAuditEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -OutputDirectory "C:\compliance\evidence" `
        -Zone "3" `
        -IncludeExceptions `
        -FromDate (Get-Date).AddDays(-90) `
        -ToDate (Get-Date) `
        -ClientId "12345..." `
        -CertificateThumbprint "ABCDEF..."

    Exports 90 days of Zone 3 violations with exceptions using service principal
    authentication.

.EXAMPLE
    .\Export-ActionAuditEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -OutputDirectory ".\evidence" `
        -RunId "a1b2c3d4-e5f6-7890-abcd-ef1234567890" `
        -IncludeExceptions `
        -Interactive

    Exports results for a specific validation run with exceptions included.

.OUTPUTS
    PSCustomObject with properties:
    - EvidenceFile: Full path to JSON evidence file
    - HashFile: Full path to SHA-256 companion file
    - SHA256: Hash value (64 hex characters)
    - RecordCount: Number of validation records in export
    - ViolationCount: Number of violation records in export
    - GeneratedAt: ISO 8601 timestamp of export generation

.NOTES
    Version: 1.0.0
    Solution: Action Confirmation Auditor (ACA)
    Control: 1.23 (Step-Up Authentication for Agent Operations)
    Requires:
    - PowerShell 7.0 or later
    - MSAL.PS module for Dataverse authentication
    - ACA Dataverse schema deployed (fsi_actionscanrun,
      fsi_actionauditresults, fsi_actionconfirmationexceptions tables)

    Evidence file naming convention:
    - aca-evidence-{zone}-{yyyyMMdd-HHmmss}.json
    - Example: aca-evidence-All-20260210-143022.json

    SHA-256 companion file format:
    - {hash}  {filename}  (two spaces, standard checksum format)
    - Verifiable via Test-EvidenceIntegrity or standard tools (shasum, certutil)

    JSON evidence schema:
    - metadata: Export context (timestamp, solution, date range, org URL, version)
    - summary: Aggregate statistics (overall status, scan/violation counts, action metrics)
    - validations: Complete array of validation history records
    - violations: Complete array of per-action confirmation violation records
    - exceptions: Active action confirmation exceptions (if -IncludeExceptions specified)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$OutputDirectory,

    [Parameter(Mandatory = $false)]
    [ValidateSet('All', '1', '2', '3')]
    [string]$Zone = 'All',

    [Parameter(Mandatory = $false)]
    [string]$RunId,

    [Parameter(Mandatory = $false)]
    [datetime]$FromDate = (Get-Date).AddDays(-30),

    [Parameter(Mandatory = $false)]
    [datetime]$ToDate = (Get-Date),

    [Parameter(Mandatory = $false)]
    [switch]$IncludeExceptions,

    [Parameter(Mandatory = $false)]
    [switch]$Interactive,

    [Parameter(Mandatory = $false)]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [string]$ClientId
)

$ErrorActionPreference = "Stop"

#region Initialization

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Action Confirmation Evidence Export" -ForegroundColor Cyan
Write-Host "  FSI-AgentGov ACA Solution" -ForegroundColor Cyan
Write-Host "  Control 1.23 - Step-Up Authentication" -ForegroundColor Gray
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Import ACAClient module for Dataverse operations
$scriptRoot = $PSScriptRoot
try {
    Import-Module "$scriptRoot/private/ACAClient.psm1" -Force
}
catch {
    Write-Error "Failed to load required modules: $($_.Exception.Message)"
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

$dataverseScope = "$($DataverseUrl.TrimEnd('/'))/.default"

if ($Interactive) {
    # Interactive browser-based authentication via MSAL.PS
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
    # Service principal authentication with certificate
    if (-not $ClientId) {
        throw "ClientId is required for service principal authentication. Use -Interactive for browser-based auth."
    }
    if (-not $CertificateThumbprint) {
        throw "CertificateThumbprint is required for service principal authentication."
    }

    try {
        if (-not (Get-Module -ListAvailable -Name MSAL.PS)) {
            throw "MSAL.PS module is required for authentication. Install with: Install-Module MSAL.PS -Scope CurrentUser"
        }
        Import-Module MSAL.PS -ErrorAction Stop

        $authResult = Get-MsalToken `
            -TenantId $TenantId `
            -ClientId $ClientId `
            -ClientCertificate (Get-Item "Cert:\CurrentUser\My\$CertificateThumbprint") `
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

# Connect ACAClient module
Connect-ACADataverse -DataverseUrl $DataverseUrl -AccessToken $accessToken

#endregion

#region Query Validation Results

Write-Host "Querying validation results..." -ForegroundColor Cyan
Write-Host "  Zone Filter:  $Zone" -ForegroundColor Cyan
Write-Host "  From Date:    $($FromDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
Write-Host "  To Date:      $($ToDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
if ($RunId) {
    Write-Host "  Run ID:       $RunId" -ForegroundColor Cyan
}
Write-Host ""

$baseUrl = $DataverseUrl.TrimEnd('/')
$headers = @{
    'Authorization'    = "Bearer $accessToken"
    'Accept'           = 'application/json'
    'OData-MaxVersion' = '4.0'
    'OData-Version'    = '4.0'
    'Prefer'           = 'odata.include-annotations=*'
}

# Query validation history from fsi_actionscanrun
$fromDateStr = $FromDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$toDateStr = $ToDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

$validationFilter = "fsi_validationtime ge $fromDateStr and fsi_validationtime le $toDateStr"
if ($RunId) {
    $validationFilter += " and fsi_runid eq '$RunId'"
}

try {
    $validationUri = "$baseUrl/api/data/v9.2/fsi_actionscanrun?`$filter=$validationFilter&`$orderby=fsi_validationtime desc"
    $validationResponse = Invoke-RestMethod -Uri $validationUri -Method Get -Headers $headers -ErrorAction Stop
    $validations = if ($validationResponse.value) { $validationResponse.value } else { @() }
    Write-Host "Retrieved $($validations.Count) validation records" -ForegroundColor Green
} catch {
    Write-Error "Failed to query validation results: $($_.Exception.Message)"
    throw
}

# Query violation records from fsi_actionauditresults
$violationFilter = "fsi_detectedat ge $fromDateStr and fsi_detectedat le $toDateStr"
if ($RunId) {
    $violationFilter += " and fsi_runid eq '$RunId'"
}
if ($Zone -ne 'All') {
    $violationFilter += " and fsi_zone eq 'Zone$Zone'"
}

try {
    $violationUri = "$baseUrl/api/data/v9.2/fsi_actionauditresults?`$filter=$violationFilter&`$orderby=fsi_detectedat desc"
    $violationResponse = Invoke-RestMethod -Uri $violationUri -Method Get -Headers $headers -ErrorAction Stop
    $violations = if ($violationResponse.value) { $violationResponse.value } else { @() }
    Write-Host "Retrieved $($violations.Count) violation records" -ForegroundColor Green
    Write-Host ""
} catch {
    Write-Error "Failed to query violation results: $($_.Exception.Message)"
    throw
}

#endregion

#region Query Exceptions (optional)

$exceptionRecords = @()

if ($IncludeExceptions) {
    Write-Host "Querying active action confirmation exceptions..." -ForegroundColor Cyan

    try {
        $exceptionUri = "$baseUrl/api/data/v9.2/fsi_actionconfirmationexceptions?`$filter=fsi_isactive eq true"
        $exceptionResponse = Invoke-RestMethod -Uri $exceptionUri -Method Get -Headers $headers -ErrorAction Stop
        if ($exceptionResponse.value) {
            $exceptionRecords = @($exceptionResponse.value)
        }
        Write-Host "Retrieved $($exceptionRecords.Count) active exception records" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Warning "Failed to query exceptions: $($_.Exception.Message)"
        Write-Host "Continuing without exception data." -ForegroundColor Yellow
        Write-Host ""
    }
}

#endregion

#region Build Evidence JSON

Write-Host "Building evidence package..." -ForegroundColor Cyan

# Convert validation history records to readable format
$validationsReadable = $validations | ForEach-Object {
    [PSCustomObject]@{
        name                 = $_.fsi_name
        runId                = $_.fsi_runid
        scanTime             = $_.fsi_validationtime
        totalAgents          = $_.fsi_totalagents
        totalActions         = $_.fsi_totalactions
        compliantCount       = $_.fsi_compliantcount
        violationCount       = $_.fsi_violationcount
        overallStatus        = $_.fsi_overallstatus
        environmentsScanned  = $_.fsi_environmentsscanned
        summaryJson          = $_.fsi_summaryjson
    }
}

# Convert violation records to readable format (action-level detail for ACA)
$violationsReadable = $violations | ForEach-Object {
    [PSCustomObject]@{
        name               = $_.fsi_name
        environmentGuid    = $_.fsi_environmentguid
        environmentName    = $_.fsi_environmentname
        agentId            = $_.fsi_agentid
        agentName          = $_.fsi_agentname
        zone               = $_.fsi_zone
        actionName         = $_.fsi_actionname
        actionType         = $_.fsi_actiontype
        actionCategory     = $_.fsi_violationtype  # Action category derived from violation type
        connectorName      = $_.fsi_connectorname
        confirmationStatus = $_.fsi_confirmationstatus
        violationType      = $_.fsi_violationtype
        severity           = $_.fsi_severity
        topicName          = $_.fsi_topicname
        regulatoryContext   = $_.fsi_regulatorycontext
        detectedAt         = $_.fsi_detectedat
        runId              = $_.fsi_runid
    }
}

# Convert exception records to readable format (if included)
$exceptionsReadable = @()
if ($IncludeExceptions -and $exceptionRecords.Count -gt 0) {
    $exceptionsReadable = $exceptionRecords | ForEach-Object {
        [PSCustomObject]@{
            agentId            = $_.fsi_agentid
            agentName          = $_.fsi_agentname
            actionName         = $_.fsi_actionname
            actionType         = $_.fsi_actiontype
            zone               = $_.fsi_zone
            reason             = $_.fsi_justification
            approvedBy         = $_.fsi_approvedby
            approvedAt         = $_.fsi_approvedat
            expiresAt          = $_.fsi_expiresat
            isActive           = $_.fsi_isactive
        }
    }
}

# Compute summary statistics
$totalScans = $validationsReadable.Count
$scansCompliant = ($validationsReadable | Where-Object { $_.overallStatus -eq 'Compliant' -or $_.overallStatus -eq 'Passed' }).Count
$scansWithViolations = ($validationsReadable | Where-Object { $_.violationCount -gt 0 }).Count
$totalViolations = $violationsReadable.Count

# Agent-level and action-level metrics from validation history
$totalAgents = 0
$totalActions = 0
if ($validationsReadable.Count -gt 0) {
    $latestScan = $validationsReadable | Select-Object -First 1
    $totalAgents = if ($latestScan.totalAgents) { $latestScan.totalAgents } else { 0 }
    $totalActions = if ($latestScan.totalActions) { $latestScan.totalActions } else { 0 }
}

# Violation severity breakdown
$criticalViolations = ($violationsReadable | Where-Object { $_.severity -eq 'Critical' }).Count
$highViolations = ($violationsReadable | Where-Object { $_.severity -eq 'High' }).Count
$mediumViolations = ($violationsReadable | Where-Object { $_.severity -eq 'Medium' }).Count
$warningViolations = ($violationsReadable | Where-Object { $_.severity -eq 'Warning' }).Count

# Violation type breakdown
$violationTypes = @{}
foreach ($v in $violationsReadable) {
    if ($v.violationType) {
        if (-not $violationTypes.ContainsKey($v.violationType)) {
            $violationTypes[$v.violationType] = 0
        }
        $violationTypes[$v.violationType]++
    }
}

# Compute overall status (worst-case across all scans)
$overallStatus = "Compliant"
$statusValues = $validationsReadable | Select-Object -ExpandProperty overallStatus -ErrorAction SilentlyContinue
if ($statusValues -contains "Critical") {
    $overallStatus = "Critical"
}
elseif ($statusValues -contains "NonCompliant" -or $statusValues -contains "Failed") {
    $overallStatus = "NonCompliant"
}
elseif ($statusValues -contains "Warning" -or $statusValues -contains "Review") {
    $overallStatus = "Warning"
}
elseif ($totalScans -eq 0) {
    $overallStatus = "NoData"
}

# Build metadata section
$exportTimestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$metadata = [PSCustomObject]@{
    exportedAt      = $exportTimestamp
    solution        = "Action Confirmation Auditor"
    solutionVersion = "1.0.0"
    control         = "1.23"
    fromDate        = $FromDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    toDate          = $ToDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    runId           = if ($RunId) { $RunId } else { $null }
    zoneFilter      = $Zone
    exportVersion   = "1.0.0"
    recordCount     = $totalScans
    violationCount  = $totalViolations
    organizationUrl = $DataverseUrl
}

# Build summary section
$summary = [PSCustomObject]@{
    overallStatus       = $overallStatus
    totalScans          = $totalScans
    scansCompliant      = $scansCompliant
    scansWithViolations = $scansWithViolations
    totalAgents         = $totalAgents
    totalActions        = $totalActions
    totalViolations     = $totalViolations
    criticalViolations  = $criticalViolations
    highViolations      = $highViolations
    mediumViolations    = $mediumViolations
    warningViolations   = $warningViolations
    violationTypes      = [PSCustomObject]$violationTypes
}

# Build complete evidence object
$evidence = [PSCustomObject]@{
    metadata   = $metadata
    summary    = $summary
    validations = @($validationsReadable)
    violations = @($violationsReadable)
    exceptions = @($exceptionsReadable)
}

#endregion

#region Write JSON Evidence File

# Generate filename with zone and timestamp
$fileTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$fileName = "aca-evidence-$Zone-$fileTimestamp.json"
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
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  Evidence Export Summary" -ForegroundColor Cyan
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ("  Evidence File:  {0}" -f (Split-Path -Leaf $evidenceFilePath)) -ForegroundColor Cyan
Write-Host ("  Hash File:      {0}" -f (Split-Path -Leaf $hashFilePath)) -ForegroundColor Cyan
Write-Host ("  Validations:    {0}" -f $totalScans) -ForegroundColor Cyan
Write-Host ("  Violations:     {0}" -f $totalViolations) -ForegroundColor Cyan
Write-Host ("  Exceptions:     {0}" -f $exceptionsReadable.Count) -ForegroundColor Cyan
Write-Host ("  Total Agents:   {0}" -f $totalAgents) -ForegroundColor Cyan
Write-Host ("  Total Actions:  {0}" -f $totalActions) -ForegroundColor Cyan
Write-Host ("  Overall Status: {0}" -f $overallStatus) -ForegroundColor Cyan
Write-Host ("  SHA-256:        {0}" -f $hashValue.Substring(0, [Math]::Min(33, $hashValue.Length))) -ForegroundColor Cyan
if ($hashValue.Length -gt 33) {
    Write-Host ("                  {0}" -f $hashValue.Substring(33)) -ForegroundColor Cyan
}
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Evidence files ready for compliance verification." -ForegroundColor Green
Write-Host ""

#endregion

#region Return Result Object

$result = [PSCustomObject]@{
    EvidenceFile   = $evidenceFilePath
    HashFile       = $hashFilePath
    SHA256         = $hashValue
    RecordCount    = $totalScans
    ViolationCount = $totalViolations
    GeneratedAt    = $exportTimestamp
}

return $result

#endregion
