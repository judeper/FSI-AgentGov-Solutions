#Requires -Version 7.0
<#
.SYNOPSIS
    Creates a Sandbox Power Platform environment with Dataverse, billed via an
    existing Power Platform PAYG billing policy. Idempotent: returns the
    existing env if one with the same displayName already exists.

.DESCRIPTION
    Single REST call to the BAP environments endpoint that combines:
      - environmentSku=Sandbox
      - databaseType=CommonDataService
      - billingPolicy.id (PAYG policy GUID; routes Dataverse meters to Azure)
      - linkedEnvironmentMetadata (Dataverse provisioning details)

    This is the only known fully-automated path for tenants whose prepaid
    Dataverse pool is exhausted. Adding Dataverse to an already-created shell
    via provisionInstance does NOT honor a billing policy (the
    provisionInstance DTO has no billingPolicy field), so the prepaid pool
    capacity gate fires and the call returns 409 OverCapacity_StorageDriven.

    Prerequisites:
      - az CLI installed and authenticated as a Power Platform Administrator
      - An existing Power Platform PAYG billing policy backed by an Azure
        subscription Microsoft.PowerPlatform/accounts resource whose product
        scope covers Dataverse (verify in PPAC > Licensing > the policy detail
        > Power Platform products list)

    Source pattern: microsoft/terraform-provider-power-platform
        internal/services/environment/api_environment.go:468
        internal/services/environment/models.go:115,150
        internal/constants/constants.go (BAP_API_VERSION = "2023-06-01")

.PARAMETER ConfigPath
    Path to lab-config.json. Defaults to ./lab-config.json relative to this script.

.PARAMETER DisplayName
    Environment display name. Defaults to lab-config powerPlatform.displayName
    if set, otherwise "FSI-MCM-PocDryRun".

.PARAMETER DomainName
    Dataverse subdomain (becomes <subdomain>.crm.dynamics.com). Defaults to a
    random unique value. Must be globally unique across the Dataverse tenant.

.PARAMETER BillingPolicyId
    GUID of an existing PAYG billing policy. If not provided, the script picks
    the first Enabled tenant-owned policy returned by the licensing API and
    writes the chosen GUID to lab-config.json for re-runs.

.PARAMETER Region
    BAP region (a.k.a. "location"). Defaults to "unitedstates".

.PARAMETER WriteConfig
    Write the resolved environmentId + environmentUrl + billingPolicyId back to
    lab-config.json. Default true. Pass -WriteConfig:$false for dry-runs.

.EXAMPLE
    pwsh ./00b_New-PaygEnvironment.ps1
    Use lab-config.json values; create env if not already present.

.EXAMPLE
    pwsh ./00b_New-PaygEnvironment.ps1 -DisplayName "MyTestEnv" -DomainName "mytestenv-001"
    Override display name and Dataverse subdomain.

.NOTES
    Cleanup: removing the env requires a DELETE on
        https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/{envId}?api-version=2023-06-01
    with body {"code":"User","message":"..."}. The lab/99_Remove-LabDeployment.ps1
    script handles this when run with -RemoveEnvironment.

    This script does NOT bill anything by itself. The env it creates incurs
    Azure charges only for actual Dataverse storage/requests usage beyond the
    PAYG-included 1 GB. Idle empty envs cost ~$0/day in PAYG mode.
