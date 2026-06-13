<#
.SYNOPSIS
    Agent Access Monitor Dataverse client module.

.DESCRIPTION
    Provides helper functions for Dataverse interaction with the AAM solution.
    Follows the proven SSCClient/ACVClient pattern with AAM_ environment variable prefix.

.NOTES
    Module: AAMClient.psm1
    Version: 1.2.0
    Author: FSI Agent Governance Team
#>

#region Module Variables

$script:DataverseUrl = $null
$script:AccessToken = $null
$script:ClientId = $null
$script:TenantId = $null
$script:TokenExpiry = $null

#endregion

#region Connection Functions

function Connect-AAMDataverse {
    <#
    .SYNOPSIS
        Establishes connection to Dataverse for AAM operations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DataverseUrl,
        
        [Parameter()]
        [string]$AccessToken,

        [Parameter()]
        [string]$ClientId,

        [Parameter()]
        [string]$TenantId
    )
    
    $script:DataverseUrl = $DataverseUrl.TrimEnd('/')
    $script:ClientId = $ClientId
    $script:TenantId = $TenantId

    if ($AccessToken) {
        $script:AccessToken = $AccessToken
        # Assume caller-supplied tokens are valid for 55 minutes (conservative vs typical 60m expiry)
        $script:TokenExpiry = (Get-Date).AddMinutes(55)
    } else {
        # Attempt to get token from Graph context
        try {
            $context = Get-MgContext
            if ($context) {
                Write-Verbose "Using existing Graph context for Dataverse access"
                # Note: Graph token may not work for Dataverse - may need separate auth
            }
        } catch {
            Write-Warning "No access token provided and Graph context not available"
        }
    }
    
    Write-Verbose "Connected to Dataverse: $script:DataverseUrl"
}

function Get-ValidToken {
    <#
    .SYNOPSIS
        Returns a valid access token, refreshing via MSAL if expired or near expiry.
    #>
    [CmdletBinding()]
    param()

    $isExpiring = (-not $script:TokenExpiry) -or ((Get-Date) -ge $script:TokenExpiry.AddMinutes(-5))
    if ($isExpiring -and $script:TokenExpiry) {
        # In-module silent refresh was removed with the archived MSAL.PS dependency.
        # Tokens are acquired up front via Get-AAMAccessToken and stay valid for the
        # duration of a typical scan (2-5 minutes). If a token is near expiry, reconnect
        # with a freshly issued -AccessToken rather than relying on an in-module refresh.
        Write-Warning ("Access token has expired or is near expiry and AAMClient no longer " +
            "performs an in-module token refresh (the archived MSAL.PS dependency was removed). " +
            "Reconnect via Connect-AAMDataverse with a freshly issued -AccessToken (acquire one " +
            "with Get-AAMAccessToken). Subsequent Dataverse requests are likely to fail with HTTP 401.")
    }
    return $script:AccessToken
}

function Get-AAMConnection {
    <#
    .SYNOPSIS
        Returns current Dataverse connection info.
    #>
    [CmdletBinding()]
    param()
    
    [PSCustomObject]@{
        DataverseUrl = $script:DataverseUrl
        IsConnected  = $null -ne $script:DataverseUrl
    }
}

