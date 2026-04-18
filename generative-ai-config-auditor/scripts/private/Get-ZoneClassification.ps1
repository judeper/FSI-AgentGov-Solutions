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
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$EnvironmentId,

    [Parameter(Mandatory)]
    [string]$EnvironmentDisplayName,

    [Parameter()]
    [string]$DataverseUrl,

    [Parameter()]
    [string]$AccessToken
)

$sharedScript = "$PSScriptRoot\..\..\..\scripts\shared\Get-ZoneClassification.ps1"
& $sharedScript @PSBoundParameters
