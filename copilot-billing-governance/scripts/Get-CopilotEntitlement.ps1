<#
.SYNOPSIS
    Resolves, from live tenant data, the per-user entitlement input objects the
    switch-on-pathway entitlement engine (Invoke-EntitlementEvaluation.ps1) consumes,
    and emits a Find-No-Filter (FNF) "blocked from a gated Copilot capability" lens.

.DESCRIPTION
    Invoke-EntitlementEvaluation.ps1 consumes per-(agent, user) input objects whose
    booleans (hasCopilotLicense, inCreditScopeGroup, inApiAudienceGroup,
    inEligibleCohort, surfaceZeroRated) are supplied today by -InputPath fixtures.
    This resolver produces those booleans from REAL tenant data so the engine can run
    on a live audience. It takes a set of user principal names (UPNs) - in production
    the audience-to-UPN expansion produced by copilot-agent-inventory (CAI) - and:

      1. LICENSE (Microsoft Graph). For each UPN it reads
         GET /users/{upn}/licenseDetails (which already INCLUDES transitive,
         group-based license assignments) and classifies the user as Copilot-licensed
         ONLY when at least one servicePlans[] entry has a servicePlanId in the paid
         Microsoft 365 Copilot service-plan GUID allowlist AND provisioningStatus is
         exactly "Success". Detection is by literal GUID, never by a COPILOT substring
         or a servicePlanName regex, because friendly names drift (Bing_Chat_Enterprise
         now renders as "RETIRED - Commercial data protection for Microsoft Copilot").

      2. DENY trap. E5/E3 Bing_Chat_Enterprise (0d0c0d31-fae7-41f2-b909-eaf4d7f26dba)
         and the Sales / Viva Sales Copilot plans are placed on an explicit DENY list
         and never count as Microsoft 365 Copilot entitlement, hardening against future
         name or SKU drift.

      3. UNDOCUMENTED SKUs. "Microsoft 365 E7" and "Copilot Premium" have NO documented
         SKU GUIDs and are NOT hard-coded. The resolver builds a tenant SKU dictionary
         from GET /subscribedSkus and marks any SKU carrying an allowlisted Copilot
         service plan as Copilot-bearing. A user holding such a SKU is therefore
         "licensed by construction" via the service-plan check above, whatever the SKU
         is named locally.

      4. PAY-AS-YOU-GO / CREDITS. There is no Microsoft Graph endpoint for Copilot
         billing-policy membership. PAYG-covered users are enumerated from the Power
         Platform billing-policy admin REST API (or a pre-exported policy set via
         -BillingPolicyInputPath / Get-AdminBillingPolicy). A policy scoped to "All
         Users" makes EVERY tenant user covered for that capability (which collapses the
         blocked set to zero); a group-scoped policy is resolved transitively via
         GET /groups/{id}/transitiveMembers. Coverage is treated PER CAPABILITY (PAYG
         covers Copilot Chat / SharePoint agents today, not every feature).

      5. BLOCKED. A user is BLOCKED from a gated capability if and only if they have NO
         paid Copilot service plan AND are NOT covered by an applicable PAYG/credit
         policy for that capability. License and PAYG are always joined.

    The resolver does NOT re-implement or modify the engine's decision tree; it feeds
    it. PAYG/credit coverage for the gated capability maps to the engine's
    inCreditScopeGroup input (the "org will pay for this user's consumption" gate);
    api-direct audience and metered eligible-cohort memberships map to inApiAudienceGroup
    and inEligibleCohort when their Entra group object ids are supplied.

    Authentication is managed-identity-first: pass -GraphAccessToken and
    -BillingApiAccessToken from a managed identity or workload identity. A
    Get-AzAccessToken fallback is provided for dev-only interactive runs. All HTTP calls
    go through a throttling-aware wrapper that honours Retry-After on 429/503.

.PARAMETER UserPrincipalName
    One or more UPNs to resolve. Use this OR -InputPath.

.PARAMETER InputPath
    Path to a JSON file describing the audience. Two shapes are accepted:
      - { "upns": ["a@contoso.com", "b@contoso.com"] }  -> flat FNF lens over the UPNs.
      - { "agents": [ { "agentId", "agentName", "createdIn", "configuredTier",
          "spendScope", "sourcePolicyId", "intendedUpns": ["a@contoso.com", ...] } ] }
          -> resolves each agent's audience and assembles an engine-ready -InputPath
          document (agents[].intendedUsers[]) so Invoke-EntitlementEvaluation.ps1 runs
          on real data.

.PARAMETER OutputPath
    Optional path to write the full result document (FNF users + payg coverage + sku
    dictionary + engine input) as JSON.

.PARAMETER EngineInputPath
    Optional path to write ONLY the engine-ready document (the agents[] structure with
    resolved intendedUsers[]) suitable for piping straight into
    Invoke-EntitlementEvaluation.ps1 -InputPath. Requires the agents-skeleton input.

.PARAMETER GatedCapability
    The Copilot capability whose entitlement is being gated. CopilotChat (default),
    SharePointAgents, or Both. Selects which PAYG-connected service must cover a user.

