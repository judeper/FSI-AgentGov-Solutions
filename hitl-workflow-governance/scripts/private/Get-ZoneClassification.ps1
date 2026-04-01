# Zone Classification — delegated to shared module
# See scripts/shared/Get-ZoneClassification.ps1 for canonical implementation

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
