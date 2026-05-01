#Requires -Version 7.0
#Requires -Modules Az.Accounts, Az.KeyVault, Az.Resources
<#
.SYNOPSIS
    Provisions Key Vault and stores the lab client secret. Idempotent.

.DESCRIPTION
    Creates the Key Vault if absent (RBAC mode), stores
    `$env:MCM_LAB_LAST_SECRET` (set by 01_New-AppRegistration.ps1) under the
    configured secret name, and grants the runner the Key Vault Secrets User
    role via Azure RBAC. If the env var is empty, the secret in Key Vault is
    left as-is (idempotent re-run after a no-rotation app reg call).

.PARAMETER ConfigPath
    Path to lab-config.json.

.PARAMETER SkipKeyVault
    Skip Key Vault creation and secret upload entirely. Useful when the lab
    operator already has a Key Vault and only wants to validate role assignment.

.NOTES
    Lab dry-run step 2 of 7. Solution: message-center-monitor v2.5.0+
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()] [string] $ConfigPath,
    [Parameter()] [switch] $SkipKeyVault,
    [Parameter()] [switch] $AllowProduction
)

$ErrorActionPreference = 'Stop'
. $PSScriptRoot/lib/Write-LabLog.ps1
$null = Initialize-LabLog -StepName '02-key-vault'

if ($SkipKeyVault) {
    Write-LabLog -Level Warn -Message "-SkipKeyVault set. Skipping Key Vault provisioning. Smoke test will require an already-populated secret reachable by the runner."
    return
}

$cfg   = Get-LabConfig -ConfigPath $ConfigPath
Assert-NonProdAcknowledgement -Config $cfg -AllowProduction:$AllowProduction
$state = Get-LabState
if (-not $state.appRegistration) {
    Write-LabLog -Level Error -Message "No appRegistration block in lab-state.json. Run 01_New-AppRegistration.ps1 first." -Throw
}

# --- 1. Az login -------------------------------------------------------------
Write-LabLog -Level Info -Message "Connecting to Azure (subscription=$($cfg.azure.subscriptionId))..."
$az = Get-AzContext -ErrorAction SilentlyContinue
if (-not $az -or $az.Subscription.Id -ne $cfg.azure.subscriptionId) {
    Connect-AzAccount -Subscription $cfg.azure.subscriptionId -Tenant $cfg.tenant.tenantId -ErrorAction Stop | Out-Null
}
Set-AzContext -SubscriptionId $cfg.azure.subscriptionId -ErrorAction Stop | Out-Null

# --- 2. Resource group -------------------------------------------------------
$rg = Get-AzResourceGroup -Name $cfg.azure.resourceGroup -ErrorAction SilentlyContinue
if (-not $rg) {
    Write-LabLog -Level Info -Message "Creating resource group '$($cfg.azure.resourceGroup)' in $($cfg.azure.region)..."
    if ($PSCmdlet.ShouldProcess($cfg.azure.resourceGroup, 'New-AzResourceGroup')) {
        $rg = New-AzResourceGroup -Name $cfg.azure.resourceGroup -Location $cfg.azure.region -ErrorAction Stop
    }
} else {
    Write-LabLog -Level Info -Message "Resource group '$($cfg.azure.resourceGroup)' already exists."
}

