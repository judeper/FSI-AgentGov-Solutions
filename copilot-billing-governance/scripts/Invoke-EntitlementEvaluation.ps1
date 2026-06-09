<#
.SYNOPSIS
    Evaluates Copilot consumption entitlement using the switch-on-pathway contract and
    produces per-agent coverage-gap aggregates (monitor-only).

.DESCRIPTION
    Implements the entitlement contract in docs/entitlement-contract.md. For each
    agent it classifies the consumption pathway FIRST (none / mcp-cs /
    mcp-agentbuilder / api-direct / metered / unmapped) — mapping the authoritative
    Work IQ configuredTier first and falling back to the createdIn (Azure Resource
    Graph) signal only when configuredTier is empty or unrecognized — then applies
    pathway-specific eligibility for each intended user:

      - none              -> ALLOW (eligibility N/A); unblocks the agent majority.
      - mcp-agentbuilder  -> license required.
      - api-direct        -> API audience cohort required.
      - mcp-cs            -> license AND (zero-rating resolved AND surface zero-rated,
                             OR user in credit scope); otherwise FAIL-CLOSED. The June
                             2026 Licensing Guide (footnotes 6 & 7) resolves the base
                             case, so the default is resolved: a Copilot-licensed user
                             on a zero-rated M365 surface under their identity is
                             Allowed.
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
    Treats the zero-rating conflict as resolved. Defaults to $true per the June 2026
    Microsoft Copilot Studio Licensing Guide (footnotes 6 & 7): a Copilot-licensed user
    on a Microsoft 365 surface under their own identity is included in the Microsoft 365
    Copilot User SL at no additional charge, so the mcp-cs arm allows when the surface is
    zero-rated. Pass -ZeroRatingResolved:$false to revert to the conservative fail-closed
    posture. The generative-answer-with-tenant-grounding and beyond-fair-use refinements
    affect credit cost, not this base entitlement, and are confirmed per tenant.

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
    Evaluates entitlement for the fixture agents (zero-rating resolved by default per the
    June 2026 Licensing Guide) and writes decisions plus per-agent coverage gaps to
    result.json.

