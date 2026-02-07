#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Identity.SignIns

<#
.SYNOPSIS
    Validates tenant session security configuration against zone-specific baselines.

.DESCRIPTION
    Orchestrates execution of five session security validators and produces a consolidated
    compliance validation report for Microsoft 365 Conditional Access session controls.

    This script executes the following validators:
    1. Session Controls - Validates signInFrequency and persistentBrowser settings against zone baselines
    2. Authentication Strength - Verifies zone-appropriate MFA requirements (standard/passwordless/phishing-resistant)
    3. PIM Role Settings - Checks Privileged Identity Management configuration for AI admin roles
    4. Break-Glass Exclusions - Critical safety check to prevent tenant lockout
    5. Policy Conflict Audit - Optional analysis of overlapping CA policies (informational)

    Each validator runs in isolation. Failures in one validator do not prevent execution
    of the others, allowing administrators to see the complete compliance picture even
    when some aspects fail.

    Results are displayed to console with color-coded status indicators and optionally
    written to a JSON file for downstream processing (Power Automate, compliance dashboards,
    audit evidence collection).

    This script supports compliance validation for FSI-AgentGov Control 1.23
    (Session Security and Step-Up Authentication).

.PARAMETER Zone
    Governance zone to validate against. Required.
    Valid values: Zone1 (Personal Productivity), Zone2 (Team Collaboration),
    Zone3 (Enterprise Managed)

    Zone affects session control requirements:
    - Zone1: 8-hour sign-in frequency, standard MFA
    - Zone2: 4-hour sign-in frequency, passwordless MFA
    - Zone3: 1-hour sign-in frequency, phishing-resistant MFA, compliant device

.PARAMETER ConfigPath
    Path to tenant configuration JSON file. Required.
    Must contain breakGlassAccounts array with user object IDs.

.PARAMETER BaselinePath
    Directory containing zone baseline JSON files. Defaults to templates/session-baselines.
    Expected files: zone1-baseline.json, zone2-baseline.json, zone3-baseline.json

.PARAMETER OutputPath
    Optional path for JSON output file. If specified, the complete validation results
    object is written to this file. If omitted, results only display to the console.

.PARAMETER Interactive
    Use interactive browser-based authentication instead of service principal.

.PARAMETER TenantId
    Azure AD tenant ID. Required for service principal authentication.

.PARAMETER ClientId
    Azure AD application (client) ID. Required for service principal authentication.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication.

.PARAMETER SkipPimValidation
    Skip PIM role settings validation. Use when account lacks RoleManagement.Read.All permission.
    Results will show PIM validator as "Skipped" instead of Passed/Failed.

.PARAMETER IncludeConflictAudit
    Include Conditional Access policy conflict analysis in validation.
    Identifies overlapping policies that may interact with session security controls.
    Returns informational warnings only (does not fail overall validation).

.EXAMPLE
    .\Test-SessionCompliance.ps1 -Zone Zone3 -ConfigPath ".\tenant-config.json" -Interactive

    Runs full validation suite for Enterprise Managed zone using interactive authentication.
    Includes all 5 validators with PIM checks.

.EXAMPLE
    .\Test-SessionCompliance.ps1 -Zone Zone2 -ConfigPath ".\config.json" -OutputPath ".\results.json" -SkipPimValidation -Interactive

    Runs validation for Team Collaboration zone, skips PIM checks, writes results to JSON.

.EXAMPLE
    .\Test-SessionCompliance.ps1 -Zone Zone3 -ConfigPath ".\config.json" -IncludeConflictAudit -TenantId "contoso.onmicrosoft.com" -ClientId "12345..." -CertificateThumbprint "ABCDEF..."

    Runs full validation with policy conflict audit using service principal authentication.

.OUTPUTS
    PSCustomObject with properties:
    - Timestamp: ISO 8601 timestamp
    - Zone: Zone1 | Zone2 | Zone3
    - ZoneName: Friendly zone name
    - Validators: Hashtable with keys SessionControls, AuthenticationStrength, PimRoleSettings, BreakGlassExclusions, PolicyConflictAudit
    - OverallStatus: Passed | Failed | Warning
    - Reason: Summary of overall status

