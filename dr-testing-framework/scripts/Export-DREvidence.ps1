<#
.SYNOPSIS
    Exports DR test evidence for compliance reporting.

.DESCRIPTION
    Collects and packages DR test results, audit logs, and validation data
    into compliance evidence artifacts. Supports export to JSON files for
    regulatory review (OCC, FFIEC, SEC 17a-4, FINRA 4370).

    When Dataverse credentials are provided (TenantId/ClientId/ClientSecret),
    queries fsi_drtestresults for test execution records and computes
    compliance metrics. Generates a SHA-256 hash companion file for
    tamper-evident evidence packaging.

.PARAMETER Environment
    Dataverse environment URL to query test results from.

.PARAMETER OutputDir
    Directory to write evidence files to. Defaults to ./evidence.

.PARAMETER TestRunId
    Optional correlation ID to filter results to a specific test run.

.EXAMPLE
    .\Export-DREvidence.ps1 -Environment "https://contoso.crm.dynamics.com" -OutputDir "./evidence"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [string]$OutputDir = (Join-Path $PSScriptRoot ".." "evidence"),

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^[0-9a-zA-Z\-]+$')]
    [string]$TestRunId,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^$|^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^$|^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter(Mandatory = $false)]
    [SecureString]$ClientSecret
)

#Requires -Version 7.0

# Convert AZURE_CLIENT_SECRET env var to SecureString if parameter not provided
if (-not $ClientSecret -and $env:AZURE_CLIENT_SECRET) {
    $ClientSecret = $env:AZURE_CLIENT_SECRET | ConvertTo-SecureString -AsPlainText -Force
}

$ErrorActionPreference = "Stop"

function Get-EvidenceAuthEndpoint {
    param([string]$EnvironmentUrl)
    if ($EnvironmentUrl -match '\.dynamics\.cn$') {
        return 'https://login.chinacloudapi.cn'
    } elseif ($EnvironmentUrl -match '\.(microsoftdynamics\.us|appsplatform\.us)$') {
        return 'https://login.microsoftonline.us'
    } else {
        return 'https://login.microsoftonline.com'
    }
}

function Get-EvidenceAccessToken {
    param([string]$TenantId, [string]$ClientId, [SecureString]$ClientSecret, [string]$Scope, [string]$AuthEndpoint)
    $plainSecret = [System.Net.NetworkCredential]::new('', $ClientSecret).Password
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
    }
}

