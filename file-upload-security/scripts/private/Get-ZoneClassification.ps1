# Zone Classification — delegated to shared module with fallback
# See scripts/shared/Get-ZoneClassification.ps1 for canonical implementation
$sharedZoneScript = "$PSScriptRoot\..\..\..\scripts\shared\Get-ZoneClassification.ps1"
if (Test-Path $sharedZoneScript) {
    . $sharedZoneScript
} else {
    Write-Warning "Shared Get-ZoneClassification.ps1 not found at $sharedZoneScript. Using naming-convention fallback."
    function Get-ZoneClassification {
        param(
            [string]$EnvironmentId,
            [string]$EnvironmentDisplayName,
            [string]$DataverseUrl,
            [string]$AccessToken
        )
        # Naming-convention fallback: classify by environment display name patterns
        if ($EnvironmentDisplayName -match '(?i)enterprise|prod|production') { return 'Zone 3' }
        if ($EnvironmentDisplayName -match '(?i)team|shared|collab') { return 'Zone 2' }
        if ($EnvironmentDisplayName -match '(?i)personal|dev|sandbox') { return 'Zone 1' }
        return 'Unknown'
    }
}