<#
.SYNOPSIS
    Conditional Access Automation Dataverse client module.

.DESCRIPTION
    Provides helper functions for Dataverse interaction with the CAA solution.
    Follows the proven AAMClient pattern with CAA-specific table and field names.

    Requires MSAL.PS module for interactive OAuth2 token acquisition.
    All HTTP calls include retry logic with exponential backoff for 429/5xx
    responses and automatic pagination via @odata.nextLink.

.NOTES
    Module: CAAClient.psm1
    Version: 1.0.0
    Author: FSI Agent Governance Team
#>

#region Module Variables

$script:CAADataverseUrl = $null
$script:CAAAccessToken = $null
$script:CAAHeaders = $null
$script:CAATokenExpiry = [datetime]::MinValue
$script:CAAMsalClientId = '51f81489-12ee-4a9e-aaae-a2591f45987d'
$script:CAAMsalTenantId = $null

#endregion

#region Private Helper Functions

function Invoke-CAARestMethod {
    <#
    .SYNOPSIS
        Wraps Invoke-RestMethod with retry logic for transient failures.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri,
        [Parameter(Mandatory)][ValidateSet('Get','Post','Patch','Delete')][string]$Method,
        [Parameter()][string]$Body,
        [Parameter()][switch]$ReturnRepresentation,
        [Parameter()][int]$MaxRetries = 3
    )

    $attempt = 0
    while ($true) {
        $attempt++
        try {
            $requestHeaders = @{}
            foreach ($key in $script:CAAHeaders.Keys) { $requestHeaders[$key] = $script:CAAHeaders[$key] }

            if ($ReturnRepresentation) {
                $requestHeaders['Prefer'] = "return=representation,$($requestHeaders['Prefer'])"
            }

            $params = @{
                Uri     = $Uri
                Method  = $Method
                Headers = $requestHeaders
            }
            if ($Body) {
                $params['Body']        = $Body
                $params['ContentType'] = 'application/json; charset=utf-8'
            }

            return (Invoke-RestMethod @params)
        }
        catch {
            $statusCode = $null
            if ($_.Exception.Response) {
                $statusCode = [int]$_.Exception.Response.StatusCode
            }

            # Return $null on 404
            if ($statusCode -eq 404) {
                Write-Verbose "Resource not found (404): $Uri"
                return $null
            }

            # Non-retryable client errors (400-428)
            if ($statusCode -and $statusCode -ge 400 -and $statusCode -lt 429) {
                throw
            }

            if ($attempt -ge $MaxRetries) {
                throw
            }

            # Exponential backoff for 429 / 5xx
            $delay = [math]::Pow(2, $attempt)
            if ($statusCode -eq 429 -and $_.Exception.Response.Headers) {
                try {
                    $retryAfter = $_.Exception.Response.Headers.GetValues('Retry-After') | Select-Object -First 1
                    if ($retryAfter) { $delay = [math]::Max($delay, [int]$retryAfter) }
                } catch { }
            }
            Write-Verbose "Attempt $attempt/$MaxRetries failed (HTTP $statusCode). Retrying in ${delay}s..."
            Start-Sleep -Seconds $delay
        }
    }
}

function Get-CAAAllPages {
    <#
    .SYNOPSIS
        Follows @odata.nextLink pagination and returns all records.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)][string]$Uri
    )

    $allRecords = [System.Collections.ArrayList]::new()
    $currentUrl = $Uri
    $pageCount  = 0

    while ($currentUrl) {
        $pageCount++
        Write-Verbose "  Fetching page $pageCount..."
        $response = Invoke-CAARestMethod -Uri $currentUrl -Method Get
        if ($null -eq $response) { break }

        if ($response.value) {
            foreach ($record in $response.value) {
                [void]$allRecords.Add($record)
            }
        }
        $currentUrl = $response.'@odata.nextLink'
    }

    Write-Verbose "  Retrieved $($allRecords.Count) records across $pageCount page(s)."
    return ,$allRecords
}

