<#
.SYNOPSIS
    Content Moderation Monitor Dataverse client module.

.DESCRIPTION
    Provides helper functions for Dataverse interaction with the CMM solution.
    Follows the proven AAMClient pattern with CMM_ environment variable prefix.

.NOTES
    Module: CMMClient.psm1
    Version: 0.2.0
    Author: FSI Agent Governance Team
#>

#region Module Variables

$script:DataverseUrl = $null
$script:AccessToken = $null

#endregion

#region Connection Functions

function Connect-CMMDataverse {
    <#
    .SYNOPSIS
        Establishes connection to Dataverse for CMM operations.
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
            $script:AccessToken = $token.Token
            Write-Verbose "Acquired Dataverse token via Az.Accounts"
        } catch {
            Write-Warning "No access token provided and Az.Accounts token acquisition failed. Use Connect-EnvironmentDataverse for authenticated access."
        }
    }

    Write-Verbose "Connected to Dataverse: $script:DataverseUrl"
}

function Get-CMMConnection {
    <#
    .SYNOPSIS
        Returns current Dataverse connection info.
    #>
    [CmdletBinding()]
    param()

    [PSCustomObject]@{
        DataverseUrl = $script:DataverseUrl
        IsConnected  = $null -ne $script:DataverseUrl -and $null -ne $script:AccessToken
    }
}

#endregion

#region Environment Variable Functions

