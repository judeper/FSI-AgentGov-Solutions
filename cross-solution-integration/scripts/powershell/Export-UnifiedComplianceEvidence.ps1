<#
.SYNOPSIS
    Exports unified compliance evidence (run-level history) from Tier 2
    governance solutions into a CSV bundle with a SHA-256 manifest.

.DESCRIPTION
    Queries each Tier 2 solution's run-level validation-history table in
    Dataverse and writes per-solution CSVs plus a master manifest that
    captures SHA-256 hashes of every exported file.

    The manifest is suitable as a *collection step* in an audit-evidence
    workflow that supports record-keeping requirements such as FINRA Rule
    4511 and SEC Rule 17a-4. Long-term immutability requires downstream
    storage on a WORM/immutable target; this script does not provide WORM
    semantics on its own.

    NOTE: v2.0.0 narrows the export to run-level history tables only.
    Per-finding violation tables (fsi_*violations) vary in shape across
    solutions and are deferred to a future release that will join history
    -> violation by run id.

.PARAMETER DataverseUrl
    The Dataverse environment URL.

.PARAMETER TenantId
    The Microsoft Entra tenant ID.

.PARAMETER OutputPath
    Base directory for evidence export. A timestamped subdirectory will be created.

.PARAMETER StartDate
    Export records from this date (inclusive). Default: 30 days ago.

.PARAMETER EndDate
    Export records through this date (inclusive). Default: today.

.PARAMETER Solutions
    Which solutions to export. Default: all (ACV,SSC,AAM,CMM,FUS,CAA).

.PARAMETER ClientId
    App registration client ID for legacy service principal auth.

.PARAMETER ClientSecret
    App registration client secret. Legacy dev-only fallback; use managed identity in production.

.PARAMETER ManagedIdentity
    Use system-assigned managed identity from an Azure-hosted worker.

.PARAMETER ManagedIdentityClientId
    Optional user-assigned managed identity client ID.

.PARAMETER Interactive
    Use interactive authentication.

.PARAMETER Cloud
    Sovereign cloud (Public, USGov, USGovHigh, USGovDoD, China, Germany).

.PARAMETER DryRun
    Show export plan without querying Dataverse.

.EXAMPLE
    .\Export-UnifiedComplianceEvidence.ps1 -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "guid" -OutputPath "C:\evidence" -Interactive

.EXAMPLE
    .\Export-UnifiedComplianceEvidence.ps1 -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "guid" -OutputPath "C:\evidence" -ManagedIdentity

.EXAMPLE
    .\Export-UnifiedComplianceEvidence.ps1 -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "guid" -Solutions ACV,SSC -StartDate "2026-01-01" -Interactive

.NOTES
    Version: 2.0.3
    Date: 2026-05-22
    Requires: IntegrationConfig.psm1 v2.0.3
#>

#Requires -Version 7.0

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(Mandatory)]
    [string]$DataverseUrl,

    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter()]
    [string]$OutputPath = '.',

    [Parameter()]
    [datetime]$StartDate = (Get-Date).AddDays(-30),

    [Parameter()]
    [datetime]$EndDate = (Get-Date),

    [Parameter()]
    [ValidateSet('ACV', 'SSC', 'AAM', 'CMM', 'FUS', 'CAA')]
    [string[]]$Solutions = @('ACV', 'SSC', 'AAM', 'CMM', 'FUS', 'CAA'),

    [Parameter(ParameterSetName = 'ManagedIdentity', Mandatory)]
    [switch]$ManagedIdentity,

    [Parameter(ParameterSetName = 'ManagedIdentity')]
    [string]$ManagedIdentityClientId,

    [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory)]
    [string]$ClientId,

    [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory)]
    [SecureString]$ClientSecret,

    [Parameter(ParameterSetName = 'Interactive', Mandatory)]
    [switch]$Interactive,

    [Parameter()]
    [ValidateSet('Public', 'USGov', 'USGovHigh', 'USGovDoD', 'China', 'Germany')]
    [string]$Cloud = 'Public',

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Import integration module
$modulePath = Join-Path $PSScriptRoot 'IntegrationConfig.psm1'
Import-Module $modulePath -Force

#region Authentication (provided by IntegrationConfig.psm1)

#endregion

#region Solution Table Definitions

