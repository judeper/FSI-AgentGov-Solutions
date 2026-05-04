#Requires -Version 7.0

<#
.SYNOPSIS
    Verifies SHA-256 integrity of Message Center Monitor evidence files.

.DESCRIPTION
    Validates the cryptographic integrity of JSON evidence files by comparing
    the computed SHA-256 hash against the expected hash stored in the companion
    .sha256 file.

    Returns boolean result for automation compatibility, with optional console
    output for interactive verification workflows.

    Internal evidence integrity for change-tracking workflows. Confirms
    machine-readable JSON artifacts produced by Export-MessageCenterEvidence.ps1
    have not been modified after export (operational, not regulatory).

.PARAMETER EvidenceFilePath
    Full path to the JSON evidence file to verify.

.PARAMETER HashFilePath
    Optional path to the SHA-256 companion file. If not specified, defaults
    to "{EvidenceFilePath}.sha256" following the standard naming convention.

.PARAMETER Quiet
    Suppress console output. Returns only the boolean result ($true/$false).
    In Quiet mode, errors (missing files, invalid hash file) are written to the
    verbose stream and the function returns $false; the script also exits with
    a non-zero exit code so batch callers can detect failure.

.EXAMPLE
    .\Test-EvidenceIntegrity.ps1 -EvidenceFilePath ".\evidence\mcm-evidence-20260209-143022.json"

    Verifies the integrity of a single evidence file using the default companion
    hash file location. Displays verification result to console and returns boolean.

.EXAMPLE
    Get-ChildItem .\evidence\mcm-evidence-*.json | ForEach-Object {
        .\Test-EvidenceIntegrity.ps1 -EvidenceFilePath $_.FullName
    }

    Batch verification of all MCM evidence files in a directory. Iterates through
    all matching JSON files and verifies each one against its companion hash file.

.EXAMPLE
    $isValid = .\Test-EvidenceIntegrity.ps1 `
        -EvidenceFilePath ".\evidence\mcm-evidence-20260209-143022.json" `
        -Quiet

    if ($isValid) {
        Write-Host "Evidence file is valid" -ForegroundColor Green
    } else {
        Write-Host "Evidence file integrity check FAILED" -ForegroundColor Red
    }

    Quiet mode for automation. Returns boolean without console output, allowing
    calling script to handle verification result programmatically.

.OUTPUTS
    Boolean - $true if hash matches (file integrity verified), $false otherwise.

.NOTES
    Version: 2.5.1
    Requires PowerShell 7.0 or later (Get-FileHash cmdlet availability).

    SHA-256 companion file format:
    - First field: 64-character hex hash
    - Two spaces
    - Second field: Filename
    - Example: "abc123...  mcm-evidence-20260209-143022.json"

    This format is compatible with standard checksum tools (shasum, certutil,
    sha256sum) enabling cross-platform verification workflows.
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
    # Validate evidence file exists
    if (-not (Test-Path -Path $EvidenceFilePath -PathType Leaf)) {
        throw "Evidence file not found: $EvidenceFilePath"
    }

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
        # Integrity verified
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
        # Hash mismatch — evidence may be tampered
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
        } else {
            Write-Verbose "Hash mismatch for $EvidenceFilePath (expected $expectedHash, got $actualHash)"
        }
        $script:LASTEXITCODE = 1
        return $false
    }
}
catch {
    # Honor the .OUTPUTS Boolean contract: in Quiet mode return $false and exit
    # non-zero rather than throwing, so batch callers can rely on the boolean.
    if ($Quiet) {
        Write-Verbose "Evidence integrity verification failed: $($_.Exception.Message)"
        $script:LASTEXITCODE = 1
        return $false
    }
    Write-Error "Evidence integrity verification failed: $($_.Exception.Message)"
    throw
}
