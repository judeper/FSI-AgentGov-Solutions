#Requires -Version 7.2
#Requires -Modules @{ ModuleName = "Pester"; ModuleVersion = "5.0.0" }

<#
.SYNOPSIS
    Pester 5 tests for Get-FnfPeopleSweepReport.ps1 - the Find-No-Filter (FNF)
    People-Sweep lens/orchestrator that joins the CAI People-capability artifact,
    the CAI audience artifact, and the CBG entitlement resolver + engine into the
    deliverable per-agent FNF report.

.DESCRIPTION
    The lens does NOT re-implement the entitlement rule: per-user scoring is piped
    through Get-CopilotEntitlement.ps1 (the resolver) and Invoke-EntitlementEvaluation.ps1
    (the engine). Both the resolver and the lens are dot-sourced with placeholder
    arguments so their main bodies are guarded off and their functions load at script
    scope. The single HTTP seam (Invoke-CbgRestMethod) is mocked with a URI-dispatching
    body so Microsoft Graph licenseDetails / subscribedSkus responses can be crafted per
    test; the engine then runs for real over the resolver's materialized input (it does
    no network I/O). Tests call the testable core (Invoke-FnfPeopleSweep) and the pure
    units (Resolve-FnfPeopleAgentSet, ConvertTo-FnfResolverSkeleton, Get-FnfAgentCoverageStatus)
    directly, over the fixtures in fixtures/fnf/.

    One Describe per requirement:
      SEAM 1  - agent-id keying / provisional gate (+ id-map reconciliation).
      SEAM 2  - intendedUsers[].upn -> intendedUpns[] transform (regression: a non-empty
                UPN list MUST actually score; the bug that produced a silent 0-blocked run
                cannot regress) + createdIn join driving the engine pathway.
      SEAM 2c - whole-tenant: audienceMode=WholeTenant, coverageStatus=Partial,
                blockedUserCount=null (NEVER a silent 0).
      SEAM 5  - coverageStatus roll-up (Complete / Partial / Failed) over the ~7 gaps.
      Happy path - a People-capable Agent-Builder agent with an unlicensed user reports a
                blocked user and coverageStatus=Complete.
      Never-silent-zero invariant - across the full report.

.NOTES
    Run with: Invoke-Pester -Path .\FnfPeopleSweepReport.Tests.ps1 -Output Detailed
#>

param()

