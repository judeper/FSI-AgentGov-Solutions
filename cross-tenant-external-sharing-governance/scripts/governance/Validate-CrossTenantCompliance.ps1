#Requires -Version 7.0
#Requires -Modules Az.Accounts

<#
.SYNOPSIS
    Generate examiner-ready cross-tenant compliance posture report.

.DESCRIPTION
    Queries all five CTSG Dataverse tables to produce a comprehensive compliance
    summary. Designed for examination preparation and ongoing compliance monitoring.

    Tables queried:
      1. fsi_externalsharefindings      — Open findings with severity breakdown
      2. fsi_approvedexternaltenants    — Approved tenants with overdue review counts
      3. fsi_crosstenantcomplianceevents — Expired onboarding requests
      4. fsi_tenantisolationrecords     — Latest tenant isolation snapshot
      5. fsi_entractarecords            — Latest Entra CTA snapshot

    Authentication: System-Assigned Managed Identity (MI-CrossTenantReadOnly) only.

.PARAMETER DataverseEnvironmentUrl
    Target Dataverse environment URL (e.g., https://org.crm.dynamics.com)

.PARAMETER OutputPath
    File path for the compliance report JSON (default: .\ctsg-compliance-{timestamp}.json)

.PARAMETER FindingStatusOpen
    OptionSet integer value for Open finding status.
    WARNING: Confirm against deployed solution XML. Default assumes 0.

.PARAMETER FindingStatusResolved
    OptionSet integer value for Resolved finding status.
    WARNING: Confirm against deployed solution XML. Default assumes 1.

.PARAMETER SeverityCritical
    OptionSet integer value for Critical severity.
    WARNING: Confirm against deployed solution XML. Default assumes 0.

.PARAMETER SeverityHigh
    OptionSet integer value for High severity.
    WARNING: Confirm against deployed solution XML. Default assumes 1.

.PARAMETER SeverityMedium
    OptionSet integer value for Medium severity.
    WARNING: Confirm against deployed solution XML. Default assumes 2.

.PARAMETER SeverityLow
    OptionSet integer value for Low severity.
    WARNING: Confirm against deployed solution XML. Default assumes 3.

.PARAMETER ApprovalStatusApproved
    OptionSet integer value for Approved status on approved tenants.
    WARNING: Confirm against deployed solution XML. Default assumes 1.

.PARAMETER ApprovalStatusExpired
    OptionSet integer value for Expired status on onboarding requests.
    WARNING: Confirm against deployed solution XML. Default assumes 2.

.EXAMPLE
    .\Validate-CrossTenantCompliance.ps1 -DataverseEnvironmentUrl "https://myorg.crm.dynamics.com"

.EXAMPLE
    .\Validate-CrossTenantCompliance.ps1 -DataverseEnvironmentUrl "https://myorg.crm.dynamics.com" -SeverityCritical 0 -SeverityHigh 1

.NOTES
    FSI Agent Governance Framework - Cross-Tenant External Sharing Governance

    IMPORTANT: Entity set names (fsi_externalsharefindings, fsi_approvedexternaltenants, etc.)
    must be confirmed post-deployment. If the Dataverse publisher prefix or plural conventions
    differ, update the $EntitySets hashtable below.

    IMPORTANT: All OptionSet integer defaults are ASSUMED values. Confirm against
    the deployed solution XML or the auto-generated dataverse-schema.md before
    production use. Incorrect OptionSet values produce silent query mismatches.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$DataverseEnvironmentUrl,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [int]$FindingStatusOpen = 0,

    [Parameter()]
    [int]$FindingStatusResolved = 1,

    [Parameter()]
    [int]$SeverityCritical = 0,

    [Parameter()]
    [int]$SeverityHigh = 1,

    [Parameter()]
    [int]$SeverityMedium = 2,

    [Parameter()]
    [int]$SeverityLow = 3,

    [Parameter()]
    [int]$ApprovalStatusApproved = 1,

    [Parameter()]
    [int]$ApprovalStatusExpired = 2
)