function Get-AAMAccessToken {
    <#
    .SYNOPSIS
        Acquires a Dataverse access token via direct OAuth 2.0 REST calls.

    .DESCRIPTION
        Modern-auth replacement for the archived MSAL.PS module (Microsoft archived
        MSAL.PS on 2024-04-15). Mirrors the Agent Sharing Access Restriction Detector
        (ASARD) auth pattern. Two flows are supported:
          -Interactive : device-code flow. The user copies a one-time code into
                         https://microsoft.com/devicelogin from any browser. Uses a
                         public-client app registration.
          default      : client-credentials flow with a service-principal secret.

        Certificate-thumbprint authentication is intentionally not supported here
        because it required the archived MSAL.PS module. Use -Interactive or
        -ClientSecret instead. Managed identity is the recommended production path.

    .PARAMETER TenantId
        Microsoft Entra ID tenant ID.

    .PARAMETER ClientId
        Application (client) ID. Required for both flows.

    .PARAMETER Resource
        Resource base URL the token is scoped to (for example the Dataverse org URL).
        The "/.default" scope suffix is appended automatically.

    .PARAMETER Interactive
        Use device-code flow instead of a service-principal secret.

    .PARAMETER ClientSecret
        Service-principal client secret (SecureString) for the client-credentials
        flow. Dev-only legacy fallback; production should use a managed identity.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$TenantId,

        [Parameter(Mandatory)]
        [string]$ClientId,

        [Parameter(Mandatory)]
        [string]$Resource,

        [Parameter()]
        [switch]$Interactive,

        [Parameter()]
        [securestring]$ClientSecret
    )

    $scope = "$($Resource.TrimEnd('/'))/.default"
    $tokenEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"

    if ($Interactive) {
        # Device-code flow: pure REST equivalent of MSAL.PS interactive auth.
        $deviceCodeEndpoint = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/devicecode"
        $deviceCodeResponse = Invoke-RestMethod -Uri $deviceCodeEndpoint -Method Post `
            -ContentType 'application/x-www-form-urlencoded' `
            -Body @{ client_id = $ClientId; scope = $scope } -ErrorAction Stop

        Write-Host ""
        Write-Host $deviceCodeResponse.message -ForegroundColor Yellow
        Write-Host ""

        $pollIntervalSeconds = [int]$deviceCodeResponse.interval
        if ($pollIntervalSeconds -lt 1) { $pollIntervalSeconds = 5 }
        $deadline = (Get-Date).AddSeconds([int]$deviceCodeResponse.expires_in)
        $pollBody = @{
            grant_type  = 'urn:ietf:params:oauth:grant-type:device_code'
            client_id   = $ClientId
            device_code = $deviceCodeResponse.device_code
        }

        $accessToken = $null
        while ((Get-Date) -lt $deadline) {
            Start-Sleep -Seconds $pollIntervalSeconds
            try {
                $tokenResponse = Invoke-RestMethod -Uri $tokenEndpoint -Method Post `
                    -ContentType 'application/x-www-form-urlencoded' -Body $pollBody -ErrorAction Stop
                $accessToken = $tokenResponse.access_token
                break
            } catch {
                $errorBody = $null
                if ($_.ErrorDetails -and $_.ErrorDetails.Message) {
                    try { $errorBody = $_.ErrorDetails.Message | ConvertFrom-Json } catch { $errorBody = $null }
                }
                $errorCode = if ($errorBody) { $errorBody.error } else { $_.Exception.Message }
                switch ($errorCode) {
                    'authorization_pending' { continue }
                    'slow_down'             { $pollIntervalSeconds += 5; continue }
                    default { throw "Device-code authentication failed: $errorCode" }
                }
            }
        }

        if (-not $accessToken) {
            throw "Device-code authentication timed out before the user completed sign-in."
        }
        return $accessToken
    }

    if (-not $ClientSecret) {
        throw "ClientSecret is required for service-principal authentication. Use -Interactive for device-code flow."
    }

    # legacy: dev-only — replace with managed identity in production.
    $plainSecret = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR(
        [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($ClientSecret)
    )
    try {
        $tokenResponse = Invoke-RestMethod -Uri $tokenEndpoint -Method Post `
            -ContentType 'application/x-www-form-urlencoded' `
            -Body @{
                grant_type    = 'client_credentials'
                client_id     = $ClientId
                client_secret = $plainSecret
                scope         = $scope
            } -ErrorAction Stop
        return $tokenResponse.access_token
    } finally {
        $plainSecret = $null
    }
}

#endregion

#region Retry Helper

function Invoke-DataverseRequest {
    <#
    .SYNOPSIS
        Wraps Invoke-RestMethod with retry/backoff for transient Dataverse errors.
    #>
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [string]$Method = 'GET',

        $Body,

        $Headers,

        [int]$MaxRetries = 3
    )

    for ($i = 0; $i -lt $MaxRetries; $i++) {
        try {
            $params = @{ Uri = $Uri; Method = $Method; Headers = $Headers }
            if ($Body) { $params['Body'] = $Body }
            return Invoke-RestMethod @params
        } catch {
            $statusCode = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { 0 }
            if ($statusCode -eq 429 -or $statusCode -ge 500) {
                # Honor Retry-After when present (Dataverse throttling guidance).
                $delay = [math]::Pow(2, $i)
                try {
                    $retryAfter = $_.Exception.Response.Headers['Retry-After']
                    if ($retryAfter) {
                        $parsed = 0
                        if ([int]::TryParse([string]$retryAfter, [ref]$parsed) -and $parsed -gt 0) { $delay = $parsed }
                    }
                } catch {
                    Write-Verbose ("Retry-After header lookup for {0} failed; using exponential backoff: {1}" -f $Uri, $_.Exception.Message)
                }
                Write-Verbose "Dataverse request failed (HTTP $statusCode), retrying in ${delay}s..."
                Start-Sleep -Seconds $delay
            } else {
                throw
            }
        }
    }
    throw "Max retries ($MaxRetries) exceeded for $Uri"
}

#endregion

#region Environment Variable Functions

function Get-AAMEnvironmentVariable {
    <#
    .SYNOPSIS
        Retrieves AAM environment variable value from Dataverse.
    
    .PARAMETER Name
        Variable name (without fsi_AAM_ prefix).
    
    .PARAMETER DefaultValue
        Value to return if variable not found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Name,
        
        [Parameter()]
        $DefaultValue = $null
    )
    
    if (-not $script:DataverseUrl) {
        Write-Verbose "Dataverse not connected, returning default value"
        return $DefaultValue
    }
    
    try {
        $schemaName = "fsi_AAM_$Name"
        $uri = "$script:DataverseUrl/api/data/v9.2/environmentvariabledefinitions?" + 
               "`$filter=schemaname eq '$schemaName'&" +
               "`$expand=environmentvariablevalues"
        
        $headers = @{
            'Authorization' = "Bearer $(Get-ValidToken)"
            'Accept' = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version' = '4.0'
        }
        
        $response = Invoke-DataverseRequest -Uri $uri -Headers $headers -Method Get
        
        if ($response.value.Count -gt 0) {
            $varDef = $response.value[0]
            if ($varDef.environmentvariablevalues.Count -gt 0) {
                return $varDef.environmentvariablevalues[0].value
            }
            return $varDef.defaultvalue
        }
        
        return $DefaultValue
    } catch {
        Write-Warning "Failed to get environment variable '$Name': $($_.Exception.Message)"
        return $DefaultValue
    }
}

#endregion

#region Baseline Functions

function Get-AAMActiveBaseline {
    <#
    .SYNOPSIS
        Retrieves the active access baseline from Dataverse.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$EnvironmentId
    )
    
    if (-not $script:DataverseUrl) {
        Write-Warning "Dataverse not connected"
        return $null
    }
    
    try {
        $filter = "fsi_isactive eq true"
        if ($EnvironmentId) {
            $filter += " and fsi_environmentguid eq '$($EnvironmentId -replace "'", "''")'"
        }
        
        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_accessbaselines?" +
               "`$filter=$filter&`$orderby=fsi_capturedat desc"
        
        $headers = @{
            'Authorization' = "Bearer $(Get-ValidToken)"
            'Accept' = 'application/json'
        }
        
        $response = Invoke-DataverseRequest -Uri $uri -Headers $headers -Method Get
        return $response.value
    } catch {
        Write-Warning "Failed to get active baseline: $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region Validation History Functions

function Write-AAMValidationHistory {
    <#
    .SYNOPSIS
        Writes a validation history record to Dataverse.

    .DESCRIPTION
        The fsi_accessvalidationhistory table is append-only by role design: the AAM
        application user is granted Create + Read only, with Write and Delete denied.
        Dataverse does not provide native column- or row-level immutability; the
        append-only behavior comes from the security role, not from a table flag.
        See docs/role-design-append-only.md.

    .PARAMETER ValidationResult
        Hashtable containing validation summary metrics.

    .PARAMETER RunId
        GUID correlating all records from a single scan execution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$ValidationResult,
        
        [Parameter(Mandatory)]
        [string]$RunId
    )
    
    if (-not $script:DataverseUrl) {
        Write-Warning "Dataverse not connected, skipping validation history write"
        return $null
    }
    
    try {
        $record = @{
            fsi_name              = "$($ValidationResult.OverallStatus)-$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')"
            fsi_runid             = $RunId
            fsi_validationtime    = (Get-Date).ToUniversalTime().ToString('o')
            fsi_totalenvironments = $ValidationResult.TotalEnvironments
            fsi_compliantcount    = $ValidationResult.CompliantCount
            fsi_violationcount    = $ValidationResult.ViolationCount
            fsi_overallstatus     = $ValidationResult.OverallStatus
            fsi_summaryjson       = ($ValidationResult | ConvertTo-Json -Depth 10 -Compress)
            fsi_severity          = switch ($ValidationResult.OverallStatus) {
                'Passed'  { 100000000 }
                'Warning' { 100000001 }
                'Failed'  { 100000003 }
                'Error'   { 100000004 }
                default   { 100000001 }
            }
        }
        # fsi_zone is intentionally omitted: aggregate validation records span
        # multiple zones. Per-zone detail is available in fsi_summaryjson.
        
        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_accessvalidationhistory"
        
        $headers = @{
            'Authorization' = "Bearer $(Get-ValidToken)"
            'Content-Type' = 'application/json'
            'Accept' = 'application/json'
        }
        
        $response = Invoke-DataverseRequest -Uri $uri -Method Post -Body ($record | ConvertTo-Json -Depth 10) -Headers $headers
        Write-Verbose "Validation history record created"
        return $response
    } catch {
        Write-Error "CRITICAL: Failed to write validation history (audit trail gap): $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Violation Functions

function Write-AAMViolation {
    <#
    .SYNOPSIS
        Writes violation record to Dataverse.
    
    .PARAMETER Violation
        Hashtable containing violation details.
    
    .PARAMETER RunId
        Optional GUID correlating this violation to a scan execution.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Violation,
        
        [Parameter()]
        [string]$RunId
    )
    
    if (-not $script:DataverseUrl) {
        Write-Warning "Dataverse not connected, skipping violation write"
        return $null
    }
    
    try {
        $zoneMap = @{
            "Zone1"   = 100000001
            "Zone2"   = 100000002
            "Zone3"   = 100000003
            "Unknown" = 100000000
        }
        $zoneValue = if ($zoneMap.ContainsKey($Violation.Zone)) { $zoneMap[$Violation.Zone] } else { 100000000 }

        # Map severity strings to fsi_acv_severity picklist integers
        # Note: Critical and High both map to 100000003 (Failed) per the shared fsi_acv_severity
        # option set. Use fsi_severitylabel column to distinguish Critical from High.
        $severityMap = @{
            "Critical" = 100000003  # Failed (use fsi_severitylabel to distinguish from High)
            "High"     = 100000003  # Failed (use fsi_severitylabel to distinguish from Critical)
            "Warning"  = 100000001  # Warning
            "Info"     = 100000000  # Passed
        }
        $severityValue = if ($severityMap.ContainsKey($Violation.Severity)) { $severityMap[$Violation.Severity] } else { 100000004 }

        $record = @{
            fsi_name              = "$($Violation.Zone)-$($Violation.ViolationType)-$(Get-Date -Format 'yyyy-MM-dd')"
            fsi_environmentguid   = $Violation.EnvironmentId
            fsi_environmentname   = $Violation.EnvironmentDisplayName
            fsi_zone              = $zoneValue
            fsi_violationtype     = $Violation.ViolationType
            fsi_expectedvalue     = [string]$Violation.Expected
            fsi_actualvalue       = [string]$Violation.Actual
            fsi_severity          = $severityValue
            fsi_severitylabel     = $Violation.Severity
            fsi_regulatorycontext = $Violation.RegulatoryContext
            fsi_detectedat        = (Get-Date).ToUniversalTime().ToString('o')
        }
        
        if ($RunId) {
            $record['fsi_runid'] = $RunId
        }
        
        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_accessviolations"
        
        $headers = @{
            'Authorization' = "Bearer $(Get-ValidToken)"
            'Content-Type' = 'application/json'
            'Accept' = 'application/json'
        }
        
        $response = Invoke-DataverseRequest -Uri $uri -Method Post -Body ($record | ConvertTo-Json -Depth 10) -Headers $headers
        Write-Verbose "Violation record created for $($Violation.EnvironmentDisplayName)"
        return $response
    } catch {
        Write-Error "CRITICAL: Failed to write violation record for '$($Violation.EnvironmentDisplayName)': $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Baseline Write Functions

function Save-AAMBaseline {
    <#
    .SYNOPSIS
        Saves an agent access baseline record to Dataverse.
    .DESCRIPTION
        Captures current environment access settings as a baseline. Deactivates any existing
        active baseline for the environment before writing the new one, maintaining a single
        active baseline per environment for drift detection.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$EnvironmentGuid,

        [Parameter(Mandatory)]
        [string]$EnvironmentName,

        [Parameter(Mandatory)]
        [int]$Zone,

        [Parameter(Mandatory)]
        [AllowEmptyString()]
        [string]$BotLimitSharingMode,

        [Parameter(Mandatory)]
        [bool]$BotAuthoringSharingDisabled,

        [Parameter()]
        [string]$BotMaxLimitUserSharing,

        [string]$CapturedBy,

        [string]$RawJson
    )

    if (-not $script:DataverseUrl) {
        Write-Warning "Dataverse not connected, skipping baseline save"
        return $null
    }

    try {
        # Map zone integer to Dataverse option set value
        $zoneMap = @{
            1 = 100000001
            2 = 100000002
            3 = 100000003
        }
        $zoneValue = if ($zoneMap.ContainsKey($Zone)) { $zoneMap[$Zone] } else { 100000000 }

        $headers = @{
            'Authorization'    = "Bearer $(Get-ValidToken)"
            'Content-Type'     = 'application/json'
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }

        # Deactivate existing active baselinefor this environment
        $filter = "fsi_isactive eq true and fsi_environmentguid eq '$($EnvironmentGuid -replace "'", "''")'"
        $queryUri = "$script:DataverseUrl/api/data/v9.2/fsi_accessbaselines?`$filter=$filter&`$select=fsi_accessbaselineid"

        $existing = Invoke-DataverseRequest -Uri $queryUri -Method Get -Headers $headers

        foreach ($baseline in $existing.value) {
            $baselineId = $baseline.fsi_accessbaselineid
            if ($PSCmdlet.ShouldProcess("Baseline $baselineId", "Deactivate previous active baseline")) {
                $patchUri = "$script:DataverseUrl/api/data/v9.2/fsi_accessbaselines($baselineId)"
                $patchBody = @{ fsi_isactive = $false } | ConvertTo-Json
                Invoke-DataverseRequest -Uri $patchUri -Method Patch -Body $patchBody -Headers $headers | Out-Null
                Write-Verbose "Deactivated previous baseline: $baselineId"
            }
        }

        # Create new active baseline
        $timestamp = (Get-Date).ToUniversalTime().ToString('o')
        $capturedByValue = if ($CapturedBy) { $CapturedBy } else { "System" }
        $rawJsonValue = if ($RawJson) { $RawJson } else { "" }

        $record = @{
            fsi_name                             = "$EnvironmentName-Zone$Zone-$timestamp"
            fsi_environmentguid                  = $EnvironmentGuid
            fsi_environmentname                  = $EnvironmentName
            fsi_zone                             = $zoneValue
            fsi_botlimitsharingmode              = $BotLimitSharingMode
            fsi_botauthoringsharingdisabled       = $BotAuthoringSharingDisabled
            fsi_botmaxlimitusersharing            = $BotMaxLimitUserSharing
            fsi_capturedby                       = $capturedByValue
            fsi_capturedat                       = $timestamp
            fsi_isactive                         = $true
            fsi_rawjson                          = $rawJsonValue
        }

        if ($PSCmdlet.ShouldProcess("$EnvironmentName (Zone $Zone)", "Save new access baseline")) {
            $uri = "$script:DataverseUrl/api/data/v9.2/fsi_accessbaselines"
            $response = Invoke-DataverseRequest -Uri $uri -Method Post -Body ($record | ConvertTo-Json -Depth 10) -Headers $headers
            Write-Verbose "Baseline saved for $EnvironmentName (Zone $Zone)"
            return $response
        }
    } catch {
        Write-Error "CRITICAL: Failed to save baseline for '$EnvironmentName': $($_.Exception.Message)"
        throw
    }
}

#endregion

#region Validation Query Functions

function Get-AAMLastValidation {
    <#
    .SYNOPSIS
        Retrieves recent validation history records from Dataverse.
    .DESCRIPTION
        Queries the fsi_accessvalidationhistory table ordered by timestamp descending.
        Used by drift detection to compare current scan results against previous runs.
    #>
    [CmdletBinding()]
    param(
        [int]$Top = 1
    )

    if (-not $script:DataverseUrl) {
        Write-Warning "Dataverse not connected"
        return $null
    }

    try {
        $select = "fsi_name,fsi_runid,fsi_overallstatus,fsi_violationcount,fsi_totalenvironments,fsi_summaryjson,fsi_validationtime"
        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_accessvalidationhistory?" +
               "`$orderby=fsi_validationtime desc&`$top=$Top&`$select=$select"

        $headers = @{
            'Authorization'    = "Bearer $(Get-ValidToken)"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }

        $response = Invoke-DataverseRequest -Uri $uri -Headers $headers -Method Get

        if ($response.value.Count -gt 0) {
            return $response.value | ForEach-Object {
                [PSCustomObject]@{
                    Name              = $_.fsi_name
                    RunId             = $_.fsi_runid
                    OverallStatus     = $_.fsi_overallstatus
                    ViolationCount    = $_.fsi_violationcount
                    TotalEnvironments = $_.fsi_totalenvironments
                    SummaryJson       = $_.fsi_summaryjson
                    Timestamp         = $_.fsi_validationtime
                }
            }
        }

        return $null
    } catch {
        Write-Warning "Failed to get validation history: $($_.Exception.Message)"
        return $null
    }
}

#endregion

# Export functions
Export-ModuleMember -Function @(
    'Connect-AAMDataverse',
    'Get-AAMConnection',
    'Get-AAMAccessToken',
    'Get-ValidToken',
    'Get-AAMEnvironmentVariable',
    'Get-AAMActiveBaseline',
    'Write-AAMValidationHistory',
    'Write-AAMViolation',
    'Save-AAMBaseline',
    'Get-AAMLastValidation'
)
