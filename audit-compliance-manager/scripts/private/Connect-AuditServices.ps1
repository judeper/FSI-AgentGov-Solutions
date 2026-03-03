#Requires -Version 7.0
#Requires -Modules @{ ModuleName="ExchangeOnlineManagement"; ModuleVersion="3.7.0" }

<#
.SYNOPSIS
    Connects to Microsoft 365 audit services (Exchange Online and Security & Compliance).

.DESCRIPTION
    Establishes connections to Exchange Online PowerShell and/or Security & Compliance
    PowerShell for audit configuration validation. Supports both interactive authentication
    and service principal (certificate-based) authentication.

    Exchange Online connection is required for Unified Audit Log configuration checks
    (Get-AdminAuditLogConfig). Security & Compliance connection is required for Purview
    retention policy validation (Get-UnifiedAuditLogRetentionPolicy).

.PARAMETER TenantId
    Azure AD tenant ID. Required for service principal authentication.

.PARAMETER ClientId
    Azure AD application (client) ID. Required for service principal authentication.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication. Certificate must be
    installed in the local machine or current user certificate store.

.PARAMETER CertificateFilePath
    Path to certificate file (.pfx) for service principal authentication. Alternative
    to CertificateThumbprint.

.PARAMETER Interactive
    Use interactive authentication (browser-based). Default authentication mode.

.PARAMETER ComplianceOnly
    Connect only to Security & Compliance PowerShell (skip Exchange Online).

.PARAMETER ExchangeOnly
    Connect only to Exchange Online PowerShell (skip Security & Compliance).

.EXAMPLE
    Connect-AuditServices -Interactive
    Connects to both Exchange Online and Security & Compliance using interactive auth.

.EXAMPLE
    Connect-AuditServices -TenantId "contoso.onmicrosoft.com" -ClientId "12345..." -CertificateThumbprint "ABCDEF..."
    Connects using service principal authentication with certificate thumbprint.

.EXAMPLE
    Connect-AuditServices -ExchangeOnly -Interactive
    Connects only to Exchange Online for Unified Audit Log checks.

.NOTES
    Version: 1.0.0
    Requires ExchangeOnlineManagement module v3.7.0 or later.

    IMPORTANT: Get-AdminAuditLogConfig must be called via Exchange Online PowerShell,
    NOT Security & Compliance PowerShell. The UnifiedAuditLogIngestionEnabled property
    always returns False when queried via Security & Compliance.
#>

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $true, ParameterSetName = 'ServicePrincipalThumbprint')]
    [Parameter(Mandatory = $true, ParameterSetName = 'ServicePrincipalFile')]
    [string]$ClientId,

    [Parameter(Mandatory = $true, ParameterSetName = 'ServicePrincipalThumbprint')]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $true, ParameterSetName = 'ServicePrincipalFile')]
    [string]$CertificateFilePath,

    [Parameter(Mandatory = $false, ParameterSetName = 'Interactive')]
    [switch]$Interactive,

    [Parameter(Mandatory = $false)]
    [switch]$ComplianceOnly,

    [Parameter(Mandatory = $false)]
    [switch]$ExchangeOnly
)

$ErrorActionPreference = "Stop"

