<#
.SYNOPSIS
    Exports CA policy compliance evidence with SHA-256 integrity hashing.

.DESCRIPTION
    Produces a JSON evidence package containing Conditional Access policy
    validation results, active violations, and current baselines from the
    CAA Dataverse solution. Each export includes a companion SHA-256 hash
    file for tamper-evident verification during regulatory examinations.

    The evidence schema includes metadata (export timestamp, scope, date range,
    record counts), a compliance summary (overall status, zone breakdown), and
    the full record arrays for validations, violations, and baselines.

    Supports compliance with FINRA 4511/3110, SEC 17a-3/4, SOX 302/404,
    and OCC 2011-12 through verifiable evidence collection.

.PARAMETER DataverseUrl
    The Dataverse environment URL (e.g., https://org.crm.dynamics.com).

.PARAMETER OutputPath
    Directory path where the evidence JSON and SHA-256 files will be written.
    The directory is created automatically if it does not exist.

.PARAMETER FromDate
    Start date for the evidence collection window. Defaults to 30 days ago.

.PARAMETER ToDate
    End date for the evidence collection window. Defaults to the current time.

.PARAMETER RunId
    Optional validation run identifier to scope evidence to a specific run.

.PARAMETER IncludeBaselines
    Include active CA policy baselines in the evidence package.
    Both baselines and violations are included by default when neither switch is specified.

.PARAMETER IncludeViolations
    Include active CA policy violations in the evidence package.
    Both baselines and violations are included by default when neither switch is specified.

.EXAMPLE
    .\Export-CAAComplianceEvidence.ps1 -DataverseUrl 'https://org.crm.dynamics.com' `
        -OutputPath './evidence'

    Exports the last 30 days of compliance evidence with SHA-256 verification.

.EXAMPLE
    .\Export-CAAComplianceEvidence.ps1 -DataverseUrl 'https://org.crm.dynamics.com' `
        -OutputPath './evidence' -FromDate '2026-01-01' -ToDate '2026-01-31'

    Exports evidence for the month of January 2026.

.EXAMPLE
    .\Export-CAAComplianceEvidence.ps1 -DataverseUrl 'https://org.crm.dynamics.com' `
        -OutputPath './evidence' -RunId 'abc123' -IncludeBaselines:$false

    Exports validation results for a specific run without baseline data.

.EXAMPLE
    .\Export-CAAComplianceEvidence.ps1 -DataverseUrl 'https://org.crm.dynamics.com' `
        -OutputPath './evidence' -WhatIf

    Previews the evidence export without querying Dataverse.

.OUTPUTS
    System.IO.FileInfo
    The path to the generated evidence JSON file.

.NOTES
    File: Export-CAAComplianceEvidence.ps1
    Version: 1.0.0
    Generates SHA-256 companion files in sha256sum-compatible format
    for evidence integrity verification during regulatory examinations.
#>

#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$DataverseUrl,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath,

    [Parameter()]
    [datetime]$FromDate = (Get-Date).AddDays(-30),

    [Parameter()]
    [datetime]$ToDate = (Get-Date),

    [Parameter()]
    [string]$RunId,

    [Parameter()]
    [switch]$IncludeBaselines,

    [Parameter()]
    [switch]$IncludeViolations,

    [Parameter()]
    [string]$TenantId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Default: include both baselines and violations when neither switch is specified
if (-not $IncludeBaselines -and -not $IncludeViolations) {
    $IncludeBaselines = [switch]::new($true)
    $IncludeViolations = [switch]::new($true)
}

# Import private helpers
. $PSScriptRoot/private/Get-CAAValidationResults.ps1

# Import CAAClient module for Dataverse authentication
Import-Module $PSScriptRoot/private/CAAClient.psm1 -Force

# --- Severity priority map ---
$severityPriority = @{
    'Error'       = 5
    'Failed'      = 4
    'GracePeriod' = 3
    'Warning'     = 2
    'Passed'      = 1
}

# --- Banner ---
Write-Host ('=' * 60) -ForegroundColor Cyan
Write-Host 'CAA Compliance Evidence Export' -ForegroundColor Cyan
Write-Host ('=' * 60) -ForegroundColor Cyan
Write-Host "  Dataverse URL:  $DataverseUrl"
Write-Host "  Output path:    $OutputPath"
Write-Host "  Date range:     $($FromDate.ToString('yyyy-MM-dd')) to $($ToDate.ToString('yyyy-MM-dd'))"
if ($RunId) { Write-Host "  Run ID:         $RunId" }
Write-Host "  Baselines:      $IncludeBaselines"
Write-Host "  Violations:     $IncludeViolations"
Write-Host ''

# --- WhatIf preview ---
if ($WhatIfPreference) {
    Write-Host '[WhatIf] Would perform the following:' -ForegroundColor Yellow
    Write-Host '  1. Connect to Dataverse for authentication'
    Write-Host '  2. Query validation history records'
    if ($IncludeViolations) { Write-Host '  3. Query violation records' }
    if ($IncludeBaselines)  { Write-Host '  4. Query baseline records' }
    Write-Host '  5. Build evidence JSON with metadata and summary'
    Write-Host '  6. Write evidence file with SHA-256 companion hash'
    return
}

# --- Ensure output directory ---
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
    Write-Verbose "Created output directory: $OutputPath"
}

