#Requires -Version 7.0
#Requires -Modules @{ ModuleName='Az.Accounts'; ModuleVersion='2.17.0' }

<#
.SYNOPSIS
    Scans inactivity timeout configuration across Power Platform environments for zone compliance.

.DESCRIPTION
    Main scanning script for the Inactivity Timeout Enforcement (ITE) solution.
    Enumerates Power Platform environments, retrieves governance configuration
    via the BAP Admin API, and evaluates inactivity timeout settings against
    zone-specific policies.

    For each environment the script:
    1. Authenticates to Power Platform Admin API via managed identity by default, with legacy client-secret fallback for development
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
    Application/client ID for user-assigned managed identity or legacy client-secret fallback. Defaults to $env:AZURE_CLIENT_ID.

.PARAMETER ClientSecret
    Legacy dev-only service principal client secret as SecureString. If not provided, the script attempts managed identity authentication before reading $env:AZURE_CLIENT_SECRET.

.PARAMETER UseManagedIdentity
    Prefer Azure managed identity for BAP and Dataverse token acquisition. This is the recommended automation mode.

.PARAMETER ManagedIdentityClientId
    Optional user-assigned managed identity client ID. Defaults to $env:AZURE_CLIENT_ID when present.

.PARAMETER BapApiBaseUrl
    Base URL for the Business Application Platform Admin API.
    Default: https://api.bap.microsoft.com

.PARAMETER EnvironmentFilter
    Optional list of environment display names or IDs to limit the scan scope.
    When omitted, all accessible environments are scanned.

.PARAMETER ExcludeSandbox
    Exclude sandbox environments from scan. Default: $false; sandboxes are included unless this switch is specified.

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
    Version: 1.1.2
    Solution: Inactivity Timeout Enforcement (ITE)
    Controls: 2.22 (Inactivity Timeout), 1.23 (Session Security), 3.7/3.8 (Monitoring)
    Regulations: GLBA Section 501(b), SOX Section 302, SOX Section 404, FINRA Rule 4511(a), NIST 800-53 AC-11/AC-12
#>

