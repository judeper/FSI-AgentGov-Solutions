#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Authentication

<#
.SYNOPSIS
    Connects to Microsoft Graph for Conditional Access policy management.

.DESCRIPTION
    Establishes connection to Microsoft Graph with required scopes for Conditional Access
    session security operations. Supports both interactive authentication and service
    principal (certificate-based) authentication.

    Checks for existing Graph context and reuses if tenant matches, avoiding
    redundant authentication prompts.

.PARAMETER TenantId
    Azure AD tenant ID. Optional for interactive auth, required for service principal.

.PARAMETER Interactive
    Use interactive authentication (browser-based). Default authentication mode.

.PARAMETER ClientId
    Azure AD application (client) ID. Required for service principal authentication.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication. Certificate must be
    installed in the local machine or current user certificate store.

.PARAMETER Scopes
    Graph API permission scopes. Defaults to Conditional Access policy management scopes.

.EXAMPLE
    Connect-GraphSession -Interactive
    Connects to Microsoft Graph using interactive authentication.

.EXAMPLE
    Connect-GraphSession -TenantId "contoso.onmicrosoft.com" -ClientId "12345..." -CertificateThumbprint "ABCDEF..."
    Connects using service principal authentication with certificate thumbprint.

.OUTPUTS
    Microsoft.Graph.PowerShell.Authentication.Models.GraphContext
    Returns the authenticated Graph context object.

.NOTES
    Version: 1.0.0
    Requires Microsoft.Graph.Authentication module v2.35.1 or later.

    Default scopes:
    - Policy.ReadWrite.ConditionalAccess: CA policy CRUD operations
    - Policy.Read.All: Read all CA policies, auth contexts, auth strength
#>

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false, ParameterSetName = 'Interactive')]
    [switch]$Interactive,

    [Parameter(Mandatory = $true, ParameterSetName = 'ServicePrincipal')]
    [string]$ClientId,

    [Parameter(Mandatory = $true, ParameterSetName = 'ServicePrincipal')]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [string[]]$Scopes = @("Policy.ReadWrite.ConditionalAccess", "Policy.Read.All")
)

$ErrorActionPreference = "Stop"

function Connect-GraphSession {
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantId,

        [Parameter(Mandatory = $false, ParameterSetName = 'Interactive')]
        [switch]$Interactive,

        [Parameter(Mandatory = $true, ParameterSetName = 'ServicePrincipal')]
        [string]$ClientId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ServicePrincipal')]
        [string]$CertificateThumbprint,

        [Parameter(Mandatory = $false)]
        [string[]]$Scopes = @("Policy.ReadWrite.ConditionalAccess", "Policy.Read.All")
    )

    try {
        # Check for existing Graph connection
        $existingContext = Get-MgContext -ErrorAction SilentlyContinue

        if ($existingContext) {
            # Check if existing connection matches requested tenant
            if ($TenantId -and $existingContext.TenantId -ne $TenantId) {
                Write-Host "Existing Graph connection to different tenant. Reconnecting..." -ForegroundColor Yellow
                Disconnect-MgGraph -ErrorAction SilentlyContinue
            }
            else {
                Write-Host "Using existing Graph connection to tenant: $($existingContext.TenantId)" -ForegroundColor Cyan
                return $existingContext
            }
        }

        Write-Host "Connecting to Microsoft Graph..." -ForegroundColor Cyan

        # Build authentication parameters hashtable
        $authParams = @{}

        if ($PSCmdlet.ParameterSetName -eq 'ServicePrincipal') {
            # Service principal authentication
            if (-not $TenantId) {
                throw "TenantId is required for service principal authentication."
            }

            $authParams.ClientId = $ClientId
            $authParams.CertificateThumbprint = $CertificateThumbprint
            $authParams.TenantId = $TenantId

            Write-Host "Authenticating as service principal..." -ForegroundColor Cyan
        }
        else {
            # Interactive authentication
            $authParams.Scopes = $Scopes

            if ($TenantId) {
                $authParams.TenantId = $TenantId
            }

            Write-Host "Launching interactive authentication..." -ForegroundColor Cyan
        }

        # Connect to Microsoft Graph
        Connect-MgGraph @authParams -NoWelcome -ErrorAction Stop

        # Retrieve and return context
        $context = Get-MgContext
        Write-Host "Connected to Microsoft Graph." -ForegroundColor Green
        Write-Host "Tenant: $($context.TenantId)" -ForegroundColor Cyan
        Write-Host "Account: $($context.Account)" -ForegroundColor Cyan
        Write-Host "Scopes: $($context.Scopes -join ', ')" -ForegroundColor Cyan

        return $context
    }
    catch [System.Management.Automation.CommandNotFoundException] {
        throw "Microsoft.Graph.Authentication module not found. Install with: Install-Module Microsoft.Graph.Authentication -MinimumVersion 2.35.1"
    }
    catch {
        throw "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    }
}

function Disconnect-GraphSession {
    <#
    .SYNOPSIS
        Disconnects from Microsoft Graph session.

    .DESCRIPTION
        Cleanly disconnects the active Microsoft Graph session.
        Errors are silently ignored to allow cleanup even if connection was not established.

    .EXAMPLE
        Disconnect-GraphSession
        Disconnects from Microsoft Graph.

    .NOTES
        Safe to call even if connection was not established.
    #>

    try {
        Write-Host "Disconnecting from Microsoft Graph..." -ForegroundColor Cyan
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        Write-Host "Disconnected from Microsoft Graph." -ForegroundColor Green
    }
    catch {
        # Silently ignore errors during disconnect
        Write-Host "Warning: Error during disconnect (safely ignored): $($_.Exception.Message)" -ForegroundColor Yellow
    }
}