# --- Authenticate ---
Write-Verbose 'Connecting to Dataverse...'
try {
    # Resolve tenant identifier: prefer explicit -TenantId parameter, fall back to org name extraction.
    # The org name fallback (e.g., "contoso" from https://contoso.crm.dynamics.com) is NOT a valid
    # tenant GUID and will cause auth failures when Phase 2 Dataverse integration ships.
    if ($TenantId) {
        $tenantHint = $TenantId
    } else {
        Write-Warning "No -TenantId provided. Extracting org name from DataverseUrl as tenant hint — this is not a valid tenant GUID and will fail when Phase 2 Dataverse integration ships."
        $tenantHint = ([Uri]$DataverseUrl).Host.Split('.')[0]
    }
    Connect-CAADataverse -DataverseUrl $DataverseUrl -TenantId $tenantHint
} catch {
    Write-Warning "Connect-CAADataverse failed: $_. Falling back to Get-AzAccessToken."
}
$accessToken = $script:CAAAccessToken

# If CAAClient sets module-scoped token, retrieve it; otherwise fall back
# to interactive token acquisition for the Dataverse resource
if (-not $accessToken) {
    Write-Verbose 'Acquiring access token for Dataverse...'
    try {
        # Use -AsSecureString to avoid deprecated plaintext .Token (Az module 12+)
        $tokenResponse = Get-AzAccessToken -ResourceUrl $DataverseUrl -AsSecureString
        $accessToken = [System.Net.NetworkCredential]::new('', $tokenResponse.Token).Password
    }
    catch {
        Write-Error "Failed to acquire Dataverse access token. Ensure you are authenticated (Connect-AzAccount) or CAAClient is configured: $_"
        throw
    }
}

# --- Common query parameters ---
$queryParams = @{
    DataverseUrl = $DataverseUrl
    AccessToken  = $accessToken
    FromDate     = $FromDate
    ToDate       = $ToDate
}
if ($RunId) { $queryParams['RunId'] = $RunId }

# --- Query validation histories ---
Write-Host 'Querying validation history...' -ForegroundColor DarkGray
$validations = Get-CAAValidationResults @queryParams -Table 'fsi_capolicyvalidationhistories'
Write-Host "  Found $($validations.Count) validation record(s)."

# --- Query violations (optional) ---
$violations = @()
if ($IncludeViolations) {
    Write-Host 'Querying violations...' -ForegroundColor DarkGray
    $violationParams = @{
        DataverseUrl = $DataverseUrl
        AccessToken  = $accessToken
        Table        = 'fsi_capolicyviolations'
        FromDate     = $FromDate
        ToDate       = $ToDate
    }
    $violations = Get-CAAValidationResults @violationParams
    Write-Host "  Found $($violations.Count) violation record(s)."
}

# --- Query baselines (optional) ---
$baselines = @()
if ($IncludeBaselines) {
    Write-Host 'Querying baselines...' -ForegroundColor DarkGray
    $baselineParams = @{
        DataverseUrl = $DataverseUrl
        AccessToken  = $accessToken
        Table        = 'fsi_capolicybaselines'
    }
    $baselines = Get-CAAValidationResults @baselineParams
    Write-Host "  Found $($baselines.Count) baseline record(s)."
}

# --- Compute summary ---
$passedCount  = @($validations | Where-Object { $_.fsi_overallstatus -eq 'Passed' }).Count
$failedCount  = @($validations | Where-Object { $_.fsi_overallstatus -in @('Failed', 'Error') }).Count
$warningCount = @($validations | Where-Object { $_.fsi_overallstatus -in @('Warning', 'GracePeriod') }).Count

