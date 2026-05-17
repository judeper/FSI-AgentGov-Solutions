<#
.SYNOPSIS
    Extended smoke test for the agent-intake solution.

.DESCRIPTION
    Runs the original seven deployment checks plus schema integrity validation,
    documentation language scanning, and optional seeded-data assertions for the
    Express, Standard, and Full paths.

.PARAMETER EnvironmentUrl
    Dataverse environment URL.

.PARAMETER PathScope
    Limits seeded-data assertions to Express, Standard, Full, or All.

.PARAMETER IncludeSeededDataChecks
    Requires that seed-test-data.ps1 has already been run and validates the
    deterministic lab scenarios.

.PARAMETER DryRun
    Logs the checks that would run without querying remote services.

.EXAMPLE
    pwsh .\scripts\smoke_test.ps1 -EnvironmentUrl https://contoso.crm.dynamics.com

.EXAMPLE
    pwsh .\scripts\smoke_test.ps1 -EnvironmentUrl https://contoso.crm.dynamics.com -IncludeSeededDataChecks -PathScope All
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$EnvironmentUrl,

    [ValidateSet('Express', 'Standard', 'Full', 'All')]
    [string]$PathScope = 'All',

    [switch]$IncludeSeededDataChecks,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$script:TargetEnvironmentUrl = $EnvironmentUrl
$script:SelectedPathScope = $PathScope
$script:IsDryRun = [bool]$DryRun

$script:SolutionRoot = Split-Path -Path $PSScriptRoot -Parent
$script:FixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath 'seed-test-data'
$script:RuntimeRoot = Join-Path -Path $PSScriptRoot -ChildPath '.smoke-runtime'
$script:DriftSchemaPath = Join-Path -Path $script:SolutionRoot -ChildPath 'templates\drift-handoff-payload-schema.json'
$script:Results = [System.Collections.Generic.List[object]]::new()
$script:DataverseToken = $null
$script:EnvironmentMetadata = $null
$script:EntityMap = @{
    fsi_intakerequest         = @{ EntitySetName = 'fsi_intakerequests'; PrimaryIdAttribute = 'fsi_intakerequestid' }
    fsi_intakedatasource      = @{ EntitySetName = 'fsi_intakedatasources'; PrimaryIdAttribute = 'fsi_intakedatasourceid' }
    fsi_intakerisksignal      = @{ EntitySetName = 'fsi_intakerisksignals'; PrimaryIdAttribute = 'fsi_intakerisksignalid' }
    fsi_intakereview          = @{ EntitySetName = 'fsi_intakereviews'; PrimaryIdAttribute = 'fsi_intakereviewid' }
    fsi_intakeapproval        = @{ EntitySetName = 'fsi_intakeapprovals'; PrimaryIdAttribute = 'fsi_intakeapprovalid' }
    fsi_intakedecisionlog     = @{ EntitySetName = 'fsi_intakedecisionlogs'; PrimaryIdAttribute = 'fsi_intakedecisionlogid' }
    fsi_intakesponsorship     = @{ EntitySetName = 'fsi_intakesponsorships'; PrimaryIdAttribute = 'fsi_intakesponsorshipid' }
    fsi_intakeauditevent      = @{ EntitySetName = 'fsi_intakeauditevents'; PrimaryIdAttribute = 'fsi_intakeauditeventid' }
    fsi_intakeretentionrecord = @{ EntitySetName = 'fsi_intakeretentionrecords'; PrimaryIdAttribute = 'fsi_intakeretentionrecordid' }
}
$script:TableNameList = @(
    'fsi_intakerequest',
    'fsi_intakedatasource',
    'fsi_intakerisksignal',
    'fsi_intakereview',
    'fsi_intakeapproval',
    'fsi_intakedecisionlog',
    'fsi_intakesponsorship',
    'fsi_intakeauditevent',
    'fsi_intakeretentionrecord'
)
$script:KeyColumnMap = @{
    fsi_intakerequest = @('fsi_requestid', 'fsi_agentdisplayname', 'fsi_pathused', 'fsi_risktier', 'fsi_zone', 'fsi_status', 'fsi_policyversionapplied')
    fsi_intakedatasource = @('fsi_requestid', 'fsi_datasourcename', 'fsi_dataclassification')
    fsi_intakerisksignal = @('fsi_requestid', 'fsi_triggercode', 'fsi_triggeranswer')
    fsi_intakereview = @('fsi_requestid', 'fsi_reviewerrole', 'fsi_reviewoutcome')
    fsi_intakeapproval = @('fsi_requestid', 'fsi_approverrole', 'fsi_decisionoutcome')
    fsi_intakedecisionlog = @('fsi_requestid', 'fsi_decisionoutcome', 'fsi_decisionpackhash')
    fsi_intakesponsorship = @('fsi_requestid', 'fsi_sponsorupn', 'fsi_attestationmethod')
    fsi_intakeauditevent = @('fsi_requestid', 'fsi_eventtype', 'fsi_eventon')
    fsi_intakeretentionrecord = @('fsi_requestid', 'fsi_labelname', 'fsi_stampedon')
}
$script:OptionSetNameList = @(
    'fsi_acv_zone',
    'fsi_intake_pathused',
    'fsi_intake_status',
    'fsi_intake_routingtopology',
    'fsi_intake_risktier',
    'fsi_intake_agenttype',
    'fsi_intake_dataclassification',
    'fsi_intake_reviewerrole',
    'fsi_intake_reviewdecision',
    'fsi_intake_mrmhandoffstatus',
    'fsi_intake_decisionoutcome'
)
$script:ChoiceMap = @{
    'fsi_acv_zone' = @{ 100000000 = 'Unclassified'; 100000001 = 'Zone 1 (Enterprise)'; 100000002 = 'Zone 2 (Team)'; 100000003 = 'Zone 3 (Personal)' }
    'fsi_intake_pathused' = @{ 100000000 = 'Express'; 100000001 = 'Standard'; 100000002 = 'Full' }
    'fsi_intake_risktier' = @{ 100000000 = 'Tier 1 (High)'; 100000001 = 'Tier 2 (Medium)'; 100000002 = 'Tier 3 (Low)' }
    'fsi_intake_mrmhandoffstatus' = @{ 100000000 = 'Pending'; 100000001 = 'Handed off'; 100000002 = 'NotApplicable'; 100000003 = 'Failed' }
    'fsi_intake_reviewdecision' = @{ 100000000 = 'Pending'; 100000001 = 'Approved'; 100000002 = 'Approved with conditions'; 100000003 = 'Denied'; 100000004 = 'Recused'; 100000005 = 'Timeout' }
    'fsi_intake_status' = @{ 100000004 = 'Approved'; 100000005 = 'Denied' }
}
$script:ScenarioScopeMap = @{
    'express-happy' = 'Express'
    'standard-conditional' = 'Standard'
    'full-parallel-board' = 'Full'
    'cross-border-deny' = 'Standard'
    'sponsor-self-approval-deny' = 'Express'
}
$script:RequiredAuditEventMap = @{
    'express-happy' = @('Submitted', 'Routed', 'SponsorClicked', 'Approved', 'EntraAgentIdMinted', 'DriftHandoffPrepared', 'HandoffComplete', 'RetentionStamped')
    'standard-conditional' = @('Submitted', 'Routed', 'ReviewerQueued', 'ReviewerDecided', 'Approved', 'EntraAgentIdMinted', 'DriftHandoffPrepared', 'HandoffComplete', 'RetentionStamped')
    'full-parallel-board' = @('Submitted', 'Routed', 'ReviewerQueued', 'ReviewerDecided', 'Approved', 'EntraAgentIdMinted', 'DriftHandoffPrepared', 'HandoffComplete', 'RetentionStamped')
    'cross-border-deny' = @('Submitted', 'Routed', 'Denied')
    'sponsor-self-approval-deny' = @('Submitted', 'Routed', 'Denied')
}

