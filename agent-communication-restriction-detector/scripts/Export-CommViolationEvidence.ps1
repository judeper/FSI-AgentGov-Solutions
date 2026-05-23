#Requires -Version 5.1
# Authentication uses Az.Accounts (Get-AzAccessToken). MSAL.PS was deprecated by
# the maintainer and is no longer receiving security updates; ACRDClient.psm1 and
# Connect-EnvironmentDataverse.ps1 already use Az.Accounts. Az.Accounts >= 2.17
# returns the access token as a SecureString from Get-AzAccessToken, so we detect
# and unwrap. (council review M-5)
#Requires -Modules @{ ModuleName='Az.Accounts'; ModuleVersion='2.17.0' }

<#
.SYNOPSIS
    Exports agent communication restriction violation evidence from Dataverse
    to JSON with SHA-256 integrity hashing.

.DESCRIPTION
    Produces machine-readable compliance evidence packages containing scan run
    results, violation details, optional approved routes, optional communication
    exceptions, and cryptographic integrity verification for the Agent
    Communication Restriction Detector (ACRD) solution.

    Each export generates:
    - JSON evidence file with metadata, summary, scan runs, violations,
      approved routes, and communication exceptions
    - SHA-256 hash companion file for integrity verification

    Evidence files support regulatory examination workflows (FINRA, SEC, GLBA)
    by providing tamper-evident exports with full scan history, timestamps,
    and audit trail metadata.

    ACRD operates at the agent communication level: violation records include
    per-agent detail (fsi_callingagentid, fsi_callingagentname, fsi_calledagentid,
    fsi_calledagentname, fsi_callingagentzone, fsi_calledagentzone, fsi_violationtype) for
    inter-agent communication governance. This script supports FSI-AgentGov
    Control 2.17 (Multi-Agent Orchestration Limits) evidence collection
    requirements for agent communication restriction governance.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).

.PARAMETER TenantId
    Microsoft Entra ID tenant ID. Required for authentication.

.PARAMETER OutputDirectory
    Directory path for evidence files. Created if it does not exist.

.PARAMETER Zone
    Optional zone filter for violation records: All, 1, 2, or 3.
    Scan run history is always included regardless of zone filter.
    Default: All.

.PARAMETER RunId
    Optional GUID to export results from a specific scan run only.

.PARAMETER FromDate
    Start of date range filter (inclusive). Defaults to 30 days ago.

.PARAMETER ToDate
    End of date range filter (inclusive). Defaults to current timestamp.

.PARAMETER IncludeApprovedRoutes
    When specified, includes approved communication routes from
    fsi_approvedcommroutes in the evidence export.

.PARAMETER IncludeExceptions
    When specified, includes communication exception records from
    fsi_commexceptions in the evidence export.

.PARAMETER Interactive
    Use interactive browser-based authentication instead of service principal.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication.

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID for service principal authentication.

.EXAMPLE
    .\Export-CommViolationEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -OutputDirectory ".\evidence" `
        -Interactive

    Exports all scan runs and violations from the past 30 days using
    interactive authentication. Generates JSON evidence file and SHA-256 hash.

.EXAMPLE
    .\Export-CommViolationEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -OutputDirectory "C:\compliance\evidence" `
        -Zone "2" `
        -IncludeApprovedRoutes `
        -IncludeExceptions `
        -FromDate (Get-Date).AddDays(-90) `
        -ToDate (Get-Date) `
        -ClientId "12345..." `
        -CertificateThumbprint "ABCDEF..."

    Exports 90 days of Zone 2 violations with approved routes and exceptions
    using service principal authentication.