BeforeAll {
    $script:ResolverScript = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Get-CopilotEntitlement.ps1')).Path
    $script:EngineScript = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Invoke-EntitlementEvaluation.ps1')).Path
    $script:FnfScript = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Get-FnfPeopleSweepReport.ps1')).Path
    $script:FixturesDir = (Resolve-Path (Join-Path $PSScriptRoot 'fixtures' 'fnf')).Path

    # Dot-source the resolver (guarded main) so Invoke-CbgEntitlementResolution and the
    # mockable Invoke-CbgRestMethod seam load at script scope.
    . $script:ResolverScript -UserPrincipalName 'placeholder@contoso.com'
    # Dot-source the lens (guarded main) so its functions load into the same scope - the
    # functions are defined top-level and the main body runs only on direct invocation.
    . $script:FnfScript -CapabilityArtifactPath 'placeholder' -AudienceArtifactPath 'placeholder'

    # Locked-rule service-plan GUID (ALLOW) - mirrors the resolver / GATE0b constants.
    $script:PlanApps = 'a62f8878-de10-42f3-b68f-6149a25ceb97'  # M365_COPILOT_APPS (ALLOW)

    # Engine decision option-set integers.
    $script:DecisionAllow = 100000000
    $script:DecisionBlock = 100000001

    # A single shared working directory for intermediate engine files.
    $script:WorkDir = (Join-Path $TestDrive 'fnf-work')
    New-Item -ItemType Directory -Path $script:WorkDir -Force | Out-Null

    # Mock data, read lazily by the dispatching mock body. Reset per test in BeforeEach.
    $script:MockLdByUser = @{}
    $script:MockSkus = @()
    $script:MockGroupMembers = @{}
    $script:MockErrorUsers = @()

    # URI-dispatching body shared by every Invoke-CbgRestMethod mock (mirrors the resolver tests).
    $script:GraphMockBody = {
        if ($Uri -match '/subscribedSkus') {
            return [pscustomobject]@{ value = @($script:MockSkus) }
        }
        if ($Uri -match '/groups/([^/]+)/transitiveMembers') {
            $gid = $Matches[1]
            $members = @()
            if ($script:MockGroupMembers.ContainsKey($gid)) { $members = $script:MockGroupMembers[$gid] }
            return [pscustomobject]@{ value = @($members) }
        }
        if ($Uri -match '/users/([^/]+)/licenseDetails') {
            $u = [uri]::UnescapeDataString($Matches[1])
            if (@($script:MockErrorUsers) -contains $u) { throw "Simulated Graph 503 throttling for $u" }
            $ld = @()
            if ($script:MockLdByUser.ContainsKey($u)) { $ld = $script:MockLdByUser[$u] }
            return [pscustomobject]@{ value = @($ld) }
        }
        return [pscustomobject]@{ value = @() }
    }

    # Build one licenseDetails entry (a SKU with one service plan).
    function Get-CbgLicenseDetailFixture {
        param(
            [Parameter(Mandatory)][string]$SkuPartNumber,
            [Parameter(Mandatory)][string]$ServicePlanId,
            [string]$ServicePlanName = 'PLAN',
            [string]$ProvisioningStatus = 'Success',
            [string]$SkuId = ([guid]::NewGuid().Guid)
        )
        return [pscustomobject]@{
            skuId         = $SkuId
            skuPartNumber = $SkuPartNumber
            servicePlans  = @(
                [pscustomobject]@{
                    servicePlanId      = $ServicePlanId
                    servicePlanName    = $ServicePlanName
                    provisioningStatus = $ProvisioningStatus
                }
            )
        }
    }

    # Canonical license posture for the fixture UPN set: only licensed@ holds a Copilot plan;
    # unlicensed@, analyst@ and pilot@ have empty licenseDetails -> unlicensed -> BLOCK.
    function Initialize-FnfDefaultLicenses {
        $script:MockLdByUser = @{
            'licensed@contoso.com' = @(Get-CbgLicenseDetailFixture -SkuPartNumber 'Microsoft_365_Copilot' -ServicePlanId $script:PlanApps)
        }
        $script:MockSkus = @()
        $script:MockErrorUsers = @()
    }

    # Load (a fresh copy of) the canonical fixtures.
    function Get-FnfFixture {
        param([Parameter(Mandatory)][string]$Name)
        return Get-Content -LiteralPath (Join-Path $script:FixturesDir $Name) -Raw | ConvertFrom-Json
    }

    # Run the full sweep over the canonical fixtures (optionally with the id-map).
    function Invoke-FnfSweepFixture {
        param([switch]$WithIdMap)
        $capability = Get-FnfFixture -Name 'cai-people-capability.sample.json'
        $audience = Get-FnfFixture -Name 'cai-audience.sample.json'
        $agentMaster = Get-FnfFixture -Name 'agent-master.sample.json'
        $idMap = if ($WithIdMap) { Get-FnfFixture -Name 'agent-id-map.sample.json' } else { $null }
        return Invoke-FnfPeopleSweep -CapabilityArtifact $capability -AudienceArtifact $audience `
            -AgentMaster $agentMaster -IdMap $idMap -Policy @() -GraphToken 'tok' -Capability 'CopilotChat' `
            -EngineScript $script:EngineScript -WorkingDir $script:WorkDir
    }

    function Get-FnfRow {
        param([Parameter(Mandatory)][psobject]$Report, [Parameter(Mandatory)][string]$AgentId)
        # StrictMode-safe: indexing an empty array with [0] throws under Set-StrictMode -Version
        # Latest (inherited from the dot-sourced scripts), so guard the not-found case.
        $matched = @($Report.agents | Where-Object { $_.agentId -eq $AgentId })
        if ($matched.Count -eq 0) { return $null }
        return $matched[0]
    }

    # Stable agent ids used across the fixtures.
    $script:AgentGrouped = '11110000-0000-0000-0000-000000000001'  # Org Directory Helper (mcp-agentbuilder, Complete)
    $script:AgentWholeTenant = '11110000-0000-0000-0000-000000000002'  # Company Concierge (whole-tenant)
    $script:AgentPartial = '11110000-0000-0000-0000-000000000003'  # Loan Ops People Finder (mcp-cs, Partial audience)
    $script:AgentReconciled = '11110000-0000-0000-0000-000000000004'  # Pilot People Bot (reconciled from declarativeAgent)
    $script:AgentFailed = '11110000-0000-0000-0000-000000000006'  # Branch Lookup Bot (Failed audience)
    $script:AgentMissing = '11110000-0000-0000-0000-000000000007'  # Mentor Match Bot (absent from audience artifact)
    $script:AgentDisabled = '11110000-0000-0000-0000-000000000005'  # Knowledge Base Bot (disabled People feature)
    $script:ProvisionalStem = 'declarativeAgent'
}

