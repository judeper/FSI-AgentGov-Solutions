#Requires -Version 7.0
<#
.SYNOPSIS
    Wraps the Python schema/env-var/connection-reference setup with active-key polling.

.DESCRIPTION
    Calls the three Python setup scripts in order, then polls Dataverse
    EntityDefinitions(LogicalName='fsi_messagecenterlog')/Keys for
    EntityKeyIndexStatus == Active (2) up to thresholds.schemaKeyActivationMaxSeconds
    (default 900s). Pending = wait; Failed = fatal; Active = continue.

    The alternate-key index activation is asynchronous in Dataverse and the
    fix in v2.4.0 (idempotent upsert via the alt key) WILL fail if scripts
    proceed before the index is Active.

.PARAMETER ConfigPath
    Path to lab-config.json.

.PARAMETER PocOnly
    Skip the env-var + connection-reference Python scripts. Only run
    create_mcm_dataverse_schema.py (and wait for alternate-key
    activation). This is the Phase 1 ("POC bar") deployment path used by
    lab/07_Invoke-PocSmokeTest.ps1 and by customers following the POC
    Quickstart runbook in docs/poc-quickstart.md.

    The skipped scripts (environment variables and connection references)
    are only needed by the Phase 3 Power Automate flow, not by the
    Phase 1 PowerShell sync.

.NOTES
    Lab dry-run step 3 of 7. Solution: message-center-monitor v2.5.0+
#>
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()] [string] $ConfigPath,
    [Parameter()] [switch] $AllowProduction,
    [Parameter()] [switch] $PocOnly
)

$ErrorActionPreference = 'Stop'
. $PSScriptRoot/lib/Write-LabLog.ps1
$null = Initialize-LabLog -StepName '03-deploy-schema'

$cfg   = Get-LabConfig -ConfigPath $ConfigPath
Assert-NonProdAcknowledgement -Config $cfg -AllowProduction:$AllowProduction
$state = Get-LabState

if (-not $state.appRegistration) {
    Write-LabLog -Level Error -Message "appRegistration missing from lab-state.json. Run 01_New-AppRegistration.ps1 first." -Throw
}

# Resolve the secret from Key Vault for the Python scripts (which use ClientSecret auth).
Write-LabLog -Level Info -Message "Reading client secret from Key Vault '$($cfg.keyVault.name)/$($cfg.keyVault.secretName)'..."
$kvSecret = Get-AzKeyVaultSecret -VaultName $cfg.keyVault.name -Name $cfg.keyVault.secretName -AsPlainText -ErrorAction Stop
if ([string]::IsNullOrEmpty($kvSecret)) {
    Write-LabLog -Level Error -Message "Key Vault secret is empty. Re-run 01 + 02 with -ForceRotate." -Throw
}

$envBackup = @{
    MCM_TENANT_ID         = $env:MCM_TENANT_ID
    MCM_CLIENT_ID         = $env:MCM_CLIENT_ID
    MCM_CLIENT_SECRET     = $env:MCM_CLIENT_SECRET
    MCM_DATAVERSE_URL     = $env:MCM_DATAVERSE_URL
}
$env:MCM_TENANT_ID     = $cfg.tenant.tenantId
$env:MCM_CLIENT_ID     = $state.appRegistration.applicationId
$env:MCM_CLIENT_SECRET = $kvSecret
$env:MCM_DATAVERSE_URL = $cfg.powerPlatform.environmentUrl

