<#
.SYNOPSIS
    Classifies a Power Platform environment into a governance zone (local helper).

.DESCRIPTION
    Private, solution-scoped variant of the shared zone classifier. Returns
    the zone for a given environment using naming convention matching and,
    where supported, an optional Dataverse ELM lookup. Falls back to
    'Unknown' when the zone cannot be resolved.

.PARAMETER EnvironmentId
    Power Platform environment GUID or name.

.PARAMETER EnvironmentDisplayName
    Optional display name used for naming-convention fallback.

.PARAMETER DataverseUrl
    Optional Dataverse URL for ELM table lookup.

.NOTES
    Prefer scripts/shared/Get-ZoneClassification.ps1 when a canonical
    implementation is needed; this file is intentionally scoped to the
    parent solution and may be simpler.
#>
$script:FUSSharedZoneScript = "$PSScriptRoot\..\..\..\scripts\shared\Get-ZoneClassification.ps1"

function Get-ZoneClassification {
    [CmdletBinding()]
    param(
        [string]$EnvironmentId,
        [string]$EnvironmentDisplayName,
        [string]$DataverseUrl,
        [string]$AccessToken
    )

    # Prefer the canonical shared classifier (ELM Dataverse lookup + canonical
    # naming convention) when it has been promoted to the repo root. The shared
    # file is a parameterised SCRIPT, not a function library, so it must be
    # INVOKED with the call operator -- dot-sourcing it would execute its
    # mandatory-parameter body at import time and fail with
    # "missing mandatory parameters: EnvironmentId EnvironmentDisplayName".
    # Fall back to the local naming-convention map when the shared script is
    # absent or cannot resolve a concrete zone.
    if (Test-Path $script:FUSSharedZoneScript) {
        $sharedParams = @{
            EnvironmentId          = $EnvironmentId
            EnvironmentDisplayName = $EnvironmentDisplayName
        }
        if ($DataverseUrl) { $sharedParams['DataverseUrl'] = $DataverseUrl }
        if ($AccessToken)  { $sharedParams['AccessToken'] = $AccessToken }

        try {
            $sharedZone = & $script:FUSSharedZoneScript @sharedParams
            if ($sharedZone -and $sharedZone -ne 'Unknown') { return $sharedZone }
        } catch {
            Write-Warning "Shared Get-ZoneClassification failed ($($_.Exception.Message)); using naming-convention fallback."
        }
    }

    # Naming-convention fallback: classify by environment display name patterns.
    # Canonical zone semantics: Zone 1 (Enterprise) = most-restrictive,
    # Zone 3 (Personal) = least-restrictive.
    if ($EnvironmentDisplayName -match '(?i)enterprise|prod|production') { return 'Zone 1' }
    if ($EnvironmentDisplayName -match '(?i)team|shared|collab') { return 'Zone 2' }
    if ($EnvironmentDisplayName -match '(?i)personal|dev|sandbox') { return 'Zone 3' }
    # Fail-safe: unclassifiable environments default to Zone 1 (most restrictive)
    return 'Zone 1'
}