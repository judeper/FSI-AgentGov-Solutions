#Requires -Version 7.0
#Requires -Modules @{ ModuleName="Microsoft.PowerApps.Administration.PowerShell"; ModuleVersion="2.0" }

<#
.SYNOPSIS
    Connects to Power Platform Admin API and Dataverse Web API.

.DESCRIPTION
    Establishes authentication for both Power Platform Admin API (via PowerShell module)
    and Dataverse Web API (via MSAL token acquisition). Supports both interactive
    authentication and service principal (certificate-based or client secret) authentication.

    Power Platform Admin API connection is required for environment discovery and
    administration operations. Dataverse Web API connection is required for direct
    table operations (environment registry, validation history).

.PARAMETER TenantId
    Azure AD tenant ID. Required for all authentication methods.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com). Required for
    Dataverse Web API token acquisition.

.PARAMETER ClientId
    Azure AD application (client) ID. Required for service principal authentication.
    Optional for interactive authentication (uses well-known Power Apps client ID if not provided).

.PARAMETER ClientSecret
    Client secret for service principal authentication. Must be provided as SecureString.
    Required when using client secret authentication.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication. Certificate must be
    installed in the local machine or current user certificate store.
    Required when using certificate authentication.

.PARAMETER Interactive
    Use interactive authentication (device code or browser-based). Default authentication mode.

.EXAMPLE
    Connect-PowerPlatform -TenantId "contoso.onmicrosoft.com" -DataverseUrl "https://org.crm.dynamics.com" -Interactive
    Connects using interactive authentication with default Power Apps client ID.

.EXAMPLE
    $secret = ConvertTo-SecureString "client-secret" -AsPlainText -Force
    Connect-PowerPlatform -TenantId "contoso.onmicrosoft.com" -DataverseUrl "https://org.crm.dynamics.com" -ClientId "12345..." -ClientSecret $secret
    Connects using service principal authentication with client secret.

.EXAMPLE
    Connect-PowerPlatform -TenantId "contoso.onmicrosoft.com" -DataverseUrl "https://org.crm.dynamics.com" -ClientId "12345..." -CertificateThumbprint "ABCDEF..."
    Connects using service principal authentication with certificate thumbprint.

.NOTES
    Version: 1.0.0
    Requires Microsoft.PowerApps.Administration.PowerShell module v2.0 or later.
    Requires MSAL.PS module for Dataverse token acquisition.

    IMPORTANT: Power Platform Administrator or Global Administrator role is required
    for environment discovery operations (Get-AdminPowerAppEnvironment).

    Well-known Power Apps client ID for interactive auth: 1950a258-227b-4e31-a9cf-717495945fc2

.OUTPUTS
    Hashtable with authentication status:
    - PowerAppsAuthenticated (bool): True if Power Platform Admin API connection succeeded
    - DataverseAccessToken (string): Bearer token for Dataverse Web API
    - DataverseUrl (string): Dataverse organization URL
    - TenantId (string): Azure AD tenant ID
    - AuthMethod (string): "Interactive", "ServicePrincipal-Secret", or "ServicePrincipal-Certificate"
#>

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $false, ParameterSetName = 'ServicePrincipalSecret')]
    [Parameter(Mandatory = $false, ParameterSetName = 'ServicePrincipalCertificate')]
    [Parameter(Mandatory = $false, ParameterSetName = 'Interactive')]
    [string]$ClientId,

    [Parameter(Mandatory = $true, ParameterSetName = 'ServicePrincipalSecret')]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory = $true, ParameterSetName = 'ServicePrincipalCertificate')]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $false, ParameterSetName = 'Interactive')]
    [switch]$Interactive
)

$ErrorActionPreference = "Stop"

# Well-known Power Apps client ID for interactive authentication
$PowerAppsClientId = "1950a258-227b-4e31-a9cf-717495945fc2"

