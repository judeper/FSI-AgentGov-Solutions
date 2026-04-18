<#
.SYNOPSIS
    Verifies the integrity of a unified compliance evidence export package.

.DESCRIPTION
    Reads manifest.json from an evidence export directory, recalculates SHA-256
    hashes for all referenced files, and validates against the recorded values
    and master hash chain. Returns exit code 0 (pass) or 1 (fail).

.PARAMETER ExportPath
    Path to the evidence export directory (contains manifest.json).

.PARAMETER Detailed
    Show per-file hash comparison details.

.EXAMPLE
    .\Test-UnifiedEvidenceIntegrity.ps1 -ExportPath ".\evidence-export-2026-02-01-140000"

.EXAMPLE
    .\Test-UnifiedEvidenceIntegrity.ps1 -ExportPath ".\evidence-export-2026-02-01-140000" -Detailed

.NOTES
    Version: 2.0.0
    Date: 2026-04-16
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ExportPath,

    [switch]$Detailed
)

$ErrorActionPreference = 'Stop'

Write-Host "`nTest-UnifiedEvidenceIntegrity" -ForegroundColor Cyan
Write-Host "==============================`n" -ForegroundColor Cyan

# Read manifest
$manifestPath = Join-Path $ExportPath 'manifest.json'
if (-not (Test-Path $manifestPath)) {
    Write-Host "[FAIL] manifest.json not found in: $ExportPath" -ForegroundColor Red
    exit 1
}

try {
    $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
} catch {
    Write-Error "manifest.json is not valid JSON. Ensure the file is properly formatted. Error: $($_.Exception.Message)"
    exit 1
}

Write-Host "Export ID:    $($manifest.exportId)" -ForegroundColor Gray
Write-Host "Export Date:  $($manifest.exportDate)" -ForegroundColor Gray
Write-Host "Period:       $($manifest.periodStart) to $($manifest.periodEnd)" -ForegroundColor Gray
Write-Host "Framework:    $($manifest.framework) $($manifest.frameworkVersion)" -ForegroundColor Gray
Write-Host ""

# Verify individual file hashes
$failed = 0
$passed = 0
$allHashes = @()

$fileHashes = $manifest.fileHashes | Get-Member -MemberType NoteProperty | ForEach-Object {
    @{ Name = $_.Name; ExpectedHash = $manifest.fileHashes.($_.Name) }
} | Sort-Object { $_.Name }

foreach ($entry in $fileHashes) {
    $filePath = Join-Path $ExportPath $entry.Name.Replace('/', [System.IO.Path]::DirectorySeparatorChar)

    if (-not (Test-Path $filePath)) {
        Write-Host "[FAIL] Missing file: $($entry.Name)" -ForegroundColor Red
        $failed++
        continue
    }

    $actualHash = (Get-FileHash -Path $filePath -Algorithm SHA256).Hash

    if ($actualHash -eq $entry.ExpectedHash) {
        if ($Detailed) {
            Write-Host "[PASS] $($entry.Name)" -ForegroundColor Green
            Write-Host "       Hash: $($actualHash.Substring(0,16))..." -ForegroundColor Gray
        }
        $passed++
        $allHashes += $actualHash
    } else {
        Write-Host "[FAIL] $($entry.Name)" -ForegroundColor Red
        Write-Host "       Expected: $($entry.ExpectedHash.Substring(0,16))..." -ForegroundColor Yellow
        Write-Host "       Actual:   $($actualHash.Substring(0,16))..." -ForegroundColor Yellow
        $failed++
        $allHashes += $actualHash
    }
}

# Verify master hash chain
Write-Host ""
$sortedHashes = ($allHashes | Sort-Object) -join ''
$hashBytes = [System.Text.Encoding]::UTF8.GetBytes($sortedHashes)
$sha = [System.Security.Cryptography.SHA256]::Create()
$masterHashBytes = $sha.ComputeHash($hashBytes)
$calculatedMaster = [System.BitConverter]::ToString($masterHashBytes) -replace '-', ''

if ($calculatedMaster -eq $manifest.masterHash) {
    Write-Host "[PASS] Master hash chain verified" -ForegroundColor Green
    if ($Detailed) {
        Write-Host "       Hash: $($calculatedMaster.Substring(0,16))..." -ForegroundColor Gray
    }
} else {
    Write-Host "[FAIL] Master hash chain MISMATCH" -ForegroundColor Red
    Write-Host "       Expected: $($manifest.masterHash.Substring(0,16))..." -ForegroundColor Yellow
    Write-Host "       Actual:   $($calculatedMaster.Substring(0,16))..." -ForegroundColor Yellow
    $failed++
}

# Summary
Write-Host "`n==============================" -ForegroundColor Cyan
$total = $passed + $failed
Write-Host "Files verified: $($fileHashes.Count) | Total checks (incl. master hash): $($total)" -ForegroundColor Gray
Write-Host "Passed: $passed | Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { 'Red' } else { 'Green' })

if ($failed -gt 0) {
    Write-Host "`nVERDICT: FAIL — Evidence package integrity compromised." -ForegroundColor Red
    exit 1
} else {
    Write-Host "`nVERDICT: PASS — Evidence package integrity verified." -ForegroundColor Green
    exit 0
}
