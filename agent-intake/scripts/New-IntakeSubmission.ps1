<#
.SYNOPSIS
    Creates a pristine "Submitted" agent-intake request row to trigger the router flow (Flow 1).

.DESCRIPTION
    Functional-verification driver for the agent-intake lab. Reads one of the scenario
    fixtures under scripts/seed-test-data/ and writes a NEW fsi_intakerequest row that
    contains only the maker-supplied inputs (agent details, sponsor, the T1-T6 trigger
    answers, declared data sources) with fsi_status = Submitted (100000001) and no router
    output columns (fsi_pathused, fsi_risktier, fsi_zone, fsi_decisionpath, ...).

    The seeded fixtures created by seed-test-data.ps1 land in terminal states for the
    reviewer-app and smoke checks; they do NOT exercise the router. This helper produces a
    clean submission so Flow 1 (fsi-intake-router) fires its "row added/modified AND
    fsi_status = Submitted AND blank fsi_decisionpath" trigger and performs the routing
    itself. Use it to drive the live demo-script scenes once the flows are built.

    A fresh fsi_requestid GUID is generated on every run (unless -RequestId is supplied) so
    repeated submissions never collide on the alternate key. The created row's GUID and
    request id are returned for downstream verification.

    Authentication follows the lab standard: an Azure CLI access token for the target
    environment (az login) or a DATAVERSE_ACCESS_TOKEN environment variable. This helps meet
    the unattended-auth posture used throughout the lab harness.

.PARAMETER Scenario
    Which fixture to submit. One of the request-*.json scenarios under scripts/seed-test-data/.

.PARAMETER EnvironmentUrl
    Dataverse environment URL, for example https://<your-env>.crm.dynamics.com/.

.PARAMETER RequestId
    Optional explicit fsi_requestid (GUID string). When omitted a new GUID is generated.

.PARAMETER RemoveAfter
    Create the row, report it, then delete it. Useful for validating the helper itself
    without leaving an orphan row when the router flow is not yet built.

.PARAMETER PreClassify
    Also stamp the validated router outputs (fsi_pathused, fsi_risktier, fsi_zone,
    fsi_routingtopology, fsi_quorumrequired, fsi_decisionpath, fsi_mrmrequired) from the
    fixture's expectedClassification/expectedOutcome. Use this for the vertical-slice
    "Option C" flow build, where the router triggers on fsi_status = Submitted and
    orchestrates (status transition, self-approval override, fan-out) without re-running the
    already-proven classifier. The reviewer board (fsi_parallelreviewersjson) is intentionally
    left to the Flow 4 build.

.PARAMETER SponsorUpn
    Override the fixture's fsi_sponsorupn with a real tenant UPN. Use this for live
    Teams-approval testing (Flow 3 sponsor card) so the adaptive card is delivered to a
    real mailbox, e.g. -SponsorUpn admin@example.com.

.PARAMETER MakerUpn
    Override the fixture's fsi_makerupn with a real tenant UPN. Keep the maker distinct from
    the sponsor to avoid the router's self-approval default-deny, or set both equal to
    exercise the self-approval deny branch.

.PARAMETER ReviewersJson
    Populate fsi_parallelreviewersjson on the created row (PATCHed after creation) so the
    F4 (parallel-reviewers) flow can iterate. Pass a JSON array of {role, upn, quorumWeight}
    objects, e.g.:
        -ReviewersJson '[{"role":"InfoSec","upn":"admin@example.com","quorumWeight":1}]'
    fsi_quorumrequired is bumped to the sum of weights (or count of reviewers, default
    weight 1 each). Only meaningful for standard-conditional / full-parallel-board scenarios;
    ignored for express-happy.

.PARAMETER DryRun
    Print the payload and the target request without writing to Dataverse.

.EXAMPLE
    ./New-IntakeSubmission.ps1 -Scenario express-happy -EnvironmentUrl https://<your-env>.crm.dynamics.com/

    Submits a clean Express-path intake request and prints the new request id.

