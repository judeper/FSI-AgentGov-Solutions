<#
.SYNOPSIS
    Registers an Entra ID service principal for Conditional Access policy automation.

.DESCRIPTION
    Creates an Entra ID app registration with the Microsoft Graph API permissions
    required for Conditional Access policy management and stores the resulting
    credentials in Azure Key Vault.

    The app registration receives the following application (Role) permissions:
      - Policy.Read.All — read CA policies and named locations
      - Policy.ReadWrite.ConditionalAccess — create and update CA policies
      - Application.Read.All — enumerate app registrations
      - Directory.Read.All — read directory objects (users, groups)
      - AuditLog.Read.All — read sign-in and audit logs

    Supports WhatIf/Confirm via ShouldProcess so administrators can preview
    each Graph API and Key Vault operation before execution. The legacy -DryRun
    switch is retained for backward compatibility and maps to -WhatIf internally.

.PARAMETER TenantId
    The Entra ID (Azure AD) tenant GUID to register the app in.

.PARAMETER AppName
    Display name for the app registration. Should follow organizational
    naming conventions (e.g., "CAA-Automation-SP").

.PARAMETER KeyVaultName
    Name of the Azure Key Vault where client credentials will be stored.
    The running user must have Set permission on secrets.

.PARAMETER DryRun
    [Obsolete] Legacy switch retained for backward compatibility. Maps to
    -WhatIf internally. Prefer using -WhatIf instead.

.EXAMPLE
    .\Register-ServicePrincipal.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -AppName "CAA-Automation-SP" -KeyVaultName "kv-caa" -WhatIf

    Previews all registration steps without creating any resources.

.EXAMPLE
    .\Register-ServicePrincipal.ps1 -TenantId "contoso.onmicrosoft.com" -AppName "CAA-Automation-SP" -KeyVaultName "kv-caa"

    Creates the app registration, service principal, client secret, and stores
    credentials in Key Vault. Outputs the admin consent URL.

.EXAMPLE
    .\Register-ServicePrincipal.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -AppName "CAA-Prod-SP" -KeyVaultName "kv-caa-prod" -Confirm:$false

    Runs without interactive confirmation prompts.

.OUTPUTS
    None. Status output is written to the host and verbose streams.

.NOTES
    File: Register-ServicePrincipal.ps1
    Version: 2.0.0
    Supports compliance with FINRA 4511 and SEC 17a-4 by establishing
    auditable, least-privilege service identities for CA automation.
#>

[CmdletBinding(SupportsShouldProcess, ConfirmImpact = 'High')]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$AppName,

    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    # [Obsolete("Use -WhatIf instead of -DryRun. -DryRun is retained for backward compatibility.")]
    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Applications, Az.KeyVault

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Import private helpers
. $PSScriptRoot/private/Connect-GraphSession.ps1

# Map legacy -DryRun to WhatIf
if ($DryRun) { $WhatIfPreference = $true }

Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "Service Principal Registration" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "Tenant: $TenantId"
Write-Host "App Name: $AppName"
Write-Host "Key Vault: $KeyVaultName"
Write-Host "Mode: $(if ($WhatIfPreference) { 'DRY RUN (WhatIf)' } else { 'CREATE' })"
Write-Host ""

# Define required permissions with inline documentation
$requiredPermissions = @(
    @{
        ResourceAppId = "00000003-0000-0000-c000-000000000000"  # Microsoft Graph
        Permissions = @(
            @{ Id = "246dd0d5-5bd0-4def-940b-0421030a5b68"; Type = "Role" }  # Policy.Read.All
            @{ Id = "01c0a623-fc9b-48e9-b794-0756f8e8f067"; Type = "Role" }  # Policy.ReadWrite.ConditionalAccess
            @{ Id = "9a5d68dd-52b0-4cc2-bd40-abcf44ac3a30"; Type = "Role" }  # Application.Read.All
            @{ Id = "7ab1d382-f21e-4acd-a863-ba3e13f7da61"; Type = "Role" }  # Directory.Read.All
            @{ Id = "b0afded3-3588-46d8-8b3d-9842eff778da"; Type = "Role" }  # AuditLog.Read.All
        )
    }
)

Write-Verbose "Required Microsoft Graph permissions:"
Write-Verbose "  - 246dd0d5-... = Policy.Read.All"
Write-Verbose "  - 01c0a623-... = Policy.ReadWrite.ConditionalAccess"
Write-Verbose "  - 9a5d68dd-... = Application.Read.All"
Write-Verbose "  - 7ab1d382-... = Directory.Read.All"
Write-Verbose "  - b0afded3-... = AuditLog.Read.All"

