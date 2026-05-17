#Requires -Version 7.0

<#!
.SYNOPSIS
    Seeds deterministic lab data for the agent-intake solution.

.DESCRIPTION
    Creates five request scenarios that cover the Express, Standard, Full, and
    defensive deny paths. The script uses deterministic request IDs so reruns are
    idempotent. By default, it creates the request and declared data-source rows.
    When -RunClassifierInline is set, it also mirrors the routing result into the
    intake tables, reviewer rows, decision-log evidence, drift handoff payloads,
    and the Tier-1 MRM handoff bridge.

.PARAMETER EnvironmentUrl
    Dataverse environment URL.

.PARAMETER RunClassifierInline
    Calls the local classifier and writes the derived fields and downstream lab
    evidence directly. Use this mode when the Power Automate router flow is not
    available in the lab.

.PARAMETER Cleanup
    Deletes only the deterministic seeded lab data.

.PARAMETER DryRun
    Logs the actions that would run without writing to Dataverse.

.EXAMPLE
    pwsh .\seed-test-data.ps1 -EnvironmentUrl https://contoso.crm.dynamics.com -RunClassifierInline

.EXAMPLE
    pwsh .\seed-test-data.ps1 -EnvironmentUrl https://contoso.crm.dynamics.com -Cleanup
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$EnvironmentUrl,

    [switch]$RunClassifierInline,

    [switch]$Cleanup,

    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$InformationPreference = 'Continue'

$script:TargetEnvironmentUrl = $EnvironmentUrl
$script:RunClassifierInlineRequested = [bool]$RunClassifierInline
$script:CleanupRequested = [bool]$Cleanup
$script:IsDryRun = [bool]$DryRun

$script:SolutionRoot = Split-Path -Path $PSScriptRoot -Parent
$script:FixtureRoot = Join-Path -Path $PSScriptRoot -ChildPath 'seed-test-data'
$script:RuntimeRoot = Join-Path -Path $PSScriptRoot -ChildPath '.seed-runtime'
$script:PolicyTablesPath = Join-Path -Path $script:SolutionRoot -ChildPath 'templates\policy-lookup-tables.yaml'
$script:DriftSchemaPath = Join-Path -Path $script:SolutionRoot -ChildPath 'templates\drift-handoff-payload-schema.json'
$script:MrmSchemaPath = Join-Path -Path $script:SolutionRoot -ChildPath 'templates\mrm-handoff-payload-schema.json'
$script:FullBoardDecisionPath = Join-Path -Path $script:FixtureRoot -ChildPath 'reviewer-decisions-full-board.json'
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
$script:ChoiceMap = @{
    'fsi_acv_zone' = @{
        'Unclassified' = 100000000
        'Zone 1 (Enterprise)' = 100000001
        'Zone 2 (Team)' = 100000002
        'Zone 3 (Personal)' = 100000003
    }
    'fsi_intake_pathused' = @{
        'Express' = 100000000
        'Standard' = 100000001
        'Full' = 100000002
    }
    'fsi_intake_status' = @{
        'Draft' = 100000000
        'Submitted' = 100000001
        'AwaitingSponsor' = 100000002
        'AwaitingReviewers' = 100000003
        'Approved' = 100000004
        'Denied' = 100000005
        'Withdrawn' = 100000006
        'Escalated' = 100000007
        'AutoApproved' = 100000008
        'DeferredOutOfScope' = 100000009
        'SponsorTimeout' = 100000010
    }
    'fsi_intake_routingtopology' = @{
        'Sequential' = 100000000
        'Parallel' = 100000001
        'Quorum' = 100000002
    }
    'fsi_intake_risktier' = @{
        'Tier 1 (High)' = 100000000
        'Tier 2 (Medium)' = 100000001
        'Tier 3 (Low)' = 100000002
    }
    'fsi_intake_agenttype' = @{
        'Agent Builder (M365 Copilot)' = 100000000
        'Copilot Studio (classic)' = 100000001
        'Declarative Agent (M365 Copilot)' = 100000002
        'Custom Engine Agent' = 100000003
        'Azure AI Foundry / Pro-Dev' = 100000004
    }
    'fsi_intake_dataclassification' = @{
        'Public' = 100000000
        'Internal' = 100000001
        'Confidential' = 100000002
        'Restricted' = 100000003
    }
    'fsi_intake_reviewerrole' = @{
        'InfoSec' = 100000000
        'Privacy' = 100000001
        'Compliance' = 100000002
        'Legal' = 100000003
        'MRM' = 100000004
        'Sponsor' = 100000005
        'Sponsor Manager' = 100000006
    }
    'fsi_intake_reviewdecision' = @{
        'Pending' = 100000000
        'Approved' = 100000001
        'Approved with conditions' = 100000002
        'Denied' = 100000003
        'Recused' = 100000004
        'Timeout' = 100000005
    }
    'fsi_intake_mrmhandoffstatus' = @{
        'Pending' = 100000000
        'Handed off' = 100000001
        'NotApplicable' = 100000002
        'Failed' = 100000003
    }
    'fsi_intake_decisionoutcome' = @{
        'Approved' = 100000000
        'AutoApproved' = 100000001
        'Denied' = 100000002
        'EscalatedToManager' = 100000003
        'WithdrawnByMaker' = 100000004
    }
}
$script:TriggerSignalMap = [ordered]@{
    fsi_t1initiatesfinancialtxn = 'FinancialTxn'
    fsi_t2customerfacing = 'CustomerFacing'
    fsi_t3autonomousunmonitored = 'AutonomousUnmonitored'
    fsi_t4handlesnpi = 'Npi'
    fsi_t5handlesmnpi = 'Mnpi'
    fsi_t6crossborderdata = 'CrossBorder'
}
$script:FixtureFiles = @(
    'request-express-happy.json',
    'request-standard-conditional.json',
    'request-full-parallel-board.json',
    'request-cross-border-deny.json',
    'request-sponsor-self-approval-deny.json'
)
$script:SummaryRows = [System.Collections.Generic.List[object]]::new()
$script:EnvironmentMetadata = $null
$script:DataverseToken = $null

function Write-Info {
    param([Parameter(Mandatory)][string]$Message)
    Write-Information "[seed-test-data] $Message" -InformationAction Continue
}

function Write-WarnMessage {
    param([Parameter(Mandatory)][string]$Message)
    Write-Warning "[seed-test-data] $Message"
}

function Add-SummaryRow {
    param(
        [Parameter(Mandatory)][string]$Scenario,
        [Parameter(Mandatory)][string]$Status,
        [Parameter(Mandatory)][string]$Detail
    )

    $script:SummaryRows.Add([pscustomobject]@{
            Scenario = $Scenario
            Status = $Status
            Detail = $Detail
        }) | Out-Null
}

function Initialize-RuntimeDirectory {
    if (-not (Test-Path -LiteralPath $script:RuntimeRoot)) {
        New-Item -ItemType Directory -Path $script:RuntimeRoot | Out-Null
    }
}

function Remove-RuntimeDirectory {
    [CmdletBinding(SupportsShouldProcess)]
    param()

    if ((Test-Path -LiteralPath $script:RuntimeRoot) -and $PSCmdlet.ShouldProcess($script:RuntimeRoot, 'Remove runtime directory')) {
        Remove-Item -LiteralPath $script:RuntimeRoot -Recurse -Force -ErrorAction SilentlyContinue
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

function Get-DataverseAccessToken {
    param([switch]$Force)

    if ($DryRun) {
        return 'dry-run-token'
    }

    if ($Force) {
        $script:DataverseToken = $null
    }

    if (-not [string]::IsNullOrWhiteSpace($script:DataverseToken)) {
        return $script:DataverseToken
    }

    if (-not $Force) {
        $envToken = $env:DATAVERSE_ACCESS_TOKEN
        if (-not [string]::IsNullOrWhiteSpace($envToken)) {
            $script:DataverseToken = $envToken.Trim()
            return $script:DataverseToken
        }
    }

    $az = Get-Command -Name 'az' -ErrorAction SilentlyContinue
    if ($null -ne $az) {
        try {
            $token = & $az.Source account get-access-token --resource $EnvironmentUrl --query accessToken -o tsv 2>$null
            if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace($token)) {
                $script:DataverseToken = $token.Trim()
                return $script:DataverseToken
            }
        }
        catch {
            Write-WarnMessage "Azure CLI token acquisition failed: $_"
        }
    }

    if (Get-Command -Name 'Get-AzAccessToken' -ErrorAction SilentlyContinue) {
        try {
            $script:DataverseToken = (Get-AzAccessToken -ResourceUrl $EnvironmentUrl).Token
            return $script:DataverseToken
        }
        catch {
            Write-WarnMessage "Az.Accounts token acquisition failed: $_"
        }
    }

    throw 'Could not acquire a Dataverse access token. Authenticate with az login or make a DATAVERSE_ACCESS_TOKEN available.'
}

function Get-PythonTokenSource {
    $az = Get-Command -Name 'az' -ErrorAction SilentlyContinue
    if ($null -ne $az) {
        try {
            & $az.Source account show --only-show-errors 1>$null 2>$null
            if ($LASTEXITCODE -eq 0) {
                return 'cli'
            }
        }
        catch {
            Write-Verbose 'Azure CLI context probe was unavailable.'
        }
    }

    return 'mi'
}

function Get-DataverseHeader {
    param([Parameter(Mandatory)][string]$Token)

    return @{
        Authorization = "Bearer $Token"
        Accept = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version' = '4.0'
    }
}

function ConvertTo-ODataStringLiteral {
    param([Parameter(Mandatory)][string]$Value)

    return "'{0}'" -f $Value.Replace("'", "''")
}

function Invoke-DataverseRequest {
    param(
        [Parameter(Mandatory)]
        [ValidateSet('GET', 'POST', 'PATCH', 'DELETE')]
        [string]$Method,

        [Parameter(Mandatory)]
        [string]$RelativeUri,

        [Parameter()]
        [object]$Body,

        [switch]$AllowNotFound
    )

    $uri = '{0}/api/data/v9.2/{1}' -f $EnvironmentUrl.TrimEnd('/'), $RelativeUri.TrimStart('/')
    if ($DryRun) {
        Write-Info "[DRY RUN] $Method $uri"
        if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
            Write-Info ((ConvertTo-Json -InputObject $Body -Depth 20 -Compress))
        }

        return [pscustomobject]@{
            StatusCode = 200
            Body = $null
            Headers = @{}
        }
    }

    $headers = Get-DataverseHeader -Token (Get-DataverseAccessToken)
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        $headers['Content-Type'] = 'application/json; charset=utf-8'
    }

    $bodyJson = $null
    if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
        $bodyJson = ConvertTo-Json -InputObject $Body -Depth 20 -Compress
    }

    $response = Invoke-WebRequest -Uri $uri -Method $Method -Headers $headers -Body $bodyJson -UseBasicParsing -SkipHttpErrorCheck
    if ($response.StatusCode -eq 401) {
        Write-Info "Dataverse token rejected (HTTP 401); refreshing and retrying $Method $RelativeUri."
        $headers = Get-DataverseHeader -Token (Get-DataverseAccessToken -Force)
        if ($PSBoundParameters.ContainsKey('Body') -and $null -ne $Body) {
            $headers['Content-Type'] = 'application/json; charset=utf-8'
        }
        $response = Invoke-WebRequest -Uri $uri -Method $Method -Headers $headers -Body $bodyJson -UseBasicParsing -SkipHttpErrorCheck
    }
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

    return [pscustomobject]@{
        StatusCode = [int]$response.StatusCode
        Body = $payload
        Headers = $response.Headers
    }
}

