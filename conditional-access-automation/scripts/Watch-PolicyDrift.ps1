<#
.SYNOPSIS
    Detects drift between a saved Conditional Access policy baseline and the
    current live tenant state.

.DESCRIPTION
    Loads a previously exported baseline JSON file, queries the current CA
    policy state from Microsoft Graph, and compares the two snapshots across
    five dimensions: state changes, condition changes, grant control changes,
    session control changes, and policy additions/removals.

    Each finding is classified using the ACV severity scale (1–5) with
    Zone 3 escalation. Results are filtered by the specified severity
    threshold and displayed using the requested output format.

    Exit codes support CI/CD pipeline integration:
      0 — No drift above the specified severity threshold
      1 — Drift detected above the specified severity threshold

    Supports WhatIf mode to preview the detection workflow without querying Graph.

.PARAMETER TenantId
    The Entra ID tenant GUID to check policies against.

.PARAMETER BaselinePath
    Path to the previously exported baseline JSON file (from Export-PolicyBaseline.ps1).

.PARAMETER ConfigPath
    Optional path to a tenant configuration JSON file containing group IDs,
    application IDs, break-glass accounts, and an optional policyPrefix.

.PARAMETER OutputPath
    Optional file path for writing drift detection results as a JSON report.

.PARAMETER OutputFormat
    Format for console output. Valid values: Table (default), JSON, Object.
    Table renders a formatted summary banner; JSON writes raw JSON to the
    pipeline; Object returns the results hashtable for pipeline processing.

.PARAMETER SeverityThreshold
    Minimum severity level to report. Findings below this threshold are excluded
    from the output. Valid values: Passed (1), Warning (2), GracePeriod (3),
    Failed (4), Error (5). Default: Warning.

.EXAMPLE
    .\Watch-PolicyDrift.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -BaselinePath "./baselines/baseline.json"

    Compares current policies against the baseline and displays drift in table format.

.EXAMPLE
    .\Watch-PolicyDrift.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -BaselinePath "./baseline.json" -SeverityThreshold Failed

    Reports only Failed (4) and Error (5) severity findings.

.EXAMPLE
    .\Watch-PolicyDrift.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -BaselinePath "./baseline.json" -OutputPath "./reports/drift.json" -OutputFormat JSON

    Writes drift results to a JSON report file and outputs JSON to the pipeline.

.EXAMPLE
    .\Watch-PolicyDrift.ps1 -TenantId "00000000-0000-0000-0000-000000000000" -BaselinePath "./baseline.json" -WhatIf

    Previews which policies would be checked without connecting to Graph.

.OUTPUTS
    System.Collections.Hashtable
    When -OutputFormat is 'Object', returns the drift detection results hashtable.

.NOTES
    File: Watch-PolicyDrift.ps1
    Version: 1.0.0
    Exit code 0: No drift above threshold. Exit code 1: Drift detected above threshold.
    Supports compliance with FINRA 4511/3110, SEC 17a-3/4, and OCC 2011-12
    through automated policy drift detection and severity-based alerting.
#>

#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$BaselinePath,

    [Parameter(Mandatory = $false)]
    [string]$ConfigPath,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [ValidateSet("Table", "JSON", "Object")]
    [string]$OutputFormat = "Table",

    [Parameter(Mandatory = $false)]
    [ValidateSet("Passed", "Warning", "GracePeriod", "Failed", "Error")]
    [string]$SeverityThreshold = "Warning"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# Import private helpers
. $PSScriptRoot/private/Connect-GraphSession.ps1
. $PSScriptRoot/private/Get-PolicyBaseline.ps1
. $PSScriptRoot/private/Compare-PolicyBaseline.ps1

# Map severity names to numbers
$severityMap = @{
    'Passed'      = 1
    'Warning'     = 2
    'GracePeriod' = 3
    'Failed'      = 4
    'Error'       = 5
}
$severityNumber = $severityMap[$SeverityThreshold]