function Assert-CAAConnection {
    <#
    .SYNOPSIS
        Verifies an active Dataverse connection exists and refreshes token if needed.
    #>
    [CmdletBinding()]
    param()

    if ($null -eq $script:CAAAccessToken) {
        throw "Not connected to Dataverse. Call Connect-CAADataverse first."
    }

    # Refresh token if expired or within 5 minutes of expiry
    if ($script:CAATokenExpiry -lt (Get-Date).ToUniversalTime().AddMinutes(5)) {
        Write-Verbose "Token expired or expiring soon — refreshing..."
        $scope = "$($script:CAADataverseUrl)/.default"
        try {
            $tokenResult = Get-MsalToken -ClientId $script:CAAMsalClientId `
                -TenantId $script:CAAMsalTenantId `
                -Scopes @($scope) `
                -Silent
        }
        catch {
            Write-Verbose "Silent token refresh failed — attempting interactive login."
            $tokenResult = Get-MsalToken -ClientId $script:CAAMsalClientId `
                -TenantId $script:CAAMsalTenantId `
                -Scopes @($scope) `
                -Interactive
        }
        $script:CAAAccessToken = $tokenResult.AccessToken
        $script:CAATokenExpiry = $tokenResult.ExpiresOn.UtcDateTime
        $script:CAAHeaders = @{
            'Authorization' = "Bearer $($script:CAAAccessToken)"
            'Accept'        = 'application/json'
            'OData-Version' = '4.0'
            'Prefer'        = 'odata.include-annotations="*"'
        }
        Write-Verbose "Token refreshed. New expiry: $($script:CAATokenExpiry)"
    }
}

function ConvertTo-CAAZoneValue {
    <#
    .SYNOPSIS
        Maps a zone label or number to its Dataverse option set integer value.
    #>
    param([object]$Zone)
    if ($Zone -is [int]) { return $Zone }
    switch -Wildcard ("$Zone") {
        '*3*' { return 3 }
        '*2*' { return 2 }
        '*1*' { return 1 }
        default { return 0 }
    }
}

function ConvertTo-CAASeverityValue {
    <#
    .SYNOPSIS
        Maps a severity label or number to its Dataverse option set integer value.
    #>
    param([object]$Severity)
    if ($Severity -is [int]) { return $Severity }
    switch ("$Severity") {
        'Passed'      { return 1 }
        'Warning'     { return 2 }
        'GracePeriod' { return 3 }
        'Failed'      { return 4 }
        'Critical'    { return 4 }
        'Error'       { return 5 }
        default       { return 4 }
    }
}

#endregion

#region Connection Functions

