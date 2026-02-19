<#
.SYNOPSIS
    File Upload Security Dataverse client module.

.DESCRIPTION
    Provides helper functions for Dataverse interaction with the FUS solution.
    Follows the proven CMMClient pattern with FUS_ environment variable prefix.

.NOTES
    Module: FUSClient.psm1
    Version: 1.0.0
    Author: FSI Agent Governance Team
    Solution: File Upload Security Configurator (v8)
#>

#region Module Variables

$script:DataverseUrl = $null
$script:AccessToken = $null

#endregion

#region Connection Functions

function Connect-FUSDataverse {
    <#
    .SYNOPSIS
        Establishes connection to Dataverse for FUS operations.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DataverseUrl,

        [Parameter()]
        [string]$AccessToken
    )

    $script:DataverseUrl = $DataverseUrl.TrimEnd('/')

    if ($AccessToken) {
        $script:AccessToken = $AccessToken
    } else {
        # Attempt to get token via Az.Accounts
        try {
            $token = Get-AzAccessToken -ResourceUrl "$script:DataverseUrl" -ErrorAction Stop
            # Az.Accounts 5.0+ returns SecureString for .Token; convert to plain text
            $script:AccessToken = if ($token.Token -is [securestring]) {
                $token.Token | ConvertFrom-SecureString -AsPlainText
            } else {
                $token.Token
            }
            Write-Verbose "Acquired Dataverse token via Az.Accounts"
        } catch {
            Write-Warning "No access token provided and Az.Accounts token acquisition failed. Use Connect-EnvironmentDataverse for authenticated access."
        }
    }

    Write-Verbose "Connected to Dataverse: $script:DataverseUrl"
}

function Get-FUSConnection {
    <#
    .SYNOPSIS
        Returns current Dataverse connection info.
    #>
    [CmdletBinding()]
    param()

    [PSCustomObject]@{
        DataverseUrl = $script:DataverseUrl
        AccessToken  = $script:AccessToken
        IsConnected  = $null -ne $script:DataverseUrl -and $null -ne $script:AccessToken
    }
}

#endregion

#region Environment Variable Functions

function Get-FUSEnvironmentVariable {
    <#
    .SYNOPSIS
        Retrieves FUS environment variable value from Dataverse.

    .PARAMETER Name
        Variable name (without fsi_FUS_ prefix).

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
        $schemaName = "fsi_FUS_$Name"
        $uri = "$script:DataverseUrl/api/data/v9.2/environmentvariabledefinitions?" +
               "`$filter=schemaname eq '$schemaName'&" +
               "`$expand=environmentvariablevalues"

        $headers = @{
            'Authorization'    = "Bearer $script:AccessToken"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }

        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

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

#region Bot Query Functions

function Get-AgentBots {
    <#
    .SYNOPSIS
        Queries Copilot Studio agent (bot) records from a Dataverse environment.

    .DESCRIPTION
        Queries the bot table in a specified environment's Dataverse instance to enumerate
        Copilot Studio agents. By default, returns only active (published) bots.

        The bot table schema includes:
        - botid: Unique identifier for the bot
        - name: Display name of the bot
        - statecode: 0 = Active, 1 = Inactive
        - statuscode: Status reason
        - configuration: JSON blob containing bot configuration including file upload settings
        - publishedon: Last publish timestamp
        - schemaname: Internal schema name

    .PARAMETER DataverseUrl
        The Dataverse URL for the environment to query.

    .PARAMETER AccessToken
        Bearer token for Dataverse authentication.

    .PARAMETER IncludeDrafts
        When specified, includes inactive/draft bots (statecode != 0).
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DataverseUrl,

        [Parameter(Mandatory)]
        [string]$AccessToken,

        [switch]$IncludeDrafts
    )

    try {
        $select = "botid,name,statecode,statuscode,configuration,publishedon,schemaname"
        $baseUrl = $DataverseUrl.TrimEnd('/')

        if ($IncludeDrafts) {
            $uri = "$baseUrl/api/data/v9.2/bots?`$select=$select"
        } else {
            $uri = "$baseUrl/api/data/v9.2/bots?`$select=$select&`$filter=statecode eq 0"
        }

        $headers = @{
            'Authorization'    = "Bearer $AccessToken"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }

        $allBots = @()
        $nextLink = $uri

        while ($nextLink) {
            $response = Invoke-RestMethod -Uri $nextLink -Headers $headers -Method Get -ErrorAction Stop
            $allBots += $response.value
            $nextLink = $response.'@odata.nextLink'
        }

        Write-Verbose "Retrieved $($allBots.Count) bot records from $baseUrl"
        return $allBots
    } catch {
        Write-Warning "Failed to query bots from $DataverseUrl`: $($_.Exception.Message)"
        return @()
    }
}

