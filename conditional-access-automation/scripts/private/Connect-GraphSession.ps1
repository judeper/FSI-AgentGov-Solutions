<#
.SYNOPSIS
    Establishes or reuses a Microsoft Graph session for Conditional Access operations.

.DESCRIPTION
    Connects to Microsoft Graph with the scopes required for Conditional Access policy
    management. If an existing Graph context is detected for the same tenant with
    matching scopes, the session is reused without reconnecting.

    Three authentication paths are supported:

      - Interactive (default)        : interactive browser flow with delegated scopes.
      - Certificate (app-only)       : -ClientId + -CertificateThumbprint for
                                       unattended Azure Automation runbooks.
      - Managed Identity             : -UseManagedIdentity (system-assigned or
                                       user-assigned with -ClientId) for runbooks
                                       executed under an Azure managed identity.

    This helper supports WhatIf mode to preview which scopes/auth path would be
    used without actually connecting.

.PARAMETER TenantId
    The Microsoft Entra ID tenant GUID to connect to.

.PARAMETER Scopes
    Optional array of Graph permission scopes to request (interactive flow only —
    app-only flows derive permissions from the app registration). Defaults to
    Policy.Read.All, Policy.ReadWrite.ConditionalAccess, and Application.Read.All.

.PARAMETER ClientId
    App registration AppId. Required for certificate auth and for user-assigned
    managed identity.

.PARAMETER CertificateThumbprint
    Local cert store thumbprint of the certificate registered against -ClientId.
    Use with -TenantId for app-only certificate auth.

.PARAMETER UseManagedIdentity
    Connect using the Azure managed identity of the host (system-assigned by
    default; pass -ClientId for user-assigned).

.EXAMPLE
    Connect-CAAGraphSession -TenantId '00000000-0000-0000-0000-000000000000'

    Interactive connection with default CA management scopes.

.EXAMPLE
    Connect-CAAGraphSession -TenantId $tid -ClientId $appId -CertificateThumbprint $thumb

    App-only certificate auth (Azure Automation, scheduled task).

.EXAMPLE
    Connect-CAAGraphSession -TenantId $tid -UseManagedIdentity

    System-assigned managed identity (runbook in an Azure Automation account
    with system MI enabled).

.OUTPUTS
    Microsoft.Graph.PowerShell.Authentication.AuthContext

.NOTES
    File: Connect-GraphSession.ps1
    Version: 1.1.0
    Requires: Microsoft.Graph.Authentication module
#>

function Connect-CAAGraphSession {
    [CmdletBinding(SupportsShouldProcess, DefaultParameterSetName = 'Interactive')]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter(ParameterSetName = 'Interactive')]
        [string[]]$Scopes = @(
            'Policy.Read.All',
            'Policy.ReadWrite.ConditionalAccess',
            'Application.Read.All'
        ),

        [Parameter(Mandatory, ParameterSetName = 'Certificate')]
        [Parameter(ParameterSetName = 'ManagedIdentity')]
        [string]$ClientId,

        [Parameter(Mandatory, ParameterSetName = 'Certificate')]
        [string]$CertificateThumbprint,

        [Parameter(Mandatory, ParameterSetName = 'ManagedIdentity')]
        [switch]$UseManagedIdentity
    )

    $ErrorActionPreference = 'Stop'

    $authMode = $PSCmdlet.ParameterSetName
    Write-Verbose "Requesting Graph session for tenant: $TenantId (auth: $authMode)"
    if ($authMode -eq 'Interactive') {
        Write-Verbose "Scopes requested: $($Scopes -join ', ')"
    }

    $shouldProcessTarget = "Microsoft Graph (Tenant: $TenantId, Auth: $authMode)"
    $shouldProcessAction = switch ($authMode) {
        'Interactive'     { "Connect with scopes: $($Scopes -join ', ')" }
        'Certificate'     { "Connect with certificate $CertificateThumbprint as $ClientId" }
        'ManagedIdentity' { if ($ClientId) { "Connect with user-assigned MI ($ClientId)" } else { "Connect with system-assigned managed identity" } }
    }

    if ($PSCmdlet.ShouldProcess($shouldProcessTarget, $shouldProcessAction)) {
        # Check for existing Graph context
        try {
            $existingContext = Get-MgContext
        } catch {
            Write-Verbose "No existing Graph context detected"
            $existingContext = $null
        }

        if ($existingContext -and $existingContext.TenantId -eq $TenantId) {
            Write-Verbose "Existing Graph context found for tenant $TenantId"

            if ($authMode -eq 'Interactive') {
                $missingScopes = $Scopes | Where-Object { $_ -notin $existingContext.Scopes }
                if (-not $missingScopes) {
                    Write-Verbose "Existing session has all required scopes — reusing connection"
                    return $existingContext
                }
                Write-Verbose "Existing session missing scopes: $($missingScopes -join ', ') — reconnecting"
            } else {
                # App-only / MI: trust existing context if AppId matches.
                if ($ClientId -and $existingContext.ClientId -eq $ClientId) {
                    Write-Verbose "Existing app-only context for ClientId $ClientId — reusing"
                    return $existingContext
                }
            }
        }

        Write-Verbose "Connecting to Microsoft Graph ($authMode)..."
        switch ($authMode) {
            'Interactive' {
                Connect-MgGraph -TenantId $TenantId -Scopes $Scopes -ErrorAction Stop | Out-Null
            }
            'Certificate' {
                Connect-MgGraph -TenantId $TenantId -ClientId $ClientId -CertificateThumbprint $CertificateThumbprint -ErrorAction Stop | Out-Null
            }
            'ManagedIdentity' {
                if ($ClientId) {
                    Connect-MgGraph -Identity -ClientId $ClientId -ErrorAction Stop | Out-Null
                } else {
                    Connect-MgGraph -Identity -ErrorAction Stop | Out-Null
                }
            }
        }

        $context = Get-MgContext
        Write-Verbose "Connected to tenant $($context.TenantId) as $($context.Account)"

        return $context
    }
}
