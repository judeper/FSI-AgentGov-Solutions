#Requires -Version 7.2
#Requires -Modules @{ ModuleName = "Pester"; ModuleVersion = "5.0.0" }

<#
.SYNOPSIS
    Pester 5 tests for Get-CopilotEntitlement.ps1 - the per-user entitlement
    resolver that produces the booleans the switch-on-pathway entitlement engine
    consumes, and for the PAYG scope / connected-capability surfacing added to
    Get-BillingPolicyInventory.ps1.

.DESCRIPTION
    The resolver is dot-sourced with a placeholder UPN so its main body is guarded
    off (the script defines its functions at top level and runs main only on direct
    invocation). The single HTTP seam (Invoke-CbgRestMethod) is mocked with a
    URI-dispatching body so Microsoft Graph (licenseDetails / subscribedSkus /
    transitiveMembers) and the Power Platform billing-policy responses can be
    crafted per test. Tests then call Invoke-CbgEntitlementResolution directly.

    Coverage maps to the LOCKED rule in docs/GATE0b and the build brief:
      - paid M365 Copilot service plan (provisioningStatus=Success) -> licensed.
      - Bing_Chat_Enterprise DENY trap: an E5 user with only BCE is NOT licensed.
      - a paid plan not in Success state does NOT confer entitlement.
      - a transitive (group-based) Copilot license is honoured (licenseDetails
        already includes group-assigned plans).
      - unlicensed + no applicable PAYG -> BLOCKED; an All Users PAYG policy
        collapses the blocked set to zero; coverage is per-capability.
      - undocumented SKUs carrying a Copilot plan are licensed-by-construction.
      - a Graph read error fails OPEN: the user is recorded unresolved (NOT blocked)
        and excluded from the engine input.
      - the assembled engine input is consumed by Invoke-EntitlementEvaluation.ps1.

.NOTES
    Run with: Invoke-Pester -Path .\CopilotEntitlement.Tests.ps1 -Output Detailed
#>

param()

BeforeAll {
    $script:ResolverScript = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Get-CopilotEntitlement.ps1')).Path
    $script:EngineScript = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Invoke-EntitlementEvaluation.ps1')).Path

    # Dot-source with a placeholder argument: the main body is guarded off, the
    # functions (including Invoke-CbgEntitlementResolution and the Invoke-CbgRestMethod
    # seam) load at script scope for direct call + mocking.
    . $script:ResolverScript -UserPrincipalName 'placeholder@contoso.com'

    # Locked-rule service-plan GUIDs (mirror GATE0b / the resolver constants).
    $script:PlanApps = 'a62f8878-de10-42f3-b68f-6149a25ceb97'  # M365_COPILOT_APPS (ALLOW)
    $script:PlanChat = '3f30311c-6b1e-48a4-ab79-725b469da960'  # M365_COPILOT_BUSINESS_CHAT (ALLOW)
    $script:PlanSpo = '0aedf20c-091d-420b-aadf-30c042609612'  # M365_COPILOT_SHAREPOINT (ALLOW)
    $script:PlanBce = '0d0c0d31-fae7-41f2-b909-eaf4d7f26dba'  # Bing_Chat_Enterprise (DENY)
    $script:KnownCopilotSkuId = '639dec6b-bb19-468b-871c-c5c441c4b0cb'  # Microsoft_365_Copilot (documented)

    # Engine option-set integers (mirror docs/entitlement-contract.md / engine maps).
    $script:DecisionAllow = 100000000
    $script:DecisionBlock = 100000001

    # Mock data, read lazily by the dispatching mock body. Each test resets these.
    $script:MockLdByUser = @{}
    $script:MockSkus = @()
    $script:MockGroupMembers = @{}
    $script:MockErrorUsers = @()

    # URI-dispatching body shared by every Invoke-CbgRestMethod mock.
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
            if (@($script:MockErrorUsers) -contains $u) { throw "Simulated Graph 503 throttling/again for $u" }
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

    # Return the resolved per-user object for a given UPN out of a result.
    function Get-CbgResolvedUser {
        param([Parameter(Mandatory)][psobject]$Result, [Parameter(Mandatory)][string]$Upn)
        return @($Result.users | Where-Object { $_.upn -eq $Upn })[0]
    }
}

