<#
.SYNOPSIS
    Tests Conditional Access policy compliance, coverage, and session controls.

.DESCRIPTION
    Verifies that Conditional Access policies are properly configured, covering all
    required governance zones and AI applications with correct grant controls, session
    controls, and break-glass exclusions.

    Performs five compliance checks (six when BaselinePath is provided):
      1. Policy Existence — verifies expected policies exist for each zone
      2. Policy State — confirms policies are enabled or report-only
      3. Break-Glass Exclusions — validates emergency accounts are excluded
      4. MFA Grant Controls — checks MFA requirement on non-block policies
      5. Session Controls — validates signInFrequency and persistentBrowser settings
      6. Policy Drift Analysis — compares current state against a saved baseline (optional)

    Supports WhatIf mode to preview which policies would be checked without
    querying Microsoft Graph.

.PARAMETER TenantId
    The Entra ID (Azure AD) tenant GUID to check policies against.

.PARAMETER ConfigPath
    Path to the tenant configuration JSON file containing group IDs,
    application IDs, break-glass accounts, and optional policy prefix.

.PARAMETER OutputPath
    Optional directory path for compliance report files.  When provided,
    JSON report files are written to this directory.  When omitted,
    results are displayed to the console only.

.PARAMETER OutputFormat
    Format for console output. Valid values: Table (default), JSON, Object.
    Table renders a formatted summary; JSON writes raw JSON to the pipeline;
    Object returns the compliance results hashtable for further processing.

.PARAMETER BaselinePath
    Optional path to a previously exported baseline JSON file (from
    Export-PolicyBaseline.ps1). When provided, an additional drift analysis
    check compares the current policy state against the baseline and adds
    findings to the compliance results.

.PARAMETER IncludeReportOnly
    When specified, counts report-only policies as passing the state check.

.EXAMPLE
    .\Test-PolicyCompliance.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -ConfigPath "./config.json"

    Runs compliance checks and displays results in table format on the console.

.EXAMPLE
    .\Test-PolicyCompliance.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -ConfigPath "./config.json" -OutputPath "./reports" -OutputFormat JSON

    Runs checks, exports JSON reports to ./reports, and writes raw JSON to stdout.

.EXAMPLE
    .\Test-PolicyCompliance.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -ConfigPath "./config.json" -WhatIf

    Previews which policies would be checked without connecting to Graph.

.OUTPUTS
    System.Collections.Hashtable
    When -OutputFormat is 'Object', returns the compliance results hashtable.

.NOTES
    File: Test-PolicyCompliance.ps1
    Version: 2.0.0
    Supports compliance with FINRA 4511/3110, SEC 17a-3/4, and OCC 2011-12
    through automated policy coverage verification and gap detection.
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Table", "JSON", "Object")]
    [string]$OutputFormat = "Table",

    [Parameter(Mandatory = $false)]
    [string]$BaselinePath,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeReportOnly
)

#Requires -Version 7.0
#Requires -Modules @{ ModuleName = 'Microsoft.Graph.Identity.SignIns'; ModuleVersion = '2.0.0' }

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Import private helpers
. $PSScriptRoot/private/Connect-GraphSession.ps1
. $PSScriptRoot/private/Get-ZoneClassification.ps1
. $PSScriptRoot/private/Test-ParameterValidation.ps1
. $PSScriptRoot/private/Get-PolicyBaseline.ps1
. $PSScriptRoot/private/Compare-PolicyBaseline.ps1

$timestamp = Get-Date -Format "yyyy-MM-dd"

Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "Conditional Access Policy Compliance Check" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "Tenant: $TenantId"
Write-Host "Timestamp: $timestamp"
Write-Host ""

# Load configuration
Write-Verbose "Loading configuration from $ConfigPath..."
Test-CAAConfigPath -Path $ConfigPath
$config = Get-Content $ConfigPath -ErrorAction Stop | ConvertFrom-Json
Write-Verbose "Configuration loaded and validated."