function Write-Info {
    param([Parameter(Mandatory)][string]$Message)
    Write-Information "[smoke] $Message" -InformationAction Continue
}

function Add-ResultRecord {
    param(
        [Parameter(Mandatory)][string]$Check,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Detail
    )

    $script:Results.Add([pscustomobject]@{
            Check = $Check
            Status = $Status
            Detail = $Detail
        }) | Out-Null
}

function Invoke-SmokeFailure {
    param(
        [Parameter(Mandatory)][string]$Check,
        [Parameter(Mandatory)][string]$Reason
    )

    Write-Error "FAIL: ${Check}: $Reason"
    exit 1
}

function Invoke-SmokeCheck {
    param(
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][scriptblock]$Action
    )

    Write-Info $Name
    try {
        $result = & $Action
        if ($null -eq $result) {
            Add-ResultRecord -Check $Name -Status 'PASS' -Detail 'OK'
            return
        }

        $status = if ($result.PSObject.Properties.Name -contains 'Status') { [string]$result.Status } else { 'PASS' }
        $detail = if ($result.PSObject.Properties.Name -contains 'Detail') { [string]$result.Detail } else { 'OK' }
        if ($status -eq 'FAIL') {
            Invoke-SmokeFailure -Check $Name -Reason $detail
        }

        Add-ResultRecord -Check $Name -Status $status -Detail $detail
    }
    catch {
        Invoke-SmokeFailure -Check $Name -Reason $_.Exception.Message
    }
}

function Get-PythonCommand {
    foreach ($candidate in @('python', 'py')) {
        $command = Get-Command -Name $candidate -ErrorAction SilentlyContinue
        if ($null -ne $command) {
            return $command.Name
        }
    }

    throw 'Python 3.10 or later is required.'
}