function Get-RecordWithoutNull {
    param([Parameter(Mandatory)][hashtable]$InputObject)

    $clean = [ordered]@{}
    foreach ($entry in $InputObject.GetEnumerator()) {
        if ($null -ne $entry.Value) {
            $clean[$entry.Key] = $entry.Value
        }
    }

    return $clean
}

function Read-JsonFile {
    param([Parameter(Mandatory)][string]$Path)

    return Get-Content -LiteralPath $Path -Raw | ConvertFrom-Json -AsHashtable
}

function Get-PolicyDocument {
    return Get-Content -LiteralPath $script:PolicyTablesPath -Raw | ConvertFrom-Yaml
}

function Get-ChoiceValue {
    param(
        [Parameter(Mandatory)][string]$ChoiceSet,
        [Parameter(Mandatory)][string]$Label
    )

    if ($Label -match '^\d+$') {
        return [int]$Label
    }

    $map = $script:ChoiceMap[$ChoiceSet]
    if ($null -eq $map -or -not $map.ContainsKey($Label)) {
        throw "Choice '$Label' was not found in '$ChoiceSet'."
    }

    return [int]$map[$Label]
}

function Get-RoutingTopologyLabel {
    param([Parameter(Mandatory)][string]$PathUsed)

    switch ($PathUsed) {
        'Express' { return 'Sequential' }
        'Standard' { return 'Quorum' }
        'Full' { return 'Parallel' }
        default { throw "Unsupported path '$PathUsed'." }
    }
}

function Get-ReviewApprovalOutcome {
    param([Parameter(Mandatory)][string]$ReviewDecision)

    switch ($ReviewDecision) {
        'Approved' { return 'Approved' }
        'Approved with conditions' { return 'Approved' }
        'Denied' { return 'Denied' }
        default { return $null }
    }
}

function Get-ReviewerDecisionForMrm {
    param([Parameter(Mandatory)][string]$ReviewDecision)

    switch ($ReviewDecision) {
        'Approved' { return 'Approved' }
        'Approved with conditions' { return 'ApprovedWithConditions' }
        'Denied' { return 'Rejected' }
        'Timeout' { return 'Pending' }
        default { return 'NoAction' }
    }
}

function Get-HighestDeclaredClassification {
    param([Parameter(Mandatory)][object[]]$DataSources)

    $ranking = @{
        Public = 0
        Internal = 1
        Confidential = 2
        Restricted = 3
    }

    $resolved = 'Public'
    foreach ($source in $DataSources) {
        $label = [string]$source.classification
        if ($ranking[$label] -gt $ranking[$resolved]) {
            $resolved = $label
        }
    }

    return $resolved
}

function Get-DriftDataSource {
    param([Parameter(Mandatory)][object[]]$DataSources)

    $items = @()
    foreach ($source in $DataSources) {
        $items += [ordered]@{
            dataSourceName = [string]$source.name
            dataSourceType = [string]$source.type
            dataClassification = [string]$source.classification
            isCustomerData = [bool]$source.isCustomerData
            isRestricted = [bool]$source.isRestricted
            dataResidencyCountry = [string]$source.dataResidencyCountry
        }
    }

    return $items
}

function Get-MrmDataSource {
    param([Parameter(Mandatory)][object[]]$DataSources)

    $items = @()
    foreach ($source in $DataSources) {
        $classification = if ([bool]$source.isRestricted) {
            'MNPI'
        }
        elseif ([bool]$source.isCustomerData) {
            'NPI'
        }
        else {
            [string]$source.classification
        }

        $items += [ordered]@{
            name = [string]$source.name
            type = [string]$source.type
            classification = $classification
            residencyCountry = [string]$source.dataResidencyCountry
            customerData = [bool]$source.isCustomerData
            restricted = [bool]$source.isRestricted
        }
    }

    return $items
}

function ConvertTo-UtcString {
    param([Parameter(Mandatory)][datetime]$Value)

    return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ')
}

function Get-ScenarioTimeline {
    param([Parameter(Mandatory)][int]$ScenarioIndex)

    $base = (Get-Date).ToUniversalTime().AddMinutes((-30) - ($ScenarioIndex * 7))
    return [ordered]@{
        submitted = ConvertTo-UtcString -Value $base
        routed = ConvertTo-UtcString -Value $base.AddMinutes(1)
        sponsor = ConvertTo-UtcString -Value $base.AddMinutes(2)
        reviewOne = ConvertTo-UtcString -Value $base.AddMinutes(3)
        reviewTwo = ConvertTo-UtcString -Value $base.AddMinutes(4)
        reviewThree = ConvertTo-UtcString -Value $base.AddMinutes(5)
        decided = ConvertTo-UtcString -Value $base.AddMinutes(6)
        stamped = ConvertTo-UtcString -Value $base.AddMinutes(7)
    }
}

function Get-Sha256Hex {
    param([Parameter(Mandatory)][string]$Text)

    $hashBytes = [System.Security.Cryptography.SHA256]::HashData([System.Text.Encoding]::UTF8.GetBytes($Text))
    return ([System.BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
}

function Get-RequestRecordGuid {
    param([Parameter(Mandatory)][string]$RequestId)

    if ($DryRun) {
        return $null
    }

    $filter = "fsi_requestid eq {0}" -f (ConvertTo-ODataStringLiteral -Value $RequestId)
    $records = @(Get-RecordsByFilter -LogicalName 'fsi_intakerequest' -Filter $filter -Select 'fsi_intakerequestid')
    if ($records.Count -eq 0) {
        return $null
    }

    return [string]$records[0].fsi_intakerequestid
}

function Get-RequestLookupUri {
    param([Parameter(Mandatory)][string]$RequestId)

    $guid = Get-RequestRecordGuid -RequestId $RequestId
    if ([string]::IsNullOrWhiteSpace($guid)) {
        return $null
    }

    return 'fsi_intakerequests({0})' -f $guid
}

function Set-RequestRecord {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$RequestId,
        [Parameter(Mandatory)][hashtable]$Body
    )

    if (-not $PSCmdlet.ShouldProcess($RequestId, 'Upsert intake request row')) {
        return
    }

    $body = Get-RecordWithoutNull -InputObject $Body
    $existingUri = Get-RequestLookupUri -RequestId $RequestId
    if ($existingUri) {
        Invoke-DataverseRequest -Method PATCH -RelativeUri $existingUri -Body $body | Out-Null
    }
    else {
        $entityInfo = $script:EntityMap['fsi_intakerequest']
        Invoke-DataverseRequest -Method POST -RelativeUri $entityInfo.EntitySetName -Body $body | Out-Null
    }
}

function Add-EntityRecord {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$LogicalName,
        [Parameter(Mandatory)][hashtable]$Body
    )

    $entityInfo = $script:EntityMap[$LogicalName]
    if ($PSCmdlet.ShouldProcess($LogicalName, 'Create Dataverse record')) {
        Invoke-DataverseRequest -Method POST -RelativeUri $entityInfo.EntitySetName -Body (Get-RecordWithoutNull -InputObject $Body) | Out-Null
    }
}

function Get-RecordsByFilter {
    param(
        [Parameter(Mandatory)][string]$LogicalName,
        [Parameter(Mandatory)][string]$Filter,
        [Parameter()][string]$Select
    )

    if ($DryRun) {
        return [object[]]@()
    }

    $entityInfo = $script:EntityMap[$LogicalName]
    $select = if ([string]::IsNullOrWhiteSpace($Select)) { $entityInfo.PrimaryIdAttribute } else { $Select }
    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("{0}?`$select={1}&`$filter={2}" -f $entityInfo.EntitySetName, $select, $Filter)
    return @($response.Body.value)
}

function Remove-RecordByFilter {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$LogicalName,
        [Parameter(Mandatory)][string]$Filter
    )

    $entityInfo = $script:EntityMap[$LogicalName]
    $records = @(Get-RecordsByFilter -LogicalName $LogicalName -Filter $Filter -Select $entityInfo.PrimaryIdAttribute)
    if (-not $PSCmdlet.ShouldProcess($LogicalName, 'Delete Dataverse record set')) {
        return 0
    }

    foreach ($record in $records) {
        $id = $record[$entityInfo.PrimaryIdAttribute]
        Invoke-DataverseRequest -Method DELETE -RelativeUri ('{0}({1})' -f $entityInfo.EntitySetName, $id) | Out-Null
    }

    return $records.Count
}

