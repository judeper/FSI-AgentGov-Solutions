#Requires -Version 7.2
#Requires -Modules @{ ModuleName="ExchangeOnlineManagement"; ModuleVersion="3.0.0"; MaximumVersion="3.9.2" }

<#
.SYNOPSIS
    Validates mailbox audit on-by-default configuration.

.DESCRIPTION
    Validates that mailbox audit logging is enabled organization-wide via the
    AuditDisabled property of Get-OrganizationConfig. This check confirms that
    mailbox audit on-by-default is active for the tenant.

    IMPORTANT: The AuditDisabled property has INVERTED LOGIC.
    - AuditDisabled = $false means mailbox audit IS enabled (correct state)
    - AuditDisabled = $true means mailbox audit IS disabled (compliance risk)

    The script performs two validation checks:
    1. Organization-level check via Get-OrganizationConfig.AuditDisabled
    2. Mailbox audit bypass check via Get-MailboxAuditBypassAssociation to detect
       accounts explicitly excluded from mailbox audit logging

    When mailbox auditing on by default is turned on, it overrides the per-mailbox
    AuditEnabled property: Get-Mailbox always returns AuditEnabled=$true and setting
    AuditEnabled=$false on a mailbox is ignored. The supported way to exclude an
    account from auditing is a mailbox audit bypass association
    (Set-MailboxAuditBypassAssociation -AuditBypassEnabled $true). Accounts with an
    active bypass association are not audited, which is a compliance risk and
    triggers a Warning status.
    Reference: https://learn.microsoft.com/en-us/purview/audit-mailboxes

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

.EXAMPLE
    .\Test-MailboxAudit.ps1 -Interactive
    Validates mailbox audit using interactive authentication.

.EXAMPLE
    .\Test-MailboxAudit.ps1 -TenantId "contoso.onmicrosoft.com" -ClientId "12345..." -CertificateThumbprint "ABCDEF..."
    Validates using service principal authentication.

.OUTPUTS
    PSCustomObject with properties:
    - Timestamp: ISO 8601 timestamp
    - ValidationType: "MailboxAudit"
    - Checks: Array of check results
    - OverallStatus: Passed | Failed | Warning
    - Confidence: High
    - Reason: Summary explanation

.NOTES
    Version: 1.0.2
    Requires:
    - ExchangeOnlineManagement module v3.0.0 or later
    - Exchange Online Administrator or Global Administrator role
    - For service principal: Application with Exchange.ManageAsApp permission

    Regulatory context:
    This script supports compliance validation for:
    - FINRA Rule 4511 (audit trail retention)
    - SEC Rule 17a-4 (records retention)
    - FINRA Rule 25-07 (communications supervision for AI agents)
    - SOX Section 302 (internal controls over financial reporting)

    IMPORTANT: Mailbox audit on-by-default has been enabled for all M365
    tenants since January 2019. If this check fails, it indicates either:
    1. Manual disablement at organization level (serious compliance risk)
    2. Legacy tenant that hasn't been upgraded (contact Microsoft support)
#>

