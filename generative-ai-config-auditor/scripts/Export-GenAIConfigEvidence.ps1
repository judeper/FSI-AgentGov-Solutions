#Requires -Version 7.0

<#
.SYNOPSIS
    Exports generative AI configuration compliance evidence from Dataverse to JSON
    with SHA-256 integrity hashing.

.DESCRIPTION
    Produces machine-readable compliance evidence packages containing validation
    results, violation details, optional baselines, optional approved connections,
    and cryptographic integrity verification for the Generative AI Config Auditor
    (GAC) solution.

    Each export generates:
    - JSON evidence file with metadata, summary, validations, violations,
      baselines, and approved connections
    - SHA-256 hash companion file for integrity verification

    Evidence files support regulatory examination workflows (FINRA, SEC, GLBA)
    by providing tamper-evident exports with full validation history, timestamps,
    and audit trail metadata.

    GAC operates at the agent level: violation records include per-agent detail
    (fsi_agentid, fsi_agentname, fsi_aoaienabled, fsi_orchestrationmode) for
    generative AI configuration governance. This script supports FSI-AgentGov
    Control 2.24 (Agent Feature Enablement Governance) evidence collection
    requirements for generative AI configuration governance.

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

.PARAMETER IncludeBaselines
    When specified, includes active GenAI configuration baselines from
    fsi_gacbaselines in the evidence export.

.PARAMETER IncludeApprovedConnections
    When specified, includes approved AOAI connection records from
    fsi_gacapprovedconnections in the evidence export.

.PARAMETER Interactive
    Use interactive browser-based authentication instead of service principal.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication.

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID for service principal authentication.

.EXAMPLE
    .\Export-GenAIConfigEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -OutputDirectory ".\evidence" `
        -Interactive

    Exports all validation results and violations from the past 30 days using
    interactive authentication. Generates JSON evidence file and SHA-256 hash.

.EXAMPLE
    .\Export-GenAIConfigEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -OutputDirectory "C:\compliance\evidence" `
        -Zone "2" `
        -IncludeBaselines `
        -IncludeApprovedConnections `
        -FromDate (Get-Date).AddDays(-90) `
        -ToDate (Get-Date) `
        -ClientId "12345..." `
        -CertificateThumbprint "ABCDEF..."

    Exports 90 days of Zone 2 violations with baselines and approved connections
    using service principal authentication.

