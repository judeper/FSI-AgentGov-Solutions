#Requires -Version 7.2
#Requires -Modules @{ ModuleName="ExchangeOnlineManagement"; ModuleVersion="3.0.0"; MaximumVersion="3.9.2" }

<#
.SYNOPSIS
    Validates M365 Unified Audit Log configuration using dual validation strategy.

.DESCRIPTION
    Performs comprehensive validation of Microsoft 365 Unified Audit Log enablement
    by combining cmdlet status checks with canary event retrieval. This dual validation
    approach prevents false positives that can occur when audit is enabled at the
    configuration level but events are not being ingested or retrievable.

    Validation checks:
    1. UnifiedAuditLogIngestionEnabled status via Get-AdminAuditLogConfig
    2. AdminAuditLogEnabled status (Exchange admin operations audit)
    3. Canary event generation and retrieval via Search-UnifiedAuditLog

    The script handles audit ingestion lag periods (up to 24 hours) with a configurable
    grace period to avoid false positives for recently-enabled tenants.

    IMPORTANT: This script uses Exchange Online PowerShell for Get-AdminAuditLogConfig.
    The Security & Compliance PowerShell version always returns False for
    UnifiedAuditLogIngestionEnabled, which would cause false negatives.

.PARAMETER SkipCanaryValidation
    Skip the canary event validation step. Returns result with Confidence="Medium"
    based only on cmdlet status checks. Use only for read-only assessments where
    mailbox modifications are not permitted.

.PARAMETER GracePeriodHours
    Hours to allow for audit ingestion lag after enablement. Default: 24.
    If audit was enabled within this window and canary event is not found,
    the result status will be "GracePeriod" instead of "Warning".

.PARAMETER CanaryWaitSeconds
    Seconds to wait after generating canary event before searching for it.
    Default: 300 (5 minutes). Increase if audit ingestion is consistently slow.

.PARAMETER Interactive
    Use interactive browser-based authentication instead of service principal.

.PARAMETER TenantId
    Microsoft Entra ID tenant ID. Required for service principal authentication.

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID. Required for service principal authentication.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication.

.PARAMETER CertificateFilePath
    Path to certificate file (.pfx) for service principal authentication.

.PARAMETER CanaryMailboxIdentity
    Mailbox identity used for canary event generation (UPN, email, alias, or shared mailbox).
    Required and recommended for service-principal canary validation; interactive runs may omit it.

.EXAMPLE
    .\Test-UnifiedAuditLog.ps1 -Interactive
    Validates Unified Audit Log using interactive authentication and full dual validation.

.EXAMPLE
    .\Test-UnifiedAuditLog.ps1 -TenantId "contoso.onmicrosoft.com" -ClientId "12345..." -CertificateThumbprint "ABCDEF..."
    Validates using service principal authentication.

.EXAMPLE
    .\Test-UnifiedAuditLog.ps1 -Interactive -SkipCanaryValidation
    Validates using only cmdlet status checks (no canary event).

.EXAMPLE
    .\Test-UnifiedAuditLog.ps1 -Interactive -CanaryWaitSeconds 600
    Validates with 10-minute wait after canary generation (for slow audit ingestion).

.OUTPUTS
    PSCustomObject with properties:
    - Timestamp: ISO 8601 timestamp
    - ValidationType: "UnifiedAuditLog"
    - Checks: Array of check results
    - OverallStatus: Passed | Failed | Warning | GracePeriod
    - Confidence: High | Medium
    - Reason: Summary explanation

.NOTES
    Version: 1.0.4
    Requires:
    - ExchangeOnlineManagement module v3.0.0 or later
    - Exchange Online Admin or Entra Global Admin role
    - For service principal: Application with Exchange.ManageAsApp permission

    Regulatory context:
    This script supports compliance validation for:
    - FINRA Rule 4511 (audit trail retention)
    - SEC Rule 17a-4 (records retention)
    - GLBA 501(b) (audit logging requirements)

    Performance considerations:
    - Full validation (with canary) takes 5-10 minutes due to audit ingestion lag
    - Use -SkipCanaryValidation for faster checks if audit is known to be working
    - Canary events use CustomAttribute15 (non-disruptive to mail flow)
#>

[CmdletBinding()]
param(
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
    [string]$CertificateFilePath,

    [Parameter(Mandatory = $false)]
    [string]$CanaryMailboxIdentity
)

$ErrorActionPreference = "Stop"

#region Dot-source private helpers

