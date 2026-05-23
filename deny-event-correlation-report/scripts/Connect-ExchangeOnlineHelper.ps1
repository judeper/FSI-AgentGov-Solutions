<#
.SYNOPSIS
    Shared helper: connects to Exchange Online if not already connected.
.DESCRIPTION
    Dot-sourced by Export-CopilotDenyEvents.ps1 and Export-DlpCopilotEvents.ps1
    to avoid duplicate function definitions when the orchestrator runs both
    scripts in-process. Supports interactive auth (manual/dev) and certificate-
    based app-only auth (Azure Automation / unattended).

    Requires the ExchangeOnlineManagement module v3.0.0 or later.
#>

#Requires -Modules @{ ModuleName = 'ExchangeOnlineManagement'; ModuleVersion = '3.0.0' }

function Connect-ToExchangeOnline {
    <#
    .SYNOPSIS
        Connects to Exchange Online if not already connected.
    .PARAMETER AppId
        Entra application (client) ID for app-only authentication.
    .PARAMETER CertificateThumbprint
        Thumbprint of the certificate associated with the Entra app registration.
    .PARAMETER Organization
        Tenant primary domain (e.g. `example.onmicrosoft.com`) - required for
        certificate-based connections.
    .PARAMETER ManagedIdentity
        Use the Azure managed identity assigned to the runbook host. Requires
        the `Exchange.ManageAsApp` Office 365 Exchange Online API permission
        and an Exchange Administrator role assignment on the managed identity.
    #>
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param(
        [Parameter(ParameterSetName = 'Certificate', Mandatory)]
        [string]$AppId,

        [Parameter(ParameterSetName = 'Certificate', Mandatory)]
        [string]$CertificateThumbprint,

        [Parameter(ParameterSetName = 'Certificate', Mandatory)]
        [Parameter(ParameterSetName = 'ManagedIdentity', Mandatory)]
        [string]$Organization,

        [Parameter(ParameterSetName = 'ManagedIdentity', Mandatory)]
        [switch]$ManagedIdentity
    )

    # Check for an active EXO session (not just module presence)
    $exoSession = Get-ConnectionInformation -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq 'Connected' }
    if ($exoSession) {
        Write-Verbose "Already connected to Exchange Online."
        return
    }

    Write-Verbose "Connecting to Exchange Online (parameter set: $($PSCmdlet.ParameterSetName))..."
    try {
        switch ($PSCmdlet.ParameterSetName) {
            'Certificate' {
                Connect-ExchangeOnline -AppId $AppId `
                    -CertificateThumbprint $CertificateThumbprint `
                    -Organization $Organization `
                    -ShowBanner:$false -ErrorAction Stop
            }
            'ManagedIdentity' {
                Connect-ExchangeOnline -ManagedIdentity `
                    -Organization $Organization `
                    -ShowBanner:$false -ErrorAction Stop
            }
            default {
                Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
            }
        }
        Write-Verbose "Connected to Exchange Online."
    }
    catch {
        throw "Failed to connect to Exchange Online: $_"
    }
}
