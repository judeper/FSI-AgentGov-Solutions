#Requires -Version 7.0
#Requires -Modules @{ ModuleName='MSAL.PS'; ModuleVersion='4.37.0.0' }

<#
.SYNOPSIS
    Exports credential scan history and violations from Dataverse with SHA-256 integrity hash.

.DESCRIPTION
    Produces machine-readable compliance evidence packages from the Credential
    Oversharing Detector (COD) Dataverse tables. Exports credential scan records
    and violation details with full metadata, summary statistics, and cryptographic
    integrity verification.

    Each export generates:
    - JSON evidence file with metadata, summary, scan records, and violations
    - SHA-256 hash companion file for integrity verification

    Evidence files support regulatory examination workflows (FINRA, SEC, GLBA)
    by providing tamper-evident exports with full scan history, timestamps,
    and audit trail metadata.

    This script supports FSI-AgentGov credential governance evidence collection
    requirements.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com). Required.

.PARAMETER TenantId
    Microsoft Entra ID tenant GUID. Defaults to $env:AZURE_TENANT_ID.

.PARAMETER OutputDirectory
    Directory path for evidence files. Created if it does not exist.
    Default: ./evidence

.PARAMETER Zone
    Zone filter for violation records: All, 1, 2, or 3.
    Default: All.

.PARAMETER FromDate
    Start of date range filter (inclusive). Defaults to 30 days ago.

.PARAMETER ToDate
    End of date range filter (inclusive). Defaults to current timestamp.

.PARAMETER Interactive
    Use interactive browser-based authentication instead of service principal.

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID for service principal authentication.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication.

.EXAMPLE
    .\Export-CredentialEvidence.ps1 -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "example.onmicrosoft.com" -Interactive

    Exports all credential scan results from the past 30 days using interactive
    authentication. Generates JSON evidence file and SHA-256 hash.

.EXAMPLE
    .\Export-CredentialEvidence.ps1 -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "example.onmicrosoft.com" -Zone "3" `
        -FromDate (Get-Date).AddDays(-90) -ToDate (Get-Date) `
        -ClientId "12345..." -CertificateThumbprint "ABCDEF..."

    Exports 90 days of Zone 3 violations using service principal authentication.

.EXAMPLE
    .\Export-CredentialEvidence.ps1 -DataverseUrl "https://org.crm.dynamics.com" `
        -OutputDirectory "C:\compliance\evidence" -Zone "All" `
        -Interactive

    Exports all zone violations to a custom directory.

.OUTPUTS
    PSCustomObject with properties:
    - EvidenceFile: Full path to JSON evidence file
    - HashFile: Full path to SHA-256 companion file
    - SHA256: Hash value (64 hex characters)
    - ScanCount: Number of scan records in export
    - ViolationCount: Number of violation records in export
    - GeneratedAt: ISO 8601 timestamp of export generation

.NOTES
    Version: 2.0.1
    Solution: Credential Oversharing Detector (COD)
    Controls: 1.14, 1.4, 1.18
    Regulations: FINRA Rule 4511, SEC 17a-4, SOX 302/404, GLBA 501(b)

    Evidence file naming convention:
    - cod-evidence-{Zone}-{yyyyMMdd-HHmmss}.json
    - Example: cod-evidence-All-20260209-143022.json

    SHA-256 companion file format:
    - {hash}  {filename}  (two spaces, standard checksum format)
    - Verifiable via Test-EvidenceIntegrity.ps1 or standard tools (shasum, certutil)

    Part of FSI Agent Governance Framework
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter()]
    [string]$TenantId = $env:AZURE_TENANT_ID,

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
    [string]$CertificateThumbprint
)

$ErrorActionPreference = "Stop"

#region Initialization

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Credential Oversharing Evidence Export           ║" -ForegroundColor Cyan
Write-Host "║  FSI Agent Governance Framework                   ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if (-not $TenantId) {
    throw "TenantId is required. Provide -TenantId or set `$env:AZURE_TENANT_ID."
}