function Get-DataverseToken {
    if ($DryRun) {
        return 'dry-run-token'
    }

    if (-not [string]::IsNullOrWhiteSpace($script:DataverseToken)) {
        return $script:DataverseToken
    }

    $envToken = $env:DATAVERSE_ACCESS_TOKEN
    if (-not [string]::IsNullOrWhiteSpace($envToken)) {
        $script:DataverseToken = $envToken.Trim()
        return $script:DataverseToken
    }

    $az = Get-Command -Name 'az' -ErrorAction SilentlyContinue
    if ($null -ne $az) {
        $token = & $az.Source account get-access-token --resource $EnvironmentUrl --query accessToken -o tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($token)) {
            $script:DataverseToken = $token.Trim()
            return $script:DataverseToken
        }
    }

    if (Get-Command -Name 'Get-AzAccessToken' -ErrorAction SilentlyContinue) {
        $script:DataverseToken = (Get-AzAccessToken -ResourceUrl $EnvironmentUrl).Token
        return $script:DataverseToken
    }

    throw 'Could not acquire a Dataverse access token.'
}

function Get-DataverseHeader {
    return @{
        Authorization = "Bearer $(Get-DataverseToken)"
        Accept = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version' = '4.0'
    }
}

function Invoke-DataverseRequest {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)][string]$RelativeUri,

        [switch]$AllowNotFound
    )

    $uri = '{0}/api/data/v9.2/{1}' -f $EnvironmentUrl.TrimEnd('/'), $RelativeUri.TrimStart('/')
    if ($DryRun) {
        Write-Info "[DRY RUN] $Method $uri"
        return [pscustomobject]@{ StatusCode = 200; Body = $null }
    }

    $response = Invoke-WebRequest -Uri $uri -Method $Method -Headers (Get-DataverseHeader) -UseBasicParsing -SkipHttpErrorCheck
    if ($AllowNotFound -and $response.StatusCode -eq 404) {
        return $null
    }
    if ($response.StatusCode -ge 400) {
        throw "Dataverse request failed ($Method $RelativeUri): HTTP $($response.StatusCode) $($response.Content)"
    }

    $payload = $null
    if (-not [string]::IsNullOrWhiteSpace($response.Content)) {
        try {
            $payload = $response.Content | ConvertFrom-Json -AsHashtable
        }
        catch {
            $payload = $response.Content
        }
    }

    return [pscustomobject]@{ StatusCode = [int]$response.StatusCode; Body = $payload }
}

function ConvertTo-ODataStringLiteral {
    param([Parameter(Mandatory)][string]$Value)
    return "'{0}'" -f $Value.Replace("'", "''")
}

function Get-EnvironmentMetadataRecord {
    if ($DryRun) {
        return [ordered]@{ OrganizationId = '00000000-0000-4000-8000-000000000000'; FriendlyName = ([System.Uri]$EnvironmentUrl).Host }
    }

    $response = Invoke-DataverseRequest -Method GET -RelativeUri 'WhoAmI'
    return [ordered]@{
        OrganizationId = [string]$response.Body.OrganizationId
        FriendlyName = ([System.Uri]$EnvironmentUrl).Host
    }
}

function Get-EntityRecord {
    param([Parameter(Mandatory)][string]$LogicalName)

    if ($DryRun) {
        return [ordered]@{ LogicalName = $LogicalName; EntitySetName = ($LogicalName + 's'); PrimaryIdAttribute = ($LogicalName + 'id') }
    }

    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("EntityDefinitions(LogicalName='{0}')?`$select=LogicalName,EntitySetName,PrimaryIdAttribute" -f $LogicalName) -AllowNotFound
    if ($null -eq $response) {
        return $null
    }

    return $response.Body
}

function Test-EntityColumnSet {
    param(
        [Parameter(Mandatory)][string]$LogicalName,
        [Parameter(Mandatory)][string[]]$RequiredColumn
    )

    if ($DryRun) {
        return $true
    }

    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("EntityDefinitions(LogicalName='{0}')/Attributes?`$select=LogicalName" -f $LogicalName)
    $actual = @($response.Body.value | ForEach-Object { [string]$_.LogicalName })
    foreach ($column in $RequiredColumn) {
        if ($column -notin $actual) {
            return $false
        }
    }

    return $true
}

function Test-GlobalOptionSetPresence {
    param([Parameter(Mandatory)][string]$Name)

    if ($DryRun) {
        return $true
    }

    # Dataverse rejects $filter on GlobalOptionSetDefinitions ('not supported',
    # HTTP 405). Use direct key access with -AllowNotFound instead.
    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("GlobalOptionSetDefinitions(Name='{0}')?`$select=Name" -f $Name) -AllowNotFound
    return $null -ne $response
}

function Get-EnvironmentVariableCurrentValue {
    param([Parameter(Mandatory)][string]$SchemaName)

    if ($DryRun) {
        return 'dry-run-value'
    }

    $filter = ConvertTo-ODataStringLiteral -Value $SchemaName
    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("environmentvariablevalues?`$select=value,schemaname&`$filter=schemaname eq $filter")
    $record = @($response.Body.value | Select-Object -First 1)[0]
    if ($null -eq $record) {
        return $null
    }

    return [string]$record.value
}

