<#
.SYNOPSIS
    Registers a newly provisioned environment in ACV's environment registry.

.DESCRIPTION
    Creates or updates an fsi_environmentregistry record in the ACV Dataverse tables
    with zone classification from the ELM provisioning request. This is the PowerShell
    equivalent of the ELM-SolutionInitializer Power Automate flow.

.PARAMETER DataverseUrl
    The Dataverse environment URL.

.PARAMETER TenantId
    The Microsoft Entra tenant ID.

.PARAMETER EnvironmentId
    The Power Platform environment GUID.

.PARAMETER EnvironmentName
    The environment display name.

.PARAMETER EnvironmentUrl
    The Dataverse URL for the environment.

.PARAMETER Zone
    The governance zone (1, 2, or 3).

.PARAMETER EnvironmentType
    The environment type (1=Production, 2=Sandbox, 3=Developer, 4=Trial, 5=Default).

.PARAMETER ClientId
    App registration client ID for service principal auth.

.PARAMETER ClientSecret
    App registration client secret.

.PARAMETER Interactive
    Use interactive authentication.

.PARAMETER DryRun
    Show what would be created without writing to Dataverse.

.EXAMPLE
    .\Register-ProvisionedEnvironment.ps1 -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "guid" -EnvironmentId "env-guid" -EnvironmentName "TRADING-Ops-PROD" `
        -EnvironmentUrl "https://trading.crm.dynamics.com" -Zone 3 -EnvironmentType 2 -Interactive

.NOTES
    Version: 1.0.0
    Date: 2026-02-10
    Requires: IntegrationConfig.psm1
#>

#Requires -Version 7.0

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(Mandatory)]
    [string]$DataverseUrl,

    [Parameter(Mandatory)]
    [string]$TenantId,

    [Parameter(Mandatory)]
    [ValidatePattern('^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$')]
    [string]$EnvironmentId,

    [Parameter(Mandatory)]
    [string]$EnvironmentName,

    [Parameter()]
    [string]$EnvironmentUrl,

    [Parameter(Mandatory)]
    [ValidateSet(1, 2, 3)]
    [int]$Zone,

    [Parameter()]
    [ValidateSet(1, 2, 3, 4, 5)]
    [int]$EnvironmentType = 2,

    [Parameter()]
    [string]$RequestNumber,

    [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory)]
    [string]$ClientId,

    [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory)]
    [SecureString]$ClientSecret,

    [Parameter(ParameterSetName = 'Interactive')]
    [switch]$Interactive,

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Import integration module
$modulePath = Join-Path $PSScriptRoot 'IntegrationConfig.psm1'
Import-Module $modulePath -Force

#region Authentication (provided by IntegrationConfig.psm1)

#endregion

Write-Host "`nRegister-ProvisionedEnvironment" -ForegroundColor Cyan
Write-Host "================================`n" -ForegroundColor Cyan

# Connect
Write-Host "Connecting to Dataverse..." -ForegroundColor Gray
$connection = Connect-DataverseApi -Url $DataverseUrl -TenantId $TenantId `
    -ClientId $ClientId -ClientSecret $ClientSecret -Interactive:$Interactive

$canonicalZone = Get-CanonicalZoneValue -ZoneValue $Zone

# Check if environment already registered
Write-Host "Checking ACV environment registry..." -ForegroundColor Gray
$checkUrl = "$($connection.BaseUrl)/fsi_environmentregistrys?`$filter=fsi_environmentid eq '$EnvironmentId'&`$top=1"
$existing = (Invoke-RestMethod -Uri $checkUrl -Headers $connection.Headers -Method Get).value

$record = @{
    'fsi_name'            = $EnvironmentName
    'fsi_environmentid'   = $EnvironmentId
    'fsi_zone'            = $canonicalZone
    'fsi_status'          = 1  # Active
    'fsi_environmenttype' = $EnvironmentType
    'fsi_discoveredon'    = (Get-Date).ToString('yyyy-MM-ddTHH:mm:ssZ')
    'fsi_notes'           = "Auto-registered via ELM provisioning$(if ($RequestNumber) { ". Request: $RequestNumber" })"
}

if ($EnvironmentUrl) {
    $record['fsi_environmenturl'] = $EnvironmentUrl
}

if ($existing.Count -gt 0) {
    $existingId = $existing[0].fsi_environmentregistryid

    if ($DryRun) {
        Write-Host "[DryRun] Would UPDATE existing registry: $existingId" -ForegroundColor Yellow
    } else {
        $updateUrl = "$($connection.BaseUrl)/fsi_environmentregistrys($existingId)"
        $body = $record | ConvertTo-Json -Depth 5
        Invoke-RestMethod -Uri $updateUrl -Headers $connection.Headers -Method Patch -Body $body
        Write-Host "[Updated] Environment registry: $EnvironmentName (Zone $canonicalZone)" -ForegroundColor Green
    }
} else {
    if ($DryRun) {
        Write-Host "[DryRun] Would CREATE new registry for: $EnvironmentName (Zone $canonicalZone)" -ForegroundColor Yellow
    } else {
        $createUrl = "$($connection.BaseUrl)/fsi_environmentregistrys"
        $body = $record | ConvertTo-Json -Depth 5
        $created = Invoke-RestMethod -Uri $createUrl -Headers $connection.Headers -Method Post -Body $body
        Write-Host "[Created] Environment registry: $EnvironmentName (Zone $canonicalZone)" -ForegroundColor Green
        Write-Host "  Registry ID: $($created.fsi_environmentregistryid)" -ForegroundColor Gray
    }
}

Write-Host "`nRegistration complete.`n" -ForegroundColor Cyan
