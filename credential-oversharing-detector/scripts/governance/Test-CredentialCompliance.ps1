#Requires -Version 7.0
#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    Orchestrates a credential scan and evaluates zone compliance.

.DESCRIPTION
    Compliance orchestrator for the Credential Oversharing Detector (COD)
    solution. Invokes Invoke-CredentialScan.ps1 to discover credential
    configurations, evaluates results against zone-based policies from
    Get-ExpectedCredentialPolicy.ps1, and produces a compliance report.

    Workflow:
    1. Imports and calls Invoke-CredentialScan.ps1 for environment scanning
    2. Loads zone credential policies from zone-credential-policy.json
    3. Compares scan results against zone-specific thresholds
    4. Computes summary: total agents, compliant count, violations by severity
    5. Optionally persists results to Dataverse
    6. Outputs compliance report in requested format

    This script is designed for scheduled automation (Azure Automation,
    Logic Apps) and interactive compliance checks.

.PARAMETER OutputFormat
    Output format: Table (default), JSON, or Object.
    - Table: Formatted table with color-coded severity
    - JSON: Machine-readable JSON for evidence export
    - Object: Raw PSCustomObject for pipeline consumption

.PARAMETER ExcludeSandbox
    Exclude sandbox-type environments from the scan.

.PARAMETER IncludeCompliant
    Include compliant agents in output. Default: violations only.