Describe 'Get-CopilotEntitlement - license detection (locked GUID rule)' {

    It 'classifies a user with a paid M365 Copilot service plan (Success) as licensed' {
        $script:MockLdByUser = @{ 'licensed@contoso.com' = @(Get-CbgLicenseDetailFixture -SkuPartNumber 'Microsoft_365_Copilot' -ServicePlanId $script:PlanApps) }
        $script:MockSkus = @()
        $script:MockErrorUsers = @()
        Mock Invoke-CbgRestMethod $script:GraphMockBody

        $r = Invoke-CbgEntitlementResolution -Upn @('licensed@contoso.com') -Policy @() -GraphToken 'tok' -Capability 'CopilotChat'
        $u = Get-CbgResolvedUser -Result $r -Upn 'licensed@contoso.com'

        $u.hasCopilotLicense | Should -BeTrue
        $u.isBlocked | Should -BeFalse
        $u.matchedPlanIds | Should -Contain $script:PlanApps
    }

    It 'does NOT count Bing_Chat_Enterprise as entitlement (E5 DENY trap)' {
        # An E5 user whose only Copilot-looking plan is Bing_Chat_Enterprise.
        $script:MockLdByUser = @{ 'e5@contoso.com' = @(Get-CbgLicenseDetailFixture -SkuPartNumber 'ENTERPRISEPREMIUM' -ServicePlanId $script:PlanBce) }
        $script:MockSkus = @()
        $script:MockErrorUsers = @()
        Mock Invoke-CbgRestMethod $script:GraphMockBody

        $r = Invoke-CbgEntitlementResolution -Upn @('e5@contoso.com') -Policy @() -GraphToken 'tok' -Capability 'CopilotChat'
        $u = Get-CbgResolvedUser -Result $r -Upn 'e5@contoso.com'

        $u.hasCopilotLicense | Should -BeFalse
        $u.deniedPlanIdsObserved | Should -Contain $script:PlanBce
        # No license and (here) no PAYG -> blocked from the gated capability.
        $u.isBlocked | Should -BeTrue
    }

    It 'does NOT count a paid Copilot plan that is not provisioningStatus=Success' {
        $script:MockLdByUser = @{ 'pending@contoso.com' = @(Get-CbgLicenseDetailFixture -SkuPartNumber 'Microsoft_365_Copilot' -ServicePlanId $script:PlanApps -ProvisioningStatus 'PendingProvisioning') }
        $script:MockSkus = @()
        $script:MockErrorUsers = @()
        Mock Invoke-CbgRestMethod $script:GraphMockBody

        $r = Invoke-CbgEntitlementResolution -Upn @('pending@contoso.com') -Policy @() -GraphToken 'tok' -Capability 'CopilotChat'
        (Get-CbgResolvedUser -Result $r -Upn 'pending@contoso.com').hasCopilotLicense | Should -BeFalse
    }

    It 'honours a transitive group-based Copilot license (licenseDetails includes it)' {
        # GET /users/{id}/licenseDetails already includes group-assigned plans, so a
        # user licensed only via a group appears exactly like a directly-licensed user.
        $script:MockLdByUser = @{ 'grouplic@contoso.com' = @(Get-CbgLicenseDetailFixture -SkuPartNumber 'Microsoft_365_Copilot' -ServicePlanId $script:PlanChat) }
        $script:MockSkus = @()
        $script:MockErrorUsers = @()
        Mock Invoke-CbgRestMethod $script:GraphMockBody

        $r = Invoke-CbgEntitlementResolution -Upn @('grouplic@contoso.com') -Policy @() -GraphToken 'tok' -Capability 'CopilotChat'
        $u = Get-CbgResolvedUser -Result $r -Upn 'grouplic@contoso.com'

        $u.hasCopilotLicense | Should -BeTrue
        $u.isBlocked | Should -BeFalse
    }

    It 'treats a user with no licenses as unlicensed (a valid result, not an error)' {
        $script:MockLdByUser = @{}                 # no entry -> empty licenseDetails
        $script:MockSkus = @()
        $script:MockErrorUsers = @()
        Mock Invoke-CbgRestMethod $script:GraphMockBody

        $r = Invoke-CbgEntitlementResolution -Upn @('nolic@contoso.com') -Policy @() -GraphToken 'tok' -Capability 'CopilotChat'

        $r.summary.unresolvedCount | Should -Be 0
        (Get-CbgResolvedUser -Result $r -Upn 'nolic@contoso.com').hasCopilotLicense | Should -BeFalse
    }
}

