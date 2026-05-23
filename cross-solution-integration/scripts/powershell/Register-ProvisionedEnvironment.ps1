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
    The governance zone as 1/2/3 or `fsi_acv_zone` option-set value (100000001..100000003).

.PARAMETER EnvironmentType
    The environment type as legacy 1=Production, 2=Sandbox, 3=Developer, 4=Trial, 5=Default, ELM option-set value, or ACV option-set value when -EnvironmentTypeFormat Acv is specified. The script writes the corresponding ACV option-set value.

.PARAMETER EnvironmentTypeFormat
    Indicates whether EnvironmentType uses legacy/ELM values (default) or ACV values. ELM Production (100000002) overlaps ACV Developer, so pass -EnvironmentTypeFormat Acv for direct ACV values.

.PARAMETER ManagedIdentity
    Use system-assigned managed identity from an Azure-hosted worker.

.PARAMETER ManagedIdentityClientId
    Optional user-assigned managed identity client ID.

.PARAMETER ClientId
    App registration client ID for legacy service principal auth.

.PARAMETER ClientSecret
    App registration client secret. Legacy dev-only fallback; use managed identity in production.

.PARAMETER Interactive
    Use interactive authentication.

.PARAMETER DryRun
    Show what would be created without writing to Dataverse.

.EXAMPLE
    .\Register-ProvisionedEnvironment.ps1 -DataverseUrl "https://org.crm.dynamics.com" `
        -TenantId "guid" -EnvironmentId "env-guid" -EnvironmentName "TRADING-Ops-PROD" `
        -EnvironmentUrl "https://trading.crm.dynamics.com" -Zone 3 -EnvironmentType 1 -Interactive

.NOTES
    Version: 2.0.3
    Date: 2026-05-22
    Requires: IntegrationConfig.psm1 v2.0.3
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
    [ValidateSet(1, 2, 3, 100000001, 100000002, 100000003)]
    [int]$Zone,

    [Parameter()]
    [ValidateSet(1, 2, 3, 4, 5, 100000000, 100000001, 100000002, 100000003, 100000004)]
    [int]$EnvironmentType = 2,

    [Parameter()]
    [ValidateSet('LegacyOrElm', 'Acv')]
    [string]$EnvironmentTypeFormat = 'LegacyOrElm',

    [Parameter()]
    [string]$RequestNumber,

    [Parameter(ParameterSetName = 'ManagedIdentity', Mandatory)]
    [switch]$ManagedIdentity,

    [Parameter(ParameterSetName = 'ManagedIdentity')]
    [string]$ManagedIdentityClientId,

    [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory)]
    [string]$ClientId,

    [Parameter(ParameterSetName = 'ServicePrincipal', Mandatory)]
    [SecureString]$ClientSecret,

    [Parameter(ParameterSetName = 'Interactive', Mandatory)]
    [switch]$Interactive,

    [ValidateSet('Public', 'USGov', 'USGovHigh', 'USGovDoD', 'China', 'Germany')]
    [string]$Cloud = 'Public',

    [switch]$DryRun
)

$ErrorActionPreference = 'Stop'

# Import integration module
$modulePath = Join-Path $PSScriptRoot 'IntegrationConfig.psm1'
Import-Module $modulePath -Force

#region Authentication (provided by IntegrationConfig.psm1)

#endregion


function Get-ResponseStatusCode {
    param([System.Management.Automation.ErrorRecord]$ErrorRecord)

    if ($null -ne $ErrorRecord.Exception.Response -and $null -ne $ErrorRecord.Exception.Response.StatusCode) {
        return [int]$ErrorRecord.Exception.Response.StatusCode
    }
    return 0
}

function Get-RetryDelaySeconds {
    param(
        [System.Management.Automation.ErrorRecord]$ErrorRecord,
        [int]$RetryCount
    )

    $response = $ErrorRecord.Exception.Response
    if ($null -ne $response -and $null -ne $response.Headers) {
        try {
            $retryAfter = ($response.Headers.GetValues('Retry-After') | Select-Object -First 1)
            if ($retryAfter -and ($retryAfter -as [int])) {
                return [int]$retryAfter
            }
        } catch {
            Write-Verbose ("Retry-After header lookup for Dataverse retry response {0} failed; using exponential backoff: {1}" -f $ErrorRecord.TargetObject, $_.Exception.Message)
        }
    }

    return [int]([math]::Pow(2, $RetryCount) * 5)
}

Write-Host "`nRegister-ProvisionedEnvironment" -ForegroundColor Cyan
Write-Host "================================`n" -ForegroundColor Cyan

# Connect
Write-Host "Connecting to Dataverse..." -ForegroundColor Gray
if ($ManagedIdentity) {
    $connection = Connect-DataverseApi -Url $DataverseUrl -TenantId $TenantId `
        -ManagedIdentity -ManagedIdentityClientId $ManagedIdentityClientId -Cloud $Cloud
} elseif ($Interactive) {
    $connection = Connect-DataverseApi -Url $DataverseUrl -TenantId $TenantId -Interactive -Cloud $Cloud
} else {
    # legacy: dev-only — replace with managed identity in production
    $connection = Connect-DataverseApi -Url $DataverseUrl -TenantId $TenantId `
        -ClientId $ClientId -ClientSecret $ClientSecret -Cloud $Cloud
}

