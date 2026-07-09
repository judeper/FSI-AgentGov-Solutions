#Requires -Version 7.2
#Requires -Modules @{ ModuleName="Microsoft.PowerApps.Administration.PowerShell"; ModuleVersion="2.0.180" }
#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    Connects to Power Platform Admin API and Dataverse Web API.

.DESCRIPTION
    Establishes authentication for both Power Platform Admin API (via PowerShell module)
    and Dataverse Web API (via Az.Accounts token acquisition). Supports both interactive
    authentication and service principal authentication. Prefer certificate-based or managed identity paths; client-secret auth is a legacy dev-only fallback.

    Power Platform Admin API connection is required for environment discovery and
    administration operations. Dataverse Web API connection is required for direct
    table operations (environment registry, validation history).

.PARAMETER TenantId
    Microsoft Entra ID tenant ID. Required for all authentication methods.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com). Required for
    Dataverse Web API token acquisition.

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID. Required for service principal authentication.
    Optional for interactive authentication(uses well-known Power Apps client ID if not provided).

.PARAMETER ClientSecret
    Legacy dev-only client secret for service principal authentication. Must be provided as SecureString.
    Prefer certificate-based authentication or managed identity where supported.

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
    Connects using legacy dev-only service principal client-secret authentication.

.EXAMPLE
    Connect-PowerPlatform -TenantId "contoso.onmicrosoft.com" -DataverseUrl "https://org.crm.dynamics.com" -ClientId "12345..." -CertificateThumbprint "ABCDEF..."
    Connects using service principal authentication with certificate thumbprint.

.NOTES
    Version: 1.0.2
    Requires Microsoft.PowerApps.Administration.PowerShell module v2.0 or later.
    Requires Az.Accounts module for Dataverse token acquisition.

    IMPORTANT: Power Platform Admin or Entra Global Admin role is required
    for environment discovery operations (Get-AdminPowerAppEnvironment).

.OUTPUTS
    Hashtable with authentication status:
    - PowerAppsAuthenticated (bool): True if Power Platform Admin API connection succeeded
    - DataverseAccessToken (string): Bearer token for Dataverse Web API
    - DataverseUrl (string): Dataverse organization URL
    - TenantId (string): Microsoft Entra ID tenant ID
    - AuthMethod (string): "Interactive", "ServicePrincipal-Secret", or "ServicePrincipal-Certificate"
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Dev-only legacy auth path. Production deployments use managed identity via scripts/shared/dataverse_client.py per AGENTS.md "Authentication standard". Plaintext secret here is wrapped immediately into SecureString and never persisted.'
)]
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

function Connect-PowerPlatform {
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', '',
        Justification = 'PSScriptAnalyzer requires this rule suppression on the function param block; individual compatibility parameters carry specific justifications.'
    )]
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
        [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
            'PSReviewUnusedParameter', '',
            Justification = 'Required by the authentication parameter-set contract; the selected parameter set drives behavior in this implementation.'
        )]
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
            # legacy: dev-only — replace with managed identity in production
            # Use OAuth 2.0 client credentials grant directly (no MSAL dependency)
            $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)
            $plainSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
            [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)

            try {
                $body = @{
                    grant_type    = 'client_credentials'
                    client_id     = $ClientId
                    client_secret = $plainSecret
                    scope         = $dataverseScope
                }
                $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
                $tokenResponse = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
                $result.DataverseAccessToken = $tokenResponse.access_token
                Write-Host "Acquired Dataverse Web API token (service principal)." -ForegroundColor Green
            }
            finally {
                # Clear plain text secret from memory
                $plainSecret = $null
            }
        }
        elseif ($authMethod -eq "ServicePrincipal-Certificate") {
            # Certificate-based service principal via Az.Accounts
            Import-Module Az.Accounts -ErrorAction Stop

            Connect-AzAccount -ServicePrincipal `
                -ApplicationId $ClientId `
                -CertificateThumbprint $CertificateThumbprint `
                -Tenant $TenantId `
                -ErrorAction Stop | Out-Null

            try {
                $tokenResult = Get-AzAccessToken -ResourceUrl $DataverseUrl -ErrorAction Stop
            }
            catch {
                $tokenResult = Get-AzAccessToken -ResourceUri $DataverseUrl -ErrorAction Stop
            }

            # Az.Accounts 5.x returns the token as a SecureString by default; convert it
            # back to a plain string for the Dataverse Web API Authorization header.
            $rawToken = $tokenResult.Token
            if ($rawToken -is [System.Security.SecureString]) {
                $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($rawToken)
                try {
                    $rawToken = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
                }
                finally {
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                }
            }

            $result.DataverseAccessToken = [string]$rawToken
            Write-Host "Acquired Dataverse Web API token (certificate)." -ForegroundColor Green
        }
        else {
            # Interactive authentication via Az.Accounts (uses existing Azure context)
            Import-Module Az.Accounts -ErrorAction Stop

            $context = Get-AzContext -ErrorAction Stop
            if (-not $context) {
                $errorMessage = "No Azure context found. You must connect to Azure first."
                $errorMessage += "`n"
                $errorMessage += "`n  Remediation:"
                $errorMessage += "`n  1. Run: Connect-AzAccount"
                $errorMessage += "`n  2. Select the correct subscription if needed"
                $errorMessage += "`n  3. Re-run this script"
                throw $errorMessage
            }

            Write-Verbose "Using Azure context: $($context.Account.Id) in tenant $($context.Tenant.Id)"

            try {
                $tokenResult = Get-AzAccessToken -ResourceUrl $DataverseUrl -ErrorAction Stop
            }
            catch {
                $tokenResult = Get-AzAccessToken -ResourceUri $DataverseUrl -ErrorAction Stop
            }

            # Az.Accounts 5.x returns the token as a SecureString by default; convert it
            # back to a plain string for the Dataverse Web API Authorization header.
            $rawToken = $tokenResult.Token
            if ($rawToken -is [System.Security.SecureString]) {
                $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($rawToken)
                try {
                    $rawToken = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
                }
                finally {
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                }
            }

            $result.DataverseAccessToken = [string]$rawToken
            Write-Host "Acquired Dataverse Web API token (interactive)." -ForegroundColor Green
        }

        return $result
    }
    catch [System.Management.Automation.CommandNotFoundException] {
        $missingCommand = $_.Exception.Message
        if ($missingCommand -like "*Add-PowerAppsAccount*") {
            throw "Microsoft.PowerApps.Administration.PowerShell module not found. Install with: Install-Module Microsoft.PowerApps.Administration.PowerShell -MinimumVersion 2.0"
        }
        elseif ($missingCommand -like "*Get-AzAccessToken*" -or $missingCommand -like "*Connect-AzAccount*") {
            throw "Az.Accounts module not found. Install with: Install-Module Az.Accounts -Scope CurrentUser"
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