.PARAMETER GraphAccessToken
    Bearer token for Microsoft Graph (resource https://graph.microsoft.com).
    Managed-identity-first; when omitted the resolver falls back to Get-AzAccessToken
    (dev-only). Required permissions: User.Read.All and Group.Read.All (application).

.PARAMETER BillingApiAccessToken
    Bearer token for the Power Platform licensing API
    (resource https://api.powerplatform.com/). Used only when PAYG policies are read
    live (no -BillingPolicyInputPath / -BillingPolicy supplied). Managed-identity-first;
    falls back to Get-AzAccessToken (dev-only). A live-read failure degrades (it does not
    abort the report): PAYG coverage is flagged uncertain and routed to manual review.

.PARAMETER BillingPolicyInputPath
    Path to a JSON file of pre-enumerated PAYG/credit billing policies, e.g. exported
    from Get-AdminBillingPolicy or hand-built from the Microsoft 365 admin center. This
    is the RECOMMENDED path because the live Copilot billing-policy REST schema is a
    summary view (no per-policy scope/capability surface). Canonical shape:
      { "billingPolicies": [
          { "name": "All-up Chat", "scope": "AllUsers", "capabilities": ["Chat"],
            "connected": true },
          { "name": "Pilot group", "scope": "Group",
            "groupIds": ["00000000-0000-0000-0000-000000000000"],
            "capabilities": ["Chat", "SharePoint"], "connected": true } ] }
    The live REST shape ({ "value": [...] }) and a bare top-level array are also tolerated;
    an input with no recognized policy collection (e.g. an empty { "value": [] }) yields
    zero policies (no spurious manual-review entry).

.PARAMETER BillingPolicy
    Pre-enumerated billing-policy objects supplied directly (same shape as the elements
    of -BillingPolicyInputPath's billingPolicies array). Bypasses any live read.

.PARAMETER ApiAudienceGroupId
    Entra group object id whose transitive members populate inApiAudienceGroup
    (the api-direct pathway audience cohort). Optional.

.PARAMETER EligibleCohortGroupId
    Entra group object id whose transitive members populate inEligibleCohort
    (the metered pathway eligible cohort). Optional.

.PARAMETER CreditScopeGroupId
    Entra group object id whose transitive members populate inCreditScopeGroup. When
    supplied it OVERRIDES the PAYG-derived credit-scope coverage (use when the tenant
    models credit scope as a distinct registered group in fsi_cbgapprovedgrouppolicy).
    When omitted, inCreditScopeGroup is derived from PAYG/credit policy coverage for the
    gated capability.

.PARAMETER SurfaceZeroRated
    Value to stamp onto each resolved user's surfaceZeroRated input. Defaults to $true
    per the June 2026 Microsoft Copilot Studio Licensing Guide (footnotes 6 & 7): a
    Copilot-licensed user on a Microsoft 365 surface under their own identity is included
    in the Microsoft 365 Copilot User SL. Override per agent surface as needed.

.EXAMPLE
    PS> .\Get-CopilotEntitlement.ps1 -InputPath .\audience.json -GraphAccessToken $g `
            -BillingPolicyInputPath .\billing-policies.json -OutputPath .\fnf.json
    Resolves the audience, joins license + PAYG, and writes the FNF lens (which users are
    blocked from Copilot Chat) plus the engine-ready input to fnf.json.

.EXAMPLE
    PS> .\Get-CopilotEntitlement.ps1 -InputPath .\agents.skeleton.json -GraphAccessToken $g `
            -BillingPolicyInputPath .\billing-policies.json -EngineInputPath .\engine.input.json
    PS> .\Invoke-EntitlementEvaluation.ps1 -InputPath .\engine.input.json -OutputPath .\result.json
    Assembles real per-user inputs for each agent's audience, then runs the entitlement
    engine on that real data.

.NOTES
    Commercial-cloud Microsoft 365 only. Microsoft's licensing service-plan reference
    disclaims drift; re-verify the GUID allowlist quarterly. The live PAYG read targets
    https://api.powerplatform.com/licensing/billingPolicies (api-version 2024-10-01,
    verified 200); its list view is a summary (no scope/capability surface) so live
    policies typically route to manual review - prefer -BillingPolicyInputPath for the full
    policy shape. A live-read failure degrades rather than aborting the report. Dataverse
    logical names are lowercase with no inter-word underscores; this resolver emits engine
    input JSON, not
    Dataverse rows.

    The functions in this script are defined at top level so the script can be
    dot-sourced (with a placeholder argument) in Pester tests to exercise them with
    mocked Graph / billing-policy responses; the main body runs only when the script is
    invoked directly (guarded by a dot-source check).
#>
[CmdletBinding(DefaultParameterSetName = 'Upns')]
[Diagnostics.CodeAnalysis.SuppressMessageAttribute('PSAvoidUsingPlainTextForPassword', 'CreditScopeGroupId',
    Justification = 'CreditScopeGroupId is an Entra group object id (GUID), not a secret. The rule false-positives on the "Cred" substring in "Credit"; the name deliberately mirrors the engine input inCreditScopeGroup.')]
param(
    [Parameter(Mandatory, ParameterSetName = 'Upns')]
    [ValidateNotNullOrEmpty()]
    [string[]]$UserPrincipalName,

    [Parameter(Mandatory, ParameterSetName = 'InputFile')]
    [ValidateNotNullOrEmpty()]
    [string]$InputPath,

    [Parameter()]
    [string]$OutputPath,

    [Parameter()]
    [string]$EngineInputPath,

    [Parameter()]
    [ValidateSet('CopilotChat', 'SharePointAgents', 'Both')]
    [string]$GatedCapability = 'CopilotChat',

    [Parameter()]
    [string]$GraphAccessToken,

    [Parameter()]
    [string]$BillingApiAccessToken,

    [Parameter()]
    [string]$BillingPolicyInputPath,

    [Parameter()]
    [AllowNull()]
    [object[]]$BillingPolicy,

    [Parameter()]
    [string]$ApiAudienceGroupId,

    [Parameter()]
    [string]$EligibleCohortGroupId,

    [Parameter()]
    [string]$CreditScopeGroupId,

    [Parameter()]
    [bool]$SurfaceZeroRated = $true
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# --------------------------------------------------------------------------------------
# Locked rule constants (see docs GATE0b-verify-license.md). Detection is by literal
# service-plan GUID, NEVER by a COPILOT substring or servicePlanName regex.
# --------------------------------------------------------------------------------------

# ALLOW: the paid Microsoft 365 Copilot service plans (the 8-GUID allowlist). The six
# M365_COPILOT_* plans plus the two sibling plans bundled in the same paid SKU. Any one
# of them with provisioningStatus == Success implies the paid SKU is assigned.
$script:PaidCopilotPlanIds = @(
    '3f30311c-6b1e-48a4-ab79-725b469da960', # M365_COPILOT_BUSINESS_CHAT
    'a62f8878-de10-42f3-b68f-6149a25ceb97', # M365_COPILOT_APPS
    'b95945de-b3bd-46db-8437-f2beb6ea2347', # M365_COPILOT_TEAMS
    '0aedf20c-091d-420b-aadf-30c042609612', # M365_COPILOT_SHAREPOINT
    '931e4a88-a67f-48b5-814f-16a5f1e6028d', # M365_COPILOT_INTELLIGENT_SEARCH
    '89f1c4c8-0878-40f7-804d-869c9128ab5d', # M365_COPILOT_CONNECTORS
    '82d30987-df9b-4486-b146-198b21d164c7', # GRAPH_CONNECTORS_COPILOT (sibling)
    'fe6c28b3-d468-44ea-bbd0-a10a5167435c'  # COPILOT_STUDIO_IN_COPILOT_FOR_M365 (sibling)
)

# DENY: confusable plans that look like Copilot but are NOT paid M365 Copilot. Kept as an
# explicit guard so that even if one of these were ever added to the allowlist by
# mistake, or shipped inside a Copilot-bearing SKU, it can never grant entitlement.
$script:DenyPlanIds = @(
    '0d0c0d31-fae7-41f2-b909-eaf4d7f26dba', # Bing_Chat_Enterprise (free Copilot Chat / BCE)
    '8ba1ff15-7bf6-4620-b65c-ecedb6942766', # Microsoft Sales Copilot Premium & Trial (Viva Sales)
    'a933a62f-c3fb-48e5-a0b7-ac92b94b4420'  # Microsoft_Viva_Sales_PowerAutomate
)

# Reference only (NOT used for the per-user decision; that is by service plan above).
# Known SKU GUIDs that bundle the allowlisted Copilot plans, used to annotate the tenant
# SKU dictionary. Undocumented local names ("E7", "Copilot Premium") are intentionally
# absent and resolved from /subscribedSkus instead.
$script:KnownCopilotBearingSkuIds = @{
    '639dec6b-bb19-468b-871c-c5c441c4b0cb' = 'Microsoft_365_Copilot'
    'ad9c22b3-52d7-4e7e-973c-88121ea96436' = 'Microsoft_365_Copilot_EDU'
    '15f2e9fc-b782-4f73-bf51-81d8b7fff6f4' = 'Microsoft_Copilot_for_Sales'
    'a809996b-059e-42e2-9866-db24b99a9782' = 'M365_Copilot (legacy)'
}

$script:GraphResource = 'https://graph.microsoft.com'
$script:GraphBaseUri = 'https://graph.microsoft.com/v1.0'
# Power Platform licensing API surface for the PAYG billing-policy read. The legacy
# api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/billingPolicies route no
# longer serves billing policies: the old '2022-03-01-preview' is rejected provider-wide
# (400 InvalidApiVersion) and the provider's currently-supported versions 404 on that path
# (the resource moved). Verified live against the licensing surface (2026-06): GET
# https://api.powerplatform.com/licensing/billingPolicies?api-version=2024-10-01 -> 200.
$script:BillingApiResource = 'https://api.powerplatform.com/'
# Most-recent GENERALLY-AVAILABLE licensing api-version (supported list observed live:
# 2024-10-01, 2026-05-01-preview, 2022-03-01-preview, 2021-10-01-preview). A GA version is
# pinned deliberately - the original outage was a *-preview version being retired.
$script:BillingApiVersion = '2024-10-01'
$script:SuccessStatus = 'Success'

# --------------------------------------------------------------------------------------
# Safe property access under Set-StrictMode -Version Latest.
# --------------------------------------------------------------------------------------
function Get-CbgProperty {
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
# Token acquisition - managed-identity-first, Get-AzAccessToken dev-only fallback.
# --------------------------------------------------------------------------------------
function Get-CbgResourceToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceUrl,
        [string]$ProvidedToken
    )
    if (-not [string]::IsNullOrWhiteSpace($ProvidedToken)) { return $ProvidedToken }

    # legacy: dev-only - replace with a managed-identity-supplied token in production
    Write-Verbose "No token supplied for $ResourceUrl; falling back to Get-AzAccessToken (dev-only)."
    if (-not (Get-Command -Name Get-AzAccessToken -ErrorAction SilentlyContinue)) {
        throw "No token provided for $ResourceUrl and Az.Accounts (Get-AzAccessToken) is not available. Supply a managed-identity token or install Az.Accounts and sign in."
    }
    $secure = (Get-AzAccessToken -ResourceUrl $ResourceUrl -AsSecureString).Token
    return ($secure | ConvertFrom-SecureString -AsPlainText)
}

# --------------------------------------------------------------------------------------
# Throttling-aware REST wrapper (the single mockable HTTP seam). Honours Retry-After on
# 429/503; otherwise exponential backoff capped at MaxDelaySeconds.
# --------------------------------------------------------------------------------------
function Invoke-CbgRestMethod {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][hashtable]$Headers,
        [Parameter()][string]$Method = 'Get',
        [Parameter()][string]$Body,
        [int]$MaxRetries = 5,
        [int]$BaseDelaySeconds = 2,
        [int]$MaxDelaySeconds = 60
    )
    $attempt = 0
    while ($true) {
        $attempt++
        try {
            if ($PSBoundParameters.ContainsKey('Body') -and $Body) {
                return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -Body $Body
            }
            return Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method
        }
        catch {
            $status = $null
            try { $status = [int]$_.Exception.Response.StatusCode } catch {
                Write-Verbose "Status lookup failed for $Method $Uri; continuing without status."
            }

            $isRetryable = ($status -eq 429 -or ($null -ne $status -and $status -ge 500 -and $status -le 599))
            if ($isRetryable -and $attempt -le $MaxRetries) {
                $retryAfter = 0
                try {
                    $hdrs = $_.Exception.Response.Headers
                    $values = $null
                    if ($hdrs -and $hdrs.GetType().GetMethod('TryGetValues')) {
                        if ($hdrs.TryGetValues('Retry-After', [ref]$values)) {
                            $retryAfter = [int]([System.Linq.Enumerable]::FirstOrDefault($values))
                        }
                    }
                    elseif ($hdrs) {
                        $hdr = $hdrs['Retry-After']
                        if ($hdr) { $retryAfter = [int]$hdr }
                    }
                }
                catch {
                    Write-Verbose "Retry-After lookup failed for $Method $Uri; using exponential backoff."
                }
                if ($retryAfter -le 0) {
                    $retryAfter = [Math]::Min($MaxDelaySeconds, $BaseDelaySeconds * [Math]::Pow(2, $attempt - 1))
                }
                Write-Warning "  Throttled ($status) on $Method. Sleeping $retryAfter s (attempt $attempt/$MaxRetries)..."
                Start-Sleep -Seconds $retryAfter
                continue
            }

            $bodyText = $null
            try {
                if ($_.ErrorDetails -and $_.ErrorDetails.Message) { $bodyText = $_.ErrorDetails.Message }
            }
            catch {
                Write-Verbose "Error-details lookup failed for $Method $Uri."
            }
            $msg = "Invoke-CbgRestMethod failed: status=$status method=$Method uri=$Uri error=$($_.Exception.Message)"
            if ($bodyText) { $msg += " body=$bodyText" }
            throw $msg
        }
    }
}