$ErrorActionPreference = "Stop"

if (-not $OutputPath) {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $OutputPath = ".\ctsg-compliance-$timestamp.json"
}

# --- Entity set names ---
# WARNING: Confirm these entity set names match the deployed Dataverse solution.
# Entity set names are the plural form used in OData URLs. If the publisher
# prefix or pluralization differs, update these values.
$EntitySets = @{
    Findings          = "fsi_externalsharefindings"
    ApprovedTenants   = "fsi_approvedexternaltenants"
    ComplianceEvents  = "fsi_crosstenantcomplianceevents"
    TenantIsolation   = "fsi_tenantisolationrecords"
    EntraCTA          = "fsi_entractarecords"
}

# --- Authentication ---
Connect-AzAccount -Identity | Out-Null

$dvUrl = $DataverseEnvironmentUrl.TrimEnd('/')
$tokenResult = Get-AzAccessToken -ResourceUrl $dvUrl -AsSecureString
$token = $tokenResult.Token | ConvertFrom-SecureString -AsPlainText

$headers = @{
    "Authorization"    = "Bearer $token"
    "Content-Type"     = "application/json"
    "OData-Version"    = "4.0"
    "OData-MaxVersion" = "4.0"
    "Accept"           = "application/json"
    "Prefer"           = "odata.include-annotations=*,odata.maxpagesize=500"
}

$apiBase = "$dvUrl/api/data/v9.2"

Write-Host "`n=== CROSS-TENANT COMPLIANCE POSTURE REPORT ===" -ForegroundColor Cyan
Write-Host "Generated:   $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss UTC')" -ForegroundColor Cyan
Write-Host "Environment: $dvUrl" -ForegroundColor Cyan
Write-Warning "OptionSet defaults assumed. Confirm against deployed solution XML."

# =============================================================================
# Helper: Query Dataverse with pagination
# =============================================================================
function Get-DVRecords {
    <#
    .SYNOPSIS
        Queries a Dataverse entity set with automatic pagination and retry.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$EntitySet,

        [Parameter()]
        [string]$Select,

        [Parameter()]
        [string]$Filter,

        [Parameter()]
        [string]$OrderBy,

        [Parameter()]
        [int]$Top = 0,

        [Parameter()]
        [int]$MaxRetries = 3
    )

    $queryParts = @()
    if ($Select)  { $queryParts += "`$select=$Select" }
    if ($Filter)  { $queryParts += "`$filter=$Filter" }
    if ($OrderBy) { $queryParts += "`$orderby=$OrderBy" }
    if ($Top -gt 0) { $queryParts += "`$top=$Top" }

    $queryString = $queryParts -join "&"
    $url = "$apiBase/$EntitySet"
    if ($queryString) { $url += "?$queryString" }

    $results = [System.Collections.ArrayList]::new()
    while ($url) {
        $attempt = 0
        $response = $null
        while ($attempt -lt $MaxRetries) {
            $attempt++
            try {
                $response = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop
                break
            } catch {
                $statusCode = $_.Exception.Response.StatusCode.value__
                if ($statusCode -eq 429 -and $attempt -lt $MaxRetries) {
                    $retryAfter = 5 * $attempt
                    Write-Warning "Rate limited querying $EntitySet. Retrying in $retryAfter seconds (attempt $attempt/$MaxRetries)..."
                    Start-Sleep -Seconds $retryAfter
                } elseif ($statusCode -ge 500 -and $attempt -lt $MaxRetries) {
                    $retryAfter = 3 * $attempt
                    Write-Warning "Server error ($statusCode) querying $EntitySet. Retrying in $retryAfter seconds..."
                    Start-Sleep -Seconds $retryAfter
                } else {
                    throw
                }
            }
        }

        if ($null -eq $response) {
            throw "Failed to query $EntitySet after $MaxRetries attempts."
        }

        foreach ($record in $response.value) {
            [void]$results.Add($record)
        }
        $url = $response.'@odata.nextLink'
    }

    return $results.ToArray()
}