.EXAMPLE
    .\Export-CommViolationEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -OutputDirectory ".\evidence" `
        -RunId "a1b2c3d4-e5f6-7890-abcd-ef1234567890" `
        -IncludeApprovedRoutes `
        -Interactive

    Exports results for a specific scan run with approved routes included.

.OUTPUTS
    PSCustomObject with properties:
    - EvidenceFile: Full path to JSON evidence file
    - HashFile: Full path to SHA-256 companion file
    - SHA256: Hash value (64 hex characters)
    - RecordCount: Number of scan run records in export
    - ViolationCount: Number of violation records in export
    - GeneratedAt: ISO 8601 timestamp of export generation

.NOTES
    Version: 1.2.1
    Solution: Agent Communication Restriction Detector (ACRD)
    Control: 2.17 (Multi-Agent Orchestration Limits)
    Requires:
    - Windows PowerShell 5.1 or later
    - Az.Accounts module (>= 2.17.0) for Dataverse authentication
    - ACRD Dataverse schema deployed (fsi_commscanrun,
      fsi_agentcommviolations, fsi_approvedcommroutes, fsi_commexceptions tables)

    Evidence file naming convention:
    - acrd-evidence-{zone}-{yyyyMMdd-HHmmss}.json
    - Example: acrd-evidence-All-20260210-143022.json

    SHA-256 companion file format:
    - {hash}  {filename}  (two spaces, standard checksum format)
    - Verifiable via Test-EvidenceIntegrity or standard tools (shasum, certutil)

    JSON evidence schema:
    - metadata: Export context (timestamp, solution, date range, org URL, version)
    - summary: Aggregate statistics (overall status, scan/violation counts, severity breakdown)
    - scanRuns: Complete array of communication scan run records
    - violations: Complete array of per-agent communication violation records
    - approvedRoutes: Approved zone-to-zone routes (if -IncludeApprovedRoutes specified)
    - exceptions: Communication exceptions (if -IncludeExceptions specified)

    Regulatory context:
    Evidence export supports integrity requirements for:
    - FINRA Rule 4511 (audit trail accuracy)
    - SEC Rule 17a-4 (record integrity)
    - SOX Section 302/404 (internal control verification)
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
    [switch]$IncludeApprovedRoutes,

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
Write-Host "  Agent Communication Violation Evidence" -ForegroundColor Cyan
Write-Host "  FSI-AgentGov ACRD Solution" -ForegroundColor Cyan
Write-Host "  Control 2.17 - Multi-Agent Orchestration" -ForegroundColor Gray
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Import ACRDClient module for Dataverse operations
$scriptRoot = $PSScriptRoot
try {
    Import-Module "$scriptRoot/private/ACRDClient.psm1" -Force
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

# Helper to unwrap a token that Az.Accounts >= 2.17 returns as a SecureString.
# Concatenating a SecureString into a Bearer header produces literal
# 'Bearer System.Security.SecureString' which Dataverse rejects with HTTP 401.
function Unprotect-AzAccessToken {
    param([Parameter(Mandatory)] $TokenResult)

    $raw = $TokenResult.Token
    if ($raw -is [System.Security.SecureString]) {
        if ($PSVersionTable.PSVersion.Major -ge 7) {
            return ConvertFrom-SecureString -SecureString $raw -AsPlainText
        }
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($raw)
        try {
            return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
        } finally {
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
    return $raw
}

Import-Module Az.Accounts -ErrorAction Stop

if ($Interactive) {
    # Interactive authentication via Az.Accounts (replaces deprecated MSAL.PS)
    try {
        $existingContext = Get-AzContext -ErrorAction SilentlyContinue
        if (-not $existingContext -or ($TenantId -and $existingContext.Tenant.Id -ne $TenantId)) {
            $connectParams = @{ ErrorAction = 'Stop' }
            if ($TenantId) { $connectParams.TenantId = $TenantId }
            Connect-AzAccount @connectParams | Out-Null
        }

        $tokenResult = Get-AzAccessToken -ResourceUrl $dataverseScope.TrimEnd('/.default').TrimEnd('/') -ErrorAction Stop
        $accessToken = Unprotect-AzAccessToken -TokenResult $tokenResult
    }
    catch {
        Write-Error "Interactive authentication failed: $($_.Exception.Message)"
        throw
    }
}
else {
    # Service principal authentication with certificate (Az.Accounts)
    if (-not $ClientId) {
        throw "ClientId is required for service principal authentication. Use -Interactive for browser-based auth."
    }
    if (-not $CertificateThumbprint) {
        throw "CertificateThumbprint is required for service principal authentication."
    }

    try {
        Connect-AzAccount `
            -ServicePrincipal `
            -TenantId $TenantId `
            -ApplicationId $ClientId `
            -CertificateThumbprint $CertificateThumbprint `
            -ErrorAction Stop | Out-Null

        $tokenResult = Get-AzAccessToken -ResourceUrl $dataverseScope.TrimEnd('/.default').TrimEnd('/') -ErrorAction Stop
        $accessToken = Unprotect-AzAccessToken -TokenResult $tokenResult
    }
    catch {
        Write-Error "Service principal authentication failed: $($_.Exception.Message)"
        throw
    }
}

Write-Host "Authentication successful." -ForegroundColor Green
Write-Host ""

# Connect ACRDClient module
Connect-ACRDDataverse -DataverseUrl $DataverseUrl -AccessToken $accessToken

#endregion

