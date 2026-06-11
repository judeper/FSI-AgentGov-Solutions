#Requires -Version 7.2

<#
.SYNOPSIS
    Find-No-Filter (FNF) People-Sweep lens: reports Copilot agents that expose the
    declarative-agent People (Org Chart & Profile) capability and are shared with users
    who lack Copilot entitlement, supporting compliance with oversight of agent reach.

.DESCRIPTION
    The FNF People-Sweep joins three upstream contracts into a single deliverable report,
    per the Wave-2 GATE-1 contract-guardian specification:

      1. copilot-agent-inventory (CAI) People-capability detection artifact
         (detect_people_capability.py): which agents declare the People capability.
      2. CAI audience artifact (expand_audience_upns.py): each agent's sharing audience
         resolved to concrete member UPNs (or flagged whole-tenant / partial).
      3. copilot-billing-governance (CBG) entitlement: per-user license + PAYG resolution
         (Get-CopilotEntitlement.ps1) feeding the switch-on-pathway entitlement engine
         (Invoke-EntitlementEvaluation.ps1).

    This script is the lens/orchestrator only. It does NOT re-implement the entitlement
    rule: per-user scoring is piped through the existing CBG resolver and engine. Its job
    is to wire the three contracts together correctly and defensively so the report can
    NEVER silently read as "0 blocked" when coverage is actually incomplete. It implements
    the three MUST-FIX seams the guardian pinned plus the coverage roll-up:

      SEAM 1 - Agent-id keying. The People filter joins on fsi_agentid ONLY when
        fsi_agentrefprovisional = $false (or after an -IdMapPath reconciliation pass that
        rewrites a provisional manifest stem to the real Dataverse bot GUID). Provisional
        rows that cannot be reconciled are surfaced as coverageStatus=Partial with the gap
        'manifest-id-unreconciled' - never silently joined to a real agent, never dropped.

      SEAM 2 - Field-shape transform. The CAI audience artifact carries
        agents[].intendedUsers[] as OBJECTS with a 'upn' property; the CBG resolver expects
        agents[].intendedUpns as a flat STRING array. A direct passthrough produces a silent
        zero-user run (the resolver finds no UPNs, the engine emits no decisions, the report
        reads "0 blocked"). This lens performs the mandatory normalization
        (intendedUsers[*].upn -> intendedUpns[]) and joins createdIn from the agent master
        (fsi_copilotagent.fsi_createdin) so the engine's pathway classifier is accurate.
        configuredTier is intentionally WIQ-scoped-out: it is passed empty and the engine
        falls back to the createdIn heuristic (documented degradation).

      SEAM 2c - Whole-tenant. When CAI marks an agent org-wide (wholeTenant / intendedUsers
        empty / resolutionStatus WholeTenantNotEnumerated) the tenant is deliberately not
        enumerated, so there are no UPNs to score. This lens does NOT emit "0 blocked" for
        such agents (a tenant-reachable People-capable agent is the highest-risk case);
        it emits audienceMode=WholeTenant, coverageStatus=Partial, blockedUserCount=null,
        and the gap 'audience-wholetenant-not-enumerated'.

      SEAM 5 - Coverage roll-up. A single per-agent coverageStatus (Complete / Partial /
        Failed) folds in every coverage gap (provisional id, attestation-pending capability,
        audience partial / truncated / errors / failed, whole-tenant, unresolved
        entitlement reads, PAYG needs-manual-review, all-users PAYG, pathway-unmapped
        fail-open) so nothing hides behind a "0 blocked" headline.

    The authoritative FNF blocked set is the engine's materialized decisions with
    fsi_decision = Block (100000001). The resolver's users[].isBlocked (license + PAYG only,
    skips pathway classification) is NOT used as the blocked set.

    Authentication is managed-identity-first end-to-end: pass -GraphAccessToken (and, for a
    live billing-policy read, -BillingApiAccessToken) from a managed identity or workload
    identity. The CBG resolver provides a dev-only Get-AzAccessToken fallback.

    The functions are defined at top level so the script can be dot-sourced (with placeholder
    arguments) in Pester tests; the main body runs only on direct invocation.

.PARAMETER CapabilityArtifactPath
    Path to the CAI People-capability detection artifact (detect_people_capability.py
    --output). Carries summary + agents[] + features[] (fsi_caiagentfeature rows).

.PARAMETER AudienceArtifactPath
    Path to the CAI audience artifact (expand_audience_upns.py --output). Carries agents[]
    with intendedUsers[].upn, wholeTenant, truncated, resolutionStatus, resolutionErrors.

.PARAMETER AgentMasterPath
    Optional path to the CAI agent master export (fsi_copilotagent rows) used to join
    createdIn (fsi_createdin) and agentName (fsi_agentname) on fsi_agentid. Accepts a bare
    array, a { "value": [...] } OData envelope, or an { "agents": [...] } wrapper. When an
    agent's createdIn cannot be joined the engine pathway falls back to unmapped (fail-open)
    and the agent is reported coverageStatus=Partial with 'pathway-unmapped-fail-open'.

.PARAMETER IdMapPath
    Optional path to an agent-id reconciliation map (SEAM 1). Maps a provisional manifest id
    (the feature row fsi_agentid stem) to the real Dataverse bot GUID. Accepted shapes:
      { "<provisional-id>": "<bot-guid>", ... }
      { "mappings": [ { "provisionalId": "<stem>", "agentId": "<bot-guid>" }, ... ] }
      [ { "provisionalId": "<stem>", "agentId": "<bot-guid>" }, ... ]
    Unreconciled provisional People rows remain in the report as coverageStatus=Partial.

.PARAMETER BillingPolicyInputPath
    Optional path to pre-enumerated PAYG/credit billing policies (passed verbatim to the CBG
    resolver -BillingPolicyInputPath). Recommended over a live billing-policy read.

.PARAMETER GraphAccessToken
    Bearer token for Microsoft Graph (resource https://graph.microsoft.com). Managed-identity
    first; when omitted the CBG resolver falls back to Get-AzAccessToken (dev-only).

.PARAMETER BillingApiAccessToken
    Bearer token for the Power Platform billing-policy admin API. Used only when policies are
    read live (no -BillingPolicyInputPath). Managed-identity-first.

.PARAMETER GatedCapability
    The Copilot capability whose entitlement is gated: CopilotChat (default),
    SharePointAgents, or Both. Forwarded to the CBG resolver.

.PARAMETER ApiAudienceGroupId
    Optional Entra group object id whose transitive members populate inApiAudienceGroup
    (api-direct pathway cohort). Forwarded to the CBG resolver.

.PARAMETER EligibleCohortGroupId
    Optional Entra group object id whose transitive members populate inEligibleCohort
    (metered pathway cohort). Forwarded to the CBG resolver.

.PARAMETER CreditScopeGroupId
    Optional Entra group object id that OVERRIDES PAYG-derived credit-scope coverage.
    Forwarded to the CBG resolver.

.PARAMETER ReportOutputPath
    Optional path to write the FNF report JSON. When omitted the report object is written to
    the pipeline only.

.PARAMETER WorkingDirectory
    Optional directory for intermediate engine input/decision files. Defaults to the
    directory of -ReportOutputPath, or the current directory.

.PARAMETER ResolverScriptPath
    Optional path to Get-CopilotEntitlement.ps1. Defaults to the sibling script.

.PARAMETER EngineScriptPath
    Optional path to Invoke-EntitlementEvaluation.ps1. Defaults to the sibling script.

.PARAMETER SampleCap
    Maximum number of blocked UPNs sampled into each report row's blockedUsers[] (the full
    count is always reported in blockedUserCount). Default 20.

