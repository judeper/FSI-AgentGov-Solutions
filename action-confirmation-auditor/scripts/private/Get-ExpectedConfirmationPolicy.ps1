<#
.SYNOPSIS
    Retrieves expected action confirmation policy and severity for a zone.

.DESCRIPTION
    Zone-to-policy reference for action confirmation requirements. Returns the
    expected confirmation policy for each governance zone, including per-action-type
    rules, violation severities, and regulatory context.

    Zone policies (hardcoded for v1.0):
    - Zone1: Advisory only — Low severity for all missing confirmations
    - Zone2: Write, delete, external transfer require confirmation — High (write/delete), Medium (external)
    - Zone3: ALL actions require confirmation — Critical (write/delete), High (read)

    v1.1 roadmap: Import risk classification rules from CSV via Import-ActionRiskClassifications.ps1

.PARAMETER Zone
    The governance zone: Zone1, Zone2, Zone3, or Unknown.

.EXAMPLE
    $policy = .\Get-ExpectedConfirmationPolicy.ps1 -Zone "Zone3"
    Returns the confirmation policy for Zone 3 (all actions require confirmation).

.OUTPUTS
    PSCustomObject with per-action-type policies, violation severities, and regulatory context.

.NOTES
    File: Get-ExpectedConfirmationPolicy.ps1
    Version: 1.1.0
    Requires: PowerShell 7.0+
#>

#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Zone1', 'Zone2', 'Zone3', 'Unknown')]
    [string]$Zone
)

$zonePolicies = @{
    'Zone1' = [PSCustomObject]@{
        Zone                              = 'Zone1'
        # Action types requiring confirmation
        RequiresConfirmation              = @()  # Advisory only — none required
        AdvisoryOnly                      = $true
        # Severity for missing confirmation by action category
        WriteDeleteSeverity               = 'Low'
        ReadSeverity                      = 'Low'
        ExternalTransferSeverity          = 'Low'
        DefaultSeverity                   = 'Low'
        # Regulatory context
        RegulatoryContext                 = 'Zone 1 (Personal Productivity) - Advisory monitoring, no confirmation requirements enforced'
    }

    'Zone2' = [PSCustomObject]@{
        Zone                              = 'Zone2'
        # Action types requiring confirmation
        RequiresConfirmation              = @('Write', 'Delete', 'ExternalTransfer')
        AdvisoryOnly                      = $false
        # Severity for missing confirmation by action category
        WriteDeleteSeverity               = 'High'
        ReadSeverity                      = 'Low'
        ExternalTransferSeverity          = 'Medium'
        DefaultSeverity                   = 'Low'
        # Regulatory context
        RegulatoryContext                 = 'Zone 2 (Team/Collaborative) - Write, delete, and external transfer actions require user confirmation'
    }

    'Zone3' = [PSCustomObject]@{
        Zone                              = 'Zone3'
        # Action types requiring confirmation
        RequiresConfirmation              = @('Write', 'Delete', 'Read', 'ExternalTransfer', 'Execute')
        AdvisoryOnly                      = $false
        # Severity for missing confirmation by action category
        WriteDeleteSeverity               = 'Critical'
        ReadSeverity                      = 'High'
        ExternalTransferSeverity          = 'Critical'
        DefaultSeverity                   = 'High'
        # Regulatory context
        RegulatoryContext                 = 'Zone 3 (Enterprise/Regulated) - ALL actions require user confirmation before execution'
    }

    'Unknown' = [PSCustomObject]@{
        Zone                              = 'Unknown'
        # Treat as advisory until classified
        RequiresConfirmation              = @()
        AdvisoryOnly                      = $true
        # Severity
        WriteDeleteSeverity               = 'Warning'
        ReadSeverity                      = 'Warning'
        ExternalTransferSeverity          = 'Warning'
        DefaultSeverity                   = 'Warning'
        # Regulatory context
        RegulatoryContext                 = 'Unclassified environment - Zone classification required before policy enforcement'
    }
}

$policy = $zonePolicies[$Zone]

if (-not $policy) {
    throw "Zone policy not found for: $Zone"
}

return $policy