function Get-EntityMetadataRecord {
    param([Parameter(Mandatory)][string]$LogicalName)

    if ($DryRun) {
        return $null
    }

    $response = Invoke-DataverseRequest -Method GET -RelativeUri ("EntityDefinitions(LogicalName='{0}')?`$select=EntitySetName,PrimaryIdAttribute,LogicalName" -f $LogicalName) -AllowNotFound
    if ($null -eq $response) {
        return $null
    }

    return $response.Body
}

function Remove-ExternalMrmArtifact {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][string]$RequestId,
        [Parameter(Mandatory)][string]$PlatformAgentId
    )

    if ($DryRun) {
        Write-Info "[DRY RUN] Would remove downstream MRM bridge artifacts for $RequestId."
        return
    }

    if (-not $PSCmdlet.ShouldProcess($RequestId, 'Remove downstream MRM bridge artifacts')) {
        return
    }

    $queueEntity = Get-EntityMetadataRecord -LogicalName 'fsi_modelinventory'
    if ($null -ne $queueEntity) {
        $queueFilter = "fsi_agentid eq {0} and fsi_environmentid eq {1}" -f (ConvertTo-ODataStringLiteral -Value $PlatformAgentId), (ConvertTo-ODataStringLiteral -Value ([string]$script:EnvironmentMetadata.OrganizationId))
        $records = Invoke-DataverseRequest -Method GET -RelativeUri ("{0}?`$select={1}&`$filter={2}" -f $queueEntity.EntitySetName, $queueEntity.PrimaryIdAttribute, $queueFilter)
        foreach ($record in @($records.Body.value)) {
            Invoke-DataverseRequest -Method DELETE -RelativeUri ('{0}({1})' -f $queueEntity.EntitySetName, $record[$queueEntity.PrimaryIdAttribute]) | Out-Null
        }
    }

    $eventEntity = Get-EntityMetadataRecord -LogicalName 'fsi_mrmcomplianceevent'
    if ($null -ne $eventEntity) {
        $eventFilter = "fsi_previousvalue eq {0}" -f (ConvertTo-ODataStringLiteral -Value $RequestId)
        $records = Invoke-DataverseRequest -Method GET -RelativeUri ("{0}?`$select={1}&`$filter={2}" -f $eventEntity.EntitySetName, $eventEntity.PrimaryIdAttribute, $eventFilter)
        foreach ($record in @($records.Body.value)) {
            Invoke-DataverseRequest -Method DELETE -RelativeUri ('{0}({1})' -f $eventEntity.EntitySetName, $record[$eventEntity.PrimaryIdAttribute]) | Out-Null
        }
    }
}

function Get-SeedFixture {
    $fixtures = @()
    foreach ($file in $script:FixtureFiles) {
        $fixtures += Read-JsonFile -Path (Join-Path -Path $script:FixtureRoot -ChildPath $file)
    }

    return $fixtures
}

function Get-FullBoardReviewPlan {
    return (Read-JsonFile -Path $script:FullBoardDecisionPath).decisions
}

function Get-ReviewPlan {
    param([Parameter(Mandatory)][hashtable]$Fixture)

    switch ($Fixture.scenario) {
        'standard-conditional' {
            return @(
                [ordered]@{
                    role = 'InfoSec'
                    upn = [string]$Fixture.reviewers.InfoSec
                    decision = 'Approved with conditions'
                    notes = 'Keep the rollout limited to the named sales-operations team and complete a quarterly access review.'
                    conditionsText = 'Quarterly access review required before widening beyond the named sales-operations team.'
                    decisionMethod = 'ReviewerApp'
                    quorumWeight = 1
                },
                [ordered]@{
                    role = 'Privacy'
                    upn = [string]$Fixture.reviewers.Privacy
                    decision = 'Approved'
                    notes = 'Customer data remains in the approved United States tenancy.'
                    conditionsText = ''
                    decisionMethod = 'ReviewerApp'
                    quorumWeight = 1
                },
                [ordered]@{
                    role = 'Compliance'
                    upn = [string]$Fixture.reviewers.Compliance
                    decision = 'Approved'
                    notes = 'Supervisory evidence and retention settings are aligned to the pilot scope.'
                    conditionsText = ''
                    decisionMethod = 'ReviewerApp'
                    quorumWeight = 1
                }
            )
        }
        'full-parallel-board' {
            return @(Get-FullBoardReviewPlan)
        }
        default {
            return [object[]]@()
        }
    }
}

function Get-ApprovedReviewerCount {
    param([Parameter()][object[]]$ReviewPlan = @())

    return @($ReviewPlan | Where-Object { $_.decision -in @('Approved', 'Approved with conditions') }).Count
}

function Get-ConsolidatedConditionsText {
    param([Parameter()][object[]]$ReviewPlan = @())

    $values = @($ReviewPlan | Where-Object { -not [string]::IsNullOrWhiteSpace($_.conditionsText) } | ForEach-Object { [string]$_.conditionsText })
    return ($values -join ' ')
}

function Invoke-LocalClassifier {
    param([Parameter(Mandatory)][hashtable]$Fixture)

    Initialize-RuntimeDirectory
    $python = Get-PythonCommand
    $fixturePath = Join-Path -Path $script:FixtureRoot -ChildPath ('request-{0}.json' -f $Fixture.scenario)
    $code = @"
import json
import sys
from pathlib import Path
sys.path.insert(0, r"$PSScriptRoot")
import seed_classification_rules as classifier
fixture = json.loads(Path(r"$fixturePath").read_text(encoding="utf-8"))
policy = classifier.load_policy(Path(r"$script:PolicyTablesPath"))
result = classifier.classify(fixture["fsi_intakerequest"], policy)
print(json.dumps(result))
"@

    $raw = & $python -c $code 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Local classifier failed for $($Fixture.scenario): $($raw -join ' ')"
    }

    return (($raw -join [Environment]::NewLine) | ConvertFrom-Json -AsHashtable)
}

function Assert-ClassificationExpectation {
    param(
        [Parameter(Mandatory)][hashtable]$Fixture,
        [Parameter(Mandatory)][hashtable]$Classification
    )

    $expected = $Fixture.expectedClassification
    $checks = @{
        pathUsed = [string]$expected.pathUsed
        decisionPath = [string]$expected.decisionPath
        riskTier = [string]$expected.riskTier
        quorumRequired = [int]$expected.quorumRequired
    }

    foreach ($entry in $checks.GetEnumerator()) {
        if ([string]$Classification[$entry.Key] -ne [string]$entry.Value) {
            throw "Classification mismatch for $($Fixture.scenario): expected $($entry.Key)=$($entry.Value), got $($Classification[$entry.Key])."
        }
    }

    $expectedZone = [string]$expected.zone
    $actualZone = if ($Classification.ContainsKey('zoneLabel')) { [string]$Classification.zoneLabel } else { [string]$Classification.zone }
    if ($expectedZone -ne $actualZone) {
        throw "Classification mismatch for $($Fixture.scenario): expected zone=$expectedZone, got $actualZone."
    }

    if ($expected.ContainsKey('routingReason')) {
        $expectedReason = [string]$expected.routingReason
        $actualReason = [string]$Classification.routingReason
        if ($expectedReason -ne $actualReason) {
            throw "Classification mismatch for $($Fixture.scenario): expected routingReason=$expectedReason, got $actualReason."
        }
    }
}

function Get-ClassificationPayload {
    param(
        [Parameter(Mandatory)][hashtable]$Fixture
    )

    if ($RunClassifierInline) {
        $classification = Invoke-LocalClassifier -Fixture $Fixture
        Assert-ClassificationExpectation -Fixture $Fixture -Classification $classification
        return $classification
    }

    $expected = $Fixture.expectedClassification
    $pathUsed = [string]$expected.pathUsed
    $reviewPlan = @(Get-ReviewPlan -Fixture $Fixture)
    $mrmRequired = ([string]$expected.riskTier -eq 'Tier 1 (High)')
    return [ordered]@{
        decisionPath = [string]$expected.decisionPath
        pathUsed = $pathUsed
        routingReason = if ($expected.ContainsKey('routingReason')) { [string]$expected.routingReason } else { $null }
        riskTier = [string]$expected.riskTier
        zoneLabel = [string]$expected.zone
        quorumRequired = [int]$expected.quorumRequired
        parallelReviewers = @($reviewPlan | ForEach-Object { $_.role })
        triggerHits = @($script:TriggerSignalMap.Keys | Where-Object { $Fixture.fsi_intakerequest[$_] -eq 'Yes' -or $Fixture.fsi_intakerequest[$_] -eq 'Not sure' }).Count
        mrmRequired = $mrmRequired
    }
}

function Get-DecisionPack {
    param(
        [Parameter(Mandatory)][hashtable]$Fixture,
        [Parameter(Mandatory)][hashtable]$Classification,
        [Parameter(Mandatory)][hashtable]$PolicyDocument,
        [Parameter(Mandatory)][string]$FinalDecision,
        [Parameter(Mandatory)][string]$SponsorCardHash,
        [Parameter(Mandatory)][hashtable]$Timeline,
        [Parameter()][object[]]$ReviewPlan = @(),
        [Parameter(Mandatory)][string]$RetentionLabel
    )

    return [ordered]@{
        scenario = [string]$Fixture.scenario
        requestId = [string]$Fixture.fsi_intakerequest.fsi_requestid
        agentDisplayName = [string]$Fixture.fsi_intakerequest.fsi_agentdisplayname
        finalDecision = $FinalDecision
        decisionPath = [string]$Classification.decisionPath
        pathUsed = [string]$Classification.pathUsed
        riskTier = [string]$Classification.riskTier
        zone = [string]$Classification.zoneLabel
        quorumRequired = [int]$Classification.quorumRequired
        approvedReviewerCount = Get-ApprovedReviewerCount -ReviewPlan $ReviewPlan
        quorumAchieved = ((Get-ApprovedReviewerCount -ReviewPlan $ReviewPlan) -ge [int]$Classification.quorumRequired)
        policyVersion = [string]$PolicyDocument.schema_version
        retentionLabel = $RetentionLabel
        sponsor = [ordered]@{
            role = [string]$Fixture.sponsorRole
            upn = [string]$Fixture.fsi_intakerequest.fsi_sponsorupn
            attestationCardHash = $SponsorCardHash
            decidedOnUtc = [string]$Timeline.sponsor
        }
        reviewers = @($ReviewPlan | ForEach-Object {
                [ordered]@{
                    role = [string]$_.role
                    upn = [string]$_.upn
                    decision = [string]$_.decision
                    conditionsText = [string]$_.conditionsText
                }
            })
        declaredDataSources = Get-DriftDataSource -DataSources $Fixture.dataSources
        routingReason = [string]$Classification.routingReason
    }
}