Describe 'Invoke-FnfPeopleSweep - SEAM 1 (agent-id keying / provisional gate)' {

    BeforeEach {
        Initialize-FnfDefaultLicenses
        Mock Invoke-CbgRestMethod $script:GraphMockBody
    }

    It 'surfaces an unreconciled provisional People agent as Partial (manifest-id-unreconciled), never joined, never dropped' {
        $report = Invoke-FnfSweepFixture

        $row = Get-FnfRow -Report $report -AgentId $script:ProvisionalStem
        $row | Should -Not -BeNullOrEmpty -Because 'the provisional row must be present (never silently dropped)'
        $row.peopleCapable | Should -BeTrue
        $row.coverageStatus | Should -Be 'Partial'
        $row.coverageGaps | Should -Contain 'manifest-id-unreconciled'
        $row.audienceMode | Should -Be 'None'
        # An unreconciled provisional id cannot be joined to a real audience -> count is null, NOT 0.
        $row.blockedUserCount | Should -BeNullOrEmpty
        # It must NOT have been silently joined to the real bot GUID it maps to.
        (Get-FnfRow -Report $report -AgentId $script:AgentReconciled) | Should -BeNullOrEmpty
        $report.summary.provisionalUnreconciled | Should -Be 1
    }

    It 'reconciles a provisional id via the id-map and scores it like a real agent' {
        $report = Invoke-FnfSweepFixture -WithIdMap

        # The provisional stem must no longer appear as its own row.
        (Get-FnfRow -Report $report -AgentId $script:ProvisionalStem) | Should -BeNullOrEmpty
        $report.summary.provisionalUnreconciled | Should -Be 0

        # It is now keyed by the real bot GUID and scored (pilot@ is unlicensed -> blocked).
        $row = Get-FnfRow -Report $report -AgentId $script:AgentReconciled
        $row | Should -Not -BeNullOrEmpty
        $row.coverageStatus | Should -Be 'Complete'
        $row.coverageGaps | Should -BeNullOrEmpty
        $row.blockedUserCount | Should -Be 1
        $row.blockedUsers | Should -Contain 'pilot@contoso.com'
    }

    It 'excludes a disabled People feature and a non-People feature (Resolve-FnfPeopleAgentSet)' {
        $capability = Get-FnfFixture -Name 'cai-people-capability.sample.json'

        $setNoMap = Resolve-FnfPeopleAgentSet -CapabilityArtifact $capability
        $resolvedIds = @($setNoMap.Resolved | ForEach-Object { $_.agentId })
        $provisionalIds = @($setNoMap.ProvisionalUnreconciled | ForEach-Object { $_.agentId })

        # Disabled People feature is not effective; File Upload is not People -> neither selected.
        $resolvedIds | Should -Not -Contain $script:AgentDisabled
        # Non-provisional People agents are resolved.
        $resolvedIds | Should -Contain $script:AgentGrouped
        $resolvedIds | Should -Contain $script:AgentPartial
        # Provisional row is held back (not joined) when there is no id-map.
        $resolvedIds | Should -Not -Contain $script:ProvisionalStem
        $provisionalIds | Should -Contain $script:ProvisionalStem

        # With the id-map the provisional stem reconciles to the real bot GUID.
        $idMap = ConvertTo-FnfIdMap -InputObject (Get-FnfFixture -Name 'agent-id-map.sample.json')
        $setMapped = Resolve-FnfPeopleAgentSet -CapabilityArtifact $capability -IdMap $idMap
        @($setMapped.Resolved | ForEach-Object { $_.agentId }) | Should -Contain $script:AgentReconciled
        @($setMapped.ProvisionalUnreconciled).Count | Should -Be 0
    }
}

