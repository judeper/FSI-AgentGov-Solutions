<#
.SYNOPSIS
    CI wrapper for the Power CAT Copilot Studio Kit evaluation gate.

.DESCRIPTION
    Drives the Power CAT Copilot Studio Kit's native test runner for a target agent
    and environment, reads rubric scores from Dataverse, and applies a config-driven
    PASS / SOFT-FAIL / HARD-FAIL gate decision.

    This wrapper does NOT reimplement Direct Line polling or the Kit's rubric scoring —
    those run inside the Kit. The wrapper's job is:
      1. Authenticate to Dataverse (service-principal + certificate)
      2. Pre-flight: verify Kit tables are reachable (HARD-FAIL if not)
      3. Find the requested test set(s) in Dataverse
      4. Create a test-run record and wait for the Kit to complete it
      5. Read aggregated category results from Dataverse
      6. Apply gate logic from eval-thresholds.json
      7. Emit a normalized result object (JSON file + stdout) and a clear exit code

    Promotion contexts:
      DevToTest  — HARD-FAIL blocks; SOFT-FAIL warns but continues
      TestToProd — HARD-FAIL and SOFT-FAIL both block

    Exit codes:
      0  — PASS (gate clears)
      1  — SOFT-FAIL (warn; DevToTest only)
      2  — HARD-FAIL (gate fails; also SOFT-FAIL in TestToProd context)

    Human-gated prerequisites (do NOT attempt from CI):
      - Install Power CAT Copilot Studio Kit in each Dataverse environment
      - Configure Direct Line channel for the target agent
      - Provision GitHub Actions environment secrets (CS_DIRECTLINE_SECRET_*, CS_CERT_THUMBPRINT_*)
      - Populate agentId, dataverseUrl, tenantId, clientId in configs/environments.json
      - Configure GitHub 'production' environment protection (required reviewer = judep_microsoft)

.PARAMETER Environment
    Target environment key: dev, test, or prod.
    Must match a key in configs/environments.json.

.PARAMETER TestSetId
    ID of the Kit test set to run. Pass the mspcat_testsetid GUID, the logical name
    (e.g., "safety-baseline-v1"), or "all" to run every registered test set.

.PARAMETER ThresholdsPath
    Path to eval-thresholds.json. Defaults to configs/eval-thresholds.json relative to
    this script.

.PARAMETER EnvironmentsPath
    Path to environments.json. Defaults to configs/environments.json relative to this
    script.

.PARAMETER PromotionContext
    Gate promotion context: DevToTest (default) or TestToProd.
    Controls whether SOFT-FAIL is blocking.

.PARAMETER DirectLineSecret
    Direct Line channel secret for the target agent. When omitted, read from the
    environment variable named in environments.json (CS_DIRECTLINE_SECRET_<ENV>).
    Never pass this on the command line in CI — use GitHub Actions environment secrets.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service-principal authentication to Dataverse.
    When omitted, read from the environment variable named in environments.json.

.PARAMETER PollIntervalSeconds
    Seconds between Dataverse status polls while waiting for the Kit test run.
    Default: 15. Minimum: 5.

.PARAMETER TimeoutSeconds
    Maximum seconds to wait for the Kit test run before HARD-FAIL.
    Default: 600 (10 min). Minimum: 60.

.PARAMETER OutputPath
    Path to write the normalized result JSON. Defaults to
    eval-gate-result-<env>-<yyyyMMddTHHmmss>.json in the current directory.

.PARAMETER WhatIf
    Preview mode. Performs authentication and pre-flight checks only; does not create
    test-run records or modify Dataverse state. Reports PASS if pre-flight succeeds.

.EXAMPLE
    .\Invoke-EvalGate.ps1 -Environment dev -TestSetId safety-baseline-v1

    Run the safety baseline against the dev environment with DevToTest gate logic.

.EXAMPLE
    .\Invoke-EvalGate.ps1 -Environment test -TestSetId all -PromotionContext TestToProd

    Run all registered test sets against test; both SOFT-FAIL and HARD-FAIL block.

.EXAMPLE
    .\Invoke-EvalGate.ps1 -Environment dev -TestSetId safety-baseline-v1 -WhatIf

    Pre-flight health check only — verifies auth and Kit connectivity; no test run.

.OUTPUTS
    [PSCustomObject] result object emitted to the pipeline.
    JSON file written to OutputPath.
    Exit code: 0 = PASS, 1 = SOFT-FAIL, 2 = HARD-FAIL.