function Connect-CAADataverse {
    <#
    .SYNOPSIS
        Establishes connection to Dataverse for CAA operations.

    .DESCRIPTION
        Acquires an OAuth2 token via MSAL.PS targeting the Dataverse resource,
        stores module-scoped connection state, and verifies connectivity with
        a test query to the organizations table.

    .PARAMETER DataverseUrl
        The Dataverse environment URL (e.g., https://org.crm.dynamics.com).

    .PARAMETER TenantId
        The Azure AD tenant GUID for authentication.

    .EXAMPLE
        Connect-CAADataverse -DataverseUrl 'https://org.crm.dynamics.com' -TenantId '00000000-...'

    .OUTPUTS
        None. Sets module-scoped connection state.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$DataverseUrl,

        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$TenantId
    )

    $baseUrl = $DataverseUrl.TrimEnd('/')
    $scope   = "$baseUrl/.default"
    Write-Verbose "Acquiring MSAL token for scope: $scope (Tenant: $TenantId)"

    try {
        $tokenResult = Get-MsalToken -ClientId $script:CAAMsalClientId `
            -TenantId $TenantId `
            -Scopes @($scope) `
            -Interactive
    }
    catch {
        throw "MSAL token acquisition failed for Dataverse '$DataverseUrl': $_"
    }

    $script:CAADataverseUrl  = $baseUrl
    $script:CAAAccessToken   = $tokenResult.AccessToken
    $script:CAATokenExpiry   = $tokenResult.ExpiresOn.UtcDateTime
    $script:CAAMsalTenantId  = $TenantId
    $script:CAAHeaders = @{
        'Authorization' = "Bearer $($script:CAAAccessToken)"
        'Accept'        = 'application/json'
        'OData-Version' = '4.0'
        'Prefer'        = 'odata.include-annotations="*"'
    }

    # Verify connection with a lightweight test query
    Write-Verbose "Verifying Dataverse connection..."
    $testUrl    = "$($script:CAADataverseUrl)/api/data/v9.2/organizations?`$select=name&`$top=1"
    $testResult = Invoke-CAARestMethod -Uri $testUrl -Method Get
    if ($null -eq $testResult -or $null -eq $testResult.value -or $testResult.value.Count -eq 0) {
        throw "Dataverse connection verification failed — no organization record returned from '$DataverseUrl'."
    }
    Write-Verbose "Connected to Dataverse organization: $($testResult.value[0].name)"
}

function Get-CAAConnection {
    <#
    .SYNOPSIS
        Returns current Dataverse connection info.

    .DESCRIPTION
        Returns the module-scoped connection state including URL, connection
        status, and token expiry time.

    .EXAMPLE
        Get-CAAConnection

    .OUTPUTS
        PSCustomObject with Connected, DataverseUrl, and TokenExpiry properties.
    #>
    [CmdletBinding()]
    param()

    $isConnected = ($null -ne $script:CAAAccessToken) -and
                   ($script:CAATokenExpiry -gt (Get-Date).ToUniversalTime())

    [PSCustomObject]@{
        Connected    = $isConnected
        DataverseUrl = $script:CAADataverseUrl
        TokenExpiry  = if ($script:CAATokenExpiry -ne [datetime]::MinValue) { $script:CAATokenExpiry } else { $null }
    }
}

#endregion

#region Environment Variable Functions

function Get-CAAEnvironmentVariable {
    <#
    .SYNOPSIS
        Retrieves a CAA environment variable value from Dataverse.

    .DESCRIPTION
        Queries the Dataverse environmentvariabledefinitions table for a
        CAA-prefixed variable and returns its current value override or
        the default value if no override exists.

    .PARAMETER VariableName
        The full schema name of the variable (e.g., 'fsi_CAA_GracePeriodHours').

    .EXAMPLE
        Get-CAAEnvironmentVariable -VariableName 'fsi_CAA_GracePeriodHours'

    .OUTPUTS
        The environment variable value, or $null if not found.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNullOrEmpty()]
        [string]$VariableName
    )

    Assert-CAAConnection

    $escapedName = $VariableName.Replace("'", "''")
    $defUrl = "$($script:CAADataverseUrl)/api/data/v9.2/environmentvariabledefinitions?" +
        "`$filter=schemaname eq '$escapedName'&`$select=environmentvariabledefinitionid,schemaname,defaultvalue"

    Write-Verbose "Querying environment variable definition: $VariableName"
    $defResponse = Invoke-CAARestMethod -Uri $defUrl -Method Get

    if ($null -eq $defResponse -or $null -eq $defResponse.value -or $defResponse.value.Count -eq 0) {
        Write-Verbose "Environment variable '$VariableName' not found."
        return $null
    }

    $defId        = $defResponse.value[0].environmentvariabledefinitionid
    $defaultValue = $defResponse.value[0].defaultvalue

    # Query for a current value override
    $valUrl = "$($script:CAADataverseUrl)/api/data/v9.2/environmentvariablevalues?" +
        "`$filter=_environmentvariabledefinitionid_value eq '$defId'&`$select=value"

    Write-Verbose "Querying environment variable value for definition: $defId"
    $valResponse = Invoke-CAARestMethod -Uri $valUrl -Method Get

    if ($null -ne $valResponse -and $null -ne $valResponse.value -and $valResponse.value.Count -gt 0) {
        Write-Verbose "Returning current value for '$VariableName'."
        return $valResponse.value[0].value
    }

    Write-Verbose "No value override found for '$VariableName' — returning default."
    return $defaultValue
}

#endregion

#region Baseline Functions

function Get-CAAActiveBaseline {
    <#
    .SYNOPSIS
        Retrieves the active CA policy baseline from Dataverse.

    .DESCRIPTION
        Queries the fsi_capolicybaselines table for currently active baseline
        records. Optionally filters by tenant ID (environment scope). Handles
        pagination via @odata.nextLink for large result sets.

    .PARAMETER EnvironmentId
        Optional tenant GUID to filter baselines by environment scope.

    .EXAMPLE
        Get-CAAActiveBaseline

        Retrieves all active baselines.

    .EXAMPLE
        Get-CAAActiveBaseline -EnvironmentId '00000000-0000-0000-0000-000000000001'

        Retrieves the active baseline for a specific environment.

    .OUTPUTS
        Array of baseline records, or $null if none found.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$EnvironmentId
    )

    Assert-CAAConnection

    $filter = "fsi_is_active eq true"
    if ($EnvironmentId) {
        $escapedId = $EnvironmentId.Replace("'", "''")
        $filter += " and fsi_tenant_id eq '$escapedId'"
    }

    $url = "$($script:CAADataverseUrl)/api/data/v9.2/fsi_capolicybaselines?" +
        "`$filter=$filter&`$orderby=fsi_captured_at desc"

    Write-Verbose "Querying active baselines: $url"
    $results = Get-CAAAllPages -Uri $url

    if ($results.Count -eq 0) {
        Write-Verbose "No active baselines found."
        return $null
    }

    return ,$results
}

#endregion

#region Validation History Functions

function Write-CAAValidationHistory {
    <#
    .SYNOPSIS
        Writes an immutable validation record to Dataverse.

    .DESCRIPTION
        Creates an immutable record in the fsi_capolicyvalidationhistories table
        capturing validation run results including compliance status, violation
        counts, and summary metrics. Records are append-only for audit trail.

    .PARAMETER Record
        Hashtable containing validation summary metrics. Expected keys include:
        RunId, TotalPolicies, PassedCount (or CompliantCount), FailedCount
        (or ViolationCount), WarningCount, DriftCount, OverallSeverity
        (or OverallStatus), ResultsJson, ValidatedBy, TenantId.

    .EXAMPLE
        Write-CAAValidationHistory -Record @{
            RunId            = (New-Guid).ToString()
            TotalPolicies    = 12
            PassedCount      = 10
            FailedCount      = 2
            WarningCount     = 0
            DriftCount       = 1
            OverallSeverity  = 'Failed'
            ValidatedBy      = 'admin@contoso.com'
            TenantId         = '00000000-...'
        }

    .OUTPUTS
        The created Dataverse record ID, or $null on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Record
    )

    Assert-CAAConnection

    $body = @{
        fsi_run_id           = $Record['RunId']
        fsi_validation_time  = if ($Record['ValidationTime']) { $Record['ValidationTime'] } else { (Get-Date).ToUniversalTime().ToString('o') }
        fsi_total_policies   = [int]($Record['TotalPolicies'])
        fsi_passed_count     = [int](if ($Record.ContainsKey('PassedCount')) { $Record['PassedCount'] } else { $Record['CompliantCount'] })
        fsi_warning_count    = [int]($Record['WarningCount'])
        fsi_failed_count     = [int](if ($Record.ContainsKey('FailedCount')) { $Record['FailedCount'] } else { $Record['ViolationCount'] })
        fsi_drift_count      = [int]($Record['DriftCount'])
        fsi_overall_severity = ConvertTo-CAASeverityValue -Severity ($Record['OverallSeverity'] ?? $Record['OverallStatus'] ?? 'Passed')
        fsi_results_json     = if ($Record['ResultsJson']) { $Record['ResultsJson'] } else { '[]' }
        fsi_validated_by     = $Record['ValidatedBy']
        fsi_tenant_id        = $Record['TenantId']
    }

    # Strip null entries — Dataverse rejects explicit nulls for required columns
    $cleanBody = @{}
    foreach ($key in $body.Keys) {
        if ($null -ne $body[$key]) { $cleanBody[$key] = $body[$key] }
    }

    $url      = "$($script:CAADataverseUrl)/api/data/v9.2/fsi_capolicyvalidationhistories"
    $jsonBody = $cleanBody | ConvertTo-Json -Depth 10 -Compress

    Write-Verbose "Writing validation history record (RunId: $($Record['RunId']))"
    $response = Invoke-CAARestMethod -Uri $url -Method Post -Body $jsonBody -ReturnRepresentation

    if ($null -ne $response) {
        $recordId = $response.fsi_capolicyvalidationhistoryid
        Write-Verbose "Created validation history record: $recordId"
        return $recordId
    }
    return $null
}

#endregion

#region Violation Functions

function Write-CAAViolation {
    <#
    .SYNOPSIS
        Writes a policy violation record to Dataverse.

    .DESCRIPTION
        Creates a record in the fsi_capolicyviolations table capturing details
        of a specific Conditional Access policy violation including expected vs.
        actual state, severity, and regulatory context.

    .PARAMETER Violation
        Hashtable containing violation details. Expected keys include:
        PolicyId, PolicyName, RunId, Zone, ViolationType, Expected, Actual,
        Severity, Description, RegulatoryContext, TenantId.

    .EXAMPLE
        Write-CAAViolation -Violation @{
            PolicyId          = '00000000-...'
            PolicyName        = 'FSI-Zone3-RequireMFA'
            RunId             = '...'
            Zone              = 'Zone3'
            ViolationType     = 'MissingMFAGrant'
            Expected          = 'MFA required'
            Actual            = 'No MFA grant control'
            Severity          = 'Failed'
            RegulatoryContext = 'FINRA 4511, SOX 404'
            TenantId          = '00000000-...'
        }

    .OUTPUTS
        The created Dataverse record ID, or $null on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Violation
    )

    Assert-CAAConnection

    # Build description — append regulatory context if supplied
    $description = $Violation['Description']
    if ($Violation['RegulatoryContext']) {
        $description = if ($description) { "$description | Regulatory: $($Violation['RegulatoryContext'])" }
                       else { "Regulatory: $($Violation['RegulatoryContext'])" }
    }

    $body = @{
        fsi_policy_display_name = $Violation['PolicyName']
        fsi_policy_id           = $Violation['PolicyId']
        fsi_run_id              = $Violation['RunId']
        fsi_violation_type      = $Violation['ViolationType']
        fsi_zone                = ConvertTo-CAAZoneValue -Zone ($Violation['Zone'] ?? 0)
        fsi_severity            = ConvertTo-CAASeverityValue -Severity ($Violation['Severity'] ?? 'Failed')
        fsi_expected_value      = $Violation['Expected']
        fsi_actual_value        = $Violation['Actual']
        fsi_description         = $description
        fsi_is_resolved         = $false
        fsi_detected_at         = if ($Violation['DetectedAt']) { $Violation['DetectedAt'] } else { (Get-Date).ToUniversalTime().ToString('o') }
        fsi_tenant_id           = $Violation['TenantId']
    }

    # Strip null entries
    $cleanBody = @{}
    foreach ($key in $body.Keys) {
        if ($null -ne $body[$key]) { $cleanBody[$key] = $body[$key] }
    }

    $url      = "$($script:CAADataverseUrl)/api/data/v9.2/fsi_capolicyviolations"
    $jsonBody = $cleanBody | ConvertTo-Json -Depth 10 -Compress

    Write-Verbose "Writing violation record (Policy: $($Violation['PolicyName']), Type: $($Violation['ViolationType']))"
    $response = Invoke-CAARestMethod -Uri $url -Method Post -Body $jsonBody -ReturnRepresentation

    if ($null -ne $response) {
        $recordId = $response.fsi_capolicyviolationid
        Write-Verbose "Created violation record: $recordId"
        return $recordId
    }
    return $null
}

#endregion

#region Baseline Write Functions

function Save-CAABaseline {
    <#
    .SYNOPSIS
        Saves a Conditional Access policy baseline record to Dataverse.

    .DESCRIPTION
        Captures current CA policy configuration as a baseline snapshot. Deactivates
        any existing active baseline for the same policy_id before creating the new
        one, ensuring a single active baseline per policy for drift detection.

    .PARAMETER Baseline
        Hashtable containing the baseline snapshot. Expected keys include:
        TenantId, PolicyId, PolicyName, PolicyState, Zone, ConditionsJson,
        GrantControlsJson, SessionControlsJson, BreakGlassExclusions,
        BaselineHash, CapturedBy, CapturedAt.

    .EXAMPLE
        Save-CAABaseline -Baseline @{
            TenantId           = '00000000-...'
            PolicyId           = '11111111-...'
            PolicyName         = 'FSI-Zone3-RequireMFA'
            PolicyState        = 'enabled'
            Zone               = 'Zone3'
            ConditionsJson     = '{"users":...}'
            GrantControlsJson  = '{"builtInControls":["mfa"]}'
            BaselineHash       = 'abc123...'
            CapturedBy         = 'admin@contoso.com'
            CapturedAt         = (Get-Date).ToUniversalTime().ToString('o')
        }

    .OUTPUTS
        The created Dataverse record ID, or $null on failure.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ValidateNotNull()]
        [hashtable]$Baseline
    )

    Assert-CAAConnection

    $policyId = $Baseline['PolicyId']

    # Step 1: Deactivate existing active baselines for this policy
    if ($policyId) {
        $escapedId = $policyId.Replace("'", "''")
        $activeUrl = "$($script:CAADataverseUrl)/api/data/v9.2/fsi_capolicybaselines?" +
            "`$filter=fsi_is_active eq true and fsi_policy_id eq '$escapedId'" +
            "&`$select=fsi_capolicybaselineid"

        Write-Verbose "Checking for existing active baselines (PolicyId: $policyId)..."
        $activeBaselines = Invoke-CAARestMethod -Uri $activeUrl -Method Get

        if ($activeBaselines -and $activeBaselines.value) {
            foreach ($existing in $activeBaselines.value) {
                $patchUrl  = "$($script:CAADataverseUrl)/api/data/v9.2/fsi_capolicybaselines($($existing.fsi_capolicybaselineid))"
                $patchBody = @{ fsi_is_active = $false } | ConvertTo-Json -Compress
                Write-Verbose "Deactivating baseline: $($existing.fsi_capolicybaselineid)"
                Invoke-CAARestMethod -Uri $patchUrl -Method Patch -Body $patchBody | Out-Null
            }
            Write-Verbose "Deactivated $($activeBaselines.value.Count) existing baseline(s)."
        }
    }

    # Step 2: Create new active baseline
    $body = @{
        fsi_policy_display_name  = $Baseline['PolicyName']
        fsi_policy_id            = $policyId
        fsi_policy_state         = $Baseline['PolicyState']
        fsi_zone                 = ConvertTo-CAAZoneValue -Zone ($Baseline['Zone'] ?? 0)
        fsi_conditions_json      = $Baseline['ConditionsJson']
        fsi_grant_controls_json  = $Baseline['GrantControlsJson']
        fsi_session_controls_json = $Baseline['SessionControlsJson']
        fsi_break_glass_exclusions = $Baseline['BreakGlassExclusions']
        fsi_baseline_hash        = $Baseline['BaselineHash']
        fsi_is_active            = $true
        fsi_captured_at          = if ($Baseline['CapturedAt']) { $Baseline['CapturedAt'] } else { (Get-Date).ToUniversalTime().ToString('o') }
        fsi_captured_by          = $Baseline['CapturedBy']
        fsi_tenant_id            = $Baseline['TenantId']
    }

    # Strip null entries
    $cleanBody = @{}
    foreach ($key in $body.Keys) {
        if ($null -ne $body[$key]) { $cleanBody[$key] = $body[$key] }
    }

    $url      = "$($script:CAADataverseUrl)/api/data/v9.2/fsi_capolicybaselines"
    $jsonBody = $cleanBody | ConvertTo-Json -Depth 10 -Compress

    Write-Verbose "Creating new active baseline (Policy: $($Baseline['PolicyName']))"
    $response = Invoke-CAARestMethod -Uri $url -Method Post -Body $jsonBody -ReturnRepresentation

    if ($null -ne $response) {
        $recordId = $response.fsi_capolicybaselineid
        Write-Verbose "Created baseline record: $recordId"
        return $recordId
    }
    return $null
}