function Get-BotFileUploadEnabled {
    <#
    .SYNOPSIS
        Extracts the file upload enabled status from a bot record.

    .DESCRIPTION
        Parses the bot.configuration JSON blob to extract the file upload setting.
        The configuration field is a JSON string containing various bot settings.
        File upload settings may appear under several key names depending on
        Copilot Studio version:
        - FileUpload
        - fileUpload
        - FileUploadEnabled
        - AllowFileUpload
        - allowFileUpload

        Normalizes returned values to boolean True/False.
        Returns $null if the setting cannot be determined.

    .PARAMETER Bot
        A bot record PSCustomObject from Get-AgentBots.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Bot
    )

    # Try extracting from bot.configuration JSON blob
    if ($Bot.configuration) {
        try {
            $config = $Bot.configuration | ConvertFrom-Json -ErrorAction Stop

            # Check known key names for file upload settings
            $fileUploadValue = $null
            $keyNames = @(
                'FileUpload', 'fileUpload', 'FileUploadEnabled', 'fileUploadEnabled',
                'AllowFileUpload', 'allowFileUpload', 'AllowFileUploads', 'allowFileUploads',
                'IsFileUploadEnabled', 'isFileUploadEnabled'
            )

            foreach ($key in $keyNames) {
                if ($config.PSObject.Properties.Name -contains $key) {
                    $rawValue = $config.$key

                    # Handle nested object (e.g., { "enabled": true })
                    if ($rawValue -is [PSCustomObject]) {
                        if ($rawValue.PSObject.Properties.Name -contains 'enabled') {
                            $fileUploadValue = $rawValue.enabled
                        } elseif ($rawValue.PSObject.Properties.Name -contains 'isEnabled') {
                            $fileUploadValue = $rawValue.isEnabled
                        }
                    } elseif ($rawValue -is [bool]) {
                        $fileUploadValue = $rawValue
                    } elseif ($rawValue -is [string]) {
                        $normalized = $rawValue.Trim().ToLower()
                        $fileUploadValue = $normalized -in @('true', 'yes', 'enabled', '1', 'on')
                    } elseif ($rawValue -is [int]) {
                        $fileUploadValue = $rawValue -ne 0
                    }
                    break
                }
            }

            if ($null -ne $fileUploadValue) {
                return [bool]$fileUploadValue
            }
        } catch {
            Write-Verbose "Failed to parse configuration JSON for bot '$($Bot.name)': $($_.Exception.Message)"
        }
    }

    Write-Warning "File upload setting could not be determined for bot '$($Bot.name)' — review this agent manually"
    return $null
}