.PARAMETER SurfaceZeroRated
    Value stamped onto each resolved user's surfaceZeroRated input (forwarded to the CBG
    resolver). Default $true per the June 2026 Microsoft Copilot Studio Licensing Guide.

.PARAMETER ZeroRatingResolved
    Forwarded to the engine -ZeroRatingResolved. Default $true.

.EXAMPLE
    PS> .\Get-FnfPeopleSweepReport.ps1 -CapabilityArtifactPath .\people.json `
            -AudienceArtifactPath .\audience.json -AgentMasterPath .\agents.json `
            -BillingPolicyInputPath .\billing-policies.json -GraphAccessToken $g `
            -ReportOutputPath .\fnf-people-sweep.json
    Builds the FNF People-Sweep report: which People-capable agents are shared with users
    blocked from Copilot Chat, with a per-agent coverageStatus roll-up.

.NOTES
    Dataverse logical names are lowercase with no inter-word underscores. Option-set integer
    values mirror the fsi_cbg_* / fsi_cai_* global option sets in docs/dataverse-schema.md.
    This lens emits report JSON, not Dataverse rows; persistence (e.g. fsi_cbgcoveragegap with
    an fsi_featurefilter="People" discriminator) is performed by the consuming flow.
#>
[CmdletBinding()]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CreditScopeGroupId',
    Justification = 'CreditScopeGroupId is an Entra group object id (GUID), not a secret. The rule false-positives on the "Cred" substring in "Credit"; the name deliberately mirrors the CBG resolver parameter and the engine input inCreditScopeGroup.')]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$CapabilityArtifactPath,

    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$AudienceArtifactPath,

    [Parameter()]
    [string]$AgentMasterPath,

    [Parameter()]
    [string]$IdMapPath,

    [Parameter()]
    [string]$BillingPolicyInputPath,

    [Parameter()]
    [string]$GraphAccessToken,

    [Parameter()]
    [string]$BillingApiAccessToken,

    [Parameter()]
    [ValidateSet('CopilotChat', 'SharePointAgents', 'Both')]
    [string]$GatedCapability = 'CopilotChat',

    [Parameter()]
    [string]$ApiAudienceGroupId,

    [Parameter()]
    [string]$EligibleCohortGroupId,

    [Parameter()]
    [string]$CreditScopeGroupId,

    [Parameter()]
    [string]$ReportOutputPath,

    [Parameter()]
    [string]$WorkingDirectory,

    [Parameter()]
    [string]$ResolverScriptPath,

    [Parameter()]
    [string]$EngineScriptPath,

    [Parameter()]
    [ValidateRange(1, 1000)]
    [int]$SampleCap = 20,

    [Parameter()]
    [bool]$SurfaceZeroRated = $true,

    [Parameter()]
    [bool]$ZeroRatingResolved = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------------------
# Constants
# --------------------------------------------------------------------------------------

# The declarative-agent People capability feature-type label emitted by CAI
# detect_people_capability.py (PEOPLE_FEATURE_TYPE). Filtering on the label is option-set
# drift-safe (the integer value is resolved by the CAI writer at upsert time).
$script:PeopleFeatureType = 'People (Org Chart & Profile)'

# FNF report schema version (mirrors the CAI/CBG preview artifact versioning).
$script:FnfSchemaVersion = '0.1.0-preview'

# Engine decision option-set integers (mirror Invoke-EntitlementEvaluation.ps1 $script:Decision).
$script:DecisionBlock = 100000001
$script:DecisionFailOpenAnomaly = 100000003
$script:DecisionFailClosedZeroRating = 100000004

# Audience resolution statuses that mean the audience could not be resolved at all (no usable
# audience -> blocked count is not computable -> coverageStatus = Failed, the most severe).
$script:AudienceFailedStatuses = @('Failed', 'NotResolved')

# --------------------------------------------------------------------------------------
# Safe property access under Set-StrictMode -Version Latest.
# --------------------------------------------------------------------------------------
function Get-FnfProperty {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowNull()]$InputObject,
        [Parameter(Mandatory)][string]$Name,
        [Parameter()]$Default = $null
    )
    if ($null -eq $InputObject) { return $Default }
    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) { return $InputObject[$Name] }
        return $Default
    }
    $prop = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $prop) { return $prop.Value }
    return $Default
}

# --------------------------------------------------------------------------------------
# Id-map normalization (SEAM 1 support). Accepts the three documented shapes and returns a
# case-insensitive hashtable keyed by provisional id -> real bot GUID.
# --------------------------------------------------------------------------------------
function ConvertTo-FnfIdMap {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter()][AllowNull()]$InputObject)

    $map = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -eq $InputObject) { return $map }

    # Unwrap a { "mappings": [...] } envelope.
    $mappings = Get-FnfProperty -InputObject $InputObject -Name 'mappings'

    if ($null -ne $mappings -or $InputObject -is [System.Array]) {
        $entries = if ($null -ne $mappings) { @($mappings) } else { @($InputObject) }
        foreach ($entry in $entries) {
            if ($null -eq $entry) { continue }
            $from = Get-FnfProperty -InputObject $entry -Name 'provisionalId'
            if ([string]::IsNullOrWhiteSpace($from)) { $from = Get-FnfProperty -InputObject $entry -Name 'from' }
            $to = Get-FnfProperty -InputObject $entry -Name 'agentId'
            if ([string]::IsNullOrWhiteSpace($to)) { $to = Get-FnfProperty -InputObject $entry -Name 'to' }
            if (-not [string]::IsNullOrWhiteSpace($from) -and -not [string]::IsNullOrWhiteSpace($to)) {
                $map[([string]$from).Trim()] = ([string]$to).Trim()
            }
        }
        return $map
    }

    # Otherwise treat it as a flat object: { "<provisional>": "<guid>", ... }.
    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            $val = $InputObject[$key]
            if (-not [string]::IsNullOrWhiteSpace($val)) { $map[[string]$key] = ([string]$val).Trim() }
        }
        return $map
    }
    foreach ($prop in $InputObject.PSObject.Properties) {
        if ($prop.Name -eq '$comment' -or $prop.Name -eq '_comment') { continue }
        if (-not [string]::IsNullOrWhiteSpace($prop.Value)) { $map[$prop.Name] = ([string]$prop.Value).Trim() }
    }
    return $map
}

# --------------------------------------------------------------------------------------
# Classify a People feature's capability source as manifest or attested (SEAM 5 / report
# peopleCapableSource). CAI detect_people_capability emits the confidence label
# "Declared (manifest capability)"; an attestation-sourced row carries an "attest*" marker.
# --------------------------------------------------------------------------------------
function Get-FnfPeopleCapabilitySource {
    [CmdletBinding()]
    [OutputType([string])]
    param([Parameter()][AllowNull()]$Feature)

    $confidence = "$(Get-FnfProperty -InputObject $Feature -Name 'fsi_detectionconfidence')"
    $source = "$(Get-FnfProperty -InputObject $Feature -Name 'fsi_detectionsource')"
    if ($confidence -match '(?i)attest' -or $source -match '(?i)attest') { return 'attested' }
    return 'manifest'
}

# --------------------------------------------------------------------------------------
# SEAM 1 - People-capability filter + agent-id keying.
# Selects the People-capable agents, honouring the provisional gate and optional id-map
# reconciliation. Provisional rows that cannot be reconciled are returned separately so the
# report can surface them as Partial coverage (never silently joined, never dropped).
# --------------------------------------------------------------------------------------
function Resolve-FnfPeopleAgentSet {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][psobject]$CapabilityArtifact,
        [Parameter()][AllowNull()][hashtable]$IdMap
    )

    if ($null -eq $IdMap) {
        $IdMap = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([System.StringComparer]::OrdinalIgnoreCase)
    }

    # Display-name lookup from the artifact agents[] (keyed by the same id-space as features).
    $nameByAgentId = @{}
    foreach ($a in @(Get-FnfProperty -InputObject $CapabilityArtifact -Name 'agents')) {
        $aid = Get-FnfProperty -InputObject $a -Name 'agentId'
        if (-not [string]::IsNullOrWhiteSpace($aid)) {
            $nameByAgentId[[string]$aid] = Get-FnfProperty -InputObject $a -Name 'agentName'
        }
    }

    $resolved = New-Object System.Collections.Generic.List[object]
    $provisionalUnreconciled = New-Object System.Collections.Generic.List[object]
    $sourceMap = @{}
    $seenResolved = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($feature in @(Get-FnfProperty -InputObject $CapabilityArtifact -Name 'features')) {
        $featureType = "$(Get-FnfProperty -InputObject $feature -Name 'fsi_featuretype')"
        if ($featureType -ne $script:PeopleFeatureType) { continue }

        # fsi_isenabled gates "declared and effective"; a disabled capability is not People-active.
        $isEnabled = Get-FnfProperty -InputObject $feature -Name 'fsi_isenabled' -Default $true
        if ($isEnabled -eq $false) { continue }

        $agentId = "$(Get-FnfProperty -InputObject $feature -Name 'fsi_agentid')"
        if ([string]::IsNullOrWhiteSpace($agentId)) { continue }

        $provisional = [bool](Get-FnfProperty -InputObject $feature -Name 'fsi_agentrefprovisional' -Default $false)
        $source = Get-FnfPeopleCapabilitySource -Feature $feature
        $agentName = $nameByAgentId[$agentId]
        $environmentId = Get-FnfProperty -InputObject $feature -Name 'fsi_environmentid'
        $runId = Get-FnfProperty -InputObject $feature -Name 'fsi_runid'

        $reconciled = $false
        $effectiveId = $agentId
        if ($provisional) {
            if ($IdMap.ContainsKey($agentId)) {
                # Reconciliation pass: rewrite the provisional stem to the real bot GUID and
                # clear the provisional flag so the row joins like a real agent.
                $effectiveId = $IdMap[$agentId]
                $reconciled = $true
            }
            else {
                # Unreconciled provisional row: surface as Partial coverage, never join, never drop.
                $provisionalUnreconciled.Add([pscustomobject]@{
                        agentId       = $agentId
                        agentName     = $agentName
                        source        = $source
                        environmentId = $environmentId
                        runId         = $runId
                    })
                continue
            }
        }

        if (-not $seenResolved.Add($effectiveId)) { continue }   # de-dup multiple feature rows per agent
        $sourceMap[$effectiveId] = $source
        $resolved.Add([pscustomobject]@{
                agentId       = $effectiveId
                agentName     = $agentName
                source        = $source
                reconciled    = $reconciled
                environmentId = $environmentId
                runId         = $runId
            })
    }

    return [pscustomobject]@{
        Resolved                = $resolved.ToArray()
        ProvisionalUnreconciled = $provisionalUnreconciled.ToArray()
        SourceMap               = $sourceMap
    }
}

# --------------------------------------------------------------------------------------
# Build an agentId -> { createdIn, agentName } lookup from the CAI agent master export.
# Tolerates a bare array, an OData { value: [...] } envelope, or an { agents: [...] } wrapper.
# --------------------------------------------------------------------------------------
function ConvertTo-FnfAgentMasterMap {
    [CmdletBinding()]
    [OutputType([hashtable])]
    param([Parameter()][AllowNull()]$InputObject)

    $map = @{}
    if ($null -eq $InputObject) { return $map }

    $rows = $null
    if ($InputObject -is [System.Array]) { $rows = @($InputObject) }
    else {
        $rows = Get-FnfProperty -InputObject $InputObject -Name 'value'
        if ($null -eq $rows) { $rows = Get-FnfProperty -InputObject $InputObject -Name 'agents' }
        if ($null -eq $rows) { $rows = @($InputObject) }
    }

    foreach ($row in @($rows)) {
        $aid = Get-FnfProperty -InputObject $row -Name 'fsi_agentid'
        if ([string]::IsNullOrWhiteSpace($aid)) { $aid = Get-FnfProperty -InputObject $row -Name 'agentId' }
        if ([string]::IsNullOrWhiteSpace($aid)) { continue }

        $createdIn = Get-FnfProperty -InputObject $row -Name 'fsi_createdin'
        if ($null -eq $createdIn) { $createdIn = Get-FnfProperty -InputObject $row -Name 'createdIn' }
        $name = Get-FnfProperty -InputObject $row -Name 'fsi_agentname'
        if ([string]::IsNullOrWhiteSpace($name)) { $name = Get-FnfProperty -InputObject $row -Name 'agentName' }

        $map[[string]$aid] = [pscustomobject]@{ createdIn = $createdIn; agentName = $name }
    }
    return $map
}

# --------------------------------------------------------------------------------------
# SEAM 2 + SEAM 2c - Field-shape transform and whole-tenant special-casing.
# Produces the CBG resolver agents-skeleton (intendedUpns flat string arrays), the per-agent
# scored metadata, the whole-tenant agents (NOT scored), and the People-capable agents that
# are missing from the audience artifact (audience not resolved).
# --------------------------------------------------------------------------------------
function ConvertTo-FnfResolverSkeleton {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][psobject]$AudienceArtifact,
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$PeopleAgents,
        [Parameter()][AllowNull()][hashtable]$AgentMaster,
        [Parameter()][string]$ConfiguredTier = '',
        [Parameter()][string]$SpendScope = 'Chat'
    )

    if ($null -eq $AgentMaster) { $AgentMaster = @{} }

    # Index the audience artifact agents by agentId.
    $audienceById = @{}
    foreach ($a in @(Get-FnfProperty -InputObject $AudienceArtifact -Name 'agents')) {
        $aid = Get-FnfProperty -InputObject $a -Name 'agentId'
        if (-not [string]::IsNullOrWhiteSpace($aid)) { $audienceById[[string]$aid] = $a }
    }

    $skeletonAgents = New-Object System.Collections.Generic.List[object]
    $scoredMeta = @{}
    $wholeTenantAgents = New-Object System.Collections.Generic.List[object]
    $failedAudienceAgents = New-Object System.Collections.Generic.List[object]
    $missingAudienceAgents = New-Object System.Collections.Generic.List[object]
    $allUpns = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)

    foreach ($people in @($PeopleAgents)) {
        $agentId = "$(Get-FnfProperty -InputObject $people -Name 'agentId')"
        if ([string]::IsNullOrWhiteSpace($agentId)) { continue }

        $master = $AgentMaster[$agentId]
        $createdIn = if ($null -ne $master) { Get-FnfProperty -InputObject $master -Name 'createdIn' } else { $null }
        $agentName = Get-FnfProperty -InputObject $people -Name 'agentName'

        if (-not $audienceById.ContainsKey($agentId)) {
            # People-capable + selected, but the audience expansion did not cover it. The
            # audience is unknown -> cannot compute blocked. Surface (do not drop).
            if ($null -ne $master) {
                $masterName = Get-FnfProperty -InputObject $master -Name 'agentName'
                if (-not [string]::IsNullOrWhiteSpace($masterName)) { $agentName = $masterName }
            }
            $missingAudienceAgents.Add([pscustomobject]@{ agentId = $agentId; agentName = $agentName })
            continue
        }

        $audience = $audienceById[$agentId]
        if ([string]::IsNullOrWhiteSpace($agentName)) { $agentName = Get-FnfProperty -InputObject $audience -Name 'agentName' }
        if ($null -ne $master) {
            $masterName = Get-FnfProperty -InputObject $master -Name 'agentName'
            if (-not [string]::IsNullOrWhiteSpace($masterName)) { $agentName = $masterName }
        }

        $resolutionStatus = "$(Get-FnfProperty -InputObject $audience -Name 'resolutionStatus' -Default 'Complete')"
        $wholeTenant = [bool](Get-FnfProperty -InputObject $audience -Name 'wholeTenant' -Default $false)
        $truncated = [bool](Get-FnfProperty -InputObject $audience -Name 'truncated' -Default $false)
        $audienceSize = [int](Get-FnfProperty -InputObject $audience -Name 'audienceSize' -Default 0)
        $resolutionErrors = @(Get-FnfProperty -InputObject $audience -Name 'resolutionErrors')
        $environmentId = Get-FnfProperty -InputObject $audience -Name 'environmentId'

        # SEAM 2a transform: intendedUsers[].upn (objects) -> intendedUpns[] (strings).
        $intendedUpns = New-Object System.Collections.Generic.List[string]
        foreach ($iu in @(Get-FnfProperty -InputObject $audience -Name 'intendedUsers')) {
            if ($null -eq $iu) { continue }
            # Tolerate either an object with .upn or a bare string.
            $upn = if ($iu -is [string]) { $iu } else { Get-FnfProperty -InputObject $iu -Name 'upn' }
            if (-not [string]::IsNullOrWhiteSpace($upn)) {
                $u = ([string]$upn).Trim()
                [void]$intendedUpns.Add($u)
                [void]$allUpns.Add($u)
            }
        }

        if ($wholeTenant -or $resolutionStatus -eq 'WholeTenantNotEnumerated') {
            # SEAM 2c: org-wide share. The tenant was deliberately not enumerated. Do NOT score
            # (and never report 0 blocked). A capped enumeration, if present, is reported as
            # evidence only - it is not the full tenant and must not be read as the blocked set.
            $wholeTenantAgents.Add([pscustomobject]@{
                    agentId             = $agentId
                    agentName           = $agentName
                    resolutionStatus    = $resolutionStatus
                    cappedAudienceSize  = $intendedUpns.Count
                    environmentId       = $environmentId
                })
            continue
        }

        if ($resolutionStatus -in $script:AudienceFailedStatuses) {
            # SEAM 5: the audience could not be resolved at all (Failed / NotResolved). There is
            # no usable audience, so a blocked count is NOT computable. Do NOT score and do NOT
            # emit 0 blocked - surface as a Failed-coverage row with blockedUserCount=null.
            $failedAudienceAgents.Add([pscustomobject]@{
                    agentId            = $agentId
                    agentName          = $agentName
                    resolutionStatus   = $resolutionStatus
                    cappedAudienceSize = $intendedUpns.Count
                    environmentId      = $environmentId
                })
            continue
        }

        # Group-scoped agent: assemble the engine-ready skeleton record.
        $skeletonAgents.Add([pscustomobject]@{
                agentId        = $agentId
                agentName      = $agentName
                createdIn      = $createdIn
                configuredTier = $ConfiguredTier            # WIQ out of scope -> empty (createdIn fallback)
                spendScope     = $SpendScope
                sourcePolicyId = $null
                intendedUpns   = $intendedUpns.ToArray()
            })

        $scoredMeta[$agentId] = [pscustomobject]@{
            agentId             = $agentId
            agentName           = $agentName
            createdIn           = $createdIn
            audienceMode        = 'GroupScoped'
            resolutionStatus    = $resolutionStatus
            truncated           = $truncated
            audienceSize        = $audienceSize
            resolutionErrorCount = @($resolutionErrors).Count
            audienceUpns        = $intendedUpns.ToArray()
            createdInMissing    = [string]::IsNullOrWhiteSpace("$createdIn")
        }
    }

    return [pscustomobject]@{
        Skeleton              = [pscustomobject]@{ agents = $skeletonAgents.ToArray() }
        ScoredMeta            = $scoredMeta
        WholeTenantAgents     = $wholeTenantAgents.ToArray()
        FailedAudienceAgents  = $failedAudienceAgents.ToArray()
        MissingAudienceAgents = $missingAudienceAgents.ToArray()
        AllUpns               = @($allUpns)
    }
}

# --------------------------------------------------------------------------------------
# SEAM 5 - Per-agent coverage roll-up. Folds every coverage gap into a single Complete /
# Partial / Failed status so nothing hides behind "0 blocked".
# --------------------------------------------------------------------------------------
function Get-FnfAgentCoverageStatus {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][string]$AudienceStatus = 'Complete',
        [Parameter()][bool]$Truncated = $false,
        [Parameter()][int]$ResolutionErrorCount = 0,
        [Parameter()][bool]$WholeTenant = $false,
        [Parameter()][bool]$AudienceMissing = $false,
        [Parameter()][int]$UnresolvedUserCount = 0,
        [Parameter()][int]$NeedsManualReviewCount = 0,
        [Parameter()][bool]$PaygAllUsersCovered = $false,
        [Parameter()][int]$FailOpenCount = 0,
        [Parameter()][bool]$Provisional = $false,
        [Parameter()][bool]$AttestationPending = $false,
        [Parameter()][bool]$CreatedInMissing = $false
    )

    $gaps = New-Object System.Collections.Generic.List[string]

    if ($Provisional) { [void]$gaps.Add('manifest-id-unreconciled') }
    if ($AttestationPending) { [void]$gaps.Add('manifest-opaque-attestation-pending') }
    if ($WholeTenant) { [void]$gaps.Add('audience-wholetenant-not-enumerated') }
    if ($AudienceMissing) { [void]$gaps.Add('audience-not-resolved') }
    if ($AudienceStatus -in $script:AudienceFailedStatuses) { [void]$gaps.Add('audience-resolution-failed') }
    if ($AudienceStatus -eq 'Partial') { [void]$gaps.Add('audience-resolution-partial') }
    if ($Truncated) { [void]$gaps.Add('audience-truncated') }
    if ($ResolutionErrorCount -gt 0) { [void]$gaps.Add('audience-resolution-errors') }
    if ($UnresolvedUserCount -gt 0) { [void]$gaps.Add('entitlement-unresolved-users') }
    if ($NeedsManualReviewCount -gt 0) { [void]$gaps.Add('payg-policy-needs-manual-review') }
    if ($PaygAllUsersCovered) { [void]$gaps.Add('payg-all-users-coverage') }
    if ($FailOpenCount -gt 0) { [void]$gaps.Add('pathway-unmapped-fail-open') }
    if ($CreatedInMissing -and $FailOpenCount -eq 0) {
        # createdIn absent: pathway classification fell back; surface even if no fail-open yet.
        [void]$gaps.Add('createdin-missing-pathway-fallback')
    }

    $status = 'Complete'
    if ($AudienceMissing -or ($AudienceStatus -in $script:AudienceFailedStatuses)) {
        # No usable audience -> blocked count is not computable -> most severe status.
        $status = 'Failed'
    }
    elseif ($gaps.Count -gt 0) {
        $status = 'Partial'
    }

    return [pscustomobject]@{
        coverageStatus = $status
        coverageGaps   = $gaps.ToArray()
    }
}

# --------------------------------------------------------------------------------------
# Per-user scoring through the EXISTING CBG resolver + engine (the entitlement rule is not
# re-implemented here). Requires Invoke-CbgEntitlementResolution in scope (dot-source the
# resolver first) so the single HTTP seam (Invoke-CbgRestMethod) is mockable in tests.
# --------------------------------------------------------------------------------------
function Invoke-FnfEntitlementScoring {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][psobject]$Skeleton,
        [Parameter()][AllowEmptyCollection()][string[]]$AllUpns = @(),
        [Parameter(Mandatory)][string]$GraphToken,
        [Parameter(Mandatory)][ValidateSet('CopilotChat', 'SharePointAgents', 'Both')][string]$Capability,
        [Parameter()][AllowNull()][object[]]$Policy,
        [Parameter()][string]$ApiAudienceGroupId,
        [Parameter()][string]$EligibleCohortGroupId,
        [Parameter()][string]$CreditScopeGroupId,
        [Parameter()][bool]$SurfaceZeroRatedValue = $true,
        [Parameter()][bool]$ZeroRatingResolvedValue = $true,
        [Parameter(Mandatory)][string]$EngineScript,
        [Parameter(Mandatory)][string]$WorkingDir
    )

    if (-not (Get-Command -Name Invoke-CbgEntitlementResolution -ErrorAction SilentlyContinue)) {
        throw "Invoke-CbgEntitlementResolution is not loaded. Dot-source Get-CopilotEntitlement.ps1 before scoring."
    }

    $agents = @(Get-FnfProperty -InputObject $Skeleton -Name 'agents')

    # The resolver produces the per-user booleans (license + PAYG + cohorts) and assembles the
    # engine-ready document (agents[].intendedUsers[] with the 6 booleans). Token acquisition
    # and HTTP go through the resolver's mockable seam.
    $resolverResult = Invoke-CbgEntitlementResolution `
        -Upn $AllUpns -AgentsSkeleton $agents -Policy @($Policy) `
        -GraphToken $GraphToken -Capability $Capability `
        -ApiAudienceGroupId $ApiAudienceGroupId -EligibleCohortGroupId $EligibleCohortGroupId `
        -CreditScopeGroupId $CreditScopeGroupId -SurfaceZeroRatedValue $SurfaceZeroRatedValue

    $decisions = @()
    $engineInput = Get-FnfProperty -InputObject $resolverResult -Name 'engineInput'
    if ($null -ne $engineInput) {
        if (-not (Test-Path -LiteralPath $WorkingDir)) {
            New-Item -ItemType Directory -Path $WorkingDir -Force | Out-Null
        }
        $stamp = [guid]::NewGuid().ToString('n')
        $engineInputFile = Join-Path $WorkingDir "fnf-engine-input-$stamp.json"
        $decisionFile = Join-Path $WorkingDir "fnf-engine-decisions-$stamp.json"

        $engineInput | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $engineInputFile -Encoding UTF8

        # Run the existing engine (separate process); it reads the file and writes decisions.
        & $EngineScript -InputPath $engineInputFile -OutputPath $decisionFile -ZeroRatingResolved $ZeroRatingResolvedValue | Out-Null

        if (Test-Path -LiteralPath $decisionFile) {
            $engineResult = Get-Content -LiteralPath $decisionFile -Raw | ConvertFrom-Json
            $decisions = @(Get-FnfProperty -InputObject $engineResult -Name 'Decisions')
        }
    }

    return [pscustomobject]@{
        Decisions      = $decisions
        ResolverResult = $resolverResult
    }
}

# --------------------------------------------------------------------------------------
# Report assembly (pure). Folds scored decisions, whole-tenant agents, missing-audience
# agents, and unreconciled provisional rows into the FNF report row schema.
# --------------------------------------------------------------------------------------
function New-FnfPeopleSweepReport {
    [CmdletBinding()]
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSUseShouldProcessForStateChangingFunctions', '',
        Justification = 'New-FnfPeopleSweepReport is a pure assembly function: it folds already-computed inputs into an in-memory report object and changes no system state. ShouldProcess is not applicable.')]
    [OutputType([pscustomobject])]
    param(
        [Parameter()][AllowNull()][hashtable]$ScoredMeta,
        [Parameter()][AllowEmptyCollection()][object[]]$WholeTenantAgents = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$MissingAudienceAgents = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$FailedAudienceAgents = @(),
        [Parameter()][AllowEmptyCollection()][object[]]$ProvisionalUnreconciled = @(),
        [Parameter()][AllowNull()][hashtable]$PeopleAgentSourceMap,
        [Parameter()][AllowEmptyCollection()][object[]]$EngineDecisions = @(),
        [Parameter()][AllowNull()][psobject]$ResolverResult,
        [Parameter()][int]$SampleCapValue = 20,
        [Parameter()][string]$Capability = 'CopilotChat'
    )

    if ($null -eq $ScoredMeta) { $ScoredMeta = @{} }
    if ($null -eq $PeopleAgentSourceMap) { $PeopleAgentSourceMap = @{} }

    # Cross-agent resolver signals (policy-level / tenant-wide for the scored UPN set).
    $needsManualReview = 0
    $paygAllUsers = $false
    $paygUncertain = $false
    $resolverUnresolvedCount = 0
    $unresolvedUpns = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    if ($null -ne $ResolverResult) {
        $summary = Get-FnfProperty -InputObject $ResolverResult -Name 'summary'
        if ($null -ne $summary) {
            $needsManualReview = [int](Get-FnfProperty -InputObject $summary -Name 'needsManualReviewCount' -Default 0)
            $paygAllUsers = [bool](Get-FnfProperty -InputObject $summary -Name 'paygAllUsersCovered' -Default $false)
            $paygUncertain = [bool](Get-FnfProperty -InputObject $summary -Name 'paygCoverageUncertain' -Default $false)
            $resolverUnresolvedCount = [int](Get-FnfProperty -InputObject $summary -Name 'unresolvedCount' -Default 0)
        }
        foreach ($u in @(Get-FnfProperty -InputObject $ResolverResult -Name 'unresolved')) {
            $upn = Get-FnfProperty -InputObject $u -Name 'upn'
            if (-not [string]::IsNullOrWhiteSpace($upn)) { [void]$unresolvedUpns.Add([string]$upn) }
        }
    }

    # Index engine decisions by agentId.
    $decisionsByAgent = @{}
    foreach ($d in @($EngineDecisions)) {
        $aid = "$(Get-FnfProperty -InputObject $d -Name 'fsi_agentid')"
        if ([string]::IsNullOrWhiteSpace($aid)) { continue }
        if (-not $decisionsByAgent.ContainsKey($aid)) { $decisionsByAgent[$aid] = New-Object System.Collections.Generic.List[object] }
        $decisionsByAgent[$aid].Add($d)
    }

    $rows = New-Object System.Collections.Generic.List[object]
    $now = (Get-Date).ToUniversalTime().ToString('o')

    # --- Scored (group-scoped) agents. ---
    foreach ($agentId in @($ScoredMeta.Keys)) {
        $meta = $ScoredMeta[$agentId]
        # NOTE: use List.ToArray() rather than @(...) - under Set-StrictMode -Version Latest the
        # array-subexpression operator throws "Argument types do not match" when wrapping a
        # System.Collections.Generic.List[object] in this PowerShell build.
        $agentDecisions = @()
        if ($decisionsByAgent.ContainsKey($agentId)) { $agentDecisions = $decisionsByAgent[$agentId].ToArray() }

        # Authoritative FNF blocked set: engine decisions with fsi_decision = Block (100000001).
        $blocked = @($agentDecisions | Where-Object { [int](Get-FnfProperty -InputObject $_ -Name 'fsi_decision' -Default 0) -eq $script:DecisionBlock })
        $blockedUpns = @($blocked | ForEach-Object { Get-FnfProperty -InputObject $_ -Name 'fsi_userupn' })
        $failOpenCount = @($agentDecisions | Where-Object { [int](Get-FnfProperty -InputObject $_ -Name 'fsi_decision' -Default 0) -eq $script:DecisionFailOpenAnomaly }).Count
        $failClosedCount = @($agentDecisions | Where-Object { [int](Get-FnfProperty -InputObject $_ -Name 'fsi_decision' -Default 0) -eq $script:DecisionFailClosedZeroRating }).Count

        # Per-agent unresolved-user count: audience UPNs that the resolver could not verify.
        $agentUnresolved = 0
        foreach ($u in @(Get-FnfProperty -InputObject $meta -Name 'audienceUpns')) {
            if ($unresolvedUpns.Contains([string]$u)) { $agentUnresolved++ }
        }

        $source = if ($PeopleAgentSourceMap.ContainsKey($agentId)) { $PeopleAgentSourceMap[$agentId] } else { 'manifest' }

        $coverage = Get-FnfAgentCoverageStatus `
            -AudienceStatus "$(Get-FnfProperty -InputObject $meta -Name 'resolutionStatus' -Default 'Complete')" `
            -Truncated ([bool](Get-FnfProperty -InputObject $meta -Name 'truncated' -Default $false)) `
            -ResolutionErrorCount ([int](Get-FnfProperty -InputObject $meta -Name 'resolutionErrorCount' -Default 0)) `
            -UnresolvedUserCount $agentUnresolved `
            -NeedsManualReviewCount $needsManualReview `
            -PaygAllUsersCovered $paygAllUsers `
            -FailOpenCount $failOpenCount `
            -CreatedInMissing ([bool](Get-FnfProperty -InputObject $meta -Name 'createdInMissing' -Default $false)) `
            -AttestationPending ($source -eq 'attested')

        $sampleUpns = @($blockedUpns | Select-Object -First $SampleCapValue)

        $rows.Add([pscustomobject]@{
                agentId             = $agentId
                agentName           = Get-FnfProperty -InputObject $meta -Name 'agentName'
                peopleCapable       = $true
                peopleCapableSource = $source
                audienceMode        = 'GroupScoped'
                coverageStatus      = $coverage.coverageStatus
                coverageGaps        = $coverage.coverageGaps
                blockedUserCount    = $blocked.Count
                blockedUsers        = $sampleUpns
                blockedUsersSampled = ($blocked.Count -gt $sampleUpns.Count)
                totalAudience       = [int](Get-FnfProperty -InputObject $meta -Name 'audienceSize' -Default 0)
                evaluationTimestamp = $now
                evidence            = [pscustomobject]@{
                    createdIn                         = Get-FnfProperty -InputObject $meta -Name 'createdIn'
                    audienceResolutionStatus          = Get-FnfProperty -InputObject $meta -Name 'resolutionStatus'
                    audienceTruncated                 = [bool](Get-FnfProperty -InputObject $meta -Name 'truncated' -Default $false)
                    audienceResolutionErrorCount      = [int](Get-FnfProperty -InputObject $meta -Name 'resolutionErrorCount' -Default 0)
                    decisionCount                     = $agentDecisions.Count
                    failOpenAnomalyCount              = $failOpenCount
                    failClosedZeroRatingCount         = $failClosedCount
                    unresolvedAudienceUserCount       = $agentUnresolved
                    cbgResolverUnresolvedCount        = $resolverUnresolvedCount
                    cbgResolverNeedsManualReviewCount = $needsManualReview
                    paygAllUsersCovered               = $paygAllUsers
                    paygCoverageUncertain             = $paygUncertain
                }
            })
    }

    # --- Whole-tenant agents (NOT scored; never "0 blocked"). ---
    foreach ($wt in @($WholeTenantAgents)) {
        $agentId = "$(Get-FnfProperty -InputObject $wt -Name 'agentId')"
        $source = if ($PeopleAgentSourceMap.ContainsKey($agentId)) { $PeopleAgentSourceMap[$agentId] } else { 'manifest' }
        $coverage = Get-FnfAgentCoverageStatus -WholeTenant $true -AttestationPending ($source -eq 'attested')
        $rows.Add([pscustomobject]@{
                agentId             = $agentId
                agentName           = Get-FnfProperty -InputObject $wt -Name 'agentName'
                peopleCapable       = $true
                peopleCapableSource = $source
                audienceMode        = 'WholeTenant'
                coverageStatus      = $coverage.coverageStatus
                coverageGaps        = $coverage.coverageGaps
                blockedUserCount    = $null            # tenant minus licensed users - NOT enumerated
                blockedUsers        = @()
                blockedUsersSampled = $false
                totalAudience       = $null
                evaluationTimestamp = $now
                evidence            = [pscustomobject]@{
                    audienceResolutionStatus = Get-FnfProperty -InputObject $wt -Name 'resolutionStatus'
                    blockedUsersComputed     = $false
                    wholeTenantCappedAudienceSize = [int](Get-FnfProperty -InputObject $wt -Name 'cappedAudienceSize' -Default 0)
                    note = 'Org-wide share; blocked count is tenant minus licensed users and was not enumerated.'
                }
            })
    }

    # --- People-capable agents missing from the audience artifact (audience not resolved). ---
    foreach ($ma in @($MissingAudienceAgents)) {
        $agentId = "$(Get-FnfProperty -InputObject $ma -Name 'agentId')"
        $source = if ($PeopleAgentSourceMap.ContainsKey($agentId)) { $PeopleAgentSourceMap[$agentId] } else { 'manifest' }
        $coverage = Get-FnfAgentCoverageStatus -AudienceMissing $true -AttestationPending ($source -eq 'attested')
        $rows.Add([pscustomobject]@{
                agentId             = $agentId
                agentName           = Get-FnfProperty -InputObject $ma -Name 'agentName'
                peopleCapable       = $true
                peopleCapableSource = $source
                audienceMode        = 'None'
                coverageStatus      = $coverage.coverageStatus
                coverageGaps        = $coverage.coverageGaps
                blockedUserCount    = $null
                blockedUsers        = @()
                blockedUsersSampled = $false
                totalAudience       = $null
                evaluationTimestamp = $now
                evidence            = [pscustomobject]@{
                    note = 'People-capable agent selected but not present in the audience artifact; audience not resolved.'
                }
            })
    }

    # --- People-capable agents whose audience could not be resolved (Failed / NotResolved). ---
    foreach ($fa in @($FailedAudienceAgents)) {
        $agentId = "$(Get-FnfProperty -InputObject $fa -Name 'agentId')"
        $source = if ($PeopleAgentSourceMap.ContainsKey($agentId)) { $PeopleAgentSourceMap[$agentId] } else { 'manifest' }
        $status = "$(Get-FnfProperty -InputObject $fa -Name 'resolutionStatus' -Default 'Failed')"
        $coverage = Get-FnfAgentCoverageStatus -AudienceStatus $status -AttestationPending ($source -eq 'attested')
        $rows.Add([pscustomobject]@{
                agentId             = $agentId
                agentName           = Get-FnfProperty -InputObject $fa -Name 'agentName'
                peopleCapable       = $true
                peopleCapableSource = $source
                audienceMode        = 'None'
                coverageStatus      = $coverage.coverageStatus
                coverageGaps        = $coverage.coverageGaps
                blockedUserCount    = $null            # audience not resolved - blocked is not computable
                blockedUsers        = @()
                blockedUsersSampled = $false
                totalAudience       = $null
                evaluationTimestamp = $now
                evidence            = [pscustomobject]@{
                    audienceResolutionStatus = $status
                    blockedUsersComputed     = $false
                    note = 'Audience resolution failed (Failed/NotResolved); blocked count is not computable and was not enumerated.'
                }
            })
    }

    # --- Unreconciled provisional People agents (SEAM 1 leftover; never silently dropped). ---
    foreach ($pv in @($ProvisionalUnreconciled)) {
        $coverage = Get-FnfAgentCoverageStatus -Provisional $true
        $rows.Add([pscustomobject]@{
                agentId             = Get-FnfProperty -InputObject $pv -Name 'agentId'
                agentName           = Get-FnfProperty -InputObject $pv -Name 'agentName'
                peopleCapable       = $true
                peopleCapableSource = "$(Get-FnfProperty -InputObject $pv -Name 'source' -Default 'manifest')"
                audienceMode        = 'None'
                coverageStatus      = $coverage.coverageStatus
                coverageGaps        = $coverage.coverageGaps
                blockedUserCount    = $null            # cannot join an unreconciled provisional id
                blockedUsers        = @()
                blockedUsersSampled = $false
                totalAudience       = $null
                evaluationTimestamp = $now
                evidence            = [pscustomobject]@{
                    agentRefProvisional = $true
                    note = 'Provisional manifest id not reconciled to a Dataverse bot GUID; supply -IdMapPath to bind it.'
                }
            })
    }

    $rowArray = $rows.ToArray()
    $partialCount = @($rowArray | Where-Object { $_.coverageStatus -eq 'Partial' }).Count
    $failedCount = @($rowArray | Where-Object { $_.coverageStatus -eq 'Failed' }).Count
    $completeCount = @($rowArray | Where-Object { $_.coverageStatus -eq 'Complete' }).Count
    $totalBlocked = (@($rowArray | Where-Object { $null -ne $_.blockedUserCount } | ForEach-Object { [int]$_.blockedUserCount }) | Measure-Object -Sum).Sum
    if ($null -eq $totalBlocked) { $totalBlocked = 0 }
    $agentsWithBlocked = @($rowArray | Where-Object { $null -ne $_.blockedUserCount -and [int]$_.blockedUserCount -gt 0 }).Count

    return [pscustomobject]@{
        schemaVersion   = $script:FnfSchemaVersion
        reportType      = 'FnfPeopleSweep'
        generatedAt     = $now
        gatedCapability = $Capability
        summary         = [pscustomobject]@{
            peopleCapableAgentCount  = $rowArray.Count
            scoredAgentCount         = $ScoredMeta.Count
            wholeTenantAgentCount    = @($WholeTenantAgents).Count
            failedAudienceCount      = @($FailedAudienceAgents).Count
            missingAudienceCount     = @($MissingAudienceAgents).Count
            provisionalUnreconciled  = @($ProvisionalUnreconciled).Count
            coverageCompleteCount    = $completeCount
            coveragePartialCount     = $partialCount
            coverageFailedCount      = $failedCount
            totalBlockedUserCount    = [int]$totalBlocked
            agentsWithBlockedUsers   = $agentsWithBlocked
        }
        agents          = $rowArray
    }
}