.EXAMPLE
    ./New-IntakeSubmission.ps1 -Scenario standard-conditional -EnvironmentUrl https://<your-env>.crm.dynamics.com/ -RemoveAfter

    Validates the helper end to end (create + verify + delete) without leaving a row behind.

.NOTES
    Logical column names follow the agent-intake schema (create_fsi_intake_dataverse_schema.py).
    fsi_intendedaudience is a string column; fsi_agenttype is a choice; the T1-T6 answers are
    'Yes'/'No' strings; fsi_makerattestation and fsi_privacyoverride are booleans.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true)]
    [ValidateSet('express-happy', 'standard-conditional', 'full-parallel-board', 'cross-border-deny', 'sponsor-self-approval-deny')]
    [string]$Scenario,

    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$EnvironmentUrl,

    [Parameter()]
    [ValidatePattern('^[0-9a-fA-F-]{36}$')]
    [string]$RequestId,

    [Parameter()]
    [switch]$RemoveAfter,

    [Parameter()]
    [switch]$PreClassify,

    [Parameter()]
    [string]$SponsorUpn,

    [Parameter()]
    [string]$MakerUpn,

    [Parameter()]
    [string]$ReviewersJson,

    [Parameter()]
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# fsi_intake_agenttype choice values (see create_fsi_intake_dataverse_schema.py / seed-test-data.ps1).
$script:AgentTypeChoiceMap = @{
    'Agent Builder (M365 Copilot)'      = 100000000
    'Copilot Studio (classic)'          = 100000001
    'Declarative Agent (M365 Copilot)'  = 100000002
    'Custom Engine Agent'               = 100000003
}

# Maker-input columns copied verbatim from the fixture's fsi_intakerequest block. Router
# outputs are intentionally excluded so the router computes them.
$script:MakerStringColumns = @(
    'fsi_agentdisplayname', 'fsi_businessoutcome', 'fsi_businessjustification',
    'fsi_makerupn', 'fsi_makerdepartment', 'fsi_makercountry', 'fsi_makerdisplayname',
    'fsi_makerjobtitle', 'fsi_sponsorupn', 'fsi_intendedaudience',
    'fsi_t1initiatesfinancialtxn', 'fsi_t2customerfacing', 'fsi_t3autonomousunmonitored',
    'fsi_t4handlesnpi', 'fsi_t5handlesmnpi', 'fsi_t6crossborderdata',
    'fsi_dataresidencycountry'
)
$script:MakerBoolColumns = @('fsi_makerattestation', 'fsi_privacyoverride')

$script:SubmittedStatusValue = 100000001

# Option-set values used by -PreClassify to stamp the router outputs (see
# create_fsi_intake_dataverse_schema.py / seed-test-data.ps1).
$script:PathUsedChoiceMap = @{ 'Express' = 100000000; 'Standard' = 100000001; 'Full' = 100000002 }
$script:RiskTierChoiceMap = @{ 'Tier 1 (High)' = 100000000; 'Tier 2 (Medium)' = 100000001; 'Tier 3 (Low)' = 100000002 }
$script:ZoneChoiceMap = @{ 'Unclassified' = 100000000; 'Zone 1 (Enterprise)' = 100000001; 'Zone 2 (Team)' = 100000002; 'Zone 3 (Personal)' = 100000003 }
$script:RoutingTopologyChoiceMap = @{ 'Sequential' = 100000000; 'Parallel' = 100000001; 'Quorum' = 100000002 }
# Router topology per path (mirrors Get-RoutingTopologyLabel in seed-test-data.ps1).
$script:PathToTopologyMap = @{ 'Express' = 'Sequential'; 'Standard' = 'Quorum'; 'Full' = 'Parallel' }

function Get-DataverseAccessToken {
    if (-not [string]::IsNullOrWhiteSpace($env:DATAVERSE_ACCESS_TOKEN)) {
        return $env:DATAVERSE_ACCESS_TOKEN.Trim()
    }

    $az = Get-Command -Name 'az' -ErrorAction SilentlyContinue
    if ($null -eq $az) {
        throw 'Could not acquire a Dataverse access token. Run az login or set DATAVERSE_ACCESS_TOKEN.'
    }

    $token = & $az.Source account get-access-token --resource $EnvironmentUrl --query accessToken -o tsv 2>$null
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($token)) {
        throw "Azure CLI token acquisition failed for $EnvironmentUrl. Run az login."
    }

    return $token.Trim()
}

