<#
.SYNOPSIS
    Retrieves expected HITL checkpoint policy and severity for a zone.

.DESCRIPTION
    Zone-to-policy reference for HITL (Human in the Loop) checkpoint requirements.
    Returns the expected HITL policy for each governance zone, including boolean HITL/reviewer
    requirements, violation severities, and regulatory context.

    This standalone script mirrors the inline Get-ExpectedHitlPolicy function in
    Test-HitlWorkflowCompliance.ps1. It can be dot-sourced by other scripts that need
    zone-based HITL policy lookups without importing the full compliance scanner.

    Zone policies (hardcoded for v1.0):
    - Zone1: Advisory only — HITL recommended but not required
    - Zone2: HITL required for financial, external sharing, and PII processing actions
    - Zone3: ALL agent flows with write/financial/external actions MUST have HITL checkpoints

.PARAMETER Zone
    The governance zone: Zone1, Zone2, Zone3, or Unknown.

.OUTPUTS
    PSCustomObject with RequiresHitl (boolean), RequiresReviewer (boolean), MinimumInputs,
    AdvisoryOnly, severity levels, and regulatory context.

.EXAMPLE
    $policy = & .\Get-ExpectedHitlPolicy.ps1 -Zone Zone3
    # $policy.RequiresHitl → $true

.EXAMPLE
    . .\private\Get-ExpectedHitlPolicy.ps1
    $policy = Get-ExpectedHitlPolicy -Zone Zone2

.NOTES
    File: Get-ExpectedHitlPolicy.ps1
    Version: 1.1.0
    Requires: PowerShell 7.0+
    Data contract: Matches inline version in Test-HitlWorkflowCompliance.ps1
#>

#requires -Version 7.0

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Zone1', 'Zone2', 'Zone3', 'Unknown')]
    [string]$Zone
)

switch ($Zone) {
    'Zone3' {
        return [PSCustomObject]@{
            Zone                    = 'Zone3'
            RequiresHitl            = $true
            RequiresReviewer        = $true
            MinimumInputs           = 1
            AdvisoryOnly            = $false
            MissingSeverity         = 'Critical'
            ReviewerMissingSeverity = 'Critical'
            InputSeverity           = 'High'
            RegulatoryContext       = 'Zone 3 (Enterprise/Regulated) - HITL checkpoints required for all write/financial/external actions per FINRA Rule 3110 supervisory requirements'
        }
    }
    'Zone2' {
        return [PSCustomObject]@{
            Zone                    = 'Zone2'
            RequiresHitl            = $true
            RequiresReviewer        = $true
            MinimumInputs           = 0
            AdvisoryOnly            = $false
            MissingSeverity         = 'High'
            ReviewerMissingSeverity = 'High'
            InputSeverity           = 'Medium'
            RegulatoryContext       = 'Zone 2 (Team/Collaborative) - HITL checkpoints required for financial/external/PII actions per GLBA Section 501(b) safeguards'
        }
    }
    'Zone1' {
        return [PSCustomObject]@{
            Zone                    = 'Zone1'
            RequiresHitl            = $false
            RequiresReviewer        = $false
            MinimumInputs           = 0
            AdvisoryOnly            = $true
            MissingSeverity         = 'Warning'
            ReviewerMissingSeverity = 'Warning'
            InputSeverity           = 'Warning'
            RegulatoryContext       = 'Zone 1 (Personal Productivity) - HITL checkpoints recommended, advisory monitoring only'
        }
    }
    default {
        return [PSCustomObject]@{
            Zone                    = 'Unknown'
            RequiresHitl            = $false
            RequiresReviewer        = $false
            MinimumInputs           = 0
            AdvisoryOnly            = $true
            MissingSeverity         = 'Warning'
            ReviewerMissingSeverity = 'Warning'
            InputSeverity           = 'Warning'
            RegulatoryContext       = 'Unclassified environment - Zone classification required before policy enforcement'
        }
    }
}
