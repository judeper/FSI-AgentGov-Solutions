#Requires -Version 7.0
<#
.SYNOPSIS
    State-driven idempotent teardown of message-center-monitor lab deployment.

.DESCRIPTION
    Reads lab-state.json and removes ONLY resources recorded there. Refuses to
    touch resources not in state unless -ForceExternalResource is set. Order:
      env vars + connection refs (best-effort) -> Dataverse table ->
      app user disable -> Graph appRoleAssignments + oauth2PermissionGrants ->
      app reg + SP -> Key Vault.

    404 / NotFound on any individual delete is treated as success (idempotent).

.PARAMETER ConfigPath
    Path to lab-config.json.

.PARAMETER DryRun
    Print what would be deleted without making changes.

.PARAMETER ForceExternalResource
    Allow deletion of named resources that are NOT in lab-state.json (e.g.,
    after the state file was lost).

.PARAMETER KeepKeyVault
    Skip Key Vault deletion. Recommended for shared lab Key Vaults.

.PARAMETER RemoveEnvironment
    Also delete the Power Platform environment recorded in
    lab-config.json (powerPlatform.environmentId). Off by default to protect
    shared lab envs. Only the env created by lab/00b_New-PaygEnvironment.ps1
    should be deleted with this flag.

.NOTES
    Lab dry-run step 99 of 99. Solution: message-center-monitor v2.5.0+
#>
[CmdletBinding(SupportsShouldProcess, ConfirmImpact='High')]
param(
    [Parameter()] [string] $ConfigPath,
    [Parameter()] [switch] $DryRun,
    [Parameter()] [switch] $ForceExternalResource,
    [Parameter()] [switch] $KeepKeyVault,
    [Parameter()] [switch] $RemoveEnvironment,
    [Parameter()] [switch] $AllowProduction
)

$ErrorActionPreference = 'Stop'
. $PSScriptRoot/lib/Write-LabLog.ps1
$null = Initialize-LabLog -StepName '99-teardown'

$cfg = Get-LabConfig -ConfigPath $ConfigPath
Assert-NonProdAcknowledgement -Config $cfg -AllowProduction:$AllowProduction
# lab-state.json lives next to this script in lab/.
$statePath = Join-Path $PSScriptRoot 'lab-state.json'

$state = $null
if (Test-Path -LiteralPath $statePath) {
    $state = Get-Content -LiteralPath $statePath -Raw | ConvertFrom-Json
} else {
    Write-LabLog -Level Warn -Message "No lab-state.json found at '$statePath'."
    if (-not $ForceExternalResource) {
        Write-LabLog -Level Error -Message "Refusing to delete unknown resources. Pass -ForceExternalResource to delete by name from lab-config.json." -Throw
    }
}

function Invoke-LabTeardownAction([scriptblock]$action, [string]$desc) {
    if ($DryRun) {
        Write-LabLog -Level Info -Message "[DRY-RUN] $desc"
        return
    }
    try {
        & $action
        Write-LabLog -Level Info -Message "  $desc [OK]"
    } catch {
        if ($_.Exception.Message -match '404|NotFound|does not exist') {
            Write-LabLog -Level Info -Message "  $desc [already gone]"
        } else {
            Write-LabLog -Level Warn -Message "  $desc FAILED: $($_.Exception.Message)"
        }
    }
}