function Get-CMMEnvironmentVariable {
    <#
    .SYNOPSIS
        Retrieves CMM environment variable value from Dataverse.

    .PARAMETER Name
        Variable name (without fsi_CMM_ prefix).

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
        $schemaName = "fsi_CMM_$Name"
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

#region Baseline Functions

function Get-ModerationBaseline {
    <#
    .SYNOPSIS
        Retrieves moderation baseline records from Dataverse.

    .PARAMETER EnvironmentId
        Optional environment GUID to filter by.
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
        $filter = "statecode eq 0"
        if ($EnvironmentId) {
            $filter += " and fsi_environment_guid eq '$EnvironmentId'"
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_moderationbaselines?" +
               "`$filter=$filter&`$orderby=createdon desc"

        $headers = @{
            'Authorization' = "Bearer $script:AccessToken"
            'Accept'        = 'application/json'
        }

        $response = Invoke-RestMethod -Uri $uri -Headers $headers -Method Get
        return $response.value
    } catch {
        Write-Warning "Failed to get moderation baseline: $($_.Exception.Message)"
        return $null
    }
}

#endregion

#region Validation History Functions

function Write-ModerationValidationHistory {
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

    if (-not $script:DataverseUrl) {
        Write-Warning "Dataverse not connected, skipping validation history write"
        return $null
    }

    try {
        $record = @{
            fsi_name               = "$($ValidationResult.OverallStatus)-$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')"
            fsi_run_id             = $RunId
            fsi_validation_time    = (Get-Date).ToUniversalTime().ToString('o')
            fsi_total_agents       = $ValidationResult.TotalAgents
            fsi_compliant_count    = $ValidationResult.CompliantCount
            fsi_violation_count    = $ValidationResult.ViolationCount
            fsi_overall_status     = $ValidationResult.OverallStatus
            fsi_environments_scanned = $ValidationResult.EnvironmentsScanned
            fsi_summary_json       = ($ValidationResult | ConvertTo-Json -Depth 10 -Compress)
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_moderationvalidationhistory"

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

function Write-ModerationViolation {
    <#
    .SYNOPSIS
        Writes moderation violation record to Dataverse.

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
        $record = @{
            fsi_name                = "$($Violation.AgentName)-$($Violation.Zone)-$(Get-Date -Format 'yyyy-MM-dd')"
            fsi_environment_guid    = $Violation.EnvironmentId
            fsi_environment_name    = $Violation.EnvironmentDisplayName
            fsi_agent_id            = $Violation.AgentId
            fsi_agent_name          = $Violation.AgentName
            fsi_zone                = $Violation.Zone
            fsi_expected_level      = $Violation.ExpectedLevel
            fsi_actual_level        = $Violation.ActualLevel
            fsi_severity            = $Violation.Severity
            fsi_regulatory_context  = $Violation.RegulatoryContext
            fsi_detected_at         = (Get-Date).ToUniversalTime().ToString('o')
        }

        if ($RunId) {
            $record['fsi_run_id'] = $RunId
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_moderationviolations"

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
        - configuration: JSON blob containing bot configuration including content moderation
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

function Get-BotModerationLevel {
    <#
    .SYNOPSIS
        Extracts the content moderation level from a bot record.

    .DESCRIPTION
        Parses the bot.configuration JSON blob to extract the content moderation setting.
        The configuration field is a JSON string containing various bot settings. Content
        moderation may appear under several key names depending on Copilot Studio version:
        - ContentModeration
        - contentModeration
        - ContentModerationSetting

        If the configuration blob does not contain moderation info, checks botcomponent
        records for moderation configuration.

        Normalizes returned values to canonical levels: Low, Medium, High.
        Returns 'Unknown' if the level cannot be determined.

    .PARAMETER Bot
        A bot record PSCustomObject from Get-AgentBots.

    .PARAMETER Components
        Optional array of botcomponent records for fallback lookup.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Bot,

        [Parameter()]
        [PSCustomObject[]]$Components
    )

    # Normalization map for various moderation level names
    $levelMap = @{
        'low'      = 'Low'
        'medium'   = 'Medium'
        'high'     = 'High'
        'strict'   = 'High'
        'none'     = 'Low'
        'standard' = 'Medium'
    }

    # Try extracting from bot.configuration JSON blob
    if ($Bot.configuration) {
        try {
            $config = $Bot.configuration | ConvertFrom-Json -ErrorAction Stop

            # Check known key names for content moderation
            $moderationValue = $null
            foreach ($key in @('ContentModeration', 'contentModeration', 'ContentModerationSetting', 'contentModerationSetting')) {
                if ($config.PSObject.Properties.Name -contains $key) {
                    $rawValue = $config.$key

                    # Handle nested object (e.g., { "level": "High" })
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
                Write-Verbose "Unrecognized moderation value '$moderationValue' for bot '$($Bot.name)', returning as-is"
                return $moderationValue
            }
        } catch {
            Write-Verbose "Failed to parse configuration JSON for bot '$($Bot.name)': $($_.Exception.Message)"
        }
    }

    # Fallback: check botcomponent records
    if ($Components) {
        foreach ($component in $Components) {
            if ($component.content) {
                try {
                    $componentConfig = $component.content | ConvertFrom-Json -ErrorAction Stop

                    foreach ($key in @('ContentModeration', 'contentModeration', 'ContentModerationSetting')) {
                        if ($componentConfig.PSObject.Properties.Name -contains $key) {
                            $rawValue = $componentConfig.$key
                            if ($rawValue -is [PSCustomObject] -and $rawValue.PSObject.Properties.Name -contains 'level') {
                                $rawValue = $rawValue.level
                            }
                            if ($rawValue -is [string]) {
                                $normalized = $rawValue.ToLower().Trim()
                                if ($levelMap.ContainsKey($normalized)) {
                                    return $levelMap[$normalized]
                                }
                                return $rawValue
                            }
                        }
                    }
                } catch {
                    Write-Verbose "Failed to parse component content for bot '$($Bot.name)'"
                }
            }
        }
    }

    Write-Verbose "Content moderation level not found for bot '$($Bot.name)'"
    return 'Unknown'
}

#endregion

#region Baseline Write Functions

function Save-CMMBaseline {
    <#
    .SYNOPSIS
        Saves a moderation baseline record to Dataverse.

    .DESCRIPTION
        Captures current agent moderation settings as a baseline. Used in Phase 3
        for drift detection support.
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
        [string]$ModerationLevel,

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

        $timestamp = (Get-Date).ToUniversalTime().ToString('o')
        $capturedByValue = if ($CapturedBy) { $CapturedBy } else { "System" }
        $rawJsonValue = if ($RawJson) { $RawJson } else { "" }

        $record = @{
            fsi_name               = "$AgentName-$Zone-$timestamp"
            fsi_environment_guid   = $EnvironmentGuid
            fsi_environment_name   = $EnvironmentName
            fsi_zone               = $Zone
            fsi_agent_id           = $AgentId
            fsi_agent_name         = $AgentName
            fsi_moderation_level   = $ModerationLevel
            fsi_captured_by        = $capturedByValue
            fsi_captured_at        = $timestamp
            fsi_is_active          = $true
            fsi_raw_json           = $rawJsonValue
        }

        if ($PSCmdlet.ShouldProcess("$AgentName in $EnvironmentName ($Zone)", "Save moderation baseline")) {
            $uri = "$script:DataverseUrl/api/data/v9.2/fsi_moderationbaselines"
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

#region Validation Query Functions

function Get-CMMLastValidation {
    <#
    .SYNOPSIS
        Retrieves recent validation history records from Dataverse.

    .DESCRIPTION
        Queries the fsi_moderationvalidationhistory table ordered by timestamp descending.
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
        $select = "fsi_name,fsi_run_id,fsi_overall_status,fsi_violation_count,fsi_total_agents,fsi_summary_json,fsi_validation_time"
        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_moderationvalidationhistory?" +
               "`$orderby=fsi_validation_time desc&`$top=$Top&`$select=$select"

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
                    Name           = $_.fsi_name
                    RunId          = $_.fsi_run_id
                    OverallStatus  = $_.fsi_overall_status
                    ViolationCount = $_.fsi_violation_count
                    TotalAgents    = $_.fsi_total_agents
                    SummaryJson    = $_.fsi_summary_json
                    Timestamp      = $_.fsi_validation_time
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
    'Connect-CMMDataverse',
    'Get-CMMConnection',
    'Get-CMMEnvironmentVariable',
    'Get-ModerationBaseline',
    'Write-ModerationValidationHistory',
    'Write-ModerationViolation',
    'Get-AgentBots',
    'Get-BotModerationLevel',
    'Save-CMMBaseline',
    'Get-CMMLastValidation'
)