.EXAMPLE
    .\Export-GenAIConfigEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -OutputDirectory ".\evidence" `
        -RunId "a1b2c3d4-e5f6-7890-abcd-ef1234567890" `
        -IncludeBaselines `
        -Interactive

    Exports results for a specific validation run with baselines included.

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
    Solution: Generative AI Config Auditor (GAC)
    Control: 2.24 (Agent Feature Enablement Governance)
    Requires:
    - PowerShell 7.0 or later
    - MSAL.PS module for Dataverse authentication
    - GAC Dataverse schema deployed (fsi_gacvalidationhistory,
      fsi_gacviolations, fsi_gacbaselines, fsi_gacapprovedconnections tables)

    Evidence file naming convention:
    - gac-evidence-{zone}-{yyyyMMdd-HHmmss}.json
    - Example: gac-evidence-All-20260210-143022.json

    SHA-256 companion file format:
    - {hash}  {filename}  (two spaces, standard checksum format)
    - Verifiable via Test-EvidenceIntegrity or standard tools (shasum, certutil)

    JSON evidence schema:
    - metadata: Export context (timestamp, solution, date range, org URL, version)
    - summary: Aggregate statistics (overall status, scan/violation counts, agent metrics)
    - validations: Complete array of validation history records
    - violations: Complete array of per-agent GenAI configuration violation records
    - baselines: Active per-agent GenAI baselines (if -IncludeBaselines specified)
    - approvedConnections: Approved AOAI connections (if -IncludeApprovedConnections)
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
    [switch]$IncludeBaselines,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeApprovedConnections,

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
Write-Host "  Generative AI Config Evidence Export" -ForegroundColor Cyan
Write-Host "  FSI-AgentGov GAC Solution" -ForegroundColor Cyan
Write-Host "  Control 2.24 - Feature Enablement" -ForegroundColor Gray
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Import GACClient module for Dataverse operations
$scriptRoot = $PSScriptRoot
try {
    Import-Module "$scriptRoot/private/GACClient.psm1" -Force
    . "$scriptRoot/private/Get-GACValidationResults.ps1"
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

# Connect GACClient module
Connect-GACDataverse -DataverseUrl $DataverseUrl -AccessToken $accessToken

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

$queryParams = @{
    DataverseUrl      = $DataverseUrl
    AccessToken       = $accessToken
    Zone              = $Zone
    FromDate          = $FromDate
    ToDate            = $ToDate
    IncludeViolations = $true
}

if ($RunId) {
    $queryParams.RunId = $RunId
}

try {
    $results = Get-GACValidationResults @queryParams

    $validations = $results.Validations
    $violations = $results.Violations

    Write-Host "Retrieved $($validations.Count) validation records" -ForegroundColor Green
    Write-Host "Retrieved $($violations.Count) violation records" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Error "Failed to query validation results: $($_.Exception.Message)"
    throw
}

#endregion

#region Query Baselines (optional)

$baselines = @()

if ($IncludeBaselines) {
    Write-Host "Querying active GenAI configuration baselines..." -ForegroundColor Cyan

    try {
        $baselineResults = Get-GACBaseline -ActiveOnly
        if ($baselineResults) {
            $baselines = @($baselineResults)
        }
        Write-Host "Retrieved $($baselines.Count) active baseline records" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Warning "Failed to query baselines: $($_.Exception.Message)"
        Write-Host "Continuing without baseline data." -ForegroundColor Yellow
        Write-Host ""
    }
}

#endregion

#region Query Approved Connections (optional)

$approvedConns = @()

if ($IncludeApprovedConnections) {
    Write-Host "Querying approved AOAI connections..." -ForegroundColor Cyan

    try {
        $connResults = Get-GACApprovedConnections
        if ($connResults) {
            $approvedConns = @($connResults)
        }
        Write-Host "Retrieved $($approvedConns.Count) approved connection records" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Warning "Failed to query approved connections: $($_.Exception.Message)"
        Write-Host "Continuing without approved connection data." -ForegroundColor Yellow
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
        validationTime       = $_.fsi_validationtime
        totalAgents          = $_.fsi_totalagents
        compliantCount       = $_.fsi_compliantcount
        violationCount       = $_.fsi_violationcount
        overallStatus        = $_.fsi_overallstatus
        environmentsScanned  = $_.fsi_environmentsscanned
        summaryJson          = $_.fsi_summaryjson
    }
}

# Convert violation records to readable format (agent-level detail for GAC)
$violationsReadable = $violations | ForEach-Object {
    [PSCustomObject]@{
        name              = $_.fsi_name
        environmentGuid   = $_.fsi_environmentguid
        environmentName   = $_.fsi_environmentname
        agentId           = $_.fsi_agentid
        agentName         = $_.fsi_agentname
        zone              = $_.fsi_zone
        violationType     = $_.fsi_violationtype
        aoaiEnabled       = $_.fsi_aoaienabled
        orchestrationMode = $_.fsi_orchestrationmode
        severity          = $_.fsi_severity
        regulatoryContext  = $_.fsi_regulatorycontext
        detectedAt        = $_.fsi_detectedat
        runId             = $_.fsi_runid
    }
}

# Convert baseline records to readable format (if included)
$baselinesReadable = @()
if ($IncludeBaselines -and $baselines.Count -gt 0) {
    $baselinesReadable = $baselines | ForEach-Object {
        [PSCustomObject]@{
            environmentGuid          = $_.EnvironmentGuid
            environmentName          = $_.EnvironmentName
            zone                     = $_.Zone
            agentId                  = $_.AgentId
            agentName                = $_.AgentName
            azureOpenAIEnabled       = $_.AzureOpenAIEnabled
            orchestrationMode        = $_.OrchestrationMode
            generativeAnswersNodeCount = $_.GenerativeAnswersNodeCount
            capturedBy               = $_.CapturedBy
            capturedAt               = $_.CapturedAt
            isActive                 = $_.IsActive
        }
    }
}

# Convert approved connection records to readable format (if included)
$approvedConnsReadable = @()
if ($IncludeApprovedConnections -and $approvedConns.Count -gt 0) {
    $approvedConnsReadable = $approvedConns | ForEach-Object {
        [PSCustomObject]@{
            connectionId     = $_.ConnectionId
            connectionName   = $_.ConnectionName
            zone             = $_.Zone
            approvedBy       = $_.ApprovedBy
            approvedAt       = $_.ApprovedAt
        }
    }
}

# Compute summary statistics
$totalScans = $validationsReadable.Count
$scansCompliant = ($validationsReadable | Where-Object { $_.overallStatus -eq 'Compliant' -or $_.overallStatus -eq 'Passed' }).Count
$scansWithViolations = ($validationsReadable | Where-Object { $_.violationCount -gt 0 }).Count
$totalViolations = $violationsReadable.Count

# Agent-level metrics from validation history
$totalAgents = 0
if ($validationsReadable.Count -gt 0) {
    $latestScan = $validationsReadable | Select-Object -First 1
    $totalAgents = if ($latestScan.totalAgents) { $latestScan.totalAgents } else { 0 }
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
    solution        = "Generative AI Config Auditor"
    solutionVersion = "1.0.0"
    control         = "2.24"
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
    totalViolations     = $totalViolations
    criticalViolations  = $criticalViolations
    highViolations      = $highViolations
    mediumViolations    = $mediumViolations
    warningViolations   = $warningViolations
    violationTypes      = [PSCustomObject]$violationTypes
}

# Build complete evidence object
$evidence = [PSCustomObject]@{
    metadata            = $metadata
    summary             = $summary
    validations         = @($validationsReadable)
    violations          = @($violationsReadable)
    baselines           = @($baselinesReadable)
    approvedConnections = @($approvedConnsReadable)
}

#endregion

#region Write JSON Evidence File

# Generate filename with zone and timestamp
$fileTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$fileName = "gac-evidence-$Zone-$fileTimestamp.json"
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
Write-Host ("  Baselines:      {0}" -f $baselinesReadable.Count) -ForegroundColor Cyan
Write-Host ("  Approved Conns: {0}" -f $approvedConnsReadable.Count) -ForegroundColor Cyan
Write-Host ("  Total Agents:   {0}" -f $totalAgents) -ForegroundColor Cyan
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