Describe 'Invoke-FnfPeopleSweep - SEAM 2 (intendedUsers->intendedUpns transform regression)' {

    BeforeEach {
        Initialize-FnfDefaultLicenses
        Mock Invoke-CbgRestMethod $script:GraphMockBody
    }

    It 'feeds a NON-EMPTY UPN list to the engine so a blocked user is actually scored (NOT a silent 0)' {
        $report = Invoke-FnfSweepFixture

        $row = Get-FnfRow -Report $report -AgentId $script:AgentGrouped
        $row | Should -Not -BeNullOrEmpty
        # Both intendedUsers were transformed to intendedUpns and scored by the engine.
        $row.evidence.decisionCount | Should -Be 2 -Because 'intendedUsers[].upn must become a 2-element intendedUpns[] the engine scores'
        # The unlicensed user is reported blocked; the count is 1 - and crucially NOT 0.
        $row.blockedUserCount | Should -Be 1
        $row.blockedUserCount | Should -Not -Be 0
        $row.blockedUsers | Should -Contain 'unlicensed@contoso.com'
        $row.blockedUsers | Should -Not -Contain 'licensed@contoso.com'
    }

    It 'joins createdIn so the engine classifies the pathway (Agent Builder -> license required -> BLOCK)' {
        $report = Invoke-FnfSweepFixture

        $row = Get-FnfRow -Report $report -AgentId $script:AgentGrouped
        $row.evidence.createdIn | Should -Be 'Microsoft 365 Copilot Agent Builder'
        # mcp-agentbuilder is a mapped pathway -> no fail-open anomaly under-reporting.
        $row.evidence.failOpenAnomalyCount | Should -Be 0
    }

    It 'ConvertTo-FnfResolverSkeleton normalizes intendedUsers[].upn (objects) to a flat string[] intendedUpns' {
        $capability = Get-FnfFixture -Name 'cai-people-capability.sample.json'
        $audience = Get-FnfFixture -Name 'cai-audience.sample.json'
        $masterMap = ConvertTo-FnfAgentMasterMap -InputObject (Get-FnfFixture -Name 'agent-master.sample.json')
        $people = Resolve-FnfPeopleAgentSet -CapabilityArtifact $capability

        $skel = ConvertTo-FnfResolverSkeleton -AudienceArtifact $audience -PeopleAgents $people.Resolved -AgentMaster $masterMap

        $grouped = @($skel.Skeleton.agents | Where-Object { $_.agentId -eq $script:AgentGrouped })[0]
        $grouped | Should -Not -BeNullOrEmpty
        # intendedUpns must be plain strings (not objects carrying a .upn property).
        $grouped.intendedUpns | Should -Be @('licensed@contoso.com', 'unlicensed@contoso.com')
        foreach ($u in $grouped.intendedUpns) { $u | Should -BeOfType [string] }
        $grouped.createdIn | Should -Be 'Microsoft 365 Copilot Agent Builder'
        # Whole-tenant / Failed / missing agents are routed away from the scored skeleton.
        @($skel.Skeleton.agents | ForEach-Object { $_.agentId }) | Should -Not -Contain $script:AgentWholeTenant
        @($skel.WholeTenantAgents | ForEach-Object { $_.agentId }) | Should -Contain $script:AgentWholeTenant
        @($skel.FailedAudienceAgents | ForEach-Object { $_.agentId }) | Should -Contain $script:AgentFailed
        @($skel.MissingAudienceAgents | ForEach-Object { $_.agentId }) | Should -Contain $script:AgentMissing
    }
}

Describe 'Invoke-FnfPeopleSweep - SEAM 2c (whole-tenant)' {

    BeforeEach {
        Initialize-FnfDefaultLicenses
        Mock Invoke-CbgRestMethod $script:GraphMockBody
    }

    It 'does NOT emit 0 blocked for an org-wide agent; emits WholeTenant / Partial / null' {
        $report = Invoke-FnfSweepFixture

        $row = Get-FnfRow -Report $report -AgentId $script:AgentWholeTenant
        $row | Should -Not -BeNullOrEmpty
        $row.peopleCapable | Should -BeTrue
        $row.audienceMode | Should -Be 'WholeTenant'
        $row.coverageStatus | Should -Be 'Partial'
        $row.coverageGaps | Should -Contain 'audience-wholetenant-not-enumerated'
        # The highest-risk case must never read as a resolved 0 - blockedUserCount is null.
        $row.blockedUserCount | Should -BeNullOrEmpty
        $row.blockedUserCount | Should -Not -Be 0
        $row.evidence.blockedUsersComputed | Should -BeFalse
        $report.summary.wholeTenantAgentCount | Should -Be 1
    }
}

