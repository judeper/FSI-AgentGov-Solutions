#Requires -Version 7.0
#Requires -Modules @{ ModuleName="Microsoft.PowerApps.Administration.PowerShell"; ModuleVersion="2.0.180" }

<#
.SYNOPSIS
    Discovers Power Platform environments, syncs to Dataverse registry, and returns validation set.

.DESCRIPTION
    Enumerates all Power Platform environments via Admin API, synchronizes them to the
    Dataverse environment registry (fsi_environmentregistries table), and returns the
    filtered set of environments ready for audit validation.

    Discovery process has three phases:
    1. Enumerate environments from Power Platform Admin API
    2. Sync to Dataverse registry (auto-register new environments as Unclassified/Active)
    3. Filter and return validation set based on zone classification and environment type

    New environments are automatically registered with Zone=Unclassified and Status=Active.
    Environments no longer returned by the API are marked Inactive (records are preserved
    for historical tracking).

    Trial and Developer environments are excluded by default (override with -IncludeTrialDev).
    Unclassified environments are excluded from validation (require zone assignment first).

.PARAMETER TenantId
    Microsoft Entra ID tenant ID. Required for authentication.

.PARAMETER DataverseUrl
    Dataverse organization URL(e.g., https://org.crm.dynamics.com). Required for
    registry synchronization.

.PARAMETER ClientId
    Microsoft Entra ID application (client) ID. Optional for interactive authentication.

.PARAMETER ClientSecret
    Client secret for service principal authentication. Must be provided as SecureString.

.PARAMETER CertificateThumbprint
    Certificate thumbprint for service principal authentication.

.PARAMETER Interactive
    Use interactive authentication (device code or browser-based).

.PARAMETER IncludeTrialDev
    Override to include Trial and Developer environments in the validation set.
    By default, Trial and Developer environments are excluded unless fsi_overrideinclude
    is set to true in the environment registry.

.PARAMETER OutputPath
    Optional path to write discovery results JSON file.

.EXAMPLE
    Invoke-EnvironmentDiscovery -TenantId "contoso.onmicrosoft.com" -DataverseUrl "https://org.crm.dynamics.com" -Interactive
    Discovers environments using interactive authentication, syncs to registry, and returns validation set.

.EXAMPLE
    Invoke-EnvironmentDiscovery -TenantId "contoso.onmicrosoft.com" -DataverseUrl "https://org.crm.dynamics.com" -Interactive -IncludeTrialDev
    Includes Trial and Developer environments in the validation set.

.EXAMPLE
    $secret = ConvertTo-SecureString "client-secret" -AsPlainText -Force
    Invoke-EnvironmentDiscovery -TenantId "contoso.onmicrosoft.com" -DataverseUrl "https://org.crm.dynamics.com" -ClientId "12345..." -ClientSecret $secret -OutputPath "discovery.json"
    Uses service principal authentication and exports results to JSON file.

.NOTES
    Version: 1.0.0
    Requires Microsoft.PowerApps.Administration.PowerShell module v2.0 or later.

    IMPORTANT: Power Platform Administrator or Global Administrator role is required
    for Get-AdminPowerAppEnvironment cmdlet. Users without these roles will receive
    an authorization error.

    Environment type mappings (Dataverse option set values):
    - Production = 100000000
    - Sandbox = 100000001
    - Developer = 100000002
    - Trial = 100000003
    - Default = 100000004

    Zone classifications (Dataverse option set values):
    - Unclassified = 100000000 (new environments, requires admin assignment)
    - Zone1 = 100000001 (Personal Productivity)
    - Zone2 = 100000002 (Team Collaboration)
    - Zone3 = 100000003 (Enterprise Managed)

.OUTPUTS
    PSCustomObject with discovery results:
    - Timestamp: UTC ISO 8601 timestamp
    - TotalDiscovered: Count of environments from API
    - NewEnvironments: Array of newly discovered environment names
    - InactivatedEnvironments: Array of deprovisioned environment names
    - SkippedUnclassified: Array of Unclassified environment names (need zone assignment)
    - SkippedTrialDev: Array of Trial/Developer environment names (excluded by policy)
    - ValidationSet: Array of environment hashtables ready for validation
#>

[CmdletBinding(DefaultParameterSetName = 'Interactive')]
param(
    [Parameter(Mandatory = $true)]
    [string]$TenantId,

    [Parameter(Mandatory = $true)]
    [string]$DataverseUrl,

    [Parameter(Mandatory = $false, ParameterSetName = 'ServicePrincipalSecret')]
    [Parameter(Mandatory = $false, ParameterSetName = 'ServicePrincipalCertificate')]
    [Parameter(Mandatory = $false, ParameterSetName = 'Interactive')]
    [string]$ClientId,

    [Parameter(Mandatory = $true, ParameterSetName = 'ServicePrincipalSecret')]
    [SecureString]$ClientSecret,

    [Parameter(Mandatory = $true, ParameterSetName = 'ServicePrincipalCertificate')]
    [string]$CertificateThumbprint,

    [Parameter(Mandatory = $false, ParameterSetName = 'Interactive')]
    [switch]$Interactive,

    [Parameter(Mandatory = $false)]
    [switch]$IncludeTrialDev,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath
)

$ErrorActionPreference = "Stop"

# Dot-source authentication helper
$privatePath = Join-Path $PSScriptRoot 'private'
$requiredHelpers = @(
    'Connect-PowerPlatform.ps1'
)
foreach ($helper in $requiredHelpers) {
    $helperPath = Join-Path $privatePath $helper
    if (-not (Test-Path $helperPath)) {
        throw "Required helper script not found: $helperPath. Ensure the solution is installed correctly."
    }
    . $helperPath
}

function Invoke-EnvironmentDiscovery {
    [CmdletBinding(DefaultParameterSetName = 'Interactive')]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TenantId,

        [Parameter(Mandatory = $true)]
        [string]$DataverseUrl,

        [Parameter(Mandatory = $false)]
        [string]$ClientId,

        [Parameter(Mandatory = $false)]
        [SecureString]$ClientSecret,

        [Parameter(Mandatory = $false)]
        [string]$CertificateThumbprint,

        [Parameter(Mandatory = $false)]
        [switch]$Interactive,

        [Parameter(Mandatory = $false)]
        [switch]$IncludeTrialDev,

        [Parameter(Mandatory = $false)]
        [string]$OutputPath
    )

    try {
        Write-Host "`n╔════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║          Power Platform Environment Discovery (EVAL-04)                ║" -ForegroundColor Cyan
        Write-Host "╚════════════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

        # Phase 0: Authenticate
        Write-Host "Phase 0: Authenticating to Power Platform and Dataverse..." -ForegroundColor Cyan
        $authParams = @{
            TenantId     = $TenantId
            DataverseUrl = $DataverseUrl
        }

        if ($ClientSecret) {
            $authParams.ClientId = $ClientId
            $authParams.ClientSecret = $ClientSecret
        }
        elseif ($CertificateThumbprint) {
            $authParams.ClientId = $ClientId
            $authParams.CertificateThumbprint = $CertificateThumbprint
        }
        else {
            $authParams.Interactive = $true
            if ($ClientId) {
                $authParams.ClientId = $ClientId
            }
        }

        $authResult = Connect-PowerPlatform @authParams

        if (-not $authResult.PowerAppsAuthenticated) {
            throw "Failed to authenticate to Power Platform Admin API."
        }

        if (-not $authResult.DataverseAccessToken) {
            throw "Failed to acquire Dataverse Web API access token."
        }

        $dataverseToken = $authResult.DataverseAccessToken
        $dataverseUrl = $authResult.DataverseUrl.TrimEnd('/')

        Write-Host "Authentication successful.`n" -ForegroundColor Green

        # Initialize tracking arrays
        $newEnvironments = @()
        $inactivatedEnvironments = @()
        $skippedUnclassified = @()
        $skippedTrialDev = @()
        $validationSet = @()

        # Phase A: Enumerate environments from Power Platform Admin API
        Write-Host "Phase A: Enumerating Power Platform environments..." -ForegroundColor Cyan

        try {
            $discoveredEnvironments = Get-AdminPowerAppEnvironment -ErrorAction Stop
        }
        catch {
            throw "Failed to enumerate environments. Ensure you have Power Platform Administrator or Global Administrator role. Error: $($_.Exception.Message)"
        }

        $totalDiscovered = $discoveredEnvironments.Count
        Write-Host "  Discovered $totalDiscovered environment(s) from Power Platform Admin API." -ForegroundColor Green

        # Map environment type strings to integers
        $envTypeMap = @{
            "Production" = 100000000
            "Sandbox"    = 100000001
            "Developer"  = 100000002
            "Trial"      = 100000003
            "Default"    = 100000004
        }

        # Build discovered environment lookup
        $discoveredEnvLookup = @{}
        foreach ($env in $discoveredEnvironments) {
            $envId = $env.EnvironmentName
            $envType = $env.EnvironmentType
            $envTypeInt = if ($envTypeMap.ContainsKey($envType)) { $envTypeMap[$envType] } else { 100000001 } # Default to Sandbox if unknown

            $discoveredEnvLookup[$envId] = @{
                EnvironmentId   = $envId
                DisplayName     = $env.DisplayName
                EnvironmentType = $envType
                EnvironmentTypeInt = $envTypeInt
                EnvironmentUrl  = $env.Internal.Properties.LinkedEnvironmentMetadata.InstanceApiUrl
            }
        }

        Write-Host "`nPhase B: Synchronizing to Dataverse environment registry..." -ForegroundColor Cyan

        # Phase B: Sync to Dataverse registry
        $headers = @{
            "Authorization"    = "Bearer $dataverseToken"
            "Content-Type"     = "application/json"
            "OData-MaxVersion" = "4.0"
            "OData-Version"    = "4.0"
            "Prefer"           = "return=representation"
        }

        # Query all existing registry entries
        $registryQueryUrl = "$dataverseUrl/api/data/v9.2/fsi_environmentregistries?`$select=fsi_environmentid,fsi_name,fsi_zone,fsi_status,fsi_environmenttype,fsi_overrideinclude"
        $registryResponse = Invoke-RestMethod -Uri $registryQueryUrl -Method Get -Headers $headers -ErrorAction Stop
        $registryEntries = $registryResponse.value

        Write-Host "  Found $($registryEntries.Count) existing registry entries." -ForegroundColor Gray

        # Build registry lookup
        $registryLookup = @{}
        foreach ($entry in $registryEntries) {
            $registryLookup[$entry.fsi_environmentid] = $entry
        }

        # Process discovered environments
        foreach ($envId in $discoveredEnvLookup.Keys) {
            $env = $discoveredEnvLookup[$envId]

            if ($registryLookup.ContainsKey($envId)) {
                # Existing registry entry: check for updates
                $registryEntry = $registryLookup[$envId]

                if (-not $registryEntry.fsi_environmentregistryid) {
                    Write-Warning "Registry entry missing ID field for environment $($env.DisplayName) — skipping update"
                    continue
                }

                # Check if environment type changed
                if ($registryEntry.fsi_environmenttype -ne $env.EnvironmentTypeInt) {
                    Write-Host "  Updating environment type for: $($env.DisplayName)" -ForegroundColor Yellow

                    $updateBody = @{
                        fsi_environmenttype = $env.EnvironmentTypeInt
                    } | ConvertTo-Json

                    $updateUrl = "$dataverseUrl/api/data/v9.2/fsi_environmentregistries($($registryEntry.fsi_environmentregistryid))"
                    Invoke-RestMethod -Uri $updateUrl -Method Patch -Headers $headers -Body $updateBody -ErrorAction Stop | Out-Null
                }

                # Ensure status is Active (might have been marked Inactive previously)
                if ($registryEntry.fsi_status -ne 1) {
                    Write-Host "  Reactivating environment: $($env.DisplayName)" -ForegroundColor Yellow

                    $updateBody = @{
                        fsi_status = 1
                    } | ConvertTo-Json

                    $updateUrl = "$dataverseUrl/api/data/v9.2/fsi_environmentregistries($($registryEntry.fsi_environmentregistryid))"
                    Invoke-RestMethod -Uri $updateUrl -Method Patch -Headers $headers -Body $updateBody -ErrorAction Stop | Out-Null
                }
            }
            else {
                # New environment: register with Unclassified zone and Active status
                Write-Host "  Registering new environment: $($env.DisplayName)" -ForegroundColor Green

                $createBody = @{
                    fsi_name            = $env.DisplayName
                    fsi_environmentid   = $envId
                    fsi_zone            = 100000000  # Unclassified
                    fsi_status          = 1  # Active
                    fsi_environmenttype = $env.EnvironmentTypeInt
                    fsi_environmenturl  = $env.EnvironmentUrl
                    fsi_discoveredon    = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
                    fsi_overrideinclude = $false
                } | ConvertTo-Json

                $createUrl = "$dataverseUrl/api/data/v9.2/fsi_environmentregistries"
                Invoke-RestMethod -Uri $createUrl -Method Post -Headers $headers -Body $createBody -ErrorAction Stop | Out-Null

                $newEnvironments += $env.DisplayName

                Write-Warning "New environment discovered: $($env.DisplayName) — requires zone classification before validation"
            }
        }

        # Check for deprovisioned environments (in registry but not discovered)
        foreach ($registryEntry in $registryEntries) {
            $envId = $registryEntry.fsi_environmentid

            if (-not $discoveredEnvLookup.ContainsKey($envId) -and $registryEntry.fsi_status -eq 1) {
                # Environment no longer exists in API but is Active in registry: mark Inactive
                Write-Host "  Environment no longer found, marking Inactive: $($registryEntry.fsi_name)" -ForegroundColor Yellow

                $updateBody = @{
                    fsi_status = 2  # Inactive
                } | ConvertTo-Json

                $updateUrl = "$dataverseUrl/api/data/v9.2/fsi_environmentregistries($($registryEntry.fsi_environmentregistryid))"
                Invoke-RestMethod -Uri $updateUrl -Method Patch -Headers $headers -Body $updateBody -ErrorAction Stop | Out-Null

                $inactivatedEnvironments += $registryEntry.fsi_name

                Write-Warning "Environment $($registryEntry.fsi_name) no longer found — marked Inactive"
            }
        }

        Write-Host "  Registry synchronization complete." -ForegroundColor Green

        # Phase C: Filter and return validation set
        Write-Host "`nPhase C: Building validation set..." -ForegroundColor Cyan

        # Re-query registry to get updated state (includes new registrations)
        $registryQueryUrl = "$dataverseUrl/api/data/v9.2/fsi_environmentregistries?`$select=fsi_environmentid,fsi_name,fsi_zone,fsi_status,fsi_environmenttype,fsi_overrideinclude&`$filter=fsi_status eq 1"
        $registryResponse = Invoke-RestMethod -Uri $registryQueryUrl -Method Get -Headers $headers -ErrorAction Stop
        $activeRegistryEntries = $registryResponse.value

        Write-Host "  Processing $($activeRegistryEntries.Count) active registry entries..." -ForegroundColor Gray

        foreach ($registryEntry in $activeRegistryEntries) {
            $envId = $registryEntry.fsi_environmentid

            # Skip if environment not in discovered set (shouldn't happen, but defensive)
            if (-not $discoveredEnvLookup.ContainsKey($envId)) {
                continue
            }

            $env = $discoveredEnvLookup[$envId]

            # Filter 1: Exclude Unclassified environments
            if ($registryEntry.fsi_zone -eq 100000000) {
                $skippedUnclassified += $env.DisplayName
                Write-Warning "Skipping $($env.DisplayName): zone is Unclassified. Assign zone before validation."
                continue
            }

            # Filter 2: Exclude Trial/Developer environments (unless IncludeTrialDev or OverrideInclude)
            if (-not $IncludeTrialDev -and ($env.EnvironmentTypeInt -eq 100000002 -or $env.EnvironmentTypeInt -eq 100000003)) {
                # Check OverrideInclude flag
                if (-not $registryEntry.fsi_overrideinclude) {
                    $skippedTrialDev += $env.DisplayName
                    Write-Host "  Skipping $($env.DisplayName): Trial/Developer environment (excluded by policy)" -ForegroundColor Gray
                    continue
                }
            }

            # Add to validation set
            $validationSet += @{
                EnvironmentId   = $envId
                EnvironmentName = $env.DisplayName
                Zone            = switch ($registryEntry.fsi_zone) {
                    100000001 { "Zone1" }
                    100000002 { "Zone2" }
                    100000003 { "Zone3" }
                    default { "Unclassified" }
                }
                EnvironmentUrl  = $env.EnvironmentUrl
                EnvironmentType = $env.EnvironmentType
            }

            Write-Host "  Included: $($env.DisplayName) (Zone $($registryEntry.fsi_zone))" -ForegroundColor Green
        }

        Write-Host "`n  Validation set: $($validationSet.Count) environment(s) ready for audit validation." -ForegroundColor Green

        # Build result object
        $result = [PSCustomObject]@{
            Timestamp                = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
            TotalDiscovered          = $totalDiscovered
            NewEnvironments          = $newEnvironments
            InactivatedEnvironments  = $inactivatedEnvironments
            SkippedUnclassified      = $skippedUnclassified
            SkippedTrialDev          = $skippedTrialDev
            ValidationSet            = $validationSet
        }

        # Export to JSON if OutputPath provided
        if ($OutputPath) {
            $result | ConvertTo-Json -Depth 10 | Out-File -FilePath $OutputPath -Encoding UTF8
            Write-Host "`nDiscovery results exported to: $OutputPath" -ForegroundColor Cyan
        }

        Write-Host "`n╔════════════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║                    Discovery Complete                                  ║" -ForegroundColor Cyan
        Write-Host "╚════════════════════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

        return $result
    }
    catch {
        Write-Host "`n[ERROR] Environment discovery failed: $($_.Exception.Message)" -ForegroundColor Red
        throw
    }
}

# Execute function if script is run directly (not dot-sourced)
if ($MyInvocation.InvocationName -ne '.') {
    $result = Invoke-EnvironmentDiscovery @PSBoundParameters
    return $result
}

# Note: This script is dot-sourced; do not use Export-ModuleMember outside a .psm1 module.
