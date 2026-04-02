<#
.SYNOPSIS
    Exports unified compliance evidence from all Tier 2 governance solutions.

.DESCRIPTION
    Queries each Tier 2 solution's Dataverse tables for validation and violation
    records, exports them as CSV files, and generates a master manifest with
    SHA-256 hash chain suitable for FINRA 4511 / SEC 17a-4 audit evidence packages.

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
    App registration client ID for service principal auth.

.PARAMETER ClientSecret
    App registration client secret.

.PARAMETER Interactive
    Use interactive authentication.

.PARAMETER DryRun
    Show export plan without querying Dataverse.

.EXAMPLE
    .\Export-UnifiedComplianceEvidence.ps1 -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "guid" -OutputPath "C:\evidence" -Interactive

.EXAMPLE
    .\Export-UnifiedComplianceEvidence.ps1 -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "guid" -Solutions ACV,SSC -StartDate "2026-01-01" -Interactive

.NOTES
    Version: 1.0.0
    Date: 2026-02-10
    Requires: IntegrationConfig.psm1
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

    [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory)]
    [string]$ClientId,

    [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory)]
    [SecureString]$ClientSecret,

    [Parameter(ParameterSetName = 'Interactive')]
    [switch]$Interactive,

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
    ACV = @{
        Validations = @{
            EntitySet = 'fsi_auditvalidationhistories'
            DateField = 'fsi_scannedon'
            Fields    = @('fsi_name', 'fsi_scannedon', 'fsi_settingname', 'fsi_expectedvalue', 'fsi_actualvalue', 'fsi_severity', 'fsi_environmentname', 'fsi_zone')
        }
        Violations  = @{
            EntitySet = 'fsi_auditvalidationviolations'
            DateField = 'fsi_detectedon'
            Fields    = @('fsi_name', 'fsi_detectedon', 'fsi_settingname', 'fsi_severity', 'fsi_status', 'fsi_environmentname', 'fsi_zone')
        }
    }
    SSC = @{
        Validations = @{
            EntitySet = 'fsi_validationhistories'
            DateField = 'fsi_scannedon'
            Fields    = @('fsi_name', 'fsi_scannedon', 'fsi_policyname', 'fsi_expectedvalue', 'fsi_actualvalue', 'fsi_severity')
        }
        Violations  = @{
            EntitySet = 'fsi_driftviolations'
            DateField = 'fsi_detectedon'
            Fields    = @('fsi_name', 'fsi_detectedon', 'fsi_policyname', 'fsi_severity', 'fsi_status')
        }
    }
    AAM = @{
        Validations = @{
            EntitySet = 'fsi_accessvalidationhistories'
            DateField = 'fsi_scannedon'
            Fields    = @('fsi_name', 'fsi_scannedon', 'fsi_agentname', 'fsi_permissiontype', 'fsi_expectedaccess', 'fsi_actualaccess', 'fsi_severity')
        }
        Violations  = @{
            EntitySet = 'fsi_accessviolations'
            DateField = 'fsi_detectedon'
            Fields    = @('fsi_name', 'fsi_detectedon', 'fsi_agentname', 'fsi_severity', 'fsi_status')
        }
    }
    CMM = @{
        Validations = @{
            EntitySet = 'fsi_moderationvalidationhistories'
            DateField = 'fsi_scannedon'
            Fields    = @('fsi_name', 'fsi_scannedon', 'fsi_agentname', 'fsi_moderationpolicy', 'fsi_expectedconfig', 'fsi_actualconfig', 'fsi_severity')
        }
        Violations  = @{
            EntitySet = 'fsi_moderationviolations'
            DateField = 'fsi_detectedon'
            Fields    = @('fsi_name', 'fsi_detectedon', 'fsi_agentname', 'fsi_severity', 'fsi_status')
        }
    }
    FUS = @{
        Validations = @{
            EntitySet = 'fsi_fileuploadvalidationhistories'
            DateField = 'fsi_scannedon'
            Fields    = @('fsi_name', 'fsi_scannedon', 'fsi_settingname', 'fsi_expectedvalue', 'fsi_actualvalue', 'fsi_severity')
        }
        Violations  = @{
            EntitySet = 'fsi_fileuploadviolations'
            DateField = 'fsi_detectedon'
            Fields    = @('fsi_name', 'fsi_detectedon', 'fsi_settingname', 'fsi_severity', 'fsi_status')
        }
    }
    CAA = @{
        Validations = @{
            EntitySet = 'fsi_capolicyvalidationhistories'
            DateField = 'fsi_scannedon'
            Fields    = @('fsi_name', 'fsi_scannedon', 'fsi_policyname', 'fsi_expectedvalue', 'fsi_actualvalue', 'fsi_severity')
        }
        Violations  = @{
            EntitySet = 'fsi_capolicyviolations'
            DateField = 'fsi_detectedon'
            Fields    = @('fsi_name', 'fsi_detectedon', 'fsi_policyname', 'fsi_severity', 'fsi_status')
        }
    }
}

