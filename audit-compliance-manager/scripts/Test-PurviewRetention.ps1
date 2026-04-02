#Requires -Version 7.0
#Requires -Modules @{ ModuleName="ExchangeOnlineManagement"; ModuleVersion="3.0.0" }

<#
.SYNOPSIS
    Validates Purview audit retention policies against FSI regulatory requirements.

.DESCRIPTION
    Validates that Microsoft Purview Unified Audit Log retention policies meet
    zone-specific retention requirements for US financial services institutions.

    Zone-specific retention minimums:
    - Zone 1 (Personal Productivity): 180 days (6 months)
    - Zone 2 (Team Collaboration): 365 days (1 year)
    - Zone 3 (Enterprise Managed): 730 days (2 years minimum per SEC 17a-4)

    The script performs three validation checks:
    1. Retrieves all custom retention policies via Get-UnifiedAuditLogRetentionPolicy
    2. Validates retention duration meets zone-specific minimums
    3. Identifies record type coverage gaps (CopilotInteraction, PowerPlatformAdmin)

    IMPORTANT: Get-UnifiedAuditLogRetentionPolicy does NOT return the default
    90-day retention policy. If no custom policies exist, the script assumes
    90-day default retention and compares against the zone minimum.

    Record type coverage validation:
    - CopilotInteraction and PowerPlatformAdmin are critical for AI agent governance
    - These record types need explicit retention policies or catch-all policies
    - Catch-all policies (empty RecordTypes property) DO cover all record types

.PARAMETER Zone
    Governance zone to validate against. Required.
    Valid values: Zone1, Zone2, Zone3

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
    .\Test-PurviewRetention.ps1 -Zone Zone3 -Interactive
    Validates retention policies for Zone 3 (730-day minimum) using interactive auth.

.EXAMPLE
    .\Test-PurviewRetention.ps1 -Zone Zone2 -TenantId "contoso.onmicrosoft.com" -ClientId "12345..." -CertificateThumbprint "ABCDEF..."
    Validates retention policies for Zone 2 (365-day minimum) using service principal auth.

.OUTPUTS
    PSCustomObject with properties:
    - Timestamp: ISO 8601 timestamp
    - ValidationType: "PurviewRetention"
    - Zone: Zone1 | Zone2 | Zone3
    - MinimumRequiredDays: Zone-specific minimum
    - Checks: Array of check results
    - Gaps: Array of record type coverage gaps
    - OverallStatus: Passed | Failed | Warning
    - Confidence: High
    - Reason: Summary explanation

.NOTES
    Version: 1.0.0
    Requires:
    - ExchangeOnlineManagement module v3.7.0 or later
    - Security & Compliance PowerShell connection
    - Compliance Administrator or Global Administrator role
    - For service principal: Application with Compliance.ManageAsApp permission

    Regulatory context:
    This script supports compliance validation for:
    - SEC Rule 17a-4 (2-year minimum for communications)
    - FINRA Rule 4511 (retention of business-related communications)
    - FINRA Rule 25-07 (AI agent communications supervision)
    - GLBA 501(b) (audit logging requirements)
    - SOX Section 302 (internal controls over financial reporting)

    Retention duration mapping:
    - ThreeMonths = 90 days
    - SixMonths = 180 days
    - NineMonths = 270 days
    - OneYear = 365 days
    - TwoYears = 730 days
    - ThreeYears = 1095 days
    - FiveYears = 1825 days
    - SevenYears = 2555 days
    - TenYears = 3650 days

    Default retention policy:
    Microsoft provides a default 90-day retention for all audit logs. This policy
    is NOT returned by Get-UnifiedAuditLogRetentionPolicy. If no custom policies
    exist, the script assumes 90-day default retention.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet("Zone1", "Zone2", "Zone3")]
    [string]$Zone,

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