Describe 'Get-CopilotEntitlement - PAYG / credit coverage join' {

    It 'blocks an unlicensed user with no PAYG coverage' {
        $script:MockLdByUser = @{}
        $script:MockSkus = @()
        $script:MockErrorUsers = @()
        Mock Invoke-CbgRestMethod $script:GraphMockBody

        $r = Invoke-CbgEntitlementResolution -Upn @('blocked@contoso.com') -Policy @() -GraphToken 'tok' -Capability 'CopilotChat'
        $u = Get-CbgResolvedUser -Result $r -Upn 'blocked@contoso.com'

        $u.isBlocked | Should -BeTrue
        $u.blockReason | Should -Be 'NoLicenseAndNoPaygCoverage'
        $r.summary.blockedCount | Should -Be 1
    }

    It 'collapses the blocked set to zero when a PAYG policy is scoped to All Users' {
        $script:MockLdByUser = @{}     # everyone unlicensed
        $script:MockSkus = @()
        $script:MockErrorUsers = @()
        Mock Invoke-CbgRestMethod $script:GraphMockBody

        $allUsersPolicy = [pscustomobject]@{ name = 'All-up Chat'; scope = 'AllUsers'; capabilities = @('Chat'); connected = $true }
        $r = Invoke-CbgEntitlementResolution -Upn @('a@contoso.com', 'b@contoso.com') -Policy @($allUsersPolicy) -GraphToken 'tok' -Capability 'CopilotChat'

        $r.paygCoverage.allUsersCovered | Should -BeTrue
        $r.summary.blockedCount | Should -Be 0
        # Coverage maps to the engine credit-scope gate.
        (Get-CbgResolvedUser -Result $r -Upn 'a@contoso.com').inCreditScopeGroup | Should -BeTrue
    }

    It 'covers only the transitive members of a group-scoped PAYG policy' {
        $script:MockLdByUser = @{}     # both unlicensed
        $script:MockSkus = @()
        $script:MockErrorUsers = @()
        $script:MockGroupMembers = @{ 'grp-001' = @([pscustomobject]@{ id = '1'; userPrincipalName = 'covered@contoso.com' }) }
        Mock Invoke-CbgRestMethod $script:GraphMockBody

        $groupPolicy = [pscustomobject]@{ name = 'Pilot'; scope = 'Group'; groupIds = @('grp-001'); capabilities = @('Chat'); connected = $true }
        $r = Invoke-CbgEntitlementResolution -Upn @('covered@contoso.com', 'uncovered@contoso.com') -Policy @($groupPolicy) -GraphToken 'tok' -Capability 'CopilotChat'

        (Get-CbgResolvedUser -Result $r -Upn 'covered@contoso.com').isBlocked | Should -BeFalse
        (Get-CbgResolvedUser -Result $r -Upn 'uncovered@contoso.com').isBlocked | Should -BeTrue
    }

    It 'treats PAYG coverage per-capability (a SharePoint policy does not cover Chat)' {
        $script:MockLdByUser = @{}
        $script:MockSkus = @()
        $script:MockErrorUsers = @()
        Mock Invoke-CbgRestMethod $script:GraphMockBody

        $spoPolicy = [pscustomobject]@{ name = 'SPO only'; scope = 'AllUsers'; capabilities = @('SharePoint'); connected = $true }
        $r = Invoke-CbgEntitlementResolution -Upn @('chatuser@contoso.com') -Policy @($spoPolicy) -GraphToken 'tok' -Capability 'CopilotChat'

        $r.paygCoverage.allUsersCovered | Should -BeFalse
        (Get-CbgResolvedUser -Result $r -Upn 'chatuser@contoso.com').isBlocked | Should -BeTrue
    }

    It 'does not count a disconnected PAYG policy as coverage' {
        $script:MockLdByUser = @{}
        $script:MockSkus = @()
        $script:MockErrorUsers = @()
        Mock Invoke-CbgRestMethod $script:GraphMockBody

        $disconnected = [pscustomobject]@{ name = 'Not connected'; scope = 'AllUsers'; capabilities = @('Chat'); connected = $false }
        $r = Invoke-CbgEntitlementResolution -Upn @('u@contoso.com') -Policy @($disconnected) -GraphToken 'tok' -Capability 'CopilotChat'

        $r.paygCoverage.allUsersCovered | Should -BeFalse
        (Get-CbgResolvedUser -Result $r -Upn 'u@contoso.com').isBlocked | Should -BeTrue
    }
}

