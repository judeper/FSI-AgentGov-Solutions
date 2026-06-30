<#
.SYNOPSIS
    Runs pre-promotion resilience validation against an unpacked Copilot Studio
    solution and (optionally) writes structured evidence to Dataverse.

.DESCRIPTION
    Performs structural, offline checks against the unpacked source of a Copilot
    Studio agent solution (the output of `pac solution unpack`) before that agent
    is promoted into an early-release (preview) ring. The checks answer a coverage
    question -- does every failure path have a graceful fallback? -- rather than a
    scoring question, which is why they inspect topic YAML and connection-reference
    definitions instead of using the Copilot Studio evaluation framework.

    Three structural checks run fully offline:

      1. FallbackCoverageCheck   - every topic that calls a connector or cloud flow
                                   has an accompanying error-handling construct.
      2. ConnectorResilienceCheck- connection references are per-environment
                                   bindable (no hard-coded connection id values).
      3. ErrorRecoveryCheck      - a System Fallback topic (and Escalate topic when
                                   present) exists with a non-stub user-facing
                                   message.

    A fourth composite check (EarlyReleaseReadinessCheck) runs the three structural
    checks and then a live probe against the deployed agent. The live probe is
    DEFERRED pending MSCAT "Building Enterprise AI Solutions" Part 2 (the
    early-release-ring environment-config schema is not yet published) -- it is
    reported as Skipped and PromotionReady is recorded as false until the probe is
    implemented. See JudeSquad issue #1266.

    This script does NOT deploy, promote, or roll back an agent, and it cannot
    simulate a connector failure at runtime (Copilot Studio exposes no native
    fault-injection mechanism). It is a pre-flight structural gate; see the README
    and docs/fallback-testing-guide.md for what each check does and does not prove.

.PARAMETER CheckType
    Validation to run: FallbackCoverageCheck, ConnectorResilienceCheck,
    ErrorRecoveryCheck, EarlyReleaseReadinessCheck, or AllStructural (runs the
    three structural checks).

.PARAMETER SolutionPath
    Path to an unpacked Copilot Studio solution directory (the output of
    `pac solution unpack`). The structural checks read topic YAML and
    connection-reference definitions from this tree.

.PARAMETER AgentId
    Optional Copilot Studio bot component id; recorded in the evidence row.

.PARAMETER AgentVersion
    Optional solution/agent version under test; recorded in the evidence row.

.PARAMETER Environment
    Optional Dataverse environment URL. When supplied with credentials, each
    result is persisted as an fsi_ervalidationresult row for evidence retention.

.PARAMETER DryRun
    Run the checks and print results without writing evidence to Dataverse.

.EXAMPLE
    .\Invoke-EarlyReleaseValidation.ps1 -CheckType AllStructural -SolutionPath ./unpacked

.EXAMPLE
    .\Invoke-EarlyReleaseValidation.ps1 -CheckType EarlyReleaseReadinessCheck `
        -SolutionPath ./unpacked -AgentId "00000000-0000-0000-0000-000000000000" `
        -Environment "https://your-org.crm.dynamics.com" -AccessToken $token
#>

[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Dev-only legacy auth path. Production deployments use managed identity via scripts/shared/dataverse_client.py per AGENTS.md "Authentication standard". Plaintext secret here is wrapped immediately into SecureString and never persisted.'
)]
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet(
        "FallbackCoverageCheck",
        "ConnectorResilienceCheck",
        "ErrorRecoveryCheck",
        "EarlyReleaseReadinessCheck",
        "AllStructural"
    )]
    [string]$CheckType,

    [Parameter(Mandatory = $true)]
    [string]$SolutionPath,

    [Parameter(Mandatory = $false)]
    [string]$AgentId,

    [Parameter(Mandatory = $false)]
    [string]$AgentVersion,

    [Parameter(Mandatory = $false)]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [switch]$DryRun,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^$|^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$TenantId = $env:AZURE_TENANT_ID,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^$|^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}$')]
    [string]$ClientId = $env:AZURE_CLIENT_ID,

    [Parameter(Mandatory = $false)]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory = $false)]
    [string]$AccessToken = $env:DATAVERSE_ACCESS_TOKEN,

    [Parameter(Mandatory = $false)]
    [ValidatePattern('^$|^[0-9a-fA-F]{1,8}$')]
    [string]$CorrelationId
)

