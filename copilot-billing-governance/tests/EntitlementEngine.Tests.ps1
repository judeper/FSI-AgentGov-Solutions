#Requires -Version 7.2
#Requires -Modules @{ ModuleName = "Pester"; ModuleVersion = "5.0.0" }

<#
.SYNOPSIS
    Pester 5 integration tests for Invoke-EntitlementEvaluation.ps1 - the
    copilot-billing-governance switch-on-pathway entitlement engine.

.DESCRIPTION
    Exercises the engine end-to-end: each test writes a crafted agents+users
    fixture to a TestDrive JSON file, invokes the script with -InputPath /
    -OutputPath, reads the result JSON back, and asserts the materialized
    fsi_pathway / fsi_decision option-set integer values against the documented
    contract in docs/entitlement-contract.md.

    Coverage:
      - pathway none (NotConfigured / Adjacent tiers) -> Allow - Eligibility N/A.
        This is the regression guard for the agent majority: a non-metered tier
        must NOT be denied, even when createdIn looks like Copilot Studio.
      - pathway mcp-cs: licensed + zero-rated surface -> Allow by default
        (-ZeroRatingResolved defaults to true per the June 2026 Licensing
        Guide); the same case with -ZeroRatingResolved:$false and no credit
        scope -> Fail-closed - Zero-rating Unresolved; unlicensed -> Block.
      - pathway api-direct: in / out of the API audience cohort -> Allow / Block.
      - pathway metered: in / out of the eligible cohort -> Allow / Block.
      - pathway unmapped: unrecognized tier and surface -> Fail-open - Anomaly
        (a classifier defect must not deny a user).

.NOTES
    The expected integer values mirror the engine's $script:Decision and
    $script:Pathway maps (the fsi_cbg_* global option sets in
    docs/dataverse-schema.md). Run with:
        Invoke-Pester -Path .\EntitlementEngine.Tests.ps1 -Output Detailed
#>

param()

