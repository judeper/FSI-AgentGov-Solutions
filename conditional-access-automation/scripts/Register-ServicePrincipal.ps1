<#
.SYNOPSIS
    Registers a service principal for CA policy automation.

.DESCRIPTION
    Creates an Entra ID app registration with required Graph API permissions
    for Conditional Access policy management, and stores credentials in Key Vault.

.PARAMETER TenantId
    Azure AD tenant ID.

.PARAMETER AppName
    Display name for the app registration.

.PARAMETER KeyVaultName
    Azure Key Vault name for credential storage.

.PARAMETER DryRun
    Preview changes without creating resources.

.EXAMPLE
    .\Register-ServicePrincipal.ps1 -TenantId "xxx" -AppName "CAA-Automation-SP" -KeyVaultName "kv-caa"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$AppName,

    [Parameter(Mandatory = $true)]
    [string]$KeyVaultName,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun
)

#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Applications, Az.KeyVault

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Service Principal Registration" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Tenant: $TenantId"
Write-Host "App Name: $AppName"
Write-Host "Key Vault: $KeyVaultName"
Write-Host "Mode: $(if ($DryRun) { 'DRY RUN' } else { 'CREATE' })"
Write-Host ""

# Define required permissions
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

Write-Host "Required Microsoft Graph permissions:"
Write-Host "  - Policy.Read.All"
Write-Host "  - Policy.ReadWrite.ConditionalAccess"
Write-Host "  - Application.Read.All"
Write-Host "  - Directory.Read.All"
Write-Host "  - AuditLog.Read.All"
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN] Would perform the following:" -ForegroundColor Yellow
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
Write-Host "Connecting to Microsoft Graph..."
Connect-MgGraph -TenantId $TenantId -Scopes "Application.ReadWrite.All"
Write-Host "Connected." -ForegroundColor Green

# Check if app already exists
Write-Host "`nChecking for existing app registration..."
$existingApp = Get-MgApplication -Filter "displayName eq '$AppName'" -ErrorAction SilentlyContinue

if ($existingApp) {
    Write-Host "App registration already exists: $($existingApp.AppId)" -ForegroundColor Yellow
    $response = Read-Host "Do you want to update it? (y/n)"
    if ($response -ne "y") {
        Write-Host "Aborted." -ForegroundColor Yellow
        return
    }
    $app = $existingApp
}
else {
    # Create app registration
    Write-Host "`nCreating app registration..."
    $appParams = @{
        DisplayName = $AppName
        SignInAudience = "AzureADMyOrg"
        RequiredResourceAccess = $requiredPermissions
    }
    $app = New-MgApplication @appParams
    Write-Host "Created app: $($app.AppId)" -ForegroundColor Green
}

# Create service principal if it doesn't exist
Write-Host "`nChecking service principal..."
$sp = Get-MgServicePrincipal -Filter "appId eq '$($app.AppId)'" -ErrorAction SilentlyContinue
if (-not $sp) {
    Write-Host "Creating service principal..."
    $sp = New-MgServicePrincipal -AppId $app.AppId
    Write-Host "Created service principal: $($sp.Id)" -ForegroundColor Green
}
else {
    Write-Host "Service principal exists: $($sp.Id)"
}

# Create client secret
Write-Host "`nCreating client secret..."
$secretParams = @{
    PasswordCredential = @{
        DisplayName = "CAA-Automation-Secret"
        EndDateTime = (Get-Date).AddYears(1)
    }
}
$secret = Add-MgApplicationPassword -ApplicationId $app.Id -BodyParameter $secretParams
Write-Host "Client secret created (expires: $($secret.EndDateTime))" -ForegroundColor Green

# Store in Key Vault
Write-Host "`nStoring credentials in Key Vault..."
try {
    Connect-AzAccount -TenantId $TenantId -ErrorAction Stop | Out-Null

    # Store client ID
    $clientIdSecret = ConvertTo-SecureString $app.AppId -AsPlainText -Force
    Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "CAA-SP-ClientId" -SecretValue $clientIdSecret | Out-Null
    Write-Host "  Stored: CAA-SP-ClientId" -ForegroundColor Green

    # Store client secret
    $clientSecretValue = ConvertTo-SecureString $secret.SecretText -AsPlainText -Force
    Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "CAA-SP-ClientSecret" -SecretValue $clientSecretValue | Out-Null
    Write-Host "  Stored: CAA-SP-ClientSecret" -ForegroundColor Green

    # Store tenant ID
    $tenantIdSecret = ConvertTo-SecureString $TenantId -AsPlainText -Force
    Set-AzKeyVaultSecret -VaultName $KeyVaultName -Name "CAA-TenantId" -SecretValue $tenantIdSecret | Out-Null
    Write-Host "  Stored: CAA-TenantId" -ForegroundColor Green
}
catch {
    Write-Host "Warning: Could not store in Key Vault: $_" -ForegroundColor Yellow
    Write-Host "Please manually store the following:" -ForegroundColor Yellow
    Write-Host "  Client ID: $($app.AppId)"
    Write-Host "  Client Secret: $($secret.SecretText)"
}

# Output summary
Write-Host "`n" + "=" * 60 -ForegroundColor Cyan
Write-Host "Service Principal Created" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan

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