Describe 'Get-CopilotEntitlement - tenant SKU dictionary (undocumented SKUs)' {

    It 'marks an undocumented SKU bearing a Copilot plan as licensed-by-construction' {
        $script:MockLdByUser = @{}
        $script:MockErrorUsers = @()
        # An undocumented local SKU (e.g. "Microsoft 365 E7") that carries an
        # allowlisted Copilot plan, plus a documented Copilot SKU for contrast.
        $script:MockSkus = @(
            [pscustomobject]@{ skuId = '99999999-9999-9999-9999-999999999999'; skuPartNumber = 'CONTOSO_E7'; servicePlans = @([pscustomobject]@{ servicePlanId = $script:PlanApps; servicePlanName = 'M365_COPILOT_APPS' }) },
            [pscustomobject]@{ skuId = $script:KnownCopilotSkuId; skuPartNumber = 'Microsoft_365_Copilot'; servicePlans = @([pscustomobject]@{ servicePlanId = $script:PlanChat; servicePlanName = 'M365_COPILOT_BUSINESS_CHAT' }) }
        )
        Mock Invoke-CbgRestMethod $script:GraphMockBody

        $r = Invoke-CbgEntitlementResolution -Upn @('x@contoso.com') -Policy @() -GraphToken 'tok' -Capability 'CopilotChat'

        $e7 = @($r.copilotBearingSkus | Where-Object { $_.skuPartNumber -eq 'CONTOSO_E7' })[0]
        $known = @($r.copilotBearingSkus | Where-Object { $_.skuPartNumber -eq 'Microsoft_365_Copilot' })[0]

        $e7 | Should -Not -BeNullOrEmpty
        $e7.licensedByConstruction | Should -BeTrue
        $known.licensedByConstruction | Should -BeFalse
        $known.documentedSkuLabel | Should -Be 'Microsoft_365_Copilot'
    }
}

