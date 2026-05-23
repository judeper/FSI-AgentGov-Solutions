#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Az.Accounts'; ModuleVersion='2.17.0' }

<#
.SYNOPSIS
    Exports inactivity timeout compliance evidence from Dataverse to JSON with SHA-256 integrity hashing.

.DESCRIPTION
    Produces machine-readable compliance evidence packages containing timeout
    compliance results and error logs from the Inactivity Timeout Enforcement
    (ITE) solution's Dataverse tables.

    Each export generates:
    - JSON evidence file with metadata, summary, compliance records, and error logs
    - SHA-256 hash companion file for tamper detection and integrity verification

    Evidence files support regulatory examination workflows by providing
    tamper-evident exports with full compliance history, timestamps, and
    audit trail metadata.

    This script supports Controls 2.22 (Inactivity Timeout), 1.23 (Session Security),
    and 3.7/3.8 (Monitoring) evidence collection requirements.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com). Required.

.PARAMETER TenantId
    Microsoft Entra ID tenant ID. Required for service principal authentication.

.PARAMETER OutputDirectory
    Directory path for evidence files. Created if it does not exist.
    Default: ./evidence

.PARAMETER Zone
    Zone filter for compliance records: All, 1, 2, or 3.
    Default: All.

.PARAMETER FromDate
    Start of date range filter (inclusive). Defaults to 30 days ago.

.PARAMETER ToDate
    End of date range filter (inclusive). Defaults to current timestamp.

.PARAMETER Interactive
    Use interactive browser-based authentication instead of service principal.

.PARAMETER ClientId
    Application/client ID for user-assigned managed identity or legacy client-secret fallback.

.PARAMETER UseManagedIdentity
    Prefer Azure managed identity for Dataverse token acquisition. This is the recommended automation mode.

.PARAMETER ManagedIdentityClientId
    Optional user-assigned managed identity client ID. Defaults to $env:AZURE_CLIENT_ID when present.

.OUTPUTS
    PSCustomObject with properties:
    - EvidenceFile: Full path to JSON evidence file
    - HashFile: Full path to SHA-256 companion file
    - SHA256: Hash value (64 hex characters)
    - RecordCount: Number of compliance records in export
    - ErrorLogCount: Number of error log records in export
    - GeneratedAt: ISO 8601 timestamp of export generation

.EXAMPLE
    .\Export-TimeoutComplianceEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -Interactive

    Exports all compliance results from the past 30 days using interactive
    authentication. Generates JSON evidence file and SHA-256 hash.