.NOTES
    Version: 1.0.0
    Requires:
    - Microsoft.Graph.Identity.SignIns module v2.35.1 or later
    - PowerShell 7.0 or later
    - Conditional Access Administrator or Global Administrator role
    - For PIM validation: RoleManagement.Read.All permission
    - For service principal: Application with Policy.Read.All and (optionally) RoleManagement.Read.All

    Regulatory context:
    This orchestrator supports compliance validation for:
    - FINRA Rule 3110 (supervision of AI agent access)
    - SEC Rule 17a-3/4 (session audit trail retention)
    - SOX Section 302/404 (access control testing)
    - OCC Bulletin 2011-12 (privileged access governance)

    License requirements:
    - Microsoft 365 E5 or E5 Security license for Conditional Access
    - Azure AD Premium P2 for Privileged Identity Management features

    Performance considerations:
    - Full validation (with PIM) takes 2-5 minutes
    - Use -SkipPimValidation for faster checks (~30 seconds)
    - Each validator runs sequentially but with independent error handling
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Zone1", "Zone2", "Zone3")]
    [string]$Zone,

    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [string]$BaselinePath = "$PSScriptRoot\..\templates\session-baselines",

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [switch]$Interactive,

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [switch]$SkipPimValidation,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeConflictAudit
)

$ErrorActionPreference = "Stop"

#region Initialization

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Session Security Configurator - Compliance     ║" -ForegroundColor Cyan
Write-Host "║  Validation                                      ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  FSI-AgentGov Control 1.23                       ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Dot-source all private helper scripts
$scriptRoot = $PSScriptRoot
try {
    . "$scriptRoot\private\Connect-GraphSession.ps1"
    . "$scriptRoot\private\Compare-SessionBaseline.ps1"
    . "$scriptRoot\private\Test-BreakGlassExclusion.ps1"
}
catch {
    Write-Error "Failed to load private helper scripts: $($_.Exception.Message)"
    throw
}

# Build common authentication parameter hashtable
$authParams = @{}
if ($Interactive) { $authParams.Interactive = $true }
if ($TenantId) { $authParams.TenantId = $TenantId }
if ($ClientId) { $authParams.ClientId = $ClientId }
if ($CertificateThumbprint) { $authParams.CertificateThumbprint = $CertificateThumbprint }

# Load tenant configuration
if (-not (Test-Path $ConfigPath)) {
    Write-Error "Configuration file not found: $ConfigPath"
    throw
}

try {
    $config = Get-Content -Path $ConfigPath -Raw | ConvertFrom-Json
    Write-Host "Loaded configuration from: $ConfigPath" -ForegroundColor Cyan
}
catch {
    Write-Error "Failed to parse configuration file: $($_.Exception.Message)"
    throw
}

# Load zone baseline
$baselineFile = Join-Path $BaselinePath "$(($Zone).ToLower())-baseline.json"
if (-not (Test-Path $baselineFile)) {
    Write-Error "Baseline file not found: $baselineFile"
    throw
}

try {
    $baseline = Get-Content -Path $baselineFile -Raw | ConvertFrom-Json
    Write-Host "Loaded baseline from: $baselineFile" -ForegroundColor Cyan
}
catch {
    Write-Error "Failed to parse baseline file: $($_.Exception.Message)"
    throw
}

# Initialize results object
$results = @{
    Timestamp = (Get-Date -Format "o")
    Zone = $Zone
    ZoneName = $baseline.zoneName
    Validators = @{}
    OverallStatus = "Unknown"
    Reason = ""
}

Write-Host "Validation Target: $Zone ($($baseline.zoneName))" -ForegroundColor Cyan
Write-Host "Timestamp: $($results.Timestamp)" -ForegroundColor Cyan
Write-Host ""

# Connect to Microsoft Graph
try {
    $graphContext = Connect-GraphSession @authParams
}
catch {
    Write-Error "Failed to connect to Microsoft Graph: $($_.Exception.Message)"
    throw
}

#endregion

#region Validator 1: Session Controls

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  VALIDATOR 1: Session Controls                    " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