function Test-JsonSchema {
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
    $raw = & $python -c $code 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "$Label schema validation failed: $($raw -join ' ')"
    }
}

function Get-DriftPayload {
    param(
        [Parameter(Mandatory)][hashtable]$Fixture,
        [Parameter(Mandatory)][hashtable]$Classification,
        [Parameter(Mandatory)][hashtable]$PolicyDocument,
        [Parameter(Mandatory)][string]$DecisionPackHash,
        [Parameter(Mandatory)][string]$EntraAgentId,
        [Parameter(Mandatory)][string]$RegistryRecordId,
        [Parameter(Mandatory)][string]$SponsorCardHash,
        [Parameter(Mandatory)][hashtable]$Timeline,
        [Parameter()][object[]]$ReviewPlan = @(),
        [Parameter(Mandatory)][string]$MrmStatus,
        [Parameter(Mandatory)][string]$RetentionLabel,
        [Parameter(Mandatory)][string]$FinalDecision
    )

    $reviewerAttestations = @($ReviewPlan |
        ForEach-Object {
            [ordered]@{
                role = [string]$_.role
                upn = [string]$_.upn
                decidedOnUtc = [string]$Timeline.decided
                decisionPackHash = $DecisionPackHash
                conditionsText = [string]$_.conditionsText
            }
        })

    return [ordered]@{
        payloadVersion = [string]$PolicyDocument.schema_version
        originIntakeId = [string]$Fixture.fsi_intakerequest.fsi_requestid
        pathUsed = [string]$Classification.pathUsed
        riskTier = [string]$Classification.riskTier
        zone = [string]$Classification.zoneLabel
        declaredAudience = [string]$Fixture.fsi_intakerequest.fsi_intendedaudience
        intendedAudience = [string]$Fixture.fsi_intakerequest.fsi_intendedaudience
        declaredDataSourcesJson = (@(Get-DriftDataSource -DataSources $Fixture.dataSources) | ConvertTo-Json -Depth 10 -Compress)
        declaredDataSources = @(Get-DriftDataSource -DataSources $Fixture.dataSources)
        connectorAllowlist = @($Fixture.dataSources | ForEach-Object { [string]$_.type } | Select-Object -Unique)
        sponsorUpn = [string]$Fixture.fsi_intakerequest.fsi_sponsorupn
        sponsor = [ordered]@{
            role = [string]$Fixture.sponsorRole
            upn = [string]$Fixture.fsi_intakerequest.fsi_sponsorupn
            attestationCardHash = $SponsorCardHash
            decidedOnUtc = [string]$Timeline.sponsor
        }
        reviewerAttestations = $reviewerAttestations
        mrmHandoffStatus = $MrmStatus
        policyVersion = [string]$PolicyDocument.schema_version
        retentionLabel = $RetentionLabel
        decisionPackHash = $DecisionPackHash
        entraAgentId = $EntraAgentId
        agentDisplayName = [string]$Fixture.fsi_intakerequest.fsi_agentdisplayname
        agentType = [string]$Fixture.fsi_intakerequest.fsi_agenttype
        decisionOutcome = $FinalDecision
        targetEnvironmentId = [string]$script:EnvironmentMetadata.OrganizationId
        targetEnvironmentName = [string]$script:EnvironmentMetadata.FriendlyName
        registryRecordId = $RegistryRecordId
        auditPointer = ('dataverse://fsi_intakedecisionlog/{0}' -f $Fixture.fsi_intakerequest.fsi_requestid)
        conditionsText = (Get-ConsolidatedConditionsText -ReviewPlan $ReviewPlan)
    }
}

function Get-MrmPayload {
    param(
        [Parameter(Mandatory)][hashtable]$Fixture,
        [Parameter(Mandatory)][hashtable]$Classification,
        [Parameter(Mandatory)][hashtable]$PolicyDocument,
        [Parameter(Mandatory)][string]$DecisionPackHash,
        [Parameter(Mandatory)][string]$EntraAgentId,
        [Parameter(Mandatory)][string]$SponsorCardHash,
        [Parameter(Mandatory)][hashtable]$Timeline,
        [Parameter()][object[]]$ReviewPlan = @()
    )

    return [ordered]@{
        '$schema' = 'https://judeper.github.io/FSI-AgentGov-Solutions/schemas/mrm-handoff-payload-v1.json'
        payloadVersion = '1.0.0'
        intake = [ordered]@{
            requestId = [string]$Fixture.fsi_intakerequest.fsi_requestid
            submittedOnUtc = [string]$Timeline.submitted
            pathUsed = 'Full'
            riskTier = 'Tier 1 (High)'
            zone = [string]$Classification.zoneLabel
            mrmRequired = $true
        }
        agent = [ordered]@{
            displayName = [string]$Fixture.fsi_intakerequest.fsi_agentdisplayname
            agentType = [string]$Fixture.fsi_intakerequest.fsi_agenttype
            platformAgentId = [string]$Fixture.fsi_intakerequest.fsi_requestid
            environmentId = [string]$script:EnvironmentMetadata.OrganizationId
            entraAgentId = $EntraAgentId
            intendedAudience = [string]$Fixture.fsi_intakerequest.fsi_intendedaudience
            businessOutcome = [string]$Fixture.fsi_intakerequest.fsi_businessoutcome
            businessJustification = [string]$Fixture.fsi_intakerequest.fsi_businessjustification
        }
        maker = [ordered]@{
            upn = [string]$Fixture.fsi_intakerequest.fsi_makerupn
            displayName = [string]$Fixture.fsi_intakerequest.fsi_makerdisplayname
            department = [string]$Fixture.fsi_intakerequest.fsi_makerdepartment
            country = [string]$Fixture.fsi_intakerequest.fsi_makercountry
        }
        model = [ordered]@{
            vendorOrInternal = 'Vendor'
            modelFamily = 'GPT-4 class model'
            providerName = 'OpenAI'
            providerModelId = 'gpt-4.1'
            decisionOutputType = 'Decision Support'
            materiality = 'High'
            fineTuned = $false
            championChallengerPlan = 'Annual challenger review before production widening.'
            knownLimitations = @('Human reviewer must confirm all adverse-action wording before issue.')
        }
        data = [ordered]@{
            declaredSources = @(Get-MrmDataSource -DataSources $Fixture.dataSources)
            crossBorder = ([string]$Fixture.fsi_intakerequest.fsi_t6crossborderdata -eq 'Yes')
            npiInvolved = ([string]$Fixture.fsi_intakerequest.fsi_t4handlesnpi -eq 'Yes')
            mnpiInvolved = ([string]$Fixture.fsi_intakerequest.fsi_t5handlesmnpi -eq 'Yes')
        }
        controls = [ordered]@{
            humanOversightLevel = 'L3'
            explainabilityArtifacts = @('Decision memo', 'Reviewer board minutes', 'Pilot controls checklist')
        }
        sponsor = [ordered]@{
            upn = [string]$Fixture.fsi_intakerequest.fsi_sponsorupn
            displayName = [string]$Fixture.fsi_intakerequest.fsi_sponsorupn
            attestationCardHash = $SponsorCardHash
        }
        reviewers = @($ReviewPlan | ForEach-Object {
                [ordered]@{
                    role = [string]$_.role
                    upn = [string]$_.upn
                    decision = (Get-ReviewerDecisionForMrm -ReviewDecision ([string]$_.decision))
                    decidedOnUtc = [string]$Timeline.decided
                    decisionPackHash = $DecisionPackHash
                }
            })
        routing = [ordered]@{
            mrmOfficerUpn = [string]$Fixture.seedArtifacts.mrmOfficerUpn
            auditorUpn = [string]$Fixture.seedArtifacts.auditorUpn
        }
        decisionPackHash = $DecisionPackHash
        retentionLabel = [string]$PolicyDocument.retention_labels.decision_log
        policyVersion = [string]$PolicyDocument.schema_version
    }
}

function Get-AgentIdAttestation {
    param(
        [Parameter(Mandatory)][hashtable]$Fixture,
        [Parameter(Mandatory)][string]$DecisionPackHash,
        [Parameter(Mandatory)][hashtable]$Timeline,
        [Parameter()][object[]]$ReviewPlan = @(),
        [Parameter(Mandatory)][string]$PathUsed
    )

    $attestations = [System.Collections.Generic.List[hashtable]]::new()
    $attestations.Add([ordered]@{
            role = 'Sponsor'
            upn = [string]$Fixture.fsi_intakerequest.fsi_sponsorupn
            decidedOnUtc = [string]$Timeline.sponsor
            decisionPackHash = $DecisionPackHash
        }) | Out-Null

    if ($PathUsed -ne 'Express') {
        foreach ($review in $ReviewPlan | Where-Object { $_.decision -in @('Approved', 'Approved with conditions') }) {
            $attestations.Add([ordered]@{
                    role = [string]$review.role
                    upn = [string]$review.upn
                    decidedOnUtc = [string]$Timeline.decided
                    decisionPackHash = $DecisionPackHash
                }) | Out-Null
        }
    }

    return @($attestations)
}

