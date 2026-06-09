<#
.SYNOPSIS
    Evaluates Copilot consumption entitlement using the switch-on-pathway contract and
    produces per-agent coverage-gap aggregates (monitor-only).

.DESCRIPTION
    Implements the entitlement contract in docs/entitlement-contract.md. For each
    agent it classifies the consumption pathway FIRST (none / mcp-cs /
    mcp-agentbuilder / api-direct / metered / unmapped) from createdIn (Azure Resource
    Graph) and configuredTier (Work IQ), then applies pathway-specific eligibility for
    each intended user:

      - none              -> ALLOW (eligibility N/A); unblocks the agent majority.
      - mcp-agentbuilder  -> license required.
      - api-direct        -> API audience cohort required.
      - mcp-cs            -> license AND (zero-rating resolved AND surface zero-rated,
                             OR user in credit scope); otherwise FAIL-CLOSED. The
                             zero-rating conflict is unresolved pending the June 2026
                             Licensing Guide, so the default is fail-closed.
      - metered           -> eligible cohort required (the only bounded ELSE -> block).
      - unmapped          -> FAIL-OPEN with anomaly; a detection defect must not deny
                             a user.

    Decisions are emitted as fsi_cbgentitlementmaterialized-shaped records, and an
    fsi_cbgcoveragegap-shaped per-agent aggregate is produced (monitor-only). Both use
    Dataverse option-set integer values (see docs/dataverse-schema.md).

    This script is a pure evaluation engine: it reads an input set (fixture JSON via
    -InputPath until the upstream copilot-agent-inventory and work-iq-usage-detection
    solutions are live) and writes the result JSON via -OutputPath. Dataverse
    persistence is performed by the CBG-CoverageGapAnalyzer flow (see
    docs/flow-configuration.md), keeping this engine free of write-API dependencies.

.PARAMETER InputPath
    Path to a JSON file describing agents and their intended users. Each agent record
    carries: agentId, agentName, createdIn, configuredTier, spendScope, and an
    intendedUsers array where each user carries upn, hasCopilotLicense,
    inApiAudienceGroup, inEligibleCohort, inCreditScopeGroup, surfaceZeroRated.
    See templates/entitlement-decision.sample.json for the output shape.

.PARAMETER OutputPath
    Optional path to write the evaluation result (decisions + coverage gaps) as JSON.
    When omitted, the result object is written to the pipeline only.

.PARAMETER ZeroRatingResolved
    When set, treats the zero-rating conflict as resolved (only flip this once the
    June 2026 Licensing Guide confirms zero-rating). Default is unset (fail-closed).

.PARAMETER CacheTtlMinutes
    Time-to-live, in minutes, stamped onto each materialized decision
    (fsi_ttlexpiresat). Default 1440 (24h). Tune from observed input-change cadence.

.PARAMETER SampleCap
    Maximum number of blocked UPNs sampled into each coverage-gap row
    (fsi_blockedsampleupns). Default 20. Keeps the aggregate bounded.

.PARAMETER GroupSizeThreshold
    Audience-size threshold T above which large groups are flagged for partitioning in
    the coverage-gap aggregate. Default 500.

.PARAMETER RetentionDays
    Retention horizon, in days, stamped onto each coverage-gap row (fsi_retainuntil).
    Default 183 (about six months).

.EXAMPLE
    PS> .\Invoke-EntitlementEvaluation.ps1 -InputPath .\agents.fixture.json -OutputPath .\result.json
    Evaluates entitlement for the fixture agents (fail-closed zero-rating) and writes
    decisions plus per-agent coverage gaps to result.json.

.EXAMPLE
    PS> .\Invoke-EntitlementEvaluation.ps1 -InputPath .\agents.fixture.json -ZeroRatingResolved
    Evaluates with zero-rating treated as resolved (post June 2026 Licensing Guide).

