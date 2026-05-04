<#
.SYNOPSIS
    Retrieves expected agent sharing policy for a governance zone.

.DESCRIPTION
    Zone-to-policy reference for agent sharing access restrictions. Returns the
    expected sharing policy for each governance zone, including whether group
    sharing, org-wide sharing, and public sharing are permitted, approved group
    requirements, violation severity mappings, and regulatory context.

    Zone policies enforce Controls 1.18 (Application-Level Authorization) and
    2.8 (Access Control and Segregation of Duties) from the FSI Agent Governance
    Framework.

    Zone policies (hardcoded for v1.0):
    - Zone1: No group sharing permitted — agents restricted to specific named users only
    - Zone2: Named groups only — sharing restricted to pre-approved security groups
    - Zone3: Approved groups only — sharing restricted to governance-approved groups; no org-wide/public
    - Unknown: Defaults to Zone 1 (most restrictive) per security-first principle

.PARAMETER Zone
    The governance zone: Zone1, Zone2, Zone3, or Unknown.
    Unknown defaults to Zone 1 (most restrictive).

.OUTPUTS
    PSCustomObject with properties:
    - Zone: Zone identifier
    - AllowGroupSharing: Whether any security group sharing is permitted
    - AllowOrgWideSharing: Whether org-wide (all tenant users) sharing is permitted
    - AllowPublicSharing: Whether public (anonymous link) sharing is permitted
    - RequireApprovedGroups: Whether shared groups must be on the approved list
    - ViolationSeverity: Hashtable mapping violation types to severity levels
    - RegulatoryContext: Regulatory references for this zone's restrictions

.EXAMPLE
    .\Get-ExpectedSharingPolicy.ps1 -Zone Zone2

    Returns the Zone 2 policy object (named groups only, no org-wide/public).

.EXAMPLE
    $policy = .\Get-ExpectedSharingPolicy.ps1 -Zone Zone3
    $policy.AllowGroupSharing   # True (approved groups only)
    $policy.RequireApprovedGroups  # True

    Retrieves Zone 3 policy and checks group sharing requirements.

.NOTES
    File: Get-ExpectedSharingPolicy.ps1
    Version: 2.0.1
    Solution: Agent Sharing Access Restriction Detector (ASARD)
    Controls: 1.18 (Application-Level Authorization), 2.8 (Access Control/Segregation of Duties)
    Regulations: FINRA Rule 4511, SOX Section 404, GLBA Section 501(b)

    Part of FSI Agent Governance Framework
#>

#Requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Zone1', 'Zone2', 'Zone3', 'Unknown')]
    [string]$Zone
)

$ErrorActionPreference = 'Stop'

$zonePolicies = @{
    'Zone1' = [PSCustomObject]@{
        Zone                  = 'Zone1'
        AllowGroupSharing     = $false
        AllowOrgWideSharing   = $false
        AllowPublicSharing    = $false
        RequireApprovedGroups = $false  # N/A — no group sharing allowed
        ViolationSeverity     = @{
            GroupSharing      = 'Critical'
            OrgWideSharing    = 'Critical'
            PublicSharing     = 'Critical'
            UnapprovedGroup   = 'Critical'
        }
        RegulatoryContext     = 'Zone 1 (Personal Productivity) — No group sharing permitted; agents restricted to specific named users per FINRA Rule 4511 and GLBA Section 501(b)'
    }

    'Zone2' = [PSCustomObject]@{
        Zone                  = 'Zone2'
        AllowGroupSharing     = $true
        AllowOrgWideSharing   = $false
        AllowPublicSharing    = $false
        RequireApprovedGroups = $true
        ViolationSeverity     = @{
            GroupSharing      = 'Informational'  # Permitted if approved
            OrgWideSharing    = 'High'
            PublicSharing     = 'Critical'
            UnapprovedGroup   = 'High'
        }
        RegulatoryContext     = 'Zone 2 (Team/Collaborative) — Named approved groups only; org-wide and public sharing prohibited per SOX Section 404 and GLBA Section 501(b)'
    }

    'Zone3' = [PSCustomObject]@{
        Zone                  = 'Zone3'
        AllowGroupSharing     = $true
        AllowOrgWideSharing   = $false
        AllowPublicSharing    = $false
        RequireApprovedGroups = $true
        ViolationSeverity     = @{
            GroupSharing      = 'Informational'  # Permitted if approved
            OrgWideSharing    = 'Critical'
            PublicSharing     = 'Critical'
            UnapprovedGroup   = 'High'
        }
        RegulatoryContext     = 'Zone 3 (Enterprise/Regulated) — Approved groups only; org-wide and public sharing prohibited per FINRA Rule 4511, SOX Section 404, and GLBA Section 501(b)'
    }

    'Unknown' = [PSCustomObject]@{
        Zone                  = 'Unknown'
        AllowGroupSharing     = $false
        AllowOrgWideSharing   = $false
        AllowPublicSharing    = $false
        RequireApprovedGroups = $false  # N/A — no group sharing allowed
        ViolationSeverity     = @{
            GroupSharing      = 'Critical'
            OrgWideSharing    = 'Critical'
            PublicSharing     = 'Critical'
            UnapprovedGroup   = 'Critical'
        }
        RegulatoryContext     = 'Unclassified environment — Defaults to Zone 1 (most restrictive) until zone classification is completed; no group sharing permitted'
    }
}

$policy = $zonePolicies[$Zone]

if (-not $policy) {
    throw "Zone policy not found for: $Zone"
}

return $policy
