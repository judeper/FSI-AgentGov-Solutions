<#
.SYNOPSIS
    Retrieves zone classification for a Power Platform environment.

.DESCRIPTION
    Determines the governance zone classification for an environment using:
    1. ELM Dataverse table lookup (if DataverseUrl provided)
    2. Naming convention fallback (pattern matching in display name)
    3. Returns 'Unknown' if neither method resolves

.PARAMETER EnvironmentId
    The Power Platform environment GUID.

.PARAMETER EnvironmentDisplayName
    The display name of the environment.

.PARAMETER DataverseUrl
    Optional Dataverse URL for ELM zone lookup.

.PARAMETER AccessToken
    Optional access token for Dataverse authentication.

.EXAMPLE
    Get-ZoneClassification -EnvironmentId "abc123" -EnvironmentDisplayName "Contoso-Z3-Trading"
    
    Returns "Zone3" based on naming convention.

.EXAMPLE
    Get-ZoneClassification -EnvironmentId "abc123" -EnvironmentDisplayName "MyEnv" -DataverseUrl "https://org.crm.dynamics.com"
    
    Looks up zone in ELM Dataverse table first, falls back to naming convention.

.OUTPUTS
    String - One of: Zone1, Zone2, Zone3, Unknown

.NOTES
    File: Get-ZoneClassification.ps1
    Version: 0.1.0
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

#region ELM Dataverse Lookup

function Get-ZoneFromELM {
    param(
        [string]$EnvironmentId,
        [string]$DataverseUrl,
        [string]$AccessToken
    )
    
    if (-not $DataverseUrl) {
        return $null
    }
    
    try {
        Write-Verbose "Looking up zone in ELM for environment: $EnvironmentId"

        # Canonical ELM contract (set by environment-lifecycle-management v1.2.0):
        #   Table:        fsi_environmentrequest (entity set: fsi_environmentrequests)
        #   Filter key:   fsi_environmentid (the Power Platform environment GUID
        #                 written back by the provisioning flow)
        #   Zone column:  fsi_zone (custom global option set, values 100000001..3)
        $uri = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2/fsi_environmentrequests?" +
               "`$filter=fsi_environmentid eq '$EnvironmentId'&" +
               "`$select=fsi_zone"

        $headers = @{
            'Authorization' = "Bearer $AccessToken"
            'Accept' = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version' = '4.0'
        }

        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop

        if ($response.value.Count -gt 0) {
            $zoneValue = $response.value[0].fsi_zone

            # Map option set value to canonical zone label.
            $zoneMapping = @{
                100000001 = 'Zone1'
                100000002 = 'Zone2'
                100000003 = 'Zone3'
            }

            if ($zoneMapping.ContainsKey($zoneValue)) {
                $zone = $zoneMapping[$zoneValue]
                Write-Verbose "ELM lookup found zone: $zone"
                return $zone
            }
        }

        Write-Verbose "Environment not found in ELM"
        return $null
    } catch {
        Write-Warning "ELM zone lookup failed for environment $($EnvironmentId): $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region Naming Convention Fallback

function Get-ZoneFromNamingConvention {
    param(
        [string]$DisplayName
    )
    
    # Normalize to lowercase for matching
    $normalized = $DisplayName.ToLower()
    
    # Pattern matching for zone indicators
    $patterns = @{
        'Zone3' = @('-z3-', '-zone3-', '_z3_', '_zone3_', 'zone3', '-prod-', '-production-', '-enterprise-')
        'Zone2' = @('-z2-', '-zone2-', '_z2_', '_zone2_', 'zone2', '-team-', '-collab-', '-shared-')
        'Zone1' = @('-z1-', '-zone1-', '_z1_', '_zone1_', 'zone1', '-personal-', '-dev-', '-sandbox-')
    }
    
    foreach ($zone in $patterns.Keys) {
        foreach ($pattern in $patterns[$zone]) {
            if ($normalized -match [regex]::Escape($pattern)) {
                Write-Verbose "Naming convention matched '$pattern' -> $zone"
                return $zone
            }
        }
    }
    
    # Check for direct zone number at end
    if ($normalized -match 'z3$|zone3$') { return 'Zone3' }
    if ($normalized -match 'z2$|zone2$') { return 'Zone2' }
    if ($normalized -match 'z1$|zone1$') { return 'Zone1' }
    
    Write-Verbose "No naming convention match found"
    return $null
}

#endregion

#region Main Logic

# Try ELM lookup first if DataverseUrl provided
if ($DataverseUrl) {
    $elmZone = Get-ZoneFromELM -EnvironmentId $EnvironmentId -DataverseUrl $DataverseUrl -AccessToken $AccessToken
    if ($elmZone) {
        return $elmZone
    }
}

# Fall back to naming convention
$conventionZone = Get-ZoneFromNamingConvention -DisplayName $EnvironmentDisplayName
if ($conventionZone) {
    return $conventionZone
}

# No match found
Write-Verbose "Unable to determine zone for environment: $EnvironmentDisplayName"
return 'Unknown'

#endregion