function Get-BotModerationLevel {
    <#
    .SYNOPSIS
        Extracts the content moderation level from a bot record.

    .DESCRIPTION
        Parses the bot.configuration JSON blob to extract the content moderation setting.
        Normalizes returned values to canonical levels: Low, Medium, High, Highest.
        Returns 'Unknown' if the level cannot be determined.

    .PARAMETER Bot
        A bot record PSCustomObject from Get-AgentBots.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Bot
    )

    # Normalization map
    $levelMap = @{
        'low'     = 'Low'
        'medium'  = 'Medium'
        'high'    = 'High'
        'highest' = 'Highest'
        'strict'  = 'Highest'
        'none'    = 'Low'
        'standard' = 'Medium'
    }

    if ($Bot.configuration) {
        try {
            $config = $Bot.configuration | ConvertFrom-Json -ErrorAction Stop

            $moderationValue = $null
            foreach ($key in @('ContentModeration', 'contentModeration', 'ContentModerationSetting', 'contentModerationSetting')) {
                if ($config.PSObject.Properties.Name -contains $key) {
                    $rawValue = $config.$key

                    if ($rawValue -is [PSCustomObject] -and $rawValue.PSObject.Properties.Name -contains 'level') {
                        $moderationValue = $rawValue.level
                    } elseif ($rawValue -is [string]) {
                        $moderationValue = $rawValue
                    }
                    break
                }
            }

            if ($moderationValue) {
                $normalized = $moderationValue.ToLower().Trim()
                if ($levelMap.ContainsKey($normalized)) {
                    return $levelMap[$normalized]
                }
                return $moderationValue
            }
        } catch {
            Write-Verbose "Failed to parse moderation config for bot '$($Bot.name)': $($_.Exception.Message)"
        }
    }

    return 'Unknown'
}

#endregion

#region Baseline Functions

function Get-FileUploadBaseline {
    <#
    .SYNOPSIS
        Retrieves file upload baseline records from Dataverse.

    .PARAMETER EnvironmentId
        Optional environment GUID to filter by.

    .PARAMETER AgentId
        Optional agent ID to filter by.

    .PARAMETER ActiveOnly
        When specified, returns only active baselines.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [string]$EnvironmentId,

        [Parameter()]
        [string]$AgentId,

        [Parameter()]
        [switch]$ActiveOnly
    )

    if (-not $script:DataverseUrl) {
        Write-Warning "Dataverse not connected"
        return $null
    }

    try {
        $filterParts = @()
        if ($ActiveOnly) {
            $filterParts += "statecode eq 0"
        }
        if ($EnvironmentId) {
            $escapedEnvId = $EnvironmentId -replace "'", "''"
            $filterParts += "fsi_environment_id eq '$escapedEnvId'"
        }
        if ($AgentId) {
            $escapedAgentId = $AgentId -replace "'", "''"
            $filterParts += "fsi_agent_id eq '$escapedAgentId'"
        }
        $filter = if ($filterParts.Count -gt 0) { $filterParts -join ' and ' } else { '' }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_fileupload_baselines?" +
               "$(if ($filter) { "`$filter=$filter&" } else { '' })`$orderby=createdon desc"

        $headers = @{
            'Authorization' = "Bearer $script:AccessToken"
            'Accept'        = 'application/json'
        }

        $allRecords = @()
        $nextLink = $uri

        while ($nextLink) {
            $response = Invoke-RestMethod -Uri $nextLink -Headers $headers -Method Get -ErrorAction Stop
            $allRecords += $response.value
            $nextLink = $response.'@odata.nextLink'
        }

        return $allRecords | ForEach-Object {
            [PSCustomObject]@{
                BaselineId          = $_.fsi_fileupload_baselineid
                Name                = $_.fsi_name
                EnvironmentId       = $_.fsi_environment_id
                EnvironmentName     = $_.fsi_environment_name
                Zone                = $_.fsi_zone
                AgentId             = $_.fsi_agent_id
                AgentName           = $_.fsi_agent_name
                FileUploadEnabled   = $_.fsi_file_upload_enabled
                ModerationLevel     = $_.fsi_content_moderation_level
                CapturedBy          = $_.fsi_baseline_captured_by
                CapturedAt          = $_.fsi_baseline_captured_on
            }
        }
    } catch {
        Write-Warning "Failed to get file upload baseline: $($_.Exception.Message)"
        return $null
    }
}