BeforeAll {
    $script:EngineScript = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Invoke-EntitlementEvaluation.ps1')).Path
    $script:FixtureDir = $TestDrive

    # Option-set integer values mirrored from the engine's $script:Decision and
    # $script:Pathway maps (see docs/dataverse-schema.md fsi_cbg_* option sets).
    $script:DecisionAllow                = 100000000
    $script:DecisionBlock                = 100000001
    $script:DecisionAllowEligibilityNA   = 100000002
    $script:DecisionFailOpenAnomaly      = 100000003
    $script:DecisionFailClosedZeroRating = 100000004

    $script:PathwayNone            = 100000000
    $script:PathwayMcpCs           = 100000001
    $script:PathwayMcpAgentBuilder = 100000002
    $script:PathwayApiDirect       = 100000003
    $script:PathwayMetered         = 100000004
    $script:PathwayUnmapped        = 100000005

    # fsi_cbgblockreason option-set integer surfaced by the coverage-gap aggregate
    # (fsi_blockreasonsummary); mirrors the engine's $script:BlockReason map.
    $script:BlockReasonNoEligibleCohort = 100000000

    # Returns a fresh intended-user hashtable with every flag present (the engine
    # runs under Set-StrictMode -Version Latest, so each referenced property must
    # exist) and defaulted to the not-eligible posture.
    function Get-CbgBaselineUser {
        return @{
            upn                = 'user@contoso.com'
            hasCopilotLicense  = $false
            inApiAudienceGroup = $false
            inEligibleCohort   = $false
            inCreditScopeGroup = $false
            surfaceZeroRated   = $false
        }
    }

    # Returns a fresh agent hashtable carrying the four properties the engine
    # reads directly (createdIn / configuredTier are accessed without a guard).
    function Get-CbgAgent {
        param(
            [Parameter(Mandatory)][AllowEmptyString()][string]$ConfiguredTier,
            [Parameter(Mandatory)][AllowEmptyString()][string]$CreatedIn,
            [Parameter(Mandatory)][hashtable]$User
        )
        return @{
            agentId        = 'agent-0001'
            agentName      = 'Fixture Agent'
            createdIn      = $CreatedIn
            configuredTier = $ConfiguredTier
            intendedUsers  = @($User)
        }
    }

    # Like Get-CbgAgent but carries an arbitrary intended-user set, so the per-agent
    # coverage-gap aggregate (fsi_cbgcoveragegap) can be exercised with a mixed
    # Allow/Block population. ConfiguredTier/CreatedIn accept empty strings so the
    # createdIn fallback classifier can be driven directly.
    function Get-CbgAgentWithUsers {
        param(
            [Parameter(Mandatory)][AllowEmptyString()][string]$ConfiguredTier,
            [Parameter(Mandatory)][AllowEmptyString()][string]$CreatedIn,
            [Parameter(Mandatory)][object[]]$Users,
            [Parameter()][string]$AgentId = 'agent-cov-0001',
            [Parameter()][string]$AgentName = 'Coverage Fixture Agent'
        )
        return @{
            agentId        = $AgentId
            agentName      = $AgentName
            createdIn      = $CreatedIn
            configuredTier = $ConfiguredTier
            intendedUsers  = @($Users)
        }
    }

    # Writes the fixture, invokes the engine, and returns the parsed result
    # object. When -ZeroRatingResolved is omitted the engine default (true) is
    # exercised; pass $true / $false to assert the toggle explicitly.
    function Invoke-CbgEngine {
        [CmdletBinding()]
        param(
            [Parameter(Mandatory)][object[]]$Agents,
            [Parameter()][object]$ZeroRatingResolved = $null
        )
        $id = [guid]::NewGuid().ToString('n')
        $inputFile = Join-Path $script:FixtureDir "in-$id.json"
        $outputFile = Join-Path $script:FixtureDir "out-$id.json"

        [pscustomobject]@{ agents = $Agents } |
            ConvertTo-Json -Depth 8 |
            Set-Content -LiteralPath $inputFile -Encoding UTF8

        $splat = @{ InputPath = $inputFile; OutputPath = $outputFile }
        if ($null -ne $ZeroRatingResolved) {
            $splat['ZeroRatingResolved'] = [bool]$ZeroRatingResolved
        }

        & $script:EngineScript @splat | Out-Null
        return (Get-Content -LiteralPath $outputFile -Raw | ConvertFrom-Json)
    }

    # The single-user fixtures emit exactly one decision; return it for asserts.
    function Get-CbgFirstDecision {
        param([Parameter(Mandatory)][psobject]$Result)
        return @($Result.Decisions)[0]
    }

    # A single-agent fixture emits exactly one coverage-gap aggregate; return it.
    function Get-CbgFirstGap {
        param([Parameter(Mandatory)][psobject]$Result)
        return @($Result.CoverageGaps)[0]
    }
}

Describe 'Invoke-EntitlementEvaluation result envelope' {
    It 'writes a result JSON with the evaluated decision count and zero-rating echo' {
        $user = Get-CbgBaselineUser
        $agent = Get-CbgAgent -ConfiguredTier 'NotConfigured' -CreatedIn '' -User $user

        $result = Invoke-CbgEngine -Agents @($agent)

        $result.AgentCount | Should -Be 1
        $result.DecisionCount | Should -Be 1
        # -ZeroRatingResolved was omitted, so the engine default (true) is echoed.
        $result.ZeroRatingResolved | Should -BeTrue
        @($result.Decisions).Count | Should -Be 1
    }
}

Describe 'Pathway none (non-metered agent majority)' {
    It 'maps the NotConfigured tier to Allow - Eligibility N/A even when createdIn looks like Copilot Studio' {
        # configuredTier is authoritative: a non-metered tier must win over a
        # Copilot-Studio createdIn so the agent majority is not denied.
        $user = Get-CbgBaselineUser
        $agent = Get-CbgAgent -ConfiguredTier 'NotConfigured' -CreatedIn 'Copilot Studio' -User $user

        $decision = Get-CbgFirstDecision -Result (Invoke-CbgEngine -Agents @($agent))

        $decision.fsi_pathway | Should -Be $script:PathwayNone
        $decision.fsi_decision | Should -Be $script:DecisionAllowEligibilityNA
    }

    It 'maps the Adjacent tier to Allow - Eligibility N/A' {
        $user = Get-CbgBaselineUser
        $agent = Get-CbgAgent -ConfiguredTier 'Adjacent' -CreatedIn '' -User $user

        $decision = Get-CbgFirstDecision -Result (Invoke-CbgEngine -Agents @($agent))

        $decision.fsi_pathway | Should -Be $script:PathwayNone
        $decision.fsi_decision | Should -Be $script:DecisionAllowEligibilityNA
    }
}

