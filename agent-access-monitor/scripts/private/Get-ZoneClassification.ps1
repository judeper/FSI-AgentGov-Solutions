# Zone Classification — standalone implementation
# Standalone zone classification helper (not currently called by main scripts).
#   -EnvironmentId, -EnvironmentDisplayName, -DataverseUrl, -AccessToken

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

# Attempt ELM Dataverse lookup if URL is provided
if ($DataverseUrl -and $AccessToken) {
    try {
        # Validate GUID format to prevent OData injection
        if ($EnvironmentId -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
            throw "Invalid GUID format for EnvironmentId: '$EnvironmentId'"
        }
        $headers = @{
            'Authorization'    = "Bearer $AccessToken"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }
        $filter = "fsi_environment_guid eq '$EnvironmentId'"
        $uri = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2/fsi_accessbaselines?`$filter=$filter and fsi_is_active eq true&`$select=fsi_zone&`$top=1"
        $maxRetries = 3
        $response = $null
        for ($i = 0; $i -lt $maxRetries; $i++) {
            try {
                $response = Invoke-RestMethod -Uri $uri -Method Get -Headers $headers -ErrorAction Stop
                break
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
                if (($statusCode -eq 429 -or $statusCode -ge 500) -and $i -lt ($maxRetries - 1)) {
                    $delay = [math]::Pow(2, $i)
                    Write-Verbose "Zone classification request failed (HTTP $statusCode), retrying in ${delay}s..."
                    Start-Sleep -Seconds $delay
                } else {
                    throw
                }
            }
        }
        if ($response.value.Count -gt 0) {
            $zoneValue = $response.value[0].fsi_zone
            $zoneMap = @{ 1 = 'Zone1'; 2 = 'Zone2'; 3 = 'Zone3' }
            if ($zoneMap.ContainsKey([int]$zoneValue)) {
                return $zoneMap[[int]$zoneValue]
            }
        }
    } catch {
        Write-Verbose "ELM lookup failed for $EnvironmentId : $($_.Exception.Message). Falling back to naming convention."
    }
}

# Fallback: naming convention heuristic
$name = $EnvironmentDisplayName
if ($name -match '(?i)(prod|production|enterprise|zone\s*3)') {
    return 'Zone3'
} elseif ($name -match '(?i)(team|department|shared|zone\s*2)') {
    return 'Zone2'
} elseif ($name -match '(?i)(personal|dev|sandbox|zone\s*1)') {
    return 'Zone1'
}

return 'Unknown'