# Reverse map for display
$severityNames = @{
    1 = 'Passed'
    2 = 'Warning'
    3 = 'GracePeriod'
    4 = 'Failed'
    5 = 'Error'
}

Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "CA Policy Drift Detection" -ForegroundColor Cyan
Write-Host ("=" * 60) -ForegroundColor Cyan
Write-Host "Tenant: $TenantId"
Write-Host "Baseline: $BaselinePath"
Write-Host "Severity threshold: $SeverityThreshold ($severityNumber)"
Write-Host ""

# WhatIf preview
if ($WhatIfPreference) {
    Write-Host "[WhatIf] Would perform the following:" -ForegroundColor Yellow
    Write-Host "  1. Load baseline from: $BaselinePath"
    Write-Host "  2. Connect to Microsoft Graph (Tenant: $TenantId)"
    Write-Host "  3. Query current CA policies matching FSI naming patterns"
    Write-Host "  4. Compare current state against baseline"
    Write-Host "  5. Filter findings at severity >= $SeverityThreshold ($severityNumber)"
    if ($OutputPath) {
        Write-Host "  6. Write report to: $OutputPath"
    }
    Write-Host "  Output format: $OutputFormat"
    return
}

# Step 1: Load baseline
Write-Verbose "Loading baseline from $BaselinePath..."
if (-not (Test-Path $BaselinePath)) {
    Write-Error "Baseline file not found: $BaselinePath"
    throw "Baseline file not found: $BaselinePath"
}

$baselineContent = Get-Content $BaselinePath -Raw -ErrorAction Stop | ConvertFrom-Json
$previousPolicies = $baselineContent.policies
Write-Verbose "Loaded baseline with $($previousPolicies.Count) policies"

# Step 2: Connect and query current state
Write-Verbose "Establishing Microsoft Graph session..."
Connect-CAAGraphSession -TenantId $TenantId -Scopes @('Policy.Read.All')
Write-Verbose "Connected."

Write-Verbose "Capturing current policy state..."
$baselineParams = @{}
if ($TenantId) { $baselineParams['TenantId'] = $TenantId }
if ($ConfigPath) { $baselineParams['ConfigPath'] = $ConfigPath }

$currentPolicies = Get-CAAPolicyBaseline @baselineParams

# Step 3: Compare baselines
Write-Verbose "Comparing baselines..."
$allDrifts = Compare-CAAPolicyBaseline -PreviousBaseline @($previousPolicies) -CurrentBaseline @($currentPolicies)

# Step 4: Filter by severity threshold
$filteredDrifts = @($allDrifts | Where-Object { $_.Severity -ge $severityNumber })
$driftItems = @($filteredDrifts | Where-Object { $_.DriftType -ne 'None' })
$passedItems = @($allDrifts | Where-Object { $_.Severity -eq 1 })

# Compute counts for summary
$totalPoliciesChecked = $previousPolicies.Count
$driftCount = $driftItems.Count
$criticalCount = @($driftItems | Where-Object { $_.Severity -ge 4 }).Count
$warningCount = @($driftItems | Where-Object { $_.Severity -ge 2 -and $_.Severity -le 3 }).Count
$passedCount = $passedItems.Count

# Build critical detail description
$criticalDetail = ''
if ($criticalCount -gt 0) {
    $firstCritical = $driftItems | Where-Object { $_.Severity -ge 4 } | Select-Object -First 1
    $criticalDetail = "($($firstCritical.Description))"
}

$warningDetail = ''
if ($warningCount -gt 0) {
    $firstWarning = $driftItems | Where-Object { $_.Severity -ge 2 -and $_.Severity -le 3 } | Select-Object -First 1
    $warningDetail = "($($firstWarning.Description))"
}

# Step 5: Display summary banner
$bannerWidth = 56
Write-Host ""
Write-Host ([char]0x2554 + ([string][char]0x2550 * $bannerWidth) + [char]0x2557) -ForegroundColor Cyan
Write-Host ([char]0x2551 + "  CA Policy Drift Detection Results".PadRight($bannerWidth) + [char]0x2551) -ForegroundColor Cyan
Write-Host ([char]0x2560 + ([string][char]0x2550 * $bannerWidth) + [char]0x2563) -ForegroundColor Cyan
Write-Host ([char]0x2551 + "  Policies Checked:  $($totalPoliciesChecked.ToString().PadRight($bannerWidth - 22))" + [char]0x2551) -ForegroundColor Cyan
Write-Host ([char]0x2551 + "  Drift Detected:    $($driftCount.ToString().PadRight($bannerWidth - 22))" + [char]0x2551) -ForegroundColor $(if ($driftCount -gt 0) { "Yellow" } else { "Cyan" })