# =============================================================================
# SECTION 1: Open Findings with Severity Breakdown
# =============================================================================
Write-Host "`n--- Section 1: Open Findings ---" -ForegroundColor Yellow

$findingsSection = @{
    TotalOpen     = 0
    Critical      = 0
    High          = 0
    Medium        = 0
    Low           = 0
    ByType        = @{}
    ByLayer       = @{}
    OldestOpenDays = 0
    Errors        = @()
}

try {
    $openFindings = Get-DVRecords `
        -EntitySet $EntitySets.Findings `
        -Select "fsi_findingstatus,fsi_severity,fsi_findingtype,fsi_governancelayer,fsi_agentname,fsi_externaltenantname,createdon" `
        -Filter "fsi_findingstatus eq $FindingStatusOpen"

    $findingsSection.TotalOpen = $openFindings.Count
    Write-Host "  Open findings: $($openFindings.Count)"

    # Severity breakdown
    foreach ($finding in $openFindings) {
        switch ($finding.fsi_severity) {
            $SeverityCritical { $findingsSection.Critical++ }
            $SeverityHigh     { $findingsSection.High++ }
            $SeverityMedium   { $findingsSection.Medium++ }
            $SeverityLow      { $findingsSection.Low++ }
        }

        # By finding type
        $fType = if ($finding.fsi_findingtype) { [string]$finding.fsi_findingtype } else { "Unknown" }
        if (-not $findingsSection.ByType.ContainsKey($fType)) {
            $findingsSection.ByType[$fType] = 0
        }
        $findingsSection.ByType[$fType]++

        # By governance layer
        $gLayer = if ($finding.fsi_governancelayer) { [string]$finding.fsi_governancelayer } else { "Unknown" }
        if (-not $findingsSection.ByLayer.ContainsKey($gLayer)) {
            $findingsSection.ByLayer[$gLayer] = 0
        }
        $findingsSection.ByLayer[$gLayer]++
    }

    # Oldest open finding
    $createdDates = $openFindings | Where-Object { $_.createdon } | ForEach-Object {
        [datetime]$_.createdon
    }
    if ($createdDates.Count -gt 0) {
        $oldest = ($createdDates | Measure-Object -Minimum).Minimum
        $findingsSection.OldestOpenDays = [math]::Floor(((Get-Date).ToUniversalTime() - $oldest).TotalDays)
    }

    Write-Host "    Critical: $($findingsSection.Critical)" -ForegroundColor $(if ($findingsSection.Critical -gt 0) { "Red" } else { "Green" })
    Write-Host "    High:     $($findingsSection.High)" -ForegroundColor $(if ($findingsSection.High -gt 0) { "Yellow" } else { "Green" })
    Write-Host "    Medium:   $($findingsSection.Medium)" -ForegroundColor Gray
    Write-Host "    Low:      $($findingsSection.Low)" -ForegroundColor Gray
    if ($findingsSection.OldestOpenDays -gt 0) {
        Write-Host "    Oldest open finding: $($findingsSection.OldestOpenDays) days" `
            -ForegroundColor $(if ($findingsSection.OldestOpenDays -gt 30) { "Red" } else { "Yellow" })
    }
} catch {
    $findingsSection.Errors += "Failed to query findings: $($_.Exception.Message)"
    Write-Warning "Failed to query $($EntitySets.Findings): $($_.Exception.Message)"
}

# =============================================================================
# SECTION 2: Approved Tenants with Overdue Review Counts
# =============================================================================
Write-Host "`n--- Section 2: Approved Tenants ---" -ForegroundColor Yellow

$tenantsSection = @{
    TotalApproved      = 0
    OverdueReviewCount = 0
    OverdueTenants     = @()
    ByRiskTier         = @{}
    Errors             = @()
}