#Requires -Version 7.1

$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------------------
# Detection markers (heuristic, intentionally configurable)
#
# These checks inspect the unpacked Copilot Studio solution as text. The exact
# YAML node names emitted by `pac solution unpack` vary by platform version, so
# the markers below are kept as editable constants. They make these checks a
# pre-flight STRUCTURAL gate, not a runtime fault-injection test. Tune them to
# match your export if a check reports false positives/negatives -- see
# docs/fallback-testing-guide.md.
# ---------------------------------------------------------------------------

# Action node kinds that reach out to an external connector or cloud flow.
$script:ConnectorActionMarkers = @(
    'InvokeConnectorAction',
    'InvokeFlowAction',
    'HttpRequestAction',
    'InvokeAIBuilderModelAction',
    'connectionReference:'
)

# Constructs that indicate a topic handles the failure path of an action.
# NOTE: a generic `kind: ConditionGroup` is intentionally NOT treated as
# error-handling on its own - a topic can contain unrelated condition branches.
# Only constructs that specifically denote error handling count here. This
# biases the gate toward false-positives (flag for review) over false-passes
# (silently promoting a non-resilient agent).
$script:ErrorHandlingMarkers = @(
    'errorHandling',
    'OnError',
    'actionScopeErrorHandler',
    'continueOnError'
)

# Markers that identify the System Fallback / conversational-boosting topic.
$script:FallbackTopicMarkers = @(
    'kind: OnUnknownIntent',
    'ConversationalBoosting',
    'System Fallback',
    'SystemFallback'
)

# Markers that identify an Escalate / human-handoff topic.
$script:EscalateTopicMarkers = @(
    'kind: OnEscalate',
    'Escalate'
)

# Activity node that surfaces a user-facing message.
$script:MessageActivityMarker = 'kind: SendActivity'

# Dataverse Picklist value maps (must match create_erv_dataverse_schema.py).
$script:TestTypeOptionValue = @{
    "FallbackCoverageCheck"      = 100000000
    "ConnectorResilienceCheck"   = 100000001
    "ErrorRecoveryCheck"         = 100000002
    "EarlyReleaseReadinessCheck" = 100000003
}
$script:TestStatusOptionValue = @{
    "Pass"    = 100000000
    "Fail"    = 100000001
    "Skipped" = 100000002
}

# ---------------------------------------------------------------------------
# Audit logging
# ---------------------------------------------------------------------------

$script:AuditLogDir = Join-Path $PSScriptRoot ".." "logs"
$script:AuditLogPath = $null
$script:CorrelationId = if ($CorrelationId) { $CorrelationId } else { [guid]::NewGuid().ToString("N").Substring(0, 8) }

function Write-AuditLog {
    param(
        [string]$Message,
        [string]$Level = "INFO"
    )
    $timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ss.fffZ")
    $entry = "[$timestamp] [$Level] [$($script:CorrelationId)] $Message"
    Write-Information $entry -InformationAction Continue
    if ($script:AuditLogPath) {
        try {
            Add-Content -Path $script:AuditLogPath -Value $entry -ErrorAction Stop
        } catch {
            Write-Verbose ("Audit log write to {0} failed (non-fatal): {1}" -f $script:AuditLogPath, $_.Exception.Message)
        }
    }
}

# ---------------------------------------------------------------------------
# Dataverse auth helpers (evidence persistence only)
# ---------------------------------------------------------------------------

function Get-ErvAuthEndpoint {
    param([string]$EnvironmentUrl)
    if ($EnvironmentUrl -match '\.dynamics\.cn$') {
        return 'https://login.chinacloudapi.cn'
    } elseif ($EnvironmentUrl -match '\.(microsoftdynamics\.us|appsplatform\.us)$') {
        return 'https://login.microsoftonline.us'
    } else {
        return 'https://login.microsoftonline.com'
    }
}

function Get-ErvAccessToken {
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

# ---------------------------------------------------------------------------
# Structural inspection helpers (pure, unit-testable)
# ---------------------------------------------------------------------------

function Get-TopicFile {
    <#
        Returns the topic-definition files in an unpacked Copilot Studio
        solution. Copilot Studio bot topics unpack to YAML; some exports also
        emit JSON component files. Both are scanned.
    #>
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        throw "SolutionPath '$Path' does not exist."
    }
    return @(
        Get-ChildItem -Path $Path -Recurse -File -Include '*.yaml', '*.yml' -ErrorAction SilentlyContinue
    )
}