Describe 'Get-CopilotEntitlement - error handling (fail-open, accuracy-first)' {

    It 'records a Graph read error as unresolved and does NOT mark the user blocked' {
        $script:MockLdByUser = @{ 'ok@contoso.com' = @(Get-CbgLicenseDetailFixture -SkuPartNumber 'Microsoft_365_Copilot' -ServicePlanId $script:PlanApps) }
        $script:MockSkus = @()
        $script:MockErrorUsers = @('boom@contoso.com')
        Mock Invoke-CbgRestMethod $script:GraphMockBody

        $r = Invoke-CbgEntitlementResolution -Upn @('ok@contoso.com', 'boom@contoso.com') -Policy @() -GraphToken 'tok' -Capability 'CopilotChat'

        $r.summary.unresolvedCount | Should -Be 1
        @($r.unresolved | Where-Object { $_.upn -eq 'boom@contoso.com' })[0].status | Should -Be 'error'
        # The errored user must NOT appear in the resolved users (and so is never "blocked").
        @($r.users | Where-Object { $_.upn -eq 'boom@contoso.com' }).Count | Should -Be 0
        $r.summary.blockedCount | Should -Be 0
    }

    It 'excludes unresolved users from the assembled engine input' {
        $script:MockLdByUser = @{ 'ok@contoso.com' = @(Get-CbgLicenseDetailFixture -SkuPartNumber 'Microsoft_365_Copilot' -ServicePlanId $script:PlanApps) }
        $script:MockSkus = @()
        $script:MockErrorUsers = @('boom@contoso.com')
        Mock Invoke-CbgRestMethod $script:GraphMockBody

        $agents = @([pscustomobject]@{ agentId = 'a1'; agentName = 'A1'; createdIn = 'CopilotStudio'; configuredTier = 'NativeMcpCopilotStudio'; spendScope = 'Chat'; sourcePolicyId = 'p1'; intendedUpns = @('ok@contoso.com', 'boom@contoso.com') })
        $r = Invoke-CbgEntitlementResolution -Upn @('ok@contoso.com', 'boom@contoso.com') -AgentsSkeleton $agents -Policy @() -GraphToken 'tok' -Capability 'CopilotChat'

        $intended = @($r.engineInput.agents[0].intendedUsers)
        $intended.Count | Should -Be 1
        $intended[0].upn | Should -Be 'ok@contoso.com'
    }
}

Describe 'Get-CopilotEntitlement - cohort group memberships' {

    It 'sets inApiAudienceGroup and inEligibleCohort from transitive group membership' {
        $script:MockLdByUser = @{}
        $script:MockSkus = @()
        $script:MockErrorUsers = @()
        $script:MockGroupMembers = @{
            'api-grp'    = @([pscustomobject]@{ id = '1'; userPrincipalName = 'member@contoso.com' })
            'cohort-grp' = @([pscustomobject]@{ id = '1'; userPrincipalName = 'member@contoso.com' })
        }
        Mock Invoke-CbgRestMethod $script:GraphMockBody

        $r = Invoke-CbgEntitlementResolution -Upn @('member@contoso.com', 'other@contoso.com') -Policy @() -GraphToken 'tok' -Capability 'CopilotChat' -ApiAudienceGroupId 'api-grp' -EligibleCohortGroupId 'cohort-grp'

        $m = Get-CbgResolvedUser -Result $r -Upn 'member@contoso.com'
        $o = Get-CbgResolvedUser -Result $r -Upn 'other@contoso.com'
        $m.inApiAudienceGroup | Should -BeTrue
        $m.inEligibleCohort | Should -BeTrue
        $o.inApiAudienceGroup | Should -BeFalse
        $o.inEligibleCohort | Should -BeFalse
    }
}

