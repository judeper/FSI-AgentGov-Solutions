<#
.SYNOPSIS
    Per-environment Dataverse authentication helper.

.DESCRIPTION
    Acquires and caches OAuth tokens for Dataverse environments. Supports three
    authentication modes:
    1. Service principal (PSCredential with ClientId/ClientSecret)
    2. Interactive via Az.Accounts (Get-AzAccessToken)
    3. Existing token passthrough

    Tokens are cached per DataverseUrl to avoid redundant authentication when
    scanning multiple environments in sequence.

.PARAMETER DataverseUrl
    The Dataverse environment URL (e.g., https://org.crm.dynamics.com).

.PARAMETER TenantId
    Azure AD tenant ID for service principal authentication.

.PARAMETER Credential
    PSCredential containing ClientId (UserName) and ClientSecret (Password)
    for service principal authentication.

.PARAMETER Interactive
    Force interactive authentication via Az.Accounts.

.PARAMETER Force
    Bypass token cache and acquire a fresh token.

.OUTPUTS
    String - Bearer access token for the specified Dataverse environment.

.EXAMPLE
    $token = & .\Connect-EnvironmentDataverse.ps1 -DataverseUrl "https://myorg.crm.dynamics.com" -Interactive

.EXAMPLE
    $cred = New-Object PSCredential($clientId, (ConvertTo-SecureString $secret -AsPlainText -Force))
    $token = & .\Connect-EnvironmentDataverse.ps1 -DataverseUrl $url -TenantId $tid -Credential $cred

.NOTES
    File: Connect-EnvironmentDataverse.ps1
    Version: 1.0.0
    Requires: PowerShell 7.0+
#>

#requires -Version 7.0

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^https://.*\.crm.*\.dynamics\.com/?$')]
    [string]$DataverseUrl,

    [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory)]
    [string]$TenantId,

    [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory)]
    [PSCredential]$Credential,

    [Parameter(ParameterSetName = 'Interactive')]
    [switch]$Interactive,

    [switch]$Force
)

# Module-level token cache (persists across calls within the same session)
if (-not $script:TokenCache) {
    $script:TokenCache = @{}
}

$normalizedUrl = $DataverseUrl.TrimEnd('/')

#region Cache Check

if (-not $Force -and $script:TokenCache.ContainsKey($normalizedUrl)) {
    $cached = $script:TokenCache[$normalizedUrl]

    # Check if token is still valid (with 5-minute buffer)
    if ($cached.ExpiresOn -gt (Get-Date).AddMinutes(5)) {
        Write-Verbose "Using cached token for $normalizedUrl (expires: $($cached.ExpiresOn))"
        return $cached.Token
    }

    Write-Verbose "Cached token expired for $normalizedUrl, acquiring new token"
    $script:TokenCache.Remove($normalizedUrl)
}

#endregion

#region Service Principal Authentication

if ($PSCmdlet.ParameterSetName -eq 'ServicePrincipal') {
    Write-Verbose "Authenticating via service principal for $normalizedUrl"

    try {
        $clientId = $Credential.UserName
        $clientSecret = $Credential.GetNetworkCredential().Password

        $body = @{
            grant_type    = 'client_credentials'
            client_id     = $clientId
            client_secret = $clientSecret
            scope         = "$normalizedUrl/.default"
        }

        $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop

        $expiresOn = (Get-Date).AddSeconds($response.expires_in)

        $script:TokenCache[$normalizedUrl] = @{
            Token     = $response.access_token
            ExpiresOn = $expiresOn
        }

        Write-Verbose "Service principal token acquired for $normalizedUrl (expires: $expiresOn)"
        return $response.access_token
    } catch {
        $errorMessage = "Service principal authentication failed for $normalizedUrl."
        $errorMessage += "`n  Tenant: $TenantId"
        $errorMessage += "`n  ClientId: $clientId"
        $errorMessage += "`n  Error: $($_.Exception.Message)"
        $errorMessage += "`n"
        $errorMessage += "`n  Remediation:"
        $errorMessage += "`n  1. Verify the app registration exists in the target tenant"
        $errorMessage += "`n  2. Confirm the client secret has not expired"
        $errorMessage += "`n  3. Check that the app has Dataverse permissions in the target environment"
        $errorMessage += "`n  4. Verify the app is registered as an application user in Dataverse"
        throw $errorMessage
    }
}

#endregion

#region Interactive Authentication (Az.Accounts)

Write-Verbose "Authenticating via Az.Accounts for $normalizedUrl"

# Verify Az.Accounts is available
if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
    $errorMessage = "Az.Accounts module is not installed."
    $errorMessage += "`n"
    $errorMessage += "`n  Remediation:"
    $errorMessage += "`n  1. Install the module: Install-Module -Name Az.Accounts -Force -Scope CurrentUser"
    $errorMessage += "`n  2. Connect to Azure: Connect-AzAccount"
    $errorMessage += "`n  3. Re-run this script"
    throw $errorMessage
}

try {
    # Verify Azure context exists
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

    $tokenResult = Get-AzAccessToken -ResourceUrl $normalizedUrl -ErrorAction Stop

    $expiresOn = if ($tokenResult.ExpiresOn) {
        $tokenResult.ExpiresOn.LocalDateTime
    } else {
        (Get-Date).AddHours(1)
    }

    $script:TokenCache[$normalizedUrl] = @{
        Token     = $tokenResult.Token
        ExpiresOn = $expiresOn
    }

    Write-Verbose "Interactive token acquired for $normalizedUrl (expires: $expiresOn)"
    return $tokenResult.Token
} catch {
    if ($_.Exception.Message -match 'No Azure context found') {
        throw $_
    }

    $errorMessage = "Interactive token acquisition failed for $normalizedUrl."
    $errorMessage += "`n  Account: $($context.Account.Id)"
    $errorMessage += "`n  Tenant: $($context.Tenant.Id)"
    $errorMessage += "`n  Error: $($_.Exception.Message)"
    $errorMessage += "`n"
    $errorMessage += "`n  Remediation:"
    $errorMessage += "`n  1. Ensure your account has Dataverse access in the target environment"
    $errorMessage += "`n  2. Try: Disconnect-AzAccount; Connect-AzAccount"
    $errorMessage += "`n  3. If using MFA, ensure your session is current"
    $errorMessage += "`n  4. Verify the Dataverse URL is correct: $normalizedUrl"
    throw $errorMessage
}

#endregion