$dotSourceSafeVars = @{
    SkipCanaryValidation  = $SkipCanaryValidation
    GracePeriodHours      = $GracePeriodHours
    CanaryWaitSeconds     = $CanaryWaitSeconds
    Interactive           = $Interactive
    TenantId              = $TenantId
    ClientId              = $ClientId
    CertificateThumbprint = $CertificateThumbprint
    CertificateFilePath   = $CertificateFilePath
    CanaryMailboxIdentity = $CanaryMailboxIdentity
}

$privatePath = Join-Path $PSScriptRoot 'private'
$requiredHelpers = @(
    'Connect-AuditServices.ps1',
    'New-CanaryEvent.ps1'
)
foreach ($helper in $requiredHelpers) {
    $helperPath = Join-Path $privatePath $helper
    if (-not (Test-Path $helperPath)) {
        throw "Required helper script not found: $helperPath. Ensure the solution is installed correctly."
    }
    . $helperPath
}
foreach ($name in $dotSourceSafeVars.Keys) {
    Set-Variable -Name $name -Value $dotSourceSafeVars[$name] -Scope Local
}

#endregion

#region Main validation function

function Test-UnifiedAuditLog {
    [CmdletBinding()]
    param(
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
        [string]$CertificateFilePath,

        [Parameter(Mandatory = $false)]
        [string]$CanaryMailboxIdentity
    )

    $checks = @()
    $overallStatus = "Unknown"
    $confidence = "High"
    $reason = ""

    try {
        Write-Host "`n=== Unified Audit Log Validation ===" -ForegroundColor Cyan
        Write-Host "Dual validation strategy: Cmdlet status + Canary event retrieval`n" -ForegroundColor Gray

        #region Step 1: Connect to Exchange Online

        Write-Host "[Step 1/4] Connecting to Exchange Online PowerShell..." -ForegroundColor Yellow

        $connectParams = @{
            ExchangeOnly = $true
        }
        if ($Interactive) { $connectParams.Interactive = $true }
        if ($TenantId) { $connectParams.TenantId = $TenantId }
        if ($ClientId) { $connectParams.ClientId = $ClientId }
        if ($CertificateThumbprint) { $connectParams.CertificateThumbprint = $CertificateThumbprint }
        if ($CertificateFilePath) { $connectParams.CertificateFilePath = $CertificateFilePath }

        Connect-AuditServices @connectParams -ErrorAction Stop

        Write-Host "Connection established.`n" -ForegroundColor Green

        #endregion

        #region Step 2: Check Unified Audit Log Ingestion

        Write-Host "[Step 2/4] Checking Unified Audit Log configuration..." -ForegroundColor Yellow

        $config = Get-AdminAuditLogConfig -ErrorAction Stop

        # Check UnifiedAuditLogIngestionEnabled
        $unifiedAuditEnabled = $config.UnifiedAuditLogIngestionEnabled

        $checks += @{
            Name = "UnifiedAuditLogIngestionEnabled"
            Status = if ($unifiedAuditEnabled) { "Passed" } else { "Failed" }
            Value = $unifiedAuditEnabled
            Source = "Get-AdminAuditLogConfig (Exchange Online)"
        }

        if (-not $unifiedAuditEnabled) {
            Write-Host "FAILED: UnifiedAuditLogIngestionEnabled = False" -ForegroundColor Red
            Write-Host "Audit log ingestion is disabled. Enable in the Microsoft Purview portal or Exchange Online PowerShell.`n" -ForegroundColor Red

            $overallStatus = "Failed"
            $confidence = "High"
            $reason = "UnifiedAuditLogIngestionEnabled is False. Audit log ingestion is disabled."

            return [PSCustomObject]@{
                Timestamp = Get-Date -Format "o"
                ValidationType = "UnifiedAuditLog"
                Checks = $checks
                OverallStatus = $overallStatus
                Confidence = $confidence
                Reason = $reason
                RawValue = "UnifiedAuditLogIngestionEnabled=$unifiedAuditEnabled"
            }
        }

        Write-Host "PASSED: UnifiedAuditLogIngestionEnabled = True" -ForegroundColor Green

        #endregion

        #region Step 3: Check Admin Audit Log

        Write-Host "[Step 3/4] Checking admin audit log configuration..." -ForegroundColor Yellow

        $adminAuditEnabled = $config.AdminAuditLogEnabled

        $checks += @{
            Name = "AdminAuditLogEnabled"
            Status = if ($adminAuditEnabled) { "Passed" } else { "Failed" }
            Value = $adminAuditEnabled
            Source = "Get-AdminAuditLogConfig (Exchange Online)"
        }

        if (-not $adminAuditEnabled) {
            Write-Host "WARNING: AdminAuditLogEnabled = False" -ForegroundColor Yellow
            Write-Host "Exchange admin audit logging is disabled. This is a separate setting.`n" -ForegroundColor Yellow
        }
        else {
            Write-Host "PASSED: AdminAuditLogEnabled = True`n" -ForegroundColor Green
        }

        #endregion

        #region Step 4: Dual validation via canary event

        if ($SkipCanaryValidation) {
            Write-Host "[Step 4/4] Canary validation SKIPPED (as requested)" -ForegroundColor Yellow
            Write-Host "Result based on cmdlet status only.`n" -ForegroundColor Gray

            $checks += @{
                Name = "CanaryEventValidation"
                Status = "Skipped"
                CanaryId = $null
                WaitSeconds = $null
                Reason = "SkipCanaryValidation flag specified"
            }

            $overallStatus = "Passed"
            $confidence = "Medium"
            $reason = "Cmdlet reports enabled (UnifiedAuditLogIngestionEnabled=True). Canary validation skipped."
        }
        else {
            Write-Host "[Step 4/4] Performing canary event validation..." -ForegroundColor Yellow
            $isServicePrincipalAuth = (-not $Interactive) -and $ClientId -and ($CertificateThumbprint -or $CertificateFilePath)
            $hasCanaryMailboxIdentity = -not [string]::IsNullOrWhiteSpace($CanaryMailboxIdentity)

            if ($isServicePrincipalAuth -and -not $hasCanaryMailboxIdentity) {
                $canaryReason = "CanaryMailboxIdentity is required for service-principal canary validation. Provide a real mailbox identity (user or shared mailbox)."
                Write-Host "WARNING: $canaryReason`n" -ForegroundColor Yellow

                $checks += @{
                    Name = "CanaryEventValidation"
                    Status = "Warning"
                    CanaryId = $null
                    WaitSeconds = 0
                    Reason = $canaryReason
                }

                $overallStatus = "Warning"
                $confidence = "Medium"
                $reason = "Cmdlet reports enabled, but canary validation needs an explicit mailbox identity for service-principal authentication."
            }
            else {
                # Generate canary event
                Write-Host "Generating canary event..." -ForegroundColor Cyan
                $canaryParams = @{}
                if ($hasCanaryMailboxIdentity) { $canaryParams.MailboxIdentity = $CanaryMailboxIdentity }
                $canary = New-CanaryEvent @canaryParams -ErrorAction Stop

                if ($canary.Status -ne "Success") {
                    Write-Host "WARNING: Canary event generation failed: $($canary.ErrorMessage)" -ForegroundColor Yellow

                    $checks += @{
                        Name = "CanaryEventValidation"
                        Status = "Warning"
                        CanaryId = $canary.CanaryId
                        WaitSeconds = 0
                        Reason = "Canary generation failed: $($canary.ErrorMessage)"
                    }

                    $overallStatus = "Warning"
                    $confidence = "Medium"
                    $reason = "Cmdlet reports enabled but canary generation failed. Manual verification recommended."
                }
                else {
                    Write-Host "Canary event generated successfully." -ForegroundColor Green
                    Write-Host "Canary ID: $($canary.CanaryId)" -ForegroundColor Gray
                    Write-Host "Waiting $CanaryWaitSeconds seconds for audit ingestion..." -ForegroundColor Cyan

                    # Wait for audit ingestion
                    Start-Sleep -Seconds $CanaryWaitSeconds

                    # Search for canary event
                    Write-Host "Searching for canary event in Unified Audit Log..." -ForegroundColor Cyan

                    $startDate = (Get-Date).AddHours(-1)
                    $endDate = Get-Date

                    $canaryEvent = Search-UnifiedAuditLog `
                        -StartDate $startDate `
                        -EndDate $endDate `
                        -FreeText $canary.CanaryId `
                        -ResultSize 1 `
                        -ErrorAction SilentlyContinue

                    if ($canaryEvent) {
                        Write-Host "SUCCESS: Canary event found in Unified Audit Log!" -ForegroundColor Green
                        Write-Host "Audit log ingestion is confirmed working.`n" -ForegroundColor Green

                        $checks += @{
                            Name = "CanaryEventValidation"
                            Status = "Passed"
                            CanaryId = $canary.CanaryId
                            WaitSeconds = $CanaryWaitSeconds
                            Reason = "Canary event successfully retrieved"
                        }

                        $overallStatus = "Passed"
                        $confidence = "High"
                        $reason = "Cmdlet enabled AND canary event retrieved. Audit log ingestion confirmed working."
                    }
                    else {
                        # Canary not found - check if we're in grace period
                        Write-Host "Canary event not found after $CanaryWaitSeconds seconds." -ForegroundColor Yellow

                        # Check if audit was recently enabled (within grace period)
                        # Look for any recent audit events to determine if we're in grace period
                        Write-Host "Checking for recent audit activity (grace period check)..." -ForegroundColor Cyan

                        $recentEvents = Search-UnifiedAuditLog `
                            -StartDate (Get-Date).AddHours(-$GracePeriodHours) `
                            -EndDate (Get-Date) `
                            -ResultSize 1 `
                            -ErrorAction SilentlyContinue

                        if (-not $recentEvents) {
                            # No events in grace period window - likely newly enabled
                            Write-Host "No audit events found in past $GracePeriodHours hours." -ForegroundColor Yellow
                            Write-Host "Audit may have been recently enabled (within grace period).`n" -ForegroundColor Yellow

                            $checks += @{
                                Name = "CanaryEventValidation"
                                Status = "GracePeriod"
                                CanaryId = $canary.CanaryId
                                WaitSeconds = $CanaryWaitSeconds
                                Reason = "No events found within $GracePeriodHours-hour grace period. Audit may be newly enabled."
                            }

                            $overallStatus = "GracePeriod"
                            $confidence = "Medium"
                            $reason = "Cmdlet reports enabled but no audit events in past $GracePeriodHours hours. Audit ingestion lag expected for newly-enabled tenants."
                        }
                        else {
                            # Events exist but canary not found - possible ingestion issue
                            Write-Host "Other audit events found, but canary event not retrieved." -ForegroundColor Yellow
                            Write-Host "Possible audit ingestion delay or configuration issue.`n" -ForegroundColor Yellow

                            $checks += @{
                                Name = "CanaryEventValidation"
                                Status = "Warning"
                                CanaryId = $canary.CanaryId
                                WaitSeconds = $CanaryWaitSeconds
                                Reason = "Cmdlet reports enabled and other events exist, but canary not found after $CanaryWaitSeconds seconds"
                            }

                            $overallStatus = "Warning"
                            $confidence = "Medium"
                            $reason = "Cmdlet reports enabled and audit events exist, but canary event not found. May indicate ingestion delay or search indexing lag."
                        }
                    }
                }
            }
        }

        #endregion

    }
    catch {
        Write-Host "`nERROR: Validation failed: $($_.Exception.Message)" -ForegroundColor Red

        return [PSCustomObject]@{
            Timestamp = Get-Date -Format "o"
            ValidationType = "UnifiedAuditLog"
            Checks = $checks
            OverallStatus = "Error"
            Confidence = "N/A"
            Reason = "Validation error: $($_.Exception.Message)"
            RawValue = "Error"
        }
    }
    finally {
        # Always disconnect
        Disconnect-AuditServices
    }

    # Return final result
    return [PSCustomObject]@{
        Timestamp = Get-Date -Format "o"
        ValidationType = "UnifiedAuditLog"
        Checks = $checks
        OverallStatus = $overallStatus
        Confidence = $confidence
        Reason = $reason
        RawValue = "UnifiedAuditLogIngestionEnabled=$unifiedAuditEnabled"
    }
}