# --- Phase 1: Dataverse cleanup (env vars, connection refs, table) -----------
if ($state.dataverse -or $ForceExternalResource) {
    $envUrl = ($state.dataverse.environmentUrl ?? $cfg.powerPlatform.environmentUrl).TrimEnd('/')
    if (-not [string]::IsNullOrEmpty($envUrl)) {
        Write-LabLog -Level Info -Message "Dataverse cleanup at $envUrl..."

        try {
            $adminTok = (Get-AzAccessToken -ResourceUrl $envUrl -ErrorAction Stop).Token
            $hdr = @{
                Authorization      = "Bearer $adminTok"
                'OData-MaxVersion' = '4.0'
                'OData-Version'    = '4.0'
                Accept             = 'application/json'
                'Content-Type'     = 'application/json'
            }
            $api = "$envUrl/api/data/v9.2"

            # Env-var values + definitions for the 6 fsi_MCM_* vars created by
            # scripts/create_mcm_environment_variables.py - the source of truth.
            $envVarNames = @(
                'fsi_MCM_PollingIntervalDays',
                'fsi_MCM_NotifySeverities',
                'fsi_MCM_TeamsTeamId',
                'fsi_MCM_TeamsChannelId',
                'fsi_MCM_DataverseUrl',
                'fsi_MCM_KeyVaultSecretName'
            )
            foreach ($name in $envVarNames) {
                $defs = Invoke-RestMethod -Uri "$api/environmentvariabledefinitions?`$filter=schemaname eq '$name'&`$select=environmentvariabledefinitionid" -Headers $hdr -Method Get -ErrorAction SilentlyContinue
                foreach ($d in $defs.value) {
                    Invoke-LabTeardownAction { Invoke-RestMethod -Uri "$api/environmentvariabledefinitions($($d.environmentvariabledefinitionid))" -Headers $hdr -Method Delete -ErrorAction Stop | Out-Null } "Delete env var def $name"
                }
            }

            # Disable application user (cannot delete in Dataverse).
            if ($state.dataverse.applicationUserId) {
                $userId = $state.dataverse.applicationUserId
                Invoke-LabTeardownAction { Invoke-RestMethod -Uri "$api/systemusers($userId)" -Headers $hdr -Method Patch -Body (@{ isdisabled = $true } | ConvertTo-Json) -ErrorAction Stop | Out-Null } "Disable Dataverse application user $userId"
            }

            # Drop the table.
            Invoke-LabTeardownAction {
                $meta = Invoke-RestMethod -Uri "$api/EntityDefinitions(LogicalName='fsi_messagecenterlog')?`$select=MetadataId" -Headers $hdr -Method Get -ErrorAction Stop
                Invoke-RestMethod -Uri "$api/EntityDefinitions($($meta.MetadataId))" -Headers $hdr -Method Delete -ErrorAction Stop | Out-Null
            } "Delete fsi_messagecenterlog table"
        } catch {
            Write-LabLog -Level Warn -Message "Dataverse cleanup partial: $($_.Exception.Message)"
        }
    }
}

# --- Phase 2: Microsoft Entra cleanup (app reg + SP) -------------------------
if ($state.appRegistration -or $ForceExternalResource) {
    Write-LabLog -Level Info -Message "Microsoft Entra cleanup..."
    try {
        Connect-MgGraph -Scopes 'Application.ReadWrite.All','AppRoleAssignment.ReadWrite.All','DelegatedPermissionGrant.ReadWrite.All' -TenantId $cfg.tenant.tenantId -NoWelcome -ErrorAction Stop | Out-Null

        $appObjId = $state.appRegistration.objectId
        $spObjId  = $state.appRegistration.servicePrincipalObjectId

        if (-not $appObjId -and $ForceExternalResource) {
            $apps = Get-MgApplication -Filter "displayName eq '$($cfg.appRegistration.displayName)'" -ErrorAction SilentlyContinue
            if ($apps) { $appObjId = ($apps | Select-Object -First 1).Id }
        }

        if ($spObjId) {
            # Remove appRoleAssignments + oauth2PermissionGrants tied to this SP.
            $assigns = Get-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $spObjId -ErrorAction SilentlyContinue
            foreach ($a in $assigns) {
                Invoke-LabTeardownAction { Remove-MgServicePrincipalAppRoleAssignment -ServicePrincipalId $spObjId -AppRoleAssignmentId $a.Id -ErrorAction Stop } "Remove appRoleAssignment $($a.Id)"
            }
            $grants = Get-MgOauth2PermissionGrant -Filter "clientId eq '$spObjId'" -ErrorAction SilentlyContinue
            foreach ($g in $grants) {
                Invoke-LabTeardownAction { Remove-MgOauth2PermissionGrant -OAuth2PermissionGrantId $g.Id -ErrorAction Stop } "Remove oauth2PermissionGrant $($g.Id)"
            }
            Invoke-LabTeardownAction { Remove-MgServicePrincipal -ServicePrincipalId $spObjId -ErrorAction Stop } "Remove service principal $spObjId"
        }

        if ($appObjId) {
            Invoke-LabTeardownAction { Remove-MgApplication -ApplicationId $appObjId -ErrorAction Stop } "Remove app registration $appObjId"
        }
    } finally {
        try { Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null } catch {
            Write-Verbose ("Microsoft Graph disconnect during lab teardown for app {0} failed (non-fatal): {1}" -f $appObjId, $_.Exception.Message)
        }
    }
}