Describe 'Pathway mcp-cs (Copilot Studio native MCP)' {
    It 'allows a licensed user on a zero-rated surface by default' {
        $user = Get-CbgBaselineUser
        $user.hasCopilotLicense = $true
        $user.surfaceZeroRated = $true
        $agent = Get-CbgAgent -ConfiguredTier 'NativeMcpCopilotStudio' -CreatedIn 'Copilot Studio' -User $user

        $result = Invoke-CbgEngine -Agents @($agent)
        $decision = Get-CbgFirstDecision -Result $result

        $decision.fsi_pathway | Should -Be $script:PathwayMcpCs
        $decision.fsi_decision | Should -Be $script:DecisionAllow
    }

    It 'fails closed for the same case when zero-rating is explicitly unresolved' {
        # Same licensed + zero-rated surface, but no credit-scope fallback and
        # the conservative -ZeroRatingResolved:$false posture.
        $user = Get-CbgBaselineUser
        $user.hasCopilotLicense = $true
        $user.surfaceZeroRated = $true
        $user.inCreditScopeGroup = $false
        $agent = Get-CbgAgent -ConfiguredTier 'NativeMcpCopilotStudio' -CreatedIn 'Copilot Studio' -User $user

        $result = Invoke-CbgEngine -Agents @($agent) -ZeroRatingResolved $false
        $decision = Get-CbgFirstDecision -Result $result

        $result.ZeroRatingResolved | Should -BeFalse
        $decision.fsi_decision | Should -Be $script:DecisionFailClosedZeroRating
    }

    It 'blocks an unlicensed user' {
        $user = Get-CbgBaselineUser
        $user.hasCopilotLicense = $false
        $agent = Get-CbgAgent -ConfiguredTier 'NativeMcpCopilotStudio' -CreatedIn 'Copilot Studio' -User $user

        $decision = Get-CbgFirstDecision -Result (Invoke-CbgEngine -Agents @($agent))

        $decision.fsi_pathway | Should -Be $script:PathwayMcpCs
        $decision.fsi_decision | Should -Be $script:DecisionBlock
    }

    It 'allows a licensed user not on a zero-rated surface when in credit scope' {
        # License held and the surface is NOT zero-rated, but the user is in the
        # credit-scope group -> the credit-scope fallback grants ALLOW. This covers
        # the third mcp-cs allow gate (inCreditScopeGroup), distinct from the
        # zero-rated-surface gate exercised above.
        $user = Get-CbgBaselineUser
        $user.hasCopilotLicense = $true
        $user.surfaceZeroRated = $false
        $user.inCreditScopeGroup = $true
        $agent = Get-CbgAgent -ConfiguredTier 'NativeMcpCopilotStudio' -CreatedIn 'Copilot Studio' -User $user

        $decision = Get-CbgFirstDecision -Result (Invoke-CbgEngine -Agents @($agent))

        $decision.fsi_pathway | Should -Be $script:PathwayMcpCs
        $decision.fsi_decision | Should -Be $script:DecisionAllow
    }

    It 'fails closed by default when licensed, surface not zero-rated, and no credit scope' {
        # ZeroRatingResolved is left at the engine default (true), yet the surface is
        # NOT zero-rated and the user is not in credit scope. "Resolved" must not be
        # mistaken for "always allow": the base case still requires an actual
        # zero-rated surface (or credit scope), so this -> FAIL-CLOSED.
        $user = Get-CbgBaselineUser
        $user.hasCopilotLicense = $true
        $user.surfaceZeroRated = $false
        $user.inCreditScopeGroup = $false
        $agent = Get-CbgAgent -ConfiguredTier 'NativeMcpCopilotStudio' -CreatedIn 'Copilot Studio' -User $user

        $result = Invoke-CbgEngine -Agents @($agent)
        $decision = Get-CbgFirstDecision -Result $result

        $result.ZeroRatingResolved | Should -BeTrue
        $decision.fsi_pathway | Should -Be $script:PathwayMcpCs
        $decision.fsi_decision | Should -Be $script:DecisionFailClosedZeroRating
    }
}

