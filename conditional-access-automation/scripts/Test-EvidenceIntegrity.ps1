<#
.SYNOPSIS
    Verifies the SHA-256 integrity of a CAA compliance evidence file.

.DESCRIPTION
    Reads the companion .sha256 hash file for a given CAA evidence JSON file,
    computes the actual SHA-256 hash of the JSON content, and compares the two
    values. Returns a result object indicating whether the evidence file has
    been modified since export.

    This verification aids in demonstrating evidence integrity during
    FINRA/SEC regulatory examinations by confirming that exported compliance
    data has not been altered after generation.

    Exit code 0 indicates the hash matches (integrity verified).
    Exit code 1 indicates a mismatch (potential tampering detected).

.PARAMETER EvidencePath
    The full path to the CAA evidence JSON file to verify.
    The companion .sha256 file must exist at the same location
    (e.g., CAA-Evidence-20260210T120000Z.json.sha256).

.EXAMPLE
    .\Test-EvidenceIntegrity.ps1 -EvidencePath './evidence/CAA-Evidence-20260210T120000Z.json'

    Verifies the evidence file against its companion SHA-256 hash.

.EXAMPLE
    $result = .\Test-EvidenceIntegrity.ps1 -EvidencePath './evidence/CAA-Evidence-20260210T120000Z.json'
    if ($result.Valid) { Write-Host 'Evidence integrity confirmed.' }

    Captures the verification result for programmatic use.

.EXAMPLE
    Get-ChildItem './evidence/*.json' | ForEach-Object {
        .\Test-EvidenceIntegrity.ps1 -EvidencePath $_.FullName
    } | Format-Table Path, Valid, ExpectedHash, ActualHash

    Batch-verifies all evidence files in a directory.

.OUTPUTS
    PSCustomObject with properties:
      - Path         [string] : The evidence file path
      - Valid        [bool]   : Whether the hash matches
      - ExpectedHash [string] : The hash from the companion .sha256 file
      - ActualHash   [string] : The computed hash of the evidence file

.NOTES
    File: Test-EvidenceIntegrity.ps1
    Version: 1.0.0
    Companion .sha256 files use sha256sum-compatible format:
    "{hash}  {filename}" (two-space separator).
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory, ValueFromPipeline, ValueFromPipelineByPropertyName)]
    [ValidateNotNullOrEmpty()]
    [Alias('FullName')]
    [string]$EvidencePath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# `exit` statements are correct for standalone CLI / CI usage but terminate
# the host runspace when the script is dot-sourced or imported. Detect
# dot-sourcing once up-front and route control via a small helper so callers
# in module/automation contexts don't lose state.
$invokedDotSourced = $MyInvocation.InvocationName -eq '.'
function _LeaveScript([int]$Code) {
    if ($script:invokedDotSourced) { return $Code } else { exit $Code }
}

# Resolve full path
$resolvedPath = Resolve-Path -Path $EvidencePath -ErrorAction Stop | Select-Object -ExpandProperty Path

# Verify evidence file exists
if (-not (Test-Path $resolvedPath -PathType Leaf)) {
    Write-Error "Evidence file not found: $resolvedPath"
    return (_LeaveScript 1)
}

# Locate companion hash file
$hashFilePath = "$resolvedPath.sha256"
if (-not (Test-Path $hashFilePath -PathType Leaf)) {
    Write-Error "Companion SHA-256 hash file not found: $hashFilePath"
    return (_LeaveScript 1)
}

# Read expected hash from companion file
# Format: "{hash}  {filename}" (sha256sum-compatible, two-space separator)
$hashContent = (Get-Content -Path $hashFilePath -Raw).Trim()
$expectedHash = ($hashContent -split '\s{2}')[0].Trim().ToUpperInvariant()

if ([string]::IsNullOrWhiteSpace($expectedHash)) {
    Write-Error "Could not parse hash from companion file: $hashFilePath"
    return (_LeaveScript 1)
}

# Compute actual hash
$actualHash = (Get-FileHash -Path $resolvedPath -Algorithm SHA256).Hash.ToUpperInvariant()

# Compare (case-insensitive, both already uppercased)
$isValid = $expectedHash -eq $actualHash

# Build result
$result = [PSCustomObject]@{
    Path         = $resolvedPath
    Valid        = $isValid
    ExpectedHash = $expectedHash
    ActualHash   = $actualHash
}

# Output result
if ($isValid) {
    Write-Host "PASS: Evidence integrity verified — $resolvedPath" -ForegroundColor Green
}
else {
    Write-Warning "FAIL: Evidence integrity mismatch — $resolvedPath"
    Write-Warning "  Expected: $expectedHash"
    Write-Warning "  Actual:   $actualHash"
}

$result

# Set exit code
if (-not $isValid) {
    return (_LeaveScript 1)
}
