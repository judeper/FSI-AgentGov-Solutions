#Requires -Version 7.0

<#
.SYNOPSIS
    Exports HITL checkpoint compliance evidence from Dataverse to JSON
    with SHA-256 integrity hashing.

.DESCRIPTION
    Produces machine-readable compliance evidence packages containing HITL
    checkpoint results, violation details, optional exception records, and
    cryptographic integrity verification for the HITL Workflow Governance
    (HWG) solution.

    Each export generates per-entity JSON files with SHA-256 sidecar
    companions and a manifest.json with export metadata:
    - checkpoints.json: HITL checkpoint scan results
    - violations.json: Per-flow violation records
    - scan-runs.json: Validation run history
    - manifest.json: Export context, record counts, hash values, operator UPN

    Evidence files support regulatory examination workflows (FINRA, SEC, GLBA)
    by providing tamper-evident exports with full validation history, timestamps,
    and audit trail metadata.

    HWG operates at the flow level within agents: violation records include
    per-flow detail (fsi_flowname, fsi_checkpointtype, fsi_violationtype)
    for HITL checkpoint governance. This script supports FSI-AgentGov
    Controls 2.12, 2.17, and 1.10 evidence collection requirements.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).

.PARAMETER TenantId
    Microsoft Entra ID tenant ID. Required for authentication.

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID for service principal authentication.

.PARAMETER ClientSecret
    Client secret for service principal authentication.

.PARAMETER Interactive
    Use interactive browser-based authentication instead of service principal.

.PARAMETER OutputDirectory
    Directory path for evidence files. Created if it does not exist.

.PARAMETER StartDate
    Start of date range filter (inclusive). Defaults to 30 days ago.

.PARAMETER EndDate
    End of date range filter (inclusive). Defaults to current timestamp.

.PARAMETER IncludeExceptions
    When specified, includes active HITL checkpoint exception records from
    fsi_hitlcheckpointexceptions in the evidence export.

.EXAMPLE
    .\Export-HitlGovernanceEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -OutputDirectory ".\evidence" `
        -Interactive

    Exports all HITL checkpoint results and violations from the past 30 days
    using interactive authentication. Generates per-entity JSON files and
    SHA-256 sidecars.

.EXAMPLE
    .\Export-HitlGovernanceEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -OutputDirectory "C:\compliance\evidence" `
        -IncludeExceptions `
        -StartDate (Get-Date).AddDays(-90) `
        -EndDate (Get-Date) `
        -ClientId "12345..." `
        -ClientSecret "secret..."

    Exports 90 days of HITL evidence with exceptions using service principal
    authentication.

.OUTPUTS
    PSCustomObject with properties:
    - ManifestFile: Full path to manifest.json
    - OutputDirectory: Path to evidence directory
    - FileCount: Number of evidence files generated
    - TotalRecords: Total records across all entities
    - GeneratedAt: ISO 8601 timestamp of export generation

.NOTES
    Version: 1.1.2
    Solution: HITL Workflow Governance (HWG)
    Controls: 2.12 (Supervision/FINRA Rule 3110), 2.17 (Multi-Agent Orchestration), 1.10 (Communication Compliance)
    Requires:
    - PowerShell 7.0 or later
    - Az.Accounts module (>= 2.17.0) for Dataverse authentication via Connect-EnvironmentDataverse.ps1
    - HWG Dataverse schema deployed (fsi_hitlscanruns,
      fsi_hitlcheckpointresults, fsi_hitlcheckpointexceptions tables)

    Evidence file naming convention:
    - hwg-checkpoints-{yyyyMMdd-HHmmss}.json
    - hwg-violations-{yyyyMMdd-HHmmss}.json
    - hwg-scan-runs-{yyyyMMdd-HHmmss}.json
    - manifest.json
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
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [string]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [switch]$Interactive,

    [Parameter(Mandatory = $false)]
    [datetime]$StartDate = (Get-Date).AddDays(-30),

    [Parameter(Mandatory = $false)]
    [datetime]$EndDate = (Get-Date),

    [Parameter(Mandatory = $false)]
    [switch]$IncludeExceptions
)

