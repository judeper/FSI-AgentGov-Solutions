#Requires -Version 7.0

<#
.SYNOPSIS
    Retrieves expected credential governance policy for a governance zone.

.DESCRIPTION
    Zone-to-policy reference for credential oversharing restrictions. Loads
    zone-credential-policy.json and returns the policy object for the requested
    governance zone, including OAuth scope limits, service principal requirements,
    credential sharing rules, and violation severity mappings.

    Zone policies:
    - Zone1 (Personal/Developer): Relaxed — up to 20 OAuth scopes, shared
      credentials permitted, cross-environment allowed, 180-day credential age
    - Zone2 (Team/Collaborative): Moderate — up to 10 OAuth scopes, no shared
      credentials, no cross-environment, 90-day credential age
    - Zone3 (Enterprise/Production): Strict — up to 5 OAuth scopes, service
      principal required, no sharing, 30-day credential age, auto-remediation
    - Unknown: Treated as restricted until classified

.PARAMETER Zone
    The governance zone: Zone1, Zone2, Zone3, or Unknown.

.PARAMETER PolicyPath
    Path to zone-credential-policy.json. Defaults to
    ../templates/zone-credential-policy.json relative to script location.

.OUTPUTS
    PSCustomObject with properties:
    - Zone: Zone identifier
    - DisplayName: Human-readable zone name
    - MaxOAuthScopes: Maximum permitted OAuth scopes
    - RequireServicePrincipal: Whether service principal is required
    - AllowCrossEnvironment: Whether cross-environment credentials are allowed
    - AllowSharedCredentials: Whether shared credentials are permitted
    - MaxCredentialAgeDays: Maximum credential age before stale violation
    - RequireCredentialRotation: Whether rotation is enforced
    - AutoRemediate: Whether auto-remediation is enabled
    - ViolationSeverities: Hashtable mapping violation type to severity
    - RegulatoryContext: Hashtable mapping severity to regulatory guidance

.EXAMPLE
    .\Get-ExpectedCredentialPolicy.ps1 -Zone "Zone3"

    Returns the Zone 3 credential policy with Critical severity for most
    violation types and auto-remediation enabled.

.EXAMPLE
    $policy = .\Get-ExpectedCredentialPolicy.ps1 -Zone "Zone2"
    if ($actualScopes -gt $policy.MaxOAuthScopes) {
        Write-Warning "Excessive OAuth scopes detected"
    }

    Uses the returned policy to evaluate OAuth scope compliance.

.NOTES
    Version: 1.0.1
    Solution: Credential Oversharing Detector (COD)
    Controls: 1.14, 1.4, 1.18
    Regulations: FINRA Rule 4511, SEC 17a-4, SOX 302/404, GLBA 501(b), OCC 2011-12

    Part of FSI Agent Governance Framework
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet('Zone1', 'Zone2', 'Zone3', 'Unknown')]
    [string]$Zone,

    [Parameter()]
    [string]$PolicyPath
)

$ErrorActionPreference = "Stop"

#region Resolve Policy File

if (-not $PolicyPath) {
    $PolicyPath = Join-Path (Split-Path (Split-Path $PSScriptRoot -Parent) -Parent) "templates" "zone-credential-policy.json"
}

#endregion

#region Load Policy

if (Test-Path $PolicyPath) {
    # Load from JSON file
    try {
        $policyFile = Get-Content -Path $PolicyPath -Raw | ConvertFrom-Json
        $zoneData = $policyFile.zones.$Zone

        if (-not $zoneData) {
            throw "Zone '$Zone' not found in policy file: $PolicyPath"
        }

        # Convert to PSCustomObject with consistent property names
        $policy = [PSCustomObject]@{
            Zone                       = $Zone
            DisplayName                = $zoneData.displayName
            MaxOAuthScopes             = $zoneData.maxOAuthScopes
            RequireServicePrincipal    = $zoneData.requireServicePrincipal
            AllowCrossEnvironment      = $zoneData.allowCrossEnvironment
            AllowSharedCredentials     = $zoneData.allowSharedCredentials
            MaxCredentialAgeDays       = $zoneData.maxCredentialAgeDays
            RequireCredentialRotation  = $zoneData.requireCredentialRotation
            AutoRemediate              = $zoneData.autoRemediate
            ViolationSeverities        = $zoneData.violationSeverities
            RegulatoryContext          = $zoneData.regulatoryContext
        }

        return $policy
    }
    catch {
        Write-Warning "Failed to load policy file '$PolicyPath': $($_.Exception.Message). Using built-in defaults."
    }
}