#>
[CmdletBinding()]
param(
    [Parameter()][string]$ConfigPath,
    [Parameter()][string]$DisplayName,
    [Parameter()][string]$DomainName,
    [Parameter()][string]$BillingPolicyId,
    [Parameter()][string]$Region = 'unitedstates',
    [Parameter()][bool]$WriteConfig = $true,
    [Parameter()][switch]$AllowProduction
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. $PSScriptRoot/lib/Write-LabLog.ps1
$null = Initialize-LabLog -StepName '00b-payg-env'

$cfg = Get-LabConfig -ConfigPath $ConfigPath
Assert-NonProdAcknowledgement -Config $cfg -AllowProduction:$AllowProduction
$resolvedConfigPath = if ($ConfigPath) { $ConfigPath } else { Join-Path (Split-Path -Parent $PSScriptRoot) 'message-center-monitor/lab/lab-config.json' }
if (-not $ConfigPath) {
    # Get-LabConfig's default-path logic
    $resolvedConfigPath = Join-Path $PSScriptRoot 'lab-config.json'
}

if (-not $DisplayName) {
    if (($cfg.powerPlatform.PSObject.Properties.Name -contains 'displayName') -and $cfg.powerPlatform.displayName) {
        $DisplayName = $cfg.powerPlatform.displayName
    } else {
        $DisplayName = 'FSI-MCM-PocDryRun'
    }
}

if (-not $DomainName) {
    $DomainName = 'fsi-mcm-' + (Get-Random -Min 1000 -Max 9999)
}

# ---------- Auth ----------
Write-LabLog -Level Info -Message "Verifying az CLI authentication..."
$acctJson = az account show 2>$null
if (-not $acctJson) {
    Write-LabLog -Level Error -Message "az CLI not authenticated. Run: az login --tenant $($cfg.tenant.tenantId)" -Throw
}
$acct = $acctJson | ConvertFrom-Json
if ($acct.tenantId -ne $cfg.tenant.tenantId) {
    Write-LabLog -Level Error -Message "az CLI authenticated to tenant $($acct.tenantId) but lab-config.json expects $($cfg.tenant.tenantId). Run: az login --tenant $($cfg.tenant.tenantId)" -Throw
}
Write-LabLog -Level Info -Message "  az auth: $($acct.user.name) in tenant $($acct.tenantId)"

function Get-BapToken {
    az account get-access-token --resource 'https://api.bap.microsoft.com' --query accessToken -o tsv 2>$null
}
function Get-PpToken {
    az account get-access-token --resource 'https://api.powerplatform.com' --query accessToken -o tsv 2>$null
}

# ---------- Resolve billing policy ----------
Write-LabLog -Level Info -Message "Resolving PAYG billing policy..."
if (-not $BillingPolicyId -and ($cfg.powerPlatform.PSObject.Properties.Name -contains 'billingPolicyId') -and $cfg.powerPlatform.billingPolicyId) {
    $BillingPolicyId = $cfg.powerPlatform.billingPolicyId
    Write-LabLog -Level Info -Message "  Using billingPolicyId from lab-config: $BillingPolicyId"
}

$ppHdr = @{ Authorization = "Bearer $(Get-PpToken)" }
$pols = Invoke-RestMethod -Uri 'https://api.powerplatform.com/licensing/billingPolicies?api-version=2024-10-01' -Headers $ppHdr
$enabled = @($pols.value | Where-Object { $_.status -eq 'Enabled' })
if ($enabled.Count -eq 0) {
    Write-LabLog -Level Error -Message "No Enabled billing policies found in tenant. Create one in PPAC > Licensing > Pay-as-you-go plans before running this script." -Throw
}

if ($BillingPolicyId) {
    $match = $enabled | Where-Object { $_.id -eq $BillingPolicyId } | Select-Object -First 1
    if (-not $match) {
        $names = ($enabled | ForEach-Object { "$($_.name) ($($_.id))" }) -join ', '
        Write-LabLog -Level Error -Message "BillingPolicyId $BillingPolicyId not found or not Enabled. Available: $names" -Throw
    }
} else {
    $match = $enabled[0]
    $BillingPolicyId = $match.id
    Write-LabLog -Level Info -Message "  Auto-selected first Enabled policy: $($match.name) ($BillingPolicyId)"
}
Write-LabLog -Level Info -Message "  Billing policy: $($match.name) ($BillingPolicyId)"
Write-LabLog -Level Info -Message "  Backed by Azure resource: $($match.billingInstrument.id)"

# ---------- Idempotency: check if env already exists ----------
Write-LabLog -Level Info -Message "Checking for existing env with displayName '$DisplayName'..."
$bapHdr = @{ Authorization = "Bearer $(Get-BapToken)" }
$all = Invoke-RestMethod -Uri 'https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2023-06-01' -Headers $bapHdr
$existing = @($all.value | Where-Object { $_.properties.displayName -eq $DisplayName })

if ($existing.Count -gt 1) {
    $ids = ($existing | ForEach-Object { $_.name }) -join ', '
    Write-LabLog -Level Error -Message "Multiple envs found with displayName '$DisplayName'. Aborting to avoid ambiguity. IDs: $ids" -Throw
}

if ($existing.Count -eq 1) {
    $envObj = $existing[0]
    Write-LabLog -Level Info -Message "  Existing env found: $($envObj.name)"
    Write-LabLog -Level Info -Message "    databaseType: $($envObj.properties.databaseType)"
    Write-LabLog -Level Info -Message "    instanceUrl: $($envObj.properties.linkedEnvironmentMetadata.instanceUrl)"
} else {
    Write-LabLog -Level Info -Message "Creating env '$DisplayName' (sandbox + Dataverse + PAYG via $($match.name))..."
    $body = @{
        location = $Region
        properties = @{
            displayName    = $DisplayName
            description    = "Auto-provisioned PAYG sandbox for message-center-monitor (lab/00b_New-PaygEnvironment.ps1)"
            environmentSku = 'Sandbox'
            databaseType   = 'CommonDataService'
            billingPolicy  = @{ id = $BillingPolicyId }
            linkedEnvironmentMetadata = @{
                baseLanguage = 1033
                domainName   = $DomainName
                currency     = @{ code = 'USD' }
                templates    = @()
            }
        }
    } | ConvertTo-Json -Depth 10

    $bapHdr2 = @{ Authorization = "Bearer $(Get-BapToken)"; 'Content-Type' = 'application/json' }
    $resp = Invoke-WebRequest -Method POST `
        -Uri 'https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/environments?api-version=2023-06-01' `
        -Headers $bapHdr2 -Body $body
    if ($resp.StatusCode -ne 202 -and $resp.StatusCode -ne 201) {
        Write-LabLog -Level Error -Message "Unexpected status $($resp.StatusCode) on env create. Body: $($resp.Content)" -Throw
    }

    $opUrl = ($resp.Headers['Location'] | Out-String).Trim()
    if (-not $opUrl) { $opUrl = ($resp.Headers['Operation-Location'] | Out-String).Trim() }
    if (-not $opUrl -and $resp.StatusCode -eq 201) {
        $envObj = $resp.Content | ConvertFrom-Json
    } else {
        Write-LabLog -Level Info -Message "  Polling lifecycle operation: $opUrl"
        $deadline = (Get-Date).AddMinutes(20)
        $finalState = $null
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds 15
            $pollHdr = @{ Authorization = "Bearer $(Get-BapToken)" }
            $poll = Invoke-WebRequest -Method GET -Uri $opUrl -Headers $pollHdr
            $pb = $poll.Content | ConvertFrom-Json
            $st = if ($pb.PSObject.Properties.Name -contains 'state' -and $pb.state) { $pb.state.id }
                  elseif (($pb.PSObject.Properties.Name -contains 'properties') -and $pb.properties -and ($pb.properties.PSObject.Properties.Name -contains 'state')) { $pb.properties.state.id }
                  else { 'Unknown' }
            Write-LabLog -Level Info -Message "    state=$st http=$($poll.StatusCode)"
            if ($st -in @('Succeeded','Failed','Canceled','FailedCreated')) {
                $finalState = $st
                break
            }
            if ($poll.StatusCode -ne 202) { break }
        }
        if ($finalState -and $finalState -ne 'Succeeded') {
            Write-LabLog -Level Error -Message "Env create lifecycle operation ended in state '$finalState'." -Throw
        }
        # Re-pull env detail
        $all2 = Invoke-RestMethod -Uri 'https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2023-06-01' -Headers @{ Authorization = "Bearer $(Get-BapToken)" }
        $envObj = $all2.value | Where-Object { $_.properties.displayName -eq $DisplayName } | Select-Object -First 1
        if (-not $envObj) {
            Write-LabLog -Level Error -Message "Env not found after create. Operation may still be in progress; check $opUrl manually." -Throw
        }
    }
    Write-LabLog -Level Info -Message "  Env created: $($envObj.name)"
    Write-LabLog -Level Info -Message "    databaseType: $($envObj.properties.databaseType)"
    Write-LabLog -Level Info -Message "    instanceUrl: $($envObj.properties.linkedEnvironmentMetadata.instanceUrl)"
}