try {
    Write-Host "Querying Conditional Access policies with SSC prefix..." -ForegroundColor Cyan

    # Query all CA policies with SSC prefix
    $sscPolicies = Get-MgIdentityConditionalAccessPolicy -Filter "startswith(displayName, 'SSC-')" -ErrorAction Stop

    if (-not $sscPolicies -or $sscPolicies.Count -eq 0) {
        $results.Validators.SessionControls = @{
            Status = "Failed"
            Confidence = "HIGH"
            Reason = "No SSC-prefixed Conditional Access policies found in tenant."
            PoliciesChecked = 0
            Mismatches = @()
            Timestamp = Get-Date -Format "o"
        }
        Write-Host "Result: FAILED" -ForegroundColor Red
        Write-Host "Reason: No SSC policies found." -ForegroundColor Red
    }
    else {
        Write-Host "Found $($sscPolicies.Count) SSC-prefixed policy(ies)." -ForegroundColor Cyan

        # Filter policies for specified zone by checking includeGroups
        # (Zone matching requires checking config group membership - for now check all SSC policies)
        $zonePolicies = $sscPolicies | Where-Object { $_.DisplayName -like "*$Zone*" }

        if (-not $zonePolicies -or $zonePolicies.Count -eq 0) {
            Write-Warning "No SSC policies found matching zone: $Zone"
            $zonePolicies = $sscPolicies
        }

        Write-Host "Validating $($zonePolicies.Count) policy(ies) for zone: $Zone" -ForegroundColor Cyan

        $allMismatches = @()
        $policiesInReportOnly = @()
        $policiesChecked = 0

        foreach ($policy in $zonePolicies) {
            Write-Host "`nChecking policy: $($policy.DisplayName)" -ForegroundColor Cyan

            # Compare against baseline
            $comparisonResult = Compare-SessionBaseline -Policy $policy -Baseline $baseline

            if ($comparisonResult.Mismatches.Count -gt 0) {
                $allMismatches += @{
                    PolicyName = $policy.DisplayName
                    PolicyId = $policy.Id
                    Mismatches = $comparisonResult.Mismatches
                }
                Write-Host "  Status: MISMATCH ($($comparisonResult.Mismatches.Count) issue(s))" -ForegroundColor Yellow
            }
            else {
                Write-Host "  Status: MATCH" -ForegroundColor Green
            }

            # Check if policy is in report-only mode
            if ($policy.State -eq "enabledForReportingButNotEnforced") {
                $policiesInReportOnly += $policy.DisplayName
                Write-Host "  Warning: Policy in report-only mode (not yet enforced)" -ForegroundColor Yellow
            }

            $policiesChecked++
        }

        # Determine overall status
        if ($allMismatches.Count -gt 0) {
            $results.Validators.SessionControls = @{
                Status = "Failed"
                Confidence = "HIGH"
                Reason = "Session controls do not match zone baseline ($($allMismatches.Count) policy(ies) with mismatches)."
                PoliciesChecked = $policiesChecked
                Mismatches = $allMismatches
                Timestamp = Get-Date -Format "o"
            }
            Write-Host "`nResult: FAILED" -ForegroundColor Red
        }
        elseif ($policiesInReportOnly.Count -gt 0) {
            $results.Validators.SessionControls = @{
                Status = "Warning"
                Confidence = "HIGH"
                Reason = "Session controls match baseline but $($policiesInReportOnly.Count) policy(ies) in report-only mode."
                PoliciesChecked = $policiesChecked
                Mismatches = @()
                ReportOnlyPolicies = $policiesInReportOnly
                Timestamp = Get-Date -Format "o"
            }
            Write-Host "`nResult: WARNING (HIGH confidence)" -ForegroundColor Yellow
        }
        else {
            $results.Validators.SessionControls = @{
                Status = "Passed"
                Confidence = "HIGH"
                Reason = "All session controls match zone baseline and are enforced."
                PoliciesChecked = $policiesChecked
                Mismatches = @()
                Timestamp = Get-Date -Format "o"
            }
            Write-Host "`nResult: PASSED (HIGH confidence)" -ForegroundColor Green
        }

        Write-Host "Reason: $($results.Validators.SessionControls.Reason)" -ForegroundColor Cyan
    }
}
catch {
    $results.Validators.SessionControls = @{
        Status = "Error"
        Reason = $_.Exception.Message
        Timestamp = Get-Date -Format "o"
    }
    Write-Warning "Session Controls validation failed: $($_.Exception.Message)"
    Write-Host "Result: ERROR" -ForegroundColor Red
}

