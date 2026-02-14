#Requires -Version 7.0
#Requires -Modules @{ ModuleName="ExchangeOnlineManagement"; ModuleVersion="3.7.0" }

<#
.SYNOPSIS
    Runs complete tenant-level audit configuration validation for FSI compliance.

.DESCRIPTION
    Orchestrates execution of three audit configuration validators and produces
    a consolidated validation report for Microsoft 365 tenant audit settings.

    This script executes the following validators:
    1. Test-UnifiedAuditLog - Unified Audit Log enablement with dual validation
    2. Test-MailboxAudit - Mailbox audit on-by-default configuration
    3. Test-PurviewRetention - Retention policy compliance with zone requirements

    Each validator runs in isolation. Failures in one validator do not prevent
    execution of the others, allowing administrators to see the complete compliance
    picture even when some aspects fail.

    Results are displayed to console with color-coded status indicators and
    optionally written to a JSON file for downstream processing (Power Automate,
    compliance dashboards, audit evidence collection).

    This script supports compliance validation for FSI-AgentGov Control 1.7
    (Audit Trail Enablement and Configuration).

.PARAMETER Zone
    Governance zone to validate against. Required.
    Valid values: Zone1 (Personal Productivity), Zone2 (Team Collaboration),
    Zone3 (Enterprise Managed)

    Zone affects retention validation thresholds:
    - Zone1: 180-day minimum retention
    - Zone2: 365-day minimum retention
    - Zone3: 730-day minimum retention (SEC 17a-4 requirement)

.PARAMETER OutputPath
    Optional path for JSON output file. If specified, the complete validation
    results object is written to this file. If omitted, results only display
    to the console.

.PARAMETER SkipCanaryValidation
    Skip the canary event validation step in Unified Audit Log testing.
    Returns result with Confidence="MEDIUM" based only on cmdlet status checks.
    Use when mailbox modifications are not permitted or for faster validation
    when audit is known to be working.

.PARAMETER GracePeriodHours
    Hours to allow for audit ingestion lag after enablement. Default: 24.
    If audit was enabled within this window and canary event is not found,
    the status will be "GracePeriod" instead of "Warning".

.PARAMETER CanaryWaitSeconds
    Seconds to wait after generating canary event before searching for it.
    Default: 300 (5 minutes). Increase if audit ingestion is consistently slow
    in your environment.

.PARAMETER Interactive
    Use interactive browser-based authentication instead of service principal.

.PARAMETER TenantId
    Azure AD tenant ID. Required for service principal authentication.

.PARAMETER ClientId
    Azure AD application (client) ID. Required for service principal authentication.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication.

.PARAMETER CertificateFilePath
    Path to certificate file (.pfx) for service principal authentication.

.EXAMPLE
    .\Invoke-TenantAuditValidation.ps1 -Zone Zone3 -Interactive

    Runs full validation suite for Enterprise Managed zone (730-day retention
    requirement) using interactive authentication. Includes canary event validation
    for high-confidence Unified Audit Log verification.

.EXAMPLE
    .\Invoke-TenantAuditValidation.ps1 -Zone Zone2 -OutputPath ".\results.json" -SkipCanaryValidation -Interactive

    Runs validation for Team Collaboration zone (365-day retention), skips
    canary validation for faster execution, and writes results to JSON file.

.EXAMPLE
    .\Invoke-TenantAuditValidation.ps1 -Zone Zone3 -TenantId "contoso.onmicrosoft.com" -ClientId "12345..." -CertificateThumbprint "ABCDEF..."

    Runs full validation suite using service principal authentication.

.OUTPUTS
    PSCustomObject with properties:
    - Timestamp: ISO 8601 timestamp
    - Zone: Zone1 | Zone2 | Zone3
    - Validators: Hashtable with keys UnifiedAuditLog, MailboxAudit, PurviewRetention
    - OverallStatus: Passed | Failed | Warning
    - Reason: Summary of overall status

