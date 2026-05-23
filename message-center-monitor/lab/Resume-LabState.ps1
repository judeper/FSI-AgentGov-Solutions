#Requires -Version 7.0
<#
.SYNOPSIS
    Rebuilds lab-state.json by detecting cloud resources that the lab scripts
    previously created. Use this on a fresh workstation to resume an in-progress
    dry-run without re-running lab/01..04 from scratch.

.DESCRIPTION
    `lab-state.json` is gitignored and lives only on the workstation where the
    lab scripts last ran. When the engineer moves to a new machine, the cloud
    resources (Power Platform env, Entra app reg, Azure Key Vault, Dataverse
    application user) still exist but their derived GUIDs are no longer on
    disk. This script queries Microsoft Graph + Azure Resource Manager +
    Dataverse Web API for each resource by NAME (read from lab-config.json),
    then writes a complete lab-state.json that subsequent lab steps and the
    teardown script can consume.

    The script is read-only against cloud resources — it never creates,
    modifies, or deletes anything. If a named resource is missing it prints
    exactly which resolution failed and exits non-zero so the engineer can
    decide whether to recreate the resource via lab/00b..04 or to update
    lab-config.json to point at a different one.

    Auth model: reuses the existing `az` CLI sign-in to mint short-lived
    bearer tokens (Microsoft Graph, BAP, Dataverse) — same pattern the rest of
    the lab scripts use. Run `az login --tenant <tenantId>` first.

.PARAMETER ConfigPath
    Path to lab-config.json. Defaults to ./lab-config.json relative to this
    script.

.PARAMETER StatePath
    Path to write lab-state.json. Defaults to ./lab-state.json relative to
    this script.

.PARAMETER Force
    Overwrite lab-state.json without prompting if it already exists.

.EXAMPLE
    pwsh ./Resume-LabState.ps1
    Rebuilds lab-state.json from cloud resources using the names in lab-config.json.

.EXAMPLE
    pwsh ./Resume-LabState.ps1 -Force
    Same, but overwrites any existing lab-state.json silently.

.NOTES
    Solution: message-center-monitor v2.5.0+
    See AGENTS.md "§ 4 Resume on a new machine" for the full bootstrap flow.