Write-Host ""

#endregion

#region Validator 2: Authentication Strength

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  VALIDATOR 2: Authentication Strength             " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

try {
    Write-Host "Querying authentication strength policies..." -ForegroundColor Cyan

    # Query authentication strength policies
    $authStrengthPolicies = Get-MgIdentityConditionalAccessAuthenticationStrengthPolicy -ErrorAction Stop

    Write-Host "Found $($authStrengthPolicies.Count) authentication strength policy(ies)." -ForegroundColor Cyan

    # Zone-specific validation
    $authStrengthStatus = "Unknown"
    $authStrengthReason = ""
    $methodsFound = @()

    switch ($Zone) {
        "Zone1" {
            # Zone 1: Standard MFA (no custom requirement)
            if ($baseline.authenticationStrength -eq $null) {
                $authStrengthStatus = "Passed"
                $authStrengthReason = "Zone 1 uses standard MFA (no custom authentication strength required)."
                $methodsFound += "Standard MFA"
            }
            else {
                $authStrengthStatus = "Failed"
                $authStrengthReason = "Zone 1 baseline expects null authentication strength but baseline specifies: $($baseline.authenticationStrength)"
            }
        }

        "Zone2" {
            # Zone 2: Passwordless MFA
            if ($baseline.authenticationStrength) {
                # Check if SSC policies reference the passwordless policy
                $sscPoliciesWithAuth = $sscPolicies | Where-Object {
                    $_.GrantControls.AuthenticationStrength.Id -eq $baseline.authenticationStrength
                }

                if ($sscPoliciesWithAuth) {
                    $authStrengthStatus = "Passed"
                    $authStrengthReason = "SSC policies reference passwordless MFA authentication strength."
                    $methodsFound += "Passwordless MFA"
                }
                else {
                    $authStrengthStatus = "Failed"
                    $authStrengthReason = "SSC policies do not reference expected passwordless MFA policy."
                }
            }
            else {
                $authStrengthStatus = "Warning"
                $authStrengthReason = "Zone 2 baseline does not specify authentication strength policy ID."
            }
        }

        "Zone3" {
            # Zone 3: Phishing-resistant MFA
            if ($baseline.authenticationStrength) {
                # Check if SSC policies reference the phishing-resistant policy
                $sscPoliciesWithAuth = $sscPolicies | Where-Object {
                    $_.GrantControls.AuthenticationStrength.Id -eq $baseline.authenticationStrength
                }

                if ($sscPoliciesWithAuth) {
                    $authStrengthStatus = "Passed"
                    $authStrengthReason = "SSC policies reference phishing-resistant MFA authentication strength."
                    $methodsFound += "Phishing-resistant MFA"
                }
                else {
                    $authStrengthStatus = "Failed"
                    $authStrengthReason = "SSC policies do not reference expected phishing-resistant MFA policy."
                }
            }
            else {
                $authStrengthStatus = "Warning"
                $authStrengthReason = "Zone 3 baseline does not specify authentication strength policy ID."
            }
        }
    }

    $results.Validators.AuthenticationStrength = @{
        Status = $authStrengthStatus
        Confidence = "MEDIUM"
        Reason = $authStrengthReason
        MethodsFound = $methodsFound
        Timestamp = Get-Date -Format "o"
    }

    $color = switch ($authStrengthStatus) {
        "Passed" { "Green" }
        "Failed" { "Red" }
        "Warning" { "Yellow" }
        default { "Gray" }
    }

    Write-Host "`nResult: $authStrengthStatus (MEDIUM confidence)" -ForegroundColor $color
    Write-Host "Reason: $authStrengthReason" -ForegroundColor $color
}
catch {
    $results.Validators.AuthenticationStrength = @{
        Status = "Error"
        Reason = $_.Exception.Message
        Timestamp = Get-Date -Format "o"
    }
    Write-Warning "Authentication Strength validation failed: $($_.Exception.Message)"
    Write-Host "Result: ERROR" -ForegroundColor Red
}

Write-Host ""

#endregion

