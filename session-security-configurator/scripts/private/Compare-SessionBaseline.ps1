#Requires -Version 7.0

<#
.SYNOPSIS
    Compares a Conditional Access policy's session controls against zone baseline.

.DESCRIPTION
    Validates that deployed CA policy session controls match the expected zone
    baseline configuration. Normalizes signInFrequency values (hours to minutes)
    for consistent comparison.

    Checks:
    - Sign-in frequency value and type
    - Persistent browser mode
    - Authentication strength policy ID
    - Compliant device requirement

    Returns structured result with status (Passed/Failed) and list of mismatches.

.PARAMETER Policy
    Policy object retrieved from Microsoft Graph (Get-MgIdentityConditionalAccessPolicy).
    Must contain sessionControls and grantControls properties.

.PARAMETER Baseline
    Baseline configuration object loaded from zone baseline JSON file.
    Expected properties:
    - signInFrequencyMinutes: Numeric value in minutes
    - persistentBrowser: Mode string ("never", "always", "persistent")
    - authenticationStrength: Auth strength policy ID (or $null)
    - requireCompliantDevice: Boolean

.EXAMPLE
    $policy = Get-MgIdentityConditionalAccessPolicy -Filter "displayName eq 'SSC-Zone2-Session-Controls'"
    $baseline = Get-Content "templates/session-baselines/zone2-baseline.json" | ConvertFrom-Json
    $result = Compare-SessionBaseline -Policy $policy -Baseline $baseline

    Returns:
    @{
        Status = "Passed"
        Mismatches = @()
    }

.EXAMPLE
    # Mismatch example
    $result = Compare-SessionBaseline -Policy $policy -Baseline $baseline

    Returns:
    @{
        Status = "Failed"
        Mismatches = @(
            @{ Property = "signInFrequency"; Expected = "240min"; Actual = "480min" }
            @{ Property = "authenticationStrength"; Expected = "policy-guid-1"; Actual = "policy-guid-2" }
        )
    }

.OUTPUTS
    PSCustomObject with properties:
    - Status: "Passed" or "Failed"
    - Mismatches: Array of mismatch objects (Property, Expected, Actual)