$SolutionEvidence = @{
    # NOTE: Field lists below are the *common, verified* run-level columns
    # exported per solution. Keep these in sync with each solution's
    # create_*_dataverse_schema.py. Per-finding violation tables are not
    # exported in v2.0.0 — see CHANGELOG.
    ACV = @{
        Validations = @{
            EntitySet = 'fsi_auditvalidationhistories'
            DateField = 'fsi_timestamp'
            Fields    = @('fsi_runid', 'fsi_timestamp', 'fsi_severity', 'fsi_zone', 'fsi_environmentid', 'fsi_environmentname', 'fsi_validationtype', 'fsi_checkcount', 'fsi_reason')
        }
    }
    SSC = @{
        Validations = @{
            EntitySet = 'fsi_validationhistories'
            DateField = 'fsi_timestamp'
            Fields    = @('fsi_runid', 'fsi_timestamp', 'fsi_severity', 'fsi_zone', 'fsi_validationtype', 'fsi_checkcount')
        }
    }
    AAM = @{
        Validations = @{
            EntitySet = 'fsi_accessvalidationhistory'
            DateField = 'fsi_validationtime'
            Fields    = @('fsi_runid', 'fsi_validationtime', 'fsi_severity', 'fsi_zone', 'fsi_overallstatus', 'fsi_totalenvironments', 'fsi_compliantcount', 'fsi_violationcount', 'fsi_summaryjson')
        }
    }
    CMM = @{
        Validations = @{
            EntitySet = 'fsi_moderationvalidationhistory'
            DateField = 'fsi_validationtime'
            Fields    = @('fsi_runid', 'fsi_validationtime', 'fsi_overallstatus', 'fsi_totalagents', 'fsi_compliantcount', 'fsi_violationcount', 'fsi_summaryjson')
        }
    }
    FUS = @{
        Validations = @{
            EntitySet = 'fsi_fileuploadvalidationhistories'
            DateField = 'fsi_validationtime'
            Fields    = @('fsi_runid', 'fsi_validationtime', 'fsi_compliancerate', 'fsi_totalagents', 'fsi_compliantcount', 'fsi_violationcount', 'fsi_summaryjson')
        }
    }
    CAA = @{
        Validations = @{
            EntitySet = 'fsi_capolicyvalidationhistories'
            DateField = 'fsi_validationtime'
            Fields    = @('fsi_runid', 'fsi_validationtime', 'fsi_overallseverity', 'fsi_totalpolicies', 'fsi_passedcount', 'fsi_warningcount', 'fsi_failedcount', 'fsi_driftcount', 'fsi_tenantid')
        }
    }
}

#endregion

#region Query and Export Functions

function Get-ResponseStatusCode {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    if ($null -ne $ErrorRecord.Exception.Response -and $null -ne $ErrorRecord.Exception.Response.StatusCode) {
        return [int]$ErrorRecord.Exception.Response.StatusCode
    }
    return 0
}

function Get-RetryDelaySeconds {
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [int]$RetryCount
    )

    $response = $ErrorRecord.Exception.Response
    if ($null -ne $response -and $null -ne $response.Headers) {
        try {
            $retryAfter = ($response.Headers.GetValues('Retry-After') | Select-Object -First 1)
            if ($retryAfter -and ($retryAfter -as [int])) {
                return [int]$retryAfter
            }
        } catch {
            Write-Verbose ("Retry-After header lookup for Dataverse retry response {0} failed; using exponential backoff: {1}" -f $ErrorRecord.TargetObject, $_.Exception.Message)
        }
    }

    return [int]([math]::Pow(2, $RetryCount) * 5)
}

function Get-DataverseRecords {
    param([hashtable]$Connection, [string]$EntitySet, [string]$Filter, [string[]]$Fields, [string]$DateField)

    $select = $Fields -join ','
    $orderField = if ($DateField) { $DateField } else { $Fields[1] }
    $url = "$($Connection.BaseUrl)/$($EntitySet)?`$filter=$Filter&`$select=$select&`$orderby=$orderField desc"
    
    $allRecords = @()
    $maxRetries = 3
    do {
        $retryCount = 0
        $success = $false
        while (-not $success -and $retryCount -lt $maxRetries) {
            try {
                $response = Invoke-RestMethod -Uri $url -Headers $Connection.Headers -Method Get
                $allRecords += $response.value
                $url = $response.'@odata.nextLink'
                $success = $true
            } catch {
                $retryCount++
                $statusCode = Get-ResponseStatusCode -ErrorRecord $_
                if ($statusCode -in @(429, 503) -and $retryCount -lt $maxRetries) {
                    $delay = Get-RetryDelaySeconds -ErrorRecord $_ -RetryCount $retryCount
                    Write-Warning "Transient error ($statusCode) querying $EntitySet — retrying in ${delay}s (attempt $retryCount/$maxRetries)"
                    Start-Sleep -Seconds $delay
                } else {
                    throw
                }
            }
        }
        if (-not $success) {
            $url = $null
        }
    } while ($url)

    return $allRecords
}

function Export-ToCsv {
    param([array]$Records, [string]$FilePath, [string[]]$Fields)

    if ($Records.Count -eq 0) {
        # Create empty CSV with headers
        $Fields -join ',' | Out-File -FilePath $FilePath -Encoding utf8
        return
    }

    $Records | ForEach-Object {
        $obj = [ordered]@{}
        foreach ($f in $Fields) {
            $obj[$f] = $_.$f
        }
        [PSCustomObject]$obj
    } | Export-Csv -Path $FilePath -NoTypeInformation -Encoding utf8
}

function Get-FileHashSHA256 {
    param([string]$FilePath)
    return (Get-FileHash -Path $FilePath -Algorithm SHA256).Hash
}

#endregion

#region Main

Write-Host "`nExport-UnifiedComplianceEvidence" -ForegroundColor Cyan
Write-Host "=================================`n" -ForegroundColor Cyan