if ($criticalCount -gt 0) {
    $criticalLine = "  Critical:          $criticalCount  $criticalDetail"
    Write-Host ([char]0x2551 + $criticalLine.PadRight($bannerWidth) + [char]0x2551) -ForegroundColor Red
}
else {
    Write-Host ([char]0x2551 + "  Critical:          0".PadRight($bannerWidth) + [char]0x2551) -ForegroundColor Cyan
}

if ($warningCount -gt 0) {
    $warningLine = "  Warning:           $warningCount  $warningDetail"
    Write-Host ([char]0x2551 + $warningLine.PadRight($bannerWidth) + [char]0x2551) -ForegroundColor Yellow
}
else {
    Write-Host ([char]0x2551 + "  Warning:           0".PadRight($bannerWidth) + [char]0x2551) -ForegroundColor Cyan
}

Write-Host ([char]0x2551 + "  Passed:            $($passedCount.ToString().PadRight($bannerWidth - 22))" + [char]0x2551) -ForegroundColor Green
Write-Host ([char]0x255A + ([string][char]0x2550 * $bannerWidth) + [char]0x255D) -ForegroundColor Cyan
Write-Host ""

# Step 5b: Detail output
if ($driftItems.Count -gt 0) {
    Write-Host "Drift Details:" -ForegroundColor Yellow
    Write-Host ("-" * 60)
    foreach ($drift in $driftItems) {
        $sevName = $severityNames[$drift.Severity]
        $color = switch ($drift.Severity) {
            5 { "Red" }
            4 { "Red" }
            3 { "Yellow" }
            2 { "Yellow" }
            default { "White" }
        }
        Write-Host "  [$sevName] $($drift.PolicyName)" -ForegroundColor $color
        Write-Host "    Type: $($drift.DriftType) | Zone: $($drift.Zone) | Dimension: $($drift.Dimension)"
        Write-Host "    Expected: $($drift.Expected)"
        Write-Host "    Actual:   $($drift.Actual)"
        Write-Host "    $($drift.Description)"
        Write-Host ""
    }
}

# Build results envelope
$resultsEnvelope = @{
    metadata = @{
        checkedAt          = (Get-Date).ToUniversalTime().ToString('o')
        tenantId           = $TenantId
        baselineFile       = $BaselinePath
        severityThreshold  = $SeverityThreshold
        policiesChecked    = $totalPoliciesChecked
        driftDetected      = $driftCount
        criticalCount      = $criticalCount
        warningCount       = $warningCount
        passedCount        = $passedCount
    }
    findings = @($filteredDrifts)
}

# Output results based on format
switch ($OutputFormat) {
    "JSON" {
        $resultsEnvelope | ConvertTo-Json -Depth 10
    }
    "Object" {
        $resultsEnvelope
    }
    # "Table" — already displayed above via Write-Host
}

# Step 6: Write report file if OutputPath specified
if ($OutputPath) {
    $reportDir = Split-Path $OutputPath -Parent
    if ($reportDir -and -not (Test-Path $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
    $resultsEnvelope | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding utf8 -Force
    Write-Host "Drift report written to: $OutputPath" -ForegroundColor Green
}

Write-Host "Drift detection complete." -ForegroundColor Green

# Exit code: 0 = no drift above threshold, 1 = drift detected above threshold.
# `exit` statements terminate the host PowerShell session, which is correct for
# standalone CLI / CI invocation but breaks dot-sourced or module-scoped use.
# Detect dot-sourcing (caller runs `. .\Watch-PolicyDrift.ps1`) and switch to
# return-style flow control to keep the caller's runspace alive.
$invokedDotSourced = $MyInvocation.InvocationName -eq '.'
if ($driftCount -gt 0) {
    if ($invokedDotSourced) { return 1 } else { exit 1 }
}
if ($invokedDotSourced) { return 0 } else { exit 0 }