function Get-PythonTokenSource {
    $az = Get-Command -Name 'az' -ErrorAction SilentlyContinue
    if ($null -ne $az) {
        & $az.Source account show --only-show-errors 1>$null 2>$null
        if ($LASTEXITCODE -eq 0) {
            return 'cli'
        }
    }

    return 'mi'
}

function Invoke-PythonScript {
    param(
        [Parameter(Mandatory)][string]$ScriptPath,
        [Parameter(Mandatory)][string[]]$Argument,
        [int[]]$AllowedExitCode = @(0)
    )

    $resolvedPath = [System.IO.Path]::GetFullPath($ScriptPath)
    if (-not (Test-Path -LiteralPath $resolvedPath)) {
        throw "Required script was not found: $resolvedPath"
    }

    $python = Get-PythonCommand
    $command = @($python, $resolvedPath) + $Argument
    Write-Info ($command -join ' ')
    $output = & $command[0] @($command[1..($command.Count - 1)]) 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -notin $AllowedExitCode) {
        throw "Python command failed: $($output -join ' ')"
    }

    return [pscustomobject]@{ ExitCode = $exitCode; Output = ($output -join [Environment]::NewLine) }
}

function Get-RuntimeFilePath {
    param([Parameter(Mandatory)][string]$Name)

    if (-not (Test-Path -LiteralPath $script:RuntimeRoot)) {
        New-Item -ItemType Directory -Path $script:RuntimeRoot | Out-Null
    }

    return Join-Path -Path $script:RuntimeRoot -ChildPath $Name
}

function Convert-ChoiceValueToLabel {
    param(
        [Parameter(Mandatory)][string]$ChoiceSet,
        [Parameter(Mandatory)][int]$Value
    )

    $map = $script:ChoiceMap[$ChoiceSet]
    if ($null -eq $map -or -not $map.ContainsKey($Value)) {
        throw "Choice value '$Value' was not defined for '$ChoiceSet'."
    }

    return [string]$map[$Value]
}

function Get-FixtureRecordSet {
    $fileNameSet = @(
        'request-express-happy.json',
        'request-standard-conditional.json',
        'request-full-parallel-board.json',
        'request-cross-border-deny.json',
        'request-sponsor-self-approval-deny.json'
    )
    $fixtures = @()
    foreach ($fileName in $fileNameSet) {
        $path = Join-Path -Path $script:FixtureRoot -ChildPath $fileName
        if (-not (Test-Path -LiteralPath $path)) {
            throw "Fixture file was not found: $path"
        }
        $fixtures += (Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable)
    }

    return $fixtures
}

function Get-ScopedFixtureRecordSet {
    $fixtures = Get-FixtureRecordSet
    if ($PathScope -eq 'All') {
        return $fixtures
    }

    return @($fixtures | Where-Object { $script:ScenarioScopeMap[[string]$_.scenario] -eq $PathScope })
}

function Get-RequestRecord {
    param([Parameter(Mandatory)][string]$RequestId)

    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("fsi_intakerequests(fsi_requestid={0})?`$select=fsi_requestid,fsi_pathused,fsi_decisionpath,fsi_risktier,fsi_zone,fsi_quorumrequired,fsi_entraagentid,fsi_mrmhandoffstatus,fsi_status,fsi_registryrecordid,fsi_targetenvironmentid,fsi_targetenvironmentname" -f (ConvertTo-ODataStringLiteral -Value $RequestId)) -AllowNotFound
    if ($null -eq $response) {
        return $null
    }

    return $response.Body
}

function Get-RecordSetByRequestId {
    param(
        [Parameter(Mandatory)][string]$LogicalName,
        [Parameter(Mandatory)][string]$RequestId,
        [string]$Select = '*'
    )

    if ($DryRun) {
        return @()
    }

    $entity = $script:EntityMap[$LogicalName]
    $filter = ConvertTo-ODataStringLiteral -Value $RequestId
    $selectClause = if ($Select -eq '*') { $entity.PrimaryIdAttribute } else { $Select }
    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("{0}?`$select={1}&`$filter=fsi_requestid eq {2}" -f $entity.EntitySetName, $selectClause, $filter)
    return @($response.Body.value)
}

function Get-ReviewDecisionPlan {
    param([Parameter(Mandatory)][hashtable]$Fixture)

    if ([string]$Fixture.scenario -eq 'full-parallel-board') {
        $path = Join-Path -Path $script:FixtureRoot -ChildPath 'reviewer-decisions-full-board.json'
        return @((Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -AsHashtable).decisions)
    }

    if ([string]$Fixture.scenario -eq 'standard-conditional') {
        return @(
            @{ role = 'InfoSec'; decision = 'Approved with conditions'; upn = [string]$Fixture.reviewers.InfoSec; conditionsText = 'Quarterly access review required before widening beyond the named sales-operations team.' },
            @{ role = 'Privacy'; decision = 'Approved'; upn = [string]$Fixture.reviewers.Privacy; conditionsText = '' },
            @{ role = 'Compliance'; decision = 'Approved'; upn = [string]$Fixture.reviewers.Compliance; conditionsText = '' }
        )
    }

    return @()
}