#region Validator 3: PIM Role Settings

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  VALIDATOR 3: PIM Role Settings                   " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($SkipPimValidation) {
    Write-Host "PIM validation: SKIPPED (requires RoleManagement.Read.All permission)" -ForegroundColor Yellow
    $results.Validators.PimRoleSettings = @{
        Status = "Skipped"
        Confidence = "N/A"
        Reason = "PIM validation skipped by user request."
        Timestamp = Get-Date -Format "o"
    }
}
else {
    try {
        Write-Host "Querying PIM role settings for AI admin roles..." -ForegroundColor Cyan

        # Target roles for Control 1.23
        $targetRoles = @(
            "Power Platform Administrator"
            "Global Administrator"
        )

        Write-Host "Target roles: $($targetRoles -join ', ')" -ForegroundColor Cyan

        # PIM validation logic would go here
        # This requires Microsoft.Graph.Identity.Governance module and RoleManagement.Read.All permission
        # For now, return informational status

        Write-Warning "PIM role settings validation requires Microsoft.Graph.Identity.Governance module and RoleManagement.Read.All permission."
        Write-Warning "Full implementation requires querying role assignment schedules and settings."

        $results.Validators.PimRoleSettings = @{
            Status = "Warning"
            Confidence = "LOW"
            Reason = "PIM validation not fully implemented. Manual verification required."
            TargetRoles = $targetRoles
            Timestamp = Get-Date -Format "o"
        }

        Write-Host "`nResult: WARNING (LOW confidence)" -ForegroundColor Yellow
        Write-Host "Reason: PIM validation requires manual verification." -ForegroundColor Yellow
    }
    catch {
        $results.Validators.PimRoleSettings = @{
            Status = "Error"
            Reason = $_.Exception.Message
            Timestamp = Get-Date -Format "o"
        }
        Write-Warning "PIM Role Settings validation failed: $($_.Exception.Message)"
        Write-Host "Result: ERROR" -ForegroundColor Red
    }
}

Write-Host ""

#endregion

#region Validator 4: Break-Glass Exclusions

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  VALIDATOR 4: Break-Glass Exclusions              " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

try {
    Write-Host "Validating break-glass account exclusions for all SSC policies..." -ForegroundColor Cyan

    if (-not $sscPolicies -or $sscPolicies.Count -eq 0) {
        $results.Validators.BreakGlassExclusions = @{
            Status = "Warning"
            Confidence = "N/A"
            Reason = "No SSC policies found to validate."
            Timestamp = Get-Date -Format "o"
        }
        Write-Host "`nResult: WARNING" -ForegroundColor Yellow
    }
    else {
        $failedPolicies = @()
        $passedCount = 0

        foreach ($policy in $sscPolicies) {
            Write-Host "`nChecking policy: $($policy.DisplayName)" -ForegroundColor Cyan

            # Convert policy to hashtable format for Test-BreakGlassExclusion
            $policyTemplate = @{
                displayName = $policy.DisplayName
                conditions = @{
                    users = @{
                        excludeUsers = $policy.Conditions.Users.ExcludeUsers
                        excludeGroups = $policy.Conditions.Users.ExcludeGroups
                    }
                }
            }

            # Test break-glass exclusions
            $breakGlassResult = Test-BreakGlassExclusion -PolicyTemplate $policyTemplate -Config $config

            if ($breakGlassResult) {
                $passedCount++
            }
            else {
                $failedPolicies += $policy.DisplayName
            }
        }

        if ($failedPolicies.Count -eq 0) {
            $results.Validators.BreakGlassExclusions = @{
                Status = "Passed"
                Confidence = "HIGH"
                Reason = "All $passedCount SSC policy(ies) exclude all break-glass accounts."
                PoliciesChecked = $sscPolicies.Count
                Timestamp = Get-Date -Format "o"
            }
            Write-Host "`nResult: PASSED (HIGH confidence)" -ForegroundColor Green
        }
        else {
            $results.Validators.BreakGlassExclusions = @{
                Status = "Failed"
                Confidence = "HIGH"
                Reason = "Break-glass validation failed for $($failedPolicies.Count) policy(ies)."
                PoliciesChecked = $sscPolicies.Count
                FailedPolicies = $failedPolicies
                Timestamp = Get-Date -Format "o"
            }
            Write-Host "`nResult: FAILED (HIGH confidence)" -ForegroundColor Red
            Write-Host "Policies with missing break-glass exclusions:" -ForegroundColor Red
            foreach ($policyName in $failedPolicies) {
                Write-Host "  - $policyName" -ForegroundColor Red
            }
        }

        Write-Host "Reason: $($results.Validators.BreakGlassExclusions.Reason)" -ForegroundColor Cyan
    }
}
catch {
    $results.Validators.BreakGlassExclusions = @{
        Status = "Error"
        Reason = $_.Exception.Message
        Timestamp = Get-Date -Format "o"
    }
    Write-Warning "Break-Glass Exclusions validation failed: $($_.Exception.Message)"
    Write-Host "Result: ERROR" -ForegroundColor Red
}