.NOTES
    Dataverse logical names are lowercase with no inter-word underscores. Option-set
    integer values match the fsi_cbg_* global option sets in docs/dataverse-schema.md.
    Per-feature credit rates are reference constants only; verify against Microsoft
    licensing documentation before relying on cost estimates.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$InputPath,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [switch]$ZeroRatingResolved,

    [Parameter()]
    [ValidateRange(1, 525600)]
    [int]$CacheTtlMinutes = 1440,

    [Parameter()]
    [ValidateRange(1, 1000)]
    [int]$SampleCap = 20,

    [Parameter()]
    [ValidateRange(1, 1000000)]
    [int]$GroupSizeThreshold = 500,

    [Parameter()]
    [ValidateRange(1, 3650)]
    [int]$RetentionDays = 183
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --- Option-set value maps (fsi_cbg_* global option sets; see docs/dataverse-schema.md) ---
$script:Pathway = @{
    none             = 100000000
    'mcp-cs'         = 100000001
    'mcp-agentbuilder' = 100000002
    'api-direct'     = 100000003
    metered          = 100000004
    unmapped         = 100000005
}
$script:Decision = @{
    Allow              = 100000000
    Block              = 100000001
    AllowEligibilityNA = 100000002
    FailOpenAnomaly    = 100000003
    FailClosedZeroRating = 100000004
}
$script:BlockReason = @{
    NoEligibleCohort     = 100000000
    MissingLicense       = 100000001
    ZeroRatingUnresolved = 100000002
    NotInCreditScope     = 100000003
    PolicyCapExceeded    = 100000004
    UnmappedPathway      = 100000005
}
$script:SpendScope = @{
    Chat       = 100000000
    SharePoint = 100000001
    Mixed      = 100000002
}

# --- Per-feature Copilot credit rates (reference constants; verify against Microsoft docs) ---
# Pricing context: $0.01 per credit; prepaid pack 25,000 credits/month, non-rolling.
$script:CreditRates = @{
    ClassicAnswer        = 1
    GenerativeAnswer     = 2
    AgentAction          = 5
    TenantGraphGrounding = 10
    AgentFlowPer100      = 13
    AiToolsLow           = 1
    AiToolsMedium        = 15
    AiToolsHigh          = 100
    ContentPerPage       = 8
    VoicePerMinuteLow    = 10
    VoicePerMinuteMedium = 35
    VoicePerMinuteHigh   = 75
}

function Get-AgentPathway {
    <#
    .SYNOPSIS
        Classify an agent's consumption pathway from createdIn + configuredTier.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()][string]$CreatedIn,
        [Parameter(Mandatory)][AllowNull()][string]$ConfiguredTier
    )

    $createdNorm = ("$CreatedIn").Trim().ToLowerInvariant()
    $tierNorm = ("$ConfiguredTier").Trim().ToLowerInvariant()

    # No metered features -> the agent majority.
    if ($tierNorm -in @('none', 'classic', 'non-metered', 'nonmetered')) {
        return 'none'
    }

    switch -Regex ($createdNorm) {
        'copilot.?studio|^cs$|mcp-cs'        { return 'mcp-cs' }
        'agent.?builder|mcp-agentbuilder'    { return 'mcp-agentbuilder' }
        'api|declarative|direct.?line|custom' { return 'api-direct' }
    }

    if ($tierNorm -in @('metered', 'generative', 'grounded', 'agent-action', 'premium')) {
        return 'metered'
    }

    # Missing or contradictory signals -> anomaly.
    return 'unmapped'
}