# --------------------------------------------------------------------------------------
# Paged Graph collection GET - follows @odata.nextLink and concatenates value[].
# --------------------------------------------------------------------------------------
function Get-CbgGraphCollection {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][string]$Token
    )
    $headers = @{
        Authorization      = "Bearer $Token"
        Accept             = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
    }
    $items = New-Object System.Collections.Generic.List[object]
    $next = $Uri
    while (-not [string]::IsNullOrWhiteSpace($next)) {
        $resp = Invoke-CbgRestMethod -Uri $next -Headers $headers -Method 'Get'
        $value = Get-CbgProperty -InputObject $resp -Name 'value'
        if ($null -ne $value) {
            foreach ($v in @($value)) { $items.Add($v) }
        }
        elseif ($null -ne $resp) {
            # A non-collection response (single entity) - return it as one item.
            $items.Add($resp)
        }
        $next = Get-CbgProperty -InputObject $resp -Name '@odata.nextLink'
    }
    return $items.ToArray()
}

# --------------------------------------------------------------------------------------
# Graph wrappers.
# --------------------------------------------------------------------------------------
function Get-CbgUserLicenseDetail {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Upn,
        [Parameter(Mandatory)][string]$Token
    )
    $escaped = [uri]::EscapeDataString($Upn)
    $uri = "$script:GraphBaseUri/users/$escaped/licenseDetails"
    return @(Get-CbgGraphCollection -Uri $uri -Token $Token)
}

function Get-CbgSubscribedSku {
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Token)
    $uri = "$script:GraphBaseUri/subscribedSkus"
    return @(Get-CbgGraphCollection -Uri $uri -Token $Token)
}

function Get-CbgGroupTransitiveMember {
    <#
    .SYNOPSIS
        Return the transitive USER members (UPN + id) of an Entra group. Nested group
        membership is expanded server-side by the transitiveMembers navigation.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$GroupId,
        [Parameter(Mandatory)][string]$Token
    )
    $escaped = [uri]::EscapeDataString($GroupId)
    $uri = "$script:GraphBaseUri/groups/$escaped/transitiveMembers/microsoft.graph.user`?`$select=id,userPrincipalName&`$top=999"
    return @(Get-CbgGraphCollection -Uri $uri -Token $Token)
}