# --- 3. Key Vault (RBAC mode) ------------------------------------------------
$kv = Get-AzKeyVault -VaultName $cfg.keyVault.name -ErrorAction SilentlyContinue
if (-not $kv) {
    Write-LabLog -Level Info -Message "Creating Key Vault '$($cfg.keyVault.name)'..."
    if ($PSCmdlet.ShouldProcess($cfg.keyVault.name, 'New-AzKeyVault')) {
        $kv = New-AzKeyVault `
            -Name $cfg.keyVault.name `
            -ResourceGroupName $cfg.azure.resourceGroup `
            -Location $cfg.azure.region `
            -EnableRbacAuthorization `
            -EnabledForTemplateDeployment:$false `
            -EnableSoftDelete `
            -SoftDeleteRetentionInDays 7 `
            -Sku Standard `
            -ErrorAction Stop
    }
} else {
    Write-LabLog -Level Info -Message "Key Vault '$($cfg.keyVault.name)' already exists."
    if (-not $kv.EnableRbacAuthorization) {
        Write-LabLog -Level Warn -Message "Key Vault is in access policy mode, not RBAC. This script grants RBAC; access policy users may need separate access policy entries."
    }
}

# --- 4. RBAC: Key Vault Secrets User for the runner -------------------------
$kvScope = $kv.ResourceId
$runnerObjectId = (Get-AzADUser -UserPrincipalName $cfg.operator.runnerUpn -ErrorAction SilentlyContinue).Id
if (-not $runnerObjectId) {
    Write-LabLog -Level Warn -Message "Could not resolve runner UPN '$($cfg.operator.runnerUpn)' to a directory object; skipping RBAC grant. Add manually if needed."
} else {
    $existing = Get-AzRoleAssignment -ObjectId $runnerObjectId -Scope $kvScope -RoleDefinitionName 'Key Vault Secrets User' -ErrorAction SilentlyContinue
    if (-not $existing) {
        Write-LabLog -Level Info -Message "Granting 'Key Vault Secrets User' to $($cfg.operator.runnerUpn) on $kvScope..."
        if ($PSCmdlet.ShouldProcess($kvScope, 'New-AzRoleAssignment')) {
            New-AzRoleAssignment -ObjectId $runnerObjectId -Scope $kvScope -RoleDefinitionName 'Key Vault Secrets User' -ErrorAction Stop | Out-Null
        }
    } else {
        Write-LabLog -Level Info -Message "Runner already has 'Key Vault Secrets User' on this vault."
    }
}

# --- 5. Store / refresh the client secret -----------------------------------
# Prefer the .secret-handoff file written by 01_New-AppRegistration.ps1 over
# any process env (the env approach broke when scripts ran in separate pwsh
# processes - council finding BLOCK 1).
$handoff = Get-LabHandoffSecret
$secretValueToStore = if (-not [string]::IsNullOrEmpty($handoff)) { $handoff }
                     elseif (-not [string]::IsNullOrEmpty($env:MCM_LAB_LAST_SECRET)) { $env:MCM_LAB_LAST_SECRET }
                     else { $null }

if ([string]::IsNullOrEmpty($secretValueToStore)) {
    Write-LabLog -Level Warn -Message "No new secret value available (.secret-handoff missing AND `$env:MCM_LAB_LAST_SECRET empty). Either 01_New-AppRegistration.ps1 reused an existing secret OR was not run. Key Vault secret is left as-is. If KV is empty/stale, re-run 01 with -ForceRotate."
} else {
    Write-LabLog -Level Info -Message "Storing client secret as '$($cfg.keyVault.secretName)' in Key Vault..."
    if ($PSCmdlet.ShouldProcess("$($cfg.keyVault.name)/$($cfg.keyVault.secretName)", 'Set-AzKeyVaultSecret')) {
        $secVal = ConvertTo-SecureString $secretValueToStore -AsPlainText -Force
        Set-AzKeyVaultSecret -VaultName $cfg.keyVault.name -Name $cfg.keyVault.secretName -SecretValue $secVal -ErrorAction Stop | Out-Null
    }
    # Scrub from process env in case it was the source.
    $env:MCM_LAB_LAST_SECRET = ''
    $secretValueToStore      = $null
    Write-LabLog -Level Info -Message "  Secret stored. Handoff file consumed and deleted."
}

# --- 6. Persist state --------------------------------------------------------
$state | Add-Member -NotePropertyName 'subscriptionId' -NotePropertyValue $cfg.azure.subscriptionId -Force
$state | Add-Member -NotePropertyName 'resourceGroup'  -NotePropertyValue $cfg.azure.resourceGroup  -Force
$state | Add-Member -NotePropertyName 'keyVault' -NotePropertyValue ([pscustomobject]@{
    name       = $kv.VaultName
    resourceId = $kv.ResourceId
    vaultUri   = $kv.VaultUri
    secretName = $cfg.keyVault.secretName
}) -Force
Save-LabState -State $state

Write-LabLog -Level Info -Message "Key Vault ready. Next: pwsh ./03_Deploy-Schema.ps1"