function Resolve-EntitlementDecision {
    <#
    .SYNOPSIS
        Apply the switch-on-pathway contract to one (agent, user) pair.
    .DESCRIPTION
        Returns a hashtable with Decision and Reason as fsi_cbg_decision /
        fsi_cbg_blockreason integer values (Reason is $null for allows).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PathwayName,
        [Parameter(Mandatory)][psobject]$User,
        [Parameter()][bool]$ZeroRatingIsResolved = $false
    )

    switch ($PathwayName) {
        'none' {
            # The agent majority: no metered consumption, eligibility not applicable.
            return @{ Decision = $script:Decision.AllowEligibilityNA; Reason = $null }
        }
        'mcp-agentbuilder' {
            if ($User.hasCopilotLicense) {
                return @{ Decision = $script:Decision.Allow; Reason = $null }
            }
            return @{ Decision = $script:Decision.Block; Reason = $script:BlockReason.MissingLicense }
        }
        'api-direct' {
            if ($User.inApiAudienceGroup) {
                return @{ Decision = $script:Decision.Allow; Reason = $null }
            }
            return @{ Decision = $script:Decision.Block; Reason = $script:BlockReason.NoEligibleCohort }
        }
        'mcp-cs' {
            # Zero-rating CONFLICT -> fail-closed interim.
            if (-not $User.hasCopilotLicense) {
                return @{ Decision = $script:Decision.Block; Reason = $script:BlockReason.MissingLicense }
            }
            if ($ZeroRatingIsResolved -and $User.surfaceZeroRated) {
                return @{ Decision = $script:Decision.Allow; Reason = $null }
            }
            if ($User.inCreditScopeGroup) {
                return @{ Decision = $script:Decision.Allow; Reason = $null }
            }
            return @{ Decision = $script:Decision.FailClosedZeroRating; Reason = $script:BlockReason.ZeroRatingUnresolved }
        }
        'metered' {
            # The only unbounded-population ELSE, bounded to a metered pathway.
            if ($User.inEligibleCohort) {
                return @{ Decision = $script:Decision.Allow; Reason = $null }
            }
            return @{ Decision = $script:Decision.Block; Reason = $script:BlockReason.NoEligibleCohort }
        }
        default {
            # unmapped: a detection defect must not deny a user.
            return @{ Decision = $script:Decision.FailOpenAnomaly; Reason = $script:BlockReason.UnmappedPathway }
        }
    }
}

function Test-DecisionIsAllow {
    <#
    .SYNOPSIS
        True when a decision value represents access (Allow or Allow - Eligibility N/A
        or Fail-open - Anomaly, which does not deny the user).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][int]$DecisionValue)

    return ($DecisionValue -in @(
            $script:Decision.Allow,
            $script:Decision.AllowEligibilityNA,
            $script:Decision.FailOpenAnomaly
        ))
}

function Get-CoverageGapAggregate {
    <#
    .SYNOPSIS
        Aggregate per-user decisions into one fsi_cbgcoveragegap-shaped row per agent.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Agent,
        [Parameter(Mandatory)][int]$PathwayValue,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Decisions,
        [Parameter(Mandatory)][int]$SampleCapValue,
        [Parameter(Mandatory)][int]$GroupSizeThresholdValue,
        [Parameter(Mandatory)][int]$RetentionDaysValue
    )

    $blocked = @($Decisions | Where-Object { -not (Test-DecisionIsAllow -DecisionValue $_.fsi_decision) })
    $eligibleCount = $Decisions.Count - $blocked.Count

    $sampleUpns = @($blocked | Select-Object -First $SampleCapValue | ForEach-Object { $_.fsi_userupn })

    $dominantReason = $null
    if ($blocked.Count -gt 0) {
        $dominantReason = ($blocked |
                Where-Object { $null -ne $_.fsi_decisionreason } |
                Group-Object -Property fsi_decisionreason |
                Sort-Object -Property Count -Descending |
                Select-Object -First 1).Name
        if ($null -ne $dominantReason) { $dominantReason = [int]$dominantReason }
    }

    $spendScope = $script:SpendScope.Chat
    if ($Agent.PSObject.Properties.Name -contains 'spendScope' -and $script:SpendScope.ContainsKey($Agent.spendScope)) {
        $spendScope = $script:SpendScope[$Agent.spendScope]
    }

    $now = (Get-Date).ToUniversalTime()
    $partition = $Decisions.Count
    if ($partition -gt $GroupSizeThresholdValue) {
        Write-Verbose "Agent '$($Agent.agentId)' audience ($partition) exceeds threshold T=$GroupSizeThresholdValue; flag for partitioning."
    }

    return [pscustomobject]@{
        fsi_name               = $Agent.agentName
        fsi_agentid            = $Agent.agentId
        fsi_agentname          = $Agent.agentName
        fsi_pathway            = $PathwayValue
        fsi_eligibleusers      = $eligibleCount
        fsi_blockeduserscount  = $blocked.Count
        fsi_blockedsampleupns  = ($sampleUpns | ConvertTo-Json -Compress)
        fsi_blockreasonsummary = $dominantReason
        fsi_spendscope         = $spendScope
        fsi_groupsizepartition = $partition
        fsi_monitoronly        = $true
        fsi_analyzedat         = $now.ToString('o')
        fsi_retainuntil        = $now.AddDays($RetentionDaysValue).ToString('o')
    }
}

