<#
.SYNOPSIS
    Shared helper: connects to Exchange Online if not already connected.
.DESCRIPTION
    Dot-sourced by Export-CopilotDenyEvents.ps1 and Export-DlpCopilotEvents.ps1
    to avoid duplicate function definitions when the orchestrator runs both
    scripts in-process.
#>

function Connect-ToExchangeOnline {
    <#
    .SYNOPSIS
        Connects to Exchange Online if not already connected.
    #>
    # Check for an active EXO session (not just module presence)
    $exoSession = Get-ConnectionInformation -ErrorAction SilentlyContinue |
        Where-Object { $_.State -eq 'Connected' }
    if (-not $exoSession) {
        Write-Verbose "Connecting to Exchange Online..."
        try {
            Connect-ExchangeOnline -ShowBanner:$false -ErrorAction Stop
            Write-Verbose "Connected to Exchange Online."
        }
        catch {
            throw "Failed to connect to Exchange Online: $_"
        }
    }
    else {
        Write-Verbose "Already connected to Exchange Online."
    }
}
