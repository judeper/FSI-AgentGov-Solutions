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
    each ceiling. It reads from one of two sources:

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
        if ($null -ne $response.value) {
            foreach ($p in $response.value) {
                $rows += [pscustomobject]@{
                    Name                 = $p.name
                    PolicyType           = 'PAYG'
                    AzureSubscriptionId  = $p.billingInstrument.resourceGroup
                    IsConnected          = ($null -ne $p.status -and $p.status -eq 'EnabledForFlowsAndPowerApps')
                    Source               = 'platform'
                }
            }
        }
        return $rows
    }

    # Proven path: reconciled Dataverse store.
    $select = 'fsi_name,fsi_policytype,fsi_azuresubscriptionid,fsi_isconnected,fsi_spendscope,fsi_policycountsnapshot,fsi_lastsyncedat'
    $records = Get-DataverseRecords -BaseUrl $BaseUrl -Token $DataverseToken -EntitySet 'fsi_cbgbillingpolicies' -Select $select
    $rows = @()
    foreach ($r in $records) {
        $rows += [pscustomobject]@{
            Name                = $r.fsi_name
            PolicyType          = 'PAYG'
            AzureSubscriptionId = $r.fsi_azuresubscriptionid
            IsConnected         = [bool]$r.fsi_isconnected
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

# --- Main ---
$dataverseToken = Get-DataverseAccessToken -ResourceUrl $EnvironmentUrl -ProvidedToken $AccessToken

$payg = @(Get-PayAsYouGoInventory -BaseUrl $EnvironmentUrl -DataverseToken $dataverseToken -Platform:$FromPlatform -BillingToken $BillingApiAccessToken)
$credit = @(Get-CreditPolicyInventory -BaseUrl $EnvironmentUrl -DataverseToken $dataverseToken -Platform:$FromPlatform)

$paygCount = $payg.Count
$creditCount = $credit.Count

$inventory = [pscustomobject]@{
    PayAsYouGo = [pscustomobject]@{
        Count        = $paygCount
        Ceiling      = $PayAsYouGoCeiling
        Headroom     = ($PayAsYouGoCeiling - $paygCount)
        AtCeiling    = ($paygCount -ge $PayAsYouGoCeiling)
        Policies     = $payg
    }
    Credit     = [pscustomobject]@{
        Count        = $creditCount
        Ceiling      = $CreditCeiling
        Headroom     = ($CreditCeiling - $creditCount)
        AtCeiling    = ($creditCount -ge $CreditCeiling)
        Policies     = $credit
    }
    Source     = $(if ($FromPlatform) { 'platform-with-dataverse-fallback' } else { 'dataverse' })
    EvaluatedAt = (Get-Date).ToUniversalTime().ToString('o')
}

Write-Output $inventory

if ($inventory.PayAsYouGo.AtCeiling) {
    Write-Warning "PAYG billing policies are at the tenant ceiling ($PayAsYouGoCeiling); no headroom for additional policies."
}
if ($inventory.Credit.AtCeiling) {
    Write-Warning "Credit policies are at the tenant ceiling ($CreditCeiling); no headroom for additional policies."
}