function Get-ApprovedReviewCount {
    param([Parameter(Mandatory)][object[]]$ReviewSet)

    return @($ReviewSet | Where-Object { $_.fsi_reviewoutcome -in @(100000001, 100000002) }).Count
}

function Test-JsonSchemaFile {
    param(
        [Parameter(Mandatory)][string]$SchemaPath,
        [Parameter(Mandatory)][string]$PayloadPath,
        [Parameter(Mandatory)][string]$Label
    )

    $python = Get-PythonCommand
    $code = @"
import json
from pathlib import Path
from jsonschema import Draft202012Validator, FormatChecker
schema = json.loads(Path(r"$SchemaPath").read_text(encoding="utf-8"))
payload = json.loads(Path(r"$PayloadPath").read_text(encoding="utf-8"))
Draft202012Validator(schema, format_checker=FormatChecker()).validate(payload)
"@
    $output = & $python -c $code 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "$Label schema validation failed: $($output -join ' ')"
    }
}

function Test-SeedScenarioRecord {
    param([Parameter(Mandatory)][hashtable]$Fixture)

    if ($DryRun) {
        return 'Dry-run only.'
    }

    $requestId = [string]$Fixture.fsi_intakerequest.fsi_requestid
    $request = Get-RequestRecord -RequestId $requestId
    if ($null -eq $request) {
        throw "Seeded request $requestId was not found. Run seed-test-data.ps1 first."
    }

    $pathUsed = Convert-ChoiceValueToLabel -ChoiceSet 'fsi_intake_pathused' -Value ([int]$request.fsi_pathused)
    $riskTier = Convert-ChoiceValueToLabel -ChoiceSet 'fsi_intake_risktier' -Value ([int]$request.fsi_risktier)
    $zone = Convert-ChoiceValueToLabel -ChoiceSet 'fsi_acv_zone' -Value ([int]$request.fsi_zone)
    if ($pathUsed -ne [string]$Fixture.expectedClassification.pathUsed) {
        throw "Expected pathUsed=$($Fixture.expectedClassification.pathUsed) but found $pathUsed."
    }
    if ([string]$request.fsi_decisionpath -ne [string]$Fixture.expectedClassification.decisionPath) {
        throw "Expected decisionPath=$($Fixture.expectedClassification.decisionPath) but found $($request.fsi_decisionpath)."
    }
    if ($riskTier -ne [string]$Fixture.expectedClassification.riskTier) {
        throw "Expected riskTier=$($Fixture.expectedClassification.riskTier) but found $riskTier."
    }
    if ($zone -ne [string]$Fixture.expectedClassification.zone) {
        throw "Expected zone=$($Fixture.expectedClassification.zone) but found $zone."
    }
    if ([int]$request.fsi_quorumrequired -ne [int]$Fixture.expectedClassification.quorumRequired) {
        throw "Expected quorumRequired=$($Fixture.expectedClassification.quorumRequired) but found $($request.fsi_quorumrequired)."
    }

    return ('Request {0} matches the expected classification.' -f $requestId)
}

function Test-HappyPathArtifactSet {
    param([Parameter(Mandatory)][hashtable]$Fixture)

    if (-not [bool]$Fixture.expectedOutcome.agentIdExpected) {
        return 'Scenario is a deny path; happy-path artifact checks are not applicable.'
    }

    $requestId = [string]$Fixture.fsi_intakerequest.fsi_requestid
    $request = Get-RequestRecord -RequestId $requestId
    if ([string]::IsNullOrWhiteSpace([string]$request.fsi_entraagentid)) {
        throw 'Expected a seeded or live Entra Agent ID on the request row.'
    }

    $decisionRows = Get-RecordSetByRequestId -LogicalName 'fsi_intakedecisionlog' -RequestId $requestId -Select 'fsi_decisionpackhash,fsi_decisionoutcome,fsi_decisionpackjson'
    if ($decisionRows.Count -lt 1) {
        throw 'Expected at least one decision-log row for the happy-path scenario.'
    }

    $driftRows = @()
    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("fsi_intakeauditevents?`$select=fsi_eventtype,fsi_eventpayloadjson&`$filter=fsi_requestid eq {0} and fsi_eventtype eq 'DriftHandoffPrepared'" -f (ConvertTo-ODataStringLiteral -Value $requestId))
    $driftRows = @($response.Body.value)
    if ($driftRows.Count -lt 1) {
        throw 'Expected a DriftHandoffPrepared audit event for the happy-path scenario.'
    }

    $payloadPath = Get-RuntimeFilePath -Name ('{0}-drift.json' -f $Fixture.scenario)
    $driftRows[0].fsi_eventpayloadjson | Set-Content -LiteralPath $payloadPath -Encoding utf8
    Test-JsonSchemaFile -SchemaPath $script:DriftSchemaPath -PayloadPath $payloadPath -Label 'Drift handoff payload'
    return ('Decision log, Agent ID, and drift payload validated for {0}.' -f $requestId)
}