# --------------------------------------------------------------------------------------
# Pure license logic.
# --------------------------------------------------------------------------------------
function Get-CbgLicenseEvidence {
    <#
    .SYNOPSIS
        Inspect a user's licenseDetails value[] and return the entitlement evidence:
        whether a paid Copilot plan is present-and-Success, which plan/sku GUIDs matched,
        and which denied plans were observed (for audit).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$LicenseDetails)

    $allow = @{}; foreach ($g in $script:PaidCopilotPlanIds) { $allow[$g.ToLowerInvariant()] = $true }
    $deny = @{}; foreach ($g in $script:DenyPlanIds) { $deny[$g.ToLowerInvariant()] = $true }

    $matchedPlans = New-Object System.Collections.Generic.List[string]
    $grantingSkus = New-Object System.Collections.Generic.List[string]
    $deniedSeen = New-Object System.Collections.Generic.List[string]

    foreach ($lic in @($LicenseDetails)) {
        if ($null -eq $lic) { continue }
        $skuPart = Get-CbgProperty -InputObject $lic -Name 'skuPartNumber'
        $plans = Get-CbgProperty -InputObject $lic -Name 'servicePlans'
        $skuGrants = $false
        foreach ($sp in @($plans)) {
            if ($null -eq $sp) { continue }
            $planId = Get-CbgProperty -InputObject $sp -Name 'servicePlanId'
            $statusVal = Get-CbgProperty -InputObject $sp -Name 'provisioningStatus'
            if ([string]::IsNullOrWhiteSpace($planId)) { continue }
            $planKey = ([string]$planId).ToLowerInvariant()

            if ($deny.ContainsKey($planKey)) {
                if (-not $deniedSeen.Contains($planKey)) { $deniedSeen.Add($planKey) }
                continue
            }
            if ($allow.ContainsKey($planKey) -and
                ($null -ne $statusVal) -and
                ([string]$statusVal).Equals($script:SuccessStatus, [System.StringComparison]::OrdinalIgnoreCase)) {
                if (-not $matchedPlans.Contains($planKey)) { $matchedPlans.Add($planKey) }
                $skuGrants = $true
            }
        }
        if ($skuGrants -and -not [string]::IsNullOrWhiteSpace($skuPart)) {
            if (-not $grantingSkus.Contains([string]$skuPart)) { $grantingSkus.Add([string]$skuPart) }
        }
    }

    return [pscustomobject]@{
        HasPaidCopilotLicense  = ($matchedPlans.Count -gt 0)
        MatchedPlanIds         = $matchedPlans.ToArray()
        GrantingSkuPartNumbers = $grantingSkus.ToArray()
        DeniedPlanIdsObserved  = $deniedSeen.ToArray()
    }
}

function Get-CbgCopilotBearingSku {
    <#
    .SYNOPSIS
        From /subscribedSkus, identify which tenant SKUs carry an allowlisted Copilot
        service plan. A user holding one of these is "licensed by construction"
        regardless of how the SKU is named locally (e.g. "E7", "Copilot Premium").
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowEmptyCollection()][object[]]$SubscribedSkus)

    $allow = @{}; foreach ($g in $script:PaidCopilotPlanIds) { $allow[$g.ToLowerInvariant()] = $true }
    $result = New-Object System.Collections.Generic.List[object]
    foreach ($sku in @($SubscribedSkus)) {
        if ($null -eq $sku) { continue }
        $skuId = Get-CbgProperty -InputObject $sku -Name 'skuId'
        $skuPart = Get-CbgProperty -InputObject $sku -Name 'skuPartNumber'
        $plans = Get-CbgProperty -InputObject $sku -Name 'servicePlans'
        $carried = New-Object System.Collections.Generic.List[string]
        foreach ($sp in @($plans)) {
            $planId = Get-CbgProperty -InputObject $sp -Name 'servicePlanId'
            if ([string]::IsNullOrWhiteSpace($planId)) { continue }
            $planKey = ([string]$planId).ToLowerInvariant()
            if ($allow.ContainsKey($planKey)) { $carried.Add($planKey) }
        }
        if ($carried.Count -gt 0) {
            $skuKey = $null
            if ($null -ne $skuId) { $skuKey = ([string]$skuId).ToLowerInvariant() }
            $documented = ($null -ne $skuKey -and $script:KnownCopilotBearingSkuIds.ContainsKey($skuKey))
            $result.Add([pscustomobject]@{
                    skuId                  = $skuId
                    skuPartNumber          = $skuPart
                    copilotPlanIds         = $carried.ToArray()
                    documentedSkuLabel     = $(if ($documented) { $script:KnownCopilotBearingSkuIds[$skuKey] } else { $null })
                    licensedByConstruction = (-not $documented)
                })
        }
    }
    return $result.ToArray()
}

# --------------------------------------------------------------------------------------
# PAYG / credit billing-policy normalisation and coverage.
# --------------------------------------------------------------------------------------
function ConvertFrom-CbgBillingPolicy {
    <#
    .SYNOPSIS
        Normalise a billing-policy object (canonical, raw BAP, or Get-AdminBillingPolicy
        shape) into { Name, ScopeType, GroupIds[], Capabilities[], Connected,
        CapabilitiesKnown }.
    .DESCRIPTION
        The Copilot billing-policy REST schema is unproven, so this tolerates several
        field spellings. ScopeType is AllUsers when a scope/userScope value matches
        /all/i (or "tenant"), Group when it matches /specific|group/i or group ids are
        present, otherwise Unknown. Capabilities are mapped to Chat / SharePoint.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()]$Policy)

    if ($null -eq $Policy) { return $null }

    $name = Get-CbgProperty -InputObject $Policy -Name 'name'
    if (-not $name) { $name = Get-CbgProperty -InputObject $Policy -Name 'policyName' }
    if (-not $name) { $name = Get-CbgProperty -InputObject $Policy -Name 'id' }
    if (-not $name) { $name = Get-CbgProperty -InputObject $Policy -Name 'Name' }

    # Locate a scope container across possible shapes.
    $scopeContainer = $Policy
    $props = Get-CbgProperty -InputObject $Policy -Name 'properties'
    if ($null -ne $props) {
        $inner = Get-CbgProperty -InputObject $props -Name 'scope'
        if ($null -ne $inner) { $scopeContainer = $inner }
        else { $scopeContainer = $props }
    }
    else {
        $directScope = Get-CbgProperty -InputObject $Policy -Name 'scope'
        if ($null -ne $directScope -and $directScope -isnot [string]) { $scopeContainer = $directScope }
    }

    # Raw scope type token from any of several keys.
    $scopeRaw = $null
    foreach ($k in @('scopeType', 'userScopeType', 'type', 'userScope', 'scope')) {
        $v = Get-CbgProperty -InputObject $scopeContainer -Name $k
        if ($null -ne $v -and $v -is [string]) { $scopeRaw = $v; break }
    }
    if ($null -eq $scopeRaw) {
        foreach ($k in @('scope', 'userScope', 'scopeType')) {
            $v = Get-CbgProperty -InputObject $Policy -Name $k
            if ($null -ne $v -and $v -is [string]) { $scopeRaw = $v; break }
        }
    }

    # Group ids from any of several locations.
    $groupIds = New-Object System.Collections.Generic.List[string]
    foreach ($container in @($scopeContainer, $Policy)) {
        foreach ($gk in @('groupIds', 'groups', 'securityGroups')) {
            $gv = Get-CbgProperty -InputObject $container -Name $gk
            foreach ($g in @($gv)) {
                if ($null -eq $g) { continue }
                if ($g -is [string]) { if (-not $groupIds.Contains($g)) { $groupIds.Add($g) } }
                else {
                    $gid = Get-CbgProperty -InputObject $g -Name 'id'
                    if (-not $gid) { $gid = Get-CbgProperty -InputObject $g -Name 'groupId' }
                    if ($gid -and -not $groupIds.Contains([string]$gid)) { $groupIds.Add([string]$gid) }
                }
            }
        }
        foreach ($sk in @('securityGroupId', 'groupId')) {
            $sv = Get-CbgProperty -InputObject $container -Name $sk
            if ($sv -and -not $groupIds.Contains([string]$sv)) { $groupIds.Add([string]$sv) }
        }
    }

    # Decide scope type.
    $scopeType = 'Unknown'
    if ($scopeRaw) {
        if ($scopeRaw -match '(?i)all|tenant|everyone') { $scopeType = 'AllUsers' }
        elseif ($scopeRaw -match '(?i)specific|group') { $scopeType = 'Group' }
    }
    if ($scopeType -eq 'Unknown' -and $groupIds.Count -gt 0) { $scopeType = 'Group' }

    # Capabilities -> Chat / SharePoint.
    $caps = New-Object System.Collections.Generic.List[string]
    $capsKnown = $false
    foreach ($ck in @('capabilities', 'services', 'connectedServices', 'serviceTypes', 'spendScope', 'surfaceScope')) {
        $cv = Get-CbgProperty -InputObject $Policy -Name $ck
        if ($null -eq $cv) { $cv = Get-CbgProperty -InputObject $scopeContainer -Name $ck }
        foreach ($c in @($cv)) {
            if ($null -eq $c) { continue }
            $ctext = if ($c -is [string]) { $c } else { [string](Get-CbgProperty -InputObject $c -Name 'name') }
            if ([string]::IsNullOrWhiteSpace($ctext)) { continue }
            $capsKnown = $true
            if ($ctext -match '(?i)chat') { if (-not $caps.Contains('Chat')) { $caps.Add('Chat') } }
            if ($ctext -match '(?i)sharepoint|spo') { if (-not $caps.Contains('SharePoint')) { $caps.Add('SharePoint') } }
        }
    }

    # Connection state. Default to NOT connected and require an explicit positive
    # signal to entitle: a billing policy not connected to a service entitles no one
    # (GATE0b 4). An undetermined connection state (no connected/isConnected/status
    # signal at all) is surfaced upstream as "connection unknown" for manual review -
    # never silently assumed connected, because a false grant under-reports the users
    # who actually lack coverage.
    $connected = $false
    $connectionKnown = $false
    foreach ($sk in @('connected', 'isConnected')) {
        $sv = Get-CbgProperty -InputObject $Policy -Name $sk
        if ($null -ne $sv) { $connected = [bool]$sv; $connectionKnown = $true; break }
    }
    if (-not $connectionKnown) {
        $statusVal = Get-CbgProperty -InputObject $Policy -Name 'status'
        if ($null -ne $statusVal -and $statusVal -is [string]) {
            $connected = ($statusVal -match '(?i)enabled|connected|active')
            $connectionKnown = $true
        }
    }

    return [pscustomobject]@{
        Name              = $name
        ScopeType         = $scopeType
        GroupIds          = $groupIds.ToArray()
        Capabilities      = $caps.ToArray()
        CapabilitiesKnown = $capsKnown
        Connected         = $connected
        ConnectionKnown   = $connectionKnown
    }
}