function Save-FUSBaseline {
    <#
    .SYNOPSIS
        Saves a file upload baseline record to Dataverse.
    #>
    [CmdletBinding(SupportsShouldProcess)]
    param(
        [Parameter(Mandatory)]
        [string]$EnvironmentGuid,

        [Parameter(Mandatory)]
        [string]$EnvironmentName,

        [Parameter(Mandatory)]
        [string]$Zone,

        [Parameter(Mandatory)]
        [string]$AgentId,

        [Parameter(Mandatory)]
        [string]$AgentName,

        [Parameter(Mandatory)]
        [bool]$FileUploadEnabled,

        [Parameter()]
        [string]$ModerationLevel = 'Unknown',

        [string]$CapturedBy,

        [string]$RawJson
    )

    if (-not $script:DataverseUrl) {
        Write-Warning "Dataverse not connected, skipping baseline save"
        return $null
    }

    try {
        $headers = @{
            'Authorization'    = "Bearer $script:AccessToken"
            'Content-Type'     = 'application/json'
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }

        # Deactivate existing active baseline for this agent
        $escapedAgentId = $AgentId -replace "'", "''"
        $deactivateFilter = "fsi_agent_id eq '$escapedAgentId'"
        $queryUri = "$script:DataverseUrl/api/data/v9.2/fsi_fileupload_baselines?`$filter=$deactivateFilter&`$select=fsi_fileupload_baselineid"

        $existing = Invoke-RestMethod -Uri $queryUri -Headers $headers -Method Get

        foreach ($prev in $existing.value) {
            $prevId = $prev.fsi_fileupload_baselineid
            if ($PSCmdlet.ShouldProcess("Baseline $prevId for $AgentName", "Deactivate previous active baseline")) {
                $patchUri = "$script:DataverseUrl/api/data/v9.2/fsi_fileupload_baselines($prevId)"
                $patchBody = @{ statecode = 1 } | ConvertTo-Json
                Invoke-RestMethod -Uri $patchUri -Headers $headers -Method Patch -Body $patchBody | Out-Null
                Write-Verbose "Deactivated previous baseline: $prevId"
            }
        }

        # Create new active baseline
        $timestamp = (Get-Date).ToUniversalTime().ToString('o')
        $capturedByValue = if ($CapturedBy) { $CapturedBy } else { "System" }
        $rawJsonValue = if ($RawJson) { $RawJson } else { "" }

        $record = @{
            fsi_name                       = "$AgentName-$Zone-$timestamp"
            fsi_environment_id             = $EnvironmentGuid
            fsi_environment_name           = $EnvironmentName
            fsi_zone                       = switch ($Zone) {
                'Zone 1' { 1 }
                'Zone 2' { 2 }
                'Zone 3' { 3 }
                default  { $null }
            }
            fsi_agent_id                   = $AgentId
            fsi_agent_name                 = $AgentName
            fsi_file_upload_enabled        = $FileUploadEnabled
            fsi_content_moderation_level   = $ModerationLevel
            fsi_baseline_captured_by       = $capturedByValue
            fsi_baseline_captured_on       = $timestamp
        }

        if ($PSCmdlet.ShouldProcess("$AgentName in $EnvironmentName ($Zone)", "Save file upload baseline")) {
            $uri = "$script:DataverseUrl/api/data/v9.2/fsi_fileupload_baselines"
            $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body ($record | ConvertTo-Json)
            Write-Verbose "Baseline saved for $AgentName in $EnvironmentName ($Zone)"
            return $response
        }
    } catch {
        Write-Warning "Failed to save baseline for '$AgentName': $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region Validation History Functions

function Write-FileUploadValidationHistory {
    <#
    .SYNOPSIS
        Writes immutable validation record to Dataverse.
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
            fsi_name                       = "$($ValidationResult.OverallStatus)-$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')"
            fsi_run_id                     = $RunId
            fsi_run_timestamp              = (Get-Date).ToUniversalTime().ToString('o')
            fsi_total_agents               = $ValidationResult.TotalAgents
            fsi_compliant_count            = $ValidationResult.CompliantCount
            fsi_violation_count            = $ValidationResult.ViolationCount
            fsi_file_upload_enabled_count  = $ValidationResult.FileUploadEnabledCount
            fsi_compliance_rate             = $ValidationResult.ComplianceRate
            fsi_environments_scanned       = $ValidationResult.EnvironmentsScanned
            fsi_scan_duration_seconds      = $ValidationResult.ScanDurationSeconds
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_fileupload_validationhistorys"

        $headers = @{
            'Authorization' = "Bearer $script:AccessToken"
            'Content-Type'  = 'application/json'
            'Accept'        = 'application/json'
        }

        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body ($record | ConvertTo-Json)
        Write-Verbose "Validation history record created"
        return $response
    } catch {
        Write-Warning "Failed to write validation history: $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region Violation Functions

function Write-FileUploadViolation {
    <#
    .SYNOPSIS
        Writes file upload violation record to Dataverse.
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
        $record = @{
            fsi_name                    = "$($Violation.AgentName)-$($Violation.Zone)-$(Get-Date -Format 'yyyy-MM-dd')"
            fsi_environment_id          = $Violation.EnvironmentId
            fsi_environment_name        = $Violation.EnvironmentDisplayName
            fsi_agent_id                = $Violation.AgentId
            fsi_agent_name              = $Violation.AgentName
            fsi_zone                    = switch ($Violation.Zone) {
                'Zone 1' { 1 }
                'Zone 2' { 2 }
                'Zone 3' { 3 }
                default  { $null }
            }
            fsi_file_upload_expected    = $(switch ($Violation.ExpectedFileUpload) {
                'Allowed' { $true }
                'Disabled' { $false }
                'Review Required' { $false }
                default { [bool]$Violation.ExpectedFileUpload }
            })
            fsi_file_upload_actual      = $Violation.ActualFileUpload
            fsi_content_moderation_minimum = $Violation.ExpectedModeration
            fsi_content_moderation_level = $Violation.ActualModeration
            fsi_severity                = switch ($Violation.Severity) {
                'Info'     { 0 }
                'Low'      { 1 }
                'Medium'   { 2 }
                'High'     { 3 }
                'Critical' { 4 }
                default    { $null }
            }
            fsi_violation_type          = $Violation.ViolationType
            fsi_remediation_notes      = $Violation.RegulatoryContext
            fsi_detected_on             = (Get-Date).ToUniversalTime().ToString('o')
        }

        if ($RunId) {
            $record['fsi_run_id'] = $RunId
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_fileupload_violations"

        $headers = @{
            'Authorization' = "Bearer $script:AccessToken"
            'Content-Type'  = 'application/json'
            'Accept'        = 'application/json'
        }

        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Post -Body ($record | ConvertTo-Json)
        Write-Verbose "Violation record created for $($Violation.AgentName)"
        return $response
    } catch {
        Write-Warning "Failed to write violation: $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region Validation Query Functions

function Get-FUSLastValidation {
    <#
    .SYNOPSIS
        Retrieves recent validation history records from Dataverse.
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
        $select = "fsi_name,fsi_run_id,fsi_violation_count,fsi_total_agents,fsi_file_upload_enabled_count,fsi_run_timestamp"
        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_fileupload_validationhistorys?" +
               "`$orderby=fsi_run_timestamp desc&`$top=$Top&`$select=$select"

        $headers = @{
            'Authorization'    = "Bearer $script:AccessToken"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }

        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get

        if ($response.value.Count -gt 0) {
            return $response.value | ForEach-Object {
                [PSCustomObject]@{
                    Name                   = $_.fsi_name
                    RunId                  = $_.fsi_run_id
                    ViolationCount         = $_.fsi_violation_count
                    TotalAgents            = $_.fsi_total_agents
                    FileUploadEnabledCount = $_.fsi_file_upload_enabled_count
                    Timestamp              = $_.fsi_run_timestamp
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
    'Connect-FUSDataverse',
    'Get-FUSConnection',
    'Get-FUSEnvironmentVariable',
    'Get-AgentBots',
    'Get-BotFileUploadEnabled',
    'Get-BotModerationLevel',
    'Get-FileUploadBaseline',
    'Save-FUSBaseline',
    'Write-FileUploadValidationHistory',
    'Write-FileUploadViolation',
    'Get-FUSLastValidation'
)
