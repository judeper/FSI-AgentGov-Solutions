#Requires -Version 5.1

<#
.SYNOPSIS
    Verifies SHA-256 integrity of HITL workflow governance evidence files.

.DESCRIPTION
    Validates the cryptographic integrity of JSON evidence files exported by
    Export-HitlGovernanceEvidence by reading manifest.json and verifying each
    listed file's SHA-256 hash against its companion .sha256 sidecar.

    Returns boolean result for automation compatibility, with detailed console
    output for interactive verification workflows.

    Evidence files produced by Export-HitlGovernanceEvidence include SHA-256
    companion files that enable tamper detection. This verification script
    supports compliance workflows by confirming evidence files have not been
    modified after export.

    Hash verification aids in meeting evidence integrity requirements for
    FINRA Rule 4511, SEC Rule 17a-4, and SOX Section 302/404.

.PARAMETER EvidencePath
    Full path to the evidence directory containing manifest.json and
    companion .sha256 files.

.PARAMETER Quiet
    Suppress console output. Returns only the boolean result ($true/$false).

.EXAMPLE
    .\Test-EvidenceIntegrity.ps1 -EvidencePath ".\evidence"

    Verifies all evidence files in the directory against manifest.json.

.EXAMPLE
    .\Test-EvidenceIntegrity.ps1 -EvidencePath ".\evidence" -Quiet

    Silent verification — returns $true or $false without console output.

.OUTPUTS
    Boolean - $true if all file hashes match (evidence integrity verified),
    $false if any mismatch is detected.

.NOTES
    Version: 1.0.0
    Solution: HITL Workflow Governance (HWG)
    Controls: 2.12 (Supervision/FINRA Rule 3110), 2.17 (Multi-Agent Orchestration), 1.10 (Communication Compliance)
    Requires PowerShell 5.1 or later (Get-FileHash cmdlet availability).
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$EvidencePath,

    [Parameter(Mandatory = $false)]
    [switch]$Quiet
)

$ErrorActionPreference = "Stop"

try {
    if (-not (Test-Path -Path $EvidencePath -PathType Container)) {
        throw "Evidence directory not found: $EvidencePath"
    }

    # Read manifest.json
    $manifestPath = Join-Path -Path $EvidencePath -ChildPath "manifest.json"

    if (-not (Test-Path -Path $manifestPath -PathType Leaf)) {
        throw "manifest.json not found in: $EvidencePath"
    }

    $manifest = Get-Content -Path $manifestPath -Raw | ConvertFrom-Json

    if (-not $manifest.files) {
        throw "manifest.json does not contain a 'files' section."
    }

    $allPassed = $true
    $fileCount = 0
    $passCount = 0
    $failCount = 0

    if (-not $Quiet) {
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host "  HITL Evidence Integrity Verification" -ForegroundColor Cyan
        Write-Host "  Directory: $EvidencePath" -ForegroundColor Gray
        Write-Host "==========================================" -ForegroundColor Cyan
        Write-Host ""
    }

    # Iterate over each file listed in manifest
    $fileNames = $manifest.files.PSObject.Properties.Name

    foreach ($fileName in $fileNames) {
        $fileCount++
        $fileEntry = $manifest.files.$fileName
        $expectedHash = $fileEntry.sha256

        $dataFilePath = Join-Path -Path $EvidencePath -ChildPath $fileName
        $hashFilePath = "$dataFilePath.sha256"

        # Verify data file exists
        if (-not (Test-Path -Path $dataFilePath -PathType Leaf)) {
            $allPassed = $false
            $failCount++
            if (-not $Quiet) {
                Write-Host "  [FAIL] $fileName - Data file missing" -ForegroundColor Red
            }
            continue
        }

        # Verify .sha256 sidecar exists
        if (-not (Test-Path -Path $hashFilePath -PathType Leaf)) {
            $allPassed = $false
            $failCount++
            if (-not $Quiet) {
                Write-Host "  [FAIL] $fileName - SHA-256 sidecar missing" -ForegroundColor Red
            }
            continue
        }

        # Compute actual hash
        $actualHashResult = Get-FileHash -Path $dataFilePath -Algorithm SHA256
        $actualHash = $actualHashResult.Hash

        # Read expected hash from sidecar
        $sidecarContent = Get-Content -Path $hashFilePath -Raw
        $sidecarHash = ($sidecarContent -split '\s+')[0].Trim()

        # Verify manifest hash matches sidecar hash
        $manifestMatch = $actualHash -eq $expectedHash
        $sidecarMatch = $actualHash -eq $sidecarHash

        if ($manifestMatch -and $sidecarMatch) {
            $passCount++
            if (-not $Quiet) {
                Write-Host "  [PASS] $fileName" -ForegroundColor Green
                Write-Host "         SHA-256: $actualHash" -ForegroundColor Gray
            }
        } else {
            $allPassed = $false
            $failCount++
            if (-not $Quiet) {
                Write-Host "  [FAIL] $fileName" -ForegroundColor Red
                Write-Host "         Expected (manifest): $expectedHash" -ForegroundColor Red
                Write-Host "         Expected (sidecar):  $sidecarHash" -ForegroundColor Red
                Write-Host "         Actual:              $actualHash" -ForegroundColor Red
            }
        }
    }

    # Summary
    if (-not $Quiet) {
        Write-Host ""
        if ($allPassed) {
            Write-Host "==========================================" -ForegroundColor Green
            Write-Host "  Evidence Integrity: VERIFIED" -ForegroundColor Green
            Write-Host "==========================================" -ForegroundColor Green
            Write-Host ""
            Write-Host "All $fileCount file(s) passed integrity verification." -ForegroundColor Green
            Write-Host "Evidence has not been modified since export." -ForegroundColor Green
        } else {
            Write-Warning "========================================"
            Write-Warning "  Evidence Integrity: FAILED"
            Write-Warning "========================================"
            Write-Warning ""
            Write-Warning "$failCount of $fileCount file(s) FAILED integrity verification."
            Write-Warning "INTEGRITY CHECK FAILED. Evidence files may have been modified or corrupted."
        }
        Write-Host ""
        Write-Host "Files checked: $fileCount  Passed: $passCount  Failed: $failCount" -ForegroundColor Gray
        Write-Host ""
    }

    return $allPassed
} catch {
    if (-not $Quiet) {
        Write-Error "Evidence integrity verification failed: $($_.Exception.Message)"
    }
    throw
}