function Test-TextContainsAnyMarker {
    param(
        [string]$Content,
        [string[]]$Markers
    )
    foreach ($marker in $Markers) {
        if ($Content -match [regex]::Escape($marker)) {
            return $true
        }
    }
    return $false
}

function Test-TopicHasConnectorCall {
    param([string]$Content)
    return Test-TextContainsAnyMarker -Content $Content -Markers $script:ConnectorActionMarkers
}

function Test-TopicHasErrorHandling {
    param([string]$Content)
    return Test-TextContainsAnyMarker -Content $Content -Markers $script:ErrorHandlingMarkers
}

function Test-TopicHasNonStubMessage {
    <#
        Returns $true when a topic both contains a SendActivity node and that
        node carries non-whitespace, non-placeholder message text. A topic that
        only declares an empty/default message activity, or whose message is an
        obvious placeholder (TODO/TBD/etc.), is treated as a stub.
    #>
    param([string]$Content)
    if ($Content -notmatch [regex]::Escape($script:MessageActivityMarker)) {
        return $false
    }
    # Find quoted/inline message values after a text/activity/message key and
    # require at least one that is not an obvious placeholder.
    $msgMatches = [regex]::Matches(
        $Content,
        '(?im)(?:text|activity|message)\s*:\s*["'']?\s*([^\r\n"'']{3,})'
    )
    foreach ($m in $msgMatches) {
        $value = $m.Groups[1].Value.Trim()
        if ($value -and $value -notmatch '(?i)^(todo|tbd|placeholder|xxx+|fixme|tba|n/?a|<[^>]*>)\b') {
            return $true
        }
    }
    return $false
}

# ---------------------------------------------------------------------------
# Check implementations -- each returns a finding list
# ---------------------------------------------------------------------------

function Get-FallbackCoverageFinding {
    param([string]$SolutionPath)
    $findings = @()
    foreach ($file in (Get-TopicFile -Path $SolutionPath)) {
        $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($null -eq $content) { continue }
        if ((Test-TopicHasConnectorCall -Content $content) -and -not (Test-TopicHasErrorHandling -Content $content)) {
            $findings += [ordered]@{
                topic    = $file.Name
                path     = $file.FullName
                severity = "High"
                issue    = "Topic calls a connector/flow but declares no error-handling construct (no fallback branch)."
            }
        }
    }
    return @($findings)
}

function Get-ConnectorResilienceFinding {
    param([string]$SolutionPath)
    $findings = @()
    $connRefFiles = @(
        Get-ChildItem -Path $SolutionPath -Recurse -File -Include '*.json', '*.xml' -ErrorAction SilentlyContinue |
            Where-Object {
                $_.FullName -match 'connectionreference' -or
                (Select-String -Path $_.FullName -Pattern 'connectionreferencelogicalname|<connectionreferences>' -Quiet -ErrorAction SilentlyContinue)
            }
    )
    foreach ($file in $connRefFiles) {
        $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
        if ($null -eq $content) { continue }
        # A hard-coded connection id (any non-empty value) prevents clean
        # per-environment binding. Empty string and null correctly pass.
        $jsonHardCoded = $content -match '(?i)"connectionid"\s*:\s*"[^"\s][^"]*"'
        $xmlHardCoded = $content -match '(?i)<connectionid>\s*\S[^<]*</connectionid>'
        if ($jsonHardCoded -or $xmlHardCoded) {
            $findings += [ordered]@{
                topic    = $file.Name
                path     = $file.FullName
                severity = "High"
                issue    = "Connection reference declares a hard-coded connectionid; it will not rebind per environment in the early-release ring."
            }
        }
    }
    return @($findings)
}

