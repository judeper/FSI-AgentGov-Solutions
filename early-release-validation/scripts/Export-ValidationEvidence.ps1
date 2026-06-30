<#
.SYNOPSIS
    Exports early-release validation evidence for supervisory review.

.DESCRIPTION
    Collects fsi_ervalidationresult rows and audit logs and packages them into a
    tamper-evident JSON evidence artifact (with a SHA-256 companion file) for
    pre-promotion change-control review (OCC 2011-12 / Fed SR 11-7 model/agent
    validation, SEC 17a-4 recordkeeping, FINRA 4511 books-and-records).

    When Dataverse credentials are provided (AccessToken, or TenantId/ClientId/
    ClientSecret), the script queries fsi_ervalidationresults, aggregates pass/
    fail/skipped metrics and promotion-readiness, and identifies coverage gaps
    (failed checks and check types never run in the evidence window).

.PARAMETER Environment
    Dataverse environment URL to query validation results from.

.PARAMETER OutputDir
    Directory to write evidence files to. Defaults to ./evidence.

.PARAMETER RunId
    Optional correlation id to filter results to a single validation run.

.EXAMPLE
    .\Export-ValidationEvidence.ps1 -Environment "https://contoso.crm.dynamics.com" -OutputDir "./evidence"
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Dev-only legacy auth path. Production deployments use managed identity via scripts/shared/dataverse_client.py per AGENTS.md "Authentication standard". Plaintext secret here is wrapped immediately into SecureString and never persisted.'
)]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [string]$OutputDir = (Join-Path $PSScriptRoot ".." "evidence"),

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[0-9a-zA-Z\-]+$')]
    [string]$RunId,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^$|^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^$|^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter(Mandatory = $false)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [string]$AccessToken = $env:DATAVERSE_ACCESS_TOKEN
)

#Requires -Version 7.1

$ErrorActionPreference = "Stop"

# Expected check types for coverage-gap detection (excludes the composite gate).
$script:ExpectedCheckTypes = @(
    "FallbackCoverageCheck",
    "ConnectorResilienceCheck",
    "ErrorRecoveryCheck"
)

function Get-ErvEvidenceAuthEndpoint {
    param([string]$EnvironmentUrl)
    if ($EnvironmentUrl -match '\.dynamics\.cn$') {
        return 'https://login.chinacloudapi.cn'
    } elseif ($EnvironmentUrl -match '\.(microsoftdynamics\.us|appsplatform\.us)$') {
        return 'https://login.microsoftonline.us'
    } else {
        return 'https://login.microsoftonline.com'
    }
}

function Get-ErvEvidenceAccessToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [SecureString]$ClientSecret,
        [string]$Scope,
        [string]$AuthEndpoint
    )
    $plainSecret = [System.Net.NetworkCredential]::new('', $ClientSecret).Password
    $body = $null
    try {
        $tokenUrl = "$AuthEndpoint/$TenantId/oauth2/v2.0/token"
        $body = @{
            client_id     = $ClientId
            client_secret = $plainSecret
            scope         = $Scope
            grant_type    = "client_credentials"
        }
        $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded" -TimeoutSec 30
        if ([string]::IsNullOrEmpty($response.access_token)) {
            throw "Token endpoint returned HTTP 200 but no access_token field."
        }
        return $response.access_token
    } finally {
        $plainSecret = $null
        if ($body) { $body['client_secret'] = $null }
    }
}

