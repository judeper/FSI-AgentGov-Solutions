<#
.SYNOPSIS
    Exports ASARD sharing compliance evidence from Dataverse to JSON with SHA-256 integrity hashing.

.DESCRIPTION
    Produces machine-readable compliance evidence packages containing sharing
    compliance records, approved security group policies, and cryptographic
    integrity verification for the Agent Sharing Access Restriction Detector
    (ASARD) solution.

    Each export generates:
    - JSON evidence file with metadata, summary, compliance records, and policies
    - SHA-256 hash companion file for integrity verification

    Evidence files support regulatory examination workflows (FINRA, SEC, GLBA)
    by providing tamper-evident exports with full validation history, timestamps,
    and audit trail metadata.

    This script supports Controls 1.18 (Application-Level Authorization) and
    2.8 (Access Control/Segregation of Duties) evidence collection requirements.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com). Required.

.PARAMETER TenantId
    Microsoft Entra ID tenant ID. Required for authentication.

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
    Microsoft Entra ID application (client) ID for service principal authentication.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication.

.EXAMPLE
    .\Export-SharingComplianceEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "example.onmicrosoft.com" `
        -Interactive

    Exports all compliance records from the past 30 days using interactive auth.

.EXAMPLE
    .\Export-SharingComplianceEvidence.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "example.onmicrosoft.com" `
        -Zone "2" `
        -FromDate (Get-Date).AddDays(-90) `
        -OutputDirectory "C:\compliance\evidence" `
        -ClientId "12345..." `
        -CertificateThumbprint "ABCDEF..."

    Exports 90 days of Zone 2 compliance records using service principal auth.

.OUTPUTS
    PSCustomObject with properties:
    - EvidenceFile: Full path to JSON evidence file
    - HashFile: Full path to SHA-256 companion file
    - SHA256: Hash value (64 hex characters)
    - RecordCount: Number of compliance records in export
    - PolicyCount: Number of approved group policy records in export
    - GeneratedAt: ISO 8601 timestamp of export generation

.NOTES
    File: Export-SharingComplianceEvidence.ps1
    Version: 1.0.4
    Solution: Agent Sharing Access Restriction Detector (ASARD)
    Controls: 1.18 (Application-Level Authorization), 2.8 (Access Control/Segregation of Duties)
    Regulations: FINRA Rule 4511, SOX Section 404, GLBA Section 501(b)

    Evidence file naming convention:
    - asard-evidence-{zone}-{yyyyMMdd-HHmmss}.json
    - Example: asard-evidence-All-20260301-143022.json

    SHA-256 companion file format:
    - {hash}  {filename}  (two spaces, standard checksum format)
    - Verifiable via Test-EvidenceIntegrity.ps1 or standard tools (shasum, certutil)

    Part of FSI Agent Governance Framework
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
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
    [string]$CertificateThumbprint
)

$ErrorActionPreference = 'Stop'

#region Initialization

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  ASARD Evidence Export                          ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  Agent Sharing Access Restriction Detector       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if (-not (Test-Path -Path $OutputDirectory)) {
    Write-Host "Creating output directory: $OutputDirectory" -ForegroundColor Cyan
    New-Item -Path $OutputDirectory -ItemType Directory -Force | Out-Null
}

#endregion

#region Authentication

Write-Host "Authenticating to Dataverse..." -ForegroundColor Cyan

$dataverseScope = "$($DataverseUrl.TrimEnd('/'))/.default"

