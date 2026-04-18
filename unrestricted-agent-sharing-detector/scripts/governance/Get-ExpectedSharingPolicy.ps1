<#
.SYNOPSIS
    Retrieves expected agent sharing policy and violation severity for a governance zone.

.DESCRIPTION
    Zone-to-policy reference for agent sharing restrictions. Returns the expected
    sharing policy for each governance zone, including permitted sharing scopes,
    violation severities by sharing type, and regulatory context.

    Zone policies (hardcoded for v1.0):
    - Zone1: Advisory only — Low severity for all sharing violations
    - Zone2: Public and external sharing prohibited — High severity; org-wide access medium
    - Zone3: ALL unrestricted sharing prohibited — Critical severity for any overly permissive config

.PARAMETER Zone
    The governance zone: Zone1, Zone2, Zone3, or Unknown.

.OUTPUTS
    PSCustomObject with permitted scopes, violation severities, and regulatory context.

.NOTES
    File: Get-ExpectedSharingPolicy.ps1
    Version: 2.0.0
    Solution: Unrestricted Agent Sharing Detector (UASD)
    Controls: 1.1, 3.8
    Regulations: FINRA Rule 4511(a), SEC Rule 17a-4, SOX Section 302/404, GLBA Section 501(b)

    Part of FSI Agent Governance Framework
#>

#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Zone1', 'Zone2', 'Zone3', 'Unknown')]
    [string]$Zone
)

$ErrorActionPreference = "Stop"

$zonePolicies = @{
    'Zone1' = [PSCustomObject]@{
        Zone                            = 'Zone1'
        # Sharing scopes that are permitted in this zone
        PermittedScopes                 = @('SpecificUsers', 'SpecificGroups', 'OrgWide', 'Public')
        # Advisory only — violations are logged but not enforcement-level
        AdvisoryOnly                    = $true
        # Severity by violation type
        UnrestrictedSharingSeverity     = 'Low'
        OrgWideAccessSeverity           = 'Low'
        ExternalSharingSeverity         = 'Low'
        SharingPolicyViolationSeverity  = 'Low'
        # Auto-remediation — Zone 1 does not auto-remediate by default
        AutoRemediateByDefault          = $false
        # Regulatory context
        RegulatoryContext               = 'Zone 1 (Personal Productivity) — Advisory monitoring only; no sharing restrictions enforced'
    }

    'Zone2' = [PSCustomObject]@{
        Zone                            = 'Zone2'
        # Only specific-user and specific-group sharing is permitted
        PermittedScopes                 = @('SpecificUsers', 'SpecificGroups')
        AdvisoryOnly                    = $false
        # Severity by violation type
        UnrestrictedSharingSeverity     = 'High'
        OrgWideAccessSeverity           = 'Medium'
        ExternalSharingSeverity         = 'High'
        SharingPolicyViolationSeverity  = 'High'
        # Auto-remediation recommended for High/Critical violations
        AutoRemediateByDefault          = $false
        # Regulatory context
        RegulatoryContext               = 'Zone 2 (Team/Collaborative) — Public and external sharing prohibited; org-wide access requires justification'
    }

    'Zone3' = [PSCustomObject]@{
        Zone                            = 'Zone3'
        # Only specific-user sharing permitted; groups require approval
        PermittedScopes                 = @('SpecificUsers')
        AdvisoryOnly                    = $false
        # All unrestricted sharing is Critical in Zone 3
        UnrestrictedSharingSeverity     = 'Critical'
        OrgWideAccessSeverity           = 'Critical'
        ExternalSharingSeverity         = 'Critical'
        SharingPolicyViolationSeverity  = 'Critical'
        # Auto-remediation strongly recommended in Zone 3
        AutoRemediateByDefault          = $true
        # Regulatory context
        RegulatoryContext               = 'Zone 3 (Enterprise/Regulated) — ALL unrestricted sharing prohibited; only specific-user sharing permitted per FINRA Rule 4511(a) and SEC Rule 17a-4'
    }

    'Unknown' = [PSCustomObject]@{
        Zone                            = 'Unknown'
        PermittedScopes                 = @('SpecificUsers', 'SpecificGroups')
        AdvisoryOnly                    = $true
        # Treat unclassified zones as warning-level
        UnrestrictedSharingSeverity     = 'Medium'
        OrgWideAccessSeverity           = 'Medium'
        ExternalSharingSeverity         = 'Medium'
        SharingPolicyViolationSeverity  = 'Medium'
        AutoRemediateByDefault          = $false
        RegulatoryContext               = 'Unclassified environment — Zone classification required before policy enforcement can begin'
    }
}

$policy = $zonePolicies[$Zone]

if (-not $policy) {
    throw "Zone policy not found for: $Zone"
}

return $policy