function Resolve-AgentIdValue {
    param(
        [Parameter(Mandatory)][hashtable]$Fixture,
        [Parameter(Mandatory)][string]$DecisionPackHash,
        [Parameter(Mandatory)][hashtable]$Timeline,
        [Parameter()][object[]]$ReviewPlan = @(),
        [Parameter(Mandatory)][string]$PathUsed
    )

    if (-not [bool]$Fixture.expectedOutcome.agentIdExpected) {
        return [pscustomobject]@{
            Value = $null
            MintMode = 'NotApplicable'
        }
    }

    $liveAgentToggle = $env:AGENT_INTAKE_LIVE_AGENT_ID
    $liveRequested = (-not [string]::IsNullOrWhiteSpace($liveAgentToggle)) -and ($liveAgentToggle -match '^(1|true|yes)$')
    $synthetic = [string]$Fixture.seedArtifacts.syntheticEntraAgentId
    if (-not $liveRequested) {
        return [pscustomobject]@{
            Value = $synthetic
            MintMode = 'Synthetic'
        }
    }

    $blueprintId = $env:AGENT_INTAKE_AGENT_BLUEPRINT_ID
    if ([string]::IsNullOrWhiteSpace($blueprintId)) {
        Write-WarnMessage 'AGENT_INTAKE_AGENT_BLUEPRINT_ID is not set. Falling back to deterministic synthetic Agent IDs for seeded data.'
        return [pscustomobject]@{
            Value = $synthetic
            MintMode = 'Synthetic'
        }
    }

    Initialize-RuntimeDirectory
    $outputPath = Join-Path -Path $script:RuntimeRoot -ChildPath ('{0}-agent-id.json' -f $Fixture.scenario)
    $attestations = Get-AgentIdAttestation -Fixture $Fixture -DecisionPackHash $DecisionPackHash -Timeline $Timeline -ReviewPlan $ReviewPlan -PathUsed $PathUsed
    $arguments = @(
        (Join-Path -Path $PSScriptRoot -ChildPath 'setup_entra_agent_id.py'),
        '--intake-request-id', [string]$Fixture.fsi_intakerequest.fsi_requestid,
        '--display-name', [string]$Fixture.fsi_intakerequest.fsi_agentdisplayname,
        '--sponsor-upn', [string]$Fixture.fsi_intakerequest.fsi_sponsorupn,
        '--blueprint-id', $blueprintId.Trim(),
        '--approval-path', $PathUsed,
        '--output', $outputPath,
        '--token-source', (Get-PythonTokenSource)
    )
    if ($PathUsed -ne 'Express') {
        $arguments += @('--reviewer-attestations-json', (($attestations | ConvertTo-Json -Depth 8 -Compress)))
    }

    $python = Get-PythonCommand
    $output = & $python @arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-WarnMessage "Live Agent ID mint failed. Falling back to deterministic synthetic Agent IDs. Details: $($output -join ' ')"
        return [pscustomobject]@{
            Value = $synthetic
            MintMode = 'Synthetic'
        }
    }

    $payload = Read-JsonFile -Path $outputPath
    if (-not $payload.ContainsKey('id')) {
        Write-WarnMessage 'Live Agent ID mint did not return an id property. Falling back to deterministic synthetic Agent IDs.'
        return [pscustomobject]@{
            Value = $synthetic
            MintMode = 'Synthetic'
        }
    }

    return [pscustomobject]@{
        Value = [string]$payload.id
        MintMode = 'Live'
    }
}

function Invoke-MrmHandoff {
    param(
        [Parameter(Mandatory)][hashtable]$Fixture,
        [Parameter(Mandatory)][hashtable]$Payload
    )

    if (-not [bool]$Fixture.expectedOutcome.mrmExpected) {
        return [pscustomobject]@{
            Status = 'NotApplicable'
            ExitCode = 0
            Detail = 'MRM handoff is not required for this scenario.'
        }
    }

    Initialize-RuntimeDirectory
    $payloadPath = Join-Path -Path $script:RuntimeRoot -ChildPath ('{0}-mrm-payload.json' -f $Fixture.scenario)
    $resultPath = Join-Path -Path $script:RuntimeRoot -ChildPath ('{0}-mrm-result.json' -f $Fixture.scenario)
    $Payload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $payloadPath -Encoding utf8
    Test-JsonSchema -SchemaPath $script:MrmSchemaPath -PayloadPath $payloadPath -Label 'MRM handoff payload'

    if ($DryRun) {
        Write-Info "[DRY RUN] Would invoke handoff_mrm.py for $($Fixture.scenario)."
        return [pscustomobject]@{
            Status = 'Pending'
            ExitCode = 0
            Detail = 'Dry-run only.'
        }
    }

    $python = Get-PythonCommand
    $arguments = @(
        (Join-Path -Path $PSScriptRoot -ChildPath 'handoff_mrm.py'),
        '--environment-url', $EnvironmentUrl,
        '--input-json', $payloadPath,
        '--output', $resultPath,
        '--token-source', (Get-PythonTokenSource),
        '--intake-request-id', [string]$Fixture.fsi_intakerequest.fsi_requestid
    )
    $output = & $python @arguments 2>&1
    $exitCode = $LASTEXITCODE
    if ($exitCode -notin @(0, 2)) {
        throw "handoff_mrm.py failed for $($Fixture.scenario): $($output -join ' ')"
    }

    $result = if (Test-Path -LiteralPath $resultPath) { Read-JsonFile -Path $resultPath } else { @{ detail = ($output -join ' ') } }
    return [pscustomobject]@{
        Status = if ($exitCode -eq 0) { 'Completed' } else { 'Pending' }
        ExitCode = $exitCode
        Detail = (($result | ConvertTo-Json -Depth 20 -Compress))
    }
}

function Get-RequestRecordPayload {
    param(
        [Parameter(Mandatory)][hashtable]$Fixture,
        [Parameter(Mandatory)][hashtable]$Classification,
        [Parameter(Mandatory)][hashtable]$PolicyDocument,
        [Parameter(Mandatory)][string]$HighestClassification,
        [Parameter(Mandatory)][string]$DeclaredDataSourcesJson,
        [Parameter(Mandatory)][string]$ParallelReviewersJson,
        [Parameter(Mandatory)][string]$FinalDecision,
        [Parameter(Mandatory)][string]$MrmStatusLabel,
        [Parameter()][string]$EntraAgentId,
        [Parameter()][string]$RegistryRecordId,
        [Parameter(Mandatory)][hashtable]$Timeline
    )

    $statusLabel = if ($FinalDecision -eq 'Denied') { 'Denied' } else { 'Approved' }
    $request = $Fixture.fsi_intakerequest
    $extendedQuestions = if ([string]$Classification.pathUsed -in @('Standard', 'Full')) {
        [ordered]@{
            seededScenario = [string]$Fixture.scenario
            runClassifierInline = [bool]$RunClassifierInline
            expectedClassification = $Fixture.expectedClassification
        } | ConvertTo-Json -Depth 10 -Compress
    }
    else {
        $null
    }

    return [ordered]@{
        fsi_name = ('{0} - {1}' -f $Fixture.scenario, $request.fsi_agentdisplayname)
        fsi_requestid = [string]$request.fsi_requestid
        fsi_agentdisplayname = [string]$request.fsi_agentdisplayname
        fsi_agenttype = Get-ChoiceValue -ChoiceSet 'fsi_intake_agenttype' -Label ([string]$request.fsi_agenttype)
        fsi_businessoutcome = [string]$request.fsi_businessoutcome
        fsi_businessjustification = [string]$request.fsi_businessjustification
        fsi_makerupn = [string]$request.fsi_makerupn
        fsi_makerdepartment = [string]$request.fsi_makerdepartment
        fsi_makercountry = [string]$request.fsi_makercountry
        fsi_makerdisplayname = [string]$request.fsi_makerdisplayname
        fsi_makerjobtitle = [string]$request.fsi_makerjobtitle
        fsi_sponsorupn = [string]$request.fsi_sponsorupn
        fsi_intendedaudience = [string]$request.fsi_intendedaudience
        fsi_t1initiatesfinancialtxn = [string]$request.fsi_t1initiatesfinancialtxn
        fsi_t2customerfacing = [string]$request.fsi_t2customerfacing
        fsi_t3autonomousunmonitored = [string]$request.fsi_t3autonomousunmonitored
        fsi_t4handlesnpi = [string]$request.fsi_t4handlesnpi
        fsi_t5handlesmnpi = [string]$request.fsi_t5handlesmnpi
        fsi_t6crossborderdata = [string]$request.fsi_t6crossborderdata
        fsi_makerattestation = [bool]$request.fsi_makerattestation
        fsi_pathused = Get-ChoiceValue -ChoiceSet 'fsi_intake_pathused' -Label ([string]$Classification.pathUsed)
        fsi_routingtopology = Get-ChoiceValue -ChoiceSet 'fsi_intake_routingtopology' -Label (Get-RoutingTopologyLabel -PathUsed ([string]$Classification.pathUsed))
        fsi_risktier = Get-ChoiceValue -ChoiceSet 'fsi_intake_risktier' -Label ([string]$Classification.riskTier)
        fsi_zone = Get-ChoiceValue -ChoiceSet 'fsi_acv_zone' -Label ([string]$Classification.zoneLabel)
        fsi_dataclassification = Get-ChoiceValue -ChoiceSet 'fsi_intake_dataclassification' -Label $HighestClassification
        fsi_status = Get-ChoiceValue -ChoiceSet 'fsi_intake_status' -Label $statusLabel
        fsi_targetenvironmentid = [string]$script:EnvironmentMetadata.OrganizationId
        fsi_targetenvironmentname = [string]$script:EnvironmentMetadata.FriendlyName
        fsi_environmentmanaged = $true
        fsi_dlppolicyoutcome = 'seeded-lab-data'
        fsi_decisionpath = [string]$Classification.decisionPath
        fsi_triggerhitcount = [int]$Classification.triggerHits
        fsi_quorumrequired = [int]$Classification.quorumRequired
        fsi_parallelreviewersjson = $ParallelReviewersJson
        fsi_dataresidencycountry = [string]$request.fsi_dataresidencycountry
        fsi_retentionyears = [int]$PolicyDocument.sponsor_attestation.retention_years
        fsi_immutablestorage = [bool]$PolicyDocument.sponsor_attestation.immutable
        fsi_privacyoverride = [bool]$request.fsi_privacyoverride
        fsi_mrmrequired = [bool]$Classification.mrmRequired
        fsi_mrmhandoffstatus = Get-ChoiceValue -ChoiceSet 'fsi_intake_mrmhandoffstatus' -Label $MrmStatusLabel
        fsi_declareddatasourcesjson = $DeclaredDataSourcesJson
        fsi_standardfullquestionsjson = $extendedQuestions
        fsi_entraagentid = $EntraAgentId
        fsi_registryrecordid = $RegistryRecordId
        fsi_submittedon = [string]$Timeline.submitted
        fsi_decidedon = [string]$Timeline.decided
        fsi_policyversionapplied = [string]$PolicyDocument.schema_version
    }
}