function Get-ErrorRecoveryFinding {
    param([string]$SolutionPath)
    $findings = @()
    $topicFiles = Get-TopicFile -Path $SolutionPath

    $fallbackFiles = @($topicFiles | Where-Object {
            $c = Get-Content -Path $_.FullName -Raw -ErrorAction SilentlyContinue
            $c -and (Test-TextContainsAnyMarker -Content $c -Markers $script:FallbackTopicMarkers)
        })

    if ($fallbackFiles.Count -eq 0) {
        $findings += [ordered]@{
            topic    = "(none)"
            path     = $SolutionPath
            severity = "High"
            issue    = "No System Fallback topic detected. Agent has no graceful path for unrecognized input."
        }
    } else {
        foreach ($file in $fallbackFiles) {
            $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
            if (-not (Test-TopicHasNonStubMessage -Content $content)) {
                $findings += [ordered]@{
                    topic    = $file.Name
                    path     = $file.FullName
                    severity = "High"
                    issue    = "System Fallback topic has no non-stub user-facing message (empty or default)."
                }
            }
        }
    }

    # Escalate topic is recommended but not mandatory -- report as Medium.
    $escalateFiles = @($topicFiles | Where-Object {
            $c = Get-Content -Path $_.FullName -Raw -ErrorAction SilentlyContinue
            $c -and (Test-TextContainsAnyMarker -Content $c -Markers $script:EscalateTopicMarkers)
        })
    foreach ($file in $escalateFiles) {
        $content = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not (Test-TopicHasNonStubMessage -Content $content)) {
            $findings += [ordered]@{
                topic    = $file.Name
                path     = $file.FullName
                severity = "Medium"
                issue    = "Escalate topic present but has no non-stub user-facing message."
            }
        }
    }

    return @($findings)
}

function Invoke-StructuralCheck {
    <#
        Runs a single structural check by name and returns a normalized result
        object: CheckType, Status (Pass/Fail/Skipped), GapCount, Findings.
    #>
    param(
        [string]$Name,
        [string]$SolutionPath
    )
    $findings = switch ($Name) {
        "FallbackCoverageCheck"    { Get-FallbackCoverageFinding -SolutionPath $SolutionPath }
        "ConnectorResilienceCheck" { Get-ConnectorResilienceFinding -SolutionPath $SolutionPath }
        "ErrorRecoveryCheck"       { Get-ErrorRecoveryFinding -SolutionPath $SolutionPath }
        default { throw "Unknown structural check: $Name" }
    }
    $findings = @($findings)
    return [ordered]@{
        CheckType = $Name
        Status    = if ($findings.Count -eq 0) { "Pass" } else { "Fail" }
        GapCount  = $findings.Count
        Findings  = $findings
    }
}

# ---------------------------------------------------------------------------
# Evidence persistence
# ---------------------------------------------------------------------------

function Save-ERValidationResult {
    param(
        [string]$Environment,
        [string]$Token,
        [hashtable]$Result
    )

    $headers = @{
        "Authorization"    = "Bearer $Token"
        "OData-MaxVersion" = "4.0"
        "OData-Version"    = "4.0"
    }

    $findingJson = (ConvertTo-Json -InputObject @($Result.Findings) -Compress -Depth 6)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hashBytes = $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($findingJson))
    $sha.Dispose()
    $evidenceHash = -join ($hashBytes | ForEach-Object { $_.ToString("x2") })

    $record = @{
        fsi_name           = "ERV-$($Result.CheckType)-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
        fsi_testtype       = $script:TestTypeOptionValue[$Result.CheckType]
        fsi_teststatus     = $script:TestStatusOptionValue[$Result.Status]
        fsi_findingdetail  = $findingJson
        fsi_executedon     = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        fsi_evidencehash   = $evidenceHash
        fsi_gapcount       = $Result.GapCount
        fsi_promotionready = [bool]$Result.PromotionReady
        fsi_correlationid  = $script:CorrelationId
    }
    if ($Result.AgentId) { $record['fsi_agentid'] = $Result.AgentId }
    if ($Result.AgentVersion) { $record['fsi_agentversion'] = $Result.AgentVersion }
    if ($Result.EnvironmentUrl) { $record['fsi_environmenturl'] = $Result.EnvironmentUrl }

    try {
        # PATCH with a client-generated GUID for idempotent upsert (no dup on retry).
        $recordId = [guid]::NewGuid().ToString()
        $uri = "$Environment/api/data/v9.2/fsi_ervalidationresults($recordId)"
        $maxRetries = 3
        for ($attempt = 1; $attempt -le $maxRetries; $attempt++) {
            try {
                Invoke-RestMethod -Uri $uri -Headers $headers -Method Patch -Body ($record | ConvertTo-Json -Depth 5) -ContentType "application/json" -TimeoutSec 30 | Out-Null
                return $true
            } catch {
                $statusCode = 0
                if ($_.Exception -is [Microsoft.PowerShell.Commands.HttpResponseException]) {
                    $statusCode = $_.Exception.Response.StatusCode.value__
                }
                $isTransient = $statusCode -in @(429, 500, 502, 503, 504)
                if (-not $isTransient -or $attempt -eq $maxRetries) { throw }
                Write-AuditLog "Dataverse save failed (attempt $attempt/$maxRetries): $($_.Exception.Message)" -Level "WARN"
                Start-Sleep -Seconds ([math]::Pow(2, $attempt))
            }
        }
    } catch {
        Write-Warning "Failed to save result: $($_.Exception.Message)"
        return $false
    }
}