# --------------------------------------------------------------------------------------
# Testable core orchestration: wire SEAM 1 -> SEAM 2/2c -> scoring -> SEAM 5 over already
# parsed inputs. Tests call this directly with fixtures and a mocked Invoke-CbgRestMethod.
# --------------------------------------------------------------------------------------
function Invoke-FnfPeopleSweep {
    [CmdletBinding()]
    [OutputType([pscustomobject])]
    param(
        [Parameter(Mandatory)][psobject]$CapabilityArtifact,
        [Parameter(Mandatory)][psobject]$AudienceArtifact,
        [Parameter()][AllowNull()]$AgentMaster,
        [Parameter()][AllowNull()]$IdMap,
        [Parameter()][AllowNull()][object[]]$Policy,
        [Parameter(Mandatory)][string]$GraphToken,
        [Parameter()][ValidateSet('CopilotChat', 'SharePointAgents', 'Both')][string]$Capability = 'CopilotChat',
        [Parameter()][string]$ApiAudienceGroupId,
        [Parameter()][string]$EligibleCohortGroupId,
        [Parameter()][string]$CreditScopeGroupId,
        [Parameter()][bool]$SurfaceZeroRatedValue = $true,
        [Parameter()][bool]$ZeroRatingResolvedValue = $true,
        [Parameter(Mandatory)][string]$EngineScript,
        [Parameter(Mandatory)][string]$WorkingDir,
        [Parameter()][int]$SampleCapValue = 20
    )

    # Normalize the optional agent master + id-map into lookups.
    $agentMasterMap = ConvertTo-FnfAgentMasterMap -InputObject $AgentMaster
    $idMapTable = ConvertTo-FnfIdMap -InputObject $IdMap

    # SEAM 1: People filter + provisional gate + id-map reconciliation.
    $peopleSet = Resolve-FnfPeopleAgentSet -CapabilityArtifact $CapabilityArtifact -IdMap $idMapTable

    # SEAM 2 + 2c: field-shape transform, createdIn join, whole-tenant special-casing.
    $skel = ConvertTo-FnfResolverSkeleton -AudienceArtifact $AudienceArtifact `
        -PeopleAgents $peopleSet.Resolved -AgentMaster $agentMasterMap

    # Scoring through the existing resolver + engine (only when there are users to score).
    $decisions = @()
    $resolverResult = $null
    if (@($skel.Skeleton.agents).Count -gt 0) {
        $scoring = Invoke-FnfEntitlementScoring -Skeleton $skel.Skeleton -AllUpns @($skel.AllUpns) `
            -GraphToken $GraphToken -Capability $Capability -Policy @($Policy) `
            -ApiAudienceGroupId $ApiAudienceGroupId -EligibleCohortGroupId $EligibleCohortGroupId `
            -CreditScopeGroupId $CreditScopeGroupId -SurfaceZeroRatedValue $SurfaceZeroRatedValue `
            -ZeroRatingResolvedValue $ZeroRatingResolvedValue -EngineScript $EngineScript -WorkingDir $WorkingDir
        $decisions = @($scoring.Decisions)
        $resolverResult = $scoring.ResolverResult
    }

    # SEAM 5: report assembly with the coverage roll-up.
    return New-FnfPeopleSweepReport -ScoredMeta $skel.ScoredMeta -WholeTenantAgents $skel.WholeTenantAgents `
        -FailedAudienceAgents $skel.FailedAudienceAgents `
        -MissingAudienceAgents $skel.MissingAudienceAgents -ProvisionalUnreconciled $peopleSet.ProvisionalUnreconciled `
        -PeopleAgentSourceMap $peopleSet.SourceMap -EngineDecisions $decisions -ResolverResult $resolverResult `
        -SampleCapValue $SampleCapValue -Capability $Capability
}

# ======================================================================================
# Main (runs only on direct invocation; dot-sourcing for tests skips this block).
# ======================================================================================
if ($MyInvocation.InvocationName -ne '.') {

    if (-not (Test-Path -LiteralPath $CapabilityArtifactPath)) { throw "Capability artifact not found: $CapabilityArtifactPath" }
    if (-not (Test-Path -LiteralPath $AudienceArtifactPath)) { throw "Audience artifact not found: $AudienceArtifactPath" }

    $capabilityArtifact = Get-Content -LiteralPath $CapabilityArtifactPath -Raw | ConvertFrom-Json
    $audienceArtifact = Get-Content -LiteralPath $AudienceArtifactPath -Raw | ConvertFrom-Json

    $agentMaster = $null
    if (-not [string]::IsNullOrWhiteSpace($AgentMasterPath)) {
        if (-not (Test-Path -LiteralPath $AgentMasterPath)) { throw "Agent master file not found: $AgentMasterPath" }
        $agentMaster = Get-Content -LiteralPath $AgentMasterPath -Raw | ConvertFrom-Json
    }
    else {
        Write-Warning "No -AgentMasterPath supplied; createdIn cannot be joined. Agents may classify as 'unmapped' (fail-open) and report coverageStatus=Partial."
    }

    $idMap = $null
    if (-not [string]::IsNullOrWhiteSpace($IdMapPath)) {
        if (-not (Test-Path -LiteralPath $IdMapPath)) { throw "Id-map file not found: $IdMapPath" }
        $idMap = Get-Content -LiteralPath $IdMapPath -Raw | ConvertFrom-Json
    }

    $policy = @()
    if (-not [string]::IsNullOrWhiteSpace($BillingPolicyInputPath)) {
        if (-not (Test-Path -LiteralPath $BillingPolicyInputPath)) { throw "Billing policy file not found: $BillingPolicyInputPath" }
        $bpObject = Get-Content -LiteralPath $BillingPolicyInputPath -Raw | ConvertFrom-Json
        $bpArray = Get-FnfProperty -InputObject $bpObject -Name 'billingPolicies'
        if ($null -eq $bpArray) { $bpArray = $bpObject }
        $policy = @($bpArray)
    }

    # Resolve sibling script paths.
    $scriptDir = Split-Path -Parent $PSCommandPath
    if ([string]::IsNullOrWhiteSpace($ResolverScriptPath)) { $ResolverScriptPath = Join-Path $scriptDir 'Get-CopilotEntitlement.ps1' }
    if ([string]::IsNullOrWhiteSpace($EngineScriptPath)) { $EngineScriptPath = Join-Path $scriptDir 'Invoke-EntitlementEvaluation.ps1' }
    if (-not (Test-Path -LiteralPath $ResolverScriptPath)) { throw "CBG resolver not found: $ResolverScriptPath" }
    if (-not (Test-Path -LiteralPath $EngineScriptPath)) { throw "CBG engine not found: $EngineScriptPath" }

    # Working directory for intermediate engine files.
    if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        if (-not [string]::IsNullOrWhiteSpace($ReportOutputPath)) {
            $WorkingDirectory = Split-Path -Parent ([System.IO.Path]::GetFullPath($ReportOutputPath))
        }
        if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) { $WorkingDirectory = (Get-Location).Path }
    }

    # Dot-source the resolver so Invoke-CbgEntitlementResolution (and its mockable HTTP seam)
    # is in scope. The resolver's main body is guarded off when dot-sourced.
    . $ResolverScriptPath -UserPrincipalName 'fnf-lens-placeholder@invalid.local'

    # Acquire the Graph token (managed-identity-first; resolver falls back to Get-AzAccessToken).
    $graphToken = Get-CbgResourceToken -ResourceUrl 'https://graph.microsoft.com' -ProvidedToken $GraphAccessToken

    # Live billing-policy read fallback (only if no policies supplied).
    if (@($policy).Count -eq 0 -and [string]::IsNullOrWhiteSpace($BillingPolicyInputPath)) {
        Write-Verbose "No billing policies supplied; attempting a live Power Platform billing-policy read via the resolver."
        $billingToken = Get-CbgResourceToken -ResourceUrl 'https://api.bap.microsoft.com/' -ProvidedToken $BillingApiAccessToken
        $policy = @(Get-CbgBillingPolicyLive -Token $billingToken)
    }

    $report = Invoke-FnfPeopleSweep `
        -CapabilityArtifact $capabilityArtifact -AudienceArtifact $audienceArtifact `
        -AgentMaster $agentMaster -IdMap $idMap -Policy @($policy) `
        -GraphToken $graphToken -Capability $GatedCapability `
        -ApiAudienceGroupId $ApiAudienceGroupId -EligibleCohortGroupId $EligibleCohortGroupId `
        -CreditScopeGroupId $CreditScopeGroupId -SurfaceZeroRatedValue $SurfaceZeroRated `
        -ZeroRatingResolvedValue $ZeroRatingResolved -EngineScript $EngineScriptPath `
        -WorkingDir $WorkingDirectory -SampleCapValue $SampleCap

    if (-not [string]::IsNullOrWhiteSpace($ReportOutputPath)) {
        $report | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $ReportOutputPath -Encoding UTF8
        Write-Verbose "Wrote FNF People-Sweep report to $ReportOutputPath."
    }

    $s = $report.summary
    Write-Host "FNF People-Sweep: $($s.peopleCapableAgentCount) People-capable agent(s) - Complete=$($s.coverageCompleteCount) Partial=$($s.coveragePartialCount) Failed=$($s.coverageFailedCount); $($s.totalBlockedUserCount) blocked user(s) across $($s.agentsWithBlockedUsers) agent(s)."
    if ($s.coveragePartialCount -gt 0 -or $s.coverageFailedCount -gt 0) {
        Write-Host "Coverage is not Complete for every agent; review coverageGaps before treating any '0 blocked' as fully entitled."
    }

    Write-Output $report
}