try {
    $approvedTenants = Get-DVRecords `
        -EntitySet $EntitySets.ApprovedTenants `
        -Select "fsi_tenantname,fsi_approvalstatus,fsi_annualreviewdue,fsi_risktier,fsi_expirynotes" `
        -Filter "fsi_approvalstatus eq $ApprovalStatusApproved"

    $tenantsSection.TotalApproved = $approvedTenants.Count
    Write-Host "  Approved tenants: $($approvedTenants.Count)"

    $now = (Get-Date).ToUniversalTime()
    foreach ($tenant in $approvedTenants) {
        # Check overdue annual reviews
        if ($tenant.fsi_annualreviewdue) {
            $reviewDue = [datetime]$tenant.fsi_annualreviewdue
            if ($reviewDue -lt $now) {
                $tenantsSection.OverdueReviewCount++
                $tenantsSection.OverdueTenants += @{
                    TenantName   = $tenant.fsi_tenantname
                    ReviewDue    = $tenant.fsi_annualreviewdue
                    DaysOverdue  = [math]::Floor(($now - $reviewDue).TotalDays)
                    ExpiryNotes  = $tenant.fsi_expirynotes
                }
            }
        }

        # Risk tier breakdown
        $tier = if ($null -ne $tenant.fsi_risktier) { [string]$tenant.fsi_risktier } else { "Unclassified" }
        if (-not $tenantsSection.ByRiskTier.ContainsKey($tier)) {
            $tenantsSection.ByRiskTier[$tier] = 0
        }
        $tenantsSection.ByRiskTier[$tier]++
    }

    Write-Host "  Overdue annual reviews: $($tenantsSection.OverdueReviewCount)" `
        -ForegroundColor $(if ($tenantsSection.OverdueReviewCount -gt 0) { "Red" } else { "Green" })
    if ($tenantsSection.OverdueReviewCount -gt 0) {
        $tenantsSection.OverdueTenants | ForEach-Object {
            Write-Host "    $($_.TenantName): $($_.DaysOverdue) days overdue" -ForegroundColor Red
        }
    }
} catch {
    $tenantsSection.Errors += "Failed to query approved tenants: $($_.Exception.Message)"
    Write-Warning "Failed to query $($EntitySets.ApprovedTenants): $($_.Exception.Message)"
}

# =============================================================================
# SECTION 3: Expired Onboarding Requests
# =============================================================================
Write-Host "`n--- Section 3: Expired Onboarding Requests ---" -ForegroundColor Yellow

$onboardingSection = @{
    TotalExpired   = 0
    ExpiredRecords = @()
    Errors         = @()
}

try {
    $expiredRequests = Get-DVRecords `
        -EntitySet $EntitySets.ApprovedTenants `
        -Select "fsi_tenantname,fsi_approvalstatus,fsi_expirynotes,createdon" `
        -Filter "fsi_approvalstatus eq $ApprovalStatusExpired"

    $onboardingSection.TotalExpired = $expiredRequests.Count
    Write-Host "  Expired onboarding requests: $($expiredRequests.Count)" `
        -ForegroundColor $(if ($expiredRequests.Count -gt 0) { "Yellow" } else { "Green" })

    $onboardingSection.ExpiredRecords = $expiredRequests | ForEach-Object {
        @{
            TenantName  = $_.fsi_tenantname
            ExpiryNotes = $_.fsi_expirynotes
            CreatedOn   = $_.createdon
        }
    }

    if ($expiredRequests.Count -gt 0) {
        $expiredRequests | Select-Object fsi_tenantname, createdon | Format-Table -AutoSize
    }
} catch {
    $onboardingSection.Errors += "Failed to query compliance events: $($_.Exception.Message)"
    Write-Warning "Failed to query $($EntitySets.ComplianceEvents): $($_.Exception.Message)"
}

# =============================================================================
# SECTION 4: Latest Tenant Isolation Record
# =============================================================================
Write-Host "`n--- Section 4: Tenant Isolation Status ---" -ForegroundColor Yellow

$isolationSection = @{
    LatestRecord      = $null
    IsolationEnabled  = $null
    UnapprovedCount   = $null
    ComplianceStatus  = $null
    ApiSchemaConfirmed = $null
    Errors            = @()
}