function Connect-PowerPlatform {
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$DataverseUrl,

        [Parameter(Mandatory = $false)]
        [string]$ClientId,

        [Parameter(Mandatory = $false)]
        [SecureString]$ClientSecret,

        [Parameter(Mandatory = $false)]
        [string]$CertificateThumbprint,

        [Parameter(Mandatory = $false)]
        [switch]$Interactive
    )

    $result = @{
        PowerAppsAuthenticated = $false
        DataverseAccessToken   = $null
        DataverseUrl           = $DataverseUrl
        TenantId               = $TenantId
        AuthMethod             = $null
    }

    try {
        # Normalize Dataverse URL (remove trailing slash)
        $DataverseUrl = $DataverseUrl.TrimEnd('/')

        # Determine authentication method
        if ($ClientSecret) {
            $authMethod = "ServicePrincipal-Secret"
        }
        elseif ($CertificateThumbprint) {
            $authMethod = "ServicePrincipal-Certificate"
        }
        else {
            $authMethod = "Interactive"
        }

        $result.AuthMethod = $authMethod

        Write-Host "Authenticating to Power Platform ($authMethod)..." -ForegroundColor Cyan

        # Phase 1: Connect to Power Platform Admin API
        if ($authMethod -eq "ServicePrincipal-Secret") {
            if (-not $ClientId) {
                throw "ClientId is required for service principal authentication."
            }

            # Convert SecureString to plain text for Add-PowerAppsAccount
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)
            $plainSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

            try {
                Add-PowerAppsAccount -TenantID $TenantId -ApplicationId $ClientId -ClientSecret $plainSecret -ErrorAction Stop | Out-Null
                Write-Host "Connected to Power Platform Admin API (service principal)." -ForegroundColor Green
                $result.PowerAppsAuthenticated = $true
            }
            finally {
                # Clear plain text secret from memory
                $plainSecret = $null
            }
        }
        elseif ($authMethod -eq "ServicePrincipal-Certificate") {
            if (-not $ClientId) {
                throw "ClientId is required for service principal authentication."
            }

            # Add-PowerAppsAccount with certificate thumbprint
            Add-PowerAppsAccount -TenantID $TenantId -ApplicationId $ClientId -CertificateThumbprint $CertificateThumbprint -ErrorAction Stop | Out-Null
            Write-Host "Connected to Power Platform Admin API (certificate)." -ForegroundColor Green
            $result.PowerAppsAuthenticated = $true
        }
        else {
            # Interactive authentication
            Add-PowerAppsAccount -TenantID $TenantId -ErrorAction Stop | Out-Null
            Write-Host "Connected to Power Platform Admin API (interactive)." -ForegroundColor Green
            $result.PowerAppsAuthenticated = $true
        }

        # Phase 2: Acquire Dataverse Web API token
        Write-Host "Acquiring Dataverse Web API token..." -ForegroundColor Cyan

        # Construct Dataverse resource scope
        $dataverseScope = "$DataverseUrl/.default"

        if ($authMethod -eq "ServicePrincipal-Secret") {
            # Use MSAL.PS for token acquisition with client secret
            try {
                Import-Module MSAL.PS -ErrorAction Stop
            }
            catch {
                throw "MSAL.PS module not found. Install with: Install-Module MSAL.PS"
            }

            # Convert SecureString to plain text for MSAL
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)
            $plainSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

            try {
                $tokenResult = Get-MsalToken `
                    -ClientId $ClientId `
                    -ClientSecret (ConvertTo-SecureString $plainSecret -AsPlainText -Force) `
                    -TenantId $TenantId `
                    -Scopes $dataverseScope `
                    -ErrorAction Stop

                $result.DataverseAccessToken = $tokenResult.AccessToken
                Write-Host "Acquired Dataverse Web API token (service principal)." -ForegroundColor Green
            }
            finally {
                # Clear plain text secret from memory
                $plainSecret = $null
            }
        }
        elseif ($authMethod -eq "ServicePrincipal-Certificate") {
            # Use MSAL.PS for token acquisition with certificate
            try {
                Import-Module MSAL.PS -ErrorAction Stop
            }
            catch {
                throw "MSAL.PS module not found. Install with: Install-Module MSAL.PS"
            }

            # Get certificate from store
            $cert = Get-Item "Cert:\*\$CertificateThumbprint" -ErrorAction SilentlyContinue
            if (-not $cert) {
                throw "Certificate with thumbprint $CertificateThumbprint not found in certificate store."
            }

            $tokenResult = Get-MsalToken `
                -ClientId $ClientId `
                -ClientCertificate $cert `
                -TenantId $TenantId `
                -Scopes $dataverseScope `
                -ErrorAction Stop

            $result.DataverseAccessToken = $tokenResult.AccessToken
            Write-Host "Acquired Dataverse Web API token (certificate)." -ForegroundColor Green
        }
        else {
            # Interactive authentication: Use device code flow or browser
            try {
                Import-Module MSAL.PS -ErrorAction Stop
            }
            catch {
                throw "MSAL.PS module not found. Install with: Install-Module MSAL.PS"
            }

            # Use well-known Power Apps client ID if no custom ClientId provided
            $effectiveClientId = if ($ClientId) { $ClientId } else { $PowerAppsClientId }

            $tokenResult = Get-MsalToken `
                -ClientId $effectiveClientId `
                -TenantId $TenantId `
                -Scopes $dataverseScope `
                -Interactive `
                -ErrorAction Stop

            $result.DataverseAccessToken = $tokenResult.AccessToken
            Write-Host "Acquired Dataverse Web API token (interactive)." -ForegroundColor Green
        }

        return $result
    }
    catch [System.Management.Automation.CommandNotFoundException] {
        $missingCommand = $_.Exception.Message
        if ($missingCommand -like "*Add-PowerAppsAccount*") {
            throw "Microsoft.PowerApps.Administration.PowerShell module not found. Install with: Install-Module Microsoft.PowerApps.Administration.PowerShell -MinimumVersion 2.0"
        }
        elseif ($missingCommand -like "*Get-MsalToken*") {
            throw "MSAL.PS module not found. Install with: Install-Module MSAL.PS"
        }
        else {
            throw "Required module not found: $missingCommand"
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
        throw "Failed to authenticate to Power Platform: $errorMsg"
    }
}

# Execute function if script is run directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    $authResult = Connect-PowerPlatform @PSBoundParameters
    return $authResult
}

# Note: This script is dot-sourced; do not use Export-ModuleMember outside a .psm1 module.