#endregion

#region Built-in Defaults (fallback)

$defaultPolicies = @{
    'Zone1' = [PSCustomObject]@{
        Zone                       = 'Zone1'
        DisplayName                = 'Zone 1 — Personal / Developer'
        MaxOAuthScopes             = 20
        RequireServicePrincipal    = $false
        AllowCrossEnvironment      = $true
        AllowSharedCredentials     = $true
        MaxCredentialAgeDays       = 180
        RequireCredentialRotation  = $false
        AutoRemediate              = $false
        ViolationSeverities        = @{
            OverprivilegedConnector    = 'Low'
            ExcessiveOAuthScope        = 'Low'
            UnauthorizedServiceAccount = 'Medium'
            CrossEnvironmentCredential = 'Informational'
            SharedCredentialMisuse     = 'Low'
            StaleCredentialAccess      = 'Informational'
        }
        RegulatoryContext          = @{
            Low           = 'Informational finding in developer environment. Document for governance awareness.'
            Medium        = 'Review recommended per GLBA 501(b) access management guidelines.'
            Informational = 'No action required. Logged for audit trail.'
        }
    }

    'Zone2' = [PSCustomObject]@{
        Zone                       = 'Zone2'
        DisplayName                = 'Zone 2 — Team / Collaborative'
        MaxOAuthScopes             = 10
        RequireServicePrincipal    = $false
        AllowCrossEnvironment      = $false
        AllowSharedCredentials     = $false
        MaxCredentialAgeDays       = 90
        RequireCredentialRotation  = $true
        AutoRemediate              = $false
        ViolationSeverities        = @{
            OverprivilegedConnector    = 'High'
            ExcessiveOAuthScope        = 'Medium'
            UnauthorizedServiceAccount = 'High'
            CrossEnvironmentCredential = 'High'
            SharedCredentialMisuse     = 'Medium'
            StaleCredentialAccess      = 'Medium'
        }
        RegulatoryContext          = @{
            High   = 'Required review per SOX Section 404 access control requirements and GLBA 501(b).'
            Medium = 'Review recommended per OCC 2011-12 operational risk management guidelines.'
            Low    = 'Document finding for periodic governance review.'
        }
    }

    'Zone3' = [PSCustomObject]@{
        Zone                       = 'Zone3'
        DisplayName                = 'Zone 3 — Enterprise / Production'
        MaxOAuthScopes             = 5
        RequireServicePrincipal    = $true
        AllowCrossEnvironment      = $false
        AllowSharedCredentials     = $false
        MaxCredentialAgeDays       = 30
        RequireCredentialRotation  = $true
        AutoRemediate              = $true
        ViolationSeverities        = @{
            OverprivilegedConnector    = 'Critical'
            ExcessiveOAuthScope        = 'High'
            UnauthorizedServiceAccount = 'Critical'
            CrossEnvironmentCredential = 'Critical'
            SharedCredentialMisuse     = 'Critical'
            StaleCredentialAccess      = 'High'
        }
        RegulatoryContext          = @{
            Critical = 'Immediate remediation required. Supports compliance with GLBA 501(b) safeguards rule, SEC Reg S-P, and FINRA Rule 3110 supervisory controls. Escalate to CISO. (SEC 17a-4 governs evidence retention of any resulting records.)'
            High     = 'Required review within 24 hours per SOX Section 302/404 and OCC 2011-12 model risk management.'
            Medium   = 'Review within 1 business week per GLBA 501(b) safeguards rule.'
        }
    }

    'Unknown' = [PSCustomObject]@{
        Zone                       = 'Unknown'
        DisplayName                = 'Unknown Zone'
        MaxOAuthScopes             = 5
        RequireServicePrincipal    = $true
        AllowCrossEnvironment      = $false
        AllowSharedCredentials     = $false
        MaxCredentialAgeDays       = 30
        RequireCredentialRotation  = $true
        AutoRemediate              = $false
        ViolationSeverities        = @{
            OverprivilegedConnector    = 'High'
            ExcessiveOAuthScope        = 'High'
            UnauthorizedServiceAccount = 'High'
            CrossEnvironmentCredential = 'High'
            SharedCredentialMisuse     = 'High'
            StaleCredentialAccess      = 'High'
        }
        RegulatoryContext          = @{
            High = 'Environment zone classification missing. Treat as restricted until classified. Review per governance policy.'
        }
    }
}

$policy = $defaultPolicies[$Zone]

if (-not $policy) {
    throw "Zone policy not found for: $Zone"
}

return $policy

#endregion