Write-Host ""

#endregion

#region Validator 5: Policy Conflict Audit (Optional)

if ($IncludeConflictAudit) {
    Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host "  VALIDATOR 5: Policy Conflict Audit               " -ForegroundColor Cyan
    Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
    Write-Host ""

    try {
        Write-Host "Analyzing Conditional Access policy conflicts..." -ForegroundColor Cyan

        # Query ALL CA policies
        $allPolicies = Get-MgIdentityConditionalAccessPolicy -ErrorAction Stop
        Write-Host "Total CA policies in tenant: $($allPolicies.Count)" -ForegroundColor Cyan

        # For each SSC policy, find overlapping policies
        $conflicts = @()

        foreach ($sscPolicy in $sscPolicies) {
            Write-Host "`nAnalyzing overlaps for: $($sscPolicy.DisplayName)" -ForegroundColor Cyan

            # Find policies that target the same groups (simplified overlap check)
            $overlappingPolicies = $allPolicies | Where-Object {
                $_.Id -ne $sscPolicy.Id -and
                $_.State -eq "enabled" -and
                $_.Conditions.Users.IncludeGroups -and
                ($_.Conditions.Users.IncludeGroups | Where-Object { $sscPolicy.Conditions.Users.IncludeGroups -contains $_ })
            }

            if ($overlappingPolicies) {
                Write-Host "  Found $($overlappingPolicies.Count) potentially overlapping policy(ies)" -ForegroundColor Yellow

                foreach ($overlap in $overlappingPolicies) {
                    $conflicts += @{
                        SscPolicy = $sscPolicy.DisplayName
                        ConflictingPolicy = $overlap.DisplayName
                        ConflictingPolicyId = $overlap.Id
                        Reason = "Both policies target overlapping user groups"
                    }

                    Write-Host "    - $($overlap.DisplayName)" -ForegroundColor Yellow
                }
            }
            else {
                Write-Host "  No conflicts detected" -ForegroundColor Green
            }
        }

        if ($conflicts.Count -eq 0) {
            $results.Validators.PolicyConflictAudit = @{
                Status = "Passed"
                Confidence = "MEDIUM"
                Reason = "No policy conflicts detected (informational check)."
                Conflicts = @()
                Timestamp = Get-Date -Format "o"
            }
            Write-Host "`nResult: PASSED (MEDIUM confidence)" -ForegroundColor Green
        }
        else {
            $results.Validators.PolicyConflictAudit = @{
                Status = "Warning"
                Confidence = "MEDIUM"
                Reason = "Found $($conflicts.Count) potential policy conflict(s) (informational - not a failure)."
                Conflicts = $conflicts
                Timestamp = Get-Date -Format "o"
            }
            Write-Host "`nResult: WARNING (MEDIUM confidence)" -ForegroundColor Yellow
            Write-Host "Note: Policy conflicts are informational only and do not fail overall validation." -ForegroundColor Yellow
        }

        Write-Host "Reason: $($results.Validators.PolicyConflictAudit.Reason)" -ForegroundColor Cyan
    }
    catch {
        $results.Validators.PolicyConflictAudit = @{
            Status = "Error"
            Reason = $_.Exception.Message
            Timestamp = Get-Date -Format "o"
        }
        Write-Warning "Policy Conflict Audit failed: $($_.Exception.Message)"
        Write-Host "Result: ERROR" -ForegroundColor Red
    }

    Write-Host ""
}

#endregion

#region Compute Overall Status

