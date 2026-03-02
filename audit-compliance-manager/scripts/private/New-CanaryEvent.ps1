#Requires -Version 7.0

<#
.SYNOPSIS
    Generates a canary audit event for dual validation.

.DESCRIPTION
    Creates a retrievable audit event in the Unified Audit Log by modifying a mailbox
    CustomAttribute and then reverting it. This provides a known event to search for
    when validating audit log ingestion.

    The canary approach prevents false positives by confirming that audit events are
    not only enabled at the configuration level, but are actually being ingested and
    retrievable via Search-UnifiedAuditLog.

    Strategy: Updates CustomAttribute15 on the specified mailbox (default: current user)
    to "ACV-Canary-{CanaryId}", waits briefly, then reverts to the original value.
    The Set-Mailbox operation generates an auditable Exchange admin event.

.PARAMETER CanaryId
    Unique identifier for this canary event. Defaults to a new GUID. Used to
    search for the specific event in Search-UnifiedAuditLog.

.PARAMETER MailboxIdentity
    Identity of the mailbox to use for the canary event. Can be UPN, email address,
    or alias. Defaults to the currently connected user's mailbox.

.PARAMETER SkipRevert
    Do not revert CustomAttribute15 to its original value. Use with caution as this
    will leave the canary marker in the mailbox.

.EXAMPLE
    $canary = New-CanaryEvent
    Generates a canary event on the current user's mailbox with a random GUID.

.EXAMPLE
    $canary = New-CanaryEvent -CanaryId "test-2024-01-15" -MailboxIdentity "admin@contoso.com"
    Generates a canary event with a specific ID on a specified mailbox.

.OUTPUTS
    PSCustomObject with properties:
    - CanaryId: The unique identifier for this canary
    - Timestamp: When the event was generated
    - Operation: The operation performed (Set-Mailbox)
    - Target: The mailbox identity
    - Status: Success or Failed
    - ErrorMessage: Error details if Status = Failed

.NOTES
    Version: 1.0.0
    Requires an active Exchange Online PowerShell connection.

    The canary event typically appears in Search-UnifiedAuditLog within 5-10 minutes,
    but may take up to 24 hours during audit ingestion delays. This is why the
    Test-UnifiedAuditLog script implements a grace period.

    CustomAttribute15 is used because:
    - It's available on all Exchange Online mailboxes
    - Modifying it generates an auditable admin action
    - It's rarely used by organizations, minimizing conflict risk
    - Changes are non-disruptive to mail flow or user experience
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$CanaryId = [Guid]::NewGuid().ToString(),

    [Parameter(Mandatory = $false)]
    [string]$MailboxIdentity,

    [Parameter(Mandatory = $false)]
    [switch]$SkipRevert
)

$ErrorActionPreference = "Stop"

function New-CanaryEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [string]$CanaryId = [Guid]::NewGuid().ToString(),

        [Parameter(Mandatory = $false)]
        [string]$MailboxIdentity,

        [Parameter(Mandatory = $false)]
        [switch]$SkipRevert
    )

    try {
        # Determine target mailbox
        if (-not $MailboxIdentity) {
            # Get current connected user's mailbox
            try {
                $currentUser = Get-ConnectionInformation | Select-Object -First 1
                if ($currentUser -and $currentUser.UserPrincipalName) {
                    $MailboxIdentity = $currentUser.UserPrincipalName
                }
                else {
                    throw "Could not determine current user. Specify -MailboxIdentity explicitly."
                }
            }
            catch {
                throw "Not connected to Exchange Online. Run Connect-AuditServices first."
            }
        }

        Write-Host "Generating canary event on mailbox: $MailboxIdentity" -ForegroundColor Cyan
        Write-Host "Canary ID: $CanaryId" -ForegroundColor Cyan

        # Get current CustomAttribute15 value to preserve it
        $mailbox = Get-Mailbox -Identity $MailboxIdentity -ErrorAction Stop
        $originalValue = $mailbox.CustomAttribute15

        # Set canary value
        $canaryValue = "ACV-Canary-$CanaryId"
        Set-Mailbox -Identity $MailboxIdentity -CustomAttribute15 $canaryValue -ErrorAction Stop

        Write-Host "Canary event generated successfully." -ForegroundColor Green
        Write-Host "CustomAttribute15 set to: $canaryValue" -ForegroundColor Gray

        # Wait briefly to ensure the operation completes
        Start-Sleep -Seconds 2

        # Revert to original value (unless SkipRevert is specified)
        if (-not $SkipRevert) {
            if ($originalValue) {
                Set-Mailbox -Identity $MailboxIdentity -CustomAttribute15 $originalValue -ErrorAction Stop
                Write-Host "CustomAttribute15 reverted to original value: $originalValue" -ForegroundColor Gray
            }
            else {
                # Clear the attribute if it was originally empty
                Set-Mailbox -Identity $MailboxIdentity -CustomAttribute15 $null -ErrorAction Stop
                Write-Host "CustomAttribute15 cleared (was originally empty)." -ForegroundColor Gray
            }
        }

        # Return canary details
        return [PSCustomObject]@{
            CanaryId   = $CanaryId
            Timestamp  = Get-Date -Format "o"
            Operation  = "Set-Mailbox"
            Target     = $MailboxIdentity
            Status     = "Success"
            ErrorMessage = $null
        }
    }
    catch {
        Write-Host "Failed to generate canary event: $($_.Exception.Message)" -ForegroundColor Red

        return [PSCustomObject]@{
            CanaryId   = $CanaryId
            Timestamp  = Get-Date -Format "o"
            Operation  = "Set-Mailbox"
            Target     = $MailboxIdentity
            Status     = "Failed"
            ErrorMessage = $_.Exception.Message
        }
    }
}

# Note: This script is dot-sourced; do not use Export-ModuleMember outside a .psm1 module.