$dashboardZone = Get-CanonicalZoneValue -ZoneValue $Zone
$acvZone = ConvertTo-AcvZoneValue -ZoneValue $Zone
$acvEnvironmentType = ConvertTo-AcvEnvironmentTypeValue -EnvironmentType $EnvironmentType -Source $EnvironmentTypeFormat

# Check if environment already registered
Write-Host "Checking ACV environment registry..." -ForegroundColor Gray
$sanitizedEnvId = $EnvironmentId -replace "[^0-9a-fA-F\-]", ''
$checkUrl = "$($connection.BaseUrl)/fsi_environmentregistries?`$filter=fsi_environmentid eq '$sanitizedEnvId'&`$top=1"

$maxRetries = 3
$retryCount = 0
$existing = $null
while ($true) {
    try {
        $existing = (Invoke-RestMethod -Uri $checkUrl -Headers $connection.Headers -Method Get).value
        break
    } catch {
        $retryCount++
        $statusCode = Get-ResponseStatusCode -ErrorRecord $_
        if ($statusCode -in @(429, 503) -and $retryCount -lt $maxRetries) {
            $delay = Get-RetryDelaySeconds -ErrorRecord $_ -RetryCount $retryCount
            Write-Warning "Transient error ($statusCode) checking registry — retrying in ${delay}s (attempt $retryCount/$maxRetries)"
            Start-Sleep -Seconds $delay
        } else {
            throw
        }
    }
}

$record = @{
    'fsi_name'            = $EnvironmentName
    'fsi_environmentid'   = $EnvironmentId
    'fsi_zone'            = $acvZone
    'fsi_status'          = 1  # Active
    'fsi_environmenttype' = $acvEnvironmentType
    'fsi_discoveredon'    = (Get-IsoUtcTimestamp)
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
        $updateUrl = "$($connection.BaseUrl)/fsi_environmentregistries($existingId)"
        $body = $record | ConvertTo-Json -Depth 5
        $retryCount = 0
        while ($true) {
            try {
                Invoke-RestMethod -Uri $updateUrl -Headers $connection.Headers -Method Patch -Body $body
                break
            } catch {
                $retryCount++
                $statusCode = Get-ResponseStatusCode -ErrorRecord $_
                if ($statusCode -in @(429, 503) -and $retryCount -lt $maxRetries) {
                    $delay = Get-RetryDelaySeconds -ErrorRecord $_ -RetryCount $retryCount
                    Write-Warning "Transient error ($statusCode) updating registry — retrying in ${delay}s (attempt $retryCount/$maxRetries)"
                    Start-Sleep -Seconds $delay
                } else {
                    throw
                }
            }
        }
        Write-Host "[Updated] Environment registry: $EnvironmentName (Zone $dashboardZone / ACV $acvZone)" -ForegroundColor Green
    }
} else {
    if ($DryRun) {
        Write-Host "[DryRun] Would CREATE new registry for: $EnvironmentName (Zone $dashboardZone / ACV $acvZone)" -ForegroundColor Yellow
    } else {
        $createUrl = "$($connection.BaseUrl)/fsi_environmentregistries"
        $body = $record | ConvertTo-Json -Depth 5
        $retryCount = 0
        $created = $null
        $confirmedViaRecheck = $false
        while ($true) {
            try {
                $created = Invoke-RestMethod -Uri $createUrl -Headers $connection.Headers -Method Post -Body $body
                break
            } catch {
                $retryCount++
                $statusCode = Get-ResponseStatusCode -ErrorRecord $_
                if ($statusCode -in @(429, 503) -and $retryCount -lt $maxRetries) {
                    # Re-query before retry to avoid duplicate creation
                    try {
                        $recheck = (Invoke-RestMethod -Uri $checkUrl -Headers $connection.Headers -Method Get).value
                        if ($recheck.Count -gt 0) {
                            $created = $recheck[0]
                            $confirmedViaRecheck = $true
                            break
                        }
                    } catch {
                        Write-Warning "Duplicate-avoidance recheck also failed — proceeding with retry"
                    }
                    $delay = Get-RetryDelaySeconds -ErrorRecord $_ -RetryCount $retryCount
                    Write-Warning "Transient error ($statusCode) creating registry — retrying in ${delay}s (attempt $retryCount/$maxRetries)"
                    Start-Sleep -Seconds $delay
                } else {
                    throw
                }
            }
        }
        if ($confirmedViaRecheck) {
            Write-Host "[Created] Environment registry (confirmed on re-check): $EnvironmentName (Zone $dashboardZone / ACV $acvZone)" -ForegroundColor Green
        } else {
            Write-Host "[Created] Environment registry: $EnvironmentName (Zone $dashboardZone / ACV $acvZone)" -ForegroundColor Green
        }
        Write-Host "  Registry ID: $($created.fsi_environmentregistryid)" -ForegroundColor Gray
    }
}

Write-Host "`nRegistration complete.`n" -ForegroundColor Cyan