Describe 'Get-CopilotEntitlement - engine integration' {

    It 'produces engine input that Invoke-EntitlementEvaluation.ps1 consumes (licensed -> Allow, unlicensed -> Block on mcp-cs)' {
        $script:MockLdByUser = @{ 'licensed@contoso.com' = @(Get-CbgLicenseDetailFixture -SkuPartNumber 'Microsoft_365_Copilot' -ServicePlanId $script:PlanApps) }
        $script:MockSkus = @()
        $script:MockErrorUsers = @()
        Mock Invoke-CbgRestMethod $script:GraphMockBody

        $agents = @(
            [pscustomobject]@{
                agentId        = 'agent-int-1'
                agentName      = 'Integration Agent'
                createdIn      = 'CopilotStudio'
                configuredTier = 'NativeMcpCopilotStudio'   # -> mcp-cs pathway
                spendScope     = 'Chat'
                sourcePolicyId = 'policy-1'
                intendedUpns   = @('licensed@contoso.com', 'unlicensed@contoso.com')
            }
        )
        $r = Invoke-CbgEntitlementResolution -Upn @('licensed@contoso.com', 'unlicensed@contoso.com') -AgentsSkeleton $agents -Policy @() -GraphToken 'tok' -Capability 'CopilotChat'

        $inputFile = Join-Path $TestDrive 'engine-input.json'
        $outputFile = Join-Path $TestDrive 'engine-output.json'
        $r.engineInput | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $inputFile -Encoding UTF8

        & $script:EngineScript -InputPath $inputFile -OutputPath $outputFile | Out-Null
        $engineResult = Get-Content -LiteralPath $outputFile -Raw | ConvertFrom-Json

        # The engine emits fsi_cbgentitlementmaterialized-shaped records: the UPN is
        # fsi_userupn and the decision option-set integer is fsi_decision.
        $decisions = @($engineResult.Decisions)
        $licensedDecision = @($decisions | Where-Object { $_.fsi_userupn -eq 'licensed@contoso.com' })[0]
        $unlicensedDecision = @($decisions | Where-Object { $_.fsi_userupn -eq 'unlicensed@contoso.com' })[0]

        $licensedDecision.fsi_decision | Should -Be $script:DecisionAllow
        $unlicensedDecision.fsi_decision | Should -Be $script:DecisionBlock
    }
}

Describe 'Get-BillingPolicyInventory - PAYG scope + connected-capability surfacing' {

    BeforeAll {
        $script:InventoryScript = (Resolve-Path (Join-Path $PSScriptRoot '..' 'scripts' 'Get-BillingPolicyInventory.ps1')).Path
        # Dot-source with a placeholder EnvironmentUrl so main is guarded off.
        . $script:InventoryScript -EnvironmentUrl 'https://placeholder.crm.dynamics.com'
    }

    It 'decodes the spend-scope option set into connected services' {
        @(ConvertFrom-CbgSpendScopeValue -Value 100000000) | Should -Be @('Chat')
        @(ConvertFrom-CbgSpendScopeValue -Value 100000001) | Should -Be @('SharePoint')
        @(ConvertFrom-CbgSpendScopeValue -Value 100000002) | Should -Be @('Chat', 'SharePoint')
        @(ConvertFrom-CbgSpendScopeValue -Value $null).Count | Should -Be 0
    }

    It 'decodes the user-scope option set' {
        ConvertFrom-CbgUserScopeValue -Value 100000000 | Should -Be 'AllUsers'
        ConvertFrom-CbgUserScopeValue -Value 100000001 | Should -Be 'Group'
        ConvertFrom-CbgUserScopeValue -Value $null | Should -Be 'Unknown'
    }

    It 'parses an all-users platform policy scope and connected services' {
        $info = Get-CbgPlatformPolicyScope -Policy ([pscustomobject]@{ name = 'P1'; scope = 'AllUsers'; connectedServices = @('CopilotChat') })
        $info.Scope | Should -Be 'AllUsers'
        $info.ConnectedServices | Should -Contain 'Chat'
    }

    It 'parses a nested group-scoped platform policy with group ids' {
        $policy = [pscustomobject]@{
            name       = 'P2'
            properties = [pscustomobject]@{ scope = [pscustomobject]@{ type = 'Specific'; groupIds = @('g1', 'g2') } }
            services   = @('SharePoint')
        }
        $info = Get-CbgPlatformPolicyScope -Policy $policy
        $info.Scope | Should -Be 'Group'
        @($info.ScopeGroupIds).Count | Should -Be 2
        $info.ConnectedServices | Should -Contain 'SharePoint'
    }

    It 'returns Unknown scope for a policy with no scope signal' {
        $info = Get-CbgPlatformPolicyScope -Policy ([pscustomobject]@{ name = 'P3' })
        $info.Scope | Should -Be 'Unknown'
        @($info.ScopeGroupIds).Count | Should -Be 0
    }
}
