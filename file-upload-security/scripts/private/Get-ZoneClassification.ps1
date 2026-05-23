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
$sharedZoneScript = "$PSScriptRoot\..\..\..\scripts\shared\Get-ZoneClassification.ps1"
if (Test-Path $sharedZoneScript) {
    . $sharedZoneScript
} else {
    Write-Warning "Shared Get-ZoneClassification.ps1 not found at $sharedZoneScript. Using naming-convention fallback."
    function Get-ZoneClassification {
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSReviewUnusedParameter', '',
            Justification = 'PSScriptAnalyzer requires this rule suppression on the function param block; individual compatibility parameters carry specific justifications.'
        )]
        param(
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSReviewUnusedParameter', '',
                Justification = 'Parameter is reserved for documented future behavior or backward-compatible CLI shape; intentionally unused in this implementation.'
            )]
            [string]$EnvironmentId,
            [string]$EnvironmentDisplayName,
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSReviewUnusedParameter', '',
                Justification = 'Parameter is reserved for documented future behavior or backward-compatible CLI shape; intentionally unused in this implementation.'
            )]
            [string]$DataverseUrl,
            [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
                'PSReviewUnusedParameter', '',
                Justification = 'Parameter is reserved for documented future behavior or backward-compatible CLI shape; intentionally unused in this implementation.'
            )]
            [string]$AccessToken
        )
        # Naming-convention fallback: classify by environment display name patterns
        if ($EnvironmentDisplayName -match '(?i)enterprise|prod|production') { return 'Zone 3' }
        if ($EnvironmentDisplayName -match '(?i)team|shared|collab') { return 'Zone 2' }
        if ($EnvironmentDisplayName -match '(?i)personal|dev|sandbox') { return 'Zone 1' }
        # Fail-safe: unclassifiable environments default to Zone 3 (most restrictive)
        return 'Zone 3'
    }
}