$ErrorActionPreference = "Stop"

#region Initialization

Write-Host ""
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  HITL Workflow Governance Evidence Export" -ForegroundColor Cyan
Write-Host "  FSI-AgentGov HWG Solution" -ForegroundColor Cyan
Write-Host "  Controls 2.12 / 2.17 / 1.10" -ForegroundColor Gray
Write-Host "==========================================" -ForegroundColor Cyan
Write-Host ""

# Import HWGClient module for Dataverse operations
$scriptRoot = $PSScriptRoot
try {
    Import-Module "$scriptRoot\private\HWGClient.psm1" -Force
} catch {
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

# §18 TrimEnd note: $DataverseUrl.TrimEnd('/') is SAFE because the argument
# is a single character. Do NOT compose multi-character TrimEnd arguments
# like the literal forward-slash-dot-default pattern — TrimEnd treats its
# argument as a character set, not a substring, and silently corrupts
# sovereign-cloud URLs (e.g. .de top-level domains).
# Connect-EnvironmentDataverse.ps1 acquires Az.Accounts tokens scoped to the
# bare environment URL (no /.default suffix) so we never need to strip a
# scope suffix here.

$connectScript = Join-Path -Path $scriptRoot -ChildPath 'private\Connect-EnvironmentDataverse.ps1'
if (-not (Test-Path -Path $connectScript)) {
    Write-Error "Required helper not found: $connectScript"
    throw "Connect-EnvironmentDataverse.ps1 must be present in scripts/private/."
}

if ($Interactive) {
    try {
        $accessToken = & $connectScript -DataverseUrl $DataverseUrl -Interactive -ErrorAction Stop
    } catch {
        Write-Error "Interactive authentication failed: $($_.Exception.Message)"
        throw
    }
} else {
    # Service principal authentication with client secret
    # legacy: dev-only — replace with managed identity in production
    if (-not $ClientId) {
        throw "ClientId is required for service principal authentication. Use -Interactive for browser-based auth (preferred for admin workstations) or run from a managed-identity host."
    }
    if (-not $ClientSecret) {
        throw "ClientSecret is required for service principal authentication."
    }

    try {
        $secureSecret = ConvertTo-SecureString -String $ClientSecret -AsPlainText -Force
        $spCredential = New-Object -TypeName System.Management.Automation.PSCredential `
            -ArgumentList $ClientId, $secureSecret

        $accessToken = & $connectScript `
            -DataverseUrl $DataverseUrl `
            -TenantId $TenantId `
            -Credential $spCredential `
            -ErrorAction Stop
    } catch {
        Write-Error "Service principal authentication failed: $($_.Exception.Message)"
        throw
    }
}

Write-Host "Authentication successful." -ForegroundColor Green
Write-Host ""

# Connect HWGClient module
Connect-HWGDataverse -DataverseUrl $DataverseUrl -AccessToken $accessToken

#endregion

#region Query Data from Dataverse

Write-Host "Querying HITL governance data..." -ForegroundColor Cyan
Write-Host "  Start Date:   $($StartDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
Write-Host "  End Date:     $($EndDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
Write-Host ""

$baseUrl = $DataverseUrl.TrimEnd('/')
$headers = @{
    'Authorization'    = "Bearer $accessToken"
    'Accept'           = 'application/json'
    'OData-MaxVersion' = '4.0'
    'OData-Version'    = '4.0'
    'Prefer'           = 'odata.include-annotations=*'
}

$startDateStr = $StartDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$endDateStr = $EndDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

# Query scan runs from fsi_hitlscanruns
$scanRunFilter = "fsi_scantime ge $startDateStr and fsi_scantime le $endDateStr"

try {
    $scanRunUri = "$baseUrl/api/data/v9.2/fsi_hitlscanruns?`$filter=$scanRunFilter&`$orderby=fsi_scantime desc"
    $scanRunResponse = Invoke-RestMethod -Uri $scanRunUri -Method Get -Headers $headers -ErrorAction Stop
    $scanRuns = if ($scanRunResponse.value) { $scanRunResponse.value } else { @() }
    Write-Host "Retrieved $($scanRuns.Count) scan run records" -ForegroundColor Green
} catch {
    Write-Error "Failed to query scan runs: $($_.Exception.Message)"
    throw
}

# Query checkpoint results from fsi_hitlcheckpointresults
$checkpointFilter = "fsi_detectedat ge $startDateStr and fsi_detectedat le $endDateStr"

try {
    $checkpointUri = "$baseUrl/api/data/v9.2/fsi_hitlcheckpointresults?`$filter=$checkpointFilter&`$orderby=fsi_detectedat desc"
    $checkpointResponse = Invoke-RestMethod -Uri $checkpointUri -Method Get -Headers $headers -ErrorAction Stop
    $checkpoints = if ($checkpointResponse.value) { $checkpointResponse.value } else { @() }
    Write-Host "Retrieved $($checkpoints.Count) checkpoint result records" -ForegroundColor Green
} catch {
    Write-Error "Failed to query checkpoint results: $($_.Exception.Message)"
    throw
}

# Separate violations (records with a violation type)
$violations = @($checkpoints | Where-Object { $_.fsi_violationtype })
Write-Host "  Of which $($violations.Count) are violation records" -ForegroundColor Yellow

# Query exceptions if requested
$exceptionRecords = @()

if ($IncludeExceptions) {
    Write-Host "Querying active HITL checkpoint exceptions..." -ForegroundColor Cyan

    try {
        $exceptionUri = "$baseUrl/api/data/v9.2/fsi_hitlcheckpointexceptions?`$filter=fsi_isactive eq true"
        $exceptionResponse = Invoke-RestMethod -Uri $exceptionUri -Method Get -Headers $headers -ErrorAction Stop
        if ($exceptionResponse.value) {
            $exceptionRecords = @($exceptionResponse.value)
        }
        Write-Host "Retrieved $($exceptionRecords.Count) active exception records" -ForegroundColor Green
    } catch {
        Write-Warning "Failed to query exceptions: $($_.Exception.Message)"
        Write-Host "Continuing without exception data." -ForegroundColor Yellow
    }
}

Write-Host ""

#endregion

#region Build Evidence JSON Files

Write-Host "Building evidence package..." -ForegroundColor Cyan

$fileTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$exportTimestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$generatedFiles = @{}

# Convert scan runs to readable format
$scanRunsReadable = $scanRuns | ForEach-Object {
    [PSCustomObject]@{
        name                = $_.fsi_name
        runId               = $_.fsi_runid
        scanTime            = $_.fsi_scantime
        totalAgents         = $_.fsi_totalagents
        totalFlows          = $_.fsi_totalflows
        compliantCount      = $_.fsi_compliantcount
        violationCount      = $_.fsi_violationcount
        overallStatus       = $_.fsi_overallstatus
        environmentsScanned = $_.fsi_environmentsscanned
        summaryJson         = $_.fsi_summaryjson
    }
}

# Convert checkpoint results to readable format
$checkpointsReadable = $checkpoints | ForEach-Object {
    [PSCustomObject]@{
        name              = $_.fsi_name
        environmentGuid   = $_.fsi_environmentguid
        environmentName   = $_.fsi_environmentname
        agentId           = $_.fsi_agentid
        agentName         = $_.fsi_agentname
        zone              = $_.fsi_zone
        flowName          = $_.fsi_flowname
        flowId            = $_.fsi_flowid
        checkpointType    = $_.fsi_checkpointtype
        checkpointName    = $_.fsi_checkpointname
        hasHitlCheckpoint = $_.fsi_hashitlcheckpoint
        assignedReviewers = $_.fsi_assignedreviewers
        inputCount        = $_.fsi_inputcount
        violationType     = $_.fsi_violationtype
        severity          = $_.fsi_severity
        regulatoryContext = $_.fsi_regulatorycontext
        detectedAt        = $_.fsi_detectedat
        runId             = $_.fsi_runid
    }
}

# Separate violations from checkpoints
$violationsReadable = @($checkpointsReadable | Where-Object { $_.violationType })

# Write scan-runs.json
$scanRunsFileName = "hwg-scan-runs-$fileTimestamp.json"
$scanRunsFilePath = Join-Path -Path $OutputDirectory -ChildPath $scanRunsFileName
$scanRunsJson = @($scanRunsReadable) | ConvertTo-Json -Depth 10
$scanRunsJson | Out-File -FilePath $scanRunsFilePath -Encoding utf8 -Force
$scanRunsHash = (Get-FileHash -Path $scanRunsFilePath -Algorithm SHA256).Hash
"$scanRunsHash  $scanRunsFileName" | Out-File -FilePath "$scanRunsFilePath.sha256" -Encoding utf8 -Force
$generatedFiles[$scanRunsFileName] = @{ Hash = $scanRunsHash; RecordCount = $scanRuns.Count }
Write-Host "  Written: $scanRunsFileName ($($scanRuns.Count) records)" -ForegroundColor Green

# Write checkpoints.json
$checkpointsFileName = "hwg-checkpoints-$fileTimestamp.json"
$checkpointsFilePath = Join-Path -Path $OutputDirectory -ChildPath $checkpointsFileName
$checkpointsJson = @($checkpointsReadable) | ConvertTo-Json -Depth 10
$checkpointsJson | Out-File -FilePath $checkpointsFilePath -Encoding utf8 -Force
$checkpointsHash = (Get-FileHash -Path $checkpointsFilePath -Algorithm SHA256).Hash
"$checkpointsHash  $checkpointsFileName" | Out-File -FilePath "$checkpointsFilePath.sha256" -Encoding utf8 -Force
$generatedFiles[$checkpointsFileName] = @{ Hash = $checkpointsHash; RecordCount = $checkpoints.Count }
Write-Host "  Written: $checkpointsFileName ($($checkpoints.Count) records)" -ForegroundColor Green

# Write violations.json
$violationsFileName = "hwg-violations-$fileTimestamp.json"
$violationsFilePath = Join-Path -Path $OutputDirectory -ChildPath $violationsFileName
$violationsJson = @($violationsReadable) | ConvertTo-Json -Depth 10
$violationsJson | Out-File -FilePath $violationsFilePath -Encoding utf8 -Force
$violationsHash = (Get-FileHash -Path $violationsFilePath -Algorithm SHA256).Hash
"$violationsHash  $violationsFileName" | Out-File -FilePath "$violationsFilePath.sha256" -Encoding utf8 -Force
$generatedFiles[$violationsFileName] = @{ Hash = $violationsHash; RecordCount = $violations.Count }
Write-Host "  Written: $violationsFileName ($($violations.Count) records)" -ForegroundColor Green

# Write exceptions.json if included
if ($IncludeExceptions) {
    $exceptionsReadable = $exceptionRecords | ForEach-Object {
        [PSCustomObject]@{
            agentId       = $_.fsi_agentid
            flowName      = $_.fsi_flowname
            flowId        = $_.fsi_flowid
            zone          = $_.fsi_zone
            justification = $_.fsi_justification
            approvedBy    = $_.fsi_approvedby
            approvedAt    = $_.fsi_approvedat
            expiresAt     = $_.fsi_expiresat
            isActive      = $_.fsi_isactive
        }
    }

    $exceptionsFileName = "hwg-exceptions-$fileTimestamp.json"
    $exceptionsFilePath = Join-Path -Path $OutputDirectory -ChildPath $exceptionsFileName
    $exceptionsJson = @($exceptionsReadable) | ConvertTo-Json -Depth 10
    $exceptionsJson | Out-File -FilePath $exceptionsFilePath -Encoding utf8 -Force
    $exceptionsHash = (Get-FileHash -Path $exceptionsFilePath -Algorithm SHA256).Hash
    "$exceptionsHash  $exceptionsFileName" | Out-File -FilePath "$exceptionsFilePath.sha256" -Encoding utf8 -Force
    $generatedFiles[$exceptionsFileName] = @{ Hash = $exceptionsHash; RecordCount = $exceptionRecords.Count }
    Write-Host "  Written: $exceptionsFileName ($($exceptionRecords.Count) records)" -ForegroundColor Green
}

#endregion

#region Generate Manifest

Write-Host "Generating manifest..." -ForegroundColor Cyan

# Attempt to determine operator UPN from token claims
$operatorUpn = "Unknown"
try {
    $tokenParts = $accessToken.Split('.')
    if ($tokenParts.Count -ge 2) {
        $payloadBase64 = $tokenParts[1]
        # Pad to multiple of 4
        $padLength = 4 - ($payloadBase64.Length % 4)
        if ($padLength -lt 4) {
            $payloadBase64 += '=' * $padLength
        }
        $payloadJson = [System.Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($payloadBase64))
        $payload = $payloadJson | ConvertFrom-Json
        if ($payload.upn) {
            $operatorUpn = $payload.upn
        } elseif ($payload.unique_name) {
            $operatorUpn = $payload.unique_name
        } elseif ($payload.appid) {
            $operatorUpn = "ServicePrincipal:$($payload.appid)"
        }
    }
} catch {
    Write-Verbose "Could not extract operator UPN from token: $($_.Exception.Message)"
}

$fileEntries = @{}
foreach ($fileName in $generatedFiles.Keys) {
    $fileEntries[$fileName] = [PSCustomObject]@{
        sha256      = $generatedFiles[$fileName].Hash
        recordCount = $generatedFiles[$fileName].RecordCount
    }
}

$totalRecords = ($generatedFiles.Values | Measure-Object -Property RecordCount -Sum).Sum

$manifest = [PSCustomObject]@{
    exportTimestamp  = $exportTimestamp
    solution         = "HITL Workflow Governance"
    solutionVersion  = "1.1.1"
    controls         = @("2.12", "2.17", "1.10")
    startDate        = $StartDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    endDate          = $EndDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    organizationUrl  = $DataverseUrl
    operatorUpn      = $operatorUpn
    totalRecords     = $totalRecords
    fileCount        = $generatedFiles.Count
    files            = [PSCustomObject]$fileEntries
}

$manifestPath = Join-Path -Path $OutputDirectory -ChildPath "manifest.json"
$manifest | ConvertTo-Json -Depth 5 | Out-File -FilePath $manifestPath -Encoding utf8 -Force
Write-Host "  Written: manifest.json" -ForegroundColor Green

#endregion

#region Summary Output

Write-Host ""
Write-Host "==========================================" -ForegroundColor Green
Write-Host "  Evidence Export Complete" -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Output directory: $OutputDirectory" -ForegroundColor Cyan
Write-Host "Files generated:  $($generatedFiles.Count + 1) (including manifest)" -ForegroundColor Cyan
Write-Host "Total records:    $totalRecords" -ForegroundColor Cyan
Write-Host "Operator:         $operatorUpn" -ForegroundColor Cyan
Write-Host ""
Write-Host "Verify integrity with:" -ForegroundColor Gray
Write-Host "  .\Test-EvidenceIntegrity.ps1 -EvidencePath '$OutputDirectory'" -ForegroundColor Gray
Write-Host ""

# Return structured output
[PSCustomObject]@{
    ManifestFile    = $manifestPath
    OutputDirectory = $OutputDirectory
    FileCount       = $generatedFiles.Count + 1
    TotalRecords    = $totalRecords
    GeneratedAt     = $exportTimestamp
}

#endregion