function Test-CbgPolicyCoversCapability {
    <#
    .SYNOPSIS
        True only when a normalised policy is connected AND its recognized capability
        surface includes the gated capability. Fail-CLOSED on policy-shape uncertainty:
        a policy whose connection state is undetermined or whose capability surface is
        unrecognized is treated as NOT covering (and routed upstream to manual review),
        because a billing policy not connected to a service entitles no one (GATE0b 4).
        Treating such a policy as covering would silently flip unlicensed in-scope users
        to not-blocked and under-report the people who actually lack access.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][psobject]$Policy,
        [Parameter(Mandatory)][ValidateSet('CopilotChat', 'SharePointAgents', 'Both')][string]$Capability
    )
    if (-not $Policy.Connected) { return $false }
    if (-not $Policy.CapabilitiesKnown) { return $false }  # unparseable surface -> fail closed (no coverage)
    $wantChat = ($Capability -in @('CopilotChat', 'Both'))
    $wantSpo = ($Capability -in @('SharePointAgents', 'Both'))
    if ($wantChat -and ($Policy.Capabilities -contains 'Chat')) { return $true }
    if ($wantSpo -and ($Policy.Capabilities -contains 'SharePoint')) { return $true }
    return $false
}

function Get-CbgBillingPolicyArray {
    <#
    .SYNOPSIS
        Extract the billing-policy array from a parsed -BillingPolicyInputPath document.
    .DESCRIPTION
        Tolerates the documented wrapper ({ "billingPolicies": [...] }), the live REST
        shape ({ "value": [...] }) and a bare top-level array. An object that carries no
        recognized policy collection yields an EMPTY set - it is NOT misread as a single
        wrapper "policy" (that bug surfaced an empty { "value": [] } input as one spurious
        policy needing manual review).
    #>
    [CmdletBinding()]
    param([Parameter()][AllowNull()]$InputObject)
    if ($null -eq $InputObject) { return @() }
    $arr = Get-CbgProperty -InputObject $InputObject -Name 'billingPolicies'
    if ($null -eq $arr) { $arr = Get-CbgProperty -InputObject $InputObject -Name 'value' }
    if ($null -eq $arr) {
        # No recognized collection property. Only a bare array is itself a policy set;
        # any other object (e.g. an empty { "value": [] } whose value unwrapped to $null)
        # carries zero policies.
        if ($InputObject -is [System.Array]) { $arr = $InputObject } else { return @() }
    }
    return @($arr)
}

function Get-CbgBillingPolicyLive {
    <#
    .SYNOPSIS
        Best-effort live read of PAYG billing policies from the Power Platform licensing
        API. DEGRADES (never throws) so a billing-read failure cannot abort the report.
    .DESCRIPTION
        Reads https://api.powerplatform.com/licensing/billingPolicies. The list view is a
        summary (no per-policy scope/capability surface), so live policies typically route
        to manual review (fail-closed) rather than asserting coverage - prefer
        -BillingPolicyInputPath when the full policy shape is needed.

        A non-200 / network / auth failure is caught and reported via ReadFailed + ReadError
        instead of throwing: PAYG coverage is one input to the report, and a read failure
        must not abort the license-based blocked-user detection that does not depend on it.
    .OUTPUTS
        [pscustomobject] with Policies (object[]), ReadFailed (bool) and ReadError (string).
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$Token)
    $uri = "$($script:BillingApiResource.TrimEnd('/'))/licensing/billingPolicies?api-version=$($script:BillingApiVersion)"
    $headers = @{ Authorization = "Bearer $Token"; Accept = 'application/json' }
    try {
        $resp = Invoke-CbgRestMethod -Uri $uri -Headers $headers -Method 'Get'
        $value = Get-CbgProperty -InputObject $resp -Name 'value'
        $policies = if ($null -eq $value) { @() } else { @($value) }
        return [pscustomobject]@{ Policies = $policies; ReadFailed = $false; ReadError = $null }
    }
    catch {
        $err = $_.Exception.Message
        Write-Warning "Live billing-policy read failed; PAYG coverage will be treated as undetermined (fail-closed, manual review) and the rest of the report still runs. Error: $err"
        return [pscustomobject]@{ Policies = @(); ReadFailed = $true; ReadError = $err }
    }
}