.NOTES
    File:       eval-gate/Invoke-EvalGate.ps1
    Version:    1.0.0
    Tooling:    FSI-AgentGov-Solutions eval-gate (shared CI tooling)
    Engine:     Power CAT Copilot Studio Kit + native Agent Evaluation
    Requires:   PowerShell 7.0+; Power CAT Copilot Studio Kit installed in target env
    Regulations: FINRA 3110, SEC 17a-3/4, OCC 2011-12 / OCC Bulletin 2026-13

    Dataverse table assumptions (Power CAT Copilot Studio Kit v1.x schema):
      mspcat_testsets          — test set definitions
      mspcat_testcaseresults   — per-case results (linked to a run)
      mspcat_testrunresults    — run-level summary and per-category aggregates
    Adjust table/column names in the #region Dataverse Schema section if your Kit
    version uses different names.
#>

#Requires -Version 7.0

[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter(Mandatory)]
    [ValidateSet('dev', 'test', 'prod')]
    [string]$Environment,

    [Parameter(Mandatory)]
    [string]$TestSetId,

    [Parameter()]
    [string]$ThresholdsPath,

    [Parameter()]
    [string]$EnvironmentsPath,

    [Parameter()]
    [ValidateSet('DevToTest', 'TestToProd')]
    [string]$PromotionContext = 'DevToTest',

    [Parameter()]
    [string]$DirectLineSecret,

    [Parameter()]
    [string]$CertificateThumbprint,

    [Parameter()]
    [ValidateRange(5, 300)]
    [int]$PollIntervalSeconds = 15,

    [Parameter()]
    [ValidateRange(60, 3600)]
    [int]$TimeoutSeconds = 600,

    [Parameter()]
    [string]$OutputPath
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:Version     = '1.0.0'
$script:ScriptRoot  = $PSScriptRoot

#region Dataverse Schema
# Power CAT Copilot Studio Kit table and column names.
# Update these constants if your Kit version uses different names.
$schema = @{
    TestSetsTable       = 'mspcat_testsets'
    TestRunsTable       = 'mspcat_testrunresults'
    CaseResultsTable    = 'mspcat_testcaseresults'
    TestSetIdCol        = 'mspcat_testsetid'
    TestSetNameCol      = 'mspcat_name'
    RunStatusCol        = 'mspcat_status'
    RunCategoryCol      = 'mspcat_category'
    RunPassRateCol      = 'mspcat_passrate'
    RunCaseCountCol     = 'mspcat_casecount'
    RunPassCountCol     = 'mspcat_passcount'
    RunP95LatencyCol    = 'mspcat_p95latencyms'
    RunTestSetIdCol     = 'mspcat_testsetid'
    RunCompletedCol     = 'mspcat_completedon'
    # Status values for mspcat_testrunresults
    StatusQueued        = 'Queued'
    StatusRunning       = 'Running'
    StatusCompleted     = 'Completed'
    StatusFailed        = 'Failed'
}
#endregion

#region Banner
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║  FSI-AgentGov eval-gate  v$($script:Version)                          ║" -ForegroundColor Cyan
Write-Host "║  Power CAT Copilot Studio Kit CI wrapper                     ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "  Environment:       $Environment"
Write-Host "  Test Set:          $TestSetId"
Write-Host "  Promotion Context: $PromotionContext"
if ($WhatIfPreference) { Write-Host "  Mode:              DRY-RUN (no test runs will be triggered)" -ForegroundColor Yellow }
Write-Host ""
#endregion

#region Load Config

$defaultThresholdsPath   = Join-Path $script:ScriptRoot 'configs' 'eval-thresholds.json'
$defaultEnvironmentsPath = Join-Path $script:ScriptRoot 'configs' 'environments.json'

$thresholdsFile   = if ($ThresholdsPath)   { $ThresholdsPath }   else { $defaultThresholdsPath }
$environmentsFile = if ($EnvironmentsPath) { $EnvironmentsPath } else { $defaultEnvironmentsPath }

foreach ($f in @($thresholdsFile, $environmentsFile)) {
    if (-not (Test-Path $f)) {
        Write-Error "Config file not found: $f"
        exit 2
    }
}

$thresholds   = Get-Content $thresholdsFile   -Raw | ConvertFrom-Json
$environments = Get-Content $environmentsFile -Raw | ConvertFrom-Json