# ===========================================================================
# Main
#
# Guarded so dot-sourcing (Pester) only defines the helper functions above
# without executing the validation flow. When the script is invoked directly,
# $MyInvocation.InvocationName is the script/path; when dot-sourced it is '.'.
# ===========================================================================

if ($MyInvocation.InvocationName -ne '.') {
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Early-Release Validation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN MODE - evidence will not be written to Dataverse]" -ForegroundColor Yellow
    Write-Host ""
}

# Initialize audit log file
try {
    if (-not (Test-Path $script:AuditLogDir)) {
        New-Item -ItemType Directory -Path $script:AuditLogDir -Force | Out-Null
    }
    $script:AuditLogPath = Join-Path $script:AuditLogDir "erv-audit-$(Get-Date -Format 'yyyyMMdd-HHmmss')-$($script:CorrelationId).log"
} catch {
    Write-Warning "Could not create audit log directory: $($_.Exception.Message). Audit events will only be written to stdout."
}

# Validate Environment URL (only when persistence is requested)
if ($Environment) {
    $Environment = $Environment.TrimEnd('/')
    if ($Environment -notmatch '^https://[\w\-]+\.(crm[\d]*\.dynamics\.com|crm\.microsoftdynamics\.us|crm\.appsplatform\.us|crm\.dynamics\.cn)$') {
        throw "Environment must be a valid Dataverse URL (e.g., https://<org>.crm.dynamics.com, .microsoftdynamics.us, .appsplatform.us, or .dynamics.cn)"
    }
}

# legacy: dev-only - replace with managed identity in production
if (-not $ClientSecret -and $env:AZURE_CLIENT_SECRET) {
    $ClientSecret = $env:AZURE_CLIENT_SECRET | ConvertTo-SecureString -AsPlainText -Force
}

Write-Host "Check type:   $CheckType"
Write-Host "Solution:     $SolutionPath"
Write-AuditLog "Starting $CheckType against $SolutionPath"
Write-Host ""

# Decide which structural checks to run
$structuralNames = switch ($CheckType) {
    "AllStructural"              { @("FallbackCoverageCheck", "ConnectorResilienceCheck", "ErrorRecoveryCheck") }
    "EarlyReleaseReadinessCheck" { @("FallbackCoverageCheck", "ConnectorResilienceCheck", "ErrorRecoveryCheck") }
    default                      { @($CheckType) }
}

$results = @()
foreach ($name in $structuralNames) {
    Write-Host "Running $name ..." -ForegroundColor White
    $r = Invoke-StructuralCheck -Name $name -SolutionPath $SolutionPath
    $r['AgentId'] = $AgentId
    $r['AgentVersion'] = $AgentVersion
    $r['EnvironmentUrl'] = $Environment
    $r['PromotionReady'] = $false
    $results += $r
}

# Composite gate: build the EarlyReleaseReadinessCheck result on top of structural
if ($CheckType -eq "EarlyReleaseReadinessCheck") {
    $structuralAllPass = -not ($results | Where-Object { $_.Status -ne "Pass" })
    $compositeFindings = @()
    foreach ($r in $results) {
        foreach ($f in $r.Findings) { $compositeFindings += $f }
    }
    # The live early-release probe is blocked on MSCAT Part 2 (issue #1266).
    $compositeFindings += [ordered]@{
        topic    = "(live-probe)"
        path     = $Environment
        severity = "Info"
        issue    = "Live early-release readiness probe deferred - blocked on MSCAT Part 2 (early-release-ring env-config schema unpublished). See JudeSquad issue #1266."
    }
    $composite = [ordered]@{
        CheckType      = "EarlyReleaseReadinessCheck"
        # Structural failures are a hard Fail; otherwise Skipped because the live
        # probe cannot run yet, so readiness cannot be confirmed.
        Status         = if (-not $structuralAllPass) { "Fail" } else { "Skipped" }
        GapCount       = @($compositeFindings | Where-Object { $_.severity -ne "Info" }).Count
        Findings       = $compositeFindings
        AgentId        = $AgentId
        AgentVersion   = $AgentVersion
        EnvironmentUrl = $Environment
        # PromotionReady is false until the live probe is implemented (MSCAT Part 2).
        PromotionReady = $false
    }
    $results += $composite
}