function Resolve-CbgPaygCoverage {
    <#
    .SYNOPSIS
        Resolve which users a set of billing policies covers for a gated capability.
        Returns AllUsersCovered, the covered-UPN set, and the applied-policy detail.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][AllowEmptyCollection()][object[]]$Policies,
        [Parameter(Mandatory)][ValidateSet('CopilotChat', 'SharePointAgents', 'Both')][string]$Capability,
        [Parameter()][string]$GraphToken,
        [Parameter()][string]$BillingReadError
    )
    $allUsersCovered = $false
    $coveredUpns = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $applied = New-Object System.Collections.Generic.List[object]
    $needsReview = New-Object System.Collections.Generic.List[object]
    $uncertain = $false

    # --- Fail-CLOSED when the live billing-policy read failed. We could not enumerate the
    #     PAYG policies at all, so coverage is undetermined: treat it as NOT covering (no
    #     unlicensed user is silently rescued) and surface a manual-review entry so the
    #     uncertainty is reported rather than read as "0 policies, all clear". ---
    if (-not [string]::IsNullOrWhiteSpace($BillingReadError)) {
        $uncertain = $true
        $needsReview.Add([pscustomobject]@{ name = '(billing-policy read failed)'; scopeType = 'Unknown'; applies = $false; capabilitiesKnown = $false; connectionUnknown = $true; readFailed = $true; reason = "live billing-policy read failed ($BillingReadError); PAYG coverage could not be determined and was treated as NOT covering pending manual review" })
    }

    foreach ($raw in @($Policies)) {
        $p = ConvertFrom-CbgBillingPolicy -Policy $raw
        if ($null -eq $p) { continue }

        # --- Fail-CLOSED on policy-shape uncertainty. A billing policy not connected to
        #     a service entitles no one (GATE0b 4); likewise an unparseable capability
        #     surface or scope cannot be asserted to cover anyone. These cases do NOT
        #     grant coverage - they are routed to needsManualReview (distinct from
        #     appliedPolicies) so affected unlicensed users stay reported as blocked
        #     pending verification, rather than being silently flipped to not-blocked. ---

        # Connection state undetermined: cannot confirm the policy is connected.
        if (-not $p.ConnectionKnown) {
            $uncertain = $true
            $needsReview.Add([pscustomobject]@{ name = $p.Name; scopeType = $p.ScopeType; applies = $false; capabilitiesKnown = $p.CapabilitiesKnown; connectionUnknown = $true; reason = 'connection state unknown; treated as not connected (no coverage) pending manual review' })
            continue
        }
        # Explicitly not connected: a known state (not uncertain) that entitles no one.
        if (-not $p.Connected) {
            $applied.Add([pscustomobject]@{ name = $p.Name; scopeType = $p.ScopeType; applies = $false; reason = 'policy not connected' })
            continue
        }
        # Connected but the capability surface is unrecognized: cannot confirm it covers
        # the gated capability, so fail closed and surface for review.
        if (-not $p.CapabilitiesKnown) {
            $uncertain = $true
            $needsReview.Add([pscustomobject]@{ name = $p.Name; scopeType = $p.ScopeType; applies = $false; capabilitiesKnown = $false; connectionUnknown = $false; reason = 'capability surface unrecognized; cannot confirm coverage of the gated capability pending manual review' })
            continue
        }
        # Connected with a recognized surface that does not include the gated capability.
        if (-not (Test-CbgPolicyCoversCapability -Policy $p -Capability $Capability)) {
            $applied.Add([pscustomobject]@{ name = $p.Name; scopeType = $p.ScopeType; applies = $false; reason = 'capability not covered' })
            continue
        }

        # --- Covers the gated capability: apply coverage by scope. ---
        if ($p.ScopeType -eq 'AllUsers') {
            $allUsersCovered = $true
            $applied.Add([pscustomobject]@{ name = $p.Name; scopeType = 'AllUsers'; applies = $true; capabilitiesKnown = $p.CapabilitiesKnown })
            continue
        }
        if ($p.ScopeType -eq 'Group') {
            $memberUpns = New-Object System.Collections.Generic.List[string]
            foreach ($gid in @($p.GroupIds)) {
                if ([string]::IsNullOrWhiteSpace($gid)) { continue }
                if ([string]::IsNullOrWhiteSpace($GraphToken)) {
                    throw "Billing policy '$($p.Name)' is group-scoped (group $gid) but no Graph token is available to resolve transitive membership."
                }
                foreach ($m in @(Get-CbgGroupTransitiveMember -GroupId $gid -Token $GraphToken)) {
                    $upn = Get-CbgProperty -InputObject $m -Name 'userPrincipalName'
                    if (-not [string]::IsNullOrWhiteSpace($upn)) {
                        [void]$coveredUpns.Add([string]$upn)
                        $memberUpns.Add([string]$upn)
                    }
                }
            }
            $applied.Add([pscustomobject]@{ name = $p.Name; scopeType = 'Group'; applies = $true; groupIds = $p.GroupIds; resolvedMemberCount = $memberUpns.Count; capabilitiesKnown = $p.CapabilitiesKnown })
            continue
        }
        # Scope type could not be determined: cannot safely assert who is covered.
        # Fail closed and surface for review (do NOT grant coverage).
        $uncertain = $true
        $needsReview.Add([pscustomobject]@{ name = $p.Name; scopeType = 'Unknown'; applies = $false; capabilitiesKnown = $p.CapabilitiesKnown; connectionUnknown = $false; reason = 'scope type could not be determined; cannot assert coverage pending manual review' })
    }

    return [pscustomobject]@{
        AllUsersCovered   = $allUsersCovered
        CoveredUpns       = $coveredUpns
        AppliedPolicies   = $applied.ToArray()
        NeedsManualReview = $needsReview.ToArray()
        CoverageUncertain = $uncertain
    }
}

function Resolve-CbgGroupMemberUpnSet {
    <#
    .SYNOPSIS
        Transitive member UPNs of a single group as a case-insensitive HashSet.
    #>
    [CmdletBinding()]
    param(
        [Parameter()][AllowNull()][string]$GroupId,
        [Parameter()][string]$GraphToken
    )
    $set = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    if ([string]::IsNullOrWhiteSpace($GroupId)) { return , $set }
    if ([string]::IsNullOrWhiteSpace($GraphToken)) {
        throw "Group $GroupId requested but no Graph token is available to resolve membership."
    }
    foreach ($m in @(Get-CbgGroupTransitiveMember -GroupId $GroupId -Token $GraphToken)) {
        $upn = Get-CbgProperty -InputObject $m -Name 'userPrincipalName'
        if (-not [string]::IsNullOrWhiteSpace($upn)) { [void]$set.Add([string]$upn) }
    }
    return , $set
}

function Resolve-CbgUserEntitlement {
    <#
    .SYNOPSIS
        Join a user's license evidence with PAYG coverage and cohort memberships into the
        per-user object the engine consumes plus FNF lens diagnostics.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Upn,
        [Parameter(Mandatory)][psobject]$LicenseEvidence,
        [Parameter(Mandatory)][bool]$PaygCovered,
        [Parameter(Mandatory)][string]$PaygCoverageSource,
        [Parameter(Mandatory)][bool]$InApiAudienceGroup,
        [Parameter(Mandatory)][bool]$InEligibleCohort,
        [Parameter(Mandatory)][bool]$SurfaceZeroRatedValue
    )
    $hasLicense = $LicenseEvidence.HasPaidCopilotLicense
    # PAYG/credit coverage for the gated capability is the engine's credit-scope gate.
    $inCreditScope = $PaygCovered
    $isBlocked = ((-not $hasLicense) -and (-not $PaygCovered))
    $blockReason = if ($isBlocked) { 'NoLicenseAndNoPaygCoverage' } else { $null }

    return [pscustomobject]@{
        upn                   = $Upn
        hasCopilotLicense     = $hasLicense
        inApiAudienceGroup    = $InApiAudienceGroup
        inCreditScopeGroup    = $inCreditScope
        inEligibleCohort      = $InEligibleCohort
        surfaceZeroRated      = $SurfaceZeroRatedValue
        # FNF lens diagnostics (not consumed by the engine; for the coverage report).
        isBlocked             = $isBlocked
        blockReason           = $blockReason
        paygCovered           = $PaygCovered
        paygCoverageSource    = $PaygCoverageSource
        matchedPlanIds        = $LicenseEvidence.MatchedPlanIds
        grantingSkus          = $LicenseEvidence.GrantingSkuPartNumbers
        deniedPlanIdsObserved = $LicenseEvidence.DeniedPlanIdsObserved
    }
}

