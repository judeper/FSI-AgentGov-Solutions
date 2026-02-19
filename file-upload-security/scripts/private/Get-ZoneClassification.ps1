<#
.SYNOPSIS
    Classifies a Power Platform environment into a governance zone.

.DESCRIPTION
    Determines zone classification (Zone 1/2/3) for an environment using
    ELM Dataverse lookup when available, falling back to naming convention.

.PARAMETER EnvironmentId
    Power Platform environment ID.

.PARAMETER EnvironmentDisplayName
    Environment display name (used for naming convention fallback).

.PARAMETER DataverseUrl
    Optional ELM Dataverse URL for zone lookup.

.PARAMETER AccessToken
    Optional access token for ELM Dataverse queries.
#>

[CmdletBinding()]
param(
    [Parameter()]
    [string]$EnvironmentId,

    [Parameter()]
    [string]$EnvironmentDisplayName,

    [Parameter()]
    [string]$DataverseUrl,

    [Parameter()]
    [string]$AccessToken
)

function Get-ZoneClassification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$EnvironmentId,

        [Parameter()]
        [string]$EnvironmentDisplayName,

        [Parameter()]
        [string]$DataverseUrl,

        [Parameter()]
        [string]$AccessToken
    )

    # Try ELM Dataverse lookup if credentials available
    if ($DataverseUrl -and $AccessToken) {
        try {
            $headers = @{
                'Authorization' = "Bearer $AccessToken"
                'Accept'        = 'application/json'
            }
            $escapedEnvId = $EnvironmentId -replace "'", "''"
            $uri = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2/fsi_acv_environmentregistrations?" +
                   "`$filter=fsi_environment_id eq '$escapedEnvId'&`$select=fsi_zone"
            $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
            if ($response.value.Count -gt 0) {
                $zoneValue = $response.value[0].fsi_zone
                return switch ($zoneValue) {
                    1 { 'Zone 1' }
                    2 { 'Zone 2' }
                    3 { 'Zone 3' }
                    default { 'Zone 1' }
                }
            }
        } catch {
            Write-Verbose "ELM zone lookup failed: $($_.Exception.Message). Falling back to naming convention."
        }
    }

    # Naming convention fallback
    $name = if ($EnvironmentDisplayName) { $EnvironmentDisplayName } else { $EnvironmentId }
    if ($name -match '(?i)(enterprise|prod|production|zone.?3)') {
        return 'Zone 3'
    }
    if ($name -match '(?i)(team|collab|department|zone.?2)') {
        return 'Zone 2'
    }
    return 'Zone 1'
}

# When called as a script (via & operator), invoke the function with bound parameters
if ($EnvironmentId) {
    Get-ZoneClassification @PSBoundParameters
}