.EXAMPLE
    PS> .\Invoke-EntitlementEvaluation.ps1 -InputPath .\agents.fixture.json -ZeroRatingResolved:$false
    Reverts to the conservative fail-closed posture; licensed mcp-cs users not in credit
    scope resolve to Fail-closed - Zero-rating Unresolved.

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
    [bool]$ZeroRatingResolved = $true,

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
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][string]$CreatedIn,
        [Parameter(Mandatory)][AllowNull()][AllowEmptyString()][string]$ConfiguredTier
    )

    $createdNorm = ("$CreatedIn").Trim().ToLowerInvariant()
    $tierNorm = ("$ConfiguredTier").Trim().ToLowerInvariant()

    # configuredTier is the AUTHORITATIVE signal and is mapped FIRST. The sibling
    # work-iq-usage-detection classifier emits one of NotConfigured |
    # NativeMcpCopilotStudio | NativeApiDirect | Adjacent (compared lowercased);
    # NotConfigured and Adjacent are non-metered, so they resolve to 'none' (the agent
    # majority -> Allow). 'none'/'classic'/'non-metered'/'nonmetered' are accepted
    # synonyms; the metered synonyms cover legacy tier labels. createdIn is consulted
    # ONLY as a last-resort fallback when configuredTier is empty or unrecognized, so a
    # Copilot-Studio createdIn can no longer override an authoritative non-metered tier.
    if ($tierNorm -eq 'nativemcpcopilotstudio') { return 'mcp-cs' }
    if ($tierNorm -eq 'nativeapidirect') { return 'api-direct' }
    if ($tierNorm -in @('notconfigured', 'adjacent', 'none', 'classic', 'non-metered', 'nonmetered')) {
        return 'none'
    }
    if ($tierNorm -in @('metered', 'generative', 'grounded', 'agent-action', 'premium')) {
        return 'metered'
    }

    # Fallback only when configuredTier is empty/unrecognized: infer from createdIn.
    switch -Regex ($createdNorm) {
        'copilot.?studio|^cs$|mcp-cs'         { return 'mcp-cs' }
        'agent.?builder|mcp-agentbuilder'     { return 'mcp-agentbuilder' }
        'api|declarative|direct.?line|custom' { return 'api-direct' }
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
        fsi_cbg_blockreason integer values (Reason is $null for allows), plus a short
        Note string (eval trace) materialized to fsi_notes.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$PathwayName,
        [Parameter(Mandatory)][psobject]$User,
        [Parameter()][bool]$ZeroRatingIsResolved = $true
    )

    switch ($PathwayName) {
        'none' {
            # The agent majority: no metered consumption, eligibility not applicable.
            return @{ Decision = $script:Decision.AllowEligibilityNA; Reason = $null; Note = 'pathway=none -> ALLOW (eligibility N/A); non-metered agent, no billing decision required.' }
        }
        'mcp-agentbuilder' {
            if ($User.hasCopilotLicense) {
                return @{ Decision = $script:Decision.Allow; Reason = $null; Note = 'pathway=mcp-agentbuilder; user holds a Copilot license -> ALLOW.' }
            }
            return @{ Decision = $script:Decision.Block; Reason = $script:BlockReason.MissingLicense; Note = 'pathway=mcp-agentbuilder; no Copilot license -> BLOCK (Missing license).' }
        }
        'api-direct' {
            if ($User.inApiAudienceGroup) {
                return @{ Decision = $script:Decision.Allow; Reason = $null; Note = 'pathway=api-direct; user in API audience cohort -> ALLOW.' }
            }
            return @{ Decision = $script:Decision.Block; Reason = $script:BlockReason.NoEligibleCohort; Note = 'pathway=api-direct; user not in API audience cohort -> BLOCK (No eligible cohort).' }
        }
        'mcp-cs' {
            # June 2026 Licensing Guide footnotes 6 & 7 resolve the base case: a Copilot-
            # licensed user on a zero-rated M365 surface under their own identity is
            # included in the M365 Copilot User SL at no additional charge. Credit scope
            # still covers non-M365 surfaces / unlicensed paths. Generative-answer-with-
            # tenant-grounding + beyond-fair-use are a credit-cost refinement (confirm per
            # tenant), not a change to this allow/deny.
            if (-not $User.hasCopilotLicense) {
                return @{ Decision = $script:Decision.Block; Reason = $script:BlockReason.MissingLicense; Note = 'pathway=mcp-cs; no Copilot license -> BLOCK (Missing license).' }
            }
            if ($ZeroRatingIsResolved -and $User.surfaceZeroRated) {
                return @{ Decision = $script:Decision.Allow; Reason = $null; Note = 'pathway=mcp-cs; licensed and on a zero-rated M365 surface under the user identity -> ALLOW (included in the M365 Copilot User SL per the June 2026 Licensing Guide, footnotes 6 & 7).' }
            }
            if ($User.inCreditScopeGroup) {
                return @{ Decision = $script:Decision.Allow; Reason = $null; Note = 'pathway=mcp-cs; user in credit scope -> ALLOW.' }
            }
            return @{ Decision = $script:Decision.FailClosedZeroRating; Reason = $script:BlockReason.ZeroRatingUnresolved; Note = 'pathway=mcp-cs; licensed but surface not zero-rated (or zero-rating reverted) and not in credit scope -> FAIL-CLOSED. A zero-rated M365 surface under the user identity is included per the June 2026 Licensing Guide (footnotes 6 & 7); non-M365 surfaces require credit scope.' }
        }
        'metered' {
            # The only unbounded-population ELSE, bounded to a metered pathway.
            if ($User.inEligibleCohort) {
                return @{ Decision = $script:Decision.Allow; Reason = $null; Note = 'pathway=metered; user in eligible cohort -> ALLOW.' }
            }
            return @{ Decision = $script:Decision.Block; Reason = $script:BlockReason.NoEligibleCohort; Note = 'pathway=metered; bounded ELSE -> BLOCK (No eligible cohort).' }
        }
        default {
            # unmapped: a detection defect must not deny a user.
            return @{ Decision = $script:Decision.FailOpenAnomaly; Reason = $script:BlockReason.UnmappedPathway; Note = "pathway=$PathwayName -> FAIL-OPEN with anomaly; classifier could not map the pathway." }
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

    # M-2: fsi_blockedsampleupns must always be a JSON array for any cardinality (0/1/n).
    # Piping an empty @() to ConvertTo-Json emits nothing (pipeline unrolls to zero items),
    # and a single element serializes as a bare string without -AsArray; guard both cases.
    $sampleUpnsJson = if (@($sampleUpns).Count -gt 0) {
        @($sampleUpns) | ConvertTo-Json -Depth 3 -Compress -AsArray
    }
    else {
        '[]'
    }

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
        fsi_blockedsampleupns  = $sampleUpnsJson
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
        $resolved = Resolve-EntitlementDecision -PathwayName $pathwayName -User $user -ZeroRatingIsResolved $ZeroRatingResolved

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
            fsi_notes          = $resolved.Note
        }
        $agentDecisions.Add($record)
        $allDecisions.Add($record)
    }

    $gap = Get-CoverageGapAggregate -Agent $agent -PathwayValue $pathwayValue -Decisions $agentDecisions.ToArray() -SampleCapValue $SampleCap -GroupSizeThresholdValue $GroupSizeThreshold -RetentionDaysValue $RetentionDays
    $allGaps.Add($gap)
}

$result = [pscustomobject]@{
    EvaluatedAt        = $now.ToString('o')
    ZeroRatingResolved = $ZeroRatingResolved
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