# The booleans the engine consumes (the rest are FNF diagnostics).
$script:EngineInputFields = @('upn', 'hasCopilotLicense', 'inApiAudienceGroup', 'inCreditScopeGroup', 'inEligibleCohort', 'surfaceZeroRated')

function Invoke-CbgEntitlementResolution {
    <#
    .SYNOPSIS
        Core resolution: join per-user license evidence with PAYG coverage and cohort
        memberships, assemble the engine-ready document, and produce the FNF lens result.
        Token acquisition, audience/billing-policy file loading, and output-file writing
        stay in the script's main body; this function does the data join so it can be
        unit-tested with a mocked Invoke-CbgRestMethod.
    .OUTPUTS
        The full result document (FNF users, PAYG coverage, SKU dictionary, engineInput).
    #>
    [CmdletBinding()]
    param(
        [Parameter()][AllowEmptyCollection()][string[]]$Upn = @(),
        [Parameter()][AllowNull()][object[]]$AgentsSkeleton,
        [Parameter()][AllowNull()][object[]]$Policy,
        [Parameter(Mandatory)][string]$GraphToken,
        [Parameter(Mandatory)][ValidateSet('CopilotChat', 'SharePointAgents', 'Both')][string]$Capability,
        [Parameter()][string]$ApiAudienceGroupId,
        [Parameter()][string]$EligibleCohortGroupId,
        [Parameter()][string]$CreditScopeGroupId,
        [Parameter()][bool]$SurfaceZeroRatedValue = $true,
        [Parameter()][string]$BillingReadError
    )

    # De-duplicate UPNs (case-insensitive) preserving order, so each user is resolved once.
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    $uniqueUpns = New-Object System.Collections.Generic.List[string]
    foreach ($u in @($Upn)) {
        if ([string]::IsNullOrWhiteSpace($u)) { continue }
        $t = $u.Trim()
        if ($seen.Add($t)) { $uniqueUpns.Add($t) }
    }

    # --- PAYG / credit coverage for the gated capability. A live billing-read failure
    #     ($BillingReadError) is threaded in so coverage is flagged uncertain (fail-closed)
    #     rather than silently treated as "no policies / all clear". ---
    $paygCoverage = Resolve-CbgPaygCoverage -Policies @($Policy) -Capability $Capability -GraphToken $GraphToken -BillingReadError $BillingReadError

    # --- Optional cohort group memberships (resolved once). ---
    $apiAudienceSet = Resolve-CbgGroupMemberUpnSet -GroupId $ApiAudienceGroupId -GraphToken $GraphToken
    $eligibleCohortSet = Resolve-CbgGroupMemberUpnSet -GroupId $EligibleCohortGroupId -GraphToken $GraphToken
    $creditScopeOverrideSet = $null
    if (-not [string]::IsNullOrWhiteSpace($CreditScopeGroupId)) {
        $creditScopeOverrideSet = Resolve-CbgGroupMemberUpnSet -GroupId $CreditScopeGroupId -GraphToken $GraphToken
    }

    # --- Tenant SKU dictionary (diagnostic; reconciles undocumented local SKU names). ---
    $copilotBearingSkus = @()
    try {
        $copilotBearingSkus = @(Get-CbgCopilotBearingSku -SubscribedSkus (Get-CbgSubscribedSku -Token $GraphToken))
    }
    catch {
        Write-Warning "Could not read /subscribedSkus for the tenant SKU dictionary: $($_.Exception.Message)"
    }

    # --- Per-user resolution. ---
    $resolvedByUpn = @{}
    $users = New-Object System.Collections.Generic.List[object]
    $unresolved = New-Object System.Collections.Generic.List[object]

    foreach ($u in $uniqueUpns) {
        $evidence = $null
        try {
            $ld = Get-CbgUserLicenseDetail -Upn $u -Token $GraphToken
            $evidence = Get-CbgLicenseEvidence -LicenseDetails $ld
        }
        catch {
            # Fail-OPEN on a read error: do NOT assert "blocked" for a user we could not
            # verify (misclassifying a licensed user as blocked is a serious error). Record
            # for manual review and exclude from the engine input.
            $unresolved.Add([pscustomobject]@{ upn = $u; status = 'error'; reason = $_.Exception.Message })
            Write-Warning "Could not resolve license for ${u}: $($_.Exception.Message)"
            continue
        }

        $paygCovered = $false
        $paygSource = 'none'
        if ($null -ne $creditScopeOverrideSet) {
            if ($creditScopeOverrideSet.Contains($u)) { $paygCovered = $true; $paygSource = 'creditScopeGroup' }
        }
        else {
            if ($paygCoverage.AllUsersCovered) { $paygCovered = $true; $paygSource = 'paygAllUsers' }
            elseif ($paygCoverage.CoveredUpns.Contains($u)) { $paygCovered = $true; $paygSource = 'paygGroup' }
        }

        $userObj = Resolve-CbgUserEntitlement -Upn $u -LicenseEvidence $evidence `
            -PaygCovered $paygCovered -PaygCoverageSource $paygSource `
            -InApiAudienceGroup ($apiAudienceSet.Contains($u)) `
            -InEligibleCohort ($eligibleCohortSet.Contains($u)) `
            -SurfaceZeroRatedValue $SurfaceZeroRatedValue
        $users.Add($userObj)
        $resolvedByUpn[$u] = $userObj
    }

    # --- Assemble the engine-ready document when an agents skeleton was supplied. ---
    $engineInput = $null
    if ($null -ne $AgentsSkeleton) {
        $engineAgents = New-Object System.Collections.Generic.List[object]
        foreach ($a in @($AgentsSkeleton)) {
            $intended = New-Object System.Collections.Generic.List[object]
            foreach ($iu in @(Get-CbgProperty -InputObject $a -Name 'intendedUpns')) {
                if ([string]::IsNullOrWhiteSpace($iu)) { continue }
                $key = ([string]$iu).Trim()
                if (-not $resolvedByUpn.ContainsKey($key)) { continue }   # unresolved users excluded
                $src = $resolvedByUpn[$key]
                $minimal = [ordered]@{}
                foreach ($f in $script:EngineInputFields) { $minimal[$f] = $src.$f }
                $intended.Add([pscustomobject]$minimal)
            }
            $agentRecord = [ordered]@{
                agentId        = Get-CbgProperty -InputObject $a -Name 'agentId'
                agentName      = Get-CbgProperty -InputObject $a -Name 'agentName'
                createdIn      = Get-CbgProperty -InputObject $a -Name 'createdIn'
                configuredTier = Get-CbgProperty -InputObject $a -Name 'configuredTier'
                spendScope     = Get-CbgProperty -InputObject $a -Name 'spendScope'
                sourcePolicyId = Get-CbgProperty -InputObject $a -Name 'sourcePolicyId'
                intendedUsers  = $intended.ToArray()
            }
            $engineAgents.Add([pscustomobject]$agentRecord)
        }
        $engineInput = [pscustomobject]@{ agents = $engineAgents.ToArray() }
    }

    # --- Result document + FNF summary. ---
    $blockedCount = @($users | Where-Object { $_.isBlocked }).Count
    $appliedCoveringPolicies = @($paygCoverage.AppliedPolicies | Where-Object { $_.applies })
    # Policies treated as NOT covering because their connection state, capability
    # surface, or scope was uncertain (fail-closed). Distinct from appliedPolicies.
    $needsManualReview = @($paygCoverage.NeedsManualReview)

    $result = [pscustomobject]@{
        generatedAt        = (Get-Date).ToUniversalTime().ToString('o')
        gatedCapability    = $Capability
        surfaceZeroRated   = $SurfaceZeroRatedValue
        summary            = [pscustomobject]@{
            requestedUpnCount            = $uniqueUpns.Count
            resolvedUserCount            = $users.Count
            unresolvedCount              = $unresolved.Count
            blockedCount                 = $blockedCount
            licensedCount                = @($users | Where-Object { $_.hasCopilotLicense }).Count
            paygCoveredCount             = @($users | Where-Object { $_.paygCovered }).Count
            paygAllUsersCovered          = $paygCoverage.AllUsersCovered
            paygCoverageUncertain        = $paygCoverage.CoverageUncertain
            needsManualReviewCount       = $needsManualReview.Count
            creditScopeFromOverrideGroup = ($null -ne $creditScopeOverrideSet)
        }
        paygCoverage       = [pscustomobject]@{
            allUsersCovered   = $paygCoverage.AllUsersCovered
            coverageUncertain = $paygCoverage.CoverageUncertain
            coveredUpnCount   = $paygCoverage.CoveredUpns.Count
            appliedPolicies   = $appliedCoveringPolicies
            needsManualReview = $needsManualReview
        }
        copilotBearingSkus = $copilotBearingSkus
        users              = $users.ToArray()
        unresolved         = $unresolved.ToArray()
        engineInput        = $engineInput
    }

    # The All-Users PAYG case collapses the blocked set to zero regardless of license -
    # surface it loudly so a product team does not read "0 blocked" as "all entitled".
    if ($paygCoverage.AllUsersCovered) {
        Write-Warning "A PAYG/credit policy is scoped to ALL USERS for '$Capability'; every tenant user is covered and the blocked set is zero by construction. Verify this is intended."
    }
    if ($paygCoverage.CoverageUncertain) {
        Write-Warning "$($needsManualReview.Count) billing policy(ies) had an undetermined connection state, an unrecognized capability surface, or an unresolved scope. Per the fail-closed-on-uncertainty posture they were treated as NOT covering and routed to 'needsManualReview'; affected unlicensed users remain reported as blocked pending manual verification against the Microsoft 365 admin center."
    }
    if ($unresolved.Count -gt 0) {
        Write-Warning "$($unresolved.Count) user(s) could not be resolved and were excluded from the engine input (see 'unresolved'). They are NOT reported as blocked."
    }

    return $result
}