function Test-ReviewerQueueSet {
    param([Parameter(Mandatory)][hashtable]$Fixture)

    $expectedReviewerCount = [int]$Fixture.expectedOutcome.reviewerCount
    if ($expectedReviewerCount -lt 1) {
        return 'Scenario does not require reviewer rows.'
    }

    $requestId = [string]$Fixture.fsi_intakerequest.fsi_requestid
    $reviews = Get-RecordSetByRequestId -LogicalName 'fsi_intakereview' -RequestId $requestId -Select 'fsi_reviewerrole,fsi_reviewoutcome,fsi_conditionstext,fsi_reviewerupn'
    if ($reviews.Count -ne $expectedReviewerCount) {
        throw "Expected $expectedReviewerCount reviewer row(s) but found $($reviews.Count)."
    }

    if ([string]$Fixture.scenario -eq 'standard-conditional') {
        if (@($reviews | Where-Object { $_.fsi_reviewoutcome -eq 100000002 }).Count -lt 1) {
            throw 'Expected one Approved with conditions reviewer row for the Standard scenario.'
        }
    }

    if ([string]$Fixture.scenario -eq 'full-parallel-board') {
        $approvedCount = Get-ApprovedReviewCount -ReviewSet $reviews
        if ($approvedCount -lt 3) {
            throw "Expected the Full path reviewer board to reach at least 3 approvals, but found $approvedCount."
        }
    }

    return ('Reviewer queue validated for {0}.' -f $requestId)
}

function Test-MrmBridge {
    param([Parameter(Mandatory)][hashtable]$Fixture)

    if (-not [bool]$Fixture.expectedOutcome.mrmExpected) {
        return 'Scenario does not require an MRM handoff.'
    }

    $requestId = [string]$Fixture.fsi_intakerequest.fsi_requestid
    $request = Get-RequestRecord -RequestId $requestId
    $statusLabel = Convert-ChoiceValueToLabel -ChoiceSet 'fsi_intake_mrmhandoffstatus' -Value ([int]$request.fsi_mrmhandoffstatus)
    $modelInventory = Get-EntityRecord -LogicalName 'fsi_modelinventory'
    if ($null -ne $modelInventory -and $statusLabel -eq 'Handed off') {
        $filter = "fsi_agentid eq {0} and fsi_environmentid eq {1}" -f (ConvertTo-ODataStringLiteral -Value $requestId), (ConvertTo-ODataStringLiteral -Value ([string]$script:EnvironmentMetadata.OrganizationId))
        $queueResponse = Invoke-DataverseRequest -Method GET -RelativeUri ("{0}?`$select=fsi_validationstatus&`$filter={1}" -f $modelInventory.EntitySetName, $filter)
        $queueRows = @($queueResponse.Body.value)
        if ($queueRows.Count -lt 1) {
            throw 'Expected an MRM queue row for the Full path scenario.'
        }
        if ([int]$queueRows[0].fsi_validationstatus -ne 100000002) {
            throw 'Expected fsi_validationstatus = Submitted on the mirrored MRM queue row.'
        }
        $eventEntity = Get-EntityRecord -LogicalName 'fsi_mrmcomplianceevent'
        if ($null -ne $eventEntity) {
            $eventResponse = Invoke-DataverseRequest -Method GET -RelativeUri ("{0}?`$select=fsi_previousvalue,fsi_newvalue&`$filter=fsi_previousvalue eq {1}" -f $eventEntity.EntitySetName, (ConvertTo-ODataStringLiteral -Value $requestId))
            if (@($eventResponse.Body.value).Count -lt 1) {
                throw 'Expected an fsi_mrmcomplianceevent mirror row for the Full path scenario.'
            }
        }
        return 'MRM queue and mirror row validated.'
    }

    $auditResponse = Invoke-DataverseRequest -Method GET -RelativeUri ("fsi_intakeauditevents?`$select=fsi_eventtype&`$filter=fsi_requestid eq {0} and fsi_eventtype eq 'MRMHandoffPending'" -f (ConvertTo-ODataStringLiteral -Value $requestId))
    if (@($auditResponse.Body.value).Count -lt 1) {
        throw 'Expected an MRMHandoffPending audit event when the downstream MRM solution is absent.'
    }

    return 'MRM fallback audit event validated.'
}

