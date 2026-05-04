<#
.SYNOPSIS
    Retrieves expected communication policy and severity classification for a zone.

.DESCRIPTION
    Zone-to-zone communication policy reference for the Agent Communication
    Restriction Detector (ACRD). Returns the expected communication policy for
    each governance zone, including per-route policies, violation severities,
    maker/checker requirements, and regulatory context.

    Zone policies:
    - Zone1: Same-zone same-env advisory, cross-zone higher-to-lower advisory,
      cross-zone lower-to-higher warning, cross-env advisory, cross-tenant blocked (High)
    - Zone2: Same-zone same-env route required, cross-zone higher-to-lower warning+approval,
      cross-zone lower-to-higher blocked unless approved, cross-env requires approval,
      cross-tenant blocked (Critical)
    - Zone3: Same-zone same-env route required, cross-zone higher-to-lower blocked unless
      approved, cross-zone lower-to-higher blocked, cross-env blocked unless explicit,
      cross-tenant blocked (Critical)

.PARAMETER Zone
    The governance zone: Zone1, Zone2, Zone3, or Unknown.

.OUTPUTS
    PSCustomObject with per-route policies, violation severities, maker/checker
    requirements, and regulatory context.

.EXAMPLE
    $policy = & ./Get-ExpectedCommPolicy.ps1 -Zone "Zone3"
    $policy.CrossTenantPolicy              # "Blocked"
    $policy.DefaultSeverity                # "Critical"

.EXAMPLE
    $policy = & ./Get-ExpectedCommPolicy.ps1 -Zone "Zone1"
    $policy.SameZoneSameEnvPolicy          # "Advisory"
    $policy.MakerCheckerRequired           # $false

.NOTES
    File: Get-ExpectedCommPolicy.ps1
    Version: 1.1.0
    Requires: Windows PowerShell 5.1+
    Control: 2.17 (Multi-Agent Orchestration Limits)
#>

#Requires -Version 5.1

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Zone1', 'Zone2', 'Zone3', 'Unknown')]
    [string]$Zone
)

# Zone policy definitions
$zonePolicies = @{
    'Zone1' = [PSCustomObject]@{
        Zone                          = 'Zone1'
        # Route policies
        SameZoneSameEnvPolicy         = 'Advisory'
        CrossZoneHigherToLowerPolicy  = 'Advisory'
        CrossZoneLowerToHigherPolicy  = 'Warning'
        CrossEnvironmentPolicy        = 'Advisory'
        CrossTenantPolicy             = 'Blocked'
        # Maker/checker requirement
        MakerCheckerRequired          = $false
        # Default severity for violations
        DefaultSeverity               = 'Warning'
        # Violation severities per route type
        SameZoneViolationSeverity     = 'Warning'
        CrossZoneViolationSeverity    = 'Warning'
        CrossEnvViolationSeverity     = 'Warning'
        CrossTenantViolationSeverity  = 'High'
        MakerCheckerViolationSeverity = 'Warning'
        # Regulatory context
        RegulatoryContext             = 'Zone 1 (Personal Productivity) - Advisory monitoring, minimal restrictions on agent-to-agent communication'
    }

    'Zone2' = [PSCustomObject]@{
        Zone                          = 'Zone2'
        # Route policies
        SameZoneSameEnvPolicy         = 'RouteRequired'
        CrossZoneHigherToLowerPolicy  = 'WarningWithApproval'
        CrossZoneLowerToHigherPolicy  = 'BlockedUnlessApproved'
        CrossEnvironmentPolicy        = 'RequiresApproval'
        CrossTenantPolicy             = 'Blocked'
        # Maker/checker requirement
        MakerCheckerRequired          = $true
        # Default severity for violations
        DefaultSeverity               = 'High'
        # Violation severities per route type
        SameZoneViolationSeverity     = 'Medium'
        CrossZoneViolationSeverity    = 'High'
        CrossEnvViolationSeverity     = 'High'
        CrossTenantViolationSeverity  = 'Critical'
        MakerCheckerViolationSeverity = 'High'
        # Regulatory context
        RegulatoryContext             = 'Zone 2 (Team/Collaborative) - Approved routes required, cross-zone communication needs approval'
    }

    'Zone3' = [PSCustomObject]@{
        Zone                          = 'Zone3'
        # Route policies
        SameZoneSameEnvPolicy         = 'RouteRequired'
        CrossZoneHigherToLowerPolicy  = 'BlockedUnlessApproved'
        CrossZoneLowerToHigherPolicy  = 'Blocked'
        CrossEnvironmentPolicy        = 'BlockedUnlessExplicit'
        CrossTenantPolicy             = 'Blocked'
        # Maker/checker requirement
        MakerCheckerRequired          = $true
        # Default severity for violations
        DefaultSeverity               = 'Critical'
        # Violation severities per route type
        SameZoneViolationSeverity     = 'High'
        CrossZoneViolationSeverity    = 'Critical'
        CrossEnvViolationSeverity     = 'Critical'
        CrossTenantViolationSeverity  = 'Critical'
        MakerCheckerViolationSeverity = 'Critical'
        # Regulatory context
        RegulatoryContext             = 'Zone 3 (Enterprise/Regulated) - Explicit route approval required, cross-zone communication blocked unless exception granted'
    }

    'Unknown' = [PSCustomObject]@{
        Zone                          = 'Unknown'
        # Route policies -- treat as restrictive until classified
        SameZoneSameEnvPolicy         = 'RequiresClassification'
        CrossZoneHigherToLowerPolicy  = 'RequiresClassification'
        CrossZoneLowerToHigherPolicy  = 'RequiresClassification'
        CrossEnvironmentPolicy        = 'RequiresClassification'
        CrossTenantPolicy             = 'Blocked'
        # Maker/checker requirement
        MakerCheckerRequired          = $false
        # Default severity for violations
        DefaultSeverity               = 'Warning'
        # Violation severities per route type
        SameZoneViolationSeverity     = 'Warning'
        CrossZoneViolationSeverity    = 'Warning'
        CrossEnvViolationSeverity     = 'Warning'
        CrossTenantViolationSeverity  = 'Warning'
        MakerCheckerViolationSeverity = 'Warning'
        # Regulatory context
        RegulatoryContext             = 'Unclassified environment - Zone classification required before communication policy enforcement'
    }
}

# Return the policy for the requested zone
$policy = $zonePolicies[$Zone]

if (-not $policy) {
    throw "Zone policy not found for: $Zone"
}

return $policy
