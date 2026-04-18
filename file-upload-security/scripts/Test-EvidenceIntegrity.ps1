#Requires -Version 7.4

<#
.SYNOPSIS
    Verifies the integrity of a File Upload Security evidence export file.

.DESCRIPTION
    Reads the SHA-256 hash from a companion .sha256 file and compares it to
    the computed hash of the evidence JSON file. Returns $true if the hashes
    match, indicating the file has not been modified since export.

    Supports SEC 17a-4(f) compliance by providing tamper-evident verification.

.PARAMETER EvidenceFilePath
    Path to the evidence JSON file.

.PARAMETER HashFilePath
    Path to the SHA-256 hash file. Defaults to {EvidenceFilePath}.sha256.

.PARAMETER Quiet
    Suppress output; only return $true/$false.

.EXAMPLE
    .\Test-EvidenceIntegrity.ps1 -EvidenceFilePath .\FUS-Evidence-20260210.json
    Verify evidence file integrity.

.NOTES
    Part of FSI Agent Governance Framework - File Upload Security Configurator
    Control: 1.14 - Data Minimization and Agent Scope Control
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$EvidenceFilePath,

    [Parameter()]
    [string]$HashFilePath,

    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

if (-not (Test-Path $EvidenceFilePath)) {
    throw "Evidence file not found: $EvidenceFilePath"
}

if (-not $HashFilePath) {
    $HashFilePath = "$EvidenceFilePath.sha256"
}

if (-not (Test-Path $HashFilePath)) {
    throw "Hash file not found: $HashFilePath"
}

# Read expected hash (first field of hash file)
$hashContent = (Get-Content $HashFilePath -Raw).Trim()
$expectedHash = ($hashContent -split '\s+')[0].ToUpperInvariant()

# Compute actual hash
$actualHash = (Get-FileHash -Path $EvidenceFilePath -Algorithm SHA256).Hash.ToUpperInvariant()

$isValid = $expectedHash -eq $actualHash

if (-not $Quiet) {
    if ($isValid) {
        Write-Host "VERIFIED: Evidence file integrity confirmed." -ForegroundColor Green
        Write-Host "  File:     $(Split-Path $EvidenceFilePath -Leaf)" -ForegroundColor Green
        Write-Host "  SHA-256:  $actualHash" -ForegroundColor Green
    } else {
        Write-Host "FAILED: Evidence file integrity check failed!" -ForegroundColor Red
        Write-Host "  Expected: $expectedHash" -ForegroundColor Red
        Write-Host "  Actual:   $actualHash" -ForegroundColor Red
        Write-Host "  File may have been modified since export." -ForegroundColor Red
    }
}

return $isValid