# --- Main ---
if (-not (Test-Path -LiteralPath $InputPath)) {
    throw "Input file not found: $InputPath"
}

$inputObject = Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json
$agents = @($inputObject.agents)
if ($agents.Count -eq 0) {
    Write-Warning "Input contains no agents under the 'agents' property."
}

$now = (Get-Date).ToUniversalTime()
$ttlExpiry = $now.AddMinutes($CacheTtlMinutes).ToString('o')

$allDecisions = New-Object System.Collections.Generic.List[object]
$allGaps = New-Object System.Collections.Generic.List[object]

foreach ($agent in $agents) {
    $pathwayName = Get-AgentPathway -CreatedIn $agent.createdIn -ConfiguredTier $agent.configuredTier
    $pathwayValue = $script:Pathway[$pathwayName]

    $agentSpendScope = $script:SpendScope.Chat
    if ($agent.PSObject.Properties.Name -contains 'spendScope' -and $script:SpendScope.ContainsKey($agent.spendScope)) {
        $agentSpendScope = $script:SpendScope[$agent.spendScope]
    }

    $agentDecisions = New-Object System.Collections.Generic.List[object]
    $intendedUsers = @()
    if ($agent.PSObject.Properties.Name -contains 'intendedUsers' -and $null -ne $agent.intendedUsers) {
        $intendedUsers = @($agent.intendedUsers)
    }

    foreach ($user in $intendedUsers) {
        $resolved = Resolve-EntitlementDecision -PathwayName $pathwayName -User $user -ZeroRatingIsResolved:$ZeroRatingResolved.IsPresent

        $record = [pscustomobject]@{
            fsi_name           = "$($agent.agentId):$($user.upn)"
            fsi_agentid        = $agent.agentId
            fsi_userupn        = $user.upn
            fsi_pathway        = $pathwayValue
            fsi_decision       = $resolved.Decision
            fsi_decisionreason = $resolved.Reason
            fsi_spendscope     = $agentSpendScope
            fsi_sourcepolicyid = $(if ($agent.PSObject.Properties.Name -contains 'sourcePolicyId') { $agent.sourcePolicyId } else { $null })
            fsi_evaluatedat    = $now.ToString('o')
            fsi_ttlexpiresat   = $ttlExpiry
        }
        $agentDecisions.Add($record)
        $allDecisions.Add($record)
    }

    $gap = Get-CoverageGapAggregate -Agent $agent -PathwayValue $pathwayValue -Decisions $agentDecisions.ToArray() -SampleCapValue $SampleCap -GroupSizeThresholdValue $GroupSizeThreshold -RetentionDaysValue $RetentionDays
    $allGaps.Add($gap)
}

$result = [pscustomobject]@{
    EvaluatedAt        = $now.ToString('o')
    ZeroRatingResolved = $ZeroRatingResolved.IsPresent
    CacheTtlMinutes    = $CacheTtlMinutes
    DecisionCount      = $allDecisions.Count
    AgentCount         = $agents.Count
    Decisions          = $allDecisions.ToArray()
    CoverageGaps       = $allGaps.ToArray()
}

if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
    $result | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
    Write-Verbose "Wrote evaluation result to $OutputPath."
}

Write-Output $result