# Script-level params: when this file is invoked directly (e.g.,
# `.\Invoke-TimeoutComplianceScan.ps1 -DataverseUrl ...`) these capture the
# arguments and forward them to the inner function. When the file is
# dot-sourced (Test-TimeoutCompliance.ps1), no arguments are supplied so the
# function is simply registered without side effects.
[CmdletBinding()]
param(
    [Parameter()] [string]$TenantId,
    [Parameter()] [string]$ClientId,
    [Parameter()] [SecureString]$ClientSecret,
    [Parameter()] [switch]$UseManagedIdentity,
    [Parameter()] [string]$ManagedIdentityClientId = $env:AZURE_CLIENT_ID,
    [Parameter()] [string]$BapApiBaseUrl = 'https://api.bap.microsoft.com',
    [Parameter()] [string[]]$EnvironmentFilter,
    [Parameter()] [switch]$ExcludeSandbox,
    [Parameter()] [string]$DataverseUrl,
    [Parameter()] [ValidateSet('Table', 'JSON', 'Object')] [string]$OutputFormat = 'Table'
)

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
        [switch]$UseManagedIdentity,

        [Parameter()]
        [string]$ManagedIdentityClientId = $env:AZURE_CLIENT_ID,

        [Parameter()]
        [string]$BapApiBaseUrl = 'https://api.bap.microsoft.com',

        [Parameter()]
        [string[]]$EnvironmentFilter,

        [Parameter()]
        [switch]$ExcludeSandbox,

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
    Write-Verbose "Inactivity Timeout Enforcement v1.1.2"
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

            Intentional limitation: this parser does NOT handle the days (D),
            seconds (S), weeks (W), or pure-date (no T) components. The BAP API
            governanceConfiguration?api-version=2021-04-01 contract only returns
            PTnM or PTnH durations for inactivityTimeoutDuration, so wider ISO
            8601 coverage is unnecessary. If a future BAP API revision adds D
            or S components, extend this function and re-run validation.
        .PARAMETER Duration
            ISO 8601 duration string (e.g., PT60M, PT2H, PT1H30M).
        .OUTPUTS
            Int32 -- total minutes, or -1 if parsing fails.
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


    #region Authentication Helpers

    function ConvertTo-PlainAccessToken {
        param([Parameter(Mandatory = $true)]$Token)

        if ($Token -is [securestring]) {
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($Token)
            try {
                return [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            }
            finally {
                if ($bstr -ne [IntPtr]::Zero) {
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                }
            }
        }

        return [string]$Token
    }

    function Get-IteManagedIdentityToken {
        param(
            [Parameter(Mandatory = $true)]
            [string]$ResourceUrl,

            [Parameter()]
            [string]$TenantId,

            [Parameter()]
            [string]$ManagedIdentityClientId
        )

        if (-not (Get-Command Connect-AzAccount -ErrorAction SilentlyContinue) -or -not (Get-Command Get-AzAccessToken -ErrorAction SilentlyContinue)) {
            throw "Az.Accounts is required for managed identity authentication. Install Az.Accounts or use the legacy client-secret fallback only for development."
        }

        $connectParams = @{ Identity = $true; ErrorAction = 'Stop' }
        if ($ManagedIdentityClientId) {
            $connectParams.AccountId = $ManagedIdentityClientId
        }
        if ($TenantId) {
            $connectParams.Tenant = $TenantId
        }
        Connect-AzAccount @connectParams | Out-Null

        $tokenParams = @{ ResourceUrl = $ResourceUrl; ErrorAction = 'Stop' }
        if ($TenantId) {
            $tokenParams.TenantId = $TenantId
        }
        $tokenResult = Get-AzAccessToken @tokenParams
        return ConvertTo-PlainAccessToken -Token $tokenResult.Token
    }

    #endregion

    #region Authentication

    Write-Host ""
    Write-Host "Inactivity Timeout Enforcement v1.1.2" -ForegroundColor Cyan
    Write-Host "RunId: $runId" -ForegroundColor DarkGray
    Write-Host ""
    Write-Host "[1/5] Authenticating to Power Platform Admin API..." -ForegroundColor Cyan

    if (-not $TenantId) {
        throw "TenantId is required. Set -TenantId or `$env:AZURE_TENANT_ID."
    }

    $useManagedIdentityAuth = $UseManagedIdentity -or (-not $ClientSecret -and -not $env:AZURE_CLIENT_SECRET)

    if ($useManagedIdentityAuth) {
        try {
            $bapToken = Get-IteManagedIdentityToken `
                -ResourceUrl 'https://service.powerapps.com/' `
                -TenantId $TenantId `
                -ManagedIdentityClientId $ManagedIdentityClientId
            Write-Host "  BAP API managed identity authentication successful." -ForegroundColor Green
        }
        catch {
            throw "BAP API managed identity authentication failed: $($_.Exception.Message)"
        }
    }
    else {
        # legacy: dev-only -- replace with managed identity in production
        if (-not $ClientId) {
            throw "ClientId is required for legacy client-secret authentication. Prefer -UseManagedIdentity for automation."
        }

        $plainSecret = $null
        if ($ClientSecret) {
            $bstr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)
            try {
                $plainSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)
            }
            finally {
                if ($bstr -ne [IntPtr]::Zero) {
                    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
                }
            }
        }
        elseif ($env:AZURE_CLIENT_SECRET) {
            $plainSecret = $env:AZURE_CLIENT_SECRET
        }
        else {
            throw "ClientSecret is a legacy dev-only fallback. Set -UseManagedIdentity or provide `$env:AZURE_CLIENT_SECRET for development only."
        }

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
            Write-Host "  BAP API legacy client-secret authentication successful." -ForegroundColor Yellow
        }
        catch {
            throw "BAP API legacy client-secret authentication failed: $($_.Exception.Message)"
        }
    }

    $bapHeaders = @{
        'Authorization' = "Bearer $bapToken"
        'Accept'        = 'application/json'
    }

    $dataverseToken = $null
    if ($DataverseUrl) {
        if ($useManagedIdentityAuth) {
            try {
                $dataverseToken = Get-IteManagedIdentityToken `
                    -ResourceUrl $($DataverseUrl.TrimEnd('/')) `
                    -TenantId $TenantId `
                    -ManagedIdentityClientId $ManagedIdentityClientId
                Write-Host "  Dataverse managed identity authentication successful." -ForegroundColor Green
            }
            catch {
                Write-Warning "Dataverse managed identity authentication failed. Results will not be persisted: $($_.Exception.Message)"
                $DataverseUrl = $null
            }
        }
        else {
            # legacy: dev-only -- replace with managed identity in production
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
                Write-Host "  Dataverse legacy client-secret authentication successful." -ForegroundColor Yellow
            }
            catch {
                Write-Warning "Dataverse legacy client-secret authentication failed. Results will not be persisted: $($_.Exception.Message)"
                $DataverseUrl = $null
            }
        }
    }

    #endregion

    #region Enumerate Environments

    Write-Host "[2/5] Enumerating Power Platform environments..." -ForegroundColor Cyan

    try {
        $allEnvironments = [System.Collections.Generic.List[PSCustomObject]]::new()
        $nextUrl = "$($BapApiBaseUrl.TrimEnd('/'))/providers/Microsoft.BusinessAppPlatform/scopes/admin/environments?api-version=2016-11-01"

        while ($nextUrl) {
            $envResponse = Invoke-RestMethod `
                -Uri $nextUrl `
                -Headers $bapHeaders `
                -Method Get `
                -ErrorAction Stop

            foreach ($item in @($envResponse.value)) {
                $props = $item.properties
                $envId = if ($item.name) { $item.name } elseif ($item.environmentName) { $item.environmentName } elseif ($props.environmentName) { $props.environmentName } else { $item.id }
                $displayName = if ($props.displayName) { $props.displayName } elseif ($item.displayName) { $item.displayName } else { $envId }
                $environmentType = if ($props.environmentSku) { $props.environmentSku } elseif ($props.environmentType) { $props.environmentType } elseif ($item.environmentType) { $item.environmentType } else { '' }

                [void]$allEnvironments.Add([PSCustomObject]@{
                    EnvironmentName = $envId
                    DisplayName     = $displayName
                    EnvironmentType = $environmentType
                })
            }

            $nextUrl = if ($envResponse.'@odata.nextLink') { $envResponse.'@odata.nextLink' } elseif ($envResponse.nextLink) { $envResponse.nextLink } else { $null }
        }
    }
    catch {
        throw "Failed to enumerate environments from BAP Admin API. Verify managed identity or legacy credential has Power Platform Admin permissions: $($_.Exception.Message)"
    }

    $environments = $allEnvironments | Where-Object {
        $env = $_
        $include = $true

        if ($EnvironmentFilter) {
            $matchesFilter = ($env.EnvironmentName -in $EnvironmentFilter) -or
                             ($env.DisplayName -in $EnvironmentFilter)
            if (-not $matchesFilter) { $include = $false }
        }
        if ($ExcludeSandbox -and $env.EnvironmentType -match 'Sandbox') {
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

    $results   = [System.Collections.Generic.List[PSCustomObject]]::new()
    $errorLogs = [System.Collections.Generic.List[PSCustomObject]]::new()

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

            # Parse governance settings for inactivity timeout. The
            # `governanceConfiguration` API exposes inactivity timeouts under
            # `properties.settings` as `inactivityTimeoutEnabled` (boolean) and
            # `inactivityTimeoutDuration` (ISO 8601 duration). Older responses
            # may use `sessionTimeoutEnabled` / `sessionTimeoutInactivityDuration`,
            # so we accept either to be resilient across API versions.
            $privacySettings = $govResponse.properties.settings
            if ($null -ne $privacySettings) {
                $timeoutEnabled = if ($null -ne $privacySettings.inactivityTimeoutEnabled) {
                    $privacySettings.inactivityTimeoutEnabled
                } else {
                    $privacySettings.sessionTimeoutEnabled
                }
                $timeoutDuration = if ($null -ne $privacySettings.inactivityTimeoutDuration) {
                    $privacySettings.inactivityTimeoutDuration
                } else {
                    $privacySettings.sessionTimeoutInactivityDuration
                }

                if ($timeoutEnabled -and $timeoutDuration) {
                    $timeoutMinutes = ConvertFrom-Iso8601Duration -Duration $timeoutDuration
                }
            }
        }
        catch {
            $apiError = $_.Exception.Message
            $statusCode = $null
            try { $statusCode = [int]$_.Exception.Response.StatusCode } catch { $statusCode = $null }

            # Classify error to satisfy required fsi_errortype column
            $errorTypeLabel = switch ($statusCode) {
                401     { 'Unauthorized' }
                403     { 'Forbidden' }
                404     { 'NotFound' }
                429     { 'Throttled' }
                default {
                    if ($apiError -match 'parse|deserialize|json') { 'ParseError' } else { 'DataverseError' }
                }
            }
            Write-Warning "  Failed to retrieve governance config for $envName`: $apiError"

            $errorLogs.Add([PSCustomObject]@{
                RunId           = $runId
                EnvironmentId   = $envId
                EnvironmentName = $envName
                Zone            = $zone
                ErrorType       = $errorTypeLabel
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
            # Zone 1: timeout not required and not enabled -- compliant
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

        # Map picklist strings to Dataverse OptionSet integer values
        $zoneMap = @{ 'Zone1' = 100000001; 'Zone2' = 100000002; 'Zone3' = 100000003; 'Unknown' = 100000000 }
        $statusMap = @{ 'Compliant' = 100000000; 'NonCompliant' = 100000001; 'Unknown' = 100000002 }

        # Persist compliance results
        $persistedCount = 0
        foreach ($r in $results) {
            try {
                $record = @{
                    'fsi_compliancename'          = "ITE-$($r.EnvironmentName)-$runId".Substring(0, [Math]::Min(200, "ITE-$($r.EnvironmentName)-$runId".Length))
                    'fsi_environmentid'           = $r.EnvironmentId
                    'fsi_environmentname'         = $r.EnvironmentName
                    'fsi_zone'                    = $zoneMap[$r.Zone]
                    'fsi_inactivitytimeoutenabled' = $r.TimeoutEnabled
                    'fsi_timeoutduration'         = $r.TimeoutDuration
                    'fsi_timeoutdurationminutes'  = $r.TimeoutDurationMinutes
                    'fsi_requiredmaxduration'     = $r.MaxAllowedMinutes
                    'fsi_timeoutrequired'         = $r.TimeoutRequired
                    'fsi_compliancestatus'        = $statusMap[$r.ComplianceStatus]
                    'fsi_severity'                = $r.Severity
                    'fsi_regulatorycontext'       = $r.RegulatoryContext
                    'fsi_notes'                   = $r.Details
                    'fsi_scanrunid'               = $r.RunId
                    'fsi_lastscandate'            = $r.ScanTime
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
                    $errorTypeMap = @{
                        'MissingPolicy'  = 100000000
                        'Unauthorized'   = 100000001
                        'Forbidden'      = 100000002
                        'NotFound'       = 100000003
                        'Throttled'      = 100000004
                        'ParseError'     = 100000005
                        'DataverseError' = 100000006
                    }
                    $errorTypeInt = if ($e.ErrorType -and $errorTypeMap.ContainsKey($e.ErrorType)) {
                        $errorTypeMap[$e.ErrorType]
                    } else {
                        100000006  # DataverseError fallback satisfies required column
                    }

                    $errorRecord = @{
                        'fsi_errorname'       = "ITE-ERR-$($e.EnvironmentName)-$runId".Substring(0, [Math]::Min(200, "ITE-ERR-$($e.EnvironmentName)-$runId".Length))
                        'fsi_environmentid'   = $e.EnvironmentId
                        'fsi_environmentname' = $e.EnvironmentName
                        'fsi_zone'            = $zoneMap[$e.Zone]
                        'fsi_errortype'       = $errorTypeInt
                        'fsi_errorraw'        = $e.ErrorMessage
                        'fsi_timestamp'       = $e.ErrorTime
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

# When invoked directly (not dot-sourced), forward the script-level args to
# the function so admins can run `.\Invoke-TimeoutComplianceScan.ps1` with
# environment-based managed identity defaults or explicit parameters.
# Dot-sourcing (e.g., from Test-TimeoutCompliance.ps1) bypasses this block
# and only registers the function for explicit invocation.
if ($MyInvocation.InvocationName -ne '.') {
    Invoke-TimeoutComplianceScan @PSBoundParameters
}
