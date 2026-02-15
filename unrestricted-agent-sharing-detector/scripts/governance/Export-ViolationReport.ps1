#Requires -Version 7.0
#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    Exports UASD violation records from Dataverse.

.DESCRIPTION
    Queries the fsi_SharingViolation Dataverse table and exports records
    to CSV or JSON format. Supports evidence hash inclusion for audit
    packaging and optional exception record join.

.PARAMETER DataverseUrl
    Dataverse environment URL (e.g., https://org.crm.dynamics.com)

.PARAMETER OutputPath
    File path for the exported report

.PARAMETER OutputFormat
    Output format: JSON or CSV (default: CSV)

.PARAMETER IncludeEvidence
    Include SHA-256 evidence hash in export

.PARAMETER IncludeExceptions
    Include related exception records in export

.PARAMETER TenantId
    Entra ID tenant GUID (optional)

.PARAMETER DaysBack
    Number of days of history to export (default: 90)

.EXAMPLE
    .\Export-ViolationReport.ps1 -DataverseUrl "https://org.crm.dynamics.com" -OutputPath .\violations.csv

.EXAMPLE
    .\Export-ViolationReport.ps1 -DataverseUrl "https://org.crm.dynamics.com" -OutputFormat JSON -OutputPath .\evidence.json -IncludeEvidence -IncludeExceptions

.NOTES
    FSI Agent Governance Framework - Unrestricted Agent Sharing Detector
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter()]
    [string]$OutputPath = ".\uasd-violations-report.csv",

    [Parameter()]
    [ValidateSet("JSON", "CSV")]
    [string]$OutputFormat = "CSV",

    [Parameter()]
    [switch]$IncludeEvidence,

    [Parameter()]
    [switch]$IncludeExceptions,

    [Parameter()]
    [string]$TenantId,

    [Parameter()]
    [int]$DaysBack = 90
)

$ErrorActionPreference = "Stop"

Write-Host "`n[UASD Violation Report Export]" -ForegroundColor Cyan
Write-Host "  Source: $DataverseUrl"

# --- Authentication ---
if (-not (Get-AzContext)) {
    Write-Host "  Authenticating..." -ForegroundColor Yellow
    if ($TenantId) { Connect-AzAccount -TenantId $TenantId | Out-Null }
    else { Connect-AzAccount | Out-Null }
}

$token = (Get-AzAccessToken -ResourceUrl $DataverseUrl).Token
$headers = @{
    "Authorization"    = "Bearer $token"
    "Content-Type"     = "application/json"
    "OData-Version"    = "4.0"
    "OData-MaxVersion" = "4.0"
    "Accept"           = "application/json"
    "Prefer"           = "odata.include-annotations=*,odata.maxpagesize=500"
}

$apiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"

# --- Query Violations ---
Write-Host "  Querying violations (last $DaysBack days)..." -ForegroundColor Gray

$cutoffDate = (Get-Date).AddDays(-$DaysBack).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$select = "fsi_name,fsi_agent_id,fsi_agent_name,fsi_environment_id,fsi_environment_name,fsi_violation_type,fsi_violation_status,fsi_severity,fsi_description,fsi_detected_at,fsi_remediated_at,fsi_remediation_result,fsi_scan_run_id"

if ($IncludeEvidence) {
    $select += ",fsi_evidence_json,fsi_principal_details"
}

$filter = "fsi_detected_at ge $cutoffDate"
$url = "$apiBase/fsi_sharingviolations?`$select=$select&`$filter=$filter&`$orderby=fsi_detected_at desc"

$violations = [System.Collections.ArrayList]::new()
while ($url) {
    try {
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get
        foreach ($record in $response.value) {
            [void]$violations.Add($record)
        }
        $url = $response.'@odata.nextLink'
    } catch {
        Write-Host "  ERROR: Failed to query violations - $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
}

Write-Host "  Violations retrieved: $($violations.Count)"

# --- Query Exceptions (if requested) ---
$exceptions = @()
if ($IncludeExceptions) {
    Write-Host "  Querying exceptions..." -ForegroundColor Gray
    $exUrl = "$apiBase/fsi_sharingexceptions?`$orderby=fsi_requested_at desc"
    $exList = [System.Collections.ArrayList]::new()
    while ($exUrl) {
        try {
            $exResponse = Invoke-RestMethod -Uri $exUrl -Headers $headers -Method Get
            foreach ($record in $exResponse.value) {
                [void]$exList.Add($record)
            }
            $exUrl = $exResponse.'@odata.nextLink'
        } catch {
            Write-Host "  Warning: Failed to query exceptions - $($_.Exception.Message)" -ForegroundColor Yellow
            break
        }
    }
    $exceptions = $exList.ToArray()
    Write-Host "  Exceptions retrieved: $($exceptions.Count)"
}

# --- Compute Evidence Hashes ---
if ($IncludeEvidence) {
    Write-Host "  Computing evidence hashes..." -ForegroundColor Gray
    foreach ($v in $violations) {
        if ($v.fsi_evidence_json) {
            $hashBytes = [System.Security.Cryptography.SHA256]::HashData(
                [System.Text.Encoding]::UTF8.GetBytes($v.fsi_evidence_json)
            )
            $v | Add-Member -NotePropertyName "evidence_hash" -NotePropertyValue (
                [System.BitConverter]::ToString($hashBytes).Replace("-", "").ToLower()
            ) -Force
        }
    }
}

# --- Write Output ---
$outputDir = Split-Path -Path $OutputPath -Parent
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

if ($OutputFormat -eq "CSV") {
    $OutputPath = [System.IO.Path]::ChangeExtension($OutputPath, ".csv")
    $violations | ForEach-Object { [PSCustomObject]$_ } | Export-Csv -Path $OutputPath -NoTypeInformation
    Write-Host "  Violations exported: $OutputPath" -ForegroundColor Green

    if ($IncludeExceptions -and $exceptions.Count -gt 0) {
        $exPath = $OutputPath -replace '\.csv$', '-exceptions.csv'
        $exceptions | ForEach-Object { [PSCustomObject]$_ } | Export-Csv -Path $exPath -NoTypeInformation
        Write-Host "  Exceptions exported: $exPath" -ForegroundColor Green
    }
} else {
    $OutputPath = [System.IO.Path]::ChangeExtension($OutputPath, ".json")
    $report = @{
        export_timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        source           = $DataverseUrl
        days_back        = $DaysBack
        violations       = $violations.ToArray()
    }
    if ($IncludeExceptions) {
        $report["exceptions"] = $exceptions
    }
    $report | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding utf8
    Write-Host "  Report exported: $OutputPath" -ForegroundColor Green
}

Write-Host "`n  Export: COMPLETE" -ForegroundColor Green
