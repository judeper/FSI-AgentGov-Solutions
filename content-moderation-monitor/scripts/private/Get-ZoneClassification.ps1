# Zone Classification — self-contained with optional shared module delegation
# Falls back to local implementation for standalone/customer deployments

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

# Try shared module if available (monorepo context).
# Repo layout: <repo-root>\scripts\shared\Get-ZoneClassification.ps1
# This file lives at <repo-root>\content-moderation-monitor\scripts\private\, so go up THREE.
$sharedScript = "$PSScriptRoot\..\..\..\scripts\shared\Get-ZoneClassification.ps1"
if (Test-Path $sharedScript) {
    & $sharedScript @PSBoundParameters
    return
}

# Standalone fallback: classify by environment name convention or Dataverse lookup
function Get-ZoneFromEnvironmentName {
    param([string]$Name)
    if ($Name -match '(?i)^Zone\s*3[-_\s]|[-_\s]Zone\s*3$|(?i)\b(production|prod|enterprise|customer)\b') {
        return 'Zone3'
    } elseif ($Name -match '(?i)^Zone\s*2[-_\s]|[-_\s]Zone\s*2$|(?i)\b(team|collab|shared)\b') {
        return 'Zone2'
    } elseif ($Name -match '(?i)^Zone\s*1[-_\s]|[-_\s]Zone\s*1$|(?i)\b(personal|dev|sandbox)\b') {
        return 'Zone1'
    }
    return $null
}

# Attempt Dataverse ELM lookup if credentials provided
if ($DataverseUrl -and $AccessToken) {
    try {
        $headers = @{
            'Authorization' = "Bearer $AccessToken"
            'OData-MaxVersion' = '4.0'
            'OData-Version' = '4.0'
            'Accept' = 'application/json'
        }
        $safeEnvId = $EnvironmentId -replace "'", "''"
        $filter = "fsi_environmentguid eq '$safeEnvId'"
        $url = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2/fsi_environmentlifecycles?`$filter=$filter&`$select=fsi_zone&`$top=1"
        $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop
        if ($response.value -and $response.value.Count -gt 0) {
            $zoneValue = $response.value[0].fsi_zone
            # fsi_zone is a Choice (option set); valid values are in the 100000000+ range.
            $zoneMap = @{
                100000000 = 'Unknown'
                100000001 = 'Zone1'
                100000002 = 'Zone2'
                100000003 = 'Zone3'
            }
            if ($zoneMap.ContainsKey($zoneValue)) {
                return [PSCustomObject]@{ Zone = $zoneMap[$zoneValue]; Source = 'Dataverse' }
            }
        }
    } catch {
        Write-Verbose "Dataverse zone lookup failed: $($_.Exception.Message). Falling back to name convention."
    }
}

# Fall back to environment name convention
$zone = Get-ZoneFromEnvironmentName -Name $EnvironmentDisplayName
if ($zone) {
    return [PSCustomObject]@{ Zone = $zone; Source = 'NameConvention' }
}

# Default: Unknown zone
return [PSCustomObject]@{ Zone = 'Unknown'; Source = 'Default' }