function Invoke-DataverseRequest {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST', 'DELETE', 'PATCH')][string]$Method,
        [Parameter(Mandatory = $true)][string]$RelativeUri,
        [Parameter()][object]$Body,
        [Parameter()][hashtable]$ExtraHeaders
    )

    $uri = '{0}/api/data/v9.2/{1}' -f $EnvironmentUrl.TrimEnd('/'), $RelativeUri.TrimStart('/')
    $headers = @{
        Authorization      = "Bearer $(Get-DataverseAccessToken)"
        Accept             = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
    }
    if ($ExtraHeaders) { $ExtraHeaders.GetEnumerator() | ForEach-Object { $headers[$_.Key] = $_.Value } }

    $params = @{ Method = $Method; Uri = $uri; Headers = $headers; TimeoutSec = 60 }
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        $params['Body'] = ConvertTo-Json -InputObject $Body -Depth 20 -Compress
        $params['ContentType'] = 'application/json; charset=utf-8'
    }

    return Invoke-RestMethod @params
}

function ConvertTo-DeclaredDataSourcesJson {
    param([Parameter()][object[]]$DataSources)

    if ($null -eq $DataSources -or $DataSources.Count -eq 0) { return $null }

    $items = foreach ($source in $DataSources) {
        [ordered]@{
            name                 = [string]$source.name
            type                 = [string]$source.type
            classification       = [string]$source.classification
            isCustomerData       = [bool]$source.isCustomerData
            isRestricted         = [bool]$source.isRestricted
            dataResidencyCountry = [string]$source.dataResidencyCountry
        }
    }

    return (ConvertTo-Json -InputObject @($items) -Depth 10 -Compress)
}

function ConvertTo-SubmissionPayload {
    param(
        [Parameter(Mandatory = $true)][psobject]$Fixture,
        [Parameter(Mandatory = $true)][string]$ResolvedRequestId,
        [Parameter()][switch]$PreClassify
    )

    $request = $Fixture.fsi_intakerequest
    $payload = [ordered]@{}

    foreach ($column in $script:MakerStringColumns) {
        if ($request.PSObject.Properties.Name -contains $column) {
            $payload[$column] = [string]$request.$column
        }
    }
    foreach ($column in $script:MakerBoolColumns) {
        if ($request.PSObject.Properties.Name -contains $column) {
            $payload[$column] = [bool]$request.$column
        }
    }

    $agentTypeLabel = [string]$request.fsi_agenttype
    if (-not $script:AgentTypeChoiceMap.ContainsKey($agentTypeLabel)) {
        throw "Unknown fsi_agenttype label '$agentTypeLabel' in fixture $Scenario."
    }
    $payload['fsi_agenttype'] = $script:AgentTypeChoiceMap[$agentTypeLabel]

    $declaredSources = $null
    if ($Fixture.PSObject.Properties.Name -contains 'dataSources') {
        $declaredSources = ConvertTo-DeclaredDataSourcesJson -DataSources $Fixture.dataSources
    }
    if ($declaredSources) { $payload['fsi_declareddatasourcesjson'] = $declaredSources }

    $payload['fsi_requestid'] = $ResolvedRequestId
    $payload['fsi_name'] = "Submit - $Scenario - $ResolvedRequestId"
    $payload['fsi_status'] = $script:SubmittedStatusValue
    $payload['fsi_submittedon'] = (Get-Date).ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')

    # -PreClassify (Option C): stamp the validated router outputs from the fixture so the
    # router flow can orchestrate (status transition, self-approval override, fan-out) without
    # re-running the already-proven classifier. The reviewer board (fsi_parallelreviewersjson)
    # is intentionally left for the Flow 4 build, where its consumption contract is defined.
    if ($PreClassify -and ($Fixture.PSObject.Properties.Name -contains 'expectedClassification')) {
        $classification = $Fixture.expectedClassification
        $pathLabel = [string]$classification.pathUsed
        if ($script:PathUsedChoiceMap.ContainsKey($pathLabel)) { $payload['fsi_pathused'] = $script:PathUsedChoiceMap[$pathLabel] }
        $tierLabel = [string]$classification.riskTier
        if ($script:RiskTierChoiceMap.ContainsKey($tierLabel)) { $payload['fsi_risktier'] = $script:RiskTierChoiceMap[$tierLabel] }
        $zoneLabel = [string]$classification.zone
        if ($script:ZoneChoiceMap.ContainsKey($zoneLabel)) { $payload['fsi_zone'] = $script:ZoneChoiceMap[$zoneLabel] }
        if ($script:PathToTopologyMap.ContainsKey($pathLabel)) {
            $payload['fsi_routingtopology'] = $script:RoutingTopologyChoiceMap[$script:PathToTopologyMap[$pathLabel]]
        }
        if ($null -ne $classification.quorumRequired) { $payload['fsi_quorumrequired'] = [int]$classification.quorumRequired }
        if (-not [string]::IsNullOrWhiteSpace([string]$classification.decisionPath)) { $payload['fsi_decisionpath'] = [string]$classification.decisionPath }
        if (($Fixture.PSObject.Properties.Name -contains 'expectedOutcome') -and ($null -ne $Fixture.expectedOutcome.mrmExpected)) {
            $payload['fsi_mrmrequired'] = [bool]$Fixture.expectedOutcome.mrmExpected
        }
    }

    return $payload
}