function Connect-AuditServices {
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ServicePrincipalThumbprint')]
        [Parameter(Mandatory = $true, ParameterSetName = 'ServicePrincipalFile')]
        [string]$ClientId,

        [Parameter(Mandatory = $true, ParameterSetName = 'ServicePrincipalThumbprint')]
        [string]$CertificateThumbprint,

        [Parameter(Mandatory = $true, ParameterSetName = 'ServicePrincipalFile')]
        [string]$CertificateFilePath,

        [Parameter(Mandatory = $false, ParameterSetName = 'Interactive')]
        [switch]$Interactive,

        [Parameter(Mandatory = $false)]
        [switch]$ComplianceOnly,

        [Parameter(Mandatory = $false)]
        [switch]$ExchangeOnly
    )

    try {
        # Connect to Exchange Online (unless ComplianceOnly specified)
        if (-not $ComplianceOnly) {
            Write-Host "Connecting to Exchange Online PowerShell..." -ForegroundColor Cyan

            if ($PSCmdlet.ParameterSetName -eq 'ServicePrincipalThumbprint') {
                # Service principal auth with certificate thumbprint
                if (-not $TenantId) {
                    throw "TenantId is required for service principal authentication."
                }
                Connect-ExchangeOnline `
                    -AppId $ClientId `
                    -CertificateThumbprint $CertificateThumbprint `
                    -Organization $TenantId `
                    -ShowBanner:$false `
                    -ErrorAction Stop
            }
            elseif ($PSCmdlet.ParameterSetName -eq 'ServicePrincipalFile') {
                # Service principal auth with certificate file
                if (-not $TenantId) {
                    throw "TenantId is required for service principal authentication."
                }
                Connect-ExchangeOnline `
                    -AppId $ClientId `
                    -CertificateFilePath $CertificateFilePath `
                    -Organization $TenantId `
                    -ShowBanner:$false `
                    -ErrorAction Stop
            }
            else {
                # Interactive auth
                Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
            }

            Write-Host "Connected to Exchange Online PowerShell." -ForegroundColor Green
        }

        # Connect to Security & Compliance (unless ExchangeOnly specified)
        if (-not $ExchangeOnly) {
            Connect-ComplianceSession `
                -TenantId $TenantId `
                -ClientId $ClientId `
                -CertificateThumbprint $CertificateThumbprint `
                -CertificateFilePath $CertificateFilePath `
                -Interactive:$Interactive
        }
    }
    catch [System.Management.Automation.CommandNotFoundException] {
        throw "ExchangeOnlineManagement module not found. Install with: Install-Module ExchangeOnlineManagement -MinimumVersion 3.7.0"
    }
    catch {
        throw "Failed to connect to audit services: $($_.Exception.Message)"
    }
}

function Connect-ComplianceSession {
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param(
        [Parameter(Mandatory = $false)]
        [string]$TenantId,

        [Parameter(Mandatory = $false)]
        [string]$ClientId,

        [Parameter(Mandatory = $false)]
        [string]$CertificateThumbprint,

        [Parameter(Mandatory = $false)]
        [string]$CertificateFilePath,

        [Parameter(Mandatory = $false)]
        [switch]$Interactive
    )

    try {
        Write-Host "Connecting to Security & Compliance PowerShell..." -ForegroundColor Cyan

        if ($ClientId -and $CertificateThumbprint) {
            # Service principal auth with certificate thumbprint
            if (-not $TenantId) {
                throw "TenantId is required for service principal authentication."
            }
            Connect-IPPSSession `
                -AppId $ClientId `
                -CertificateThumbprint $CertificateThumbprint `
                -Organization $TenantId `
                -ShowBanner:$false `
                -ErrorAction Stop
        }
        elseif ($ClientId -and $CertificateFilePath) {
            # Service principal auth with certificate file
            if (-not $TenantId) {
                throw "TenantId is required for service principal authentication."
            }
            Connect-IPPSSession `
                -AppId $ClientId `
                -CertificateFilePath $CertificateFilePath `
                -Organization $TenantId `
                -ShowBanner:$false `
                -ErrorAction Stop
        }
        else {
            # Interactive auth
            Connect-IPPSSession -ShowBanner:$false -ErrorAction Stop
        }

        Write-Host "Connected to Security & Compliance PowerShell." -ForegroundColor Green
    }
    catch {
        throw "Failed to connect to Security & Compliance PowerShell: $($_.Exception.Message)"
    }
}

function Disconnect-AuditServices {
    <#
    .SYNOPSIS
        Disconnects from Exchange Online and Security & Compliance PowerShell sessions.

    .DESCRIPTION
        Cleanly disconnects all active Exchange Online and Security & Compliance
        PowerShell sessions. Errors are silently ignored to allow cleanup even
        if connections were not fully established.

    .EXAMPLE
        Disconnect-AuditServices
        Disconnects from all audit service sessions.

    .NOTES
        Safe to call even if connections were not established.
    #>

    try {
        Write-Host "Disconnecting from audit services..." -ForegroundColor Cyan

        # Disconnect Exchange Online
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue

        # Disconnect Security & Compliance
        # Note: Connect-IPPSSession uses the same Disconnect-ExchangeOnline cmdlet
        # But call it again for clarity and to handle edge cases
        Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue

        Write-Host "Disconnected from audit services." -ForegroundColor Green
    }
    catch {
        # Silently ignore errors during disconnect
        Write-Host "Warning: Error during disconnect (safely ignored): $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

# Execute function if script is run directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    Connect-AuditServices @PSBoundParameters
}

# Note: This script is dot-sourced; do not use Export-ModuleMember outside a .psm1 module.