.EXAMPLE
    .\Export-TimeoutComplianceEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -OutputDirectory "C:\compliance\evidence" `
        -Zone "3" `
        -FromDate (Get-Date).AddDays(-90) `
        -ClientId "12345..."

    Exports 90 days of Zone 3 compliance records using service principal
    authentication. Suitable for scheduled automation via Azure Automation.

.EXAMPLE
    .\Export-TimeoutComplianceEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "contoso.onmicrosoft.com" `
        -Zone "All" `
        -Interactive

    Exports all zones with interactive auth for ad-hoc examination preparation.

.NOTES
    Version: 1.1.2
    Solution: Inactivity Timeout Enforcement (ITE)
    Controls: 2.22 (Inactivity Timeout), 1.23 (Session Security), 3.7/3.8 (Monitoring)
    Regulations: GLBA Section 501(b), SOX Section 302/404, FINRA Rule 4511(a), NIST 800-53 AC-11/AC-12

    Evidence file naming convention:
    - ite-evidence-{Zone}-{yyyyMMdd-HHmmss}.json

    SHA-256 companion file format:
    - {hash}  {filename} (two spaces, standard checksum format)
    - Verifiable via Test-EvidenceIntegrity or standard tools (shasum, certutil)
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [string]$OutputDirectory = './evidence',

    [Parameter()]
    [ValidateSet('All', '1', '2', '3')]
    [string]$Zone = 'All',

    [Parameter()]
    [datetime]$FromDate = (Get-Date).AddDays(-30),

    [Parameter()]
    [datetime]$ToDate = (Get-Date),

    [Parameter()]
    [switch]$Interactive,

    [Parameter()]
    [string]$ClientId,

    [Parameter()]
    [switch]$UseManagedIdentity,

    [Parameter()]
    [string]$ManagedIdentityClientId = $env:AZURE_CLIENT_ID
)

$ErrorActionPreference = 'Stop'

#region Initialization

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Inactivity Timeout Evidence Export              ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  FSI-AgentGov Inactivity Timeout Enforcement     ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Ensure output directory exists
if (-not (Test-Path -Path $OutputDirectory)) {
    Write-Host "Creating output directory: $OutputDirectory" -ForegroundColor Cyan
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

#endregion


function ConvertTo-PlainAccessToken {
    param([Parameter(Mandatory = $true)]$Token)

    if ($Token -is [securestring]) {
        $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
        try { return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr) }
        finally {
            if ($bstr -ne [IntPtr]::Zero) { [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
        }
    }

    return [string]$Token
}

function Get-IteManagedIdentityToken {
    param(
        [Parameter(Mandatory = $true)] [string]$ResourceUrl,
        [Parameter()] [string]$TenantId,
        [Parameter()] [string]$ManagedIdentityClientId
    )

    if (-not (Get-Command Connect-AzAccount -ErrorAction SilentlyContinue) -or -not (Get-Command Get-AzAccessToken -ErrorAction SilentlyContinue)) {
        throw "Az.Accounts is required for managed identity authentication. Install Az.Accounts or use -Interactive for workstation runs."
    }

    $connectParams = @{ Identity = $true; ErrorAction = 'Stop' }
    if ($ManagedIdentityClientId) { $connectParams.AccountId = $ManagedIdentityClientId }
    if ($TenantId) { $connectParams.Tenant = $TenantId }
    Connect-AzAccount @connectParams | Out-Null

    $tokenParams = @{ ResourceUrl = $ResourceUrl; ErrorAction = 'Stop' }
    if ($TenantId) { $tokenParams.TenantId = $TenantId }
    $tokenResult = Get-AzAccessToken @tokenParams
    return ConvertTo-PlainAccessToken -Token $tokenResult.Token
}

#region Authentication

Write-Host "Authenticating to Dataverse..." -ForegroundColor Cyan

$dataverseScope = "$($DataverseUrl.TrimEnd('/'))/.default"

if ($Interactive) {
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
    $useManagedIdentityAuth = $UseManagedIdentity -or (-not $env:AZURE_CLIENT_SECRET)

    if ($useManagedIdentityAuth) {
        try {
            $accessToken = Get-IteManagedIdentityToken `
                -ResourceUrl $($DataverseUrl.TrimEnd('/')) `
                -TenantId $TenantId `
                -ManagedIdentityClientId $ManagedIdentityClientId
        }
        catch {
            throw "Managed identity authentication failed: $($_.Exception.Message)"
        }
    }
    else {
        # legacy: dev-only -- replace with managed identity in production
        if (-not $ClientId -and -not $env:AZURE_CLIENT_ID) {
            throw "ClientId is required for legacy client-secret authentication. Use -Interactive or -UseManagedIdentity where possible."
        }
        $resolvedClientId = if ($ClientId) { $ClientId } else { $env:AZURE_CLIENT_ID }
        $resolvedTenantId = if ($TenantId) { $TenantId } else { $env:AZURE_TENANT_ID }

        if (-not $env:AZURE_CLIENT_SECRET) {
            throw "AZURE_CLIENT_SECRET is a legacy dev-only fallback. Prefer -UseManagedIdentity for automation."
        }

        $tokenBody = @{
            grant_type    = 'client_credentials'
            client_id     = $resolvedClientId
            client_secret = $env:AZURE_CLIENT_SECRET
            scope         = $dataverseScope
        }

        try {
            $tokenResponse = Invoke-RestMethod `
                -Uri "https://login.microsoftonline.com/$resolvedTenantId/oauth2/v2.0/token" `
                -Method Post `
                -ContentType 'application/x-www-form-urlencoded' `
                -Body $tokenBody `
                -ErrorAction Stop

            $accessToken = $tokenResponse.access_token
        }
        catch {
            Write-Error "Legacy client-secret authentication failed: $($_.Exception.Message)"
            throw
        }
    }
}

Write-Host "Authentication successful." -ForegroundColor Green
Write-Host ""

#endregion

#region Query Compliance Records

Write-Host "Querying compliance records..." -ForegroundColor Cyan
Write-Host "  Zone Filter:  $Zone" -ForegroundColor Cyan
Write-Host "  From Date:    $($FromDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
Write-Host "  To Date:      $($ToDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Cyan
Write-Host ""

$apiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"
$dvHeaders = @{
    'Authorization'    = "Bearer $accessToken"
    'Accept'           = 'application/json'
    'OData-MaxVersion' = '4.0'
    'OData-Version'    = '4.0'
}

# Build OData filter for compliance records
$fromDateUtc = $FromDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$toDateUtc = $ToDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

$filterParts = @(
    "fsi_lastscandate ge $fromDateUtc",
    "fsi_lastscandate le $toDateUtc"
)

if ($Zone -ne 'All') {
    # Map zone name to option set integer for Dataverse choice filter
    $zoneIntMap = @{ '1' = 100000001; '2' = 100000002; '3' = 100000003 }
    $zoneInt = if ($zoneIntMap.ContainsKey($Zone)) { $zoneIntMap[$Zone] } else { $Zone }
    $filterParts += "fsi_zone eq $zoneInt"
}

$filter = $filterParts -join ' and '
$select = 'fsi_compliancename,fsi_environmentid,fsi_environmentname,fsi_zone,fsi_inactivitytimeoutenabled,fsi_timeoutduration,fsi_timeoutdurationminutes,fsi_requiredmaxduration,fsi_timeoutrequired,fsi_compliancestatus,fsi_severity,fsi_regulatorycontext,fsi_notes,fsi_scanrunid,fsi_lastscandate'

# Paginated query for compliance records
$complianceRecords = [System.Collections.ArrayList]::new()
$nextUrl = "$apiBase/fsi_inactivitytimeoutcompliances?`$filter=$filter&`$select=$select&`$orderby=fsi_lastscandate desc"

try {
    while ($nextUrl) {
        $response = Invoke-RestMethod -Uri $nextUrl -Headers $dvHeaders -Method Get -ErrorAction Stop
        foreach ($record in $response.value) {
            [void]$complianceRecords.Add($record)
        }
        $nextUrl = $response.'@odata.nextLink'
    }
    Write-Host "Retrieved $($complianceRecords.Count) compliance record(s)" -ForegroundColor Green
}
catch {
    Write-Error "Failed to query compliance records: $($_.Exception.Message)"
    throw
}

# Query error logs
$errorLogs = [System.Collections.ArrayList]::new()
$errorFilter = "fsi_timestamp ge $fromDateUtc and fsi_timestamp le $toDateUtc"
$errorSelect = 'fsi_errorname,fsi_environmentid,fsi_environmentname,fsi_zone,fsi_errortype,fsi_errorraw,fsi_timestamp,fsi_scanrunid'
$errorNextUrl = "$apiBase/fsi_inactivitytimeouterrorlogs?`$filter=$errorFilter&`$select=$errorSelect&`$orderby=fsi_timestamp desc"

try {
    while ($errorNextUrl) {
        $errorResponse = Invoke-RestMethod -Uri $errorNextUrl -Headers $dvHeaders -Method Get -ErrorAction Stop
        foreach ($record in $errorResponse.value) {
            [void]$errorLogs.Add($record)
        }
        $errorNextUrl = $errorResponse.'@odata.nextLink'
    }
    Write-Host "Retrieved $($errorLogs.Count) error log record(s)" -ForegroundColor Green
}
catch {
    Write-Warning "Failed to query error logs: $($_.Exception.Message)"
    Write-Host "Continuing without error log data." -ForegroundColor Yellow
}

Write-Host ""

#endregion

#region Build Evidence JSON

Write-Host "Building evidence package..." -ForegroundColor Cyan

$exportTimestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

# Compute summary statistics
$totalRecords        = $complianceRecords.Count
$compliantCount      = ($complianceRecords | Where-Object { $_.fsi_compliancestatus -eq 100000000 }).Count
$nonCompliantCount   = ($complianceRecords | Where-Object { $_.fsi_compliancestatus -eq 100000001 }).Count
$unknownCount        = ($complianceRecords | Where-Object { $_.fsi_compliancestatus -eq 100000002 }).Count

$overallStatus = 'Compliant'
if ($nonCompliantCount -gt 0) {
    $overallStatus = 'Failed'
}
elseif ($unknownCount -gt 0) {
    $overallStatus = 'Warning'
}
elseif ($totalRecords -eq 0) {
    $overallStatus = 'NoData'
}

$metadata = [PSCustomObject]@{
    exportedAt      = $exportTimestamp
    solution        = 'Inactivity Timeout Enforcement'
    solutionVersion = '1.1.2'
    fromDate        = $fromDateUtc
    toDate          = $toDateUtc
    zoneFilter      = $Zone
    exportVersion   = '1.0.0'
    recordCount     = $totalRecords
    errorLogCount   = $errorLogs.Count
    organizationUrl = $DataverseUrl
}

$summary = [PSCustomObject]@{
    overallStatus    = $overallStatus
    totalRecords     = $totalRecords
    compliantCount   = $compliantCount
    nonCompliantCount = $nonCompliantCount
    unknownCount     = $unknownCount
    errorLogCount    = $errorLogs.Count
}

# Convert compliance records to readable format
$complianceReadable = $complianceRecords | ForEach-Object {
    [PSCustomObject]@{
        name                   = $_.fsi_compliancename
        environmentId          = $_.fsi_environmentid
        environmentName        = $_.fsi_environmentname
        zone                   = $_.fsi_zone
        timeoutEnabled         = $_.fsi_inactivitytimeoutenabled
        timeoutDuration        = $_.fsi_timeoutduration
        timeoutDurationMinutes = $_.fsi_timeoutdurationminutes
        maxAllowedMinutes      = $_.fsi_requiredmaxduration
        timeoutRequired        = $_.fsi_timeoutrequired
        complianceStatus       = $_.fsi_compliancestatus
        severity               = $_.fsi_severity
        regulatoryContext      = $_.fsi_regulatorycontext
        details                = $_.fsi_notes
        scanRunId              = $_.fsi_scanrunid
        scanTime               = $_.fsi_lastscandate
    }
}

# Convert error logs to readable format
$errorsReadable = $errorLogs | ForEach-Object {
    [PSCustomObject]@{
        name            = $_.fsi_errorname
        environmentId   = $_.fsi_environmentid
        environmentName = $_.fsi_environmentname
        zone            = $_.fsi_zone
        errorType       = $_.fsi_errortype
        errorMessage    = $_.fsi_errorraw
        errorTime       = $_.fsi_timestamp
        scanRunId       = $_.fsi_scanrunid
    }
}

$evidence = [PSCustomObject]@{
    metadata    = $metadata
    summary     = $summary
    compliances = @($complianceReadable)
    errorLogs   = @($errorsReadable)
}

#endregion

#region Write JSON Evidence File

$fileTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$fileName = "ite-evidence-$Zone-$fileTimestamp.json"
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
Write-Host ("║ Compliances:    {0,-33}║" -f $totalRecords) -ForegroundColor Cyan
Write-Host ("║ Error Logs:     {0,-33}║" -f $errorLogs.Count) -ForegroundColor Cyan
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
    EvidenceFile  = $evidenceFilePath
    HashFile      = $hashFilePath
    SHA256        = $hashValue
    RecordCount   = $totalRecords
    ErrorLogCount = $errorLogs.Count
    GeneratedAt   = $exportTimestamp
}

return $result

#endregion