# Normalize and validate Environment URL to prevent SSRF / token exfiltration
# Sovereign cloud auth resolution handled by Get-EvidenceAuthEndpoint below.
$Environment = $Environment.TrimEnd('/')
if ($Environment -notmatch '^https://[\w\-]+\.(crm[\d]*\.dynamics\.com|crm\.microsoftdynamics\.us|crm\.appsplatform\.us|crm\.dynamics\.cn)$') {
    throw "Environment must be a valid Dataverse URL (e.g., https://<org>.crm.dynamics.com, .microsoftdynamics.us, .appsplatform.us, or .dynamics.cn)"
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  DR Evidence Export" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Ensure output directory exists
if (-not (Test-Path $OutputDir)) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# Collect audit log files
$auditLogDir = Join-Path $PSScriptRoot ".." "logs"
$auditLogs = @()
if (Test-Path $auditLogDir) {
    $logFilter = if ($TestRunId) { "dr-audit-*-$TestRunId.log" } else { "dr-audit-*.log" }
    $auditLogs = Get-ChildItem -Path $auditLogDir -Filter $logFilter -ErrorAction SilentlyContinue
}

# Build evidence package metadata
$evidencePackage = @{
    ExportedAt   = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    Environment  = $Environment
    TestRunId    = if ($TestRunId) { $TestRunId } else { "all" }
    AuditLogFiles = @($auditLogs | ForEach-Object { $_.Name })
}

# Query Dataverse for test results if credentials are available
$testResults = @()
$metrics = @{}
$gaps = @()
$evidenceStatus = "NoCredentials"

if ($TenantId -and $ClientId -and $ClientSecret) {
    try {
        Write-Host "  Authenticating to Dataverse..." -ForegroundColor Gray
        $authEndpoint = Get-EvidenceAuthEndpoint -EnvironmentUrl $Environment
        $token = Get-EvidenceAccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$Environment/.default" -AuthEndpoint $authEndpoint
        $dvHeaders = @{
            "Authorization" = "Bearer $token"
            "OData-MaxVersion" = "4.0"
            "OData-Version" = "4.0"
            "Accept" = "application/json"
            "Prefer" = "odata.include-annotations=*"
        }

        # Build OData filter
        $filter = ""
        if ($TestRunId) {
            $filter = "fsi_correlationid eq '$TestRunId'"
        }

        $queryUri = "$Environment/api/data/v9.2/fsi_drtestresults?`$select=fsi_drtestresultid,fsi_testtype,fsi_executedon,fsi_actualrto,fsi_targetrto,fsi_rtomet,fsi_status,fsi_validationchecks,fsi_correlationid&`$orderby=fsi_executedon desc"
        if ($filter) { $queryUri += "&`$filter=$filter" }

        Write-Host "  Querying Dataverse for test results (paginated)..." -ForegroundColor Gray
        $rawResults = @()
        $pageCount = 0
        $nextUri = $queryUri
        while ($nextUri) {
            $pageCount++
            $queryResp = Invoke-RestMethod -Uri $nextUri -Headers $dvHeaders -Method Get -ContentType "application/json" -TimeoutSec 60
            if ($queryResp.value) { $rawResults += $queryResp.value }
            $nextUri = $queryResp.'@odata.nextLink'
            if ($pageCount -gt 200) {
                Write-Warning "Pagination exceeded 200 pages — aborting to avoid runaway. Narrow the query with -TestRunId."
                break
            }
        }
        Write-Verbose "Retrieved $($rawResults.Count) record(s) across $pageCount page(s)"

        if ($rawResults -and $rawResults.Count -gt 0) {
            # Map results to evidence format. NOTE (v2.0.0): the Dataverse columns are reused but their semantics changed
            # in v2.0.0 — fsi_actualrto now stores ProbeDurationHours (validation duration), fsi_targetrto stores
            # ProbeDurationTargetHours (validation budget), and fsi_rtomet stores ProbeWithinBudget. See README and CHANGELOG.
            $testResults = @($rawResults | ForEach-Object {
                @{
                    Id                       = $_.fsi_drtestresultid
                    TestType                 = $_.fsi_testtype
                    ExecutedOn               = $_.fsi_executedon
                    ProbeDurationHours       = $_.fsi_actualrto
                    ProbeDurationTargetHours = $_.fsi_targetrto
                    ProbeWithinBudget        = $_.fsi_rtomet
                    Status                   = if ($_.fsi_status -eq 1) { "Pass" } else { "Fail" }
                    CorrelationId            = $_.fsi_correlationid
                }
            })

            # Aggregate metrics
            $totalTests = $testResults.Count
            $passedTests = @($testResults | Where-Object { $_.Status -eq "Pass" }).Count
            $failedTests = $totalTests - $passedTests
            $probeValues = @($testResults | Where-Object { $null -ne $_.ProbeDurationHours } | ForEach-Object { $_.ProbeDurationHours })
            $avgProbeDuration = if ($probeValues.Count -gt 0) { [math]::Round(($probeValues | Measure-Object -Average).Average, 4) } else { $null }
            $probeWithinBudget = @($testResults | Where-Object { $_.ProbeWithinBudget -eq $true }).Count

            $metrics = @{
                TotalTests              = $totalTests
                Passed                  = $passedTests
                Failed                  = $failedTests
                PassRate                = if ($totalTests -gt 0) { [math]::Round(($passedTests / $totalTests) * 100, 1) } else { 0 }
                AvgProbeDurationHours   = $avgProbeDuration
                ProbeWithinBudgetCount  = $probeWithinBudget
                ProbeBudgetComplianceRate = if ($totalTests -gt 0) { [math]::Round(($probeWithinBudget / $totalTests) * 100, 1) } else { 0 }
            }

            # Identify gaps: failed tests and test types never run
            $gaps = @($testResults | Where-Object { $_.Status -eq "Fail" } | ForEach-Object {
                @{
                    TestType                 = $_.TestType
                    ExecutedOn               = $_.ExecutedOn
                    ProbeDurationHours       = $_.ProbeDurationHours
                    ProbeDurationTargetHours = $_.ProbeDurationTargetHours
                    Issue                    = "Validation failed — see audit log for details"
                }
            })

            # Test-type names accept both v1.x legacy values and v2.0.0 names
            $allTestTypes = @(
                "AgentReadinessCheck","EnvironmentReachabilityCheck","DataverseAccessCheck","FullValidation",
                "AgentRestore","EnvironmentFailover","DataRecovery","FullDR"
            )
            $executedTypes = @($testResults | ForEach-Object { $_.TestType } | Sort-Object -Unique)
            # Collapse legacy names to their v2 equivalents for "missing" detection
            $aliasMap = @{
                "AgentRestore"="AgentReadinessCheck";"EnvironmentFailover"="EnvironmentReachabilityCheck";
                "DataRecovery"="DataverseAccessCheck";"FullDR"="FullValidation"
            }
            $normalisedExecuted = @($executedTypes | ForEach-Object { if ($aliasMap.ContainsKey($_)) { $aliasMap[$_] } else { $_ } } | Sort-Object -Unique)
            $expectedTypes = @("AgentReadinessCheck","EnvironmentReachabilityCheck","DataverseAccessCheck","FullValidation")
            $missingTypes = @($expectedTypes | Where-Object { $_ -notin $normalisedExecuted })
            foreach ($missing in $missingTypes) {
                $gaps += @{
                    TestType = $missing
                    Issue    = "Validation type never executed in this evidence window — required for FFIEC BCP / FINRA 4370 evidence"
                }
            }

            $evidenceStatus = if ($failedTests -eq 0 -and $missingTypes.Count -eq 0) { "Validated" }
                              elseif ($failedTests -gt 0) { "ValidationFailures" }
                              else { "IncompleteValidationCoverage" }

            Write-Host "  Retrieved $totalTests validation result(s) ($passedTests passed, $failedTests failed)" -ForegroundColor Green
        } else {
            $evidenceStatus = "NoData"
            Write-Host "  No validation results found in Dataverse" -ForegroundColor Yellow
        }
    } catch {
        $evidenceStatus = "QueryFailed"
        Write-Warning "Dataverse query failed: $($_.Exception.Message)"
    }
} else {
    Write-Warning "Dataverse credentials not provided. Evidence export includes audit logs only."
}

# Populate evidence package with queried data
$evidencePackage.TestResults = $testResults
$evidencePackage.Metrics = $metrics
$evidencePackage.Gaps = $gaps
$evidencePackage.Status = $evidenceStatus

$outputPath = Join-Path $OutputDir "dr-evidence-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
$jsonContent = $evidencePackage | ConvertTo-Json -Depth 5
$jsonContent | Set-Content -Path $outputPath -Encoding utf8

# Compute SHA-256 hash of the evidence JSON for tamper detection
$sha = [System.Security.Cryptography.SHA256]::Create()
$hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($jsonContent))
$hashHex = -join ($hashBytes | ForEach-Object { $_.ToString("x2") })
$sha.Dispose()
$hashPath = "$outputPath.sha256"
"$hashHex  $(Split-Path $outputPath -Leaf)" | Set-Content -Path $hashPath -Encoding utf8
Write-Host "  SHA-256 hash written to: $hashPath" -ForegroundColor Green