#endregion

#region Query and Export Functions

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
                $statusCode = $_.Exception.Response.StatusCode.value__
                if ($statusCode -in @(429, 503) -and $retryCount -lt $maxRetries) {
                    $delay = [math]::Pow(2, $retryCount) * 5
                    Write-Warning "Transient error ($statusCode) querying $EntitySet — retrying in ${delay}s (attempt $retryCount/$maxRetries)"
                    Start-Sleep -Seconds $delay
                } else {
                    throw
                }
            }
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

$startStr = $StartDate.ToString('yyyy-MM-dd')
$endStr = $EndDate.AddDays(1).ToString('yyyy-MM-dd')
$exportDir = Join-Path $OutputPath "evidence-export-$(Get-Date -Format 'yyyy-MM-dd-HHmmss')"

Write-Host "Period: $startStr to $endStr" -ForegroundColor Gray
Write-Host "Solutions: $($Solutions -join ', ')" -ForegroundColor Gray
Write-Host "Output: $exportDir" -ForegroundColor Gray

if ($DryRun) {
    Write-Host "`n[DryRun] Export plan:" -ForegroundColor Yellow
    foreach ($sol in $Solutions) {
        $tables = $SolutionEvidence[$sol]
        Write-Host "  $sol:" -ForegroundColor Yellow
        Write-Host "    Validations: $($tables.Validations.EntitySet)" -ForegroundColor Yellow
        Write-Host "    Violations:  $($tables.Violations.EntitySet)" -ForegroundColor Yellow
    }
    Write-Host "`n[DryRun] No data exported.`n" -ForegroundColor Yellow
    return
}

# Connect
Write-Host "`nConnecting to Dataverse..." -ForegroundColor Gray
$connection = Connect-DataverseApi -Url $DataverseUrl -TenantId $TenantId `
    -ClientId $ClientId -ClientSecret $ClientSecret -Interactive:$Interactive

# Create output directory
New-Item -Path $exportDir -ItemType Directory -Force | Out-Null

$manifest = @{
    exportId      = [guid]::NewGuid().ToString()
    exportDate    = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
    periodStart   = $startStr
    periodEnd     = $endStr
    framework     = 'FSI Agent Governance Framework'
    frameworkVersion = 'v1.2.38'
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

    # Violations
    $xFilter = "$($tables.Violations.DateField) ge $startStr and $($tables.Violations.DateField) lt $endStr"
    $violations = Get-DataverseRecords -Connection $connection `
        -EntitySet $tables.Violations.EntitySet `
        -Filter $xFilter `
        -Fields $tables.Violations.Fields `
        -DateField $tables.Violations.DateField

    $xPath = Join-Path $solDir 'violations.csv'
    Export-ToCsv -Records $violations -FilePath $xPath -Fields $tables.Violations.Fields
    $xHash = Get-FileHashSHA256 -FilePath $xPath
    Write-Host "  Violations:  $($violations.Count) records" -ForegroundColor Green

    # Record manifest entries
    $manifest.solutions[$solKey] = @{
        validationCount = $validations.Count
        violationCount  = $violations.Count
        exportedAt      = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
    }

    $manifest.fileHashes["$solKey/validations.csv"] = $vHash
    $manifest.fileHashes["$solKey/violations.csv"]  = $xHash
    $allHashes += $vHash
    $allHashes += $xHash
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
