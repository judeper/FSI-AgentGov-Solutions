<#
.SYNOPSIS
    Establishes or reuses a Microsoft Graph session for Conditional Access operations.

.DESCRIPTION
    Connects to Microsoft Graph with the scopes required for Conditional Access policy
    management. If an existing Graph context is detected for the same tenant with
    matching scopes, the session is reused without reconnecting.

    This helper supports WhatIf mode to preview which scopes would be requested
    without actually connecting.

.PARAMETER TenantId
    The Azure AD tenant GUID to connect to.

.PARAMETER Scopes
    Optional array of Graph permission scopes to request. Defaults to
    Policy.Read.All, Policy.ReadWrite.ConditionalAccess, and Application.Read.All.

.EXAMPLE
    Connect-CAAGraphSession -TenantId '00000000-0000-0000-0000-000000000000'

    Connects to the specified tenant with default CA management scopes.

.EXAMPLE
    Connect-CAAGraphSession -TenantId '00000000-0000-0000-0000-000000000000' -Scopes @('Policy.Read.All') -WhatIf

    Shows which scopes would be requested without connecting.

.EXAMPLE
    $ctx = Connect-CAAGraphSession -TenantId '00000000-0000-0000-0000-000000000000' -Verbose

    Connects with verbose output and captures the resulting MgContext object.

.OUTPUTS
    Microsoft.Graph.PowerShell.Authentication.AuthContext
    The active Graph context after connection.

.NOTES
    File: Connect-GraphSession.ps1
    Version: 1.0.0
    Requires: Microsoft.Graph.Authentication module
#>

function Connect-CAAGraphSession {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId,

        [Parameter()]
        [string[]]$Scopes = @(
            'Policy.Read.All',
            'Policy.ReadWrite.ConditionalAccess',
            'Application.Read.All'
        )
    )

    $ErrorActionPreference = 'Stop'

    Write-Verbose "Requesting Graph session for tenant: $TenantId"
    Write-Verbose "Scopes requested: $($Scopes -join ', ')"

    if ($PSCmdlet.ShouldProcess(
        "Microsoft Graph (Tenant: $TenantId)",
        "Connect with scopes: $($Scopes -join ', ')"
    )) {
        # Check for existing Graph context
        try {
            $existingContext = Get-MgContext
        } catch {
            Write-Verbose "No existing Graph context detected"
            $existingContext = $null
        }

        if ($existingContext -and $existingContext.TenantId -eq $TenantId) {
            Write-Verbose "Existing Graph context found for tenant $TenantId"

            # Check if existing scopes cover what we need
            $existingScopes = $existingContext.Scopes
            $missingScopes = $Scopes | Where-Object { $_ -notin $existingScopes }

            if (-not $missingScopes) {
                Write-Verbose "Existing session has all required scopes — reusing connection"
                return $existingContext
            }

            Write-Verbose "Existing session missing scopes: $($missingScopes -join ', ') — reconnecting"
        }

        # Connect to Graph with requested scopes
        Write-Verbose "Connecting to Microsoft Graph..."
        Connect-MgGraph -TenantId $TenantId -Scopes $Scopes -ErrorAction Stop | Out-Null

        $context = Get-MgContext
        Write-Verbose "Connected to tenant $($context.TenantId) as $($context.Account)"

        return $context
    }
}
