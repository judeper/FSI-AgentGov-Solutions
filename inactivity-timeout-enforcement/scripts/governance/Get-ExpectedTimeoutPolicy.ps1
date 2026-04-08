#Requires -Version 7.0

<#
.SYNOPSIS
    Returns zone-specific inactivity timeout policy for governance compliance evaluation.

.DESCRIPTION
    Provides the expected inactivity timeout policy for a given governance zone.
    Each zone defines whether a timeout is required, the maximum permitted
    duration in minutes, the violation severity, and applicable regulatory context.

    Zone rules:
    - Zone 1 (Personal): Timeout optional; if enabled, must not exceed 120 minutes
    - Zone 2 (Team): Timeout required; must not exceed 120 minutes
    - Zone 3 (Enterprise): Timeout required; must not exceed 60 minutes
    - Unknown: Treated as Zone 3 (most restrictive) per defense-in-depth principle

    This script supports Control 2.22 (Inactivity Timeout) and Control 1.23
    (Session Security) of the FSI Agent Governance Framework.

.PARAMETER Zone
    Governance zone identifier. Must be one of: Zone1, Zone2, Zone3, Unknown.
    Unknown zones default to Zone 3 policy (most restrictive).

.OUTPUTS
    PSCustomObject with properties:
    - Zone (string): The zone identifier
    - TimeoutRequired (bool): Whether inactivity timeout must be enabled
    - MaxDurationMinutes (int): Maximum permitted timeout duration
    - ViolationSeverity (string): Severity when policy is violated (Critical/High/Warning)
    - RegulatoryContext (string[]): Applicable regulatory references

.EXAMPLE
    .\Get-ExpectedTimeoutPolicy.ps1 -Zone Zone3

    Returns Zone 3 policy: timeout required, max 60 minutes, Critical severity.

.EXAMPLE
    .\Get-ExpectedTimeoutPolicy.ps1 -Zone Unknown

    Returns most restrictive policy (Zone 3 equivalent) for unclassified environments.

.EXAMPLE
    $policy = .\Get-ExpectedTimeoutPolicy.ps1 -Zone Zone2
    if ($policy.TimeoutRequired) {
        Write-Host "Timeout must be enabled with max $($policy.MaxDurationMinutes) minutes"
    }

    Uses the returned policy object to drive compliance evaluation logic.

.NOTES
    Version: 1.0.4
    Solution: Inactivity Timeout Enforcement (ITE)
    Controls: 2.22 (Inactivity Timeout), 1.23 (Session Security), 3.7/3.8 (Monitoring)
    Regulations: GLBA 501(b), SOX 302, FINRA 4511, NIST 800-53 AC-11/AC-12
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('Zone1', 'Zone2', 'Zone3', 'Unknown')]
    [string]$Zone
)

$ErrorActionPreference = 'Stop'

$policies = @{
    Zone1 = [PSCustomObject]@{
        Zone                = 'Zone1'
        TimeoutRequired     = $false
        MaxDurationMinutes  = 120
        ViolationSeverity   = 'Warning'
        RegulatoryContext   = @(
            'NIST 800-53 AC-11 (Session Lock)'
            'NIST 800-53 AC-12 (Session Termination)'
        )
    }
    Zone2 = [PSCustomObject]@{
        Zone                = 'Zone2'
        TimeoutRequired     = $true
        MaxDurationMinutes  = 120
        ViolationSeverity   = 'High'
        RegulatoryContext   = @(
            'GLBA Section 501(b) (Safeguards Rule)'
            'NIST 800-53 AC-11 (Session Lock)'
            'NIST 800-53 AC-12 (Session Termination)'
            'FINRA Rule 4511 (Books and Records)'
        )
    }
    Zone3 = [PSCustomObject]@{
        Zone                = 'Zone3'
        TimeoutRequired     = $true
        MaxDurationMinutes  = 60
        ViolationSeverity   = 'Critical'
        RegulatoryContext   = @(
            'GLBA Section 501(b) (Safeguards Rule)'
            'SOX Section 302 (Corporate Responsibility)'
            'SOX Section 404 (Internal Controls)'
            'FINRA Rule 4511 (Books and Records)'
            'NIST 800-53 AC-11 (Session Lock)'
            'NIST 800-53 AC-12 (Session Termination)'
        )
    }
    Unknown = [PSCustomObject]@{
        Zone                = 'Unknown'
        TimeoutRequired     = $true
        MaxDurationMinutes  = 60
        ViolationSeverity   = 'Critical'
        RegulatoryContext   = @(
            'GLBA Section 501(b) (Safeguards Rule)'
            'SOX Section 302 (Corporate Responsibility)'
            'SOX Section 404 (Internal Controls)'
            'FINRA Rule 4511 (Books and Records)'
            'NIST 800-53 AC-11 (Session Lock)'
            'NIST 800-53 AC-12 (Session Termination)'
        )
    }
}

$policy = $policies[$Zone]

Write-Verbose "Zone policy loaded: $Zone — Required=$($policy.TimeoutRequired), MaxMinutes=$($policy.MaxDurationMinutes), Severity=$($policy.ViolationSeverity)"

return $policy
