#Requires -Version 7.0
<#
.SYNOPSIS
    Populates Dataverse environment variable values for the lab.

.DESCRIPTION
    Upserts environmentvariablevalues records via Dataverse Web API for:
      - MCM_NotifyChannel       (string; from lab-config.notification.channel; empty allowed)
      - MCM_NotifyTeamId        (string; from lab-config.notification.teamId;  empty allowed)
      - MCM_BodyMaxLength       (number; default 4000)
      - MCM_AssessmentSlaDays   (number; default 14)

    Uses the lab service principal's token (already validated in step 04)
    so this also serves as a write-path probe.

.NOTES
    Lab dry-run step 5 of 7. Solution: message-center-monitor v2.5.0+
#>
[Diagnostics.CodeAnalysis.SuppressMessageAttribute(
    'PSAvoidUsingConvertToSecureStringWithPlainText', '',
    Justification = 'Lab provisioning script run interactively by tenant admin. Operator pastes a temporary secret for one-time setup; not invoked in production.'
)]
[CmdletBinding(SupportsShouldProcess)]
param(
    [Parameter()] [string] $ConfigPath,
    [Parameter()] [switch] $AllowProduction
)

$ErrorActionPreference = 'Stop'
. $PSScriptRoot/lib/Write-LabLog.ps1
$null = Initialize-LabLog -StepName '05-env-vars'

$cfg   = Get-LabConfig -ConfigPath $ConfigPath
$state = Get-LabState
if (-not $state.dataverse -or -not $state.dataverse.applicationUserId) {
    Write-LabLog -Level Error -Message "Run 04_New-AppUser.ps1 first." -Throw
}
Assert-NonProdAcknowledgement -Config $cfg -AllowProduction:$AllowProduction

Import-Module MSAL.PS -ErrorAction Stop
$kvSecret = Get-AzKeyVaultSecret -VaultName $cfg.keyVault.name -Name $cfg.keyVault.secretName -AsPlainText -ErrorAction Stop
$secStr = ConvertTo-SecureString $kvSecret -AsPlainText -Force
$resource = $cfg.powerPlatform.environmentUrl.TrimEnd('/')
$tok = Get-MsalToken -ClientId $state.appRegistration.applicationId `
                     -ClientSecret $secStr `
                     -TenantId $cfg.tenant.tenantId `
                     -Authority "https://login.microsoftonline.com/$($cfg.tenant.tenantId)" `
                     -Scopes "$resource/.default" -ErrorAction Stop

$apiBase = "$resource/api/data/v9.2"
$hdr = @{
    Authorization      = "Bearer $($tok.AccessToken)"
    'OData-MaxVersion' = '4.0'
    'OData-Version'    = '4.0'
    Accept             = 'application/json'
    'Content-Type'     = 'application/json'
    Prefer             = 'return=representation'
}

# Settings to apply.
# These names MUST match scripts/create_mcm_environment_variables.py - if they
# drift, this script silently no-ops. See lab dry-run runbook for the source of truth.
$settings = @(
    @{ Name = 'fsi_MCM_TeamsTeamId';        Value = ($cfg.notification.teamId  -as [string]) }
    @{ Name = 'fsi_MCM_TeamsChannelId';     Value = ($cfg.notification.channel -as [string]) }
    @{ Name = 'fsi_MCM_DataverseUrl';       Value = $cfg.powerPlatform.environmentUrl.TrimEnd('/') }
    @{ Name = 'fsi_MCM_KeyVaultSecretName'; Value = $cfg.keyVault.secretName }
    @{ Name = 'fsi_MCM_NotifySeverities';   Value = 'high,critical' }
    @{ Name = 'fsi_MCM_PollingIntervalDays';Value = '1' }
)

foreach ($s in $settings) {
    Write-LabLog -Level Info -Message "Setting $($s.Name) = '$($s.Value)'..."

    # Look up the environmentvariabledefinition by schemaname.
    $defs = Invoke-RestMethod -Uri "$apiBase/environmentvariabledefinitions?`$filter=schemaname eq '$($s.Name)'&`$select=environmentvariabledefinitionid,schemaname" -Headers $hdr -Method Get -ErrorAction Stop
    if (-not $defs.value -or $defs.value.Count -eq 0) {
        Write-LabLog -Level Warn -Message "  Definition for $($s.Name) not found - did 03_Deploy-Schema.ps1 create env vars? Skipping."
        continue
    }
    $defId = $defs.value[0].environmentvariabledefinitionid

    # Look up existing value, if any.
    $vals = Invoke-RestMethod -Uri "$apiBase/environmentvariablevalues?`$filter=_environmentvariabledefinitionid_value eq $defId&`$select=environmentvariablevalueid,value" -Headers $hdr -Method Get -ErrorAction Stop

    if ($vals.value -and $vals.value.Count -gt 0) {
        # Update.
        $valId = $vals.value[0].environmentvariablevalueid
        if ($vals.value[0].value -eq $s.Value) {
            Write-LabLog -Level Info -Message "  unchanged."
            continue
        }
        if ($PSCmdlet.ShouldProcess($s.Name, 'PATCH environmentvariablevalues')) {
            $body = @{ value = $s.Value } | ConvertTo-Json
            Invoke-RestMethod -Uri "$apiBase/environmentvariablevalues($valId)" -Headers $hdr -Method Patch -Body $body -ErrorAction Stop | Out-Null
            Write-LabLog -Level Info -Message "  updated."
        }
    } else {
        # Create.
        if ($PSCmdlet.ShouldProcess($s.Name, 'POST environmentvariablevalues')) {
            $body = @{
                'EnvironmentVariableDefinitionId@odata.bind' = "/environmentvariabledefinitions($defId)"
                value = $s.Value
            } | ConvertTo-Json
            Invoke-RestMethod -Uri "$apiBase/environmentvariablevalues" -Headers $hdr -Method Post -Body $body -ErrorAction Stop | Out-Null
            Write-LabLog -Level Info -Message "  created."
        }
    }
}

Write-LabLog -Level Info -Message "Env vars set. Next: pwsh ./06_Invoke-LabSmokeTest.ps1"