.NOTES
    Version: 1.0.0

    Normalization rules:
    - signInFrequency: Convert hours to minutes (4 hours = 240 minutes)
    - Missing properties treated as $null (e.g., policy without authenticationStrength)
    - persistentBrowser.mode compared as string (case-insensitive)

    Source pattern: ACV Compare-ValidationBaseline.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [object]$Policy,

    [Parameter(Mandatory = $true)]
    [object]$Baseline
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Compare-SessionBaseline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object]$Policy,

        [Parameter(Mandatory = $true)]
        [object]$Baseline
    )

    try {
        $results = @{
            Status = "Unknown"
            Mismatches = @()
        }

        Write-Verbose "Comparing policy '$($Policy.DisplayName)' against baseline for $($Baseline.zoneName)"

        # Check 1: Sign-in frequency
        if ($Policy.SessionControls.SignInFrequency) {
            # Normalize policy signInFrequency to minutes
            $policyMinutes = if ($Policy.SessionControls.SignInFrequency.Type -eq "hours") {
                $Policy.SessionControls.SignInFrequency.Value * 60
            }
            elseif ($Policy.SessionControls.SignInFrequency.Type -eq "minutes") {
                $Policy.SessionControls.SignInFrequency.Value
            }
            elseif ($Policy.SessionControls.SignInFrequency.Type -eq "days") {
                $Policy.SessionControls.SignInFrequency.Value * 1440
            }
            else {
                $null
            }

            $baselineMinutes = $Baseline.signInFrequencyMinutes

            if ($policyMinutes -ne $baselineMinutes) {
                $results.Mismatches += @{
                    Property = "signInFrequency"
                    Expected = "$($baselineMinutes)min"
                    Actual = if ($policyMinutes) { "$($policyMinutes)min" } else { "not configured" }
                }
                Write-Verbose "  Mismatch: signInFrequency - Expected $($baselineMinutes)min, Actual $($policyMinutes)min"
            }
            else {
                Write-Verbose "  ✓ signInFrequency matches: $($policyMinutes)min"
            }
        }
        elseif ($Baseline.signInFrequencyMinutes) {
            # Policy missing signInFrequency but baseline expects it
            $results.Mismatches += @{
                Property = "signInFrequency"
                Expected = "$($Baseline.signInFrequencyMinutes)min"
                Actual = "not configured"
            }
            Write-Verbose "  Mismatch: signInFrequency - Expected $($Baseline.signInFrequencyMinutes)min, Actual not configured"
        }

        # Check 2: Persistent browser mode
        if ($Policy.SessionControls.PersistentBrowser) {
            $policyBrowserMode = $Policy.SessionControls.PersistentBrowser.Mode
            $baselineBrowserMode = $Baseline.persistentBrowser

            if ($policyBrowserMode -ne $baselineBrowserMode) {
                $results.Mismatches += @{
                    Property = "persistentBrowser"
                    Expected = $baselineBrowserMode
                    Actual = $policyBrowserMode
                }
                Write-Verbose "  Mismatch: persistentBrowser - Expected $baselineBrowserMode, Actual $policyBrowserMode"
            }
            else {
                Write-Verbose "  ✓ persistentBrowser matches: $policyBrowserMode"
            }
        }
        elseif ($Baseline.persistentBrowser) {
            # Policy missing persistentBrowser but baseline expects it
            $results.Mismatches += @{
                Property = "persistentBrowser"
                Expected = $Baseline.persistentBrowser
                Actual = "not configured"
            }
            Write-Verbose "  Mismatch: persistentBrowser - Expected $($Baseline.persistentBrowser), Actual not configured"
        }

        # Check 3: Authentication strength
        # Graph API returns a GUID in AuthenticationStrength.Id while baseline JSON
        # stores a display name (e.g. "Passwordless MFA"). DisplayName is NOT populated
        # by default on Get-MgIdentityConditionalAccessPolicy results — resolve the policy
        # by ID to get its current display name.
        $policyAuthStrengthId = $Policy.GrantControls.AuthenticationStrength.Id
        $policyAuthStrength = $null
        if ($policyAuthStrengthId) {
            # Prefer DisplayName when present; otherwise resolve via auth-strength endpoint.
            if ($Policy.GrantControls.AuthenticationStrength.PSObject.Properties.Name -contains 'DisplayName' -and
                $Policy.GrantControls.AuthenticationStrength.DisplayName) {
                $policyAuthStrength = $Policy.GrantControls.AuthenticationStrength.DisplayName
            }
            else {
                try {
                    $strengthPolicy = Get-MgIdentityConditionalAccessAuthenticationStrengthPolicy -AuthenticationStrengthPolicyId $policyAuthStrengthId -ErrorAction Stop
                    $policyAuthStrength = $strengthPolicy.DisplayName
                }
                catch {
                    Write-Verbose "  Unable to resolve auth-strength policy $policyAuthStrengthId : $($_.Exception.Message)"
                }
            }
        }
        $baselineAuthStrength = $Baseline.authenticationStrength

        if ($policyAuthStrength -ne $baselineAuthStrength) {
            # Handle null comparisons (Zone 1 has no auth strength requirement)
            if ($null -eq $baselineAuthStrength -and $null -eq $policyAuthStrength) {
                Write-Verbose "  ✓ authenticationStrength matches: null (not required)"
            }
            else {
                $results.Mismatches += @{
                    Property = "authenticationStrength"
                    Expected = if ($baselineAuthStrength) { $baselineAuthStrength } else { "not required" }
                    Actual = if ($policyAuthStrength) { $policyAuthStrength } else { "not configured" }
                }
                Write-Verbose "  Mismatch: authenticationStrength - Expected $baselineAuthStrength, Actual $policyAuthStrength"
            }
        }
        else {
            Write-Verbose "  ✓ authenticationStrength matches: $policyAuthStrength"
        }

        # Check 4: Compliant device requirement
        $policyRequiresCompliantDevice = $Policy.GrantControls.BuiltInControls -contains "compliantDevice"
        $baselineRequiresCompliantDevice = $Baseline.requireCompliantDevice

        if ($policyRequiresCompliantDevice -ne $baselineRequiresCompliantDevice) {
            $results.Mismatches += @{
                Property = "requireCompliantDevice"
                Expected = $baselineRequiresCompliantDevice
                Actual = $policyRequiresCompliantDevice
            }
            Write-Verbose "  Mismatch: requireCompliantDevice - Expected $baselineRequiresCompliantDevice, Actual $policyRequiresCompliantDevice"
        }
        else {
            Write-Verbose "  ✓ requireCompliantDevice matches: $policyRequiresCompliantDevice"
        }

        # Check 5: MFA built-in control (Zone 1 baselines specify requireMfa: true since they
        # rely on builtInControls=mfa rather than a custom authentication strength policy).
        if ($Baseline.PSObject.Properties.Name -contains 'requireMfa' -and $Baseline.requireMfa) {
            $policyRequiresMfa = $Policy.GrantControls.BuiltInControls -contains "mfa"
            if (-not $policyRequiresMfa) {
                $results.Mismatches += @{
                    Property = "requireMfa"
                    Expected = $true
                    Actual = $false
                }
                Write-Verbose "  Mismatch: requireMfa - Expected true, Actual false"
            }
            else {
                Write-Verbose "  ✓ requireMfa matches: true"
            }
        }

        # Determine overall status
        if ($results.Mismatches.Count -eq 0) {
            $results.Status = "Passed"
            Write-Verbose "Baseline comparison: PASSED"
        }
        else {
            $results.Status = "Failed"
            Write-Verbose "Baseline comparison: FAILED ($($results.Mismatches.Count) mismatches)"
        }

        return [PSCustomObject]$results
    }
    catch {
        Write-Error "Baseline comparison error: $($_.Exception.Message)"

        return [PSCustomObject]@{
            Status = "Error"
            Mismatches = @()
            Error = $_.Exception.Message
        }
    }
}

# Execute function if script is run directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    $result = Compare-SessionBaseline @PSBoundParameters
    return $result
}