$envConfig = $environments.environments.$Environment
if (-not $envConfig) {
    Write-Error "Environment '$Environment' not found in $environmentsFile"
    exit 2
}

# Resolve secrets from environment variables when not provided directly
if (-not $CertificateThumbprint) {
    $thumbprintVarName = $envConfig.certThumbprintEnvVar
    $CertificateThumbprint = [System.Environment]::GetEnvironmentVariable($thumbprintVarName)
    if (-not $CertificateThumbprint) {
        Write-Error "Certificate thumbprint not provided and env var '$thumbprintVarName' is not set."
        exit 2
    }
}

if (-not $DirectLineSecret) {
    $dlSecretVarName = $envConfig.directLineSecretEnvVar
    $DirectLineSecret = [System.Environment]::GetEnvironmentVariable($dlSecretVarName)
    # Direct Line secret is not used by this wrapper directly (the Kit uses it),
    # but we verify it's configured so CI fails early if the secret is missing.
    if (-not $DirectLineSecret) {
        Write-Warning "Direct Line secret env var '$dlSecretVarName' is not set. The Kit test run will fail when it attempts to connect to the agent."
    }
}

$promotionRules = $thresholds.promotionRules.$PromotionContext
if (-not $promotionRules) {
    Write-Error "PromotionContext '$PromotionContext' not found in $thresholdsFile"
    exit 2
}

Write-Host "[Config] Thresholds loaded from: $thresholdsFile" -ForegroundColor Gray
Write-Host "[Config] Environment config loaded: $($envConfig.description)" -ForegroundColor Gray
Write-Host ""

#endregion

#region Auth Helpers

function Get-DataverseToken {
    <#
    .SYNOPSIS
        Acquires a Dataverse bearer token via service-principal certificate assertion.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$TenantId,
        [Parameter(Mandatory)] [string]$ClientId,
        [Parameter(Mandatory)] [string]$DataverseUrl,
        [Parameter(Mandatory)] [string]$Thumbprint
    )

    # Locate the certificate in the local machine or current user store
    $cert = Get-ChildItem Cert:\CurrentUser\My\$Thumbprint -ErrorAction SilentlyContinue
    if (-not $cert) {
        $cert = Get-ChildItem Cert:\LocalMachine\My\$Thumbprint -ErrorAction SilentlyContinue
    }
    if (-not $cert) {
        throw "Certificate with thumbprint '$Thumbprint' not found in CurrentUser\My or LocalMachine\My."
    }

    # Build a JWT client assertion signed with the certificate (RFC 7521 / MSAL pattern)
    $now     = [DateTimeOffset]::UtcNow
    $exp     = $now.AddMinutes(5)
    $jwtId   = [Guid]::NewGuid().ToString('N')
    $audience = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    $header = [Convert]::ToBase64String(
        [Text.Encoding]::UTF8.GetBytes(
            (ConvertTo-Json @{ alg = 'RS256'; typ = 'JWT'; x5t = [Convert]::ToBase64String($cert.GetCertHash()) } -Compress)
        )
    ).TrimEnd('=').Replace('+', '-').Replace('/', '_')

    $payload = [Convert]::ToBase64String(
        [Text.Encoding]::UTF8.GetBytes(
            (ConvertTo-Json @{
                aud = $audience
                iss = $ClientId
                sub = $ClientId
                jti = $jwtId
                nbf = $now.ToUnixTimeSeconds()
                exp = $exp.ToUnixTimeSeconds()
            } -Compress)
        )
    ).TrimEnd('=').Replace('+', '-').Replace('/', '_')

    $sigInput  = "$header.$payload"
    $rsa       = $cert.GetRSAPrivateKey()
    $sigBytes  = $rsa.SignData(
        [Text.Encoding]::ASCII.GetBytes($sigInput),
        [Security.Cryptography.HashAlgorithmName]::SHA256,
        [Security.Cryptography.RSASignaturePadding]::Pkcs1
    )
    $sig       = [Convert]::ToBase64String($sigBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    $assertion = "$sigInput.$sig"

    $resource = ($DataverseUrl.TrimEnd('/') -replace '/$', '') + '/'
    $body = @{
        grant_type            = 'client_credentials'
        client_id             = $ClientId
        client_assertion_type = 'urn:ietf:params:oauth:client-assertion-type:jwt-bearer'
        client_assertion      = $assertion
        scope                 = "$resource.default"
    }

    $tokenResponse = Invoke-RestMethod `
        -Uri     "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -Method  Post `
        -Body    $body `
        -ContentType 'application/x-www-form-urlencoded'

    return $tokenResponse.access_token
}

function Invoke-DataverseGet {
    [CmdletBinding()]
    param(
        [string]$DataverseUrl,
        [string]$Token,
        [string]$RelativeUri,
        [hashtable]$Headers = @{}
    )
    $uri = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2/$RelativeUri"
    $h   = @{
        Authorization    = "Bearer $Token"
        Accept           = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
    } + $Headers

    $resp = Invoke-RestMethod -Uri $uri -Headers $h -Method Get
    return $resp
}

function Invoke-DataversePost {
    [CmdletBinding()]
    param(
        [string]$DataverseUrl,
        [string]$Token,
        [string]$RelativeUri,
        [object]$Body
    )
    $uri  = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2/$RelativeUri"
    $json = $Body | ConvertTo-Json -Depth 10 -Compress
    $h    = @{
        Authorization      = "Bearer $Token"
        Accept             = 'application/json'
        'Content-Type'     = 'application/json; charset=utf-8'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
        Prefer             = 'return=representation'
    }
    $resp = Invoke-RestMethod -Uri $uri -Headers $h -Method Post -Body $json
    return $resp
}

#endregion

#region Pre-flight Health Check

Write-Host "── Pre-flight health check ─────────────────────────────────────" -ForegroundColor Cyan

$dataverseUrl = $envConfig.dataverseUrl
$tenantId     = $envConfig.tenantId
$clientId     = $envConfig.clientId

if (-not $dataverseUrl -or -not $tenantId -or -not $clientId) {
    Write-Error (@(
        "HARD-FAIL — environment configuration incomplete.",
        "  dataverseUrl, tenantId, and clientId must be populated in configs/environments.json.",
        "  These are human-gated prerequisites — see eval-gate/README.md."
    ) -join "`n")
    exit 2
}