.NOTES
    Version: 1.0.0
    Requires:
    - ExchangeOnlineManagement module v3.7.0 or later
    - PowerShell 7.0 or later
    - Exchange Online Administrator or Global Administrator role
    - Compliance Administrator role (for Purview Retention validation)
    - For service principal: Application with Exchange.ManageAsApp and Compliance.ManageAsApp permissions

    Regulatory context:
    This orchestrator supports compliance validation for:
    - FINRA Rule 4511 (audit trail retention)
    - FINRA Rule 25-07 (AI agent communications supervision)
    - SEC Rule 17a-4 (2-year minimum communications retention)
    - GLBA 501(b) (audit logging requirements)
    - SOX Section 302/404 (internal controls)

    License requirements:
    - Microsoft 365 E5 or E5 Compliance license for advanced audit features
    - Basic audit features available in all M365 commercial licenses

    Performance considerations:
    - Full validation (with canary) takes 5-10 minutes
    - Use -SkipCanaryValidation for faster checks (~1-2 minutes)
    - Each validator runs sequentially but with independent error handling
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Zone1", "Zone2", "Zone3")]
    [string]$Zone,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath,

    [Parameter(Mandatory = $false)]
    [switch]$SkipCanaryValidation,

    [Parameter(Mandatory = $false)]
    [int]$GracePeriodHours = 24,

    [Parameter(Mandatory = $false)]
    [int]$CanaryWaitSeconds = 300,

    [Parameter(Mandatory = $false)]
    [switch]$Interactive,

    [Parameter(Mandatory = $false)]
    [string]$TenantId,

    [Parameter(Mandatory = $false)]
    [string]$ClientId,

    [Parameter(Mandatory = $false)]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $false)]
    [string]$CertificateFilePath
)

$ErrorActionPreference = "Stop"

#region Initialization

Write-Host "`n╔══════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  M365 Tenant Audit Configuration Validation     ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan
Write-Host "║  FSI-AgentGov Control 1.7                        ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

# Dot-source all validator scripts
$scriptRoot = $PSScriptRoot
try {
    . "$scriptRoot\Test-UnifiedAuditLog.ps1"
    . "$scriptRoot\Test-MailboxAudit.ps1"
    . "$scriptRoot\Test-PurviewRetention.ps1"
}
catch {
    Write-Error "Failed to load validator scripts: $($_.Exception.Message)"
    throw
}

# Build common authentication parameter hashtable
$authParams = @{}
if ($Interactive) { $authParams.Interactive = $true }
if ($TenantId) { $authParams.TenantId = $TenantId }
if ($ClientId) { $authParams.ClientId = $ClientId }
if ($CertificateThumbprint) { $authParams.CertificateThumbprint = $CertificateThumbprint }
if ($CertificateFilePath) { $authParams.CertificateFilePath = $CertificateFilePath }

# Initialize results object
$results = @{
    Timestamp = (Get-Date -Format "o")
    Zone = $Zone
    Validators = @{}
    OverallStatus = "Unknown"
    Reason = ""
}

# Map zone to friendly name for display
$zoneName = switch ($Zone) {
    "Zone1" { "Personal Productivity" }
    "Zone2" { "Team Collaboration" }
    "Zone3" { "Enterprise Managed" }
}

Write-Host "Validation Target: $Zone ($zoneName)" -ForegroundColor Cyan
Write-Host "Timestamp: $($results.Timestamp)" -ForegroundColor Cyan
Write-Host ""

#endregion

#region Validator 1: Unified Audit Log

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  VALIDATOR 1: Unified Audit Log                   " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

try {
    # Build parameters for UAL validator
    $ualParams = $authParams.Clone()
    if ($SkipCanaryValidation) {
        $ualParams.SkipCanaryValidation = $true
        Write-Host "Canary validation: SKIPPED (faster execution)" -ForegroundColor Yellow
    }
    $ualParams.GracePeriodHours = $GracePeriodHours
    $ualParams.CanaryWaitSeconds = $CanaryWaitSeconds

    # Execute validator
    $results.Validators.UnifiedAuditLog = Test-UnifiedAuditLog @ualParams

    # Display result
    $status = $results.Validators.UnifiedAuditLog.OverallStatus
    $confidence = $results.Validators.UnifiedAuditLog.Confidence
    $color = switch ($status) {
        "Passed" { "Green" }
        "Failed" { "Red" }
        "Warning" { "Yellow" }
        "GracePeriod" { "Yellow" }
        default { "Gray" }
    }
    Write-Host "`nResult: $status ($confidence confidence)" -ForegroundColor $color
    Write-Host "Reason: $($results.Validators.UnifiedAuditLog.Reason)" -ForegroundColor $color
}
catch {
    $results.Validators.UnifiedAuditLog = @{
        Status = "Error"
        Reason = $_.Exception.Message
        Timestamp = Get-Date -Format "o"
    }
    Write-Warning "Unified Audit Log validation failed: $($_.Exception.Message)"
    Write-Host "Result: ERROR" -ForegroundColor Red
}

Write-Host ""

#endregion

#region Validator 2: Mailbox Audit

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  VALIDATOR 2: Mailbox Audit                       " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