try {
    $isolationRecords = Get-DVRecords `
        -EntitySet $EntitySets.TenantIsolation `
        -Select "fsi_isolationenabled,fsi_unapprovedcount,fsi_compliancestatus,fsi_apischemaconfirmed,createdon" `
        -OrderBy "createdon desc" `
        -Top 1

    if ($isolationRecords.Count -gt 0) {
        $latest = $isolationRecords[0]
        $isolationSection.LatestRecord = $latest.createdon
        $isolationSection.IsolationEnabled = $latest.fsi_isolationenabled
        $isolationSection.UnapprovedCount = $latest.fsi_unapprovedcount
        $isolationSection.ComplianceStatus = $latest.fsi_compliancestatus
        $isolationSection.ApiSchemaConfirmed = $latest.fsi_apischemaconfirmed

        Write-Host "  Latest snapshot: $($latest.createdon)"
        Write-Host "  Isolation enabled: $($latest.fsi_isolationenabled)" `
            -ForegroundColor $(if ($latest.fsi_isolationenabled) { "Green" } else { "Red" })
        Write-Host "  Unapproved tenants: $($latest.fsi_unapprovedcount)" `
            -ForegroundColor $(if ($latest.fsi_unapprovedcount -gt 0) { "Red" } else { "Green" })

        if (-not $latest.fsi_apischemaconfirmed) {
            Write-Warning "API schema NOT confirmed. Run Deploy-CrossTenantBaseline.ps1 to validate API responses."
        }
    } else {
        Write-Warning "No tenant isolation records found. Flow 1 may not have run yet."
    }
} catch {
    $isolationSection.Errors += "Failed to query tenant isolation records: $($_.Exception.Message)"
    Write-Warning "Failed to query $($EntitySets.TenantIsolation): $($_.Exception.Message)"
}

# =============================================================================
# SECTION 5: Latest Entra CTA Record
# =============================================================================
Write-Host "`n--- Section 5: Entra Cross-Tenant Access Status ---" -ForegroundColor Yellow

$ctaSection = @{
    LatestRecord     = $null
    ComplianceStatus = $null
    UnapprovedCount  = $null
    Errors           = @()
}