function Test-DefensiveDenySet {
    param([Parameter(Mandatory)][hashtable]$Fixture)

    if ([bool]$Fixture.expectedOutcome.agentIdExpected) {
        return 'Scenario is not a defensive deny path.'
    }

    $requestId = [string]$Fixture.fsi_intakerequest.fsi_requestid
    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("fsi_intakeauditevents?`$select=fsi_eventtype,fsi_eventpayloadjson&`$filter=fsi_requestid eq {0} and fsi_eventtype eq 'Denied'" -f (ConvertTo-ODataStringLiteral -Value $requestId))
    $rows = @($response.Body.value)
    if ($rows.Count -lt 1) {
        throw 'Expected a Denied audit event for the defensive deny scenario.'
    }

    $payload = $rows[0].fsi_eventpayloadjson | ConvertFrom-Json -AsHashtable
    $expectedReason = [string]$Fixture.expectedClassification.routingReason
    if ([string]$payload.routingReason -ne $expectedReason) {
        throw "Expected routingReason=$expectedReason but found $($payload.routingReason)."
    }

    return ('Defensive deny reason {0} validated.' -f $expectedReason)
}

function Test-AuditTrailSet {
    param([Parameter(Mandatory)][hashtable]$Fixture)

    $requestId = [string]$Fixture.fsi_intakerequest.fsi_requestid
    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("fsi_intakeauditevents?`$select=fsi_eventtype&`$filter=fsi_requestid eq {0}" -f (ConvertTo-ODataStringLiteral -Value $requestId))
    $eventTypes = @($response.Body.value | ForEach-Object { [string]$_.fsi_eventtype })
    foreach ($requiredEvent in $script:RequiredAuditEventMap[[string]$Fixture.scenario]) {
        if ($requiredEvent -notin $eventTypes) {
            throw "Expected audit event '$requiredEvent' for scenario '$($Fixture.scenario)'."
        }
    }

    return ('Audit trail validated for {0}.' -f $requestId)
}