#region Query Scan Runs

Write-Host "Querying scan run results..." -ForegroundColor Cyan
Write-Host "  Zone Filter:  $Zone" -ForegroundColor Cyan
Write-Host "  From Date:    $($FromDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
Write-Host "  To Date:      $($ToDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
if ($RunId) {
    Write-Host "  Run ID:       $RunId" -ForegroundColor Cyan
}
Write-Host ""

$baseUrl = $DataverseUrl.TrimEnd('/')
$fromDateUtc = $FromDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$toDateUtc = $ToDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$headers = @{
    'Authorization'    = "Bearer $accessToken"
    'Accept'           = 'application/json'
    'OData-MaxVersion' = '4.0'
    'OData-Version'    = '4.0'
}

try {
    # Build scan runs OData filter
    $scanFilter = "fsi_validationtime ge $fromDateUtc and fsi_validationtime le $toDateUtc"
    if ($RunId) {
        $scanFilter += " and fsi_runid eq '$RunId'"
    }

    $scanRunUri = "$baseUrl/api/data/v9.2/fsi_commscanrun?" +
                  "`$filter=$scanFilter&`$orderby=fsi_validationtime desc"

    # Paginate through all scan run records
    $scanRuns = @()
    $nextLink = $scanRunUri

    while ($nextLink) {
        $response = Invoke-DataverseRequest -Uri $nextLink -Method Get -Headers $headers
        $scanRuns += $response.value
        $nextLink = $response.'@odata.nextLink'
    }

    Write-Host "Retrieved $($scanRuns.Count) scan run records" -ForegroundColor Green
}
catch {
    Write-Error "Failed to query scan runs: $($_.Exception.Message)"
    throw
}

#endregion

#region Query Violations

try {
    Write-Host "Querying communication violations..." -ForegroundColor Cyan

    # Build violations OData filter
    $violationFilter = "fsi_detectedat ge $fromDateUtc and fsi_detectedat le $toDateUtc"
    if ($Zone -ne 'All') {
        $zoneInt = [int]$Zone
        $violationFilter += " and fsi_callingagentzone eq $zoneInt"
    }
    if ($RunId) {
        $violationFilter += " and fsi_runid eq '$RunId'"
    }

    $violationUri = "$baseUrl/api/data/v9.2/fsi_agentcommviolations?" +
                    "`$filter=$violationFilter&`$orderby=fsi_detectedat desc"

    # Paginate through all violation records
    $violations = @()
    $nextLink = $violationUri

    while ($nextLink) {
        $response = Invoke-DataverseRequest -Uri $nextLink -Method Get -Headers $headers
        $violations += $response.value
        $nextLink = $response.'@odata.nextLink'
    }

    Write-Host "Retrieved $($violations.Count) violation records" -ForegroundColor Green
    Write-Host ""
}
catch {
    Write-Error "Failed to query violations: $($_.Exception.Message)"
    throw
}

#endregion

#region Query Approved Routes (optional)

$approvedRoutes = @()

if ($IncludeApprovedRoutes) {
    Write-Host "Querying approved communication routes..." -ForegroundColor Cyan

    try {
        $routeResults = Get-ApprovedCommRoutes -ActiveOnly
        if ($routeResults) {
            $approvedRoutes = @($routeResults)
        }
        Write-Host "Retrieved $($approvedRoutes.Count) approved route records" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Warning "Failed to query approved routes: $($_.Exception.Message)"
        Write-Host "Continuing without approved route data." -ForegroundColor Yellow
        Write-Host ""
    }
}

#endregion

#region Query Exceptions (optional)

$exceptions = @()

if ($IncludeExceptions) {
    Write-Host "Querying communication exceptions..." -ForegroundColor Cyan

    try {
        $exceptionResults = Get-CommExceptions
        if ($exceptionResults) {
            $exceptions = @($exceptionResults)
        }
        Write-Host "Retrieved $($exceptions.Count) exception records" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Warning "Failed to query communication exceptions: $($_.Exception.Message)"
        Write-Host "Continuing without exception data." -ForegroundColor Yellow
        Write-Host ""
    }
}

#endregion

#region Build Evidence JSON

Write-Host "Building evidence package..." -ForegroundColor Cyan

# Convert scan run records to readable format
$scanRunsReadable = $scanRuns | ForEach-Object {
    [PSCustomObject]@{
        name                 = $_.fsi_name
        runId                = $_.fsi_runid
        scanTime             = $_.fsi_validationtime
        totalAgents          = $_.fsi_totalagents
        totalSkills          = $_.fsi_totalskills
        compliantCount       = $_.fsi_compliantcount
        violationCount       = $_.fsi_violationcount
        overallStatus        = $_.fsi_overallstatus
        environmentsScanned  = $_.fsi_environmentsscanned
        summaryJson          = $_.fsi_summaryjson
    }
}

