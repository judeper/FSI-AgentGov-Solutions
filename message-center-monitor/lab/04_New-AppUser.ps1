#Requires -Version 7.0
<#
.SYNOPSIS
    Creates Dataverse Application User for the lab service principal and assigns a security role.

.DESCRIPTION
    1. Resolves environmentId from environmentUrl if not in lab-state.json.
    2. Calls Microsoft.PowerApps.Administration.PowerShell to create the
       Application User in the resolved environment (idempotent: skips if it exists).
    3. Via Dataverse Web API: queries `systemusers?$filter=applicationid eq <appId>`
       to get systemuserid, looks up the requested security role
       (`-RoleName 'FSI Message Center Sync'` by default; falls back to
       'System Customizer' for lab simplicity if the FSI role is not present),
       then PUTs the systemuserroles_association.
    4. Probes effective access by issuing GET fsi_messagecenterlogs?$top=1
       using the SP's own access token. A 401/403 here means the role
       association did not propagate; the script retries up to 6 times with
       exponential backoff before failing.

.PARAMETER ConfigPath
    Path to lab-config.json.

.PARAMETER RoleName
    Security role to assign. Default: 'FSI Message Center Sync'. Falls back to
    'System Customizer' in the lab if the FSI role is not present (this is
    intentional for non-prod; production must use the FSI role).

.NOTES
    Lab dry-run step 4 of 7. Solution: message-center-monitor v2.5.0+
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()] [string] $ConfigPath,
    [Parameter()] [string] $RoleName = 'FSI Message Center Sync',
    [Parameter()] [switch] $AllowProduction
)

$ErrorActionPreference = 'Stop'
. $PSScriptRoot/lib/Write-LabLog.ps1
$null = Initialize-LabLog -StepName '04-app-user'

$cfg   = Get-LabConfig -ConfigPath $ConfigPath
Assert-NonProdAcknowledgement -Config $cfg -AllowProduction:$AllowProduction
$state = Get-LabState
if (-not $state.appRegistration) { Write-LabLog -Level Error -Message "Run 01 first." -Throw }
if (-not $state.dataverse)        { Write-LabLog -Level Error -Message "Run 03 first." -Throw }

$kvSecret = Get-AzKeyVaultSecret -VaultName $cfg.keyVault.name -Name $cfg.keyVault.secretName -AsPlainText -ErrorAction Stop
$resource = $cfg.powerPlatform.environmentUrl.TrimEnd('/')

# --- 1. Resolve environmentId if needed --------------------------------------
$envId = $state.dataverse.environmentId
if ([string]::IsNullOrEmpty($envId)) {
    Write-LabLog -Level Info -Message "Resolving environmentId from environmentUrl..."
    Import-Module Microsoft.PowerApps.Administration.PowerShell -ErrorAction Stop
    $allEnvs = Get-AdminPowerAppEnvironment -ErrorAction Stop
    $match = $allEnvs | Where-Object {
        $_.Internal.properties.linkedEnvironmentMetadata.instanceUrl -and
        ($_.Internal.properties.linkedEnvironmentMetadata.instanceUrl.TrimEnd('/') -eq $resource)
    } | Select-Object -First 1
    if (-not $match) { Write-LabLog -Level Error -Message "No Power Platform env matches '$resource'." -Throw }
    $envId = $match.EnvironmentName
    $state.dataverse.environmentId = $envId
    Save-LabState -State $state
    Write-LabLog -Level Info -Message "  environmentId=$envId"
}

# --- 2. Create Application User ---------------------------------------------
Write-LabLog -Level Info -Message "Creating Dataverse Application User for appId=$($state.appRegistration.applicationId)..."
Import-Module Microsoft.PowerApps.Administration.PowerShell -ErrorAction Stop
if ($PSCmdlet.ShouldProcess("env=$envId / appId=$($state.appRegistration.applicationId)", 'New-AdminPowerAppCdsDatabaseApplicationUser')) {
    try {
        New-AdminPowerAppCdsDatabaseApplicationUser -EnvironmentName $envId -ApplicationId $state.appRegistration.applicationId -ErrorAction Stop | Out-Null
        Write-LabLog -Level Info -Message "  Application User created."
    } catch {
        # The cmdlet returns 409/duplicate when the user already exists; treat that as success.
        if ($_.Exception.Message -match 'already exists|409|duplicate') {
            Write-LabLog -Level Info -Message "  Application User already exists; reusing."
        } else { throw }
    }
}

# --- 3. Look up systemuser + role + assign via Dataverse Web API -------------
Import-Module MSAL.PS -ErrorAction Stop
$secStr = ConvertTo-SecureString $kvSecret -AsPlainText -Force
$tok = Get-MsalToken -ClientId $state.appRegistration.applicationId `
                     -ClientSecret $secStr `
                     -TenantId $cfg.tenant.tenantId `
                     -Authority "https://login.microsoftonline.com/$($cfg.tenant.tenantId)" `
                     -Scopes "$resource/.default" -ErrorAction Stop

# We need an interactive admin token to write the role association (the SP cannot
# assign roles to itself before it has any). Reuse the engineer's existing Az login
# to get a Dataverse token via Get-AzAccessToken.
$adminTok = (Get-AzAccessToken -ResourceUrl $resource -ErrorAction Stop).Token
$adminHdr = @{
    Authorization      = "Bearer $adminTok"
    'OData-MaxVersion' = '4.0'
    'OData-Version'    = '4.0'
    Accept             = 'application/json'
    'Content-Type'     = 'application/json'
}