if ($WhatIfPreference) {
    Write-Host "[WhatIf] Would perform the following:" -ForegroundColor Yellow
    Write-Host "  1. Create app registration: $AppName"
    Write-Host "  2. Add required Graph API permissions"
    Write-Host "  3. Create client secret (1 year expiry)"
    Write-Host "  4. Store credentials in Key Vault: $KeyVaultName"
    Write-Host "  5. Generate admin consent URL"
    Write-Host ""
    Write-Host "Admin consent URL would be:"
    Write-Host "  https://login.microsoftonline.com/$TenantId/adminconsent?client_id=<app-id>"
    return
}

# Connect to Microsoft Graph
Write-Verbose "Establishing Microsoft Graph session..."
Connect-CAAGraphSession -TenantId $TenantId -Scopes @('Application.ReadWrite.All')
Write-Verbose "Connected."

# Check if app already exists
Write-Verbose "Checking for existing app registration..."
$existingApp = Get-MgApplication -Filter "displayName eq '$AppName'" -ErrorAction SilentlyContinue

if ($existingApp) {
    Write-Verbose "App registration already exists: $($existingApp.AppId)"
    if (-not $PSCmdlet.ShouldContinue(
        "App registration '$AppName' already exists ($($existingApp.AppId)). Update it?",
        "Existing app found"
    )) {
        Write-Host "Aborted." -ForegroundColor Yellow
        return
    }
    $app = $existingApp
}
else {
    # Create app registration
    if ($PSCmdlet.ShouldProcess("App registration: $AppName", "Create in tenant $TenantId")) {
        Write-Verbose "Creating app registration..."
        $appParams = @{
            DisplayName = $AppName
            SignInAudience = "AzureADMyOrg"
            RequiredResourceAccess = $requiredPermissions
        }
        $app = New-MgApplication @appParams
        Write-Verbose "Created app: $($app.AppId)"
    }
    else {
        return
    }
}

# Create service principal if it doesn't exist
Write-Verbose "Checking service principal..."
$sp = Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'" -ErrorAction SilentlyContinue
if (-not $sp) {
    if ($PSCmdlet.ShouldProcess("Service principal for app: $($app.AppId)", "Create in tenant $TenantId")) {
        Write-Verbose "Creating service principal..."
        $sp = New-MgServicePrincipal -AppId $app.AppId
        Write-Verbose "Created service principal: $($sp.Id)"
    }
}
else {
    Write-Verbose "Service principal exists: $($sp.Id)"
}

# Create client secret
if ($PSCmdlet.ShouldProcess("Client secret for app: $AppName", "Create with 1-year expiry")) {
    Write-Verbose "Creating client secret..."
    $secretParams = @{
        PasswordCredential = @{
            DisplayName = "CAA-Automation-Secret"
            EndDateTime = (Get-Date).AddYears(1)
        }
    }
    $secret = Add-MgApplicationPassword -ApplicationId $app.Id -BodyParameter $secretParams
    Write-Verbose "Client secret created (expires: $($secret.EndDateTime))"
}

# Store in Key Vault
if ($PSCmdlet.ShouldProcess("Key Vault: $KeyVaultName", "Store CAA credentials (ClientId, ClientSecret, TenantId)")) {
    Write-Verbose "Storing credentials in Key Vault..."
    try {
        Connect-AzAccount -TenantId $TenantId -ErrorAction Stop | Out-Null

        # Store client ID
        Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "CAA-SP-ClientId" -SecretValue $app.AppId | Out-Null
        Write-Verbose "  Stored: CAA-SP-ClientId"

        # Store client secret
        Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "CAA-SP-ClientSecret" -SecretValue $secret.SecretText | Out-Null
        Write-Verbose "  Stored: CAA-SP-ClientSecret"

        # Store tenant ID
        Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "CAA-TenantId" -SecretValue $TenantId | Out-Null
        Write-Verbose "  Stored: CAA-TenantId"
    }
    catch {
        Write-Host "Warning: Could not store in Key Vault: $_" -ForegroundColor Yellow
        Write-Host "Please manually store the following:" -ForegroundColor Yellow
        Write-Host "  Client ID: $($app.AppId)"
        Write-Host "  Client Secret: $($secret.SecretText)"
    }
}

# Output summary
Write-Host ("`n" + "=" * 60) -ForegroundColor Cyan
Write-Host "Service Principal Created" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan

Write-Host "`nApplication Details:"
Write-Host "  Display Name: $AppName"
Write-Host "  Application ID: $($app.AppId)"
Write-Host "  Object ID: $($app.Id)"
Write-Host "  Service Principal ID: $($sp.Id)"

Write-Host "`nAdmin Consent Required:" -ForegroundColor Yellow
Write-Host "  Open the following URL in a browser and sign in as Global Administrator:"
Write-Host ""
Write-Host "  https://login.microsoftonline.com/$TenantId/adminconsent?client_id=$($app.AppId)" -ForegroundColor Cyan
Write-Host ""

Write-Host "After granting consent, verify with:" -ForegroundColor Yellow
Write-Host '  Get-MgServicePrincipal -Filter "appId eq ''$($app.AppId)''" | Select-Object AppRoleAssignments'

Write-Host "`nRegistration complete." -ForegroundColor Green