# --- Main ----------------------------------------------------------------------------------
$fixturePath = Join-Path $PSScriptRoot ("seed-test-data/request-{0}.json" -f $Scenario)
if (-not (Test-Path -Path $fixturePath)) {
    throw "Fixture not found: $fixturePath"
}

$fixture = Get-Content -Path $fixturePath -Raw | ConvertFrom-Json
$resolvedRequestId = if ($PSBoundParameters.ContainsKey('RequestId')) { $RequestId } else { [guid]::NewGuid().ToString() }
$payload = ConvertTo-SubmissionPayload -Fixture $fixture -ResolvedRequestId $resolvedRequestId -PreClassify:$PreClassify

# Real-tenant UPN overrides for live Teams-approval testing (e.g. sponsor = admin for the lab).
if (-not [string]::IsNullOrWhiteSpace($SponsorUpn)) { $payload['fsi_sponsorupn'] = $SponsorUpn }
if (-not [string]::IsNullOrWhiteSpace($MakerUpn)) { $payload['fsi_makerupn'] = $MakerUpn }

$expectedPath = if ($fixture.PSObject.Properties.Name -contains 'expectedClassification') { [string]$fixture.expectedClassification.pathUsed } else { '(unknown)' }
Write-Host "Scenario        : $Scenario (expected router path: $expectedPath)" -ForegroundColor Cyan
Write-Host "Environment     : $EnvironmentUrl" -ForegroundColor Cyan
Write-Host "fsi_requestid   : $resolvedRequestId" -ForegroundColor Cyan
Write-Host "Maker / Sponsor : $($payload['fsi_makerupn']) -> $($payload['fsi_sponsorupn'])" -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "`n[DRY RUN] Would POST the following to fsi_intakerequests:" -ForegroundColor Yellow
    $payload | ConvertTo-Json -Depth 10 | Write-Host
    return [pscustomobject]@{ RequestId = $resolvedRequestId; RecordId = $null; Scenario = $Scenario; DryRun = $true }
}

if (-not $PSCmdlet.ShouldProcess("fsi_intakerequests ($resolvedRequestId)", 'Create Submitted intake request')) {
    return
}