# --- Phase 3: Key Vault ------------------------------------------------------
if (-not $KeepKeyVault -and ($state.keyVault -or $ForceExternalResource)) {
    Write-LabLog -Level Info -Message "Key Vault cleanup..."
    $kvName = ($state.keyVault.name ?? $cfg.keyVault.name)
    if ($kvName) {
        try {
            Set-AzContext -SubscriptionId ($state.subscriptionId ?? $cfg.azure.subscriptionId) -ErrorAction Stop | Out-Null
            Invoke-LabTeardownAction { Remove-AzKeyVault -VaultName $kvName -Force -ErrorAction Stop } "Soft-delete Key Vault $kvName"
            Invoke-LabTeardownAction { Remove-AzKeyVault -VaultName $kvName -InRemovedState -Location ($state.azure.region ?? $cfg.azure.region) -Force -ErrorAction Stop } "Purge soft-deleted Key Vault $kvName"
        } catch {
            Write-LabLog -Level Warn -Message "Key Vault cleanup partial: $($_.Exception.Message)"
        }
    }
}

# --- Phase 4: State file ------------------------------------------------------
if (-not $DryRun -and (Test-Path -LiteralPath $statePath)) {
    Move-Item -LiteralPath $statePath -Destination "$statePath.deleted-$((Get-Date -AsUTC).ToString('yyyyMMddTHHmmssZ'))"
    Write-LabLog -Level Info -Message "Renamed lab-state.json to a .deleted-<ts> suffix; remove manually when satisfied."
}

# --- Phase 5: Power Platform environment (opt-in) ----------------------------
# Tears down the env created by lab/00b_New-PaygEnvironment.ps1. Off by default
# so a forgotten -RemoveEnvironment flag never blasts a shared environment.
if ($RemoveEnvironment) {
    $envIdToDelete = $cfg.powerPlatform.environmentId
    if (-not $envIdToDelete -or $envIdToDelete -eq '') {
        Write-LabLog -Level Warn -Message "No powerPlatform.environmentId in lab-config.json. Nothing to delete."
    } else {
        Write-LabLog -Level Info -Message "Deleting Power Platform env $envIdToDelete..."
        Invoke-LabTeardownAction {
            $bapTok = az account get-access-token --resource 'https://api.bap.microsoft.com' --query accessToken -o tsv 2>$null
            if (-not $bapTok) { throw "az CLI not authenticated. Run: az login --tenant $($cfg.tenant.tenantId)" }
            $hdr = @{ Authorization = "Bearer $bapTok"; 'Content-Type' = 'application/json' }
            $body = '{"code":"User","message":"lab/99_Remove-LabDeployment teardown"}'
            Invoke-WebRequest -Method DELETE `
                -Uri "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/$envIdToDelete`?api-version=2023-06-01" `
                -Headers $hdr -Body $body -ErrorAction Stop | Out-Null
        } "Delete Power Platform environment $envIdToDelete"
    }
}

Write-LabLog -Level Info -Message "Teardown complete."