try {
    $pyScriptsDir = Join-Path (Split-Path -Parent $PSScriptRoot) 'scripts'

    # In -PocOnly mode, skip env-vars + connection-references scripts
    # (those exist only for the Phase 3 Power Automate flow path).
    $allScripts = @('create_mcm_dataverse_schema.py', 'create_mcm_environment_variables.py', 'create_mcm_connection_references.py')
    if ($PocOnly) {
        $scriptsToRun = @('create_mcm_dataverse_schema.py')
        Write-LabLog -Level Info -Message "PocOnly mode: skipping create_mcm_environment_variables.py and create_mcm_connection_references.py"
    } else {
        $scriptsToRun = $allScripts
    }

    foreach ($script in $scriptsToRun) {
        $path = Join-Path $pyScriptsDir $script
        Write-LabLog -Level Info -Message "Running $script..."
        if ($PSCmdlet.ShouldProcess($script, 'python')) {
            & python $path
            if ($LASTEXITCODE -ne 0) {
                Write-LabLog -Level Error -Message "$script failed with exit code $LASTEXITCODE. See log above." -Throw
            }
        }
    }

    # --- Poll alternate-key activation ---------------------------------------
    $maxSec    = $cfg.thresholds.schemaKeyActivationMaxSeconds
    $backoff   = $cfg.thresholds.schemaKeyActivationInitialBackoffSeconds
    if (-not $maxSec)   { $maxSec   = 900 }
    if (-not $backoff)  { $backoff  = 5 }
    $deadline  = (Get-Date).AddSeconds($maxSec)

    Write-LabLog -Level Info -Message "Polling alternate-key fsi_MessageCenterIdKey for Active status (max $maxSec s)..."

    # Get an MSAL token for Dataverse so we can query EntityDefinitions.
    Import-Module MSAL.PS -ErrorAction Stop
    $resource  = ($cfg.powerPlatform.environmentUrl.TrimEnd('/'))
    $authority = "https://login.microsoftonline.com/$($cfg.tenant.tenantId)"
    $secStr    = ConvertTo-SecureString $kvSecret -AsPlainText -Force
    $tok = Get-MsalToken -ClientId $state.appRegistration.applicationId `
                         -ClientSecret $secStr `
                         -TenantId $cfg.tenant.tenantId `
                         -Authority $authority `
                         -Scopes "$resource/.default" -ErrorAction Stop

    $url = "$resource/api/data/v9.2/EntityDefinitions(LogicalName='fsi_messagecenterlog')/Keys"
    $headers = @{
        Authorization      = "Bearer $($tok.AccessToken)"
        Accept             = 'application/json'
        'OData-MaxVersion' = '4.0'
        'OData-Version'    = '4.0'
    }

    $status = 'Unknown'
    $attempt = 0
    while ((Get-Date) -lt $deadline) {
        $attempt++
        try {
            $resp = Invoke-RestMethod -Uri $url -Headers $headers -Method Get -ErrorAction Stop
            $key  = $resp.value | Where-Object { $_.LogicalName -eq 'fsi_messagecenteridkey' -or $_.SchemaName -eq 'fsi_MessageCenterIdKey' } | Select-Object -First 1
            if (-not $key) {
                Write-LabLog -Level Warn -Message "  attempt ${attempt}: alt key not yet visible in EntityDefinitions"
            } else {
                # EntityKeyIndexStatus: 0=Pending, 1=InProgress, 2=Active, 3=Failed
                $status = switch ($key.EntityKeyIndexStatus) {
                    0 { 'Pending' }
                    1 { 'InProgress' }
                    2 { 'Active' }
                    3 { 'Failed' }
                    default { "Unknown($($key.EntityKeyIndexStatus))" }
                }
                Write-LabLog -Level Info -Message "  attempt ${attempt}: status=$status"
                if ($status -eq 'Active')  { break }
                if ($status -eq 'Failed')  {
                    Write-LabLog -Level Error -Message "Alternate key activation FAILED. Inspect Solution > Tables > Message Center Log > Keys in Power Apps maker portal." -Throw
                }
            }
        } catch {
            Write-LabLog -Level Warn -Message "  attempt ${attempt}: poll error $($_.Exception.Message)"
        }
        Start-Sleep -Seconds $backoff
        $backoff = [Math]::Min($backoff * 2, 60)
    }

    if ($status -ne 'Active') {
        Write-LabLog -Level Error -Message "Alternate key did not reach Active within $maxSec s (last status=$status). Re-run this script later or extend thresholds.schemaKeyActivationMaxSeconds." -Throw
    }
    Write-LabLog -Level Info -Message "Alternate key Active [OK]"

    # --- Persist state -------------------------------------------------------
    $state | Add-Member -NotePropertyName 'dataverse' -NotePropertyValue ([pscustomobject]@{
        environmentUrl    = $cfg.powerPlatform.environmentUrl
        environmentId     = $cfg.powerPlatform.environmentId
        tableLogicalName  = 'fsi_messagecenterlog'
        alternateKeyName  = 'fsi_MessageCenterIdKey'
        applicationUserId = $null
        assignedRole      = $null
    }) -Force
    Save-LabState -State $state

    Write-LabLog -Level Info -Message "Schema deployed. Next: pwsh ./04_New-AppUser.ps1"
}
finally {
    # Restore previous env values, never leave the secret in the env.
    foreach ($k in $envBackup.Keys) { Set-Item -Path "Env:$k" -Value $envBackup[$k] -ErrorAction SilentlyContinue }
    $env:MCM_CLIENT_SECRET = $envBackup.MCM_CLIENT_SECRET
}