$token = $null
try {
    Write-Host "  Authenticating to Dataverse ($dataverseUrl)..." -ForegroundColor Gray
    $token = Get-DataverseToken `
        -TenantId    $tenantId `
        -ClientId    $clientId `
        -DataverseUrl $dataverseUrl `
        -Thumbprint  $CertificateThumbprint
    Write-Host "  ✓ Authentication succeeded" -ForegroundColor Green
}
catch {
    Write-Error "HARD-FAIL — Dataverse authentication failed: $_"
    exit 2
}

try {
    Write-Host "  Verifying Kit tables ($($schema.TestSetsTable), $($schema.TestRunsTable))..." -ForegroundColor Gray
    $null = Invoke-DataverseGet `
        -DataverseUrl $dataverseUrl `
        -Token        $token `
        -RelativeUri  "$($schema.TestSetsTable)?`$top=1&`$select=$($schema.TestSetIdCol)"
    Write-Host "  ✓ Kit tables reachable" -ForegroundColor Green
}
catch {
    Write-Error @"
HARD-FAIL — Kit Dataverse tables not reachable.
  Attempted: GET $dataverseUrl/api/data/v9.2/$($schema.TestSetsTable)
  Error: $_

  This indicates the Power CAT Copilot Studio Kit is not installed in the '$Environment'
  Dataverse environment, or the service principal lacks read access to its tables.
  See eval-gate/README.md for human-gated prerequisites.
"@
    exit 2
}

Write-Host "  ✓ Pre-flight passed" -ForegroundColor Green
Write-Host ""

if ($WhatIfPreference) {
    Write-Host "WhatIf mode — stopping after pre-flight. No test run triggered." -ForegroundColor Yellow
    $result = [PSCustomObject]@{
        evalGateVersion  = $script:Version
        environment      = $Environment
        testSetId        = $TestSetId
        promotionContext = $PromotionContext
        verdict          = 'PASS'
        exitCode         = 0
        mode             = 'dry-run'
        timestamp        = (Get-Date -Format 'o')
        categories       = @()
        notes            = 'WhatIf mode — pre-flight only'
    }
    $result | ConvertTo-Json -Depth 10 | Write-Host
    exit 0
}

#endregion

#region Resolve Test Sets

Write-Host "── Resolving test sets ─────────────────────────────────────────" -ForegroundColor Cyan

$testSetsToRun = [System.Collections.Generic.List[PSObject]]::new()

if ($TestSetId -eq 'all') {
    $allSets = Invoke-DataverseGet `
        -DataverseUrl $dataverseUrl `
        -Token        $token `
        -RelativeUri  "$($schema.TestSetsTable)?`$select=$($schema.TestSetIdCol),$($schema.TestSetNameCol)"
    foreach ($s in $allSets.value) {
        $testSetsToRun.Add($s)
    }
    Write-Host "  Found $($testSetsToRun.Count) test set(s) in Dataverse" -ForegroundColor Gray
}
else {
    # Accept either a GUID or a logical name
    $isGuid = $TestSetId -match '^[0-9a-f]{8}-([0-9a-f]{4}-){3}[0-9a-f]{12}$'
    $filter  = if ($isGuid) {
        "$($schema.TestSetIdCol) eq '$TestSetId'"
    } else {
        "$($schema.TestSetNameCol) eq '$TestSetId'"
    }

    $found = Invoke-DataverseGet `
        -DataverseUrl $dataverseUrl `
        -Token        $token `
        -RelativeUri  "$($schema.TestSetsTable)?`$filter=$([Uri]::EscapeDataString($filter))&`$select=$($schema.TestSetIdCol),$($schema.TestSetNameCol)"

    if (-not $found.value -or $found.value.Count -eq 0) {
        Write-Error "HARD-FAIL — test set '$TestSetId' not found in $($schema.TestSetsTable). Upload the test set to the Kit before running CI."
        exit 2
    }
    $testSetsToRun.Add($found.value[0])
    Write-Host "  Resolved test set: $($found.value[0].$($schema.TestSetNameCol)) ($($found.value[0].$($schema.TestSetIdCol)))" -ForegroundColor Gray
}

Write-Host ""

#endregion

#region Trigger Kit Test Runs

Write-Host "── Triggering Kit test run(s) ──────────────────────────────────" -ForegroundColor Cyan

$runIds = [System.Collections.Generic.List[string]]::new()
$agentId = $envConfig.agentId

if (-not $agentId) {
    Write-Error "HARD-FAIL — agentId is not set in configs/environments.json for environment '$Environment'. This is a human-gated prerequisite."
    exit 2
}

foreach ($ts in $testSetsToRun) {
    $setId = $ts.$($schema.TestSetIdCol)
    Write-Host "  Submitting test run for set: $($ts.$($schema.TestSetNameCol)) ($setId)..." -ForegroundColor Gray

    $runRecord = @{
        $schema.RunStatusCol  = $schema.StatusQueued
        $schema.RunTestSetIdCol = $setId
        'mspcat_agentid'      = $agentId
        'mspcat_environment'  = $Environment
        'mspcat_triggeredby'  = 'eval-gate-ci'
        'mspcat_triggeredon'  = (Get-Date -Format 'o')
    }

    $createdRun = Invoke-DataversePost `
        -DataverseUrl $dataverseUrl `
        -Token        $token `
        -RelativeUri  $schema.TestRunsTable `
        -Body         $runRecord

    # Dataverse returns the primary key in the OData-EntityId header or in the response
    # depending on the Prefer header. Extract from the response or construct from known pattern.
    $runId = if ($createdRun.mspcat_testrunresultid) {
        $createdRun.mspcat_testrunresultid
    } elseif ($createdRun.'@odata.id') {
        # Extract GUID from OData ID URL
        $createdRun.'@odata.id' -replace ".*\('([^']+)'\).*", '$1'
    } else {
        throw "Could not extract run ID from Dataverse response. Response: $($createdRun | ConvertTo-Json -Compress)"
    }

    $runIds.Add($runId)
    Write-Host "  ✓ Run queued: $runId" -ForegroundColor Green
}

Write-Host ""

#endregion

#region Poll for Completion

Write-Host "── Waiting for test run(s) to complete ─────────────────────────" -ForegroundColor Cyan
Write-Host "   Polling every ${PollIntervalSeconds}s (timeout: ${TimeoutSeconds}s)" -ForegroundColor Gray
Write-Host ""

$deadline = [DateTimeOffset]::UtcNow.AddSeconds($TimeoutSeconds)
$completedRuns = [System.Collections.Generic.List[PSObject]]::new()

foreach ($runId in $runIds) {
    Write-Host "  Polling run $runId..." -ForegroundColor Gray
    $run = $null

    while ([DateTimeOffset]::UtcNow -lt $deadline) {
        # Re-authenticate if token may be near expiry (15 min runs are possible)
        if (-not $token) {
            $token = Get-DataverseToken -TenantId $tenantId -ClientId $clientId `
                -DataverseUrl $dataverseUrl -Thumbprint $CertificateThumbprint
        }

        $runResp = Invoke-DataverseGet `
            -DataverseUrl $dataverseUrl `
            -Token        $token `
            -RelativeUri  "$($schema.TestRunsTable)($runId)?`$select=$($schema.RunStatusCol),$($schema.RunCompletedCol)"

        $status = $runResp.$($schema.RunStatusCol)
        Write-Host "    Status: $status  [$(Get-Date -Format 'HH:mm:ss')]" -ForegroundColor Gray

        if ($status -eq $schema.StatusCompleted) {
            $run = $runResp
            break
        }
        if ($status -eq $schema.StatusFailed) {
            Write-Error "HARD-FAIL — Kit test run $runId ended with status 'Failed'. Check the Kit logs in Dataverse for details."
            exit 2
        }

        Start-Sleep -Seconds $PollIntervalSeconds
    }

    if (-not $run) {
        Write-Error "HARD-FAIL — Kit test run $runId did not complete within $TimeoutSeconds seconds."
        exit 2
    }

    $completedRuns.Add($run)
    Write-Host "  ✓ Run $runId completed" -ForegroundColor Green
}