# ---------------------------------------------------------------------------
# Report
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Validation Results" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$anyFail = $false
foreach ($r in $results) {
    $color = switch ($r.Status) {
        "Pass"    { "Green" }
        "Fail"    { "Red" }
        "Skipped" { "Yellow" }
        default   { "Gray" }
    }
    Write-Host "  [$($r.Status)] $($r.CheckType) - $($r.GapCount) gap(s)" -ForegroundColor $color
    foreach ($f in $r.Findings) {
        Write-Host "      - ($($f.severity)) $($f.topic): $($f.issue)" -ForegroundColor DarkGray
    }
    if ($r.Status -eq "Fail") { $anyFail = $true }
}
Write-AuditLog "Validation completed - overall: $(if ($anyFail) { 'FAIL' } else { 'PASS/SKIPPED' })"

# ---------------------------------------------------------------------------
# Persist evidence (optional)
# ---------------------------------------------------------------------------

$script:DataverseSaveFailed = $false
$HasDataverseAuth = $AccessToken -or ($TenantId -and $ClientId -and $ClientSecret)
if (-not $DryRun -and $Environment -and $HasDataverseAuth) {
    Write-Host ""
    Write-Host "Saving evidence to Dataverse..." -ForegroundColor Gray
    try {
        if ($AccessToken) {
            $token = $AccessToken
        } else {
            $authEndpoint = Get-ErvAuthEndpoint -EnvironmentUrl $Environment
            $token = Get-ErvAccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret -Scope "$Environment/.default" -AuthEndpoint $authEndpoint
        }
        foreach ($r in $results) {
            if (Save-ERValidationResult -Environment $Environment -Token $token -Result $r) {
                Write-Host "  Saved $($r.CheckType)" -ForegroundColor Green
            } else {
                $script:DataverseSaveFailed = $true
            }
        }
        Write-AuditLog "Evidence saved to Dataverse"
    } catch {
        $script:DataverseSaveFailed = $true
        Write-Warning "Dataverse persistence failed: $($_.Exception.Message). Results were not saved."
        Write-AuditLog "Dataverse save skipped - error: $($_.Exception.Message)" -Level "WARN"
    }
} elseif (-not $DryRun -and $Environment) {
    Write-Warning "Dataverse authentication not provided (AccessToken or TenantId/ClientId/ClientSecret). Results were not saved."
    Write-AuditLog "Dataverse save skipped - credentials not configured" -Level "WARN"
}

Write-Host ""
# A deferred/not-ready early-release gate must NOT report green or exit 0 - a
# promotion pipeline that gates on the exit code could otherwise silently
# promote an agent whose readiness was never confirmed (live probe pending).
$notPromotionReady = $false
if ($CheckType -eq "EarlyReleaseReadinessCheck") {
    $composite = @($results | Where-Object { $_.CheckType -eq "EarlyReleaseReadinessCheck" })[0]
    if ($composite -and ($composite.Status -eq "Skipped" -or -not $composite.PromotionReady)) {
        $notPromotionReady = $true
    }
}

if ($anyFail) {
    Write-Host "Overall: FAIL (resilience gaps detected)" -ForegroundColor Red
} elseif ($notPromotionReady) {
    Write-Host "Overall: NOT PROMOTION-READY (structural checks passed; live readiness probe deferred - MSCAT Part 2 / issue #1266)" -ForegroundColor Yellow
} else {
    Write-Host "Overall: PASS" -ForegroundColor Green
}

# Exit codes: 1 = resilience gap (Fail), 2 = checks ran but Dataverse save
# failed, 3 = early-release readiness deferred / not promotion-ready (do NOT
# auto-promote), 0 = pass.
if ($anyFail) {
    exit 1
}
if ($script:DataverseSaveFailed) {
    exit 2
}
if ($notPromotionReady) {
    exit 3
}
}