# ---------- Verify billing policy binding ----------
Write-LabLog -Level Info -Message "Verifying billing policy binding..."
$ppHdr2 = @{ Authorization = "Bearer $(Get-PpToken)" }
$bound = Invoke-RestMethod -Uri "https://api.powerplatform.com/licensing/billingPolicies/$BillingPolicyId/environments?api-version=2024-10-01" -Headers $ppHdr2
$isBound = $bound.value | Where-Object { $_.environmentId -eq $envObj.name }
if (-not $isBound) {
    Write-LabLog -Level Info -Message "  Env not yet bound to policy. Adding via /environments/add..."
    $addBody = @{ environmentIds = @($envObj.name) } | ConvertTo-Json
    $addHdr = @{ Authorization = "Bearer $(Get-PpToken)"; 'Content-Type' = 'application/json' }
    Invoke-RestMethod -Method POST `
        -Uri "https://api.powerplatform.com/licensing/billingPolicies/$BillingPolicyId/environments/add?api-version=2024-10-01" `
        -Headers $addHdr -Body $addBody | Out-Null
    Write-LabLog -Level Info -Message "  Env added to billing policy."
} else {
    Write-LabLog -Level Info -Message "  Env bound to billing policy."
}

# ---------- Write resolved values back to lab-config.json ----------
if ($WriteConfig) {
    Write-LabLog -Level Info -Message "Writing resolved values to lab-config.json..."
    $envUrl = $envObj.properties.linkedEnvironmentMetadata.instanceUrl
    $envId  = $envObj.name
    if ($BillingPolicyId) {
        $cfg.powerPlatform | Add-Member -NotePropertyName 'billingPolicyId' -NotePropertyValue $BillingPolicyId -Force
    }
    if ($DisplayName) {
        $cfg.powerPlatform | Add-Member -NotePropertyName 'displayName' -NotePropertyValue $DisplayName -Force
    }
    $cfg.powerPlatform.environmentId  = $envId
    $cfg.powerPlatform.environmentUrl = $envUrl
    $cfg | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $resolvedConfigPath -Encoding utf8NoBOM
    Write-LabLog -Level Info -Message "  powerPlatform.environmentId  = $envId"
    Write-LabLog -Level Info -Message "  powerPlatform.environmentUrl = $envUrl"
    Write-LabLog -Level Info -Message "  powerPlatform.billingPolicyId = $BillingPolicyId"
}

Write-LabLog -Level Info -Message "Done. Next: pwsh ./01_New-AppRegistration.ps1"