$apiBase = "$resource/api/data/v9.2"
$appIdLit = $state.appRegistration.applicationId
$su = Invoke-RestMethod -Uri "$apiBase/systemusers?`$filter=applicationid eq $appIdLit&`$select=systemuserid,fullname" -Headers $adminHdr -Method Get -ErrorAction Stop
if (-not $su.value -or $su.value.Count -eq 0) {
    Write-LabLog -Level Error -Message "systemuser for applicationid=$appIdLit not found. App user provisioning may not have committed yet; re-run after a minute." -Throw
}
$systemuserid = $su.value[0].systemuserid
Write-LabLog -Level Info -Message "  systemuserid=$systemuserid"

# Look up role; fallback to System Customizer for lab if FSI role absent.
$resolvedRoleName = $RoleName
$roleResp = Invoke-RestMethod -Uri "$apiBase/roles?`$filter=name eq '$RoleName'&`$select=roleid,name" -Headers $adminHdr -Method Get -ErrorAction Stop
if (-not $roleResp.value -or $roleResp.value.Count -eq 0) {
    Write-LabLog -Level Warn -Message "Role '$RoleName' not found in environment. Falling back to 'System Customizer' for the lab. PROD MUST USE THE FSI ROLE."
    $resolvedRoleName = 'System Customizer'
    $roleResp = Invoke-RestMethod -Uri "$apiBase/roles?`$filter=name eq 'System Customizer'&`$select=roleid,name" -Headers $adminHdr -Method Get -ErrorAction Stop
    if (-not $roleResp.value) { Write-LabLog -Level Error -Message "Even 'System Customizer' role not found." -Throw }
}
$roleid = $roleResp.value[0].roleid
Write-LabLog -Level Info -Message "  role='$resolvedRoleName' roleid=$roleid"

# Associate (idempotent: PUT returns 204 even if already associated, or 412/409).
$assocBody = @{ '@odata.id' = "$apiBase/roles($roleid)" } | ConvertTo-Json
if ($PSCmdlet.ShouldProcess("systemuser/$systemuserid + role/$roleid", 'Associate systemuserroles')) {
    try {
        Invoke-RestMethod -Uri "$apiBase/systemusers($systemuserid)/systemuserroles_association/`$ref" `
                          -Headers $adminHdr -Method Post -Body $assocBody -ErrorAction Stop | Out-Null
        Write-LabLog -Level Info -Message "  role associated."
    } catch {
        if ($_.Exception.Message -match '412|409|duplicate|already') {
            Write-LabLog -Level Info -Message "  role association already in place."
        } else { throw }
    }
}

# --- 4. Probe effective access using the SP's own token ----------------------
Write-LabLog -Level Info -Message "Probing effective access (SP queries fsi_messagecenterlogs)..."
$probeOk = $false
$attempt = 0
$delay = 4
while ($attempt -lt 6 -and -not $probeOk) {
    $attempt++
    # Re-acquire the SP token before each probe attempt. Tokens minted before
    # the role association may have been issued without the new role's claims;
    # acquiring fresh ensures we test the role we just granted (council finding #7).
    try {
        $tok = Get-MsalToken -ClientId $state.appRegistration.applicationId `
                             -ClientSecret $secStr `
                             -TenantId $cfg.tenant.tenantId `
                             -Authority "https://login.microsoftonline.com/$($cfg.tenant.tenantId)" `
                             -Scopes "$resource/.default" `
                             -ForceRefresh -ErrorAction Stop
    } catch {
        Write-LabLog -Level Warn -Message "  probe attempt $attempt token refresh failed: $($_.Exception.Message)"
        if ($attempt -lt 6) { Start-Sleep -Seconds $delay; $delay = [Math]::Min($delay * 2, 60) }
        continue
    }
    $spHdr = @{
        Authorization      = "Bearer $($tok.AccessToken)"
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
        Accept             = 'application/json'
    }
    try {
        $r = Invoke-RestMethod -Uri "$apiBase/fsi_messagecenterlogs?`$top=1&`$select=fsi_messagecenterid" -Headers $spHdr -Method Get -ErrorAction Stop
        $probeOk = $true
        Write-LabLog -Level Info -Message "  probe attempt $attempt OK ($(@($r.value).Count) row(s))"
    } catch {
        Write-LabLog -Level Warn -Message "  probe attempt $attempt failed: $($_.Exception.Message)"
        if ($attempt -lt 6) { Start-Sleep -Seconds $delay; $delay = [Math]::Min($delay * 2, 60) }
    }
}
if (-not $probeOk) {
    Write-LabLog -Level Error -Message "SP cannot query fsi_messagecenterlogs after role assignment. Verify in Power Apps maker portal: Settings > Users + permissions > Application users > $($cfg.appRegistration.displayName)." -Throw
}

# --- 5. Persist state --------------------------------------------------------
$state.dataverse.applicationUserId = $systemuserid
$state.dataverse.assignedRole      = $resolvedRoleName
Save-LabState -State $state
Write-LabLog -Level Info -Message "App user ready. Next: pwsh ./05_Set-EnvVarValues.ps1"