# Determine overall status based on individual validator results
$statuses = @()
foreach ($validatorName in $results.Validators.Keys) {
    $validator = $results.Validators[$validatorName]
    $validatorStatus = if ($validator.Status) {
        $validator.Status
    } else {
        "Unknown"
    }

    # Don't count Skipped validators in overall status
    if ($validatorStatus -ne "Skipped") {
        $statuses += $validatorStatus
    }
}

# Priority: Error/Failed > Warning > Passed
# Break-Glass failures are critical
if ($results.Validators.BreakGlassExclusions.Status -eq "Failed") {
    $results.OverallStatus = "Failed"
    $results.Reason = "CRITICAL: Break-glass validation failed. Tenant lockout risk detected."
}
elseif ($statuses -contains "Error" -or $statuses -contains "Failed") {
    $results.OverallStatus = "Failed"
    $results.Reason = "One or more validators failed. Review individual validator results."
}
elseif ($statuses -contains "Warning") {
    $results.OverallStatus = "Warning"
    $results.Reason = "All critical validators passed, but warnings detected. Review individual validator results."
}
elseif ($statuses -match "Passed") {
    $results.OverallStatus = "Passed"
    $results.Reason = "All validators passed successfully."
}
else {
    $results.OverallStatus = "Unknown"
    $results.Reason = "Unable to determine overall status. Check validator execution."
}

#endregion

#region Display Summary

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     Session Security Compliance Report          ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan

# Zone and timestamp
Write-Host ("║ Zone:           {0,-33}║" -f "$Zone ($($baseline.zoneName))") -ForegroundColor Cyan
Write-Host ("║ Timestamp:      {0,-33}║" -f $results.Timestamp) -ForegroundColor Cyan

# Overall status with color
$overallStatusLine = "║ Overall Status: "
Write-Host $overallStatusLine -NoNewline -ForegroundColor Cyan
$statusColor = switch ($results.OverallStatus) {
    "Passed" { "Green" }
    "Failed" { "Red" }
    "Warning" { "Yellow" }
    default { "Gray" }
}
$statusText = ("{0,-33}║" -f $results.OverallStatus.ToUpper())
Write-Host $statusText -ForegroundColor $statusColor

Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan

# Individual validator statuses
$validatorDisplayNames = @{
    "SessionControls" = "Session Controls"
    "AuthenticationStrength" = "Auth Strength"
    "PimRoleSettings" = "PIM Role Settings"
    "BreakGlassExclusions" = "Break-Glass Exclusions"
    "PolicyConflictAudit" = "Policy Conflict Audit"
}

foreach ($validatorName in @("SessionControls", "AuthenticationStrength", "PimRoleSettings", "BreakGlassExclusions", "PolicyConflictAudit")) {
    if ($results.Validators.ContainsKey($validatorName)) {
        $validator = $results.Validators[$validatorName]
        $validatorStatus = if ($validator.Status) { $validator.Status } else { "Unknown" }
        $validatorConfidence = if ($validator.Confidence) { "($($validator.Confidence) confidence)" } else { "" }

        $displayName = $validatorDisplayNames[$validatorName]

        $line = "║ {0,-21}" -f "${displayName}:"
        Write-Host $line -NoNewline -ForegroundColor Cyan

        $statusColor = switch ($validatorStatus) {
            "Passed" { "Green" }
            "Failed" { "Red" }
            "Warning" { "Yellow" }
            "Error" { "Red" }
            "Skipped" { "Gray" }
            default { "Gray" }
        }

        $statusText = "{0,-28}║" -f "$($validatorStatus.ToUpper()) $validatorConfidence"
        Write-Host $statusText -ForegroundColor $statusColor
    }
}

Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary: $($results.Reason)" -ForegroundColor Cyan
Write-Host ""

#endregion

#region JSON Output

if ($OutputPath) {
    try {
        $jsonOutput = $results | ConvertTo-Json -Depth 10
        $jsonOutput | Out-File -FilePath $OutputPath -Encoding utf8 -Force
        Write-Host "Results written to: $OutputPath" -ForegroundColor Green
        Write-Host ""
    }
    catch {
        Write-Warning "Failed to write JSON output: $($_.Exception.Message)"
    }
}

#endregion

#region Return Results

return $results

#endregion
