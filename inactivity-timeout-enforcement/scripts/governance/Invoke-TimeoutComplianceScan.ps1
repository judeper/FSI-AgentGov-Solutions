#Requires -Version 7.0
#Requires -Modules Microsoft.PowerApps.Administration.PowerShell

<#
.SYNOPSIS
    Scans inactivity timeout configuration across Power Platform environments for zone compliance.

.DESCRIPTION
    Main scanning script for the Inactivity Timeout Enforcement (ITE) solution.
    Enumerates Power Platform environments, retrieves governance configuration
    via the BAP Admin API, and evaluates inactivity timeout settings against
    zone-specific policies.

    For each environment the script:
    1. Authenticates to Power Platform Admin API via service principal credentials
    2. Enumerates environments (with optional sandbox exclusion and name filtering)
    3. Classifies each environment into a governance zone via ELM lookup or naming convention
    4. Retrieves privacy/governance settings from BAP Admin API
    5. Parses inactivity timeout configuration (enabled state and ISO 8601 duration)
    6. Loads zone policy via Get-ExpectedTimeoutPolicy
    7. Evaluates compliance:
       - Compliant: enabled AND duration within zone maximum
       - NonCompliant: disabled when required, or duration exceeds zone maximum
       - Unknown: API error, missing policy data, or enabled with null duration
    8. Optionally persists results to Dataverse tables
    9. Outputs results in the specified format

    This script supports Controls 2.22 (Inactivity Timeout), 1.23 (Session Security),
    and 3.7/3.8 (Monitoring) of the FSI Agent Governance Framework.

.PARAMETER TenantId
    Microsoft Entra ID tenant GUID. Defaults to $env:AZURE_TENANT_ID.

.PARAMETER ClientId
    Service principal application (client) ID. Defaults to $env:AZURE_CLIENT_ID.

.PARAMETER ClientSecret
    Service principal client secret as SecureString. If not provided, attempts
    to read from $env:AZURE_CLIENT_SECRET.

.PARAMETER BapApiBaseUrl
    Base URL for the Business Application Platform Admin API.
    Default: https://api.bap.microsoft.com

.PARAMETER EnvironmentFilter
    Optional list of environment display names or IDs to limit the scan scope.
    When omitted, all accessible environments are scanned.

.PARAMETER ExcludeSandbox
    Exclude sandbox environments from scan. Default: $true.

.PARAMETER DataverseUrl
    Dataverse organization URL for persisting results. When provided, compliance
    records are written to fsi_inactivitytimeoutcompliances and errors to
    fsi_inactivitytimeouterrorlogs.

.PARAMETER OutputFormat
    Output format: Table (default), JSON, or Object.

.OUTPUTS
    Formatted table, JSON string, or PSCustomObject[] depending on -OutputFormat.
    Each result includes: EnvironmentName, EnvironmentId, Zone, TimeoutEnabled,
    TimeoutDurationMinutes, MaxAllowedMinutes, ComplianceStatus, Severity, RunId.

.EXAMPLE
    .\Invoke-TimeoutComplianceScan.ps1

    Scan all non-sandbox environments using environment variable credentials.
    Outputs results as formatted table.

.EXAMPLE
    .\Invoke-TimeoutComplianceScan.ps1 -EnvironmentFilter @("Prod-Zone3") -OutputFormat JSON

    Scan a specific environment with JSON output for evidence pipeline integration.

.EXAMPLE
    .\Invoke-TimeoutComplianceScan.ps1 `
        -DataverseUrl "https://org.crm.dynamics.com" `
        -OutputFormat Object

    Full scan with Dataverse persistence, returning PSCustomObjects for pipeline use.

.NOTES
    Version: 1.0.0
    Solution: Inactivity Timeout Enforcement (ITE)
    Controls: 2.22 (Inactivity Timeout), 1.23 (Session Security), 3.7/3.8 (Monitoring)
    Regulations: GLBA 501(b), SOX 302/404, FINRA 4511, NIST 800-53 AC-11/AC-12
#>