# Copy audit logs into evidence directory
if ($auditLogs.Count -gt 0) {
    $logsDestDir = Join-Path $OutputDir "audit-logs"
    if (-not (Test-Path $logsDestDir)) {
        New-Item -ItemType Directory -Path $logsDestDir -Force | Out-Null
    }
    foreach ($log in $auditLogs) {
        Copy-Item -Path $log.FullName -Destination $logsDestDir -Force
    }
    Write-Host "  Copied $($auditLogs.Count) audit log file(s) to evidence package" -ForegroundColor Green
} else {
    Write-Host "  No audit log files found" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "Evidence package written to: $outputPath" -ForegroundColor Green
$statusColor = switch ($evidenceStatus) {
    "Validated"                     { 'Green' }
    "ValidationFailures"            { 'Red' }
    "IncompleteValidationCoverage"  { 'Yellow' }
    "NoData"                        { 'Yellow' }
    "QueryFailed"                   { 'Red' }
    default                         { 'Yellow' }
}
Write-Host "Status: $evidenceStatus" -ForegroundColor $statusColor
Write-Host ""

# Exit codes: 0=Validated, 1=ValidationFailures or QueryFailed (hard failure), 2=NoData / IncompleteValidationCoverage (warning)
if ($evidenceStatus -eq "ValidationFailures" -or $evidenceStatus -eq "QueryFailed") {
    exit 1
}
if ($evidenceStatus -eq "NoData" -or $evidenceStatus -eq "IncompleteValidationCoverage") {
    exit 2
}
