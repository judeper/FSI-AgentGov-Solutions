#Requires -Version 7.0

<#
.SYNOPSIS
    Queries Dataverse environment variables for zone-specific session security thresholds.

.DESCRIPTION
    Retrieves zone-specific session security threshold values from Dataverse environment
    variables deployed by the Session Security Configurator Dataverse schema.

    This helper queries the Dataverse Web API for environment variable definitions
    with the fsi_SSC_ prefix and returns a structured hashtable containing sign-in
    frequency minutes and authentication strength values for the specified zone.

    The helper is designed to fail gracefully. If Dataverse is unavailable or the
    environment variables are not deployed, it returns $null without throwing an
    exception. The caller (Test-SessionCompliance.ps1) handles fallback to local
    JSON baseline files.

.PARAMETER DataverseUrl
    Dataverse environment URL. Required.
    Example: "https://org.crm.dynamics.com"

.PARAMETER Zone
    Governance zone identifier. Required.
    Valid values: Zone1, Zone2, Zone3

.PARAMETER AccessToken
    Pre-acquired bearer token for Dataverse Web API authentication. Optional.
    If omitted, attempts to extract token from current Microsoft Graph session
    via Get-MgContext.

    NOTE: The Dataverse Web API scope is different from Microsoft Graph scope.
    Callers should provide a Dataverse-scoped token when possible.

.EXAMPLE
    Get-DataverseThreshold -DataverseUrl "https://contoso.crm.dynamics.com" -Zone Zone3 -AccessToken $token

    Returns:
    @{
        SignInFrequencyMinutes = 60
        AuthStrength = "phishing-resistant"
        Source = "Dataverse"
    }

.EXAMPLE
    # Using current Graph context token
    Connect-MgGraph -Scopes "https://contoso.crm.dynamics.com/.default"
    Get-DataverseThreshold -DataverseUrl "https://contoso.crm.dynamics.com" -Zone Zone2

    Returns:
    @{
        SignInFrequencyMinutes = 240
        AuthStrength = "passwordless"
        Source = "Dataverse"
    }

.EXAMPLE
    # Graceful failure when Dataverse unavailable
    Get-DataverseThreshold -DataverseUrl "https://invalid.crm.dynamics.com" -Zone Zone1
    # Returns: $null
    # Writes warning with error details

.OUTPUTS
    System.Collections.Hashtable or $null
    Returns hashtable with SignInFrequencyMinutes, AuthStrength, and Source properties
    when successful. Returns $null on failure (network error, auth error, env vars not deployed).

.NOTES
    Version: 1.0.0

    Requires:
    - Dataverse environment with SSC environment variables deployed (Plan 02-02)
    - Bearer token with Dataverse Web API scope
    - Network connectivity to Dataverse environment

    Environment variables queried:
    - fsi_SSC_Zone1SignInFrequencyMinutes, fsi_SSC_Zone1AuthStrength
    - fsi_SSC_Zone2SignInFrequencyMinutes, fsi_SSC_Zone2AuthStrength
    - fsi_SSC_Zone3SignInFrequencyMinutes, fsi_SSC_Zone3AuthStrength

    The Dataverse Web API scope is different from Graph API scope. Callers must provide
    an appropriate token via -AccessToken parameter or ensure the current Graph context
    has a Dataverse-scoped token.

    Error handling:
    This helper never throws exceptions. Returns $null on any failure to allow callers
    to implement graceful fallback to local JSON baseline files.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $true)]
    [ValidateSet("Zone1", "Zone2", "Zone3")]
    [string]$Zone,

    [Parameter(Mandatory = $false)]
    [string]$AccessToken
)

$ErrorActionPreference = "Stop"

function Get-DataverseThreshold {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$DataverseUrl,

        [Parameter(Mandatory = $true)]
        [ValidateSet("Zone1", "Zone2", "Zone3")]
        [string]$Zone,

        [Parameter(Mandatory = $false)]
        [string]$AccessToken
    )

    try {
        # Build authorization headers
        $token = $null

        if ($AccessToken) {
            $token = $AccessToken
            Write-Verbose "Using provided access token for Dataverse authentication."
        }
        else {
            # Attempt to get token from current Graph context
            try {
                $context = Get-MgContext -ErrorAction SilentlyContinue
                if ($context -and $context.AccessToken) {
                    $token = $context.AccessToken
                    Write-Verbose "Using access token from current Microsoft Graph session."
                }
            }
            catch {
                Write-Verbose "Failed to retrieve token from Graph context: $($_.Exception.Message)"
            }
        }

        if (-not $token) {
            Write-Warning "No access token available. Provide token via -AccessToken parameter or connect to Graph with Dataverse scope."
            return $null
        }

        $headers = @{
            "Authorization" = "Bearer $token"
            "Accept" = "application/json"
            "OData-MaxVersion" = "4.0"
            "OData-Version" = "4.0"
        }

        # Build OData query for environment variable definitions
        $filter = "startswith(schemaname,'fsi_SSC_$Zone')"
        $select = "schemaname"
        $expand = "environmentvariablevalues(`$select=value)"
        $apiUrl = "$DataverseUrl/api/data/v9.2/environmentvariabledefinitions?`$filter=$filter&`$select=$select&`$expand=$expand"

        Write-Verbose "Querying Dataverse environment variables for zone: $Zone"
        Write-Verbose "API URL: $apiUrl"

        # Query Dataverse Web API
        $response = Invoke-RestMethod -Uri $apiUrl -Method Get -Headers $headers -ErrorAction Stop

        # Parse response
        if (-not $response.value -or $response.value.Count -eq 0) {
            Write-Warning "No environment variables found with fsi_SSC_$Zone prefix. Ensure environment variables are deployed."
            return $null
        }

        Write-Verbose "Found $($response.value.Count) environment variable(s) for zone: $Zone"

        # Extract values from response
        $signInFrequencyMinutes = $null
        $authStrength = $null

        foreach ($envVar in $response.value) {
            $schemaName = $envVar.schemaname

            if ($schemaName -eq "fsi_SSC_${Zone}SignInFrequencyMinutes") {
                if ($envVar.environmentvariablevalues -and $envVar.environmentvariablevalues.Count -gt 0) {
                    # Environment variable values are stored as strings - convert to int
                    $signInFrequencyMinutes = [int]$envVar.environmentvariablevalues[0].value
                    Write-Verbose "  SignInFrequencyMinutes: $signInFrequencyMinutes"
                }
            }
            elseif ($schemaName -eq "fsi_SSC_${Zone}AuthStrength") {
                if ($envVar.environmentvariablevalues -and $envVar.environmentvariablevalues.Count -gt 0) {
                    $authStrength = $envVar.environmentvariablevalues[0].value
                    Write-Verbose "  AuthStrength: $authStrength"
                }
            }
        }

        # Return structured result
        if ($null -ne $signInFrequencyMinutes -or $null -ne $authStrength) {
            return @{
                SignInFrequencyMinutes = $signInFrequencyMinutes
                AuthStrength = $authStrength
                Source = "Dataverse"
            }
        }
        else {
            Write-Warning "Environment variables found but no values configured. Check environment variable deployment."
            return $null
        }
    }
    catch {
        Write-Warning "Failed to query Dataverse environment variables: $($_.Exception.Message)"
        Write-Verbose "Error details: $($_.Exception | Format-List * | Out-String)"
        return $null
    }
}

# Execute function if script is run directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    $result = Get-DataverseThreshold @PSBoundParameters
    return $result
}

# Export function if this script is dot-sourced
Export-ModuleMember -Function Get-DataverseThreshold