Write-Host ""

#endregion

#region Read and Aggregate Results

Write-Host "── Reading category results ─────────────────────────────────────" -ForegroundColor Cyan

# For each completed run, read per-category aggregates from Dataverse.
# The Kit writes one result record per category per run, with category name,
# pass rate, case count, and (for latency) p95LatencyMs.

$categoryResults = [System.Collections.Generic.Dictionary[string, System.Collections.Generic.List[PSObject]]]::new()

foreach ($run in $completedRuns) {
    $setFilter = "$($schema.RunTestSetIdCol) eq '$($run.$($schema.RunTestSetIdCol))'"
    $catRows = Invoke-DataverseGet `
        -DataverseUrl $dataverseUrl `
        -Token        $token `
        -RelativeUri  ("$($schema.CaseResultsTable)?" +
                       "`$filter=$([Uri]::EscapeDataString($setFilter))" +
                       "&`$select=$($schema.RunCategoryCol),$($schema.RunPassRateCol)," +
                       "$($schema.RunCaseCountCol),$($schema.RunPassCountCol),$($schema.RunP95LatencyCol)")

    foreach ($row in $catRows.value) {
        $cat = $row.$($schema.RunCategoryCol)
        if (-not $categoryResults.ContainsKey($cat)) {
            $categoryResults[$cat] = [System.Collections.Generic.List[PSObject]]::new()
        }
        $categoryResults[$cat].Add($row)
    }
}