#endregion

#region Script execution

# Execute validation when run directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    $execParams = @{
        SkipCanaryValidation = $SkipCanaryValidation
        GracePeriodHours     = $GracePeriodHours
        CanaryWaitSeconds    = $CanaryWaitSeconds
    }
    if ($Interactive) { $execParams.Interactive = $true }
    if ($TenantId) { $execParams.TenantId = $TenantId }
    if ($ClientId) { $execParams.ClientId = $ClientId }
    if ($CertificateThumbprint) { $execParams.CertificateThumbprint = $CertificateThumbprint }
    if ($CertificateFilePath) { $execParams.CertificateFilePath = $CertificateFilePath }
    if (-not [string]::IsNullOrWhiteSpace($CanaryMailboxIdentity)) { $execParams.CanaryMailboxIdentity = $CanaryMailboxIdentity }

    $result = Test-UnifiedAuditLog @execParams

    # Display result
    Write-Host "`n=== Validation Result ===" -ForegroundColor Cyan
    Write-Host "Overall Status: $($result.OverallStatus)" -ForegroundColor $(
        switch ($result.OverallStatus) {
            "Passed" { "Green" }
            "Failed" { "Red" }
            "Warning" { "Yellow" }
            "GracePeriod" { "Yellow" }
            default { "Gray" }
        }
    )
    Write-Host "Confidence: $($result.Confidence)" -ForegroundColor Gray
    Write-Host "Reason: $($result.Reason)" -ForegroundColor Gray
    Write-Host "`nDetailed Checks:" -ForegroundColor Cyan
    $result.Checks | ForEach-Object {
        Write-Host "  - $($_.Name): $($_.Status)" -ForegroundColor Gray
    }
    Write-Host ""

    # Return result object for pipeline use
    return $result
}

#endregion