Describe 'Get-FnfAgentCoverageStatus - SEAM 5 coverage roll-up' {

    It 'returns Complete with no gaps for a fully resolved group-scoped agent' {
        $c = Get-FnfAgentCoverageStatus -AudienceStatus 'Complete'
        $c.coverageStatus | Should -Be 'Complete'
        @($c.coverageGaps).Count | Should -Be 0
    }

    It 'rolls up each non-fatal gap to Partial with the matching reason' -ForEach @(
        @{ Splat = @{ AudienceStatus = 'Partial' }; Gap = 'audience-resolution-partial' }
        @{ Splat = @{ Truncated = $true }; Gap = 'audience-truncated' }
        @{ Splat = @{ ResolutionErrorCount = 2 }; Gap = 'audience-resolution-errors' }
        @{ Splat = @{ WholeTenant = $true }; Gap = 'audience-wholetenant-not-enumerated' }
        @{ Splat = @{ UnresolvedUserCount = 1 }; Gap = 'entitlement-unresolved-users' }
        @{ Splat = @{ NeedsManualReviewCount = 1 }; Gap = 'payg-policy-needs-manual-review' }
        @{ Splat = @{ PaygAllUsersCovered = $true }; Gap = 'payg-all-users-coverage' }
        @{ Splat = @{ FailOpenCount = 1 }; Gap = 'pathway-unmapped-fail-open' }
        @{ Splat = @{ Provisional = $true }; Gap = 'manifest-id-unreconciled' }
        @{ Splat = @{ AttestationPending = $true }; Gap = 'manifest-opaque-attestation-pending' }
        @{ Splat = @{ CreatedInMissing = $true }; Gap = 'createdin-missing-pathway-fallback' }
    ) {
        $c = Get-FnfAgentCoverageStatus @Splat
        $c.coverageStatus | Should -Be 'Partial'
        $c.coverageGaps | Should -Contain $Gap
    }

    It 'returns Failed when the audience cannot be resolved at all' -ForEach @(
        @{ Splat = @{ AudienceStatus = 'Failed' }; Gap = 'audience-resolution-failed' }
        @{ Splat = @{ AudienceStatus = 'NotResolved' }; Gap = 'audience-resolution-failed' }
        @{ Splat = @{ AudienceMissing = $true }; Gap = 'audience-not-resolved' }
    ) {
        $c = Get-FnfAgentCoverageStatus @Splat
        $c.coverageStatus | Should -Be 'Failed'
        $c.coverageGaps | Should -Contain $Gap
    }

    It 'a fail-open (unmapped pathway) does not silently pass as Complete' {
        # The engine counts an unmapped pathway as FAIL-OPEN (not blocked); the roll-up must
        # still surface it so the agent is not read as fully entitled.
        $c = Get-FnfAgentCoverageStatus -AudienceStatus 'Complete' -FailOpenCount 3
        $c.coverageStatus | Should -Be 'Partial'
        $c.coverageGaps | Should -Contain 'pathway-unmapped-fail-open'
    }
}