function Get-DataSourcePayload {
    param(
        [Parameter(Mandatory)][hashtable]$Fixture
    )

    $items = @()
    $index = 0
    foreach ($source in $Fixture.dataSources) {
        $index++
        $items += [ordered]@{
            fsi_name = ('{0} - data-source-{1}' -f $Fixture.scenario, $index)
            fsi_requestid = [string]$Fixture.fsi_intakerequest.fsi_requestid
            fsi_datasourcename = [string]$source.name
            fsi_datasourcetype = [string]$source.type
            fsi_dataclassification = Get-ChoiceValue -ChoiceSet 'fsi_intake_dataclassification' -Label ([string]$source.classification)
            fsi_iscustomerdata = [bool]$source.isCustomerData
            fsi_isrestricted = [bool]$source.isRestricted
        }
    }

    return $items
}

function Get-RiskSignalPayload {
    param(
        [Parameter(Mandatory)][hashtable]$Fixture,
        [Parameter(Mandatory)][hashtable]$Timeline
    )

    $items = @()
    foreach ($entry in $script:TriggerSignalMap.GetEnumerator()) {
        $items += [ordered]@{
            fsi_name = ('{0} - {1}' -f $Fixture.scenario, $entry.Key)
            fsi_requestid = [string]$Fixture.fsi_intakerequest.fsi_requestid
            fsi_triggercode = ($entry.Key -replace '^fsi_', '').Replace('initiatesfinancialtxn', 'T1').Replace('customerfacing', 'T2').Replace('autonomousunmonitored', 'T3').Replace('handlesnpi', 'T4').Replace('handlesmnpi', 'T5').Replace('crossborderdata', 'T6')
            fsi_triggeranswer = [string]$Fixture.fsi_intakerequest[$entry.Key]
            fsi_derivedsignal = if ($Fixture.fsi_intakerequest[$entry.Key] -eq 'No') { $null } else { [string]$entry.Value }
            fsi_capturedon = [string]$Timeline.submitted
        }
    }

    return $items
}

function Get-SponsorshipPayload {
    param(
        [Parameter(Mandatory)][hashtable]$Fixture,
        [Parameter(Mandatory)][hashtable]$PolicyDocument,
        [Parameter(Mandatory)][string]$SponsorCardHash,
        [Parameter(Mandatory)][hashtable]$Timeline
    )

    return [ordered]@{
        fsi_name = ('{0} - sponsorship' -f $Fixture.scenario)
        fsi_requestid = [string]$Fixture.fsi_intakerequest.fsi_requestid
        fsi_sponsorupn = [string]$Fixture.fsi_intakerequest.fsi_sponsorupn
        fsi_sponsorrole = [string]$Fixture.sponsorRole
        fsi_attestationtext = [string]$PolicyDocument.sponsor_attestation.card_text
        fsi_attestedon = [string]$Timeline.sponsor
        fsi_attestationmethod = 'TeamsAdaptiveCard'
        fsi_renderedcardhash = $SponsorCardHash
        fsi_isvalid = $true
    }
}

function Get-ReviewPayload {
    param(
        [Parameter(Mandatory)][hashtable]$Fixture,
        [Parameter()][object[]]$ReviewPlan = @(),
        [Parameter(Mandatory)][hashtable]$Timeline,
        [Parameter(Mandatory)][string]$PathUsed
    )

    $items = @()
    $counter = 0
    foreach ($review in $ReviewPlan) {
        $counter++
        $completedOn = switch ($counter) {
            1 { [string]$Timeline.reviewOne }
            2 { [string]$Timeline.reviewTwo }
            default { [string]$Timeline.reviewThree }
        }
        $items += [ordered]@{
            fsi_name = ('{0} - review - {1}' -f $Fixture.scenario, $review.role)
            fsi_requestid = [string]$Fixture.fsi_intakerequest.fsi_requestid
            fsi_reviewerrole = Get-ChoiceValue -ChoiceSet 'fsi_intake_reviewerrole' -Label ([string]$review.role)
            fsi_reviewerupn = [string]$review.upn
            fsi_reviewtype = $PathUsed
            fsi_reviewoutcome = Get-ChoiceValue -ChoiceSet 'fsi_intake_reviewdecision' -Label ([string]$review.decision)
            fsi_reviewnotes = [string]$review.notes
            fsi_quorumweight = [int]$review.quorumWeight
            fsi_dueon = [string]$Timeline.decided
            fsi_conditionstext = [string]$review.conditionsText
            fsi_startedon = [string]$Timeline.routed
            fsi_completedon = $completedOn
        }
    }

    return $items
}

function Get-ApprovalPayload {
    param(
        [Parameter(Mandatory)][hashtable]$Fixture,
        [Parameter()][object[]]$ReviewPlan = @(),
        [Parameter(Mandatory)][string]$DecisionPackHash,
        [Parameter(Mandatory)][hashtable]$Timeline
    )

    $items = @(
        [ordered]@{
            fsi_name = ('{0} - approval - Sponsor' -f $Fixture.scenario)
            fsi_requestid = [string]$Fixture.fsi_intakerequest.fsi_requestid
            fsi_approverrole = Get-ChoiceValue -ChoiceSet 'fsi_intake_reviewerrole' -Label 'Sponsor'
            fsi_approverupn = [string]$Fixture.fsi_intakerequest.fsi_sponsorupn
            fsi_decisionoutcome = Get-ChoiceValue -ChoiceSet 'fsi_intake_decisionoutcome' -Label 'Approved'
            fsi_decidedon = [string]$Timeline.sponsor
            fsi_decisionmethod = 'TeamsAdaptiveCard'
            fsi_decisioncontexthash = $DecisionPackHash
            fsi_clientipaddress = '127.0.0.1'
        }
    )

    foreach ($review in $ReviewPlan) {
        $approvalOutcome = Get-ReviewApprovalOutcome -ReviewDecision ([string]$review.decision)
        if ([string]::IsNullOrWhiteSpace($approvalOutcome)) {
            continue
        }

        $items += [ordered]@{
            fsi_name = ('{0} - approval - {1}' -f $Fixture.scenario, $review.role)
            fsi_requestid = [string]$Fixture.fsi_intakerequest.fsi_requestid
            fsi_approverrole = Get-ChoiceValue -ChoiceSet 'fsi_intake_reviewerrole' -Label ([string]$review.role)
            fsi_approverupn = [string]$review.upn
            fsi_decisionoutcome = Get-ChoiceValue -ChoiceSet 'fsi_intake_decisionoutcome' -Label $approvalOutcome
            fsi_decidedon = [string]$Timeline.decided
            fsi_decisionmethod = [string]$review.decisionMethod
            fsi_decisioncontexthash = $DecisionPackHash
            fsi_clientipaddress = '127.0.0.1'
        }
    }

    return $items
}

function Get-DecisionLogPayload {
    param(
        [Parameter(Mandatory)][hashtable]$Fixture,
        [Parameter(Mandatory)][hashtable]$Classification,
        [Parameter(Mandatory)][string]$FinalDecision,
        [Parameter(Mandatory)][string]$DecisionPackJson,
        [Parameter(Mandatory)][string]$DecisionPackHash,
        [Parameter(Mandatory)][string]$RetentionLabel,
        [Parameter(Mandatory)][hashtable]$Timeline,
        [Parameter(Mandatory)][hashtable]$PolicyDocument
    )

    return [ordered]@{
        fsi_name = ('{0} - decision-log' -f $Fixture.scenario)
        fsi_requestid = [string]$Fixture.fsi_intakerequest.fsi_requestid
        fsi_decisionoutcome = Get-ChoiceValue -ChoiceSet 'fsi_intake_decisionoutcome' -Label $FinalDecision
        fsi_risktier = Get-ChoiceValue -ChoiceSet 'fsi_intake_risktier' -Label ([string]$Classification.riskTier)
        fsi_zone = Get-ChoiceValue -ChoiceSet 'fsi_acv_zone' -Label ([string]$Classification.zoneLabel)
        fsi_pathused = Get-ChoiceValue -ChoiceSet 'fsi_intake_pathused' -Label ([string]$Classification.pathUsed)
        fsi_policyversionapplied = [string]$PolicyDocument.schema_version
        fsi_decisionpackjson = $DecisionPackJson
        fsi_decisionpackhash = $DecisionPackHash
        fsi_decidedon = [string]$Timeline.decided
        fsi_retentionlabelapplied = $RetentionLabel
        fsi_retentionlabelappliedon = [string]$Timeline.stamped
    }
}

