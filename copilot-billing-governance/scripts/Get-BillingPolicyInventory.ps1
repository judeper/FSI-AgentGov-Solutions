<#
.SYNOPSIS
    Reads the two Copilot consumption billing policy objects - pay-as-you-go (PAYG)
    billing policies and prepaid Copilot credit policies - and reports tenant
    inventory against the 50 (PAYG) / 10 (credit) ceilings.

.DESCRIPTION
    Copilot consumption billing is governed by two distinct policy objects:

      - PAYG billing policy: backed by an Azure subscription, added then connected
        to one or more environments (two-step add -> connect). Tenant ceiling is 50.
        PAYG provides budget alerts, not a hard-stop.
      - Copilot credit policy: prepaid, standalone hard-stop, no Azure subscription.
        Tenant ceiling is 10. Credit policies are Chat-only today; SharePoint
        grounding stays on PAYG.

    This cmdlet returns a normalized inventory of both objects plus headroom against
    each ceiling. For each PAYG policy it also surfaces the user scope (AllUsers,
    Group, or Unknown), any assigned Entra security group object ids (ScopeGroupIds),
    and the connected Copilot surfaces (ConnectedServices: Chat / SharePoint) so an
    operator can see at a glance which policies cover all users for which capability.
    A PAYG policy scoped to all users covers every tenant user for its surface and, in
    the entitlement resolver, collapses the blocked set to zero for that capability. It
    reads from one of two sources:

      - Dataverse (default): the reconciled rows in fsi_cbgbillingpolicy and
        fsi_cbgcreditpolicy that CBG-PolicySync maintains. This is the proven path.
      - Platform (-FromPlatform): a live read of the Power Platform billing-policy
        admin API. The PAYG billing-policy endpoint is documented; the credit-policy
        endpoint is UNPROVEN at time of writing, so the credit read is best-effort
        and falls back to the Dataverse rows. See docs/entitlement-contract.md and
        the README "Assumptions & build-time verifications".

    Authentication is managed-identity-first. Supply -AccessToken (Dataverse) and,
    for -FromPlatform, -BillingApiAccessToken (https://api.bap.microsoft.com/) from a
    managed identity or workload identity. An Az.Accounts fallback is provided for
    dev-only use.

.PARAMETER EnvironmentUrl
    The Dataverse environment URL holding the CBG tables
    (for example https://contoso.crm.dynamics.com).

.PARAMETER AccessToken
    A Dataverse bearer token. Managed-identity-first: acquire it from a managed
    identity in the caller and pass it here. When omitted, the cmdlet falls back to
    Get-AzAccessToken (dev-only; requires Az.Accounts and a sign-in).

.PARAMETER FromPlatform
    Read PAYG policies live from the Power Platform billing-policy admin API instead
    of the Dataverse store. The credit-policy live read is unproven and falls back to
    Dataverse.

.PARAMETER BillingApiAccessToken
    Bearer token for the Power Platform billing-policy admin API
    (resource https://api.bap.microsoft.com/). Used only with -FromPlatform.
    Managed-identity-first; falls back to Get-AzAccessToken (dev-only).

.PARAMETER PayAsYouGoCeiling
    Tenant ceiling for PAYG billing policies. Defaults to 50.

.PARAMETER CreditCeiling
    Tenant ceiling for prepaid credit policies. Defaults to 10.

.EXAMPLE
    PS> .\Get-BillingPolicyInventory.ps1 -EnvironmentUrl 'https://contoso.crm.dynamics.com' -AccessToken $token
    Reads both policy objects from the reconciled Dataverse store and reports headroom.

.EXAMPLE
    PS> .\Get-BillingPolicyInventory.ps1 -EnvironmentUrl 'https://contoso.crm.dynamics.com' -AccessToken $dvToken -FromPlatform -BillingApiAccessToken $bapToken
    Reads PAYG policies live from the platform API; credit policies fall back to Dataverse.

.NOTES
    Dataverse logical names are lowercase with no inter-word underscores
    (fsi_cbgbillingpolicy, fsi_cbgcreditpolicy). See docs/dataverse-schema.md.
    Write APIs for credit-policy CRUD and per-agent caps are unproven; this cmdlet is
    read-only and does not attempt any policy mutation.
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateNotNullOrEmpty()]
    [string]$EnvironmentUrl,

    [Parameter()]
    [string]$AccessToken,

    [Parameter()]
    [switch]$FromPlatform,

    [Parameter()]
    [string]$BillingApiAccessToken,

    [Parameter()]
    [ValidateRange(1, 1000)]
    [int]$PayAsYouGoCeiling = 50,

    [Parameter()]
    [ValidateRange(1, 1000)]
    [int]$CreditCeiling = 10
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Power Platform billing-policy admin API resource (BAP).
$script:BillingApiResource = 'https://api.bap.microsoft.com/'

function Get-DataverseAccessToken {
    <#
    .SYNOPSIS
        Resolve a Dataverse bearer token, managed-identity-first.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$ResourceUrl,
        [string]$ProvidedToken
    )

    if (-not [string]::IsNullOrWhiteSpace($ProvidedToken)) {
        return $ProvidedToken
    }

    # legacy: dev-only - replace with a managed-identity-supplied -AccessToken in production
    Write-Verbose 'No token supplied; falling back to Get-AzAccessToken (dev-only).'
    if (-not (Get-Command -Name Get-AzAccessToken -ErrorAction SilentlyContinue)) {
        throw "No token provided and Az.Accounts (Get-AzAccessToken) is not available. Supply a managed-identity token, or install Az.Accounts and sign in."
    }
    $secure = (Get-AzAccessToken -ResourceUrl $ResourceUrl -AsSecureString).Token
    return ($secure | ConvertFrom-SecureString -AsPlainText)
}

function Get-DataverseRecords {
    <#
    .SYNOPSIS
        Read rows from a Dataverse table using logical column names.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$Token,
        [Parameter(Mandatory)][string]$EntitySet,
        [Parameter(Mandatory)][string]$Select
    )

    $uri = "$($BaseUrl.TrimEnd('/'))/api/data/v9.2/$EntitySet`?`$select=$Select"
    $headers = @{
        'Authorization'    = "Bearer $Token"
        'Accept'           = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
    }
    $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
    if ($null -eq $response.value) { return @() }
    return @($response.value)
}