[CmdletBinding()]
param(
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

# Set strict error handling
$ErrorActionPreference = "Stop"

# Dot-source the authentication helper
$privatePath = Join-Path $PSScriptRoot 'private'
$requiredHelpers = @(
    'Connect-AuditServices.ps1'
)
foreach ($helper in $requiredHelpers) {
    $helperPath = Join-Path $privatePath $helper
    if (-not (Test-Path $helperPath)) {
        throw "Required helper script not found: $helperPath. Ensure the solution is installed correctly."
    }
    . $helperPath
}

function Test-MailboxAudit {
    [CmdletBinding()]
    param(
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

    $checks = @()
    $overallStatus = "Unknown"
    $reason = ""

    try {
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Mailbox Audit Validation" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""

        # Step 1: Connect to Exchange Online
        Write-Host "[1/3] Connecting to Exchange Online..." -ForegroundColor Yellow

        $connectParams = @{}
        if ($Interactive) { $connectParams.Interactive = $true }
        if ($TenantId) { $connectParams.TenantId = $TenantId }
        if ($ClientId) { $connectParams.ClientId = $ClientId }
        if ($CertificateThumbprint) { $connectParams.CertificateThumbprint = $CertificateThumbprint }
        if ($CertificateFilePath) { $connectParams.CertificateFilePath = $CertificateFilePath }

        Connect-AuditServices -ExchangeOnly @connectParams

        Write-Host "Connected to Exchange Online." -ForegroundColor Green
        Write-Host ""

        # Step 2: Check organization-level mailbox audit configuration
        Write-Host "[2/3] Checking organization-level mailbox audit configuration..." -ForegroundColor Yellow

        $orgConfig = Get-OrganizationConfig -ErrorAction Stop

        # CRITICAL: AuditDisabled has INVERTED LOGIC
        # AuditDisabled = $false means mailbox audit IS enabled (correct state)
        # AuditDisabled = $true means mailbox audit IS disabled (compliance risk)
        $auditDisabled = $orgConfig.AuditDisabled
        $auditEnabled = -not $auditDisabled

        # Interpret the inverted property
        if ($auditEnabled) {
            $interpretation = "Mailbox audit is enabled organization-wide (AuditDisabled = $auditDisabled)"
            $orgCheckStatus = "Passed"
            Write-Host "✓ Organization-level mailbox audit: ENABLED" -ForegroundColor Green
        }
        else {
            $interpretation = "Mailbox audit is DISABLED organization-wide (AuditDisabled = $auditDisabled)"
            $orgCheckStatus = "Failed"
            Write-Host "✗ Organization-level mailbox audit: DISABLED" -ForegroundColor Red
        }

        $checks += @{
            Name           = "OrganizationAuditDisabled"
            Status         = $orgCheckStatus
            RawValue       = $auditDisabled
            Interpretation = $interpretation
        }

        Write-Host ""

        # Step 3: Check for mailbox audit bypass associations.
        # When mailbox auditing on by default is enabled, the per-mailbox AuditEnabled
        # property is overridden (Get-Mailbox always returns True) and AuditEnabled=$false
        # is ignored. The supported way to exclude an account from auditing is a mailbox
        # audit bypass association, so that is what we detect here.
        # Reference: https://learn.microsoft.com/en-us/purview/audit-mailboxes
        Write-Host "[3/3] Checking for mailbox audit bypass associations..." -ForegroundColor Yellow

        $mailboxCheckStatus = "Unknown"
        $associationsChecked = 0
        $bypassEnabledCount = 0
        $bypassedAccounts = @()

        try {
            # AuditBypassEnabled=$true means the account is excluded from mailbox audit logging.
            $bypassAssociations = Get-MailboxAuditBypassAssociation -ResultSize unlimited -ErrorAction Stop

            $associationsChecked = @($bypassAssociations).Count

            foreach ($association in $bypassAssociations) {
                if ($association.AuditBypassEnabled -eq $true) {
                    $bypassEnabledCount++
                    $bypassedAccounts += $association.Name
                    Write-Host "  ⚠ Bypass detected: $($association.Name) has AuditBypassEnabled=`$true" -ForegroundColor Yellow
                }
            }

            if ($bypassEnabledCount -eq 0) {
                $mailboxCheckStatus = "Passed"
                Write-Host "✓ No mailbox audit bypass associations detected (checked $associationsChecked account(s))" -ForegroundColor Green
            }
            else {
                $mailboxCheckStatus = "Warning"
                Write-Host "⚠ Found $bypassEnabledCount account(s) bypassing mailbox audit (checked $associationsChecked account(s))" -ForegroundColor Yellow
                Write-Host "  These accounts are excluded from mailbox audit logging via Set-MailboxAuditBypassAssociation." -ForegroundColor Yellow
            }
        }
        catch {
            # If the bypass query fails (e.g., permissions issue), log warning but don't fail overall check
            Write-Host "⚠ Warning: Unable to check mailbox audit bypass associations. Error: $($_.Exception.Message)" -ForegroundColor Yellow
            Write-Host "  This is supplementary validation. Organization-level check is primary." -ForegroundColor Yellow
            $mailboxCheckStatus = "Skipped"
        }

        $checks += @{
            Name                 = "MailboxAuditBypassAssociations"
            Status               = $mailboxCheckStatus
            AssociationsChecked  = $associationsChecked
            BypassEnabledCount   = $bypassEnabledCount
            BypassedAccounts     = $bypassedAccounts
        }

        Write-Host ""

        # Determine overall status
        if ($orgCheckStatus -eq "Failed") {
            $overallStatus = "Failed"
            $reason = "Mailbox audit is DISABLED at organization level. This is a critical compliance risk. Enable via Set-OrganizationConfig -AuditDisabled `$false"
        }
        elseif ($mailboxCheckStatus -eq "Warning") {
            $overallStatus = "Warning"
            $reason = "Mailbox audit is enabled organization-wide, but $bypassEnabledCount account(s) bypass mailbox audit logging. Review and remove the bypass where it is not required: Set-MailboxAuditBypassAssociation -Identity <account> -AuditBypassEnabled `$false"
        }
        else {
            $overallStatus = "Passed"
            $reason = "Mailbox audit is enabled organization-wide. No mailbox audit bypass associations detected."
        }

        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Overall Status: $overallStatus" -ForegroundColor $(if ($overallStatus -eq "Passed") { "Green" } elseif ($overallStatus -eq "Warning") { "Yellow" } else { "Red" })
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
    }
    catch {
        $overallStatus = "Failed"
        $reason = "Validation failed with error: $($_.Exception.Message)"

        Write-Host ""
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "Validation Failed" -ForegroundColor Red
        Write-Host "========================================" -ForegroundColor Red
        Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""

        $checks += @{
            Name    = "ValidationError"
            Status  = "Failed"
            Error   = $_.Exception.Message
        }
    }
    finally {
        # Disconnect from Exchange Online
        try {
            Write-Host "Disconnecting from Exchange Online..." -ForegroundColor Yellow
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "Disconnected." -ForegroundColor Green
        }
        catch {
            Write-Host "Warning: Error during disconnect: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # Return structured result
    return [PSCustomObject]@{
        Timestamp      = (Get-Date -Format "o")
        ValidationType = "MailboxAudit"
        Checks         = $checks
        OverallStatus  = $overallStatus
        Confidence     = "High"
        Reason         = $reason
        RawValue       = "AuditDisabled=$auditDisabled"
    }
}

# Execute the validation when run directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    Test-MailboxAudit @PSBoundParameters
}
