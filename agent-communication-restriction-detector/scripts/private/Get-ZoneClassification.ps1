#Requires -Version 7.0

<#
.SYNOPSIS
    Delegates zone classification to the shared Get-ZoneClassification module.

.DESCRIPTION
    Thin wrapper that forwards parameters to the canonical zone classification
    implementation at scripts/shared/Get-ZoneClassification.ps1. The shared
    module resolves a Power Platform environment to its governance zone
    (Zone1, Zone2, Zone3, or Unknown) using Dataverse lookup or naming convention.

.PARAMETER EnvironmentId
    The GUID of the Power Platform environment to classify.

.PARAMETER EnvironmentDisplayName
    The display name of the Power Platform environment (used for convention-based
    classification when Dataverse lookup is unavailable).

.PARAMETER DataverseUrl
    Optional Dataverse URL for zone classification lookup via ELM tables.

.PARAMETER AccessToken
    Optional pre-acquired Dataverse access token for authentication.

.EXAMPLE
    .\Get-ZoneClassification.ps1 -EnvironmentId "abc-123" -EnvironmentDisplayName "Prod-Zone3"

    Returns the governance zone for the specified environment using naming convention.

.EXAMPLE
    .\Get-ZoneClassification.ps1 -EnvironmentId "abc-123" -EnvironmentDisplayName "Prod" `
        -DataverseUrl "https://governance.crm.dynamics.com" -AccessToken $token

    Returns the governance zone using Dataverse ELM lookup with explicit token.

.NOTES
    File: Get-ZoneClassification.ps1
    Version: 1.0.1
    Solution: Agent Communication Restriction Detector (ACRD)
    Delegates to: scripts/shared/Get-ZoneClassification.ps1
#>

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