# Ensure output directory exists
if (-not (Test-Path -Path $OutputDirectory)) {
    Write-Host "  Creating output directory: $OutputDirectory" -ForegroundColor Cyan
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

#endregion

#region Authentication

Write-Host "  Authenticating to Dataverse..." -ForegroundColor Cyan

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
    # Service principal with certificate
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

Write-Host "  Authentication successful." -ForegroundColor Green
Write-Host ""

$headers = @{
    "Authorization"    = "Bearer $accessToken"
    "Content-Type"     = "application/json"
    "OData-Version"    = "4.0"
    "OData-MaxVersion" = "4.0"
    "Accept"           = "application/json"
    "Prefer"           = "odata.include-annotations=*,odata.maxpagesize=500"
}

$apiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"

#endregion

#region Query Credential Scans

Write-Host "  Querying credential scan records..." -ForegroundColor Cyan
Write-Host "    Zone Filter: $Zone" -ForegroundColor Gray
Write-Host "    From: $($FromDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray
Write-Host "    To: $($ToDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor Gray

$fromDateStr = $FromDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$toDateStr = $ToDate.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

$scanSelect = "fsi_scanid,fsi_scanrunid,fsi_scanstartedat,fsi_totalenvironments,fsi_agentsscanned,fsi_violationsfound,fsi_scanstatus,fsi_overallstatus,fsi_compliantagents,fsi_zonesummary"
$scanFilter = "fsi_scanstartedat ge $fromDateStr and fsi_scanstartedat le $toDateStr"

$scanUrl = "$apiBase/fsi_credentialscans?`$select=$scanSelect&`$filter=$scanFilter&`$orderby=fsi_scanstartedat desc"

$scans = [System.Collections.ArrayList]::new()
while ($scanUrl) {
    try {
        $response = Invoke-RestMethod -Uri $scanUrl -Headers $headers -Method Get
        foreach ($record in $response.value) {
            [void]$scans.Add($record)
        }
        $scanUrl = $response.'@odata.nextLink'
    }
    catch {
        Write-Error "Failed to query credential scans: $($_.Exception.Message)"
        throw
    }
}

Write-Host "    Scan records retrieved: $($scans.Count)" -ForegroundColor Green

#endregion

#region Query Violations

Write-Host "  Querying violation records..." -ForegroundColor Cyan

# Build violation filter based on scan run IDs
$violationSelect = "fsi_violationid,fsi_scanrunid,fsi_agentid,fsi_agentname,fsi_environmentid,fsi_environmentname,fsi_zone,fsi_violationtype,fsi_severity,fsi_description,fsi_detectedat"
$violationFilter = "fsi_detectedat ge $fromDateStr and fsi_detectedat le $toDateStr"

if ($Zone -ne 'All') {
    $zoneName = "Zone$Zone"
    # Map zone name to option set integer for Dataverse choice filter
    $zoneIntMap = @{ 'Zone1' = 100000001; 'Zone2' = 100000002; 'Zone3' = 100000003 }
    $zoneInt = if ($zoneIntMap.ContainsKey($zoneName)) { $zoneIntMap[$zoneName] } else { $zoneName }
    $violationFilter += " and fsi_zone eq $zoneInt"
}

$violationUrl = "$apiBase/fsi_credentialviolations?`$select=$violationSelect&`$filter=$violationFilter&`$orderby=fsi_detectedat desc"

$violations = [System.Collections.ArrayList]::new()
while ($violationUrl) {
    try {
        $response = Invoke-RestMethod -Uri $violationUrl -Headers $headers -Method Get
        foreach ($record in $response.value) {
            [void]$violations.Add($record)
        }
        $violationUrl = $response.'@odata.nextLink'
    }
    catch {
        Write-Error "Failed to query violations: $($_.Exception.Message)"
        throw
    }
}

Write-Host "    Violation records retrieved: $($violations.Count)" -ForegroundColor Green

#endregion

#region Build Evidence JSON

Write-Host "`n  Building evidence package..." -ForegroundColor Cyan

$exportTimestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")

# Compute summary statistics
$severityLabels = @{ 100000000 = 'Critical'; 100000001 = 'High'; 100000002 = 'Medium'; 100000003 = 'Low'; 100000004 = 'Informational' }

$totalViolations = $violations.Count
$criticalCount = @($violations | Where-Object { $_.fsi_severity -eq 100000000 }).Count
$highCount = @($violations | Where-Object { $_.fsi_severity -eq 100000001 }).Count
$mediumCount = @($violations | Where-Object { $_.fsi_severity -eq 100000002 }).Count
$lowCount = @($violations | Where-Object { $_.fsi_severity -eq 100000003 }).Count
$infoCount = @($violations | Where-Object { $_.fsi_severity -eq 100000004 }).Count

$overallStatus = "Compliant"
if ($criticalCount -gt 0) { $overallStatus = "Critical" }
elseif ($highCount -gt 0) { $overallStatus = "NonCompliant" }
elseif ($mediumCount -gt 0) { $overallStatus = "Review" }
elseif ($lowCount -gt 0) { $overallStatus = "Advisory" }
elseif ($infoCount -gt 0) { $overallStatus = "Informational" }
elseif ($scans.Count -eq 0) { $overallStatus = "NoData" }

$evidence = [PSCustomObject]@{
    metadata   = [PSCustomObject]@{
        exportedAt      = $exportTimestamp
        solution        = "Credential Oversharing Detector"
        solutionVersion = "2.0.1"
        fromDate        = $fromDateStr
        toDate          = $toDateStr
        zoneFilter      = $Zone
        exportVersion   = "1.0.0"
        scanCount       = $scans.Count
        violationCount  = $totalViolations
        organizationUrl = $DataverseUrl
    }
    summary    = [PSCustomObject]@{
        overallStatus           = $overallStatus
        totalScans              = $scans.Count
        totalViolations         = $totalViolations
        criticalViolations      = $criticalCount
        highViolations          = $highCount
        mediumViolations        = $mediumCount
        lowViolations           = $lowCount
        informationalViolations = $infoCount
    }
    scans      = @($scans)
    violations = @($violations)
}

#endregion

#region Write Evidence File

$fileTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$fileName = "cod-evidence-$Zone-$fileTimestamp.json"
$evidenceFilePath = Join-Path -Path $OutputDirectory -ChildPath $fileName

Write-Host "  Writing evidence file: $evidenceFilePath" -ForegroundColor Cyan

try {
    $jsonContent = $evidence | ConvertTo-Json -Depth 10
    $jsonContent | Out-File -FilePath $evidenceFilePath -Encoding utf8 -Force
    Write-Host "  Evidence file written successfully." -ForegroundColor Green
}
catch {
    Write-Error "Failed to write evidence file: $($_.Exception.Message)"
    throw
}

#endregion

#region Generate SHA-256 Hash

Write-Host "  Generating SHA-256 integrity hash..." -ForegroundColor Cyan

try {
    $hashResult = Get-FileHash -Path $evidenceFilePath -Algorithm SHA256
    $hashValue = $hashResult.Hash

    # Write hash companion file in standard format: {hash}  {filename}
    $hashFileName = "$fileName.sha256"
    $hashFilePath = Join-Path -Path $OutputDirectory -ChildPath $hashFileName
    $hashContent = "$hashValue  $fileName"
    $hashContent | Out-File -FilePath $hashFilePath -Encoding utf8 -Force

    Write-Host "  SHA-256 hash: $hashValue" -ForegroundColor Green
    Write-Host "  Hash file: $hashFilePath" -ForegroundColor Green
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
Write-Host ("║ Scans:          {0,-33}║" -f $scans.Count) -ForegroundColor Cyan
Write-Host ("║ Violations:     {0,-33}║" -f $totalViolations) -ForegroundColor Cyan
Write-Host ("║ Overall Status: {0,-33}║" -f $overallStatus) -ForegroundColor Cyan
Write-Host ("║ SHA-256:        {0,-33}║" -f $hashValue.Substring(0, [Math]::Min(33, $hashValue.Length))) -ForegroundColor Cyan
if ($hashValue.Length -gt 33) {
    Write-Host ("║                 {0,-33}║" -f $hashValue.Substring(33)) -ForegroundColor Cyan
}
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Verify with: .\Test-EvidenceIntegrity.ps1 -EvidenceFilePath `"$evidenceFilePath`"" -ForegroundColor Gray
Write-Host ""
Write-Host "  Evidence export: COMPLETE" -ForegroundColor Green

#endregion

#region Return Result Object

return [PSCustomObject]@{
    EvidenceFile   = $evidenceFilePath
    HashFile       = $hashFilePath
    SHA256         = $hashValue
    ScanCount      = $scans.Count
    ViolationCount = $totalViolations
    GeneratedAt    = $exportTimestamp
}

#endregion