try {
    $script:EnvironmentMetadata = Get-EnvironmentMetadataRecord

    Invoke-SmokeCheck -Name 'dataverse-schema' -Action {
        foreach ($tableName in $script:TableNameList) {
            if ($null -eq (Get-EntityRecord -LogicalName $tableName)) {
                throw "Missing table $tableName."
            }
            if (-not (Test-EntityColumnSet -LogicalName $tableName -RequiredColumn $script:KeyColumnMap[$tableName])) {
                throw "Key column validation failed for $tableName."
            }
        }
        foreach ($optionSetName in $script:OptionSetNameList) {
            if (-not (Test-GlobalOptionSetPresence -Name $optionSetName)) {
                throw "Missing global option set $optionSetName."
            }
        }
        return [pscustomobject]@{ Status = 'PASS'; Detail = 'All agent-intake tables, key columns, and option sets are present.' }
    }

    Invoke-SmokeCheck -Name 'portal-page' -Action {
        if ($DryRun) {
            return [pscustomobject]@{ Status = 'PASS'; Detail = 'Dry-run skipped portal reachability.' }
        }
        $portalUrl = Get-EnvironmentVariableCurrentValue -SchemaName 'fsi_intake_makerportalurl'
        if ([string]::IsNullOrWhiteSpace($portalUrl)) {
            throw 'Environment variable fsi_intake_makerportalurl is empty.'
        }
        if ($portalUrl -match 'manual-step-required') {
            throw 'fsi_intake_makerportalurl still contains a placeholder.'
        }
        $response = Invoke-WebRequest -Uri $portalUrl -Method Head -UseBasicParsing -TimeoutSec 30
        if ($response.StatusCode -notin @(200, 302)) {
            throw "Unexpected HTTP status $($response.StatusCode) for $portalUrl."
        }
        return [pscustomobject]@{ Status = 'PASS'; Detail = ("{0} returned HTTP {1}." -f $portalUrl, $response.StatusCode) }
    }

    Invoke-SmokeCheck -Name 'router-flow' -Action {
        return [pscustomobject]@{ Status = 'MANUAL'; Detail = 'Verify in Power Automate that fsi-intake-router exists, is enabled, and is bound to fsi_intakerequest.' }
    }

    Invoke-SmokeCheck -Name 'sponsor-card-json' -Action {
        $cardPath = Join-Path -Path $script:SolutionRoot -ChildPath 'templates\sponsor-approval-card.json'
        $card = Get-Content -LiteralPath $cardPath -Raw | ConvertFrom-Json -AsHashtable
        if ([string]$card.type -ne 'AdaptiveCard') {
            throw 'Sponsor card template is not an AdaptiveCard.'
        }
        if (@($card.actions).Count -lt 2) {
            throw 'Sponsor card template should expose at least two actions.'
        }
        return [pscustomobject]@{ Status = 'PASS'; Detail = ("Adaptive Card validated with {0} action(s)." -f @($card.actions).Count) }
    }

    Invoke-SmokeCheck -Name 'classification-self-test' -Action {
        $selfTestResult = Invoke-PythonScript -ScriptPath (Join-Path -Path $PSScriptRoot -ChildPath 'seed_classification_rules.py') -Argument @('--self-test')
        return [pscustomobject]@{ Status = 'PASS'; Detail = ('seed_classification_rules.py --self-test passed with exit code {0}.' -f $selfTestResult.ExitCode) }
    }

    Invoke-SmokeCheck -Name 'env-autodetect' -Action {
        if ($DryRun) {
            return [pscustomobject]@{ Status = 'PASS'; Detail = 'Dry-run skipped environment auto-detect.' }
        }
        $outputPath = Get-RuntimeFilePath -Name 'autodetect-environments.json'
        $null = Invoke-PythonScript -ScriptPath (Join-Path -Path $PSScriptRoot -ChildPath 'autodetect_environments.py') -Argument @('--output', $outputPath, '--token-source', (Get-PythonTokenSource))
        $envs = Get-Content -LiteralPath $outputPath -Raw | ConvertFrom-Json
        $eligible = @($envs | Where-Object { $_.expressPathEligible })
        if ($eligible.Count -lt 1) {
            return [pscustomobject]@{ Status = 'WARN'; Detail = '0 Express-eligible environments were reported.' }
        }
        return [pscustomobject]@{ Status = 'PASS'; Detail = ("{0} Express-eligible environment(s) discovered." -f $eligible.Count) }
    }

    Invoke-SmokeCheck -Name 'purview-label' -Action {
        if ($DryRun) {
            return [pscustomobject]@{ Status = 'WARN'; Detail = 'Dry-run skipped automatic Purview verification. Validate the configured label in the portal during a live run.' }
        }
        $result = Invoke-PythonScript -ScriptPath (Join-Path -Path $PSScriptRoot -ChildPath 'autodetect_purview.py') -Argument @('--token-source', (Get-PythonTokenSource)) -AllowedExitCode @(0, 2)
        if ($result.ExitCode -eq 0) {
            return [pscustomobject]@{ Status = 'PASS'; Detail = 'FSI-AgentIntake-7yr verification succeeded.' }
        }
        return [pscustomobject]@{ Status = 'WARN'; Detail = 'Purview label could not be verified automatically. Confirm delegated Purview permissions or validate in the portal.' }
    }

    Invoke-SmokeCheck -Name 'docs-language-scan' -Action {
        $ruleOne = 'ensures' + ' compliance'
        $ruleTwo = 'guaran' + 'tees'
        $ruleThree = 'will' + ' ' + 'prevent'
        $ruleFour = 'eliminates' + ' ' + 'risk'
        $legacyBrand = 'Azure' + ' ' + 'AD'
        $pattern = "{0}|{1}|{2}|{3}|{4}" -f $ruleOne, $ruleTwo, $ruleThree, $ruleFour, $legacyBrand
        $hits = Select-String -Path (Join-Path -Path $script:SolutionRoot -ChildPath 'docs\*.md') -Pattern $pattern -CaseSensitive:$false -ErrorAction SilentlyContinue
        if ($null -ne $hits -and @($hits).Count -gt 0) {
            throw 'Banned language was found in agent-intake/docs/.'
        }
        return [pscustomobject]@{ Status = 'PASS'; Detail = 'No banned regulatory language or deprecated product naming was found in agent-intake/docs/.' }
    }

    if ($IncludeSeededDataChecks) {
        foreach ($fixture in Get-ScopedFixtureRecordSet) {
            Invoke-SmokeCheck -Name ("seeded-classification-{0}" -f $fixture.scenario) -Action { [pscustomobject]@{ Status = 'PASS'; Detail = (Test-SeedScenarioRecord -Fixture $fixture) } }
            Invoke-SmokeCheck -Name ("seeded-reviewers-{0}" -f $fixture.scenario) -Action { [pscustomobject]@{ Status = 'PASS'; Detail = (Test-ReviewerQueueSet -Fixture $fixture) } }
            Invoke-SmokeCheck -Name ("seeded-happy-path-{0}" -f $fixture.scenario) -Action { [pscustomobject]@{ Status = 'PASS'; Detail = (Test-HappyPathArtifactSet -Fixture $fixture) } }
            Invoke-SmokeCheck -Name ("seeded-mrm-{0}" -f $fixture.scenario) -Action { [pscustomobject]@{ Status = 'PASS'; Detail = (Test-MrmBridge -Fixture $fixture) } }
            Invoke-SmokeCheck -Name ("seeded-defensive-deny-{0}" -f $fixture.scenario) -Action { [pscustomobject]@{ Status = 'PASS'; Detail = (Test-DefensiveDenySet -Fixture $fixture) } }
            Invoke-SmokeCheck -Name ("seeded-audit-{0}" -f $fixture.scenario) -Action { [pscustomobject]@{ Status = 'PASS'; Detail = (Test-AuditTrailSet -Fixture $fixture) } }
        }
    }

    Write-Output ''
    Write-Output 'Smoke test summary'
    $script:Results | Format-Table -AutoSize | Out-String | Write-Output
    exit 0
}
finally {
    if (Test-Path -LiteralPath $script:RuntimeRoot) {
        Remove-Item -LiteralPath $script:RuntimeRoot -Recurse -Force -ErrorAction SilentlyContinue
    }
}