function Get-RetentionRecordPayload {
    param(
        [Parameter(Mandatory)][hashtable]$Fixture,
        [Parameter(Mandatory)][string]$RetentionLabel,
        [Parameter(Mandatory)][hashtable]$PolicyDocument,
        [Parameter(Mandatory)][hashtable]$Timeline
    )

    return [ordered]@{
        fsi_name = ('{0} - retention' -f $Fixture.scenario)
        fsi_requestid = [string]$Fixture.fsi_intakerequest.fsi_requestid
        fsi_labelname = $RetentionLabel
        fsi_retentionyears = [int]$PolicyDocument.sponsor_attestation.retention_years
        fsi_stampedon = [string]$Timeline.stamped
        fsi_stampedby = 'seed-test-data.ps1'
        fsi_regulatorybasis = 'SEC 17a-4, FINRA 4511, CFTC 1.31'
    }
}

function Get-AuditEventPayload {
    param(
        [Parameter(Mandatory)][hashtable]$Fixture,
        [Parameter(Mandatory)][hashtable]$Classification,
        [Parameter(Mandatory)][string]$FinalDecision,
        [Parameter(Mandatory)][string]$DecisionPackHash,
        [Parameter(Mandatory)][string]$MrmStatus,
        [Parameter()][hashtable]$DriftPayload,
        [Parameter()]$MrmResult,
        [Parameter(Mandatory)][hashtable]$Timeline,
        [Parameter()][string]$AgentIdValue,
        [Parameter(Mandatory)][string]$AgentIdMode,
        [Parameter()][object[]]$ReviewPlan = @()
    )

    $events = [System.Collections.Generic.List[hashtable]]::new()
    $requestId = [string]$Fixture.fsi_intakerequest.fsi_requestid
    $events.Add([ordered]@{
            fsi_name = ('{0} - audit - Submitted' -f $Fixture.scenario)
            fsi_requestid = $requestId
            fsi_eventtype = 'Submitted'
            fsi_pathphase = 'Submitted'
            fsi_actorupn = [string]$Fixture.fsi_intakerequest.fsi_makerupn
            fsi_eventon = [string]$Timeline.submitted
            fsi_eventpayloadjson = (@{ scenario = $Fixture.scenario; decisionPackHash = $DecisionPackHash } | ConvertTo-Json -Compress)
        }) | Out-Null
    $events.Add([ordered]@{
            fsi_name = ('{0} - audit - Routed' -f $Fixture.scenario)
            fsi_requestid = $requestId
            fsi_eventtype = 'Routed'
            fsi_pathphase = 'RouterRouted'
            fsi_actorupn = 'system'
            fsi_eventon = [string]$Timeline.routed
            fsi_eventpayloadjson = (@{ pathUsed = $Classification.pathUsed; decisionPath = $Classification.decisionPath; routingReason = $Classification.routingReason } | ConvertTo-Json -Compress)
        }) | Out-Null

    if ($FinalDecision -eq 'Approved') {
        $events.Add([ordered]@{
                fsi_name = ('{0} - audit - SponsorClicked' -f $Fixture.scenario)
                fsi_requestid = $requestId
                fsi_eventtype = 'SponsorClicked'
                fsi_pathphase = 'SponsorAttested'
                fsi_actorupn = [string]$Fixture.fsi_intakerequest.fsi_sponsorupn
                fsi_eventon = [string]$Timeline.sponsor
                fsi_eventpayloadjson = (@{ scenario = $Fixture.scenario } | ConvertTo-Json -Compress)
            }) | Out-Null
    }

    if ($ReviewPlan.Count -gt 0) {
        $events.Add([ordered]@{
                fsi_name = ('{0} - audit - ReviewerQueued' -f $Fixture.scenario)
                fsi_requestid = $requestId
                fsi_eventtype = 'ReviewerQueued'
                fsi_pathphase = 'ReviewerQueued'
                fsi_actorupn = 'system'
                fsi_eventon = [string]$Timeline.routed
                fsi_eventpayloadjson = (@{ reviewers = @($ReviewPlan | ForEach-Object { $_.role }) } | ConvertTo-Json -Compress)
            }) | Out-Null

        foreach ($review in $ReviewPlan) {
            $events.Add([ordered]@{
                    fsi_name = ('{0} - audit - ReviewerDecided - {1}' -f $Fixture.scenario, $review.role)
                    fsi_requestid = $requestId
                    fsi_eventtype = 'ReviewerDecided'
                    fsi_pathphase = 'ReviewerDecided'
                    fsi_actorupn = [string]$review.upn
                    fsi_eventon = [string]$Timeline.decided
                    fsi_eventpayloadjson = (@{ role = $review.role; decision = $review.decision; conditionsText = $review.conditionsText } | ConvertTo-Json -Compress)
                }) | Out-Null
        }
    }

    if ($FinalDecision -eq 'Denied') {
        $events.Add([ordered]@{
                fsi_name = ('{0} - audit - Denied' -f $Fixture.scenario)
                fsi_requestid = $requestId
                fsi_eventtype = 'Denied'
                fsi_pathphase = 'RouterRouted'
                fsi_actorupn = 'system'
                fsi_eventon = [string]$Timeline.decided
                fsi_eventpayloadjson = (@{ routingReason = $Classification.routingReason } | ConvertTo-Json -Compress)
            }) | Out-Null
        return @($events)
    }

    $events.Add([ordered]@{
            fsi_name = ('{0} - audit - Approved' -f $Fixture.scenario)
            fsi_requestid = $requestId
            fsi_eventtype = 'Approved'
            fsi_pathphase = 'Handed off'
            fsi_actorupn = 'system'
            fsi_eventon = [string]$Timeline.decided
            fsi_eventpayloadjson = (@{ decisionPackHash = $DecisionPackHash } | ConvertTo-Json -Compress)
        }) | Out-Null
    $events.Add([ordered]@{
            fsi_name = ('{0} - audit - EntraAgentIdMinted' -f $Fixture.scenario)
            fsi_requestid = $requestId
            fsi_eventtype = 'EntraAgentIdMinted'
            fsi_pathphase = 'Handed off'
            fsi_actorupn = 'system'
            fsi_eventon = [string]$Timeline.decided
            fsi_eventpayloadjson = (@{ entraAgentId = $AgentIdValue; mintMode = $AgentIdMode } | ConvertTo-Json -Compress)
        }) | Out-Null
    if ($null -ne $DriftPayload) {
        $events.Add([ordered]@{
                fsi_name = ('{0} - audit - DriftHandoffPrepared' -f $Fixture.scenario)
                fsi_requestid = $requestId
                fsi_eventtype = 'DriftHandoffPrepared'
                fsi_pathphase = 'Handed off'
                fsi_actorupn = 'system'
                fsi_eventon = [string]$Timeline.decided
                fsi_eventpayloadjson = ($DriftPayload | ConvertTo-Json -Depth 20 -Compress)
            }) | Out-Null
    }
    if ($Classification.mrmRequired) {
        $eventType = if ($MrmStatus -eq 'Completed') { 'MRMHandoffSubmitted' } else { 'MRMHandoffPending' }
        $events.Add([ordered]@{
                fsi_name = ('{0} - audit - {1}' -f $Fixture.scenario, $eventType)
                fsi_requestid = $requestId
                fsi_eventtype = $eventType
                fsi_pathphase = 'Handed off'
                fsi_actorupn = 'system'
                fsi_eventon = [string]$Timeline.decided
                fsi_eventpayloadjson = if ($null -ne $MrmResult) { ($MrmResult | ConvertTo-Json -Depth 20 -Compress) } else { '{}' }
            }) | Out-Null
    }
    $events.Add([ordered]@{
            fsi_name = ('{0} - audit - HandoffComplete' -f $Fixture.scenario)
            fsi_requestid = $requestId
            fsi_eventtype = 'HandoffComplete'
            fsi_pathphase = 'Handed off'
            fsi_actorupn = 'system'
            fsi_eventon = [string]$Timeline.decided
            fsi_eventpayloadjson = (@{ drift = ($null -ne $DriftPayload); mrm = $Classification.mrmRequired } | ConvertTo-Json -Compress)
        }) | Out-Null
    $events.Add([ordered]@{
            fsi_name = ('{0} - audit - RetentionStamped' -f $Fixture.scenario)
            fsi_requestid = $requestId
            fsi_eventtype = 'RetentionStamped'
            fsi_pathphase = 'Handed off'
            fsi_actorupn = 'system'
            fsi_eventon = [string]$Timeline.stamped
            fsi_eventpayloadjson = (@{ label = $PolicyDocument.retention_labels.decision_log } | ConvertTo-Json -Compress)
        }) | Out-Null

    return @($events)
}

function Remove-ScenarioRecord {
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)][hashtable]$Fixture
    )

    $requestId = [string]$Fixture.fsi_intakerequest.fsi_requestid
    $filter = "fsi_requestid eq {0}" -f (ConvertTo-ODataStringLiteral -Value $requestId)

    foreach ($logicalName in @(
            'fsi_intakeretentionrecord',
            'fsi_intakeauditevent',
            'fsi_intakedecisionlog',
            'fsi_intakeapproval',
            'fsi_intakereview',
            'fsi_intakesponsorship',
            'fsi_intakerisksignal',
            'fsi_intakedatasource'
        )) {
        $removed = Remove-RecordByFilter -LogicalName $logicalName -Filter $filter
        if ($removed -gt 0) {
            Write-Info "Removed $removed row(s) from $logicalName for request $requestId."
        }
    }

    if ($DryRun) {
        Write-Info "[DRY RUN] Would delete request row for $requestId."
    }
    elseif ($PSCmdlet.ShouldProcess($requestId, 'Delete seeded request row')) {
        $lookupUri = Get-RequestLookupUri -RequestId $requestId
        if ($lookupUri) {
            Invoke-DataverseRequest -Method DELETE -RelativeUri $lookupUri -AllowNotFound | Out-Null
        }
    }

    Remove-ExternalMrmArtifact -RequestId $requestId -PlatformAgentId $requestId
}