# Convert violation records to readable format (agent communication detail for ACRD)
$violationsReadable = $violations | ForEach-Object {
    [PSCustomObject]@{
        name                 = $_.fsi_name
        callingEnvironmentId = $_.fsi_callingenvironmentid
        environmentName      = $_.fsi_environmentname
        callingAgentId       = $_.fsi_callingagentid
        callingAgentName     = $_.fsi_callingagentname
        calledAgentId        = $_.fsi_calledagentid
        calledAgentName      = $_.fsi_calledagentname
        callingAgentZone     = $_.fsi_callingagentzone
        calledAgentZone      = $_.fsi_calledagentzone
        violationType        = $_.fsi_violationtype
        severity             = $_.fsi_severity
        regulatoryContext    = $_.fsi_regulatorycontext
        detectedAt           = $_.fsi_detectedat
        runId                = $_.fsi_runid
        skillName            = $_.fsi_skillname
        calledEnvironmentId  = $_.fsi_calledenvironmentid
    }
}

# Convert approved route records to readable format (if included)
$approvedRoutesReadable = @()
if ($IncludeApprovedRoutes -and $approvedRoutes.Count -gt 0) {
    $approvedRoutesReadable = $approvedRoutes | ForEach-Object {
        [PSCustomObject]@{
            sourceZone            = $_.SourceZone
            targetZone            = $_.TargetZone
            directionType         = $_.DirectionType
            allowCrossEnvironment = $_.AllowCrossEnvironment
            approvedBy            = $_.ApprovedBy
            expiresAt             = $_.ExpiresAt
            isActive              = $_.IsActive
            notes                 = $_.Notes
        }
    }
}

# Convert exception records to readable format (if included)
$exceptionsReadable = @()
if ($IncludeExceptions -and $exceptions.Count -gt 0) {
    $exceptionsReadable = $exceptions | ForEach-Object {
        [PSCustomObject]@{
            callingAgentId  = $_.CallingAgentId
            targetAgentId   = $_.TargetAgentId
            sourceZone      = $_.SourceZone
            targetZone      = $_.TargetZone
            status          = $_.Status
            approvedBy      = $_.ApprovedBy
            expiresAt       = $_.ExpiresAt
            justification   = $_.Justification
        }
    }
}

# Compute summary statistics
$totalScans = @($scanRunsReadable).Count
$scansCompliant = @($scanRunsReadable | Where-Object { $_.overallStatus -eq 'Compliant' -or $_.overallStatus -eq 'Passed' }).Count
$scansWithViolations = @($scanRunsReadable | Where-Object { $_.violationCount -gt 0 }).Count
$totalViolations = @($violationsReadable).Count

# Violation severity breakdown
$criticalViolations = @($violationsReadable | Where-Object { $_.severity -eq 'Critical' }).Count
$highViolations = @($violationsReadable | Where-Object { $_.severity -eq 'High' }).Count
$mediumViolations = @($violationsReadable | Where-Object { $_.severity -eq 'Medium' }).Count
$warningViolations = @($violationsReadable | Where-Object { $_.severity -eq 'Warning' }).Count

# Violation type breakdown
$violationTypes = @{}
foreach ($v in $violationsReadable) {
    if ($v.violationType) {
        $typeKey = [string]$v.violationType
        if (-not $violationTypes.ContainsKey($typeKey)) {
            $violationTypes[$typeKey] = 0
        }
        $violationTypes[$typeKey]++
    }
}

# Compute overall status (worst-case across all scans)
$overallStatus = "Compliant"
$statusValues = $scanRunsReadable | Select-Object -ExpandProperty overallStatus -ErrorAction SilentlyContinue
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
    solution        = "Agent Communication Restriction Detector"
    solutionVersion = "1.2.1"
    control         = "2.17"
    controlName     = "Multi-Agent Orchestration Limits"
    fromDate        = $FromDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    toDate          = $ToDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    runId           = if ($RunId) { $RunId } else { $null }
    zoneFilter      = $Zone
    exportVersion   = "1.2.1"
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
    totalViolations     = $totalViolations
    criticalViolations  = $criticalViolations
    highViolations      = $highViolations
    mediumViolations    = $mediumViolations
    warningViolations   = $warningViolations
    violationTypes      = (& {
        $h = [ordered]@{}
        foreach ($k in ($violationTypes.Keys | Sort-Object)) { $h[$k] = $violationTypes[$k] }
        [PSCustomObject]$h
    })
}