function Get-CbgProperty {
    <#
    .SYNOPSIS
        Read a property safely under Set-StrictMode -Version Latest (missing
        properties return the default instead of throwing).
    #>
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

function ConvertFrom-CbgSpendScopeValue {
    <#
    .SYNOPSIS
        Decode the fsi_cbg_spendscope option-set integer into the connected-surface
        tokens (Chat / SharePoint) the FNF lens and the entitlement resolver use.
    #>
    [CmdletBinding()]
    param([Parameter()][AllowNull()]$Value)
    switch ([string]$Value) {
        '100000000' { return @('Chat') }          # Chat - Credit-eligible
        '100000001' { return @('SharePoint') }    # SharePoint - PAYG-only
        '100000002' { return @('Chat', 'SharePoint') }  # Mixed
        default { return @() }
    }
}

function ConvertFrom-CbgUserScopeValue {
    <#
    .SYNOPSIS
        Decode the fsi_cbg_userscope option-set integer into a user-scope token
        (AllUsers / Group / Unknown).
    #>
    [CmdletBinding()]
    param([Parameter()][AllowNull()]$Value)
    switch ([string]$Value) {
        '100000000' { return 'AllUsers' }   # All users
        '100000001' { return 'Group' }      # Specific security group
        default { return 'Unknown' }
    }
}

function Get-CbgPlatformPolicyScope {
    <#
    .SYNOPSIS
        Best-effort extraction of user scope + connected services from a live
        (UNPROVEN) Power Platform billing-policy object. Tolerates several field
        spellings. Authoritative per-user scope resolution lives in
        Get-CopilotEntitlement.ps1; this is for the inventory report only.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][AllowNull()]$Policy)

    $scope = 'Unknown'
    $groupIds = New-Object System.Collections.Generic.List[string]
    $services = New-Object System.Collections.Generic.List[string]

    if ($null -ne $Policy) {
        $scopeContainer = $Policy
        $props = Get-CbgProperty -InputObject $Policy -Name 'properties'
        if ($null -ne $props) {
            $inner = Get-CbgProperty -InputObject $props -Name 'scope'
            if ($null -ne $inner) { $scopeContainer = $inner } else { $scopeContainer = $props }
        }

        $scopeRaw = $null
        foreach ($k in @('scopeType', 'userScopeType', 'type', 'userScope', 'scope')) {
            $v = Get-CbgProperty -InputObject $scopeContainer -Name $k
            if ($null -ne $v -and $v -is [string]) { $scopeRaw = $v; break }
        }

        foreach ($container in @($scopeContainer, $Policy)) {
            foreach ($gk in @('groupIds', 'groups', 'securityGroups')) {
                $gv = Get-CbgProperty -InputObject $container -Name $gk
                foreach ($g in @($gv)) {
                    if ($null -eq $g) { continue }
                    if ($g -is [string]) {
                        if (-not $groupIds.Contains($g)) { $groupIds.Add($g) }
                    }
                    else {
                        $gid = Get-CbgProperty -InputObject $g -Name 'id'
                        if (-not $gid) { $gid = Get-CbgProperty -InputObject $g -Name 'groupId' }
                        if ($gid -and -not $groupIds.Contains([string]$gid)) { $groupIds.Add([string]$gid) }
                    }
                }
            }
        }

        if ($scopeRaw) {
            if ($scopeRaw -match '(?i)all|tenant|everyone') { $scope = 'AllUsers' }
            elseif ($scopeRaw -match '(?i)specific|group') { $scope = 'Group' }
        }
        if ($scope -eq 'Unknown' -and $groupIds.Count -gt 0) { $scope = 'Group' }

        foreach ($ck in @('connectedServices', 'services', 'serviceTypes', 'capabilities')) {
            $cv = Get-CbgProperty -InputObject $Policy -Name $ck
            if ($null -eq $cv) { $cv = Get-CbgProperty -InputObject $scopeContainer -Name $ck }
            foreach ($c in @($cv)) {
                if ($null -eq $c) { continue }
                $ctext = if ($c -is [string]) { $c } else { [string](Get-CbgProperty -InputObject $c -Name 'name') }
                if ([string]::IsNullOrWhiteSpace($ctext)) { continue }
                if ($ctext -match '(?i)chat' -and -not $services.Contains('Chat')) { $services.Add('Chat') }
                if ($ctext -match '(?i)sharepoint|spo' -and -not $services.Contains('SharePoint')) { $services.Add('SharePoint') }
            }
        }
    }

    return [pscustomobject]@{
        Scope             = $scope
        ScopeGroupIds     = $groupIds.ToArray()
        ConnectedServices = $services.ToArray()
    }
}