try {
    $ctaRecords = Get-DVRecords `
        -EntitySet $EntitySets.EntraCTA `
        -Select "fsi_compliancestatus,fsi_unapprovedcount,createdon" `
        -OrderBy "createdon desc" `
        -Top 1

    if ($ctaRecords.Count -gt 0) {
        $latestCta = $ctaRecords[0]
        $ctaSection.LatestRecord = $latestCta.createdon
        $ctaSection.ComplianceStatus = $latestCta.fsi_compliancestatus
        $ctaSection.UnapprovedCount = $latestCta.fsi_unapprovedcount

        Write-Host "  Latest snapshot: $($latestCta.createdon)"
        Write-Host "  Compliance status: $($latestCta.fsi_compliancestatus)"
        Write-Host "  Unapproved partners: $($latestCta.fsi_unapprovedcount)" `
            -ForegroundColor $(if ($latestCta.fsi_unapprovedcount -gt 0) { "Red" } else { "Green" })
    } else {
        Write-Warning "No Entra CTA records found. Flow 2 may not have run yet."
    }
} catch {
    $ctaSection.Errors += "Failed to query Entra CTA records: $($_.Exception.Message)"
    Write-Warning "Failed to query $($EntitySets.EntraCTA): $($_.Exception.Message)"
}

# =============================================================================
# Overall Compliance Status Determination
# =============================================================================
Write-Host "`n--- Overall Compliance Status ---" -ForegroundColor Yellow

$overallStatus = "Compliant"
$statusReasons = [System.Collections.ArrayList]::new()

# Critical or high findings -> Non-Compliant
if ($findingsSection.Critical -gt 0) {
    $overallStatus = "Non-Compliant"
    [void]$statusReasons.Add("$($findingsSection.Critical) critical finding(s) open")
}
if ($findingsSection.High -gt 0 -and $overallStatus -ne "Non-Compliant") {
    $overallStatus = "Non-Compliant"
    [void]$statusReasons.Add("$($findingsSection.High) high-severity finding(s) open")
} elseif ($findingsSection.High -gt 0) {
    [void]$statusReasons.Add("$($findingsSection.High) high-severity finding(s) open")
}

# Overdue reviews -> At Risk
if ($tenantsSection.OverdueReviewCount -gt 0) {
    if ($overallStatus -eq "Compliant") { $overallStatus = "At Risk" }
    [void]$statusReasons.Add("$($tenantsSection.OverdueReviewCount) overdue annual review(s)")
}

# Tenant isolation disabled -> Non-Compliant
if ($isolationSection.IsolationEnabled -eq $false) {
    $overallStatus = "Non-Compliant"
    [void]$statusReasons.Add("Power Platform tenant isolation is disabled")
}

# Unapproved tenants in isolation or CTA -> Non-Compliant
if ($isolationSection.UnapprovedCount -gt 0) {
    $overallStatus = "Non-Compliant"
    [void]$statusReasons.Add("$($isolationSection.UnapprovedCount) unapproved tenant(s) in isolation allow-list")
}
if ($ctaSection.UnapprovedCount -gt 0) {
    $overallStatus = "Non-Compliant"
    [void]$statusReasons.Add("$($ctaSection.UnapprovedCount) unapproved partner(s) in Entra CTA")
}

# API schema not confirmed -> At Risk
if ($isolationSection.ApiSchemaConfirmed -eq $false) {
    if ($overallStatus -eq "Compliant") { $overallStatus = "At Risk" }
    [void]$statusReasons.Add("Tenant isolation API schema not confirmed")
}

# Medium findings -> At Risk
if ($findingsSection.Medium -gt 0) {
    if ($overallStatus -eq "Compliant") { $overallStatus = "At Risk" }
    [void]$statusReasons.Add("$($findingsSection.Medium) medium-severity finding(s) open")
}

# Expired onboarding requests -> At Risk
if ($onboardingSection.TotalExpired -gt 0) {
    if ($overallStatus -eq "Compliant") { $overallStatus = "At Risk" }
    [void]$statusReasons.Add("$($onboardingSection.TotalExpired) expired onboarding request(s)")
}

# No data from any flow -> Unknown
$allErrors = @()
$allErrors += $findingsSection.Errors
$allErrors += $tenantsSection.Errors
$allErrors += $onboardingSection.Errors
$allErrors += $isolationSection.Errors
$allErrors += $ctaSection.Errors

if ($null -eq $isolationSection.LatestRecord -and $null -eq $ctaSection.LatestRecord -and $findingsSection.TotalOpen -eq 0 -and $tenantsSection.TotalApproved -eq 0) {
    $overallStatus = "Unknown"
    [void]$statusReasons.Add("No data found in any table — governance flows may not have run")
}

$statusColor = switch ($overallStatus) {
    "Compliant"     { "Green" }
    "At Risk"       { "Yellow" }
    "Non-Compliant" { "Red" }
    "Unknown"       { "DarkYellow" }
    default         { "White" }
}

Write-Host "`n  OVERALL STATUS: $overallStatus" -ForegroundColor $statusColor
if ($statusReasons.Count -gt 0) {
    foreach ($reason in $statusReasons) {
        Write-Host "    - $reason" -ForegroundColor $statusColor
    }
}

# =============================================================================
# Export Compliance Report JSON
# =============================================================================
Write-Host "`n--- Exporting Compliance Report ---" -ForegroundColor Yellow

$report = @{
    MetaData = @{
        GeneratedAt          = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        ScriptVersion        = "1.0.0"
        DataverseEnvironment = $dvUrl
        Authentication       = "System-Assigned Managed Identity (MI-CrossTenantReadOnly)"
        OptionSetDefaults    = @{
            FindingStatusOpen      = $FindingStatusOpen
            FindingStatusResolved  = $FindingStatusResolved
            SeverityCritical       = $SeverityCritical
            SeverityHigh           = $SeverityHigh
            SeverityMedium         = $SeverityMedium
            SeverityLow            = $SeverityLow
            ApprovalStatusApproved = $ApprovalStatusApproved
            ApprovalStatusExpired  = $ApprovalStatusExpired
        }
        OptionSetWarning     = "All OptionSet integer values are ASSUMED defaults. Confirm against deployed solution XML before production use."
        EntitySetWarning     = "Entity set names must be confirmed post-deployment. Update the EntitySets hashtable if they differ."
    }
    OverallCompliance = @{
        Status  = $overallStatus
        Reasons = $statusReasons.ToArray()
    }
    Section1_OpenFindings = @{
        TotalOpen      = $findingsSection.TotalOpen
        SeverityBreakdown = @{
            Critical = $findingsSection.Critical
            High     = $findingsSection.High
            Medium   = $findingsSection.Medium
            Low      = $findingsSection.Low
        }
        ByFindingType  = $findingsSection.ByType
        ByGovernanceLayer = $findingsSection.ByLayer
        OldestOpenDays = $findingsSection.OldestOpenDays
        Errors         = $findingsSection.Errors
    }
    Section2_ApprovedTenants = @{
        TotalApproved      = $tenantsSection.TotalApproved
        OverdueReviewCount = $tenantsSection.OverdueReviewCount
        OverdueTenants     = $tenantsSection.OverdueTenants
        ByRiskTier         = $tenantsSection.ByRiskTier
        Errors             = $tenantsSection.Errors
    }
    Section3_ExpiredOnboarding = @{
        TotalExpired   = $onboardingSection.TotalExpired
        ExpiredRecords = $onboardingSection.ExpiredRecords
        Errors         = $onboardingSection.Errors
    }
    Section4_TenantIsolation = @{
        LatestRecord       = $isolationSection.LatestRecord
        IsolationEnabled   = $isolationSection.IsolationEnabled
        UnapprovedCount    = $isolationSection.UnapprovedCount
        ComplianceStatus   = $isolationSection.ComplianceStatus
        ApiSchemaConfirmed = $isolationSection.ApiSchemaConfirmed
        Errors             = $isolationSection.Errors
    }
    Section5_EntraCTA = @{
        LatestRecord     = $ctaSection.LatestRecord
        ComplianceStatus = $ctaSection.ComplianceStatus
        UnapprovedCount  = $ctaSection.UnapprovedCount
        Errors           = $ctaSection.Errors
    }
    QueryErrors = $allErrors
}

$outputDir = Split-Path -Path $OutputPath -Parent
if ($outputDir -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$report | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding utf8
Write-Host "  Report exported: $OutputPath" -ForegroundColor Green

# --- Final Summary ---
Write-Host "`n=== COMPLIANCE REPORT SUMMARY ===" -ForegroundColor Cyan
Write-Host "  Overall Status:         $overallStatus" -ForegroundColor $statusColor
Write-Host "  Open Findings:          $($findingsSection.TotalOpen) (Critical: $($findingsSection.Critical), High: $($findingsSection.High))"
Write-Host "  Approved Tenants:       $($tenantsSection.TotalApproved) (Overdue reviews: $($tenantsSection.OverdueReviewCount))"
Write-Host "  Expired Onboarding:     $($onboardingSection.TotalExpired)"
Write-Host "  Tenant Isolation:       $(if ($null -ne $isolationSection.IsolationEnabled) { $isolationSection.IsolationEnabled } else { 'No data' })"
Write-Host "  Entra CTA Unapproved:   $(if ($null -ne $ctaSection.UnapprovedCount) { $ctaSection.UnapprovedCount } else { 'No data' })"
Write-Host "  Query Errors:           $($allErrors.Count)" -ForegroundColor $(if ($allErrors.Count -gt 0) { "Red" } else { "Green" })
Write-Host ""
Write-Host "  Compliance report: COMPLETE" -ForegroundColor Green
