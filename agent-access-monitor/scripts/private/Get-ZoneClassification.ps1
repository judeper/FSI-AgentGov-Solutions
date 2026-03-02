# Zone Classification — local implementation
# Classifies environments into governance zones using naming convention
# or optional Dataverse ELM lookup.

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
        $filter = "fsi_environment_id eq '$($EnvironmentId -replace "'", "''")'"
        $uri = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2/fsi_environmentlifecycles?" +
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
        Write-Verbose "ELM lookup failed for $EnvironmentId, falling back to naming convention: $($_.Exception.Message)"
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