Describe 'Invoke-FnfPeopleSweep - SEAM 5 propagation (integration)' {

    BeforeEach {
        Initialize-FnfDefaultLicenses
        Mock Invoke-CbgRestMethod $script:GraphMockBody
    }

    It 'a Partial audience still scores the resolved subset and is flagged Partial (not dropped, not 0-clean)' {
        $report = Invoke-FnfSweepFixture

        $row = Get-FnfRow -Report $report -AgentId $script:AgentPartial
        $row | Should -Not -BeNullOrEmpty
        $row.coverageStatus | Should -Be 'Partial'
        $row.coverageGaps | Should -Contain 'audience-resolution-partial'
        $row.coverageGaps | Should -Contain 'audience-truncated'
        $row.coverageGaps | Should -Contain 'audience-resolution-errors'
        # analyst@ (unlicensed, mcp-cs pathway) is scored and blocked.
        $row.blockedUserCount | Should -Be 1
        $row.blockedUsers | Should -Contain 'analyst@contoso.com'
    }

    It 'a Failed audience reports coverageStatus=Failed with blockedUserCount=null (NOT a silent 0)' {
        $report = Invoke-FnfSweepFixture

        $row = Get-FnfRow -Report $report -AgentId $script:AgentFailed
        $row | Should -Not -BeNullOrEmpty
        $row.coverageStatus | Should -Be 'Failed'
        $row.coverageGaps | Should -Contain 'audience-resolution-failed'
        $row.audienceMode | Should -Be 'None'
        $row.blockedUserCount | Should -BeNullOrEmpty
        $row.blockedUserCount | Should -Not -Be 0
    }

    It 'a People-capable agent missing from the audience artifact is surfaced as Failed (audience-not-resolved)' {
        $report = Invoke-FnfSweepFixture

        $row = Get-FnfRow -Report $report -AgentId $script:AgentMissing
        $row | Should -Not -BeNullOrEmpty
        $row.coverageStatus | Should -Be 'Failed'
        $row.coverageGaps | Should -Contain 'audience-not-resolved'
        $row.blockedUserCount | Should -BeNullOrEmpty
    }
}

Describe 'Invoke-FnfPeopleSweep - happy path + never-silent-zero invariant' {

    BeforeEach {
        Initialize-FnfDefaultLicenses
        Mock Invoke-CbgRestMethod $script:GraphMockBody
    }

    It 'reports a People-capable Agent-Builder agent with an unlicensed user as a blocked user, coverageStatus=Complete' {
        $report = Invoke-FnfSweepFixture

        $row = Get-FnfRow -Report $report -AgentId $script:AgentGrouped
        $row.peopleCapable | Should -BeTrue
        $row.peopleCapableSource | Should -Be 'manifest'
        $row.audienceMode | Should -Be 'GroupScoped'
        $row.coverageStatus | Should -Be 'Complete'
        @($row.coverageGaps).Count | Should -Be 0
        $row.blockedUserCount | Should -Be 1
        $row.blockedUsers | Should -Be @('unlicensed@contoso.com')
        $row.totalAudience | Should -Be 2
    }

    It 'produces the expected report-level roll-up (with id-map)' {
        $report = Invoke-FnfSweepFixture -WithIdMap

        $report.reportType | Should -Be 'FnfPeopleSweep'
        $report.gatedCapability | Should -Be 'CopilotChat'
        # 6 People-capable agents surface: grouped, whole-tenant, partial, reconciled, failed, missing.
        $report.summary.peopleCapableAgentCount | Should -Be 6
        $report.summary.scoredAgentCount | Should -Be 3
        $report.summary.wholeTenantAgentCount | Should -Be 1
        $report.summary.failedAudienceCount | Should -Be 1
        $report.summary.missingAudienceCount | Should -Be 1
        # grouped(1) + partial(1) + reconciled(1) blocked users across 3 agents.
        $report.summary.totalBlockedUserCount | Should -Be 3
        $report.summary.agentsWithBlockedUsers | Should -Be 3
        $report.summary.coverageFailedCount | Should -Be 2
    }

    It 'never reports a silent 0: every non-Complete-audience row has blockedUserCount=null, and scoring did occur' {
        $report = Invoke-FnfSweepFixture -WithIdMap

        # Whole-tenant, Failed and missing-audience rows must carry null (uncomputed), never 0.
        foreach ($row in @($report.agents | Where-Object { $_.audienceMode -ne 'GroupScoped' })) {
            $row.blockedUserCount | Should -BeNullOrEmpty -Because "agent $($row.agentId) ($($row.audienceMode)) must not read as a resolved 0"
        }
        # At least one agent was actually scored to a positive blocked count (transform works).
        @($report.agents | Where-Object { $null -ne $_.blockedUserCount -and $_.blockedUserCount -gt 0 }).Count | Should -BeGreaterThan 0
        # The global headline is not "0 blocked".
        $report.summary.totalBlockedUserCount | Should -BeGreaterThan 0
    }
}