try {
    # Execute validator
    $results.Validators.MailboxAudit = Test-MailboxAudit @authParams

    # Display result
    $status = $results.Validators.MailboxAudit.OverallStatus
    $confidence = $results.Validators.MailboxAudit.Confidence
    $color = switch ($status) {
        "Passed" { "Green" }
        "Failed" { "Red" }
        "Warning" { "Yellow" }
        default { "Gray" }
    }
    Write-Host "`nResult: $status ($confidence confidence)" -ForegroundColor $color
    Write-Host "Reason: $($results.Validators.MailboxAudit.Reason)" -ForegroundColor $color
}
catch {
    $results.Validators.MailboxAudit = @{
        Status = "Error"
        Reason = $_.Exception.Message
        Timestamp = Get-Date -Format "o"
    }
    Write-Warning "Mailbox Audit validation failed: $($_.Exception.Message)"
    Write-Host "Result: ERROR" -ForegroundColor Red
}

Write-Host ""

#endregion

#region Validator 3: Purview Retention

Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  VALIDATOR 3: Purview Retention                   " -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

try {
    # Build parameters for Purview validator (needs Zone parameter)
    $purviewParams = $authParams.Clone()
    $purviewParams.Zone = $Zone

    # Execute validator
    $results.Validators.PurviewRetention = Test-PurviewRetention @purviewParams

    # Display result
    $status = $results.Validators.PurviewRetention.OverallStatus
    $confidence = $results.Validators.PurviewRetention.Confidence
    $gapCount = if ($results.Validators.PurviewRetention.Gaps) {
        $results.Validators.PurviewRetention.Gaps.Count
    } else { 0 }

    $color = switch ($status) {
        "Passed" { "Green" }
        "Failed" { "Red" }
        "Warning" { "Yellow" }
        default { "Gray" }
    }
    Write-Host "`nResult: $status ($confidence confidence)" -ForegroundColor $color
    Write-Host "Reason: $($results.Validators.PurviewRetention.Reason)" -ForegroundColor $color
    if ($gapCount -gt 0) {
        Write-Host "Coverage gaps: $gapCount record type(s)" -ForegroundColor Yellow
    }
}
catch {
    $results.Validators.PurviewRetention = @{
        Status = "Error"
        Reason = $_.Exception.Message
        Timestamp = Get-Date -Format "o"
    }
    Write-Warning "Purview Retention validation failed: $($_.Exception.Message)"
    Write-Host "Result: ERROR" -ForegroundColor Red
}

Write-Host ""

#endregion

#region Compute Overall Status

# Determine overall status based on individual validator results
$statuses = @()
foreach ($validatorName in $results.Validators.Keys) {
    $validator = $results.Validators[$validatorName]
    $validatorStatus = if ($validator.OverallStatus) {
        $validator.OverallStatus
    } elseif ($validator.Status) {
        $validator.Status
    } else {
        "Unknown"
    }
    $statuses += $validatorStatus
}

# Priority: Error/Failed > Warning/GracePeriod > Passed
if ($statuses -contains "Error" -or $statuses -contains "Failed") {
    $results.OverallStatus = "Failed"
    $results.Reason = "One or more validators failed. Review individual validator results."
}
elseif ($statuses -contains "Warning" -or $statuses -contains "GracePeriod") {
    $results.OverallStatus = "Warning"
    $results.Reason = "All validators passed, but warnings detected. Review individual validator results."
}
elseif ($statuses -match "Passed" -and $statuses.Count -eq 3) {
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
Write-Host "║       Tenant Audit Configuration Report         ║" -ForegroundColor Cyan
Write-Host "╠══════════════════════════════════════════════════╣" -ForegroundColor Cyan

# Zone and timestamp
Write-Host ("║ Zone:           {0,-33}║" -f "$Zone ($zoneName)") -ForegroundColor Cyan
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
foreach ($validatorName in @("UnifiedAuditLog", "MailboxAudit", "PurviewRetention")) {
    if ($results.Validators.ContainsKey($validatorName)) {
        $validator = $results.Validators[$validatorName]
        $validatorStatus = if ($validator.OverallStatus) {
            $validator.OverallStatus
        } elseif ($validator.Status) {
            $validator.Status
        } else {
            "Unknown"
        }
        $validatorConfidence = if ($validator.Confidence) {
            "($($validator.Confidence) confidence)"
        } else {
            ""
        }

        # Format display name
        $displayName = switch ($validatorName) {
            "UnifiedAuditLog" { "Unified Audit Log" }
            "MailboxAudit" { "Mailbox Audit" }
            "PurviewRetention" { "Purview Retention" }
        }

        $line = "║ {0,-21}" -f "${displayName}:"
        Write-Host $line -NoNewline -ForegroundColor Cyan

        $statusColor = switch ($validatorStatus) {
            "Passed" { "Green" }
            "Failed" { "Red" }
            "Warning" { "Yellow" }
            "GracePeriod" { "Yellow" }
            "Error" { "Red" }
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
