<#
.SYNOPSIS
    File Upload Security Dataverse client module.

.DESCRIPTION
    Provides helper functions for Dataverse interaction with the FUS solution.
    Follows the proven CMMClient pattern with FUS_ environment variable prefix.

.NOTES
    Module: FUSClient.psm1
    Version: 1.1.2
    Author: FSI Agent Governance Team
    Solution: File Upload Security Configurator (v8)
#>

#region Module Variables

$script:DataverseUrl = $null
$script:AccessToken = $null

#endregion

#region Retry Helper

function Invoke-DataverseRequest {
    <#
    .SYNOPSIS
        Wrapper around Invoke-RestMethod with retry/backoff for transient errors.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$Uri,

        [Parameter(Mandatory)]
        [hashtable]$Headers,

        [Parameter()]
        [string]$Method = 'Get',

        [Parameter()]
        [string]$Body,

        [int]$MaxRetries = 3,

        [int]$BaseDelaySeconds = 2
    )

    for ($attempt = 0; $attempt -le $MaxRetries; $attempt++) {
        try {
            $params = @{ Uri = $Uri; Headers = $Headers; Method = $Method; ErrorAction = 'Stop' }
            if ($Body) { $params['Body'] = $Body }
            return Invoke-RestMethod @params
        } catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            if ($statusCode -in @(429, 500, 502, 503, 504) -and $attempt -lt $MaxRetries) {
                $delay = $BaseDelaySeconds * [math]::Pow(2, $attempt)
                Write-Verbose "Transient error ($statusCode) on attempt $($attempt+1). Retrying in ${delay}s..."
                Start-Sleep -Seconds $delay
            } else {
                throw
            }
        }
    }
}

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
        # Canonical one-to-many navigation property is environmentvariabledefinition_environmentvariablevalue;
        # 'environmentvariablevalues' is not a valid navigation property and fails $expand.
        $uri = "$script:DataverseUrl/api/data/v9.2/environmentvariabledefinitions?" +
               "`$filter=schemaname eq '$schemaName'&" +
               "`$expand=environmentvariabledefinition_environmentvariablevalue(`$select=value)"

        $headers = @{
            'Authorization'    = "Bearer $script:AccessToken"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }

        $response = Invoke-DataverseRequest -Uri $uri -Headers $headers -Method Get

        if ($response.value.Count -gt 0) {
            $varDef = $response.value[0]
            $envValues = $varDef.environmentvariabledefinition_environmentvariablevalue
            if ($envValues -and $envValues.Count -gt 0) {
                return $envValues[0].value
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
            $response = Invoke-DataverseRequest -Uri $nextLink -Headers $headers -Method Get
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

function ConvertTo-FileUploadBool {
    <#
    .SYNOPSIS
        Normalizes a raw configuration value to boolean True/False.

    .DESCRIPTION
        Coerces the supported representations of a file-upload flag
        (bool, string, numeric, or nested { enabled } / { isEnabled } object)
        into a boolean. Returns $null when the value cannot be normalized so
        callers can treat it as indeterminate rather than as disabled.
    #>
    [CmdletBinding()]
    param(
        [Parameter()]
        [AllowNull()]
        [object]$RawValue
    )

    if ($null -eq $RawValue) { return $null }

    if ($RawValue -is [PSCustomObject]) {
        if ($RawValue.PSObject.Properties.Name -contains 'enabled') {
            return [bool]$RawValue.enabled
        }
        if ($RawValue.PSObject.Properties.Name -contains 'isEnabled') {
            return [bool]$RawValue.isEnabled
        }
        return $null
    }

    if ($RawValue -is [bool]) { return $RawValue }

    if ($RawValue -is [string]) {
        $normalized = $RawValue.Trim().ToLower()
        if ([string]::IsNullOrWhiteSpace($normalized)) { return $null }
        return ($normalized -in @('true', 'yes', 'enabled', '1', 'on'))
    }

    if ($RawValue -is [int] -or $RawValue -is [long] -or $RawValue -is [double]) {
        return $RawValue -ne 0
    }

    return $null
}

function Get-BotFileUploadEnabled {
    <#
    .SYNOPSIS
        Extracts the file upload enabled status from a bot record.

    .DESCRIPTION
        Parses the bot.configuration JSON blob to extract the file upload setting.
        The configuration field is a JSON string containing the agent's settings.

        PRIMARY (live Copilot Studio schema, verified on the lab validation tenant): the flag lives
        nested at 'aISettings.isFileAnalysisEnabled' (boolean). The parser reads
        that first.

        FALLBACK (legacy / fixture schemas): older or synthetic configurations may
        carry a flat top-level key (FileUpload, AllowFileUpload, etc.). These are
        evaluated only when the nested flag is absent.

        Normalizes returned values to boolean True/False. Returns $null when the
        setting cannot be determined so the caller can treat it as INDETERMINATE.
        A missing setting is never collapsed into 'disabled' / 'compliant'.

    .PARAMETER Bot
        A bot record PSCustomObject from Get-AgentBots.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Bot
    )

    if (-not $Bot.configuration) {
        Write-Verbose "Bot '$($Bot.name)' has no configuration -- treating as indeterminate"
        return $null
    }

    try {
        $config = $Bot.configuration | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Verbose "Failed to parse configuration JSON for bot '$($Bot.name)': $($_.Exception.Message) -- treating as indeterminate"
        return $null
    }

    $rawValue = $null
    $found = $false

    # PRIMARY: nested aISettings.isFileAnalysisEnabled (live Copilot Studio shape).
    if (($config.PSObject.Properties.Name -contains 'aISettings') -and ($null -ne $config.aISettings)) {
        $aiSettings = $config.aISettings
        if ($aiSettings.PSObject.Properties.Name -contains 'isFileAnalysisEnabled') {
            $rawValue = $aiSettings.isFileAnalysisEnabled
            $found = $true
        }
    }

    # FALLBACK: legacy / fixture flat top-level keys (only if the nested flag is absent).
    if (-not $found) {
        $legacyKeys = @(
            'FileUpload', 'fileUpload', 'FileUploadEnabled', 'fileUploadEnabled',
            'AllowFileUpload', 'allowFileUpload', 'AllowFileUploads', 'allowFileUploads',
            'IsFileUploadEnabled', 'isFileUploadEnabled'
        )
        foreach ($key in $legacyKeys) {
            if ($config.PSObject.Properties.Name -contains $key) {
                $rawValue = $config.$key
                $found = $true
                break
            }
        }
    }

    if (-not $found) {
        Write-Verbose "File upload setting (aISettings.isFileAnalysisEnabled or legacy key) not found for bot '$($Bot.name)' -- treating as indeterminate"
        return $null
    }

    $fileUploadValue = ConvertTo-FileUploadBool -RawValue $rawValue
    if ($null -ne $fileUploadValue) {
        return [bool]$fileUploadValue
    }

    Write-Verbose "File upload value for bot '$($Bot.name)' could not be normalized -- treating as indeterminate"
    return $null  # Caller must handle $null as indeterminate, not as disabled
}

function Get-BotModerationLevel {
    <#
    .SYNOPSIS
        Extracts the content moderation level from a bot record.

    .DESCRIPTION
        Parses the bot.configuration JSON blob to extract the content moderation setting.

        PRIMARY (live Copilot Studio schema, verified on the lab validation tenant): the setting lives
        nested at 'aISettings.contentModeration'. The parser reads that first.

        FALLBACK (legacy / fixture schemas): older or synthetic configurations may
        carry a flat top-level key (ContentModeration, etc.), evaluated only when the
        nested setting is absent.

        Normalizes returned values to canonical levels: Low, Medium, High, Highest.
        Returns 'Unknown' when the level cannot be determined. A missing setting is
        never collapsed into a concrete level.

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

    if (-not $Bot.configuration) { return 'Unknown' }

    try {
        $config = $Bot.configuration | ConvertFrom-Json -ErrorAction Stop
    } catch {
        Write-Verbose "Failed to parse moderation config for bot '$($Bot.name)': $($_.Exception.Message)"
        return 'Unknown'
    }

    $moderationValue = $null

    # PRIMARY: nested aISettings.contentModeration (live Copilot Studio shape).
    if (($config.PSObject.Properties.Name -contains 'aISettings') -and ($null -ne $config.aISettings)) {
        $aiSettings = $config.aISettings
        if ($aiSettings.PSObject.Properties.Name -contains 'contentModeration') {
            $rawValue = $aiSettings.contentModeration
            if ($rawValue -is [PSCustomObject] -and $rawValue.PSObject.Properties.Name -contains 'level') {
                $moderationValue = $rawValue.level
            } elseif ($rawValue -is [string]) {
                $moderationValue = $rawValue
            }
        }
    }

    # FALLBACK: legacy / fixture flat top-level keys (only if the nested setting is absent).
    if (-not $moderationValue) {
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
    }

    if ($moderationValue) {
        $normalized = $moderationValue.ToLower().Trim()
        if ([string]::IsNullOrWhiteSpace($normalized)) { return 'Unknown' }
        if ($levelMap.ContainsKey($normalized)) {
            return $levelMap[$normalized]
        }
        return $moderationValue
    }

    return 'Unknown'
}

#endregion

#region Option Set Mapping Helpers

function ConvertTo-ZoneOptionValue {
    <#
    .SYNOPSIS
        Converts a zone string label to its fsi_acv_zone option set integer value.

    .DESCRIPTION
        Maps to the LIVE shared fsi_acv_zone 4-member set verified on the lab validation tenant:
          Unclassified = 100000000
          Zone 1       = 100000001
          Zone 2       = 100000002
          Zone 3       = 100000003
        Accepts both spaced ('Zone 1') and unspaced ('Zone1') labels, and treats
        'Unclassified' / 'Unknown' as the Unclassified member. Returns $null for
        anything that cannot be mapped so callers omit the picklist rather than
        writing a wrong integer.

        Canonical zone semantics (reconciled per coordinator decision
        Option A): Zone 1 (Enterprise) is the MOST-restrictive tier and
        Zone 3 (Personal) the least. FUS's policy table, naming classifier,
        and violation text are all aligned to this meaning, so the name-derived
        zone (Zone1..Zone3) maps straight to its canonical integer.
    #>
    param([string]$Zone)
    switch -Regex ($Zone) {
        '3' { return 100000003 }
        '2' { return 100000002 }
        '1' { return 100000001 }
        '(?i)^\s*(unclassified|unknown)\s*$' { return 100000000 }
        default {
            Write-Warning "Unknown zone '$Zone' -- cannot map to option set value"
            return $null
        }
    }
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
        $filter = "statecode eq 0"
        if ($EnvironmentId) {
            $safeEnvId = $EnvironmentId -replace "'", "''"
            $filter += " and fsi_environmentid eq '$safeEnvId'"
        }
        if ($AgentId) {
            $safeAgentId = $AgentId -replace "'", "''"
            $filter += " and fsi_agentid eq '$safeAgentId'"
        }
        if ($ActiveOnly) {
            # Active records already filtered by statecode eq 0 above
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_fileuploadbaselines?" +
               "`$filter=$filter&`$orderby=createdon desc"

        $headers = @{
            'Authorization' = "Bearer $script:AccessToken"
            'Accept'        = 'application/json'
        }

        $allRecords = @()
        $nextLink = $uri

        while ($nextLink) {
            $response = Invoke-DataverseRequest -Uri $nextLink -Headers $headers -Method Get
            $allRecords += $response.value
            $nextLink = $response.'@odata.nextLink'
        }

        return $allRecords | ForEach-Object {
            [PSCustomObject]@{
                BaselineId          = $_.fsi_fileuploadbaselineid
                Name                = $_.fsi_name
                EnvironmentGuid     = $_.fsi_environmentid
                EnvironmentName     = $_.fsi_environmentname
                Zone                = $_.fsi_zone
                AgentId             = $_.fsi_agentid
                AgentName           = $_.fsi_agentname
                FileUploadEnabled   = $_.fsi_fileuploadenabled
                ModerationLevel     = $_.fsi_contentmoderationlevel
                CapturedBy          = $_.fsi_baselinecapturedby
                CapturedAt          = $_.fsi_baselinecapturedon
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
    [Diagnostics.CodeAnalysis.SuppressMessageAttribute(
        'PSReviewUnusedParameter', 'RawJson',
        Justification = 'Parameter is retained for backward-compatible callers; the current Dataverse baseline schema does not persist raw JSON.'
    )]
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
        $deactivateFilter = "statecode eq 0 and fsi_agentid eq '$($AgentId -replace "'", "''")'"
        $queryUri = "$script:DataverseUrl/api/data/v9.2/fsi_fileuploadbaselines?`$filter=$deactivateFilter&`$select=fsi_fileuploadbaselineid"

        $existing = Invoke-DataverseRequest -Uri $queryUri -Headers $headers -Method Get

        foreach ($prev in $existing.value) {
            $prevId = $prev.fsi_fileuploadbaselineid
            if ($PSCmdlet.ShouldProcess("Baseline $prevId for $AgentName", "Deactivate previous active baseline")) {
                $patchUri = "$script:DataverseUrl/api/data/v9.2/fsi_fileuploadbaselines($prevId)"
                # Dataverse rejects partial state transitions -- must include statuscode paired with statecode
                $patchBody = @{ statecode = 1; statuscode = 2 } | ConvertTo-Json
                Invoke-DataverseRequest -Uri $patchUri -Headers $headers -Method Patch -Body $patchBody | Out-Null
                Write-Verbose "Deactivated previous baseline: $prevId"
            }
        }

        # Create new active baseline
        $timestamp = (Get-Date).ToUniversalTime().ToString('o')
        $capturedByValue = if ($CapturedBy) { $CapturedBy } else { "System" }

        $record = @{
            fsi_name                  = "$AgentName-$Zone-$timestamp"
            fsi_environmentid         = $EnvironmentGuid
            fsi_environmentname       = $EnvironmentName
            fsi_zone                  = (ConvertTo-ZoneOptionValue -Zone $Zone)
            fsi_agentid               = $AgentId
            fsi_agentname             = $AgentName
            fsi_fileuploadenabled     = $FileUploadEnabled
            fsi_contentmoderationlevel = $ModerationLevel
            fsi_baselinecapturedby    = $capturedByValue
            fsi_baselinecapturedon    = $timestamp
        }

        if ($PSCmdlet.ShouldProcess("$AgentName in $EnvironmentName ($Zone)", "Save file upload baseline")) {
            $uri = "$script:DataverseUrl/api/data/v9.2/fsi_fileuploadbaselines"
            $response = Invoke-DataverseRequest -Uri $uri -Headers $headers -Method Post -Body ($record | ConvertTo-Json)
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
            fsi_name                   = "$($ValidationResult.OverallStatus)-$(Get-Date -Format 'yyyy-MM-ddTHH:mm:ssZ')"
            fsi_runid                  = $RunId
            fsi_validationtime         = (Get-Date).ToUniversalTime().ToString('o')
            fsi_totalagents            = $ValidationResult.TotalAgents
            fsi_compliantcount         = $ValidationResult.CompliantCount
            fsi_violationcount         = $ValidationResult.ViolationCount
            fsi_fileuploadenabledcount = $ValidationResult.FileUploadEnabledCount
            fsi_overallstatus          = $ValidationResult.OverallStatus
            fsi_environmentsscanned    = $ValidationResult.EnvironmentsScanned
            fsi_runtimestamp            = (Get-Date).ToUniversalTime().ToString('o')
            fsi_compliancerate         = [math]::Round(($ValidationResult.CompliantCount / [math]::Max($ValidationResult.TotalAgents, 1)) * 100, 2)
            fsi_summaryjson            = ($ValidationResult | ConvertTo-Json -Depth 10 -Compress)
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_fileuploadvalidationhistories"

        $headers = @{
            'Authorization' = "Bearer $script:AccessToken"
            'Content-Type'  = 'application/json'
            'Accept'        = 'application/json'
        }

        $response = Invoke-DataverseRequest -Uri $uri -Headers $headers -Method Post -Body ($record | ConvertTo-Json)
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
            fsi_environmentid           = $Violation.EnvironmentId
            fsi_environmentname         = $Violation.EnvironmentDisplayName
            fsi_agentid                 = $Violation.AgentId
            fsi_agentname               = $Violation.AgentName
            fsi_zone                    = (ConvertTo-ZoneOptionValue -Zone $Violation.Zone)
            fsi_fileuploadexpected      = $Violation.ExpectedFileUpload
            fsi_fileuploadactual        = $Violation.ActualFileUpload
            fsi_contentmoderationminimum = $Violation.ExpectedModeration
            fsi_contentmoderationlevel  = $Violation.ActualModeration
            fsi_severity                = $Violation.Severity
            fsi_violationtype           = $Violation.ViolationType
            fsi_detectedon              = (Get-Date).ToUniversalTime().ToString('o')
        }

        if ($RunId) {
            $record['fsi_runid'] = $RunId
        }

        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_fileuploadviolations"

        $headers = @{
            'Authorization' = "Bearer $script:AccessToken"
            'Content-Type'  = 'application/json'
            'Accept'        = 'application/json'
        }

        $response = Invoke-DataverseRequest -Uri $uri -Headers $headers -Method Post -Body ($record | ConvertTo-Json)
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
        $select = "fsi_name,fsi_runid,fsi_overallstatus,fsi_violationcount,fsi_totalagents,fsi_fileuploadenabledcount,fsi_summaryjson,fsi_validationtime"
        $uri = "$script:DataverseUrl/api/data/v9.2/fsi_fileuploadvalidationhistories?" +
               "`$orderby=fsi_validationtime desc&`$top=$Top&`$select=$select"

        $headers = @{
            'Authorization'    = "Bearer $script:AccessToken"
            'Accept'           = 'application/json'
            'OData-MaxVersion' = '4.0'
            'OData-Version'    = '4.0'
        }

        $response = Invoke-DataverseRequest -Uri $uri -Headers $headers -Method Get

        if ($response.value.Count -gt 0) {
            return $response.value | ForEach-Object {
                [PSCustomObject]@{
                    Name                   = $_.fsi_name
                    RunId                  = $_.fsi_runid
                    OverallStatus          = $_.fsi_overallstatus
                    ViolationCount         = $_.fsi_violationcount
                    TotalAgents            = $_.fsi_totalagents
                    FileUploadEnabledCount = $_.fsi_fileuploadenabledcount
                    SummaryJson            = $_.fsi_summaryjson
                    Timestamp              = $_.fsi_validationtime
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
    'Get-FUSLastValidation',
    'Invoke-DataverseRequest'
)