$startStr = $StartDate.ToUniversalTime().ToString('yyyy-MM-dd')
# End is exclusive in OData filters below; advance by one day so that records on
# EndDate are included.
$endStr = $EndDate.ToUniversalTime().AddDays(1).ToString('yyyy-MM-dd')
$exportDir = Join-Path $OutputPath "evidence-export-$([DateTime]::UtcNow.ToString('yyyy-MM-dd-HHmmss'))"

Write-Host "Period: $startStr to $endStr" -ForegroundColor Gray
Write-Host "Solutions: $($Solutions -join ', ')" -ForegroundColor Gray
Write-Host "Output: $exportDir" -ForegroundColor Gray

if ($DryRun) {
    Write-Host "`n[DryRun] Export plan:" -ForegroundColor Yellow
    foreach ($sol in $Solutions) {
        $tables = $SolutionEvidence[$sol]
        Write-Host "  $($sol):" -ForegroundColor Yellow
        Write-Host "    Validations: $($tables.Validations.EntitySet)" -ForegroundColor Yellow
    }
    Write-Host "`n[DryRun] No data exported.`n" -ForegroundColor Yellow
    return
}

# Connect
Write-Host "`nConnecting to Dataverse..." -ForegroundColor Gray
if ($ManagedIdentity) {
    $connection = Connect-DataverseApi -Url $DataverseUrl -TenantId $TenantId `
        -ManagedIdentity -ManagedIdentityClientId $ManagedIdentityClientId -Cloud $Cloud
} elseif ($Interactive) {
    $connection = Connect-DataverseApi -Url $DataverseUrl -TenantId $TenantId -Interactive -Cloud $Cloud
} else {
    # legacy: dev-only — replace with managed identity in production
    $connection = Connect-DataverseApi -Url $DataverseUrl -TenantId $TenantId `
        -ClientId $ClientId -ClientSecret $ClientSecret -Cloud $Cloud
}

# Create output directory
New-Item -Path $exportDir -ItemType Directory -Force | Out-Null

$manifest = @{
    exportId      = [guid]::NewGuid().ToString()
    exportDate    = (Get-IsoUtcTimestamp)
    periodStart   = $startStr
    periodEnd     = $EndDate.ToUniversalTime().ToString('yyyy-MM-dd')
    framework     = 'FSI Agent Governance Framework'
    frameworkVersion = 'v1.6.0'
    moduleVersion    = '2.0.3'
    solutions     = @{}
    fileHashes    = @{}
    masterHash    = $null
}

$allHashes = @()

foreach ($sol in $Solutions) {
    $solKey = $sol.ToLower()
    $solDir = Join-Path $exportDir $solKey
    New-Item -Path $solDir -ItemType Directory -Force | Out-Null

    $tables = $SolutionEvidence[$sol]
    Write-Host "`nExporting $sol..." -ForegroundColor Cyan

    # Validations
    $vFilter = "$($tables.Validations.DateField) ge $startStr and $($tables.Validations.DateField) lt $endStr"
    $validations = Get-DataverseRecords -Connection $connection `
        -EntitySet $tables.Validations.EntitySet `
        -Filter $vFilter `
        -Fields $tables.Validations.Fields `
        -DateField $tables.Validations.DateField

    $vPath = Join-Path $solDir 'validations.csv'
    Export-ToCsv -Records $validations -FilePath $vPath -Fields $tables.Validations.Fields
    $vHash = Get-FileHashSHA256 -FilePath $vPath
    Write-Host "  Validations: $($validations.Count) records" -ForegroundColor Green

    # Record manifest entries
    $manifest.solutions[$solKey] = @{
        validationCount = $validations.Count
        exportedAt      = (Get-IsoUtcTimestamp)
    }

    $manifest.fileHashes["$solKey/validations.csv"] = $vHash
    $allHashes += $vHash
}

# Calculate master hash (SHA-256 of sorted concatenated file hashes)
$sortedHashes = ($allHashes | Sort-Object) -join ''
$hashBytes = [System.Text.Encoding]::UTF8.GetBytes($sortedHashes)
$sha = [System.Security.Cryptography.SHA256]::Create()
$masterHashBytes = $sha.ComputeHash($hashBytes)
$manifest.masterHash = [System.BitConverter]::ToString($masterHashBytes) -replace '-', ''

# Write manifest
$manifestPath = Join-Path $exportDir 'manifest.json'
$manifest | ConvertTo-Json -Depth 5 | Out-File -FilePath $manifestPath -Encoding utf8

Write-Host "`n=================================" -ForegroundColor Cyan
Write-Host "Evidence export complete!" -ForegroundColor Cyan
Write-Host "  Location:    $exportDir" -ForegroundColor Gray
Write-Host "  Solutions:   $($Solutions.Count)" -ForegroundColor Gray
Write-Host "  Master Hash: $($manifest.masterHash.Substring(0,16))..." -ForegroundColor Gray
Write-Host "  Manifest:    $manifestPath" -ForegroundColor Gray
Write-Host "`n" -ForegroundColor Cyan

#endregion