# If Dataverse has no per-category rows (Kit version variation), fall back to
# reading the run-level summary and treating it as a single "Overall" category.
if ($categoryResults.Count -eq 0) {
    Write-Warning "No per-category result rows found. Falling back to run-level summary as 'Overall'."
    foreach ($run in $completedRuns) {
        if (-not $categoryResults.ContainsKey('Overall')) {
            $categoryResults['Overall'] = [System.Collections.Generic.List[PSObject]]::new()
        }
        $categoryResults['Overall'].Add($run)
    }
}

# Build aggregated category summary (weighted average across multiple runs)
$aggregated = [ordered]@{}
foreach ($cat in $categoryResults.Keys) {
    $rows      = $categoryResults[$cat]
    $totalPass = ($rows | Measure-Object -Property $schema.RunPassCountCol -Sum).Sum
    $totalCase = ($rows | Measure-Object -Property $schema.RunCaseCountCol -Sum).Sum
    $passRate  = if ($totalCase -gt 0) { [Math]::Round($totalPass / $totalCase, 4) } else { 0 }
    $p95       = ($rows | Where-Object { $_.$($schema.RunP95LatencyCol) } |
                  Measure-Object -Property $schema.RunP95LatencyCol -Maximum).Maximum

    $aggregated[$cat] = [PSCustomObject]@{
        category  = $cat
        passRate  = $passRate
        passCount = $totalPass
        caseCount = $totalCase
        p95Latency = $p95
    }

    Write-Host ("  {0,-25} passRate={1:P1}  cases={2}  p95={3}ms" -f `
        $cat, $passRate, $totalCase, $(if ($p95) { $p95 } else { 'n/a' })) `
        -ForegroundColor Gray
}

Write-Host ""

#endregion

#region Gate Decision Logic

Write-Host "── Applying gate logic ($PromotionContext) ─────────────────────" -ForegroundColor Cyan

$categoryVerdicts  = [System.Collections.Generic.List[PSObject]]::new()
$overallVerdictStr = 'PASS'
$hardFailReasons   = [System.Collections.Generic.List[string]]::new()
$softFailReasons   = [System.Collections.Generic.List[string]]::new()

function Get-CategoryVerdict {
    param(
        [string]   $CategoryName,
        [PSObject] $ThresholdDef,
        [PSObject] $Actual
    )

    $advisory = $ThresholdDef.verdictOnSoftFail -eq 'advisory'

    # Safety: special case — also enforces minimum case count
    if ($CategoryName -eq 'Safety') {
        $minCount = $thresholds.minTestCount
        # Try the testSetMetadata minCaseCountRequired from the local safety test set
        $safetyTestFile = Join-Path $script:ScriptRoot 'test-sets' 'safety-baseline.json'
        if (Test-Path $safetyTestFile) {
            $stf = Get-Content $safetyTestFile -Raw | ConvertFrom-Json
            if ($stf.testSetMetadata.minCaseCountRequired) {
                $minCount = $stf.testSetMetadata.minCaseCountRequired
            }
        }

        if ($Actual.caseCount -lt $minCount) {
            return [PSCustomObject]@{
                category      = $CategoryName
                metric        = 'caseCount'
                actual        = $Actual.caseCount
                passThreshold = $minCount
                verdict       = 'HARD-FAIL'
                reason        = "Safety test set has $($Actual.caseCount) case(s); minimum required is $minCount."
                advisory      = $false
            }
        }
    }

    # Determine the metric to use
    $metricName   = $ThresholdDef.metric
    $actualValue  = if ($metricName -eq 'p95LatencyMs') { $Actual.p95Latency } else { $Actual.passRate }

    # Latency uses upper-bound semantics (lower is better)
    $isLatency = $metricName -eq 'p95LatencyMs'

    if ($advisory -or $null -eq $actualValue) {
        # Advisory — always PASS, but log the value
        $verdict = 'PASS'
        $reason  = if ($advisory) { 'Advisory — does not gate promotion.' } else { 'No data — advisory pass.' }
    }
    elseif ($isLatency) {
        $pass      = $ThresholdDef.passThreshold
        $softLimit = $ThresholdDef.softFailThreshold
        $verdict = if ($actualValue -le $pass)      { 'PASS' }
                   elseif ($actualValue -le $softLimit) { 'SOFT-FAIL' }
                   else                             { 'advisory' }   # latency is advisory per thresholds
        $reason = "p95=${actualValue}ms  (PASS<=${pass}ms; advisory>${softLimit}ms)"
    }
    else {
        $pass      = $ThresholdDef.passThreshold
        $soft      = $ThresholdDef.softFailThreshold
        $hard      = $ThresholdDef.hardFailThreshold

        $verdict = if ($actualValue -ge $pass)     { 'PASS' }
                   elseif ($null -ne $soft -and $actualValue -ge $soft) { 'SOFT-FAIL' }
                   else                            { 'HARD-FAIL' }

        $reason = ("passRate={0:P1}  (PASS>={1:P0}" -f $actualValue, $pass) +
                  $(if ($null -ne $soft) { "; SOFT-FAIL>={0:P0}" -f $soft } else { '' }) +
                  $(if ($null -ne $hard) { "; HARD-FAIL<{0:P0}" -f $hard } else { '' }) + ')'
    }

    return [PSCustomObject]@{
        category      = $CategoryName
        metric        = $metricName
        actual        = $actualValue
        passThreshold = $ThresholdDef.passThreshold
        verdict       = $verdict
        reason        = $reason
        advisory      = $advisory
    }
}

# Evaluate each configured threshold category against actual results
foreach ($catName in $thresholds.categories.PSObject.Properties.Name) {
    $thresholdDef = $thresholds.categories.$catName
    $actualData   = if ($aggregated.Contains($catName)) { $aggregated[$catName] } else { $null }

    if (-not $actualData) {
        # Category not present in results — HARD-FAIL for blocking categories, warn for advisory
        $isAdvisory = $thresholdDef.verdictOnSoftFail -eq 'advisory'
        $v = if ($isAdvisory) { 'PASS' } else { 'HARD-FAIL' }
        $r = if ($isAdvisory) { "No data — advisory skip." } else { "Category '$catName' not found in Kit results. Ensure the test set includes cases tagged with this category." }
        $categoryVerdicts.Add([PSCustomObject]@{
            category = $catName; metric = $thresholdDef.metric; actual = $null
            passThreshold = $thresholdDef.passThreshold; verdict = $v; reason = $r; advisory = $isAdvisory
        })
        continue
    }

    $cv = Get-CategoryVerdict -CategoryName $catName -ThresholdDef $thresholdDef -Actual $actualData
    $categoryVerdicts.Add($cv)
}

# Compute overall verdict
foreach ($cv in $categoryVerdicts) {
    $color = switch ($cv.verdict) {
        'PASS'       { 'Green'  }
        'SOFT-FAIL'  { 'Yellow' }
        'HARD-FAIL'  { 'Red'    }
        default      { 'Gray'   }
    }
    $advisory = if ($cv.advisory) { ' [advisory]' } else { '' }
    Write-Host ("  {0,-25} {1}{2}  — {3}" -f $cv.category, $cv.verdict, $advisory, $cv.reason) `
        -ForegroundColor $color

    if (-not $cv.advisory) {
        if ($cv.verdict -eq 'HARD-FAIL') { $hardFailReasons.Add("$($cv.category): $($cv.reason)") }
        if ($cv.verdict -eq 'SOFT-FAIL') { $softFailReasons.Add("$($cv.category): $($cv.reason)") }
    }
}

Write-Host ""

# Determine combined verdict from promotion rules
$blockingVerdicts = $promotionRules.blockingVerdicts
$softBehavior     = $promotionRules.softFailBehavior

if ($hardFailReasons.Count -gt 0) {
    $overallVerdictStr = 'HARD-FAIL'
}
elseif ($softFailReasons.Count -gt 0) {
    $overallVerdictStr = if ('SOFT-FAIL' -in $blockingVerdicts) { 'HARD-FAIL' } else { 'SOFT-FAIL' }
}
else {
    $overallVerdictStr = 'PASS'
}

$exitCode = switch ($overallVerdictStr) {
    'PASS'      { 0 }
    'SOFT-FAIL' { 1 }
    default     { 2 }   # HARD-FAIL
}

#endregion

#region Emit Result

$resultTs = Get-Date -Format 'yyyyMMddTHHmmss'

if (-not $OutputPath) {
    $OutputPath = "eval-gate-result-$($Environment)-$resultTs.json"
}

$resultObj = [PSCustomObject]@{
    evalGateVersion  = $script:Version
    environment      = $Environment
    testSetId        = $TestSetId
    promotionContext = $PromotionContext
    verdict          = $overallVerdictStr
    exitCode         = $exitCode
    timestamp        = (Get-Date -Format 'o')
    runIds           = @($runIds)
    categories       = @($categoryVerdicts)
    hardFailReasons  = @($hardFailReasons)
    softFailReasons  = @($softFailReasons)
    thresholdsFile   = $thresholdsFile
    notes            = $promotionRules.notes
}

$resultObj | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath -Encoding UTF8
Write-Host "[Result] Written to: $OutputPath" -ForegroundColor Gray
Write-Host ""

# Final verdict banner
Write-Host "══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
$verdictColor = switch ($overallVerdictStr) {
    'PASS'      { 'Green'  }
    'SOFT-FAIL' { 'Yellow' }
    default     { 'Red'    }
}
Write-Host "  GATE VERDICT: $overallVerdictStr  (exit $exitCode)" -ForegroundColor $verdictColor
Write-Host "══════════════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""

if ($hardFailReasons.Count -gt 0) {
    Write-Host "HARD-FAIL reasons:" -ForegroundColor Red
    $hardFailReasons | ForEach-Object { Write-Host "  • $_" -ForegroundColor Red }
    Write-Host ""
}
if ($softFailReasons.Count -gt 0) {
    Write-Host "SOFT-FAIL reasons ($PromotionContext — $softBehavior):" -ForegroundColor Yellow
    $softFailReasons | ForEach-Object { Write-Host "  • $_" -ForegroundColor Yellow }
    Write-Host ""
}

# Return the result object to the pipeline
$resultObj

exit $exitCode

#endregion