# Build complete evidence object
$evidence = [PSCustomObject]@{
    metadata       = $metadata
    summary        = $summary
    scanRuns       = @($scanRunsReadable)
    violations     = @($violationsReadable)
    approvedRoutes = @($approvedRoutesReadable)
    exceptions     = @($exceptionsReadable)
}

#endregion

#region Write JSON Evidence File

# Generate filename with zone and timestamp
$fileTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$fileName = "acrd-evidence-$Zone-$fileTimestamp.json"
$evidenceFilePath = Join-Path -Path $OutputDirectory -ChildPath $fileName

Write-Host "Writing evidence file: $evidenceFilePath" -ForegroundColor Cyan

try {
    # Canonicalize evidence object for deterministic SHA-256 (recursive key sort,
    # stable record ordering, LF-only UTF-8 no-BOM file write).
    function ConvertTo-CanonicalObject {
        param($InputObject)
        if ($null -eq $InputObject) { return $null }
        if ($InputObject -is [System.Collections.IDictionary] -or $InputObject -is [PSCustomObject]) {
            $ordered = [ordered]@{}
            $names = if ($InputObject -is [System.Collections.IDictionary]) {
                $InputObject.Keys | Sort-Object
            } else {
                ($InputObject.PSObject.Properties.Name | Sort-Object)
            }
            foreach ($n in $names) {
                $val = if ($InputObject -is [System.Collections.IDictionary]) { $InputObject[$n] } else { $InputObject.$n }
                $ordered[$n] = ConvertTo-CanonicalObject -InputObject $val
            }
            return [PSCustomObject]$ordered
        }
        if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
            $arr = @()
            foreach ($item in $InputObject) { $arr += ,(ConvertTo-CanonicalObject -InputObject $item) }
            return ,$arr
        }
        return $InputObject
    }

    if ($evidence.scanRuns)       { $evidence.scanRuns       = @($evidence.scanRuns       | Sort-Object validationTime, runId) }
    if ($evidence.violations)     { $evidence.violations     = @($evidence.violations     | Sort-Object detectedAt, runId, callingAgentId, calledAgentId) }
    if ($evidence.approvedRoutes) { $evidence.approvedRoutes = @($evidence.approvedRoutes | Sort-Object sourceZone, targetZone, directionType) }
    if ($evidence.exceptions)     { $evidence.exceptions     = @($evidence.exceptions     | Sort-Object exceptionId) }

    $canonical = ConvertTo-CanonicalObject -InputObject $evidence
    $jsonContent = $canonical | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($evidenceFilePath, ($jsonContent -replace "`r`n", "`n"), [System.Text.UTF8Encoding]::new($false))

    Write-Host "Evidence file written successfully (canonicalized, LF, UTF-8 no BOM)." -ForegroundColor Green
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

    # LF-only, UTF-8 no BOM for cross-platform sha256sum compat
    $hashFileName = "$fileName.sha256"
    $hashFilePath = Join-Path -Path $OutputDirectory -ChildPath $hashFileName
    [System.IO.File]::WriteAllText($hashFilePath, "$hashValue  $fileName`n", [System.Text.UTF8Encoding]::new($false))

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
Write-Host ("  Evidence File:    {0}" -f (Split-Path -Leaf $evidenceFilePath)) -ForegroundColor Cyan
Write-Host ("  Hash File:        {0}" -f (Split-Path -Leaf $hashFilePath)) -ForegroundColor Cyan
Write-Host ("  Scan Runs:        {0}" -f $totalScans) -ForegroundColor Cyan
Write-Host ("  Violations:       {0}" -f $totalViolations) -ForegroundColor Cyan
Write-Host ("  Approved Routes:  {0}" -f $approvedRoutesReadable.Count) -ForegroundColor Cyan
Write-Host ("  Exceptions:       {0}" -f $exceptionsReadable.Count) -ForegroundColor Cyan
Write-Host ("  Overall Status:   {0}" -f $overallStatus) -ForegroundColor Cyan
Write-Host ("  SHA-256:          {0}" -f $hashValue.Substring(0, [Math]::Min(33, $hashValue.Length))) -ForegroundColor Cyan
if ($hashValue.Length -gt 33) {
    Write-Host ("                    {0}" -f $hashValue.Substring(33)) -ForegroundColor Cyan
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