.PARAMETER DataverseUrl
    Dataverse organization URL (e.g., https://org.crm.dynamics.com).
    Required when -PersistResults is specified.

.PARAMETER DataverseToken
    Pre-obtained access token for Dataverse authentication. If not provided,
    uses Az.Accounts module for token acquisition.

.PARAMETER PersistResults
    When specified with -DataverseUrl, writes compliance results to
    Dataverse for dashboard reporting and evidence collection.

.PARAMETER BaselinePath
    Path to zone-credential-policy.json. Defaults to
    ../templates/zone-credential-policy.json relative to script location.

.EXAMPLE
    .\Test-CredentialCompliance.ps1

    Runs a credential compliance scan of all environments with default
    settings and table output.

.EXAMPLE
    .\Test-CredentialCompliance.ps1 -OutputFormat JSON -ExcludeSandbox

    Scans non-sandbox environments with JSON output.

.EXAMPLE
    .\Test-CredentialCompliance.ps1 -DataverseUrl "https://org.crm.dynamics.com" `
        -PersistResults -IncludeCompliant

    Full compliance scan with Dataverse persistence including compliant agents.

.OUTPUTS
    PSCustomObject with properties:
    - OverallStatus: Compliant, ViolationsDetected, or Error
    - ScanRunId: GUID from the underlying scan
    - TotalAgents: Number of agents evaluated
    - CompliantAgents: Number of compliant agents
    - TotalViolations: Number of violations detected
    - ViolationsBySeverity: Hashtable of severity counts
    - ZoneSummary: Per-zone compliance breakdown

.NOTES
    Version: 1.0.1
    Solution: Credential Oversharing Detector (COD)
    Controls: 1.14, 1.4, 1.18
    Regulations: FINRA Rule 4511, SEC 17a-4, SOX 302/404, GLBA 501(b)

    Part of FSI Agent Governance Framework
#>

[CmdletBinding()]
param(
    [Parameter()]
    [ValidateSet('Table', 'JSON', 'Object')]
    [string]$OutputFormat = 'Table',

    [Parameter()]
    [switch]$ExcludeSandbox,

    [Parameter()]
    [switch]$IncludeCompliant,

    [Parameter()]
    [string]$DataverseUrl,

    [Parameter()]
    [string]$DataverseToken,

    [Parameter()]
    [switch]$PersistResults,

    [Parameter()]
    [string]$BaselinePath
)

$ErrorActionPreference = "Stop"

#region Initialization

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Credential Oversharing Compliance Test          ║" -ForegroundColor Cyan
Write-Host "║  FSI Agent Governance Framework                  ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$scriptRoot = $PSScriptRoot

# Resolve dependency script paths
$scanScriptPath = Join-Path $scriptRoot "Invoke-CredentialScan.ps1"
$policyScriptPath = Join-Path $scriptRoot "Get-ExpectedCredentialPolicy.ps1"

if (-not (Test-Path $scanScriptPath)) {
    throw "Invoke-CredentialScan.ps1 not found at $scanScriptPath"
}
if (-not (Test-Path $policyScriptPath)) {
    throw "Get-ExpectedCredentialPolicy.ps1 not found at $policyScriptPath"
}

# Resolve baseline policy path
if (-not $BaselinePath) {
    $BaselinePath = Join-Path (Split-Path (Split-Path $scriptRoot -Parent) -Parent) "templates" "zone-credential-policy.json"
}

if (-not (Test-Path $BaselinePath)) {
    Write-Warning "Zone credential policy not found at $BaselinePath. Using script-level defaults."
}
else {
    Write-Host "  Policy baseline: $BaselinePath" -ForegroundColor Gray
}

#endregion

#region Execute Credential Scan

Write-Host "`n  Running credential scan..." -ForegroundColor Cyan

$scanParams = @{
    OutputFormat     = 'Object'
    IncludeCompliant = $IncludeCompliant.IsPresent
}

if ($ExcludeSandbox) {
    $scanParams.ExcludeSandbox = $true
}

if ($DataverseUrl) {
    $scanParams.DataverseUrl = $DataverseUrl
}

try {
    $scanResult = & $scanScriptPath @scanParams
}
catch {
    Write-Host "  ERROR: Credential scan failed - $($_.Exception.Message)" -ForegroundColor Red

    $errorResult = [PSCustomObject]@{
        OverallStatus      = "Error"
        ScanRunId          = $null
        TotalAgents        = 0
        CompliantAgents    = 0
        TotalViolations    = 0
        ViolationsBySeverity = @{}
        ZoneSummary        = @()
        ErrorMessage       = $_.Exception.Message
    }

    if ($OutputFormat -eq 'JSON') {
        $errorResult | ConvertTo-Json -Depth 5
    }

    return $errorResult
}

Write-Host "  Scan completed: $($scanResult.TotalAgents) agents, $($scanResult.TotalViolations) violations" -ForegroundColor Gray

#endregion

#region Evaluate Zone Compliance

Write-Host "`n  Evaluating zone compliance..." -ForegroundColor Cyan

$zoneSummary = [System.Collections.ArrayList]::new()
$zones = @('Zone1', 'Zone2', 'Zone3', 'Unknown')

foreach ($zoneName in $zones) {
    $zoneViolations = @($scanResult.Violations | Where-Object { $_.Zone -eq $zoneName })
    $zoneAgentIds = @($scanResult.Violations | Where-Object { $_.Zone -eq $zoneName } |
        Select-Object -ExpandProperty AgentId -Unique)

    # Load zone policy
    $policy = $null
    try {
        $policy = & $policyScriptPath -Zone $zoneName
    }
    catch {
        Write-Host "    Warning: Could not load policy for $zoneName" -ForegroundColor Yellow
    }

    $zoneEntry = [PSCustomObject]@{
        Zone               = $zoneName
        TotalViolations    = $zoneViolations.Count
        AffectedAgents     = $zoneAgentIds.Count
        Critical           = @($zoneViolations | Where-Object { $_.Severity -eq "Critical" }).Count
        High               = @($zoneViolations | Where-Object { $_.Severity -eq "High" }).Count
        Medium             = @($zoneViolations | Where-Object { $_.Severity -eq "Medium" }).Count
        Low                = @($zoneViolations | Where-Object { $_.Severity -eq "Low" }).Count
        Informational      = @($zoneViolations | Where-Object { $_.Severity -eq "Informational" }).Count
        AutoRemediate      = if ($policy) { $policy.AutoRemediate } else { $false }
        RegulatoryContext   = if ($policy) { $policy.RegulatoryContext } else { @{} }
    }

    if ($zoneViolations.Count -gt 0 -or $IncludeCompliant) {
        [void]$zoneSummary.Add($zoneEntry)
    }
}

$totalCompliant = $scanResult.TotalAgents - @($scanResult.Violations |
    Select-Object -ExpandProperty AgentId -Unique).Count
$overallStatus = if ($scanResult.TotalViolations -eq 0) { "Compliant" } else { "ViolationsDetected" }

#endregion

#region Persist Compliance Results

if ($PersistResults -and $DataverseUrl) {
    Write-Host "`n  Persisting compliance results..." -ForegroundColor Cyan

    # Acquire Dataverse token if not provided
    if (-not $DataverseToken) {
        if (-not (Get-AzContext)) {
            Connect-AzAccount | Out-Null
        }
        $tokenResult = Get-AzAccessToken -ResourceUrl $DataverseUrl -AsSecureString
        $DataverseToken = $tokenResult.Token | ConvertFrom-SecureString -AsPlainText
    }

    $dvHeaders = @{
        "Authorization"    = "Bearer $DataverseToken"
        "Content-Type"     = "application/json"
        "OData-Version"    = "4.0"
        "OData-MaxVersion" = "4.0"
        "Accept"           = "application/json"
    }

    $dvApiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"

    $complianceRecord = @{
        fsi_scanid            = "COD-Compliance-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        fsi_scanrunid         = $scanResult.ScanRunId
        fsi_scanstatus        = if ($scanResult.TotalViolations -eq 0) { 100000000 } else { 100000001 }
        fsi_overallstatus     = $overallStatus
        fsi_agentsscanned     = $scanResult.TotalAgents
        fsi_compliantagents   = $totalCompliant
        fsi_violationsfound   = $scanResult.TotalViolations
        fsi_scanstartedat     = $scanResult.ScanTimestamp
        fsi_zonesummary       = ($zoneSummary | ConvertTo-Json -Depth 5 -Compress)
    }

    try {
        Invoke-RestMethod -Uri "$dvApiBase/fsi_credentialscans" -Headers $dvHeaders `
            -Method Post -Body ($complianceRecord | ConvertTo-Json -Depth 5)
        Write-Host "    Compliance record persisted" -ForegroundColor Green
    }
    catch {
        Write-Host "    Warning: Failed to persist compliance record - $($_.Exception.Message)" -ForegroundColor Yellow
    }
}

#endregion

#region Output Compliance Report

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  Compliance Report                               ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan

$statusColor = if ($overallStatus -eq "Compliant") { "Green" } else { "Red" }
Write-Host ("║ Overall Status:   {0,-30}║" -f $overallStatus) -ForegroundColor $statusColor
Write-Host ("║ Scan Run ID:      {0,-30}║" -f $scanResult.ScanRunId.Substring(0, [Math]::Min(30, $scanResult.ScanRunId.Length))) -ForegroundColor Cyan
Write-Host ("║ Total Agents:     {0,-30}║" -f $scanResult.TotalAgents) -ForegroundColor Cyan
Write-Host ("║ Compliant:        {0,-30}║" -f $totalCompliant) -ForegroundColor Cyan
Write-Host ("║ Violations:       {0,-30}║" -f $scanResult.TotalViolations) -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan

$complianceResult = [PSCustomObject]@{
    OverallStatus        = $overallStatus
    ScanRunId            = $scanResult.ScanRunId
    TotalAgents          = $scanResult.TotalAgents
    CompliantAgents      = $totalCompliant
    TotalViolations      = $scanResult.TotalViolations
    ViolationsBySeverity = $scanResult.ViolationsBySeverity
    ZoneSummary          = @($zoneSummary)
}

switch ($OutputFormat) {
    'Table' {
        if ($zoneSummary.Count -gt 0) {
            Write-Host "`n  Zone Summary:" -ForegroundColor Cyan
            $zoneSummary | Format-Table -Property Zone, TotalViolations, AffectedAgents, Critical, High, Medium, Low -AutoSize
        }

        if ($scanResult.TotalViolations -gt 0) {
            Write-Host "  Violations:" -ForegroundColor Yellow
            $scanResult.Violations | Format-Table -Property AgentName, EnvironmentName, Zone, ViolationType, Severity -AutoSize -Wrap
        }
    }
    'JSON' {
        $complianceResult | ConvertTo-Json -Depth 10
    }
    'Object' {
        # Return raw object (emitted below)
    }
}

Write-Host "`n  Compliance Test: COMPLETE" -ForegroundColor Green

return $complianceResult

#endregion