Describe 'Pathway mcp-agentbuilder (Agent Builder via createdIn fallback)' {
    # configuredTier is empty, so the engine falls back to the createdIn regex
    # (agent.?builder) to classify the agentbuilder pathway. License is the only
    # gate on this arm: licensed -> Allow, unlicensed -> Block (Missing license).
    It 'allows a licensed user (createdIn fallback classifies the agentbuilder pathway)' {
        $user = Get-CbgBaselineUser
        $user.hasCopilotLicense = $true
        $agent = Get-CbgAgent -ConfiguredTier '' -CreatedIn 'Microsoft 365 Copilot Agent Builder' -User $user

        $decision = Get-CbgFirstDecision -Result (Invoke-CbgEngine -Agents @($agent))

        $decision.fsi_pathway | Should -Be $script:PathwayMcpAgentBuilder
        $decision.fsi_decision | Should -Be $script:DecisionAllow
    }

    It 'blocks an unlicensed user with the missing-license outcome' {
        $user = Get-CbgBaselineUser
        $user.hasCopilotLicense = $false
        $agent = Get-CbgAgent -ConfiguredTier '' -CreatedIn 'Microsoft 365 Copilot Agent Builder' -User $user

        $decision = Get-CbgFirstDecision -Result (Invoke-CbgEngine -Agents @($agent))

        $decision.fsi_pathway | Should -Be $script:PathwayMcpAgentBuilder
        $decision.fsi_decision | Should -Be $script:DecisionBlock
    }
}

Describe 'Pathway api-direct (declarative / API)' {
    It 'allows a user in the API audience cohort' {
        $user = Get-CbgBaselineUser
        $user.inApiAudienceGroup = $true
        $agent = Get-CbgAgent -ConfiguredTier 'NativeApiDirect' -CreatedIn 'API' -User $user

        $decision = Get-CbgFirstDecision -Result (Invoke-CbgEngine -Agents @($agent))

        $decision.fsi_pathway | Should -Be $script:PathwayApiDirect
        $decision.fsi_decision | Should -Be $script:DecisionAllow
    }

    It 'blocks a user outside the API audience cohort' {
        $user = Get-CbgBaselineUser
        $user.inApiAudienceGroup = $false
        $agent = Get-CbgAgent -ConfiguredTier 'NativeApiDirect' -CreatedIn 'API' -User $user

        $decision = Get-CbgFirstDecision -Result (Invoke-CbgEngine -Agents @($agent))

        $decision.fsi_pathway | Should -Be $script:PathwayApiDirect
        $decision.fsi_decision | Should -Be $script:DecisionBlock
    }
}

Describe 'Pathway metered (credit-consuming)' {
    It 'allows a user in the eligible cohort' {
        $user = Get-CbgBaselineUser
        $user.inEligibleCohort = $true
        $agent = Get-CbgAgent -ConfiguredTier 'metered' -CreatedIn '' -User $user

        $decision = Get-CbgFirstDecision -Result (Invoke-CbgEngine -Agents @($agent))

        $decision.fsi_pathway | Should -Be $script:PathwayMetered
        $decision.fsi_decision | Should -Be $script:DecisionAllow
    }

    It 'blocks a user outside the eligible cohort (the bounded ELSE)' {
        $user = Get-CbgBaselineUser
        $user.inEligibleCohort = $false
        $agent = Get-CbgAgent -ConfiguredTier 'metered' -CreatedIn '' -User $user

        $decision = Get-CbgFirstDecision -Result (Invoke-CbgEngine -Agents @($agent))

        $decision.fsi_pathway | Should -Be $script:PathwayMetered
        $decision.fsi_decision | Should -Be $script:DecisionBlock
    }
}