function Get-ErvEvidenceSummary {
    <#
        Aggregate a list of validation result hashtables (each with TestType,
        Status, PromotionReady, GapCount) into metrics, gaps, and an overall
        evidence status. Pure; unit-testable without Dataverse.
    #>
    param([object[]]$Results)

    $results = @($Results)
    $total = $results.Count
    $passed = @($results | Where-Object { $_.Status -eq "Pass" }).Count
    $failed = @($results | Where-Object { $_.Status -eq "Fail" }).Count
    $skipped = @($results | Where-Object { $_.Status -eq "Skipped" }).Count
    $promotionReady = @($results | Where-Object { $_.PromotionReady -eq $true }).Count
    $totalGaps = ($results | Measure-Object -Property GapCount -Sum).Sum
    if ($null -eq $totalGaps) { $totalGaps = 0 }

    $metrics = @{
        TotalResults        = $total
        Passed              = $passed
        Failed              = $failed
        Skipped             = $skipped
        PassRate            = if ($total -gt 0) { [math]::Round(($passed / $total) * 100, 1) } else { 0 }
        PromotionReadyCount = $promotionReady
        TotalGaps           = $totalGaps
    }

    $gaps = @($results | Where-Object { $_.Status -eq "Fail" } | ForEach-Object {
            @{
                TestType = $_.TestType
                GapCount = $_.GapCount
                Issue    = "Validation failed - see finding detail / audit log."
            }
        })

    $executedTypes = @($results | ForEach-Object { $_.TestType } | Sort-Object -Unique)
    $missingTypes = @($script:ExpectedCheckTypes | Where-Object { $_ -notin $executedTypes })
    foreach ($missing in $missingTypes) {
        $gaps += @{
            TestType = $missing
            Issue    = "Check type never executed in this evidence window - required before early-release promotion."
        }
    }

    # A composite readiness run that never confirmed promotion-readiness must not
    # be reported as fully Validated (the live probe is deferred - issue #1266).
    $readinessRows = @($results | Where-Object { $_.TestType -eq "EarlyReleaseReadinessCheck" })
    $notPromotionReady = ($readinessRows.Count -gt 0) -and
        (@($readinessRows | Where-Object { $_.PromotionReady -eq $true }).Count -eq 0)

    $status = if ($failed -gt 0) { "ValidationFailures" }
    elseif ($total -eq 0) { "NoData" }
    elseif ($missingTypes.Count -gt 0) { "IncompleteCoverage" }
    elseif ($notPromotionReady) { "NotPromotionReady" }
    else { "Validated" }

    return @{
        Metrics      = $metrics
        Gaps         = $gaps
        Status       = $status
        MissingTypes = $missingTypes
    }
}

# ===========================================================================
# Main
#
# Guarded so dot-sourcing (Pester) only defines the helper functions above
# without executing the export flow.
# ===========================================================================

