<#
.SYNOPSIS
    Agent Access Monitor Dataverse client module.

.DESCRIPTION
    Provides helper functions for Dataverse interaction with the AAM solution.
    Follows the proven SSCClient/ACVClient pattern with AAM_ environment variable prefix.

.NOTES
    Module: AAMClient.psm1
    Version: 1.0.0
    Author: FSI Agent Governance Team
#>

#region Module Variables

$script:DataverseUrl = $null
$script:AccessToken = $null
$script:ClientId = $null
$script:TenantId = $null
$script:TokenExpiry = $null

#endregion

#region Input Validation

function Assert-GuidFormat {
    <#
    .SYNOPSIS
        Validates that a string is a well-formed GUID to prevent OData injection.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Value,

        [Parameter(Mandatory)]
        [string]$ParameterName
    )

    if ($Value -notmatch '^[0-9a-fA-F]{8}-([0-9a-fA-F]{4}-){3}[0-9a-fA-F]{12}$') {
        throw "Invalid GUID format for parameter '$ParameterName': '$Value'"
    }
}

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

    if (-not $script:TokenExpiry -or (Get-Date) -ge $script:TokenExpiry.AddMinutes(-5)) {
        if ($script:ClientId -and $script:TenantId -and $script:DataverseUrl) {
            try {
                $token = Get-MsalToken -ClientId $script:ClientId -TenantId $script:TenantId -Scopes "$($script:DataverseUrl)/.default" -Silent
                $script:AccessToken = $token.AccessToken
                $script:TokenExpiry = $token.ExpiresOn.LocalDateTime
            } catch {
                Write-Warning "Token refresh failed: $($_.Exception.Message). Using existing token."
            }
        }
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
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($statusCode -eq 429 -or $statusCode -ge 500) {
                $delay = [math]::Pow(2, $i)
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
        $filter = "fsi_is_active eq true"
        if ($EnvironmentId) {
            Assert-GuidFormat -Value $EnvironmentId -ParameterName 'EnvironmentId'
            $filter += " and fsi_environment_guid eq '$EnvironmentId'"
        }
        
        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_accessbaselines?" +
               "`$filter=$filter&`$orderby=fsi_captured_at desc"
        
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
        Writes immutable validation record to Dataverse.
    
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
    
    Assert-GuidFormat -Value $RunId -ParameterName 'RunId'

    if (-not $script:DataverseUrl) {
        Write-Warning "Dataverse not connected, skipping validation history write"
        return $null
    }
    
    try {
        $record = @{
            fsi_name              = "$($ValidationResult.OverallStatus)-$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')"
            fsi_run_id            = $RunId
            fsi_validation_time   = (Get-Date).ToUniversalTime().ToString('o')
            fsi_total_environments = $ValidationResult.TotalEnvironments
            fsi_compliant_count   = $ValidationResult.CompliantCount
            fsi_violation_count   = $ValidationResult.ViolationCount
            fsi_overall_status    = $ValidationResult.OverallStatus
            fsi_summary_json      = ($ValidationResult | ConvertTo-Json -Depth 10 -Compress)
        }
        
        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_accessvalidationhistory"
        
        $headers = @{
            'Authorization' = "Bearer $(Get-ValidToken)"
            'Content-Type' = 'application/json'
            'Accept' = 'application/json'
        }
        
        $response = Invoke-DataverseRequest -Uri $uri -Method Post -Body ($record | ConvertTo-Json) -Headers $headers
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
            "Zone1" = 1
            "Zone2" = 2
            "Zone3" = 3
        }
        $zoneValue = if ($zoneMap.ContainsKey($Violation.Zone)) { $zoneMap[$Violation.Zone] } else { $Violation.Zone }

        $severityMap = @{
            'Critical' = 1
            'High'     = 2
            'Warning'  = 3
            'Info'     = 4
        }
        $severityValue = if ($severityMap.ContainsKey($Violation.Severity)) { $severityMap[$Violation.Severity] } else { $Violation.Severity }

        $record = @{
            fsi_name              = "$($Violation.Zone)-$($Violation.ViolationType)-$(Get-Date -Format 'yyyy-MM-dd')"
            fsi_environment_guid  = $Violation.EnvironmentId
            fsi_environment_name  = $Violation.EnvironmentDisplayName
            fsi_zone              = $zoneValue
            fsi_violation_type    = $Violation.ViolationType
            fsi_expected_value    = $Violation.Expected
            fsi_actual_value      = $Violation.Actual
            fsi_severity          = $severityValue
            fsi_regulatory_context = $Violation.RegulatoryContext
            fsi_detected_at       = (Get-Date).ToUniversalTime().ToString('o')
        }
        
        if ($RunId) {
            $record['fsi_run_id'] = $RunId
        }
        
        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_accessviolations"
        
        $headers = @{
            'Authorization' = "Bearer $(Get-ValidToken)"
            'Content-Type' = 'application/json'
            'Accept' = 'application/json'
        }
        
        $response = Invoke-DataverseRequest -Uri $uri -Method Post -Body ($record | ConvertTo-Json) -Headers $headers
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
        [string]$BotLimitSharingMode,

        [Parameter(Mandatory)]
        [bool]$BotAuthoringSharingDisabled,

        [Parameter(Mandatory)]
        [string]$BotPublishedBotLimitSharingMode,

        [string]$CapturedBy,

        [string]$RawJson
    )

    if (-not $script:DataverseUrl) {
        Write-Warning "Dataverse not connected, skipping baseline save"
        return $null
    }

    try {
        $headers = @{
            'Authorization'    = "Bearer $(Get-ValidToken)"
            'Content-Type'     = 'application/json'
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }

        # Deactivate existing active baselinefor this environment
        Assert-GuidFormat -Value $EnvironmentGuid -ParameterName 'EnvironmentGuid'
        $filter = "fsi_is_active eq true and fsi_environment_guid eq '$EnvironmentGuid'"
        $queryUri = "$script:DataverseUrl/api/data/v9.2/fsi_accessbaselines?`$filter=$filter&`$select=fsi_accessbaselineid"

        $existing = Invoke-DataverseRequest -Uri $queryUri -Method Get -Headers $headers

        foreach ($baseline in $existing.value) {
            $baselineId = $baseline.fsi_accessbaselineid
            if ($PSCmdlet.ShouldProcess("Baseline $baselineId", "Deactivate previous active baseline")) {
                $patchUri = "$script:DataverseUrl/api/data/v9.2/fsi_accessbaselines($baselineId)"
                $patchBody = @{ fsi_is_active = $false } | ConvertTo-Json
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
            fsi_environment_guid                 = $EnvironmentGuid
            fsi_environment_name                 = $EnvironmentName
            fsi_zone                             = $Zone
            fsi_bot_limit_sharing_mode           = $BotLimitSharingMode
            fsi_bot_authoring_sharing_disabled   = $BotAuthoringSharingDisabled
            fsi_bot_published_limit_sharing_mode = $BotPublishedBotLimitSharingMode
            fsi_captured_by                      = $capturedByValue
            fsi_captured_at                      = $timestamp
            fsi_is_active                        = $true
            fsi_raw_json                         = $rawJsonValue
        }

        if ($PSCmdlet.ShouldProcess("$EnvironmentName (Zone $Zone)", "Save new access baseline")) {
            $uri = "$script:DataverseUrl/api/data/v9.2/fsi_accessbaselines"
            $response = Invoke-DataverseRequest -Uri $uri -Method Post -Body ($record | ConvertTo-Json) -Headers $headers
            Write-Verbose "Baseline saved for $EnvironmentName (Zone $Zone)"
            return $response
        }
    } catch {
        # Recovery: re-activate previously deactivated baselines to avoid leaving environment with no active baseline
        if ($existing.value) {
            Write-Warning "Baseline creation failed — attempting to re-activate previous baseline(s) for '$EnvironmentName'"
            foreach ($baseline in $existing.value) {
                try {
                    $baselineId = $baseline.fsi_accessbaselineid
                    $patchUri = "$script:DataverseUrl/api/data/v9.2/fsi_accessbaselines($baselineId)"
                    $patchBody = @{ fsi_is_active = $true } | ConvertTo-Json
                    Invoke-DataverseRequest -Uri $patchUri -Method Patch -Body $patchBody -Headers $headers | Out-Null
                    Write-Warning "Re-activated previous baseline: $baselineId"
                } catch {
                    Write-Error "CRITICAL: Failed to re-activate baseline $baselineId during recovery: $($_.Exception.Message)"
                }
            }
        }
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
        $select = "fsi_name,fsi_run_id,fsi_overall_status,fsi_violation_count,fsi_total_environments,fsi_summary_json,fsi_validation_time"
        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_accessvalidationhistory?" +
               "`$orderby=fsi_validation_time desc&`$top=$Top&`$select=$select"

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
                    RunId             = $_.fsi_run_id
                    OverallStatus     = $_.fsi_overall_status
                    ViolationCount    = $_.fsi_violation_count
                    TotalEnvironments = $_.fsi_total_environments
                    SummaryJson       = $_.fsi_summary_json
                    Timestamp         = $_.fsi_validation_time
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
    'Assert-GuidFormat',
    'Connect-AAMDataverse',
    'Get-AAMConnection',
    'Get-ValidToken',
    'Invoke-DataverseRequest',
    'Get-AAMEnvironmentVariable',
    'Get-AAMActiveBaseline',
    'Write-AAMValidationHistory',
    'Write-AAMViolation',
    'Save-AAMBaseline',
    'Get-AAMLastValidation'
)