#>
[CmdletBinding()]
param(
    [Parameter()] [string] $ConfigPath,
    [Parameter()] [string] $StatePath,
    [Parameter()] [switch] $Force
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

. $PSScriptRoot/lib/Write-LabLog.ps1
$null = Initialize-LabLog -StepName '00c-resume-state'

$cfg = Get-LabConfig -ConfigPath $ConfigPath
if (-not $StatePath) { $StatePath = Join-Path $PSScriptRoot 'lab-state.json' }

if (Test-Path -LiteralPath $StatePath -PathType Leaf -ErrorAction SilentlyContinue) {
    if (-not $Force) {
        Write-LabLog -Level Warn -Message "lab-state.json already exists at '$StatePath'. Pass -Force to overwrite. Aborting." -Throw
    }
    Write-LabLog -Level Info -Message "Overwriting existing lab-state.json at '$StatePath' (-Force)..."
}

# ---------- 1. Verify az CLI auth ----------
Write-LabLog -Level Info -Message "Verifying az CLI sign-in..."
$acctJson = az account show 2>$null
if (-not $acctJson) {
    Write-LabLog -Level Error -Message "az CLI is not signed in. Run: az login --tenant $($cfg.tenant.tenantId)" -Throw
}
$acct = $acctJson | ConvertFrom-Json
if ($acct.tenantId -ne $cfg.tenant.tenantId) {
    Write-LabLog -Level Error -Message "az CLI authenticated to tenant $($acct.tenantId), lab-config.json expects $($cfg.tenant.tenantId). Run: az login --tenant $($cfg.tenant.tenantId)" -Throw
}
Write-LabLog -Level Info -Message "  az: $($acct.user.name) in $($acct.tenantId)"

function Get-AccessTokenForResource {
    [CmdletBinding()]
    param([Parameter(Mandatory)] [string] $Resource)
    $tok = az account get-access-token --resource $Resource --tenant $cfg.tenant.tenantId --query accessToken -o tsv 2>$null
    if (-not $tok) {
        Write-LabLog -Level Error -Message "Failed to mint a bearer token for resource '$Resource'. Confirm az CLI auth is valid." -Throw
    }
    return $tok
}

# ---------- 2. Resolve the Entra app registration ----------
Write-LabLog -Level Info -Message "Resolving Entra app registration '$($cfg.appRegistration.displayName)'..."
$graphTok = Get-AccessTokenForResource -Resource 'https://graph.microsoft.com'
$graphHdr = @{ Authorization = "Bearer $graphTok"; Accept = 'application/json' }
$dn = [uri]::EscapeDataString($cfg.appRegistration.displayName)
$appResp = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/applications?`$filter=displayName eq '$dn'&`$select=id,appId,displayName,passwordCredentials" -Headers $graphHdr -Method Get -ErrorAction Stop
$apps = @($appResp.value)
if ($apps.Count -eq 0) {
    Write-LabLog -Level Error -Message "No app registration found with displayName '$($cfg.appRegistration.displayName)'. Run lab/01_New-AppRegistration.ps1 to create it, or edit lab-config.json to point at the correct displayName." -Throw
}
if ($apps.Count -gt 1) {
    $ids = ($apps | ForEach-Object { $_.id }) -join ', '
    Write-LabLog -Level Error -Message "Found $($apps.Count) app registrations with displayName '$($cfg.appRegistration.displayName)' (objectIds: $ids). Resolve ambiguity in Entra before resuming." -Throw
}
$app = $apps[0]
Write-LabLog -Level Info -Message "  applicationId = $($app.appId)"
Write-LabLog -Level Info -Message "  objectId      = $($app.id)"

# Pick the newest non-expired client secret to report as "current"; the actual
# secret VALUE is in Key Vault, not on the app reg.
$now = Get-Date
$activeCreds = @($app.passwordCredentials | Where-Object {
    $_.endDateTime -and ([datetime]$_.endDateTime) -gt $now
})
$activeCred = if ($activeCreds.Count -gt 0) {
    $activeCreds | Sort-Object endDateTime -Descending | Select-Object -First 1
} else { $null }
$secretKeyId      = if ($activeCred) { $activeCred.keyId } else { $null }
$secretExpiresOn  = if ($activeCred) { $activeCred.endDateTime } else { $null }
if (-not $activeCred) {
    Write-LabLog -Level Warn -Message "  app registration has no non-expired client secret credentials. The lab can still bind to a secret already in Key Vault, but key-rotation tracking will be inaccurate until you rotate."
}

# Service principal (object) ID for the app
$spResp = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/servicePrincipals?`$filter=appId eq '$($app.appId)'&`$select=id,displayName" -Headers $graphHdr -Method Get -ErrorAction Stop
$sps = @($spResp.value)
if ($sps.Count -eq 0) {
    Write-LabLog -Level Error -Message "App registration $($app.appId) has no associated service principal. Run lab/01 to provision it, or check Entra admin consent state." -Throw
}
$spObjectId = $sps[0].id
Write-LabLog -Level Info -Message "  servicePrincipalObjectId = $spObjectId"

# Consented permissions snapshot (best-effort; reproduces what lab/01 records)
$rolesResp = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/servicePrincipals/$spObjectId/appRoleAssignments?`$select=appRoleId,resourceId,resourceDisplayName" -Headers $graphHdr -Method Get -ErrorAction Stop
$grantsResp = Invoke-RestMethod -Uri "https://graph.microsoft.com/v1.0/oauth2PermissionGrants?`$filter=clientId eq '$spObjectId'&`$select=scope,resourceId,consentType" -Headers $graphHdr -Method Get -ErrorAction Stop
$consented = New-Object System.Collections.Generic.List[string]
foreach ($r in @($rolesResp.value)) {
    $resourceDisplay = if ($r.PSObject.Properties['resourceDisplayName']) { $r.resourceDisplayName } else { '(unknown)' }
    $consented.Add("$resourceDisplay`: appRole $($r.appRoleId) (Application)")
}
foreach ($g in @($grantsResp.value)) {
    $scopes = if ($g.scope) { $g.scope } else { '(no scopes)' }
    $consentType = if ($g.PSObject.Properties['consentType']) { $g.consentType } else { 'Unknown' }
    $consented.Add("OAuth2 scopes ($consentType): $scopes")
}