if ($MyInvocation.InvocationName -ne '.') {

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Early-Release Validation Evidence Export" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$Environment = $Environment.TrimEnd('/')
if ($Environment -notmatch '^https://[\w\-]+\.(crm[\d]*\.dynamics\.com|crm\.microsoftdynamics\.us|crm\.appsplatform\.us|crm\.dynamics\.cn)$') {
    throw "Environment must be a valid Dataverse URL (e.g., https://<org>.crm.dynamics.com, .microsoftdynamics.us, .appsplatform.us, or .dynamics.cn)"
}

# legacy: dev-only - replace with managed identity in production
if (-not $ClientSecret -and $env:AZURE_CLIENT_SECRET) {
    $ClientSecret = $env:AZURE_CLIENT_SECRET | ConvertTo-SecureString -AsPlainText -Force
}

if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Collect audit log files
$auditLogDir = Join-Path $PSScriptRoot ".." "logs"
$auditLogs = @()
if (Test-Path $auditLogDir) {
    $logFilter = if ($RunId) { "erv-audit-*-$RunId.log" } else { "erv-audit-*.log" }
    $auditLogs = Get-ChildItem -Path $auditLogDir -Filter $logFilter -ErrorAction SilentlyContinue
}

$evidencePackage = @{
    ExportedAt    = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Environment   = $Environment
    RunId         = if ($RunId) { $RunId } else { "all" }
    AuditLogFiles = @($auditLogs | ForEach-Object { $_.Name })
}

$testResults = @()
$summary = @{ Metrics = @{}; Gaps = @(); Status = "NoCredentials"; MissingTypes = @() }

$HasDataverseAuth = $AccessToken -or ($TenantId -and $ClientId -and $ClientSecret)
if ($HasDataverseAuth) {
    try {
        Write-Host "  Authenticating to Dataverse..." -ForegroundColor Gray
        if ($AccessToken) {
            $token = $AccessToken
        } else {
            $authEndpoint = Get-ErvEvidenceAuthEndpoint -EnvironmentUrl $Environment
            $token = Get-ErvEvidenceAccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$Environment/.default" -AuthEndpoint $authEndpoint
        }
        $dvHeaders = @{
            "Authorization"    = "Bearer $token"
            "OData-MaxVersion" = "4.0"
            "OData-Version"    = "4.0"
            "Accept"           = "application/json"
        }

        $select = "fsi_ervalidationresultid,fsi_name,fsi_testtype,fsi_teststatus,fsi_gapcount,fsi_promotionready,fsi_findingdetail,fsi_executedon,fsi_agentid,fsi_agentversion,fsi_environmenturl,fsi_evidencehash,fsi_correlationid"
        $queryUri = "$Environment/api/data/v9.2/fsi_ervalidationresults?`$select=$select&`$orderby=fsi_executedon desc"
        if ($RunId) { $queryUri += "&`$filter=fsi_correlationid eq '$RunId'" }

        Write-Host "  Querying Dataverse for validation results (paginated)..." -ForegroundColor Gray
        $rawResults = [System.Collections.Generic.List[object]]::new()
        $pageCount = 0
        $nextUri = $queryUri
        while ($nextUri) {
            $pageCount++
            $queryResp = Invoke-RestMethod -Uri $nextUri -Headers $dvHeaders -Method Get -ContentType "application/json" -TimeoutSec 60
            if ($queryResp.value) {
                foreach ($item in $queryResp.value) { $rawResults.Add($item) | Out-Null }
            }
            $nextUri = $queryResp.'@odata.nextLink'
            if ($pageCount -gt 200) {
                Write-Warning "Pagination exceeded 200 pages - aborting. Narrow with -RunId."
                break
            }
        }

        # Map option-set integers back to readable labels.
        $testTypeLabel = @{
            100000000 = "FallbackCoverageCheck"
            100000001 = "ConnectorResilienceCheck"
            100000002 = "ErrorRecoveryCheck"
            100000003 = "EarlyReleaseReadinessCheck"
        }
        $testStatusLabel = @{ 100000000 = "Pass"; 100000001 = "Fail"; 100000002 = "Skipped" }

        $testResults = @($rawResults | ForEach-Object {
                @{
                    Id             = $_.fsi_ervalidationresultid
                    Name           = $_.fsi_name
                    TestType       = $testTypeLabel[[int]$_.fsi_testtype]
                    Status         = $testStatusLabel[[int]$_.fsi_teststatus]
                    GapCount       = [int]$_.fsi_gapcount
                    PromotionReady = [bool]$_.fsi_promotionready
                    FindingDetail  = $_.fsi_findingdetail
                    ExecutedOn     = $_.fsi_executedon
                    AgentId        = $_.fsi_agentid
                    AgentVersion   = $_.fsi_agentversion
                    EvidenceHash   = $_.fsi_evidencehash
                    CorrelationId  = $_.fsi_correlationid
                }
            })

        $summary = Get-ErvEvidenceSummary -Results $testResults
        Write-Host "  Retrieved $($testResults.Count) result(s)." -ForegroundColor Green
    } catch {
        $summary.Status = "QueryFailed"
        Write-Warning "Dataverse query failed: $($_.Exception.Message)"
    }
} else {
    Write-Warning "Dataverse authentication not provided. Evidence export includes audit logs only. Prefer -AccessToken for managed identity or workload identity automation."
}

$evidencePackage.Results = $testResults
$evidencePackage.Metrics = $summary.Metrics
$evidencePackage.Gaps = $summary.Gaps
$evidencePackage.Status = $summary.Status

$outputPath = Join-Path $OutputDir "erv-evidence-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$jsonContent = $evidencePackage | ConvertTo-Json -Depth 6
$jsonContent | Set-Content -Path $outputPath -Encoding utf8

# SHA-256 companion for tamper detection
$sha = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($jsonContent))
$sha.Dispose()
$hashHex = -join ($hashBytes | ForEach-Object { $_.ToString("x2") })
$hashPath = "$outputPath.sha256"
"$hashHex  $(Split-Path $outputPath -Leaf)" | Set-Content -Path $hashPath -Encoding utf8
Write-Host "  SHA-256 hash written to: $hashPath" -ForegroundColor Green

if ($auditLogs.Count -gt 0) {
    $logsDestDir = Join-Path $OutputDir "audit-logs"
    if (-not (Test-Path $logsDestDir)) {
        New-Item -ItemType Directory -Path $logsDestDir -Force | Out-Null
    }
    foreach ($log in $auditLogs) {
        Copy-Item -Path $log.FullName -Destination $logsDestDir -Force
    }
    Write-Host "  Copied $($auditLogs.Count) audit log file(s) to evidence package" -ForegroundColor Green
}

Write-Host ""
Write-Host "Evidence package written to: $outputPath" -ForegroundColor Green
$statusColor = switch ($summary.Status) {
    "Validated"          { 'Green' }
    "ValidationFailures" { 'Red' }
    "IncompleteCoverage" { 'Yellow' }
    "NotPromotionReady"  { 'Yellow' }
    "NoData"             { 'Yellow' }
    "QueryFailed"        { 'Red' }
    default              { 'Yellow' }
}
Write-Host "Status: $($summary.Status)" -ForegroundColor $statusColor
Write-Host ""

# Exit codes: 0=Validated, 1=ValidationFailures/QueryFailed,
# 2=NoData/IncompleteCoverage/NotPromotionReady (non-zero: do not auto-promote)
if ($summary.Status -eq "ValidationFailures" -or $summary.Status -eq "QueryFailed") {
    exit 1
}
if ($summary.Status -eq "NoData" -or $summary.Status -eq "IncompleteCoverage" -or $summary.Status -eq "NotPromotionReady") {
    exit 2
}
}