#endregion

#region Validation Query Functions

function Get-CAALastValidation {
    <#
    .SYNOPSIS
        Retrieves recent validation history records from Dataverse.

    .DESCRIPTION
        Queries the fsi_capolicyvalidationhistories table ordered by
        fsi_validation_time descending. Used by drift detection to compare
        current scan results against previous runs.

    .PARAMETER EnvironmentId
        Optional tenant GUID to filter validation history by environment.

    .PARAMETER Count
        Number of recent records to retrieve. Defaults to 1.

    .EXAMPLE
        Get-CAALastValidation

        Retrieves the most recent validation record.

    .EXAMPLE
        Get-CAALastValidation -Count 5

        Retrieves the 5 most recent validation records.

    .EXAMPLE
        Get-CAALastValidation -EnvironmentId '00000000-...' -Count 3

        Retrieves the 3 most recent records for a specific environment.

    .OUTPUTS
        Array of validation history records, or $null if none found.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$EnvironmentId,

        [Parameter()]
        [int]$Count = 1
    )

    Assert-CAAConnection

    $filter = ''
    if ($EnvironmentId) {
        $escapedId = $EnvironmentId.Replace("'", "''")
        $filter = "`$filter=fsi_tenant_id eq '$escapedId'&"
    }

    $url = "$($script:CAADataverseUrl)/api/data/v9.2/fsi_capolicyvalidationhistories?" +
        "${filter}`$orderby=fsi_validation_time desc&`$top=$Count"

    Write-Verbose "Querying last $Count validation record(s): $url"
    $response = Invoke-CAARestMethod -Uri $url -Method Get

    if ($null -eq $response -or $null -eq $response.value -or $response.value.Count -eq 0) {
        Write-Verbose "No validation history records found."
        return $null
    }

    return ,@($response.value)
}

#endregion

# Export all public functions
Export-ModuleMember -Function @(
    'Connect-CAADataverse',
    'Get-CAAConnection',
    'Get-CAAEnvironmentVariable',
    'Get-CAAActiveBaseline',
    'Write-CAAValidationHistory',
    'Write-CAAViolation',
    'Save-CAABaseline',
    'Get-CAALastValidation'
)