function Invoke-ScenarioSeed {
    param(
        [Parameter(Mandatory)][hashtable]$Fixture,
        [Parameter(Mandatory)][hashtable]$PolicyDocument,
        [Parameter(Mandatory)][int]$ScenarioIndex
    )

    $requestId = [string]$Fixture.fsi_intakerequest.fsi_requestid
    Remove-ScenarioRecord -Fixture $Fixture

    $classification = Get-ClassificationPayload -Fixture $Fixture
    $classification.zoneLabel = if ($classification.ContainsKey('zoneLabel')) { [string]$classification.zoneLabel } else { [string]$Fixture.expectedClassification.zone }
    $reviewPlan = @(Get-ReviewPlan -Fixture $Fixture)
    $timeline = Get-ScenarioTimeline -ScenarioIndex $ScenarioIndex
    $sponsorCardHash = Get-Sha256Hex -Text (([string]$PolicyDocument.sponsor_attestation.card_text) + '|' + $requestId)
    $decisionLabel = [string]$Fixture.expectedOutcome.decisionOutcome
    $retentionLabel = [string]$PolicyDocument.retention_labels.decision_log
    $declaredDataSources = @(Get-DriftDataSource -DataSources $Fixture.dataSources)
    $declaredDataSourcesJson = ConvertTo-Json -InputObject $declaredDataSources -Depth 10 -Compress
    $parallelReviewerSet = @($reviewPlan | ForEach-Object {
            [ordered]@{
                role = [string]$_.role
                upn = [string]$_.upn
                quorumWeight = [int]$_.quorumWeight
                decision = [string]$_.decision
            }
        })
    $parallelReviewersJson = ConvertTo-Json -InputObject $parallelReviewerSet -Depth 10 -Compress

    $decisionPack = Get-DecisionPack -Fixture $Fixture -Classification $classification -PolicyDocument $PolicyDocument -FinalDecision $decisionLabel -SponsorCardHash $sponsorCardHash -Timeline $timeline -ReviewPlan $reviewPlan -RetentionLabel $retentionLabel
    $decisionPackJson = $decisionPack | ConvertTo-Json -Depth 20 -Compress
    $decisionPackHash = Get-Sha256Hex -Text $decisionPackJson
    $agentId = Resolve-AgentIdValue -Fixture $Fixture -DecisionPackHash $decisionPackHash -Timeline $timeline -ReviewPlan $reviewPlan -PathUsed ([string]$classification.pathUsed)
    $registryRecordId = if ([bool]$Fixture.expectedOutcome.agentIdExpected) { [string]$Fixture.seedArtifacts.registryRecordId } else { $null }
    $mrmPayload = $null
    $mrmResult = $null
    $mrmStatus = if ([bool]$Fixture.expectedOutcome.mrmExpected) { 'Pending' } else { 'NotApplicable' }
    if ($RunClassifierInline -and [bool]$Fixture.expectedOutcome.mrmExpected) {
        $mrmPayload = Get-MrmPayload -Fixture $Fixture -Classification $classification -PolicyDocument $PolicyDocument -DecisionPackHash $decisionPackHash -EntraAgentId ([string]$agentId.Value) -SponsorCardHash $sponsorCardHash -Timeline $timeline -ReviewPlan $reviewPlan
        $mrmResult = Invoke-MrmHandoff -Fixture $Fixture -Payload $mrmPayload
        $mrmStatus = [string]$mrmResult.Status
    }

    $driftPayload = $null
    if ($RunClassifierInline -and [bool]$Fixture.expectedOutcome.driftPayloadExpected) {
        $driftPayload = Get-DriftPayload -Fixture $Fixture -Classification $classification -PolicyDocument $PolicyDocument -DecisionPackHash $decisionPackHash -EntraAgentId ([string]$agentId.Value) -RegistryRecordId $registryRecordId -SponsorCardHash $sponsorCardHash -Timeline $timeline -ReviewPlan $reviewPlan -MrmStatus $mrmStatus -RetentionLabel $retentionLabel -FinalDecision $decisionLabel
        Initialize-RuntimeDirectory
        $driftPath = Join-Path -Path $script:RuntimeRoot -ChildPath ('{0}-drift-payload.json' -f $Fixture.scenario)
        $driftPayload | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $driftPath -Encoding utf8
        Test-JsonSchema -SchemaPath $script:DriftSchemaPath -PayloadPath $driftPath -Label 'Drift handoff payload'
    }

    $mrmStatusLabel = if ($mrmStatus -eq 'Completed') { 'Handed off' } elseif ($mrmStatus -eq 'Pending') { 'Pending' } else { 'NotApplicable' }
    $requestPayload = Get-RequestRecordPayload -Fixture $Fixture -Classification $classification -PolicyDocument $PolicyDocument -HighestClassification (Get-HighestDeclaredClassification -DataSources $Fixture.dataSources) -DeclaredDataSourcesJson $declaredDataSourcesJson -ParallelReviewersJson $parallelReviewersJson -FinalDecision $decisionLabel -MrmStatusLabel $mrmStatusLabel -EntraAgentId ([string]$agentId.Value) -RegistryRecordId $registryRecordId -Timeline $timeline
    Set-RequestRecord -RequestId $requestId -Body $requestPayload

    foreach ($payload in Get-DataSourcePayload -Fixture $Fixture) {
        Add-EntityRecord -LogicalName 'fsi_intakedatasource' -Body $payload
    }

    if ($RunClassifierInline) {
        foreach ($payload in Get-RiskSignalPayload -Fixture $Fixture -Timeline $timeline) {
            Add-EntityRecord -LogicalName 'fsi_intakerisksignal' -Body $payload
        }

        if ($decisionLabel -eq 'Approved') {
            Add-EntityRecord -LogicalName 'fsi_intakesponsorship' -Body (Get-SponsorshipPayload -Fixture $Fixture -PolicyDocument $PolicyDocument -SponsorCardHash $sponsorCardHash -Timeline $timeline)
            foreach ($payload in Get-ApprovalPayload -Fixture $Fixture -ReviewPlan $reviewPlan -DecisionPackHash $decisionPackHash -Timeline $timeline) {
                Add-EntityRecord -LogicalName 'fsi_intakeapproval' -Body $payload
            }
        }

        foreach ($payload in Get-ReviewPayload -Fixture $Fixture -ReviewPlan $reviewPlan -Timeline $timeline -PathUsed ([string]$classification.pathUsed)) {
            Add-EntityRecord -LogicalName 'fsi_intakereview' -Body $payload
        }

        Add-EntityRecord -LogicalName 'fsi_intakedecisionlog' -Body (Get-DecisionLogPayload -Fixture $Fixture -Classification $classification -FinalDecision $decisionLabel -DecisionPackJson $decisionPackJson -DecisionPackHash $decisionPackHash -RetentionLabel $retentionLabel -Timeline $timeline -PolicyDocument $PolicyDocument)
        Add-EntityRecord -LogicalName 'fsi_intakeretentionrecord' -Body (Get-RetentionRecordPayload -Fixture $Fixture -RetentionLabel $retentionLabel -PolicyDocument $PolicyDocument -Timeline $timeline)
        foreach ($payload in Get-AuditEventPayload -Fixture $Fixture -Classification $classification -FinalDecision $decisionLabel -DecisionPackHash $decisionPackHash -MrmStatus $mrmStatus -DriftPayload $driftPayload -MrmResult $mrmResult -Timeline $timeline -AgentIdValue ([string]$agentId.Value) -AgentIdMode ([string]$agentId.MintMode) -ReviewPlan $reviewPlan) {
            Add-EntityRecord -LogicalName 'fsi_intakeauditevent' -Body $payload
        }
    }

    $detail = if ($RunClassifierInline) {
        '{0} seeded with inline routing, {1} review row(s), final decision {2}.' -f $requestId, $reviewPlan.Count, $decisionLabel
    }
    else {
        '{0} seeded for downstream router pickup.' -f $requestId
    }
    Add-SummaryRow -Scenario ([string]$Fixture.scenario) -Status 'SEEDED' -Detail $detail
}

function Get-EnvironmentMetadataRecord {
    if ($DryRun) {
        $script:EnvironmentMetadata = [ordered]@{
            OrganizationId = '00000000-0000-4000-8000-000000000000'
            FriendlyName = ([System.Uri]$EnvironmentUrl).Host
        }
        return
    }

    $response = Invoke-DataverseRequest -Method GET -RelativeUri 'WhoAmI'
    $script:EnvironmentMetadata = [ordered]@{
        OrganizationId = [string]$response.Body.OrganizationId
        FriendlyName = ([System.Uri]$EnvironmentUrl).Host
    }
}

try {
    if (-not (Test-Path -LiteralPath $script:PolicyTablesPath)) {
        throw "Policy table file not found: $script:PolicyTablesPath"
    }

    Get-EnvironmentMetadataRecord
    $policyDocument = Get-PolicyDocument
    $fixtures = Get-SeedFixture

    if ($Cleanup) {
        foreach ($fixture in $fixtures) {
            Remove-ScenarioRecord -Fixture $fixture
            Add-SummaryRow -Scenario ([string]$fixture.scenario) -Status 'REMOVED' -Detail ([string]$fixture.fsi_intakerequest.fsi_requestid)
        }

        if (($env:AGENT_INTAKE_LIVE_AGENT_ID) -match '^(1|true|yes)$') {
            Write-WarnMessage 'Live Agent ID cleanup is not automated. If you opted into live minting, remove the corresponding Microsoft Entra Agent IDs manually before reusing the tenant.'
        }
    }
    else {
        $index = 0
        foreach ($fixture in $fixtures) {
            $index++
            Invoke-ScenarioSeed -Fixture $fixture -PolicyDocument $policyDocument -ScenarioIndex $index
        }
    }

    if ($script:SummaryRows.Count -gt 0) {
        Write-Output ''
        Write-Output 'Seed test data summary'
        $script:SummaryRows | Format-Table -AutoSize | Out-String | Write-Output
    }
}
finally {
    Remove-RuntimeDirectory
}