# Define expected policies (used in WhatIf preview and live checks)
$expectedPolicies = @{
    "Zone1" = @(
        @{ Pattern = "*CopilotStudio*Zone1*"; Required = $true }
    )
    "Zone2" = @(
        @{ Pattern = "*CopilotStudio*Zone2*"; Required = $true }
        @{ Pattern = "*AgentBuilder*Zone2*"; Required = $true }
    )
    "Zone3" = @(
        @{ Pattern = "*CopilotStudio*Zone3*"; Required = $true }
        @{ Pattern = "*AgentBuilder*Zone3*"; Required = $true }
        @{ Pattern = "*CompliantDevice*Zone3*"; Required = $true }
    )
    "Common" = @(
        @{ Pattern = "*M365Copilot*"; Required = $true }
        @{ Pattern = "*BlockLegacyAuth*"; Required = $true }
    )
}

# WhatIf preview — list what would be checked without querying Graph
if ($WhatIfPreference) {
    Write-Host "[WhatIf] Would perform the following compliance checks:" -ForegroundColor Yellow
    Write-Host ""
    foreach ($zone in $expectedPolicies.Keys) {
        Write-Host "  $zone policies:" -ForegroundColor Cyan
        foreach ($expected in $expectedPolicies[$zone]) {
            Write-Host "    - $($expected.Pattern) (Required: $($expected.Required))"
        }
    }
    Write-Host ""
    Write-Host "  Checks: Policy Existence, Policy State, Break-Glass Exclusions, MFA Grant Controls, Session Controls"
    if ($BaselinePath) {
        Write-Host "  + Check 6: Policy Drift Analysis (baseline: $BaselinePath)"
    }
    Write-Host "  Output format: $OutputFormat"
    if ($OutputPath) {
        Write-Host "  Report output: $OutputPath"
    }
    else {
        Write-Host "  Report output: Console only"
    }
    return
}