function Get-PayAsYouGoInventory {
    <#
    .SYNOPSIS
        Read PAYG billing policies from Dataverse or the platform admin API.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$DataverseToken,
        [switch]$Platform,
        [string]$BillingToken
    )

    if ($Platform) {
        $token = Get-DataverseAccessToken -ResourceUrl $script:BillingApiResource -ProvidedToken $BillingToken
        $uri = "$($script:BillingApiResource.TrimEnd('/'))/providers/Microsoft.BusinessAppPlatform/billingPolicies?api-version=2022-03-01-preview"
        $headers = @{ 'Authorization' = "Bearer $token"; 'Accept' = 'application/json' }
        Write-Verbose "Reading PAYG billing policies from platform API: $uri"
        $response = Invoke-RestMethod -Method Get -Uri $uri -Headers $headers
        $rows = @()
        $value = Get-CbgProperty -InputObject $response -Name 'value'
        if ($null -ne $value) {
            foreach ($p in @($value)) {
                $instrument = Get-CbgProperty -InputObject $p -Name 'billingInstrument'
                $statusVal = Get-CbgProperty -InputObject $p -Name 'status'
                $scopeInfo = Get-CbgPlatformPolicyScope -Policy $p
                $rows += [pscustomobject]@{
                    Name                = Get-CbgProperty -InputObject $p -Name 'name'
                    PolicyType          = 'PAYG'
                    AzureSubscriptionId = Get-CbgProperty -InputObject $instrument -Name 'resourceGroup'
                    IsConnected         = ($null -ne $statusVal -and "$statusVal" -eq 'EnabledForFlowsAndPowerApps')
                    Scope               = $scopeInfo.Scope
                    ScopeGroupIds       = @($scopeInfo.ScopeGroupIds)
                    ConnectedServices   = @($scopeInfo.ConnectedServices)
                    Source              = 'platform'
                }
            }
        }
        return $rows
    }

    # Proven path: reconciled Dataverse store.
    $select = 'fsi_name,fsi_policytype,fsi_azuresubscriptionid,fsi_isconnected,fsi_spendscope,fsi_userscope,fsi_assignedgroupid,fsi_policycountsnapshot,fsi_lastsyncedat'
    $records = Get-DataverseRecords -BaseUrl $BaseUrl -Token $DataverseToken -EntitySet 'fsi_cbgbillingpolicies' -Select $select
    $rows = @()
    foreach ($r in $records) {
        $userScope = ConvertFrom-CbgUserScopeValue -Value (Get-CbgProperty -InputObject $r -Name 'fsi_userscope')
        $assignedGroupId = Get-CbgProperty -InputObject $r -Name 'fsi_assignedgroupid'
        $scopeGroupIds = @()
        if ($userScope -eq 'Group' -and -not [string]::IsNullOrWhiteSpace($assignedGroupId)) {
            $scopeGroupIds = @([string]$assignedGroupId)
        }
        $rows += [pscustomobject]@{
            Name                = Get-CbgProperty -InputObject $r -Name 'fsi_name'
            PolicyType          = 'PAYG'
            AzureSubscriptionId = Get-CbgProperty -InputObject $r -Name 'fsi_azuresubscriptionid'
            IsConnected         = [bool](Get-CbgProperty -InputObject $r -Name 'fsi_isconnected' -Default $false)
            Scope               = $userScope
            ScopeGroupIds       = $scopeGroupIds
            ConnectedServices   = @(ConvertFrom-CbgSpendScopeValue -Value (Get-CbgProperty -InputObject $r -Name 'fsi_spendscope'))
            Source              = 'dataverse'
        }
    }
    return $rows
}