function Test-PurviewRetention {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet("Zone1", "Zone2", "Zone3")]
        [string]$Zone,

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

    # Zone-specific retention minimums (in days)
    $ZoneMinimumDays = @{
        "Zone1" = 180    # 6 months - Personal Productivity
        "Zone2" = 365    # 1 year - Team Collaboration
        "Zone3" = 730    # 2 years - Enterprise Managed (SEC 17a-4 communications minimum)
    }

    # Critical record types for AI agent governance
    $RequiredRecordTypes = @("CopilotInteraction", "PowerPlatformAdmin")

    # Retention duration enum to days mapping
    $RetentionDurationMap = @{
        "ThreeMonths" = 90
        "SixMonths"   = 180
        "NineMonths"  = 270
        "OneYear"     = 365
        "TwoYears"    = 730
        "ThreeYears"  = 1095
        "FiveYears"   = 1825
        "SevenYears"  = 2555
        "TenYears"    = 3650
    }

    $checks = @()
    $gaps = @()
    $overallStatus = "Unknown"
    $reason = ""
    $minimumRequiredDays = $ZoneMinimumDays[$Zone]

    try {
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Purview Retention Policy Validation" -ForegroundColor Cyan
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Zone: $Zone (Minimum: $minimumRequiredDays days)" -ForegroundColor Cyan
        Write-Host ""

        # Step 1: Connect to Security & Compliance PowerShell
        Write-Host "[1/4] Connecting to Security & Compliance PowerShell..." -ForegroundColor Yellow

        $connectParams = @{}
        if ($Interactive) { $connectParams.Interactive = $true }
        if ($TenantId) { $connectParams.TenantId = $TenantId }
        if ($ClientId) { $connectParams.ClientId = $ClientId }
        if ($CertificateThumbprint) { $connectParams.CertificateThumbprint = $CertificateThumbprint }
        if ($CertificateFilePath) { $connectParams.CertificateFilePath = $CertificateFilePath }

        Connect-ComplianceSession @connectParams

        Write-Host "Connected to Security & Compliance PowerShell." -ForegroundColor Green
        Write-Host ""

        # Step 2: Retrieve all retention policies
        Write-Host "[2/4] Retrieving Unified Audit Log retention policies..." -ForegroundColor Yellow

        $policies = Get-UnifiedAuditLogRetentionPolicy -ErrorAction Stop

        if ($null -eq $policies -or $policies.Count -eq 0) {
            Write-Host "⚠ No custom retention policies found." -ForegroundColor Yellow
            Write-Host "  Default 90-day retention applies to all audit logs." -ForegroundColor Yellow
            Write-Host ""

            $checks += @{
                Name         = "RetentionPoliciesExist"
                Status       = "Warning"
                PolicyCount  = 0
                DefaultDays  = 90
            }

            # Default 90-day retention check
            if (90 -lt $minimumRequiredDays) {
                $checks += @{
                    Name        = "RetentionMeetsMinimum"
                    Status      = "Failed"
                    CurrentDays = 90
                    RequiredDays = $minimumRequiredDays
                    Details     = "Default 90-day retention is below $Zone minimum of $minimumRequiredDays days"
                }

                $gaps += [PSCustomObject]@{
                    RecordType           = "All (default policy)"
                    Issue                = "Retention below zone minimum"
                    CurrentRetentionDays = 90
                    RequiredRetentionDays = $minimumRequiredDays
                    Severity             = "Critical"
                    Recommendation       = "Create custom retention policy: New-UnifiedAuditLogRetentionPolicy -Name 'Zone $Zone Retention' -RetentionDuration $(Get-RequiredRetentionDuration -Days $minimumRequiredDays)"
                }
            }
            else {
                $checks += @{
                    Name        = "RetentionMeetsMinimum"
                    Status      = "Passed"
                    CurrentDays = 90
                    RequiredDays = $minimumRequiredDays
                    Details     = "Default 90-day retention meets $Zone minimum"
                }
            }

            # Check required record types (all will be gaps with default policy only)
            foreach ($recordType in $RequiredRecordTypes) {
                if (90 -lt $minimumRequiredDays) {
                    $checks += @{
                        Name         = "${recordType}Coverage"
                        Status       = "Failed"
                        RetentionDays = 90
                        CoveredBy    = "Default policy"
                    }

                    $gaps += [PSCustomObject]@{
                        RecordType           = $recordType
                        Issue                = "Retention below zone minimum (default policy only)"
                        CurrentRetentionDays = 90
                        RequiredRetentionDays = $minimumRequiredDays
                        Severity             = "Critical"
                        Recommendation       = "Create record type-specific policy: New-UnifiedAuditLogRetentionPolicy -Name '$recordType Retention' -RecordTypes $recordType -RetentionDuration $(Get-RequiredRetentionDuration -Days $minimumRequiredDays)"
                    }
                }
                else {
                    $checks += @{
                        Name         = "${recordType}Coverage"
                        Status       = "Passed"
                        RetentionDays = 90
                        CoveredBy    = "Default policy"
                    }
                }
            }
        }
        else {
            Write-Host "✓ Found $($policies.Count) custom retention policy/policies" -ForegroundColor Green
            Write-Host ""

            $checks += @{
                Name        = "RetentionPoliciesExist"
                Status      = "Passed"
                PolicyCount = $policies.Count
            }

            # Step 3: Validate retention duration meets zone minimums
            Write-Host "[3/4] Validating retention duration meets zone minimums..." -ForegroundColor Yellow

            $policyDetails = @()
            $minRetentionDays = $null

            foreach ($policy in $policies) {
                $retentionDays = $RetentionDurationMap[$policy.RetentionDuration]

                $policyDetails += [PSCustomObject]@{
                    PolicyName     = $policy.Name
                    RetentionDays  = $retentionDays
                    RecordTypes    = if ($policy.RecordTypes.Count -gt 0) { $policy.RecordTypes -join ", " } else { "All (catch-all)" }
                    Priority       = $policy.Priority
                }

                # Track minimum retention across all policies
                if ($null -eq $minRetentionDays -or $retentionDays -lt $minRetentionDays) {
                    $minRetentionDays = $retentionDays
                }

                Write-Host "  Policy: $($policy.Name)" -ForegroundColor White
                Write-Host "    Retention: $retentionDays days ($($policy.RetentionDuration))" -ForegroundColor White
                Write-Host "    Record Types: $(if ($policy.RecordTypes.Count -gt 0) { $policy.RecordTypes -join ', ' } else { 'All (catch-all)' })" -ForegroundColor White
                Write-Host ""
            }

            # Check if minimum retention meets zone requirement
            if ($minRetentionDays -lt $minimumRequiredDays) {
                $checks += @{
                    Name        = "RetentionMeetsMinimum"
                    Status      = "Failed"
                    CurrentDays = $minRetentionDays
                    RequiredDays = $minimumRequiredDays
                    Details     = $policyDetails
                }

                Write-Host "✗ Minimum retention ($minRetentionDays days) is below $Zone minimum ($minimumRequiredDays days)" -ForegroundColor Red
            }
            else {
                $checks += @{
                    Name        = "RetentionMeetsMinimum"
                    Status      = "Passed"
                    CurrentDays = $minRetentionDays
                    RequiredDays = $minimumRequiredDays
                    Details     = $policyDetails
                }

                Write-Host "✓ Minimum retention ($minRetentionDays days) meets $Zone minimum ($minimumRequiredDays days)" -ForegroundColor Green
            }

            Write-Host ""

            # Step 4: Check record type coverage gaps
            Write-Host "[4/4] Checking record type coverage for AI agent governance..." -ForegroundColor Yellow

            # Check for catch-all policies (empty RecordTypes)
            $hasCatchAll = $false
            $catchAllRetentionDays = 0

            foreach ($policy in $policies) {
                if ($null -eq $policy.RecordTypes -or $policy.RecordTypes.Count -eq 0) {
                    $hasCatchAll = $true
                    $catchAllRetentionDays = $RetentionDurationMap[$policy.RetentionDuration]
                    Write-Host "  ✓ Found catch-all policy: $($policy.Name) ($catchAllRetentionDays days)" -ForegroundColor Green
                    break
                }
            }

            Write-Host ""

            foreach ($recordType in $RequiredRecordTypes) {
                $covered = $false
                $retentionDays = 0
                $coveredBy = ""

                # Check for catch-all policy first
                if ($hasCatchAll) {
                    $covered = $true
                    $retentionDays = $catchAllRetentionDays
                    $coveredBy = "Catch-all policy"
                }
                else {
                    # Check for explicit record type policy
                    foreach ($policy in $policies) {
                        if ($policy.RecordTypes -contains $recordType) {
                            $covered = $true
                            $retentionDays = $RetentionDurationMap[$policy.RetentionDuration]
                            $coveredBy = $policy.Name
                            break
                        }
                    }
                }

                if (-not $covered) {
                    # Not covered by any policy - defaults to 90 days
                    $retentionDays = 90
                    $coveredBy = "Default policy"

                    Write-Host "  ⚠ $recordType: Not explicitly covered (defaults to 90 days)" -ForegroundColor Yellow

                    if (90 -lt $minimumRequiredDays) {
                        $checks += @{
                            Name         = "${recordType}Coverage"
                            Status       = "Failed"
                            RetentionDays = 90
                            CoveredBy    = "Default policy"
                        }

                        $gaps += [PSCustomObject]@{
                            RecordType           = $recordType
                            Issue                = "No explicit retention policy (defaults to 90 days)"
                            CurrentRetentionDays = 90
                            RequiredRetentionDays = $minimumRequiredDays
                            Severity             = "High"
                            Recommendation       = "Create record type-specific policy: New-UnifiedAuditLogRetentionPolicy -Name '$recordType Retention' -RecordTypes $recordType -RetentionDuration $(Get-RequiredRetentionDuration -Days $minimumRequiredDays)"
                        }
                    }
                    else {
                        $checks += @{
                            Name         = "${recordType}Coverage"
                            Status       = "Warning"
                            RetentionDays = 90
                            CoveredBy    = "Default policy"
                        }
                    }
                }
                elseif ($retentionDays -lt $minimumRequiredDays) {
                    # Covered but retention too short
                    Write-Host "  ✗ $recordType: Covered by '$coveredBy' but retention ($retentionDays days) is below minimum ($minimumRequiredDays days)" -ForegroundColor Red

                    $checks += @{
                        Name         = "${recordType}Coverage"
                        Status       = "Failed"
                        RetentionDays = $retentionDays
                        CoveredBy    = $coveredBy
                    }

                    $gaps += [PSCustomObject]@{
                        RecordType           = $recordType
                        Issue                = "Retention below zone minimum"
                        CurrentRetentionDays = $retentionDays
                        RequiredRetentionDays = $minimumRequiredDays
                        Severity             = "Critical"
                        Recommendation       = "Update policy '$coveredBy' to extend retention to $(Get-RequiredRetentionDuration -Days $minimumRequiredDays) or create new policy with higher retention"
                    }
                }
                else {
                    # Covered and retention sufficient
                    Write-Host "  ✓ $recordType: Covered by '$coveredBy' ($retentionDays days)" -ForegroundColor Green

                    $checks += @{
                        Name         = "${recordType}Coverage"
                        Status       = "Passed"
                        RetentionDays = $retentionDays
                        CoveredBy    = $coveredBy
                    }
                }
            }

            Write-Host ""
        }

        # Determine overall status
        $failedChecks = $checks | Where-Object { $_.Status -eq "Failed" }
        $warningChecks = $checks | Where-Object { $_.Status -eq "Warning" }

        if ($failedChecks.Count -gt 0) {
            $overallStatus = "Failed"
            $reason = "Found $($failedChecks.Count) failed check(s). Retention policies do not meet $Zone requirements. See Gaps for details."
        }
        elseif ($warningChecks.Count -gt 0) {
            $overallStatus = "Warning"
            $reason = "Found $($warningChecks.Count) warning(s). Some record types lack explicit retention policies but meet minimum via default 90-day retention."
        }
        else {
            $overallStatus = "Passed"
            $reason = "All retention policies meet $Zone minimum requirements. Critical record types (CopilotInteraction, PowerPlatformAdmin) are covered."
        }

        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host "Overall Status: $overallStatus" -ForegroundColor $(if ($overallStatus -eq "Passed") { "Green" } elseif ($overallStatus -eq "Warning") { "Yellow" } else { "Red" })
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""

        if ($gaps.Count -gt 0) {
            Write-Host "Coverage Gaps Detected:" -ForegroundColor Yellow
            foreach ($gap in $gaps) {
                Write-Host "  - $($gap.RecordType): $($gap.Issue)" -ForegroundColor Yellow
                Write-Host "    Current: $($gap.CurrentRetentionDays) days | Required: $($gap.RequiredRetentionDays) days | Severity: $($gap.Severity)" -ForegroundColor Yellow
                Write-Host "    Recommendation: $($gap.Recommendation)" -ForegroundColor White
                Write-Host ""
            }
        }
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
            Name   = "ValidationError"
            Status = "Failed"
            Error  = $_.Exception.Message
        }
    }
    finally {
        # Disconnect from Security & Compliance PowerShell
        try {
            Write-Host "Disconnecting from Security & Compliance PowerShell..." -ForegroundColor Yellow
            Disconnect-ExchangeOnline -Confirm:$false -ErrorAction SilentlyContinue
            Write-Host "Disconnected." -ForegroundColor Green
        }
        catch {
            Write-Host "Warning: Error during disconnect: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }

    # Return structured result
    return [PSCustomObject]@{
        Timestamp           = (Get-Date -Format "o")
        ValidationType      = "PurviewRetention"
        Zone                = $Zone
        MinimumRequiredDays = $minimumRequiredDays
        Checks              = $checks
        Gaps                = $gaps
        OverallStatus       = $overallStatus
        Confidence          = "High"
        Reason              = $reason
        RawValue            = "RetentionPolicies=$($checks.Count)"
    }
}

# Helper function to recommend retention duration enum
function Get-RequiredRetentionDuration {
    param([int]$Days)

    if ($Days -le 90) { return "ThreeMonths" }
    elseif ($Days -le 180) { return "SixMonths" }
    elseif ($Days -le 270) { return "NineMonths" }
    elseif ($Days -le 365) { return "OneYear" }
    elseif ($Days -le 730) { return "TwoYears" }
    elseif ($Days -le 1095) { return "ThreeYears" }
    elseif ($Days -le 1825) { return "FiveYears" }
    elseif ($Days -le 2555) { return "SevenYears" }
    else { return "TenYears" }
}

# Execute the validation when run directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    Test-PurviewRetention @PSBoundParameters
}
