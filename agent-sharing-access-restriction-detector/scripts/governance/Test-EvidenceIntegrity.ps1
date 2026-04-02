<#
.SYNOPSIS
    Verifies SHA-256 integrity of ASARD sharing compliance evidence files.

.DESCRIPTION
    Validates the cryptographic integrity of JSON evidence files by comparing
    the computed SHA-256 hash against the expected hash stored in the companion
    .sha256 file.

    Returns boolean result for automation compatibility, with optional console
    output for interactive verification workflows.

    Evidence files produced by Export-SharingComplianceEvidence include SHA-256
    companion files that enable tamper detection. This verification script
    supports compliance workflows by confirming evidence files have not been
    modified after export.

    Hash verification aids in meeting evidence integrity requirements for
    FINRA Rule 4511, SEC Rule 17a-4, and SOX Section 302/404.

.PARAMETER EvidenceFilePath
    Full path to the JSON evidence file to verify. Must exist.

.PARAMETER HashFilePath
    Optional path to the SHA-256 companion file. If not specified, defaults
    to "{EvidenceFilePath}.sha256" following the standard naming convention.

.PARAMETER Quiet
    Suppress console output. Returns only the boolean result ($true/$false).
    Useful for batch verification scripts and automated workflows.

.EXAMPLE
    .\Test-EvidenceIntegrity.ps1 -EvidenceFilePath ".\evidence\asard-evidence-All-20260301-143022.json"

    Verifies the integrity of a single evidence file using the default companion
    hash file location. Displays verification result to console and returns boolean.

.EXAMPLE
    Get-ChildItem .\evidence\asard-evidence-*.json | ForEach-Object {
        .\Test-EvidenceIntegrity.ps1 -EvidenceFilePath $_.FullName
    }

    Batch verification of all ASARD evidence files in a directory.

.EXAMPLE
    $isValid = .\Test-EvidenceIntegrity.ps1 `
        -EvidenceFilePath ".\evidence\asard-evidence-All-20260301-143022.json" `
        -Quiet

    if ($isValid) {
        Write-Host "Evidence file is valid" -ForegroundColor Green
    } else {
        Write-Host "Evidence file integrity check FAILED" -ForegroundColor Red
    }

    Quiet mode for automation. Returns boolean without console output, allowing
    calling script to handle verification result programmatically.

.OUTPUTS
    Boolean - $true if hash matches (file integrity verified), $false if mismatch.

.NOTES
    File: Test-EvidenceIntegrity.ps1
    Version: 1.0.0
    Solution: Agent Sharing Access Restriction Detector (ASARD)
    Controls: 1.18 (Application-Level Authorization), 2.8 (Access Control/Segregation of Duties)

    SHA-256 companion file format:
    - First field: 64-character hex hash
    - Two spaces
    - Second field: Filename
    - Example: "abc123...  asard-evidence-All-20260301-143022.json"

    This format is compatible with standard checksum tools (shasum, certutil,
    sha256sum) enabling cross-platform verification and audit workflows.

    Regulatory context:
    Hash verification supports evidence integrity requirements for:
    - FINRA Rule 4511 (audit trail accuracy)
    - SEC Rule 17a-4 (record integrity)
    - SOX Section 302/404 (internal control verification)

    Part of FSI Agent Governance Framework
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateScript({ Test-Path -Path $_ -PathType Leaf })]
    [string]$EvidenceFilePath,

    [Parameter()]
    [string]$HashFilePath,

    [Parameter()]
    [switch]$Quiet
)

$ErrorActionPreference = 'Stop'

try {
    # Determine hash file path (use parameter or default convention)
    if (-not $HashFilePath) {
        $HashFilePath = "$EvidenceFilePath.sha256"
    }

    # Validate hash file exists
    if (-not (Test-Path -Path $HashFilePath -PathType Leaf)) {
        throw "Hash file not found: $HashFilePath. Expected companion file with .sha256 extension."
    }

    # Read expected hash from companion file
    # Format: "{hash}  {filename}" (two spaces)
    $hashFileContent = Get-Content -Path $HashFilePath -Raw
    $expectedHash = ($hashFileContent -split '\s+')[0].Trim()

    if (-not $expectedHash -or $expectedHash.Length -ne 64) {
        throw "Invalid hash file format. Expected 64-character SHA-256 hash in file: $HashFilePath"
    }

    # Compute actual hash of evidence file
    $actualHashResult = Get-FileHash -Path $EvidenceFilePath -Algorithm SHA256
    $actualHash = $actualHashResult.Hash

    # Compare hashes (case-insensitive)
    if ($actualHash -eq $expectedHash) {
        if (-not $Quiet) {
            Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Green
            Write-Host "║       Evidence Integrity: VERIFIED              ║" -ForegroundColor Green
            Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Green
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
            Write-Warning "╔══════════════════════════════════════════════════╗"
            Write-Warning "║       Evidence Integrity: FAILED                ║"
            Write-Warning "╚══════════════════════════════════════════════════╝"
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