# ---------- 3. Resolve the Key Vault ----------
Write-LabLog -Level Info -Message "Resolving Key Vault '$($cfg.keyVault.name)'..."
$armTok = Get-AccessTokenForResource -Resource 'https://management.azure.com'
$armHdr = @{ Authorization = "Bearer $armTok"; Accept = 'application/json' }
$kvProbeUrl = "https://management.azure.com/subscriptions/$($cfg.azure.subscriptionId)/resourceGroups/$($cfg.azure.resourceGroup)/providers/Microsoft.KeyVault/vaults/$($cfg.keyVault.name)?api-version=2023-07-01"
try {
    $kvResp = Invoke-RestMethod -Uri $kvProbeUrl -Headers $armHdr -Method Get -ErrorAction Stop
} catch {
    $sc = if ($_.Exception.Response) { [int]$_.Exception.Response.StatusCode } else { -1 }
    Write-LabLog -Level Error -Message "Key Vault '$($cfg.keyVault.name)' not found in subscription $($cfg.azure.subscriptionId) / rg $($cfg.azure.resourceGroup) (http=$sc). Run lab/02_New-KeyVault.ps1 to create it, or edit lab-config.json.azure to point at the correct subscription / resource group." -Throw
}
$kvResourceId = $kvResp.id
$kvUri        = $kvResp.properties.vaultUri
Write-LabLog -Level Info -Message "  resourceId = $kvResourceId"

# ---------- 4. Resolve the Power Platform environment + Dataverse application user ----------
Write-LabLog -Level Info -Message "Resolving Power Platform environment by URL '$($cfg.powerPlatform.environmentUrl)'..."
$bapTok = Get-AccessTokenForResource -Resource 'https://api.bap.microsoft.com'
$bapHdr = @{ Authorization = "Bearer $bapTok"; Accept = 'application/json' }
$bapList = Invoke-RestMethod -Uri "https://api.bap.microsoft.com/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2023-06-01" -Headers $bapHdr -Method Get -ErrorAction Stop
$envUrlNorm = $cfg.powerPlatform.environmentUrl.TrimEnd('/')
$matchingEnvironments = @($bapList.value | Where-Object {
    $linked = $_.properties.linkedEnvironmentMetadata
    $linked -and $linked.instanceUrl -and ($linked.instanceUrl.TrimEnd('/') -eq $envUrlNorm)
})
if ($matchingEnvironments.Count -eq 0) {
    Write-LabLog -Level Error -Message "No Power Platform environment found with Dataverse URL '$envUrlNorm'. Run lab/00b_New-PaygEnvironment.ps1, or update lab-config.json.powerPlatform.environmentUrl." -Throw
}
if ($matchingEnvironments.Count -gt 1) {
    $ids = ($matchingEnvironments | ForEach-Object { $_.name }) -join ', '
    Write-LabLog -Level Error -Message "Found $($matchingEnvironments.Count) environments with that Dataverse URL ($ids). This should be impossible; check tenant state manually." -Throw
}
$envObj = $matchingEnvironments[0]
$environmentId = $envObj.name
Write-LabLog -Level Info -Message "  environmentId = $environmentId"

# Dataverse application user (systemuser linked to the SP's applicationid)
Write-LabLog -Level Info -Message "Resolving Dataverse application user for appId $($app.appId)..."
$dvTok = Get-AccessTokenForResource -Resource $envUrlNorm
$dvHdr = @{
    Authorization      = "Bearer $dvTok"
    Accept             = 'application/json'
    'OData-MaxVersion' = '4.0'
    'OData-Version'    = '4.0'
}
$dvApi = "$envUrlNorm/api/data/v9.2"

