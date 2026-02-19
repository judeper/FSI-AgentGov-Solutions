<#
.SYNOPSIS
    Retrieves zone classification for a Power Platform environment.

.DESCRIPTION
    Determines the governance zone classification for an environment using:
    1. ELM Dataverse table lookup (if DataverseUrl and AccessToken provided)
    2. Naming convention fallback (pattern matching in display name)
    3. Returns 'Unknown' if neither method resolves

    When a GroupConfig hashtable is provided, returns a richer object that includes
    the Entra group ID mapped to the resolved zone, enabling Conditional Access
    policy targeting by zone.

.PARAMETER EnvironmentId
    The Power Platform environment GUID.

.PARAMETER EnvironmentDisplayName
    The display name of the environment.

.PARAMETER DataverseUrl
    Optional Dataverse URL for ELM zone lookup.

.PARAMETER AccessToken
    Optional access token for Dataverse authentication.

.PARAMETER GroupConfig
    Optional hashtable mapping zones to Entra group IDs for CA policy targeting.
    Example: @{ Zone1 = 'group-guid-1'; Zone2 = 'group-guid-2'; Zone3 = 'group-guid-3' }
    When provided, the function returns a richer object with Zone and GroupId properties.

.EXAMPLE
    Get-CAAZoneClassification -EnvironmentId "abc123" -EnvironmentDisplayName "Contoso-Z3-Trading"

    Returns "Zone3" based on naming convention.

.EXAMPLE
    Get-CAAZoneClassification -EnvironmentId "abc123" -EnvironmentDisplayName "MyEnv" -DataverseUrl "https://org.crm.dynamics.com" -AccessToken $token

    Looks up zone in ELM Dataverse table first, falls back to naming convention.

.EXAMPLE
    $groups = @{ Zone1 = '11111111-...'; Zone2 = '22222222-...'; Zone3 = '33333333-...' }
    Get-CAAZoneClassification -EnvironmentId "abc123" -EnvironmentDisplayName "Contoso-Z3-Trading" -GroupConfig $groups

    Returns @{ Zone = 'Zone3'; GroupId = '33333333-...' }

.OUTPUTS
    System.String
    One of: Zone1, Zone2, Zone3, Unknown (when GroupConfig is not provided).

    System.Collections.Hashtable
    @{ Zone = 'Zone1|Zone2|Zone3|Unknown'; GroupId = '<group-id-or-null>' } (when GroupConfig is provided).

.NOTES
    File: Get-ZoneClassification.ps1
    Version: 1.0.0
#>

function Get-CAAZoneClassification {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$EnvironmentId,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$EnvironmentDisplayName,

        [Parameter()]
        [string]$DataverseUrl,

        [Parameter()]
        [string]$AccessToken,

        [Parameter()]
        [hashtable]$GroupConfig
    )

    $ErrorActionPreference = 'Stop'

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

            # Validate EnvironmentId is a valid GUID to prevent OData injection
            if ($EnvironmentId -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
                Write-Verbose "EnvironmentId is not a valid GUID format, skipping ELM lookup"
                return $null
            }

            $uri = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2/fsi_environments?" +
                   "`$filter=fsi_environment_guid eq '$EnvironmentId'&" +
                   "`$select=fsi_zone_classification"

            $headers = @{
                'Authorization'    = "Bearer $AccessToken"
                'Accept'           = 'application/json'
                'OData-MaxVersion' = '4.0'
                'OData-Version'    = '4.0'
            }

            $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get -ErrorAction Stop

            if ($response.value.Count -gt 0) {
                $zoneValue = $response.value[0].fsi_zone_classification

                # Map option set value to zone name
                $zoneMapping = @{
                    100000000 = 'Zone1'
                    100000001 = 'Zone2'
                    100000002 = 'Zone3'
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
            Write-Verbose "ELM lookup failed: $($_.Exception.Message)"
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

        # Zone3 patterns (most restrictive — check first)
        $zone3Patterns = @('-z3-', '-zone3-', '_zone3_', '-prod-', '-enterprise-')
        foreach ($pattern in $zone3Patterns) {
            if ($normalized.Contains($pattern)) {
                Write-Verbose "Naming convention matched '$pattern' -> Zone3"
                return 'Zone3'
            }
        }
        if ($normalized -match 'z3$|zone3$') {
            Write-Verbose "Naming convention matched end-of-string pattern -> Zone3"
            return 'Zone3'
        }

        # Zone2 patterns
        $zone2Patterns = @('-z2-', '-zone2-', '_zone2_', '-team-', '-collab-', '-shared-')
        foreach ($pattern in $zone2Patterns) {
            if ($normalized.Contains($pattern)) {
                Write-Verbose "Naming convention matched '$pattern' -> Zone2"
                return 'Zone2'
            }
        }
        if ($normalized -match 'z2$|zone2$') {
            Write-Verbose "Naming convention matched end-of-string pattern -> Zone2"
            return 'Zone2'
        }

        # Zone1 patterns
        $zone1Patterns = @('-z1-', '-zone1-', '_zone1_', '-personal-', '-dev-', '-sandbox-')
        foreach ($pattern in $zone1Patterns) {
            if ($normalized.Contains($pattern)) {
                Write-Verbose "Naming convention matched '$pattern' -> Zone1"
                return 'Zone1'
            }
        }
        if ($normalized -match 'z1$|zone1$') {
            Write-Verbose "Naming convention matched end-of-string pattern -> Zone1"
            return 'Zone1'
        }

        Write-Verbose "No naming convention match found"
        return $null
    }

    #endregion

    #region Main Logic

    $resolvedZone = $null

    # Try ELM lookup first if DataverseUrl provided
    if ($DataverseUrl) {
        $resolvedZone = Get-ZoneFromELM -EnvironmentId $EnvironmentId -DataverseUrl $DataverseUrl -AccessToken $AccessToken
    }

    # Fall back to naming convention
    if (-not $resolvedZone) {
        $resolvedZone = Get-ZoneFromNamingConvention -DisplayName $EnvironmentDisplayName
    }

    # Default to Unknown
    if (-not $resolvedZone) {
        Write-Verbose "Unable to determine zone for environment: $EnvironmentDisplayName"
        $resolvedZone = 'Unknown'
    }

    # Return enriched object when GroupConfig is provided
    if ($GroupConfig) {
        $groupId = $null
        if ($GroupConfig.ContainsKey($resolvedZone)) {
            $groupId = $GroupConfig[$resolvedZone]
        }

        return @{
            Zone    = $resolvedZone
            GroupId = $groupId
        }
    }

    # Return plain zone string for compatibility
    return $resolvedZone

    #endregion
}