function Invoke-TimeoutComplianceScan {
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$TenantId = $env:AZURE_TENANT_ID,

        [Parameter()]
        [string]$ClientId = $env:AZURE_CLIENT_ID,

        [Parameter()]
        [SecureString]$ClientSecret,

        [Parameter()]
        [string]$BapApiBaseUrl = 'https://api.bap.microsoft.com',

        [Parameter()]
        [string[]]$EnvironmentFilter,

        [Parameter()]
        [switch]$ExcludeSandbox = $true,

        [Parameter()]
        [string]$DataverseUrl,

        [Parameter()]
        [ValidateSet('Table', 'JSON', 'Object')]
        [string]$OutputFormat = 'Table'
    )

    $ErrorActionPreference = 'Stop'
    $scriptRoot = $PSScriptRoot
    $runId = [guid]::NewGuid().ToString()
    $scanStartTime = Get-Date -Format 'o'

    Write-Verbose "========================================="
    Write-Verbose "Inactivity Timeout Enforcement v1.0.0"
    Write-Verbose "RunId: $runId"
    Write-Verbose "ScanStart: $scanStartTime"
    Write-Verbose "========================================="

    #region Helper: ISO 8601 Duration Parser

    function ConvertFrom-Iso8601Duration {
        <#
        .SYNOPSIS
            Converts an ISO 8601 duration string to total minutes.
        .DESCRIPTION
            Parses ISO 8601 duration format (e.g., PT60M, PT2H, PT1H30M) and
            returns the total duration in minutes. Supports hours (H) and
            minutes (M) components within the time designator (T).
        .PARAMETER Duration
            ISO 8601 duration string (e.g., PT60M, PT2H, PT1H30M).
        .OUTPUTS
            Int32 — total minutes, or -1 if parsing fails.
        #>
        param(
            [Parameter(Mandatory = $true)]
            [string]$Duration
        )

        if ([string]::IsNullOrWhiteSpace($Duration)) {
            return -1
        }

        $normalized = $Duration.Trim().ToUpperInvariant()

        if ($normalized -notmatch '^PT') {
            Write-Verbose "Duration does not start with PT: $Duration"
            return -1
        }

        $totalMinutes = 0
        $timePart = $normalized.Substring(2)

        # Extract hours
        if ($timePart -match '(\d+)H') {
            $totalMinutes += [int]$Matches[1] * 60
            $timePart = $timePart -replace '\d+H', ''
        }

        # Extract minutes
        if ($timePart -match '(\d+)M') {
            $totalMinutes += [int]$Matches[1]
        }

        return $totalMinutes
    }

    #endregion

    #region Import Companion Scripts

    $policyScript = Join-Path $scriptRoot 'Get-ExpectedTimeoutPolicy.ps1'
    if (-not (Test-Path $policyScript)) {
        throw "Required script not found: $policyScript"
    }

    #endregion

    #region Authentication

    Write-Host ""
    Write-Host "Inactivity Timeout Enforcement v1.0.0" -ForegroundColor Cyan
    Write-Host "RunId: $runId" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "[1/5] Authenticating to Power Platform Admin API..." -ForegroundColor Cyan

    if (-not $TenantId) {
        throw "TenantId is required. Set -TenantId or `$env:AZURE_TENANT_ID."
    }
    if (-not $ClientId) {
        throw "ClientId is required. Set -ClientId or `$env:AZURE_CLIENT_ID."
    }

    # Resolve client secret
    $plainSecret = $null
    if ($ClientSecret) {
        $plainSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR(
            [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)
        )
    }
    elseif ($env:AZURE_CLIENT_SECRET) {
        $plainSecret = $env:AZURE_CLIENT_SECRET
    }
    else {
        throw "ClientSecret is required. Set -ClientSecret or `$env:AZURE_CLIENT_SECRET."
    }

    # Acquire token for BAP Admin API
    $tokenBody = @{
        grant_type    = 'client_credentials'
        client_id     = $ClientId
        client_secret = $plainSecret
        scope         = 'https://service.powerapps.com/.default'
    }
    try {
        $tokenResponse = Invoke-RestMethod `
            -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
            -Method Post `
            -ContentType 'application/x-www-form-urlencoded' `
            -Body $tokenBody `
            -ErrorAction Stop

        $bapToken = $tokenResponse.access_token
        Write-Host "  BAP API authentication successful." -ForegroundColor Green
    }
    catch {
        throw "BAP API authentication failed: $($_.Exception.Message)"
    }

    # If DataverseUrl provided, acquire a Dataverse token
    $dataverseToken = $null
    if ($DataverseUrl) {
        $dvTokenBody = @{
            grant_type    = 'client_credentials'
            client_id     = $ClientId
            client_secret = $plainSecret
            scope         = "$($DataverseUrl.TrimEnd('/'))/.default"
        }
        try {
            $dvTokenResponse = Invoke-RestMethod `
                -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
                -Method Post `
                -ContentType 'application/x-www-form-urlencoded' `
                -Body $dvTokenBody `
                -ErrorAction Stop
            $dataverseToken = $dvTokenResponse.access_token
            Write-Host "  Dataverse authentication successful." -ForegroundColor Green
        }
        catch {
            Write-Warning "Dataverse authentication failed. Results will not be persisted: $($_.Exception.Message)"
            $DataverseUrl = $null
        }
    }

    #endregion

    #region Enumerate Environments

    Write-Host "[2/5] Enumerating Power Platform environments..." -ForegroundColor Cyan

    try {
        $allEnvironments = Get-AdminPowerAppEnvironment -ErrorAction Stop
    }
    catch {
        throw "Failed to enumerate environments. Verify Microsoft.PowerApps.Administration.PowerShell is installed and authenticated: $($_.Exception.Message)"
    }

    $environments = $allEnvironments | Where-Object {
        $env = $_
        $include = $true

        if ($EnvironmentFilter) {
            $matchesFilter = ($env.EnvironmentName -in $EnvironmentFilter) -or
                             ($env.DisplayName -in $EnvironmentFilter)
            if (-not $matchesFilter) { $include = $false }
        }
        if ($ExcludeSandbox -and $env.EnvironmentType -eq 'Sandbox') {
            $include = $false
        }

        $include
    }

    Write-Host "  Found $($environments.Count) environment(s) to scan (of $($allEnvironments.Count) total)"

    #endregion

    #region Zone Classification Helper

    function Get-EnvironmentZone {
        param(
            [string]$EnvironmentId,
            [string]$EnvironmentDisplayName
        )

        # Try shared zone classification script
        $sharedZoneScript = Join-Path (Split-Path (Split-Path $scriptRoot -Parent) -Parent) 'scripts\shared\Get-ZoneClassification.ps1'
        if (Test-Path $sharedZoneScript) {
            try {
                $zone = & $sharedZoneScript `
                    -EnvironmentId $EnvironmentId `
                    -EnvironmentDisplayName $EnvironmentDisplayName
                if ($zone) { return $zone }
            }
            catch {
                Write-Verbose "Shared zone classification failed: $($_.Exception.Message)"
            }
        }

        # Fallback: naming convention
        $normalized = $EnvironmentDisplayName.ToLower()
        if ($normalized -match 'z3|zone3|prod|production|enterprise') { return 'Zone3' }
        if ($normalized -match 'z2|zone2|team|collab|shared')         { return 'Zone2' }
        if ($normalized -match 'z1|zone1|personal|dev|sandbox')       { return 'Zone1' }

        return 'Unknown'
    }

    #endregion

    #region Scan Environments

    Write-Host "[3/5] Scanning inactivity timeout configurations..." -ForegroundColor Cyan

    $results     = [System.Collections.Generic.List[PSCustomObject]]::new()
    $errorLogs   = [System.Collections.Generic.List[PSCustomObject]]::new()
    $bapHeaders  = @{
        'Authorization' = "Bearer $bapToken"
        'Accept'        = 'application/json'
    }

    foreach ($environment in $environments) {
        $envId   = $environment.EnvironmentName
        $envName = $environment.DisplayName

        Write-Verbose "Scanning environment: $envName ($envId)"

        $zone = Get-EnvironmentZone -EnvironmentId $envId -EnvironmentDisplayName $envName
        Write-Verbose "  Zone: $zone"

        $policy = & $policyScript -Zone $zone

        # Retrieve governance configuration from BAP Admin API
        $timeoutEnabled = $null
        $timeoutDuration = $null
        $timeoutMinutes = -1
        $apiError = $null

        try {
            $govConfigUrl = "$($BapApiBaseUrl.TrimEnd('/'))/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments/$envId/governanceConfiguration?api-version=2021-04-01"

            $govResponse = Invoke-RestMethod `
                -Uri $govConfigUrl `
                -Headers $bapHeaders `
                -Method Get `
                -ErrorAction Stop

            # Parse privacy settings for inactivity timeout
            $privacySettings = $govResponse.properties.settings
            if ($null -ne $privacySettings) {
                $timeoutEnabled = $privacySettings.sessionTimeoutEnabled
                $timeoutDuration = $privacySettings.sessionTimeoutInactivityDuration

                if ($timeoutEnabled -and $timeoutDuration) {
                    $timeoutMinutes = ConvertFrom-Iso8601Duration -Duration $timeoutDuration
                }
            }
        }
        catch {
            $apiError = $_.Exception.Message
            Write-Warning "  Failed to retrieve governance config for $envName`: $apiError"

            $errorLogs.Add([PSCustomObject]@{
                RunId           = $runId
                EnvironmentId   = $envId
                EnvironmentName = $envName
                Zone            = $zone
                ErrorMessage    = $apiError
                ErrorTime       = (Get-Date -Format 'o')
            })
        }

        # Evaluate compliance
        $complianceStatus = 'Unknown'
        $details = ''

        if ($null -ne $apiError) {
            $complianceStatus = 'Unknown'
            $details = "API error retrieving governance configuration: $apiError"
        }
        elseif ($null -eq $timeoutEnabled) {
            $complianceStatus = 'Unknown'
            $details = 'Timeout configuration not found in governance response'
        }
        elseif ($policy.TimeoutRequired -and -not $timeoutEnabled) {
            $complianceStatus = 'NonCompliant'
            $details = "Inactivity timeout is disabled but required for $zone (max $($policy.MaxDurationMinutes) min)"
        }
        elseif ($timeoutEnabled -and $timeoutMinutes -lt 0) {
            $complianceStatus = 'Unknown'
            $details = "Timeout enabled but duration could not be parsed: $timeoutDuration"
        }
        elseif ($timeoutEnabled -and $timeoutMinutes -gt $policy.MaxDurationMinutes) {
            $complianceStatus = 'NonCompliant'
            $details = "Timeout duration ($timeoutMinutes min) exceeds zone maximum ($($policy.MaxDurationMinutes) min)"
        }
        elseif ($timeoutEnabled -and $timeoutMinutes -le $policy.MaxDurationMinutes) {
            $complianceStatus = 'Compliant'
            $details = "Timeout enabled at $timeoutMinutes min (zone max: $($policy.MaxDurationMinutes) min)"
        }
        elseif (-not $policy.TimeoutRequired -and -not $timeoutEnabled) {
            # Zone 1: timeout not required and not enabled — compliant
            $complianceStatus = 'Compliant'
            $details = "Timeout not required for $zone and is disabled"
        }
        else {
            $complianceStatus = 'Unknown'
            $details = "Unexpected configuration state"
        }

        $result = [PSCustomObject]@{
            RunId                  = $runId
            EnvironmentId          = $envId
            EnvironmentName        = $envName
            Zone                   = $zone
            TimeoutEnabled         = $timeoutEnabled
            TimeoutDuration        = $timeoutDuration
            TimeoutDurationMinutes = if ($timeoutMinutes -ge 0) { $timeoutMinutes } else { $null }
            MaxAllowedMinutes      = $policy.MaxDurationMinutes
            TimeoutRequired        = $policy.TimeoutRequired
            ComplianceStatus       = $complianceStatus
            Severity               = if ($complianceStatus -eq 'NonCompliant') { $policy.ViolationSeverity } elseif ($complianceStatus -eq 'Unknown') { 'Warning' } else { 'Info' }
            RegulatoryContext      = ($policy.RegulatoryContext -join '; ')
            Details                = $details
            ScanTime               = $scanStartTime
        }

        $results.Add($result)

        $statusColor = switch ($complianceStatus) {
            'Compliant'    { 'Green' }
            'NonCompliant' { 'Red' }
            'Unknown'      { 'Yellow' }
            default        { 'White' }
        }
        Write-Host "  $envName [$zone]: $complianceStatus" -ForegroundColor $statusColor
    }

    Write-Host "  Scanned $($environments.Count) environment(s)" -ForegroundColor Green

    #endregion

    #region Persist Results to Dataverse

    Write-Host "[4/5] Persisting results..." -ForegroundColor Cyan

    if ($DataverseUrl -and $dataverseToken) {
        $apiBase = "$($DataverseUrl.TrimEnd('/'))/api/data/v9.2"
        $dvHeaders = @{
            'Authorization'    = "Bearer $dataverseToken"
            'Content-Type'     = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }

        # Persist compliance results
        $persistedCount = 0
        foreach ($r in $results) {
            try {
                $record = @{
                    'fsi_name'                    = "ITE-$($r.EnvironmentName)-$runId".Substring(0, [Math]::Min(100, "ITE-$($r.EnvironmentName)-$runId".Length))
                    'fsi_environmentid'           = $r.EnvironmentId
                    'fsi_environmentname'         = $r.EnvironmentName
                    'fsi_zone'                    = $r.Zone
                    'fsi_timeoutenabled'          = $r.TimeoutEnabled
                    'fsi_timeoutduration'         = $r.TimeoutDuration
                    'fsi_timeoutdurationminutes'  = $r.TimeoutDurationMinutes
                    'fsi_maxallowedminutes'       = $r.MaxAllowedMinutes
                    'fsi_timeoutrequired'         = $r.TimeoutRequired
                    'fsi_compliancestatus'        = $r.ComplianceStatus
                    'fsi_severity'                = $r.Severity
                    'fsi_regulatorycontext'       = $r.RegulatoryContext
                    'fsi_details'                 = $r.Details
                    'fsi_scanrunid'               = $r.RunId
                    'fsi_scantime'                = $r.ScanTime
                }

                Invoke-RestMethod `
                    -Uri "$apiBase/fsi_inactivitytimeoutcompliances" `
                    -Headers $dvHeaders `
                    -Method Post `
                    -Body ($record | ConvertTo-Json -Compress) `
                    -ErrorAction Stop | Out-Null

                $persistedCount++
            }
            catch {
                Write-Warning "  Failed to persist record for $($r.EnvironmentName): $($_.Exception.Message)"
            }
        }
        Write-Host "  Persisted $persistedCount of $($results.Count) compliance record(s)" -ForegroundColor Green

        # Persist error logs
        if ($errorLogs.Count -gt 0) {
            $errorPersisted = 0
            foreach ($e in $errorLogs) {
                try {
                    $errorRecord = @{
                        'fsi_name'            = "ITE-ERR-$($e.EnvironmentName)-$runId".Substring(0, [Math]::Min(100, "ITE-ERR-$($e.EnvironmentName)-$runId".Length))
                        'fsi_environmentid'   = $e.EnvironmentId
                        'fsi_environmentname' = $e.EnvironmentName
                        'fsi_zone'            = $e.Zone
                        'fsi_errormessage'    = $e.ErrorMessage
                        'fsi_errortime'       = $e.ErrorTime
                        'fsi_scanrunid'       = $e.RunId
                    }

                    Invoke-RestMethod `
                        -Uri "$apiBase/fsi_inactivitytimeouterrorlogs" `
                        -Headers $dvHeaders `
                        -Method Post `
                        -Body ($errorRecord | ConvertTo-Json -Compress) `
                        -ErrorAction Stop | Out-Null

                    $errorPersisted++
                }
                catch {
                    Write-Warning "  Failed to persist error log for $($e.EnvironmentName): $($_.Exception.Message)"
                }
            }
            Write-Host "  Persisted $errorPersisted error log(s)" -ForegroundColor Yellow
        }
    }
    elseif (-not $DataverseUrl) {
        Write-Host "  Persistence skipped (-DataverseUrl not specified)" -ForegroundColor DarkGray
    }

    #endregion

    #region Output Results

    Write-Host "[5/5] Generating output..." -ForegroundColor Cyan
    Write-Host ""

    # Summary
    $compliantCount    = ($results | Where-Object { $_.ComplianceStatus -eq 'Compliant' }).Count
    $nonCompliantCount = ($results | Where-Object { $_.ComplianceStatus -eq 'NonCompliant' }).Count
    $unknownCount      = ($results | Where-Object { $_.ComplianceStatus -eq 'Unknown' }).Count

    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host "SCAN COMPLETE" -ForegroundColor Cyan
    Write-Host "  RunId:           $runId"
    Write-Host "  Environments:    $($results.Count)"
    Write-Host "  Compliant:       $compliantCount" -ForegroundColor Green
    Write-Host "  Non-Compliant:   $nonCompliantCount" -ForegroundColor $(if ($nonCompliantCount -gt 0) { 'Red' } else { 'Green' })
    Write-Host "  Unknown:         $unknownCount" -ForegroundColor $(if ($unknownCount -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "  Errors:          $($errorLogs.Count)" -ForegroundColor $(if ($errorLogs.Count -gt 0) { 'Yellow' } else { 'Green' })
    Write-Host "=======================================" -ForegroundColor Cyan
    Write-Host ""

    switch ($OutputFormat) {
        'JSON' {
            return ($results | ConvertTo-Json -Depth 5)
        }
        'Object' {
            return $results.ToArray()
        }
        default {
            if ($results.Count -gt 0) {
                $results | Format-Table -Property EnvironmentName, Zone, TimeoutEnabled, TimeoutDurationMinutes, MaxAllowedMinutes, ComplianceStatus, Severity -AutoSize
            }
            else {
                Write-Host "No environments found matching filter criteria." -ForegroundColor Yellow
            }
        }
    }

    #endregion
}