if ($Interactive) {
    try {
        # NOTE: MSAL.PS is archived and no longer maintained.
        # Consider migrating to Microsoft.Graph.Authentication or Az.Accounts for token acquisition.
        # See https://github.com/AzureAD/MSAL.PS for archive notice.
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
        exit 1
    }
}
else {
    if (-not $ClientId) {
        throw "ClientId is required for service principal authentication. Use -Interactive for browser-based auth."
    }
    if (-not $CertificateThumbprint) {
        throw "CertificateThumbprint is required for service principal authentication."
    }

    try {
        # NOTE: MSAL.PS is archived and no longer maintained.
        # Consider migrating to Microsoft.Graph.Authentication or Az.Accounts for token acquisition.
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
        exit 1
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
$headers = @{
    'Authorization'    = "Bearer $accessToken"
    'Accept'           = 'application/json'
    'OData-MaxVersion' = '4.0'
    'OData-Version'    = '4.0'
    'Prefer'           = 'odata.include-annotations=*,odata.maxpagesize=500'
}

$fromDateUtc = $FromDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
$toDateUtc   = $ToDate.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

$select = 'fsi_complianceid,fsi_agentid,fsi_agentname,fsi_environmentid,fsi_environmentname,' +
          'fsi_zone,fsi_sharingtype,fsi_violationtype,fsi_severity,fsi_compliancestatus,fsi_description,' +
          'fsi_detectedat,fsi_scanrunid,fsi_sharedgroupids,fsi_regulatorycontext'

$filter = "fsi_detectedat ge $fromDateUtc and fsi_detectedat le $toDateUtc"
if ($Zone -ne 'All') {
    # Map zone name to option set integer
    $zoneIntMap = @{ '1' = 1; '2' = 2; '3' = 3 }
    $zoneInt = if ($zoneIntMap.ContainsKey($Zone)) { $zoneIntMap[$Zone] } else { $Zone }
    $filter += " and fsi_zone eq $zoneInt"
}

$complianceUrl = "$apiBase/fsi_agentsharingcompliances?`$select=$select&`$filter=$filter&`$orderby=fsi_detectedat desc"

$complianceRecords = [System.Collections.ArrayList]::new()
$nextUrl = $complianceUrl
while ($nextUrl) {
    try {
        $response = Invoke-RestMethod -Uri $nextUrl -Headers $headers -Method Get -ErrorAction Stop
        $values = if ($response.value) { $response.value } else { @() }
        foreach ($record in $values) {
            [void]$complianceRecords.Add($record)
        }
        $nextUrl = $response.'@odata.nextLink'
    }
    catch {
        Write-Error "Failed to query compliance records: $($_.Exception.Message)"
        exit 1
    }
}

Write-Host "  Compliance records retrieved: $($complianceRecords.Count)" -ForegroundColor Green

#endregion

#region Query Approved Security Group Policies

Write-Host "Querying approved security group policies..." -ForegroundColor Cyan

$policySelect = 'fsi_policyname,fsi_securitygroupid,fsi_securitygroupname,fsi_zone,fsi_approvedby,fsi_approvedat'
$policyFilter = 'fsi_isactive eq true'
if ($Zone -ne 'All') {
    $policyFilter += " and fsi_zone eq $zoneInt"
}

$policyUrl = "$apiBase/fsi_approvedsecuritygrouppolicies?`$select=$policySelect&`$filter=$policyFilter&`$orderby=fsi_zone asc"

$policyRecords = [System.Collections.ArrayList]::new()
$nextUrl = $policyUrl
while ($nextUrl) {
    try {
        $response = Invoke-RestMethod -Uri $nextUrl -Headers $headers -Method Get -ErrorAction Stop
        $values = if ($response.value) { $response.value } else { @() }
        foreach ($record in $values) {
            [void]$policyRecords.Add($record)
        }
        $nextUrl = $response.'@odata.nextLink'
    }
    catch {
        Write-Warning "Failed to query approved group policies: $($_.Exception.Message)"
        break
    }
}

Write-Host "  Policy records retrieved: $($policyRecords.Count)" -ForegroundColor Green
Write-Host ""

#endregion

#region Build Evidence JSON

Write-Host "Building evidence package..." -ForegroundColor Cyan

$exportTimestamp = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

# Compute summary statistics
$totalRecords      = $complianceRecords.Count
$violationRecords  = ($complianceRecords | Where-Object { $_.fsi_violationtype -and $_.fsi_violationtype -ne 'None' }).Count
$criticalCount     = ($complianceRecords | Where-Object { $_.fsi_severity -eq 100000000 }).Count
$highCount         = ($complianceRecords | Where-Object { $_.fsi_severity -eq 100000001 }).Count

$overallStatus = 'Compliant'
if ($criticalCount -gt 0)     { $overallStatus = 'Failed' }
elseif ($highCount -gt 0)     { $overallStatus = 'Warning' }
elseif ($violationRecords -gt 0) { $overallStatus = 'Review' }

$metadata = [PSCustomObject]@{
    exportedAt      = $exportTimestamp
    solution        = 'Agent Sharing Access Restriction Detector'
    solutionVersion = '1.0.4'
    controls        = @('1.18', '2.8')
    fromDate        = $fromDateUtc
    toDate          = $toDateUtc
    zoneFilter      = $Zone
    exportVersion   = '1.0.0'
    recordCount     = $totalRecords
    policyCount     = $policyRecords.Count
    organizationUrl = $DataverseUrl
}

$summary = [PSCustomObject]@{
    overallStatus    = $overallStatus
    totalRecords     = $totalRecords
    violationRecords = $violationRecords
    criticalCount    = $criticalCount
    highCount        = $highCount
    policyCount      = $policyRecords.Count
}

$evidence = [PSCustomObject]@{
    metadata          = $metadata
    summary           = $summary
    complianceRecords = @($complianceRecords)
    approvedPolicies  = @($policyRecords)
}

#endregion

#region Write Evidence File

$fileTimestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$fileName = "asard-evidence-$Zone-$fileTimestamp.json"
$evidenceFilePath = Join-Path -Path $OutputDirectory -ChildPath $fileName

Write-Host "Writing evidence file: $evidenceFilePath" -ForegroundColor Cyan

try {
    $jsonContent = $evidence | ConvertTo-Json -Depth 10
    $jsonContent | Out-File -FilePath $evidenceFilePath -Encoding utf8 -Force
    Write-Host "Evidence file written successfully." -ForegroundColor Green
}
catch {
    Write-Error "Failed to write evidence file: $($_.Exception.Message)"
    exit 1
}

#endregion

#region Generate SHA-256 Hash

Write-Host "Generating SHA-256 integrity hash..." -ForegroundColor Cyan

try {
    $hashResult = Get-FileHash -Path $evidenceFilePath -Algorithm SHA256
    $hashValue = $hashResult.Hash

    $hashFileName = "$fileName.sha256"
    $hashFilePath = Join-Path -Path $OutputDirectory -ChildPath $hashFileName
    $hashContent = "$hashValue  $fileName"
    $hashContent | Out-File -FilePath $hashFilePath -Encoding utf8 -Force

    Write-Host "SHA-256 hash file created: $hashFilePath" -ForegroundColor Green
}
catch {
    Write-Error "Failed to generate SHA-256 hash: $($_.Exception.Message)"
    exit 1
}

#endregion

#region Display Summary

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       Evidence Export Summary                    ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host ("║ Evidence File:  {0,-33}║" -f (Split-Path -Leaf $evidenceFilePath)) -ForegroundColor Cyan
Write-Host ("║ Hash File:      {0,-33}║" -f (Split-Path -Leaf $hashFilePath)) -ForegroundColor Cyan
Write-Host ("║ Records:        {0,-33}║" -f $totalRecords) -ForegroundColor Cyan
Write-Host ("║ Violations:     {0,-33}║" -f $violationRecords) -ForegroundColor Cyan
Write-Host ("║ Policies:       {0,-33}║" -f $policyRecords.Count) -ForegroundColor Cyan
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
    EvidenceFile   = $evidenceFilePath
    HashFile       = $hashFilePath
    SHA256         = $hashValue
    RecordCount    = $totalRecords
    PolicyCount    = $policyRecords.Count
    GeneratedAt    = $exportTimestamp
}

return $result

#endregion