Describe 'Pathway unmapped (classifier anomaly)' {
    It 'fails open with an anomaly for an unrecognized tier and surface' {
        # Neither the tier nor the createdIn fallback regex matches a known
        # pathway, so the engine fails open rather than denying the user.
        $user = Get-CbgBaselineUser
        $agent = Get-CbgAgent -ConfiguredTier 'ZZZUnknownTierZZZ' -CreatedIn 'ZZZUnknownSurfaceZZZ' -User $user

        $decision = Get-CbgFirstDecision -Result (Invoke-CbgEngine -Agents @($agent))

        $decision.fsi_pathway | Should -Be $script:PathwayUnmapped
        $decision.fsi_decision | Should -Be $script:DecisionFailOpenAnomaly
    }
}

Describe 'CoverageGaps per-agent aggregate (fsi_cbgcoveragegap)' {
    It 'counts eligible vs blocked users and summarizes the dominant block reason' {
        # api-direct: one user in the API audience cohort (Allow) and two outside it
        # (Block - No eligible cohort). The aggregate must report 1 eligible, 2
        # blocked, a JSON sample array of the two blocked UPNs, and the dominant
        # block-reason summary.
        $allowed = Get-CbgBaselineUser
        $allowed.upn = 'allowed@contoso.com'
        $allowed.inApiAudienceGroup = $true
        $blocked1 = Get-CbgBaselineUser
        $blocked1.upn = 'blocked1@contoso.com'
        $blocked1.inApiAudienceGroup = $false
        $blocked2 = Get-CbgBaselineUser
        $blocked2.upn = 'blocked2@contoso.com'
        $blocked2.inApiAudienceGroup = $false
        $agent = Get-CbgAgentWithUsers -ConfiguredTier 'NativeApiDirect' -CreatedIn 'API' -Users @($allowed, $blocked1, $blocked2)

        $gap = Get-CbgFirstGap -Result (Invoke-CbgEngine -Agents @($agent))

        $gap.fsi_pathway | Should -Be $script:PathwayApiDirect
        $gap.fsi_eligibleusers | Should -Be 1
        $gap.fsi_blockeduserscount | Should -Be 2

        $sample = $gap.fsi_blockedsampleupns | ConvertFrom-Json
        @($sample).Count | Should -Be 2
        $sample | Should -Contain 'blocked1@contoso.com'
        $sample | Should -Contain 'blocked2@contoso.com'

        $gap.fsi_blockreasonsummary | Should -Be $script:BlockReasonNoEligibleCohort
    }

    It 'serializes a single blocked UPN as a JSON array, not a bare string (M-2 -AsArray guard)' {
        # A lone blocked user must still round-trip to a one-element JSON array.
        # Dropping -AsArray in the engine would emit the bare string "upn" instead of
        # ["upn"], so the exact-string assertion below catches that regression.
        $blocked = Get-CbgBaselineUser
        $blocked.upn = 'solo-blocked@contoso.com'
        $blocked.inApiAudienceGroup = $false
        $agent = Get-CbgAgentWithUsers -ConfiguredTier 'NativeApiDirect' -CreatedIn 'API' -Users @($blocked)

        $gap = Get-CbgFirstGap -Result (Invoke-CbgEngine -Agents @($agent))

        $gap.fsi_blockeduserscount | Should -Be 1
        $gap.fsi_blockedsampleupns | Should -Be '["solo-blocked@contoso.com"]'
        ($gap.fsi_blockedsampleupns | ConvertFrom-Json) | Should -Be 'solo-blocked@contoso.com'
    }

    It 'emits an empty JSON array literal when no users are blocked (M-2 zero-cardinality guard)' {
        # All users allowed -> fsi_blockedsampleupns must be the literal '[]' string,
        # never an empty or null value.
        $allowed = Get-CbgBaselineUser
        $allowed.upn = 'all-allowed@contoso.com'
        $allowed.inApiAudienceGroup = $true
        $agent = Get-CbgAgentWithUsers -ConfiguredTier 'NativeApiDirect' -CreatedIn 'API' -Users @($allowed)

        $gap = Get-CbgFirstGap -Result (Invoke-CbgEngine -Agents @($agent))

        $gap.fsi_eligibleusers | Should -Be 1
        $gap.fsi_blockeduserscount | Should -Be 0
        $gap.fsi_blockedsampleupns | Should -Be '[]'
    }
}
