<#
.SYNOPSIS
    Tests Conditional Access policy compliance and coverage.

.DESCRIPTION
    Verifies that CA policies are properly configured, covering all required
    zones and applications, with correct grant and session controls.

.PARAMETER TenantId
    Azure AD tenant ID.

.PARAMETER ConfigPath
    Path to tenant configuration JSON file.

.PARAMETER OutputPath
    Directory for compliance reports.

.PARAMETER IncludeReportOnly
    Include report-only policies in coverage analysis.

.EXAMPLE
    .\Test-PolicyCompliance.ps1 -TenantId "xxx" -ConfigPath "./config.json" -OutputPath "./reports"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeReportOnly
)

#Requires -Version 7.0
#Requires -Modules Microsoft.Graph.Identity.SignIns

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

$timestamp = Get-Date -Format "yyyy-MM-dd"

Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Conditional Access Policy Compliance Check" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan
Write-Host "Tenant: $TenantId"
Write-Host "Timestamp: $timestamp"
Write-Host ""

# Load configuration
try {
    Write-Verbose "Loading configuration from $ConfigPath..."
    if (-not (Test-Path $ConfigPath)) {
        throw "Configuration file not found: $ConfigPath"
    }
    $config = Get-Content $ConfigPath -ErrorAction Stop | ConvertFrom-Json
    Write-Verbose "Configuration loaded successfully."
}
catch {
    Write-Error "Failed to load configuration from $ConfigPath"
    Write-Error "Error: $_"
    throw
}

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Connect to Microsoft Graph
try {
    Write-Host "Connecting to Microsoft Graph..."
    $context = Get-MgContext
    if (-not $context -or $context.TenantId -ne $TenantId) {
        Connect-MgGraph -TenantId $TenantId -Scopes "Policy.Read.All" -ErrorAction Stop
    }
    Write-Host "Connected." -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to Microsoft Graph (Tenant: $TenantId)"
    Write-Error "Error: $_"
    throw
}

# Get all CA policies
try {
    Write-Host "`nRetrieving Conditional Access policies..."
    $allPolicies = Get-MgIdentityConditionalAccessPolicy -ErrorAction Stop
    $fsiPolicies = $allPolicies | Where-Object {
        $_.DisplayName -like "CA-FSI-*" -or $_.DisplayName -like "$($config.policyPrefix)-*"
    }
    Write-Host "Found $($fsiPolicies.Count) FSI policies out of $($allPolicies.Count) total."
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

# Define expected policies
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

# Check 1: Policy Existence
Write-Host "`nChecking policy existence..." -ForegroundColor Yellow

foreach ($zone in $expectedPolicies.Keys) {
    foreach ($expected in $expectedPolicies[$zone]) {
        $complianceResults.checksPerformed++

        $matchingPolicies = $fsiPolicies | Where-Object {
            $_.DisplayName -like $expected.Pattern
        }

        if ($matchingPolicies.Count -gt 0) {
            $complianceResults.checksPassed++
            Write-Host "  [PASS] $($expected.Pattern)" -ForegroundColor Green

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
            Write-Host "  [FAIL] $($expected.Pattern) - Not found" -ForegroundColor Red

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
Write-Host "`nChecking policy states..." -ForegroundColor Yellow

foreach ($policy in $fsiPolicies) {
    $complianceResults.checksPerformed++

    $isEnabled = $policy.State -eq "enabled"
    $isReportOnly = $policy.State -eq "enabledForReportingButNotEnforced"
    $isDisabled = $policy.State -eq "disabled"

    if ($isEnabled -or ($IncludeReportOnly -and $isReportOnly)) {
        $complianceResults.checksPassed++
        $stateDisplay = if ($isReportOnly) { "Report-Only" } else { "Enabled" }
        Write-Host "  [PASS] $($policy.DisplayName) - $stateDisplay" -ForegroundColor Green
    }
    elseif ($isReportOnly -and -not $IncludeReportOnly) {
        $complianceResults.checksFailed++
        Write-Host "  [WARN] $($policy.DisplayName) - Report-Only (not enforcing)" -ForegroundColor Yellow
        $complianceResults.gaps += @{
            type = "PolicyNotEnabled"
            policy = $policy.DisplayName
            currentState = $policy.State
            recommendation = "Enable policy for enforcement"
        }
    }
    else {
        $complianceResults.checksFailed++
        Write-Host "  [FAIL] $($policy.DisplayName) - Disabled" -ForegroundColor Red
        $complianceResults.gaps += @{
            type = "PolicyDisabled"
            policy = $policy.DisplayName
            currentState = $policy.State
            recommendation = "Review and enable policy"
        }
    }
}

# Check 3: Break-Glass Exclusions
Write-Host "`nChecking break-glass exclusions..." -ForegroundColor Yellow

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
        Write-Host "  [PASS] $($policy.DisplayName) - Break-glass accounts excluded" -ForegroundColor Green
    }
    else {
        $complianceResults.checksFailed++
        Write-Host "  [FAIL] $($policy.DisplayName) - Missing break-glass exclusions" -ForegroundColor Red
        $complianceResults.gaps += @{
            type = "MissingBreakGlassExclusion"
            policy = $policy.DisplayName
            recommendation = "Add all break-glass accounts to exclusion list"
        }
    }
}

# Check 4: Grant Controls (MFA)
Write-Host "`nChecking MFA requirements..." -ForegroundColor Yellow

foreach ($policy in $fsiPolicies) {
    # Skip block policies
    if ($policy.GrantControls.BuiltInControls -contains "block") {
        continue
    }

    $complianceResults.checksPerformed++

    $hasMFA = $policy.GrantControls.BuiltInControls -contains "mfa"

    if ($hasMFA) {
        $complianceResults.checksPassed++
        Write-Host "  [PASS] $($policy.DisplayName) - MFA required" -ForegroundColor Green
    }
    else {
        $complianceResults.checksFailed++
        Write-Host "  [WARN] $($policy.DisplayName) - MFA not required" -ForegroundColor Yellow
        $complianceResults.gaps += @{
            type = "NoMFARequirement"
            policy = $policy.DisplayName
            grantControls = $policy.GrantControls.BuiltInControls
            recommendation = "Add MFA to grant controls"
        }
    }
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
Write-Host "`n" + "=" * 60 -ForegroundColor Cyan
Write-Host "Compliance Summary" -ForegroundColor Cyan
Write-Host "=" * 60 -ForegroundColor Cyan

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

# Export results
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

Write-Host "`nCompliance check complete." -ForegroundColor Green