# Ensure output directory exists (when provided)
if ($OutputPath -and -not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Connect to Microsoft Graph
Write-Verbose "Establishing Microsoft Graph session..."
Connect-CAAGraphSession -TenantId $TenantId -Scopes @('Policy.Read.All')
Write-Verbose "Connected."

# Get all CA policies
Write-Verbose "Retrieving Conditional Access policies..."
try {
    $allPolicies = Get-MgIdentityConditionalAccessPolicy -ErrorAction Stop
    $fsiPolicies = $allPolicies | Where-Object {
        $_.DisplayName -like "CA-FSI-*" -or
        $_.DisplayName -like "CA-CopilotStudio-*" -or
        $_.DisplayName -like "CA-AgentBuilder-*" -or
        $_.DisplayName -like "CA-M365Copilot-*" -or
        $_.DisplayName -like "CA-BlockLegacyAuth-*" -or
        $_.DisplayName -like "CA-RequireCompliantDevice-*" -or
        ($config.policyPrefix -and $_.DisplayName -like "$($config.policyPrefix)-*")
    }
    Write-Verbose "Found $($fsiPolicies.Count) FSI policies out of $($allPolicies.Count) total."
}
catch {
    Write-Error "Failed to retrieve Conditional Access policies"
    Write-Error "Error: $_"
    throw
}

# Initialize results
$complianceResults = @{
    timestamp = (Get-Date).ToUniversalTime().ToString("o")
    tenantId = $TenantId
    overallCompliance = "Unknown"
    checksPerformed = 0
    checksPassed = 0
    checksFailed = 0
    coverage = @{
        zone1 = @{ status = "Unknown"; policies = @() }
        zone2 = @{ status = "Unknown"; policies = @() }
        zone3 = @{ status = "Unknown"; policies = @() }
    }
    gaps = @()
    details = @()
}

# Check 1: Policy Existence
Write-Verbose "Checking policy existence..."

foreach ($zone in $expectedPolicies.Keys) {
    foreach ($expected in $expectedPolicies[$zone]) {
        $complianceResults.checksPerformed++

        $matchingPolicies = $fsiPolicies | Where-Object {
            $_.DisplayName -like $expected.Pattern
        }

        if ($matchingPolicies.Count -gt 0) {
            $complianceResults.checksPassed++
            Write-Verbose "  [PASS] $($expected.Pattern)"

            foreach ($policy in $matchingPolicies) {
                $complianceResults.details += @{
                    check = "PolicyExists"
                    policy = $policy.DisplayName
                    result = "Pass"
                }

                # Add to zone coverage
                $zoneLower = $zone.ToLower()
                if ($complianceResults.coverage.$zoneLower) {
                    $complianceResults.coverage.$zoneLower.policies += $policy.DisplayName
                }
            }
        }
        else {
            $complianceResults.checksFailed++
            Write-Verbose "  [FAIL] $($expected.Pattern) - Not found"

            $complianceResults.gaps += @{
                type = "MissingPolicy"
                pattern = $expected.Pattern
                zone = $zone
                recommendation = "Create policy matching pattern: $($expected.Pattern)"
            }
        }
    }
}

# Check 2: Policy State
Write-Verbose "Checking policy states..."

foreach ($policy in $fsiPolicies) {
    $complianceResults.checksPerformed++

    $isEnabled = $policy.State -eq "enabled"
    $isReportOnly = $policy.State -eq "enabledForReportingButNotEnforced"
    $isDisabled = $policy.State -eq "disabled"

    if ($isEnabled -or ($IncludeReportOnly -and $isReportOnly)) {
        $complianceResults.checksPassed++
        $stateDisplay = if ($isReportOnly) { "Report-Only" } else { "Enabled" }
        Write-Verbose "  [PASS] $($policy.DisplayName) - $stateDisplay"
    }
    elseif ($isReportOnly -and -not $IncludeReportOnly) {
        $complianceResults.checksFailed++
        Write-Verbose "  [WARN] $($policy.DisplayName) - Report-Only (not enforcing)"
        $complianceResults.gaps += @{
            type = "PolicyNotEnabled"
            policy = $policy.DisplayName
            currentState = $policy.State
            recommendation = "Enable policy for enforcement"
        }
    }
    else {
        $complianceResults.checksFailed++
        Write-Verbose "  [FAIL] $($policy.DisplayName) - Disabled"
        $complianceResults.gaps += @{
            type = "PolicyDisabled"
            policy = $policy.DisplayName
            currentState = $policy.State
            recommendation = "Review and enable policy"
        }
    }
}

# Check 3: Break-Glass Exclusions
Write-Verbose "Checking break-glass exclusions..."

foreach ($policy in $fsiPolicies) {
    $complianceResults.checksPerformed++

    $excludedUsers = $policy.Conditions.Users.ExcludeUsers
    $allBreakGlassExcluded = $true

    foreach ($bgAccount in $config.breakGlassAccounts) {
        if ($excludedUsers -notcontains $bgAccount) {
            $allBreakGlassExcluded = $false
            break
        }
    }

    if ($allBreakGlassExcluded) {
        $complianceResults.checksPassed++
        Write-Verbose "  [PASS] $($policy.DisplayName) - Break-glass accounts excluded"
    }
    else {
        $complianceResults.checksFailed++
        Write-Verbose "  [FAIL] $($policy.DisplayName) - Missing break-glass exclusions"
        $complianceResults.gaps += @{
            type = "MissingBreakGlassExclusion"
            policy = $policy.DisplayName
            recommendation = "Add all break-glass accounts to exclusion list"
        }
    }
}

# Check 4: Grant Controls (MFA)
Write-Verbose "Checking MFA requirements..."

foreach ($policy in $fsiPolicies) {
    # Skip block policies
    if ($policy.GrantControls.BuiltInControls -contains "block") {
        continue
    }

    $complianceResults.checksPerformed++

    $hasMFA = $policy.GrantControls.BuiltInControls -contains "mfa"

    if ($hasMFA) {
        $complianceResults.checksPassed++
        Write-Verbose "  [PASS] $($policy.DisplayName) - MFA required"
    }
    else {
        $complianceResults.checksFailed++
        Write-Verbose "  [WARN] $($policy.DisplayName) - MFA not required"
        $complianceResults.gaps += @{
            type = "NoMFARequirement"
            policy = $policy.DisplayName
            grantControls = $policy.GrantControls.BuiltInControls
            recommendation = "Add MFA to grant controls"
        }
    }
}

# Check 5: Session Controls (signInFrequency and persistentBrowser)
Write-Verbose "Checking session controls..."

foreach ($policy in $fsiPolicies) {
    # Skip block policies — they don't need session controls
    if ($policy.GrantControls.BuiltInControls -contains "block") {
        continue
    }

    $complianceResults.checksPerformed++

    $sessionControls = $policy.SessionControls
    $hasSignInFrequency = $sessionControls -and
        $sessionControls.SignInFrequency -and
        $sessionControls.SignInFrequency.IsEnabled -eq $true
    $hasPersistentBrowser = $sessionControls -and
        $sessionControls.PersistentBrowser -and
        $sessionControls.PersistentBrowser.IsEnabled -eq $true

    # Determine expected session controls based on zone (Zone3 should have persistentBrowser = never)
    $isZone3 = $policy.DisplayName -like "*Zone3*"

    if ($hasSignInFrequency) {
        $freqValue = $sessionControls.SignInFrequency.Value
        $freqType = $sessionControls.SignInFrequency.Type
        Write-Verbose "  [PASS] $($policy.DisplayName) - Sign-in frequency: $freqValue $freqType"

        if ($isZone3 -and $hasPersistentBrowser) {
            $browserMode = $sessionControls.PersistentBrowser.Mode
            if ($browserMode -eq "never") {
                Write-Verbose "  [PASS] $($policy.DisplayName) - Persistent browser: $browserMode"
                $complianceResults.checksPassed++
            }
            else {
                Write-Verbose "  [WARN] $($policy.DisplayName) - Persistent browser mode is '$browserMode', expected 'never' for Zone3"
                $complianceResults.checksFailed++
                $complianceResults.gaps += @{
                    type = "SessionControlMisconfigured"
                    policy = $policy.DisplayName
                    detail = "persistentBrowser.mode is '$browserMode', expected 'never' for Zone3"
                    recommendation = "Set persistentBrowser.mode to 'never' for Zone3 policies"
                }
            }
        }
        elseif ($isZone3 -and -not $hasPersistentBrowser) {
            Write-Verbose "  [WARN] $($policy.DisplayName) - Zone3 policy missing persistentBrowser control"
            $complianceResults.checksFailed++
            $complianceResults.gaps += @{
                type = "MissingSessionControl"
                policy = $policy.DisplayName
                detail = "Zone3 policy should have persistentBrowser set to 'never'"
                recommendation = "Add persistentBrowser session control with mode 'never'"
            }
        }
        else {
            $complianceResults.checksPassed++
        }
    }
    else {
        $complianceResults.checksFailed++
        Write-Verbose "  [WARN] $($policy.DisplayName) - No sign-in frequency configured"
        $complianceResults.gaps += @{
            type = "MissingSessionControl"
            policy = $policy.DisplayName
            detail = "signInFrequency not configured or not enabled"
            recommendation = "Configure sign-in frequency for session timeout enforcement"
        }
    }

    $complianceResults.details += @{
        check = "SessionControls"
        policy = $policy.DisplayName
        signInFrequency = if ($hasSignInFrequency) { "$($sessionControls.SignInFrequency.Value) $($sessionControls.SignInFrequency.Type)" } else { "Not configured" }
        persistentBrowser = if ($hasPersistentBrowser) { $sessionControls.PersistentBrowser.Mode } else { "Not configured" }
        result = if ($hasSignInFrequency) { "Pass" } else { "Fail" }
    }
}

# Check 6: Policy Drift Analysis (when BaselinePath provided)
if ($BaselinePath) {
    Write-Verbose "Running policy drift analysis against baseline: $BaselinePath"

    if (-not (Test-Path $BaselinePath)) {
        Write-Warning "Baseline file not found: $BaselinePath — skipping drift analysis"
    }
    else {
        $baselineContent = Get-Content $BaselinePath -Raw -ErrorAction Stop | ConvertFrom-Json
        $previousPolicies = $baselineContent.policies

        # Build current baseline from the already-retrieved policies
        $currentBaseline = Get-CAAPolicyBaseline -TenantId $TenantId

        $driftResults = Compare-CAAPolicyBaseline -PreviousBaseline @($previousPolicies) -CurrentBaseline @($currentBaseline)
        $driftFindings = @($driftResults | Where-Object { $_.DriftType -ne 'None' })

        foreach ($drift in $driftResults) {
            $complianceResults.checksPerformed++
            if ($drift.Severity -le 1) {
                $complianceResults.checksPassed++
            }
            else {
                $complianceResults.checksFailed++
            }
        }

        $complianceResults['driftAnalysis'] = @{
            baselineFile     = $BaselinePath
            totalDriftItems  = $driftFindings.Count
            findings         = @($driftResults)
        }

        if ($driftFindings.Count -gt 0) {
            $complianceResults.gaps += @{
                type           = "PolicyDrift"
                driftCount     = $driftFindings.Count
                recommendation = "Review drift findings and re-export baseline after remediation"
            }
        }

        Write-Verbose "  Drift analysis complete: $($driftFindings.Count) drift items found"
    }
}
else {
    Write-Verbose "No baseline provided — run Export-PolicyBaseline.ps1 to establish a baseline for drift detection"
}

# Determine zone coverage status
foreach ($zone in @("zone1", "zone2", "zone3")) {
    if ($complianceResults.coverage.$zone.policies.Count -gt 0) {
        $complianceResults.coverage.$zone.status = "Covered"
    }
    else {
        $complianceResults.coverage.$zone.status = "NotCovered"
    }
}

# Calculate overall compliance
$complianceRate = if ($complianceResults.checksPerformed -gt 0) {
    [math]::Round(($complianceResults.checksPassed / $complianceResults.checksPerformed) * 100, 2)
}
else { 0 }

$complianceResults.overallCompliance = if ($complianceRate -ge 95) {
    "Compliant"
}
elseif ($complianceRate -ge 80) {
    "PartiallyCompliant"
}
else {
    "NonCompliant"
}

# Summary
Write-Host ("`n" + "=" * 60) -ForegroundColor Cyan
Write-Host "Compliance Summary" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan

Write-Host "`nChecks Performed: $($complianceResults.checksPerformed)"
Write-Host "Checks Passed: $($complianceResults.checksPassed)" -ForegroundColor Green
Write-Host "Checks Failed: $($complianceResults.checksFailed)" -ForegroundColor $(if ($complianceResults.checksFailed -gt 0) { "Red" } else { "Green" })
Write-Host "Compliance Rate: $complianceRate%"
Write-Host "Overall Status: $($complianceResults.overallCompliance)" -ForegroundColor $(
    switch ($complianceResults.overallCompliance) {
        "Compliant" { "Green" }
        "PartiallyCompliant" { "Yellow" }
        default { "Red" }
    }
)

Write-Host "`nZone Coverage:"
foreach ($zone in @("zone1", "zone2", "zone3")) {
    $status = $complianceResults.coverage.$zone.status
    $color = if ($status -eq "Covered") { "Green" } else { "Red" }
    Write-Host "  $($zone.ToUpper()): $status ($($complianceResults.coverage.$zone.policies.Count) policies)" -ForegroundColor $color
}

if ($complianceResults.gaps.Count -gt 0) {
    Write-Host "`nGaps Identified: $($complianceResults.gaps.Count)" -ForegroundColor Yellow
    $complianceResults.gaps | ForEach-Object {
        Write-Host "  - [$($_.type)] $($_.recommendation)" -ForegroundColor Yellow
    }
}

if ($complianceResults.ContainsKey('driftAnalysis')) {
    $driftData = $complianceResults['driftAnalysis']
    Write-Host "`nDrift Analysis:" -ForegroundColor Cyan
    Write-Host "  Baseline: $($driftData.baselineFile)"
    Write-Host "  Drift items found: $($driftData.totalDriftItems)" -ForegroundColor $(if ($driftData.totalDriftItems -gt 0) { "Yellow" } else { "Green" })
}

# Output results based on format
switch ($OutputFormat) {
    "JSON" {
        $complianceResults | ConvertTo-Json -Depth 10
    }
    "Object" {
        $complianceResults
    }
    # "Table" — already displayed above via Write-Host
}

# Export results to files (only when OutputPath is specified)
if ($OutputPath) {
    try {
        $coverageFile = Join-Path $OutputPath "PolicyCoverage-$timestamp.json"
        $complianceResults | ConvertTo-Json -Depth 10 | Out-File $coverageFile -Encoding utf8
        Write-Host "`nResults exported to: $coverageFile" -ForegroundColor Green

        $gapsFile = Join-Path $OutputPath "PolicyGaps-$timestamp.json"
        $complianceResults.gaps | ConvertTo-Json -Depth 5 | Out-File $gapsFile -Encoding utf8
        Write-Host "Gaps exported to: $gapsFile"
    }
    catch {
        Write-Error "Failed to export compliance results to $OutputPath"
        Write-Error "Error: $_"
        throw
    }
}

Write-Host "`nCompliance check complete." -ForegroundColor Green
