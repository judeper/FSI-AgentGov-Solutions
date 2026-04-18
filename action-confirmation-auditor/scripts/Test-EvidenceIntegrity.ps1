#Requires -Version 5.1

<#
.SYNOPSIS
    Verifies SHA-256 integrity of action confirmation audit evidence files.

.DESCRIPTION
    Validates the cryptographic integrity of JSON evidence files by comparing
    the computed SHA-256 hash against the expected hash stored in the companion
    .sha256 file.

    Returns boolean result for automation compatibility, with optional console
    output for interactive verification workflows.

    Evidence files produced by Export-ActionAuditEvidence include SHA-256
    companion files that enable tamper detection. This verification script
    supports compliance workflows by confirming evidence files have not been
    modified after export.

    Hash verification aids in meeting evidence integrity requirements for
    FINRA Rule 4511, SEC Rule 17a-4, and SOX Section 302/404.

.PARAMETER EvidenceFilePath
    Full path to the JSON evidence file to verify.

.PARAMETER HashFilePath
    Optional path to the SHA-256 companion file. If not specified, defaults
    to "{EvidenceFilePath}.sha256" following the standard naming convention.

.PARAMETER Quiet
    Suppress console output. Returns only the boolean result ($true/$false).

.EXAMPLE
    .\Test-EvidenceIntegrity.ps1 -EvidenceFilePath ".\evidence\aca-evidence-All-20260210-143022.json"

.EXAMPLE
    Get-ChildItem .\evidence\aca-evidence-*.json | ForEach-Object {
        .\Test-EvidenceIntegrity.ps1 -EvidenceFilePath $_.FullName
    }

.OUTPUTS
    Boolean - $true if hash matches (file integrity verified), $false if mismatch.

.NOTES
    Version: 1.1.0
    Solution: Action Confirmation Auditor (ACA)
    Requires PowerShell 5.1 or later (Get-FileHash cmdlet availability).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EvidenceFilePath,

    [Parameter(Mandatory = $false)]
    [string]$HashFilePath,

    [Parameter(Mandatory = $false)]
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

try {
    if (-not (Test-Path -Path $EvidenceFilePath -PathType Leaf)) {
        throw "Evidence file not found: $EvidenceFilePath"
    }

    if (-not $HashFilePath) {
        $HashFilePath = "$EvidenceFilePath.sha256"
    }

    if (-not (Test-Path -Path $HashFilePath -PathType Leaf)) {
        throw "Hash file not found: $HashFilePath. Expected companion file with .sha256 extension."
    }

    $hashFileContent = Get-Content -Path $HashFilePath -Raw
    $expectedHash = ($hashFileContent -split '\s+')[0].Trim()

    if (-not $expectedHash -or $expectedHash.Length -ne 64) {
        throw "Invalid hash file format. Expected 64-character SHA-256 hash in file: $HashFilePath"
    }

    $actualHashResult = Get-FileHash -Path $EvidenceFilePath -Algorithm SHA256
    $actualHash = $actualHashResult.Hash

    if ($actualHash -eq $expectedHash) {
        if (-not $Quiet) {
            Write-Host "========================================" -ForegroundColor Green
            Write-Host "  Evidence Integrity: VERIFIED" -ForegroundColor Green
            Write-Host "========================================" -ForegroundColor Green
            Write-Host ""
            Write-Host "Evidence file: $(Split-Path -Leaf $EvidenceFilePath)" -ForegroundColor Green
            Write-Host "SHA-256 hash:  $actualHash" -ForegroundColor Green
            Write-Host ""
            Write-Host "File integrity confirmed. Evidence has not been modified." -ForegroundColor Green
        }
        return $true
    }
    else {
        if (-not $Quiet) {
            Write-Warning "========================================"
            Write-Warning "  Evidence Integrity: FAILED"
            Write-Warning "========================================"
            Write-Warning ""
            Write-Warning "Evidence file: $(Split-Path -Leaf $EvidenceFilePath)"
            Write-Warning "Expected hash: $expectedHash"
            Write-Warning "Actual hash:   $actualHash"
            Write-Warning ""
            Write-Warning "INTEGRITY CHECK FAILED. Evidence file may have been modified or corrupted."
        }
        return $false
    }
}
catch {
    if (-not $Quiet) {
        Write-Error "Evidence integrity verification failed: $($_.Exception.Message)"
    }
    throw
}