# ======================================================================================
# Main (runs only on direct invocation; dot-sourcing for tests skips this block).
# ======================================================================================
if ($MyInvocation.InvocationName -ne '.') {

    # --- Resolve the audience: flat UPN list or an agents skeleton. ---
    $agentsSkeleton = $null
    $upns = New-Object System.Collections.Generic.List[string]

    if ($PSCmdlet.ParameterSetName -eq 'InputFile') {
        if (-not (Test-Path -LiteralPath $InputPath)) { throw "Input file not found: $InputPath" }
        $inputObject = Get-Content -LiteralPath $InputPath -Raw | ConvertFrom-Json
        $agentsProp = Get-CbgProperty -InputObject $inputObject -Name 'agents'
        $upnsProp = Get-CbgProperty -InputObject $inputObject -Name 'upns'
        if ($null -ne $agentsProp) {
            $agentsSkeleton = @($agentsProp)
            foreach ($a in $agentsSkeleton) {
                foreach ($u in @(Get-CbgProperty -InputObject $a -Name 'intendedUpns')) {
                    if (-not [string]::IsNullOrWhiteSpace($u)) { $upns.Add([string]$u) }
                }
            }
        }
        elseif ($null -ne $upnsProp) {
            foreach ($u in @($upnsProp)) {
                if (-not [string]::IsNullOrWhiteSpace($u)) { $upns.Add([string]$u) }
            }
        }
        else {
            throw "Input file must contain an 'agents' array or a 'upns' array."
        }
    }
    else {
        foreach ($u in @($UserPrincipalName)) {
            if (-not [string]::IsNullOrWhiteSpace($u)) { $upns.Add($u.Trim()) }
        }
    }

    if ($upns.Count -eq 0) { Write-Warning "No UPNs to resolve." }

    # --- Acquire tokens (managed-identity-first). Graph always; licensing API only for live read. ---
    $graphToken = Get-CbgResourceToken -ResourceUrl $script:GraphResource -ProvidedToken $GraphAccessToken

    # --- PAYG / credit coverage. Prefer supplied policies; else a live licensing read. ---
    $policies = @()
    $billingReadError = ''
    if ($PSBoundParameters.ContainsKey('BillingPolicy') -and $null -ne $BillingPolicy) {
        $policies = @($BillingPolicy)
    }
    elseif (-not [string]::IsNullOrWhiteSpace($BillingPolicyInputPath)) {
        if (-not (Test-Path -LiteralPath $BillingPolicyInputPath)) { throw "Billing policy file not found: $BillingPolicyInputPath" }
        $bpObject = Get-Content -LiteralPath $BillingPolicyInputPath -Raw | ConvertFrom-Json
        $policies = @(Get-CbgBillingPolicyArray -InputObject $bpObject)
    }
    else {
        Write-Verbose "No billing policies supplied; attempting a best-effort live Power Platform licensing billing-policy read."
        $billingToken = Get-CbgResourceToken -ResourceUrl $script:BillingApiResource -ProvidedToken $BillingApiAccessToken
        $live = Get-CbgBillingPolicyLive -Token $billingToken
        $policies = @($live.Policies)
        $billingReadError = [string]$live.ReadError
    }

    $result = Invoke-CbgEntitlementResolution `
        -Upn $upns.ToArray() -AgentsSkeleton $agentsSkeleton -Policy $policies `
        -GraphToken $graphToken -Capability $GatedCapability `
        -ApiAudienceGroupId $ApiAudienceGroupId -EligibleCohortGroupId $EligibleCohortGroupId `
        -CreditScopeGroupId $CreditScopeGroupId -SurfaceZeroRatedValue $SurfaceZeroRated `
        -BillingReadError $billingReadError

    if (-not [string]::IsNullOrWhiteSpace($OutputPath)) {
        $result | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $OutputPath -Encoding UTF8
        Write-Verbose "Wrote full result to $OutputPath."
    }
    if (-not [string]::IsNullOrWhiteSpace($EngineInputPath)) {
        if ($null -eq $result.engineInput) {
            throw "-EngineInputPath requires the agents-skeleton input (an 'agents' array with intendedUpns); a flat UPN list has no agent dimension to assemble."
        }
        $result.engineInput | ConvertTo-Json -Depth 12 | Set-Content -LiteralPath $EngineInputPath -Encoding UTF8
        Write-Verbose "Wrote engine-ready input to $EngineInputPath."
    }

    Write-Output $result
}
