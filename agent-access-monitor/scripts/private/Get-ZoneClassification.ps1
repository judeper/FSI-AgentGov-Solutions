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

    [Parameter()]
    [string]$EnvironmentDisplayName,

    [Parameter()]
    [string]$DataverseUrl,

    [Parameter()]
    [string]$AccessToken
)

# Try Dataverse ELM lookup first if connection details provided
if ($DataverseUrl -and $AccessToken) {
    try {
        $headers = @{
            'Authorization'    = "Bearer $AccessToken"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }
        $filter = "fsi_environmentid eq '$($EnvironmentId -replace "'", "''")'"
        $uri = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2/fsi_environmentrequests?" +
               "`$filter=$filter&`$select=fsi_zone&`$top=1"
        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop
        if ($response.value.Count -gt 0) {
            $zoneValue = $response.value[0].fsi_zone
            $zoneNameMap = @{ 1 = 'Zone1'; 2 = 'Zone2'; 3 = 'Zone3' }
            if ($zoneNameMap.ContainsKey([int]$zoneValue)) {
                return $zoneNameMap[[int]$zoneValue]
            }
        }
    } catch {
        Write-Warning "ELM lookup failed for $EnvironmentId, falling back to naming convention: $($_.Exception.Message)"
    }
}

# Fallback: naming convention classification
if ($EnvironmentDisplayName) {
    $name = $EnvironmentDisplayName.ToLower()
    if ($name -match '\bz3\b' -or $name -match 'zone.?3' -or $name -match 'enterprise') {
        return 'Zone3'
    }
    if ($name -match '\bz2\b' -or $name -match 'zone.?2' -or $name -match 'team') {
        return 'Zone2'
    }
    if ($name -match '\bz1\b' -or $name -match 'zone.?1' -or $name -match 'personal') {
        return 'Zone1'
    }
}

return 'Unknown'