# Determine overall status (worst severity across all validation records)
$overallStatus = 'Passed'
$highestPriority = 0
foreach ($v in $validations) {
    $status = $v.fsi_overallstatus
    if ($status -and $severityPriority.ContainsKey($status)) {
        $priority = $severityPriority[$status]
        if ($priority -gt $highestPriority) {
            $highestPriority = $priority
            $overallStatus = $status
        }
    }
}

# Zone breakdown
$zoneBreakdown = @{}
foreach ($v in $validations) {
    $zone = if ($v.fsi_zone) { $v.fsi_zone } else { 'Unknown' }
    if (-not $zoneBreakdown.ContainsKey($zone)) {
        $zoneBreakdown[$zone] = @{ passed = 0; failed = 0; warning = 0; total = 0 }
    }
    $zoneBreakdown[$zone].total++
    switch ($v.fsi_overallstatus) {
        'Passed'      { $zoneBreakdown[$zone].passed++ }
        { $_ -in @('Failed', 'Error') } { $zoneBreakdown[$zone].failed++ }
        { $_ -in @('Warning', 'GracePeriod') } { $zoneBreakdown[$zone].warning++ }
    }
}

# --- Resolve tenant ID ---
$tenantId = 'unknown'
try {
    $mgContext = Get-MgContext -ErrorAction SilentlyContinue
    if ($mgContext -and $mgContext.TenantId) {
        $tenantId = $mgContext.TenantId
    }
}
catch {
    Write-Verbose "Could not determine tenant ID from Graph context: $_"
}

# --- Build evidence object ---
$timestamp = (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssZ')
$fileName = "CAA-Evidence-$timestamp.json"
$filePath = Join-Path $OutputPath $fileName

$evidence = [ordered]@{
    metadata    = [ordered]@{
        exportedAt     = (Get-Date).ToUniversalTime().ToString('o')
        scope          = 'Tenant'
        tenantId       = $tenantId
        fromDate       = $FromDate.ToUniversalTime().ToString('o')
        toDate         = $ToDate.ToUniversalTime().ToString('o')
        runId          = if ($RunId) { $RunId } else { $null }
        exportVersion  = '1.0.0'
        solutionVersion = '1.2.0'
        recordCount    = $validations.Count
        violationCount = $violations.Count
        baselineCount  = $baselines.Count
    }
    summary     = [ordered]@{
        overallStatus  = $overallStatus
        validationsRun = $validations.Count
        passed         = $passedCount
        failed         = $failedCount
        warning        = $warningCount
        zoneBreakdown  = $zoneBreakdown
    }
    validations = @($validations)
}

if ($IncludeViolations) {
    $evidence['violations'] = @($violations)
}

if ($IncludeBaselines) {
    $evidence['baselines'] = @($baselines)
}

# --- Write evidence JSON ---
if ($PSCmdlet.ShouldProcess($filePath, 'Export compliance evidence JSON')) {
    $jsonContent = $evidence | ConvertTo-Json -Depth 10
    $jsonContent | Out-File -FilePath $filePath -Encoding utf8 -Force
    Write-Verbose "Evidence JSON written to: $filePath"

    # --- Generate SHA-256 companion file ---
    $hash = (Get-FileHash -Path $filePath -Algorithm SHA256).Hash
    $hashLine = "$hash  $fileName"
    $hashFilePath = "$filePath.sha256"
    $hashLine | Out-File -FilePath $hashFilePath -Encoding utf8 -Force -NoNewline
    Write-Verbose "SHA-256 hash written to: $hashFilePath"

    # --- Summary banner ---
    Write-Host ''
    Write-Host 'Evidence Export Complete' -ForegroundColor Green
    Write-Host ('=' * 60) -ForegroundColor Cyan
    Write-Host "  Overall status:      $overallStatus"
    Write-Host "  Validations:         $($validations.Count) ($passedCount passed, $failedCount failed, $warningCount warning)"
    Write-Host "  Violations:          $($violations.Count)"
    Write-Host "  Baselines:           $($baselines.Count)"
    Write-Host "  Evidence file:       $filePath"
    Write-Host "  SHA-256 hash file:   $hashFilePath"
    Write-Host "  SHA-256:             $hash"
    Write-Host ('=' * 60) -ForegroundColor Cyan
    Write-Host ''

    # Return the evidence file path
    Get-Item $filePath
}
