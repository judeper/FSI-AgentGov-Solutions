<#
.SYNOPSIS
    Zone Classification — delegated to shared module.

.DESCRIPTION
    Delegates zone classification to the shared Get-ZoneClassification.ps1 script.
    See scripts/shared/Get-ZoneClassification.ps1 for canonical implementation.

.PARAMETER EnvironmentId
    The Power Platform environment GUID.

.PARAMETER EnvironmentDisplayName
    The environment display name.

.PARAMETER DataverseUrl
    Optional Dataverse URL for the environment.

.PARAMETER AccessToken
    Optional bearer token for Dataverse authentication.

.EXAMPLE
    .\Get-ZoneClassification.ps1 -EnvironmentId "abc-123" -EnvironmentDisplayName "Prod"
    Returns the zone classification for the specified environment.
#>

#requires -Version 5.1

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