$suResp = Invoke-RestMethod -Uri "$dvApi/systemusers?`$filter=applicationid eq $($app.appId)&`$select=systemuserid,fullname,isdisabled" -Headers $dvHdr -Method Get -ErrorAction Stop
$sus = @($suResp.value)
$applicationUserId = $null
$assignedRole = $null
if ($sus.Count -eq 0) {
    Write-LabLog -Level Warn -Message "  No Dataverse application user exists for applicationid $($app.appId). Run lab/04_New-AppUser.ps1 to create it. The state file will be written with applicationUserId=null."
} elseif ($sus.Count -gt 1) {
    Write-LabLog -Level Warn -Message "  Multiple Dataverse application users match applicationid $($app.appId). Picking the first. Investigate manually."
    $applicationUserId = $sus[0].systemuserid
} else {
    $applicationUserId = $sus[0].systemuserid
    Write-LabLog -Level Info -Message "  applicationUserId = $applicationUserId"
}

if ($applicationUserId) {
    # Resolve the security role(s) assigned to this app user. Report ONE role
    # for the state file (preferring FSI Message Center Sync over System
    # Customizer over anything else). The full list is logged.
    $rolesUrl = "$dvApi/systemusers($applicationUserId)/systemuserroles_association?`$select=roleid,name"
    try {
        $rolesAssoc = Invoke-RestMethod -Uri $rolesUrl -Headers $dvHdr -Method Get -ErrorAction Stop
        $allRoles = @($rolesAssoc.value | ForEach-Object { $_.name })
        Write-LabLog -Level Info -Message "  assigned roles = $(($allRoles -join ', '))"
        $assignedRole = if ('FSI Message Center Sync' -in $allRoles) {
            'FSI Message Center Sync'
        } elseif ('System Customizer' -in $allRoles) {
            'System Customizer'
        } elseif ($allRoles.Count -gt 0) {
            $allRoles[0]
        } else { $null }
    } catch {
        Write-LabLog -Level Warn -Message "  Could not query roles for application user $applicationUserId : $($_.Exception.Message). assignedRole left null."
    }
}

# ---------- 5. Assemble lab-state.json ----------
Write-LabLog -Level Info -Message "Assembling lab-state.json..."
$state = [pscustomobject]@{
    schemaVersion = '1.0.0'
    createdAt     = (Get-Date -AsUTC).ToString('o')
    createdBy     = $cfg.operator.runnerUpn
    tenantId      = $cfg.tenant.tenantId
    appRegistration = [pscustomobject]@{
        applicationId            = $app.appId
        objectId                 = $app.id
        displayName              = $app.displayName
        servicePrincipalObjectId = $spObjectId
        secretKeyId              = $secretKeyId
        secretExpiresOn          = $secretExpiresOn
        consentedPermissions     = $consented.ToArray()
    }
    subscriptionId  = $cfg.azure.subscriptionId
    resourceGroup   = $cfg.azure.resourceGroup
    keyVault = [pscustomobject]@{
        name       = $cfg.keyVault.name
        resourceId = $kvResourceId
        vaultUri   = $kvUri
        secretName = $cfg.keyVault.secretName
    }
    dataverse = [pscustomobject]@{
        environmentUrl    = $cfg.powerPlatform.environmentUrl
        environmentId     = $environmentId
        tableLogicalName  = 'fsi_messagecenterlog'
        alternateKeyName  = 'fsi_MessageCenterIdKey'
        applicationUserId = $applicationUserId
        assignedRole      = $assignedRole
    }
    lastUpdated = (Get-Date -AsUTC).ToString('o')
}

Save-LabState -State $state -StatePath $StatePath
Write-LabLog -Level Info -Message "Wrote $StatePath ($((Get-Item $StatePath).Length) bytes)."

Write-LabLog -Level Info -Message ""
Write-LabLog -Level Info -Message "Resume complete. Next: re-run preflight per AGENTS.md § 4 step 5."