$created = Invoke-DataverseRequest -Method POST -RelativeUri 'fsi_intakerequests' -Body $payload `
    -ExtraHeaders @{ Prefer = 'return=representation' }

$recordId = [string]$created.fsi_intakerequestid
$statusValue = [int]$created.fsi_status
$decisionPath = [string]$created.fsi_decisionpath

Write-Host "`nCreated row     : $recordId" -ForegroundColor Green
Write-Host "fsi_status      : $statusValue (expected $script:SubmittedStatusValue = Submitted)" -ForegroundColor Green
if ($PreClassify) {
    Write-Host "fsi_decisionpath: '$decisionPath' (pre-classified; the router triggers on status = Submitted)" -ForegroundColor Green
    Write-Host "pre-classified  : pathused=$([int]$created.fsi_pathused) risktier=$([int]$created.fsi_risktier) zone=$([int]$created.fsi_zone) quorum=$([int]$created.fsi_quorumrequired) mrm=$($created.fsi_mrmrequired)" -ForegroundColor Green
}
else {
    Write-Host "fsi_decisionpath: '$decisionPath' (expected blank so the router trigger fires)" -ForegroundColor Green
}

if ($statusValue -ne $script:SubmittedStatusValue) {
    throw "Created row landed in status $statusValue, expected $script:SubmittedStatusValue (Submitted)."
}
if (-not $PreClassify -and -not [string]::IsNullOrWhiteSpace($decisionPath)) {
    Write-Warning "fsi_decisionpath is not blank ('$decisionPath'); the router trigger guard may skip this row."
}

# -ReviewersJson: PATCH the reviewer board on the row so F4 (parallel-reviewers) can iterate
# over it once the row reaches InReview. The fixture's `reviewers` block is a role->upn map
# intended for production; for lab tests the caller passes a JSON ARRAY of
# {role, upn, quorumWeight} objects, e.g.
#   -ReviewersJson '[{"role":"InfoSec","upn":"admin@…","quorumWeight":1}]'
# fsi_quorumrequired is ALSO bumped to the sum of the weights (or count) so the F4 quorum
# compute matches the reviewer count this test wants — overrides any pre-classified value.
if (-not [string]::IsNullOrWhiteSpace($ReviewersJson)) {
    try {
        $parsedReviewers = $ReviewersJson | ConvertFrom-Json
        # ConvertFrom-Json unrolls single-element arrays to a bare PSObject — wrap in @() to normalize.
        $reviewerArray = @($parsedReviewers)
        if ($reviewerArray.Count -eq 0) {
            throw "Reviewer array is empty."
        }
        $quorumSum = 0
        foreach ($r in $reviewerArray) {
            if (-not $r.PSObject.Properties.Match('role').Count -or -not $r.PSObject.Properties.Match('upn').Count) {
                throw "Each reviewer must have 'role' and 'upn' properties."
            }
            $weight = 1
            if ($r.PSObject.Properties.Match('quorumWeight').Count) { $weight = [int]$r.quorumWeight }
            $quorumSum += $weight
        }
        $patchPayload = @{
            fsi_parallelreviewersjson = $ReviewersJson
            fsi_quorumrequired        = $quorumSum
        }
        Invoke-DataverseRequest -Method PATCH `
            -RelativeUri ("fsi_intakerequests({0})" -f $recordId) `
            -Body $patchPayload | Out-Null
        Write-Host "Reviewers board : $($reviewerArray.Count) reviewers PATCHed (fsi_parallelreviewersjson set; fsi_quorumrequired=$quorumSum)" -ForegroundColor Green
    }
    catch {
        throw "Failed to PATCH ReviewersJson onto fsi_intakerequests($recordId): $($_.Exception.Message)"
    }
}

if ($RemoveAfter) {
    if ($PSCmdlet.ShouldProcess("fsi_intakerequests($recordId)", 'Delete intake request')) {
        Invoke-DataverseRequest -Method DELETE -RelativeUri ("fsi_intakerequests({0})" -f $recordId) | Out-Null
        Write-Host "Removed row     : $recordId (-RemoveAfter)" -ForegroundColor Green
    }
}

return [pscustomobject]@{
    RequestId    = $resolvedRequestId
    RecordId     = $recordId
    Scenario     = $Scenario
    ExpectedPath = $expectedPath
    Status       = $statusValue
    PreClassified = [bool]$PreClassify
    Removed      = [bool]$RemoveAfter
}