function Get-CreditPolicyInventory {
    <#
    .SYNOPSIS
        Read prepaid credit policies from Dataverse. The live platform read is
        unproven, so this always uses the reconciled store.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$BaseUrl,
        [Parameter(Mandatory)][string]$DataverseToken,
        [switch]$Platform
    )

    if ($Platform) {
        # The credit-policy admin API is UNPROVEN at time of writing; fall back to the
        # reconciled Dataverse store rather than guess an endpoint shape.
        Write-Warning 'Credit-policy platform API is unproven; reading reconciled Dataverse rows instead.'
    }

    $select = 'fsi_name,fsi_policytype,fsi_creditpolicyid,fsi_prepaidcreditpack,fsi_creditsconsumed,fsi_hardstopenabled,fsi_surfacescope,fsi_policycountsnapshot,fsi_lastsyncedat'
    $records = Get-DataverseRecords -BaseUrl $BaseUrl -Token $DataverseToken -EntitySet 'fsi_cbgcreditpolicies' -Select $select
    $rows = @()
    foreach ($r in $records) {
        $rows += [pscustomobject]@{
            Name           = $r.fsi_name
            PolicyType     = 'Credit'
            CreditPolicyId = $r.fsi_creditpolicyid
            HardStop       = [bool]$r.fsi_hardstopenabled
            Source         = 'dataverse'
        }
    }
    return $rows
}

# --- Main (runs only on direct invocation; dot-sourcing for tests skips this) ---
if ($MyInvocation.InvocationName -ne '.') {
    $dataverseToken = Get-DataverseAccessToken -ResourceUrl $EnvironmentUrl -ProvidedToken $AccessToken

    $payg = @(Get-PayAsYouGoInventory -BaseUrl $EnvironmentUrl -DataverseToken $dataverseToken -Platform:$FromPlatform -BillingToken $BillingApiAccessToken)
    $credit = @(Get-CreditPolicyInventory -BaseUrl $EnvironmentUrl -DataverseToken $dataverseToken -Platform:$FromPlatform)

    $paygCount = $payg.Count
    $creditCount = $credit.Count

    $inventory = [pscustomobject]@{
        PayAsYouGo  = [pscustomobject]@{
            Count     = $paygCount
            Ceiling   = $PayAsYouGoCeiling
            Headroom  = ($PayAsYouGoCeiling - $paygCount)
            AtCeiling = ($paygCount -ge $PayAsYouGoCeiling)
            Policies  = $payg
        }
        Credit      = [pscustomobject]@{
            Count     = $creditCount
            Ceiling   = $CreditCeiling
            Headroom  = ($CreditCeiling - $creditCount)
            AtCeiling = ($creditCount -ge $CreditCeiling)
            Policies  = $credit
        }
        Source      = $(if ($FromPlatform) { 'platform-with-dataverse-fallback' } else { 'dataverse' })
        EvaluatedAt = (Get-Date).ToUniversalTime().ToString('o')
    }

    Write-Output $inventory

    if ($inventory.PayAsYouGo.AtCeiling) {
        Write-Warning "PAYG billing policies are at the tenant ceiling ($PayAsYouGoCeiling); no headroom for additional policies."
    }
    if ($inventory.Credit.AtCeiling) {
        Write-Warning "Credit policies are at the tenant ceiling ($CreditCeiling); no headroom for additional policies."
    }
}
